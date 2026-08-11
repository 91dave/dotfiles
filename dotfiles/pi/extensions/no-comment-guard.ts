/**
 * No-Comment Guard Extension
 *
 * Blocks write/edit calls that add Claude/agent-authored code comments, reusing
 * the shared Python guard (docs-claude-helpers/hooks/no-comment-guard.py) that
 * also backs the Claude PreToolUse hook. This extension is a thin adapter: it
 * translates pi's tool_call event into the Claude hook payload the script
 * expects, then blocks when the script returns a deny decision.
 *
 * Fails open: any error (missing python3, missing script, bad output) allows
 * the call, matching the Python script's own behaviour.
 */

import { spawn } from "node:child_process";
import { existsSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { isToolCallEventType } from "@earendil-works/pi-coding-agent";

const GUARD_ARGS = ["--allow-single-line", "--no-azdo-refs"];

/**
 * Resolve the guard script relative to ~/.claude rather than a hardcoded repo
 * path, so it survives the docs-claude-helpers repo being moved. ~/.claude/include
 * and ~/.claude/rules symlink into that repo's root; resolve one and hop to the
 * sibling hooks/ dir. Returns undefined if nothing resolves (fail open).
 */
function resolveGuardScript(): string | undefined {
	for (const anchor of ["include", "rules"]) {
		try {
			const repoRoot = dirname(realpathSync(join(homedir(), ".claude", anchor)));
			const script = join(repoRoot, "hooks", "no-comment-guard.py");
			if (existsSync(script)) return script;
		} catch {
			// try next anchor
		}
	}
	return undefined;
}

const GUARD_SCRIPT = resolveGuardScript();

type ClaudePayload = {
	tool_name: string;
	tool_input: Record<string, unknown>;
};

function runGuard(script: string, payload: ClaudePayload): Promise<string | null> {
	return new Promise((resolve) => {
		let stdout = "";
		const child = spawn("python3", [script, ...GUARD_ARGS], {
			stdio: ["pipe", "pipe", "ignore"],
		});
		child.on("error", () => resolve(null)); // fail open (e.g. no python3)
		child.stdout.on("data", (chunk) => {
			stdout += chunk.toString();
		});
		child.on("close", () => {
			const trimmed = stdout.trim();
			if (!trimmed) return resolve(null); // allowed
			try {
				const decision = JSON.parse(trimmed)?.hookSpecificOutput;
				if (decision?.permissionDecision === "deny") {
					return resolve(decision.permissionDecisionReason ?? "Comment guard blocked this edit.");
				}
			} catch {
				// fall through: fail open
			}
			resolve(null);
		});
		child.stdin.end(JSON.stringify(payload));
	});
}

export default function (pi: ExtensionAPI) {
	if (!GUARD_SCRIPT) return; // guard repo absent: fail open

	pi.on("tool_call", async (event) => {
		let payload: ClaudePayload | undefined;

		if (isToolCallEventType("write", event)) {
			payload = {
				tool_name: "Write",
				tool_input: { file_path: event.input.path, content: event.input.content },
			};
		} else if (isToolCallEventType("edit", event)) {
			payload = {
				tool_name: "Edit",
				tool_input: {
					file_path: event.input.path,
					edits: event.input.edits.map((e) => ({ old_string: e.oldText, new_string: e.newText })),
				},
			};
		}

		if (!payload) return undefined;

		try {
			const reason = await runGuard(GUARD_SCRIPT, payload);
			return reason ? { block: true, reason } : undefined;
		} catch {
			return undefined; // fail open
		}
	});
}

/**
 * Claude-Mode Extension
 *
 * Explicit, cyclable operating modes modelled on Claude Code's shift+tab cycle.
 * pi's native behaviour is full access ("auto mode"); this makes the current
 * posture visible and adds two more restrictive modes.
 *
 * Modes (cycle order):
 *   auto          ▶▶  gold   — pi default: full access, no restrictions
 *   accept-edits  ▶   purple — edits allowed, but `git commit` / `git push` blocked
 *   plan          ⏸   blue   — writes blocked (edit/write tools removed, bash gated)
 *
 * Controls:
 *   Alt+M        cycle forward  (auto → accept-edits → plan → auto)
 *   Alt+Shift+M  cycle backward
 *   /mode [name] jump to a mode, or cycle when called with no argument
 *   /readonly    alias — jump to plan mode
 *   --readonly   CLI flag — start in plan mode
 *
 * Settings (in ~/.pi/agent/settings.json):
 *   "claudeMode": {
 *     "default": "accept-edits",   // startup mode when nothing else overrides
 *     "safeCommands": [], "safePrefixes": [], "safeSubcommands": [],
 *     "destructiveCommands": [], "destructivePrefixes": []
 *   }
 *
 * Legacy back-compat: a "readonlyMode" key (boolean or object) is still honoured.
 *   true / { enabled: true } → default mode "plan"; its command lists feed the
 *   plan-mode bash classifier.
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import type { ThemeColor } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { classifyCommand, applyCommandConfig, isGitCommitOrPush } from "./utils.js";
import type { ReadonlyCommandConfig } from "./utils.js";

type Mode = "auto" | "accept-edits" | "plan";
const MODES: Mode[] = ["auto", "accept-edits", "plan"];

interface ModeSettings {
	defaultMode: Mode;
	commandConfig: ReadonlyCommandConfig;
}

function isMode(value: unknown): value is Mode {
	return value === "auto" || value === "accept-edits" || value === "plan";
}

function extractCommandConfig(source: Record<string, unknown>): ReadonlyCommandConfig {
	return {
		safeCommands: source.safeCommands as string[] | undefined,
		safePrefixes: source.safePrefixes as string[] | undefined,
		safeSubcommands: source.safeSubcommands as
			| Array<{ cmd: string; subs: string[] }>
			| undefined,
		destructiveCommands: source.destructiveCommands as string[] | undefined,
		destructivePrefixes: source.destructivePrefixes as string[] | undefined,
	};
}

function getModeSettings(): ModeSettings {
	try {
		const settingsPath = join(homedir(), ".pi", "agent", "settings.json");
		const settings = JSON.parse(readFileSync(settingsPath, "utf-8"));

		const cm = settings.claudeMode;
		if (cm && typeof cm === "object") {
			return {
				defaultMode: isMode(cm.default) ? cm.default : "accept-edits",
				commandConfig: extractCommandConfig(cm),
			};
		}

		// Legacy readonlyMode fallback
		const rm = settings.readonlyMode;
		if (rm === true) {
			return { defaultMode: "plan", commandConfig: {} };
		}
		if (rm && typeof rm === "object") {
			return {
				defaultMode: rm.enabled === true ? "plan" : "accept-edits",
				commandConfig: extractCommandConfig(rm),
			};
		}

		return { defaultMode: "accept-edits", commandConfig: {} };
	} catch {
		return { defaultMode: "accept-edits", commandConfig: {} };
	}
}

// Tools available when writes are blocked (plan mode)
const PLAN_TOOLS = ["read", "bash", "grep", "find", "ls", "subagent"];

interface ModeStyle {
	label: string;
	glyph: string;
	token: ThemeColor;
}

const MODE_STYLE: Record<Mode, ModeStyle> = {
	auto: { label: "auto mode", glyph: "▶▶", token: "warning" },
	"accept-edits": { label: "accept edits", glyph: "▶", token: "syntaxKeyword" },
	plan: { label: "plan mode", glyph: "⏸", token: "mdLink" },
};

export default function claudeModeExtension(pi: ExtensionAPI): void {
	let mode: Mode = "auto";

	pi.registerFlag("readonly", {
		description: "Start in plan mode (writes blocked)",
		type: "boolean",
		default: false,
	});

	// --- UI ---

	function renderModeLine(ctx: ExtensionContext): void {
		const style = MODE_STYLE[mode];
		const theme = ctx.ui.theme;
		const line =
			theme.fg(style.token, `${style.glyph} ${style.label}`) +
			theme.fg("dim", " · alt+m to cycle");
		ctx.ui.setStatus("claude-mode", line);
	}

	function describe(m: Mode): string {
		switch (m) {
			case "auto":
				return "auto mode — full access";
			case "accept-edits":
				return "accept edits — commits and pushes blocked";
			case "plan":
				return "plan mode — file modifications blocked";
		}
	}

	function applyMode(ctx: ExtensionContext, notify: boolean): void {
		if (mode === "plan") {
			pi.setActiveTools(PLAN_TOOLS);
		} else {
			pi.setActiveTools(pi.getAllTools().map((t) => t.name));
		}
		renderModeLine(ctx);
		if (notify) ctx.ui.notify(describe(mode), "info");
	}

	function setMode(ctx: ExtensionContext, next: Mode): void {
		mode = next;
		applyMode(ctx, true);
	}

	function cycle(ctx: ExtensionContext, delta: number): void {
		const i = MODES.indexOf(mode);
		const next = MODES[(i + delta + MODES.length) % MODES.length];
		setMode(ctx, next);
	}

	// --- Commands & shortcuts ---

	pi.registerCommand("mode", {
		description: "Set claude-mode (auto | accept-edits | plan), or cycle with no arg",
		handler: async (args, ctx) => {
			const arg = args.trim().toLowerCase().replace(/\s+/g, "-");
			if (arg === "") {
				cycle(ctx, 1);
			} else if (isMode(arg)) {
				setMode(ctx, arg);
			} else {
				ctx.ui.notify(`Unknown mode: ${args.trim()}`, "error");
			}
		},
	});

	pi.registerCommand("readonly", {
		description: "Alias — switch to plan mode (writes blocked)",
		handler: async (_args, ctx) => setMode(ctx, "plan"),
	});

	pi.registerShortcut("alt+m", {
		description: "Cycle claude-mode forward",
		handler: async (ctx) => cycle(ctx, 1),
	});

	pi.registerShortcut("alt+shift+m", {
		description: "Cycle claude-mode backward",
		handler: async (ctx) => cycle(ctx, -1),
	});

	// --- Bash gate ---

	pi.on("tool_call", async (event, ctx) => {
		if (event.toolName !== "bash") return undefined;
		if (mode === "auto") return undefined;

		const command = event.input.command as string;

		if (mode === "accept-edits") {
			if (isGitCommitOrPush(command)) {
				return {
					block: true,
					reason: `Accept-edits mode: git commit/push is blocked.\nCommand: ${command}\n\nSwitch to auto mode (alt+m) to commit or push.`,
				};
			}
			return undefined;
		}

		// plan mode
		const safety = classifyCommand(command);
		if (safety === "safe") return undefined;

		if (safety === "destructive") {
			return {
				block: true,
				reason: `Plan mode: command blocked as destructive.\nCommand: ${command}\n\nSwitch out of plan mode (alt+m) first.`,
			};
		}

		if (!ctx.hasUI) {
			return {
				block: true,
				reason: "Plan mode: unrecognised command blocked (no UI for confirmation)",
			};
		}

		const choice = await ctx.ui.select(
			`🛡️  Plan Mode — unrecognised command:\n\n  ${command}\n\nThis command is not in the plan-mode allowlist.\nAllow it to run anyway?`,
			["Allow once", "Block"],
		);
		if (choice !== "Allow once") {
			return { block: true, reason: "Blocked by user in plan mode" };
		}
		return undefined;
	});

	// --- System prompt injection ---

	pi.on("before_agent_start", async () => {
		if (mode === "plan") {
			return {
				message: {
					customType: "claude-mode-plan",
					content: `[PLAN MODE ACTIVE]
You are in plan mode. You MUST NOT modify, create, or delete any files.

Restrictions:
- edit and write tools are disabled — do not attempt to use them
- Bash commands are restricted to read-only operations
- Do NOT use bash to write files (no redirects, no tee, no sed -i, etc.)

Instead of making changes:
- Describe what changes you would make
- Show code snippets or diffs of proposed changes
- Explain your reasoning

The user will switch out of plan mode when they are ready for you to make changes.`,
					display: false,
				},
			};
		}

		if (mode === "accept-edits") {
			return {
				message: {
					customType: "claude-mode-accept",
					content: `[ACCEPT-EDITS MODE ACTIVE]
You may create, edit, and delete files freely. However you MUST NOT commit or
push: do not run \`git commit\` or \`git push\` (these are blocked). Leave the
working tree changed and let the user review and commit.`,
					display: false,
				},
			};
		}

		return undefined;
	});

	// Strip injected mode notes that belong to a mode other than the current one
	pi.on("context", async (event) => {
		const keep: Record<Mode, string | undefined> = {
			auto: undefined,
			"accept-edits": "claude-mode-accept",
			plan: "claude-mode-plan",
		};
		const current = keep[mode];
		const modeTypes = ["claude-mode-plan", "claude-mode-accept", "readonly-mode-context"];
		return {
			messages: event.messages.filter((m) => {
				const msg = m as typeof m & { customType?: string };
				if (!msg.customType || !modeTypes.includes(msg.customType)) return true;
				return msg.customType === current;
			}),
		};
	});

	// --- Session lifecycle ---

	pi.on("session_start", async (_event, ctx) => {
		const settings = getModeSettings();
		applyCommandConfig(settings.commandConfig);

		if (pi.getFlag("readonly") === true) {
			mode = "plan";
		} else {
			const entries = ctx.sessionManager.getEntries();
			const persisted = entries
				.filter(
					(e: { type: string; customType?: string }) =>
						e.type === "custom" &&
						(e.customType === "claude-mode-state" ||
							e.customType === "readonly-mode-state"),
				)
				.pop() as
				| { customType?: string; data?: { mode?: Mode; enabled?: boolean } }
				| undefined;

			if (persisted?.data && isMode(persisted.data.mode)) {
				mode = persisted.data.mode;
			} else if (persisted?.data?.enabled !== undefined) {
				mode = persisted.data.enabled ? "plan" : settings.defaultMode;
			} else {
				mode = settings.defaultMode;
			}
		}

		applyMode(ctx, false);
	});

	pi.on("session_shutdown", async () => {
		pi.appendEntry("claude-mode-state", { mode });
	});
}

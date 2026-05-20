/**
 * Readonly Mode Extension
 *
 * Toggleable read-only mode that prevents file modifications.
 *
 * When enabled:
 * - edit and write tools are removed from the active tool set
 * - Bash commands are classified as safe/destructive/unknown:
 *   - Safe (allowlisted): run without prompting
 *   - Destructive (blocklisted): blocked outright
 *   - Unknown: user is prompted for confirmation
 * - System prompt is augmented to tell the LLM not to modify files
 *
 * Configuration:
 * - /readonly command to toggle
 * - Alt+M shortcut to toggle
 * - --readonly CLI flag to start in readonly mode
 * - "readonlyMode" in settings.json to set the default
 *
 * Settings (in ~/.pi/agent/settings.json):
 *   "readonlyMode": true     // start in readonly mode by default (legacy boolean form)
 *   "readonlyMode": {        // object form with command configuration
 *     "enabled": true,       // start in readonly mode by default
 *     "safeCommands": [],    // additional command names treated as safe
 *     "safePrefixes": [],    // additional command prefixes treated as safe
 *     "safeSubcommands": [], // additional {cmd, subs[]} rules for safe cmd+subcommand
 *     "destructiveCommands": [],  // additional command names treated as destructive
 *     "destructivePrefixes": []   // additional command prefixes treated as destructive
 *   }
 */

import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
import { classifyCommand, applyCommandConfig } from "./utils.js";
import type { ReadonlyCommandConfig } from "./utils.js";

interface ReadonlySettings {
	enabled: boolean;
	commandConfig: ReadonlyCommandConfig;
}

function getReadonlySettings(): ReadonlySettings {
	try {
		const settingsPath = join(homedir(), ".pi", "agent", "settings.json");
		const settings = JSON.parse(readFileSync(settingsPath, "utf-8"));
		const rm = settings.readonlyMode;

		// Support both boolean (legacy) and object forms
		if (rm === true) {
			return { enabled: true, commandConfig: {} };
		}
		if (rm && typeof rm === "object") {
			return {
				enabled: rm.enabled === true,
				commandConfig: {
					safeCommands: rm.safeCommands,
					safePrefixes: rm.safePrefixes,
					safeSubcommands: rm.safeSubcommands,
					destructiveCommands: rm.destructiveCommands,
					destructivePrefixes: rm.destructivePrefixes,
				},
			};
		}
		return { enabled: false, commandConfig: {} };
	} catch {
		return { enabled: false, commandConfig: {} };
	}
}

// Tools available in each mode
const READONLY_TOOLS = ["read", "bash", "grep", "find", "ls", "subagent"];

export default function readonlyModeExtension(pi: ExtensionAPI): void {
	let readonlyEnabled = false;

	// Register CLI flag
	pi.registerFlag("readonly", {
		description: "Start in read-only mode",
		type: "boolean",
		default: false,
	});

	// --- UI helpers ---

	function updateStatus(ctx: ExtensionContext): void {
		if (readonlyEnabled) {
			ctx.ui.setStatus(
				"readonly-mode",
				ctx.ui.theme.fg("warning", "🔒 readonly"),
			);
		} else {
			ctx.ui.setStatus("readonly-mode", undefined);
		}
	}

	function enableReadonly(ctx: ExtensionContext): void {
		readonlyEnabled = true;
		pi.setActiveTools(READONLY_TOOLS);
		updateStatus(ctx);
		ctx.ui.notify("Readonly mode enabled — file modifications blocked", "info");
	}

	function disableReadonly(ctx: ExtensionContext): void {
		readonlyEnabled = false;
		// Restore full tool set by passing all known tool names
		const allTools = pi.getAllTools().map((t) => t.name);
		pi.setActiveTools(allTools);
		updateStatus(ctx);
		ctx.ui.notify("Readonly mode disabled — full access restored", "info");
	}

	function toggleReadonly(ctx: ExtensionContext): void {
		if (readonlyEnabled) {
			disableReadonly(ctx);
		} else {
			enableReadonly(ctx);
		}
	}

	// --- Command & shortcut ---

	pi.registerCommand("readonly", {
		description: "Toggle readonly mode (read-only exploration)",
		handler: async (_args, ctx) => toggleReadonly(ctx),
	});

	pi.registerShortcut("alt+m", {
		description: "Toggle readonly mode",
		handler: async (ctx) => toggleReadonly(ctx),
	});

	// --- Bash permission gate (only in readonly mode) ---

	pi.on("tool_call", async (event, ctx) => {
		if (!readonlyEnabled) return undefined;

		if (event.toolName !== "bash") return undefined;

		const command = event.input.command as string;
		const safety = classifyCommand(command);

		if (safety === "safe") return undefined;

		if (safety === "destructive") {
			return {
				block: true,
				reason: `Readonly mode: command blocked as destructive.\nCommand: ${command}\n\nUse /readonly to disable readonly mode first.`,
			};
		}

		// Unknown command — prompt the user
		if (!ctx.hasUI) {
			return {
				block: true,
				reason: "Readonly mode: unrecognised command blocked (no UI for confirmation)",
			};
		}

		const choice = await ctx.ui.select(
			`🛡️  Readonly Mode — unrecognised command:\n\n  ${command}\n\nThis command is not in the readonly allowlist.\nAllow it to run anyway?`,
			["Allow once", "Block"],
		);

		if (choice !== "Allow once") {
			return { block: true, reason: "Blocked by user in readonly mode" };
		}

		return undefined;
	});

	// --- System prompt injection ---

	pi.on("before_agent_start", async (event) => {
		if (!readonlyEnabled) return undefined;

		return {
			message: {
				customType: "readonly-mode-context",
				content: `[READONLY MODE ACTIVE]
You are in readonly mode. You MUST NOT modify, create, or delete any files.

Restrictions:
- edit and write tools are disabled — do not attempt to use them
- Bash commands are restricted to read-only operations
- Do NOT use bash to write files (no redirects, no tee, no sed -i, etc.)

Instead of making changes:
- Describe what changes you would make
- Show code snippets or diffs of proposed changes
- Explain your reasoning

The user will disable readonly mode when they are ready for you to make changes.`,
				display: false,
			},
		};
	});

	// Filter out stale readonly context when not in readonly mode
	pi.on("context", async (event) => {
		if (readonlyEnabled) return undefined;

		return {
			messages: event.messages.filter((m) => {
				const msg = m as typeof m & { customType?: string };
				return msg.customType !== "readonly-mode-context";
			}),
		};
	});

	// --- Session lifecycle ---

	pi.on("session_start", async (_event, ctx) => {
		// Load command configuration from settings.json
		const readonlySettings = getReadonlySettings();
		applyCommandConfig(readonlySettings.commandConfig);

		// Priority: CLI flag > persisted state > settings.json default
		if (pi.getFlag("readonly") === true) {
			readonlyEnabled = true;
		} else {
			// Check for persisted state from a previous session
			const entries = ctx.sessionManager.getEntries();
			const stateEntry = entries
				.filter(
					(e: { type: string; customType?: string }) =>
						e.type === "custom" && e.customType === "readonly-mode-state",
				)
				.pop() as
				| { data?: { enabled: boolean } }
				| undefined;

			if (stateEntry?.data !== undefined) {
				readonlyEnabled = stateEntry.data.enabled;
			} else {
				// No persisted state and no flag — check settings.json
				readonlyEnabled = readonlySettings.enabled;
			}
		}

		if (readonlyEnabled) {
			pi.setActiveTools(READONLY_TOOLS);
		}
		updateStatus(ctx);
	});

	// Persist state on toggle so it survives resume
	pi.on("session_shutdown", async () => {
		pi.appendEntry("readonly-mode-state", { enabled: readonlyEnabled });
	});
}

/**
 * Command safety classification for readonly mode.
 *
 * The command string is split into segments on shell separators (;, &&, ||, |, newlines).
 * Each segment's command name is extracted (stripping env vars, sudo, etc.) and checked
 * against known safe and destructive command lists.
 *
 * Classification:
 * - "safe"        — all segments use allowlisted read-only commands
 * - "destructive" — any segment uses a blocklisted command or redirect
 * - "unknown"     — none matched either list; the caller decides (prompt or block)
 *
 * Configuration (in ~/.pi/agent/settings.json under "readonlyMode"):
 *   "safeCommands"        — additional command names to treat as safe
 *   "safePrefixes"        — additional command prefixes to treat as safe
 *   "safeSubcommands"     — additional {cmd, subs} rules for safe command+subcommand pairs
 *   "destructiveCommands" — additional command names to treat as destructive
 *   "destructivePrefixes" — additional command prefixes to treat as destructive
 */

// --- Destructive command names (single-word) ---
const DESTRUCTIVE_COMMANDS = new Set([
	"rm", "rmdir", "mv", "cp", "mkdir", "touch",
	"chmod", "chown", "chgrp", "ln",
	"tee", "truncate", "dd", "shred",
	"sudo", "su",
	"kill", "pkill", "killall",
	"reboot", "shutdown",
	"vi", "vim", "nano", "emacs", "code", "subl",
]);

// --- Destructive multi-word patterns (command + subcommand) ---
const DESTRUCTIVE_SUBCOMMANDS: Array<{ cmd: string; subs: RegExp }> = [
	{ cmd: "npm", subs: /^(install|uninstall|update|ci|link|publish)$/i },
	{ cmd: "yarn", subs: /^(add|remove|install|publish)$/i },
	{ cmd: "pnpm", subs: /^(add|remove|install|publish)$/i },
	{ cmd: "pip", subs: /^(install|uninstall)$/i },
	{ cmd: "apt", subs: /^(install|remove|purge|update|upgrade)$/i },
	{ cmd: "apt-get", subs: /^(install|remove|purge|update|upgrade)$/i },
	{ cmd: "brew", subs: /^(install|uninstall|upgrade)$/i },
	{ cmd: "git", subs: /^(add|commit|push|pull|merge|rebase|reset|checkout|stash|cherry-pick|revert|tag|init|clone)$/i },
	{ cmd: "git.exe", subs: /^(add|commit|push|pull|merge|rebase|reset|checkout|stash|cherry-pick|revert|tag|init|clone)$/i },
	{ cmd: "systemctl", subs: /^(start|stop|restart|enable|disable)$/i },
	{ cmd: "dotnet.exe", subs: /^(new|add|remove|publish|pack)$/i },
];

// Also destructive: git branch -d/-D
const DESTRUCTIVE_GIT_BRANCH = /^-[dD]/;

// --- Safe command names ---
const DEFAULT_SAFE_COMMANDS = new Set([
	"cat", "head", "tail", "less", "more",
	"grep", "find", "ls", "pwd",
	"echo", "printf", "wc", "sort", "uniq",
	"diff", "file", "stat", "du", "df", "tree",
	"which", "whereis", "type", "env", "printenv",
	"uname", "whoami", "id", "date", "cal", "uptime",
	"ps", "top", "htop", "free",
	"rg", "fd", "bat", "eza", "jq", "awk",
	"curl", "web", "repo-find",
]);

// --- Safe multi-word patterns (command + subcommand) ---
const SAFE_SUBCOMMANDS: Array<{ cmd: string; subs: RegExp }> = [
	{ cmd: "git", subs: /^(status|log|diff|show|branch|remote|ls-files|ls-tree|ls-remote)$/i },
	{ cmd: "git", subs: /^config$/i }, // git config --get is safe; handled by not matching destructive
	{ cmd: "git.exe", subs: /^(status|log|diff|show|branch|remote|ls-files|ls-tree|ls-remote|config)$/i },
	{ cmd: "npm", subs: /^(list|ls|view|info|search|outdated|audit)$/i },
	{ cmd: "yarn", subs: /^(list|info|why|audit)$/i },
	{ cmd: "node", subs: /^--version$/i },
	{ cmd: "python", subs: /^--version$/i },
	{ cmd: "dotnet.exe", subs: /^(--version|--list-sdks|--list-runtimes|--info|list)$/i },
	{ cmd: "sed", subs: /^-n$/i }, // sed -n (print only) is safe
];

// Safe if the command starts with these prefixes
const DEFAULT_SAFE_PREFIXES = [
	"cli-anything",
	"wget -O -", // wget to stdout only
];

// --- Redirect detection ---
const REDIRECT_PATTERN = /(^|[^<])>(?!>)|>>/;

// --- Command parsing ---

/**
 * Split a command string into segments on shell separators.
 * Handles ;  &&  ||  |  and newlines.
 */
function splitSegments(command: string): string[] {
	// Replace newlines with ; for uniform splitting
	const normalized = command.replace(/\n/g, " ; ");
	// Split on && || ; | (capturing the separator isn't needed)
	return normalized
		.split(/\s*(?:&&|\|\||[;|])\s*/)
		.map((s) => s.trim())
		.filter((s) => s.length > 0);
}

/**
 * Extract the command name and first argument from a segment.
 * Strips leading env assignments (FOO=bar) and sudo/su prefixes.
 */
function extractCommand(segment: string): { cmd: string; firstArg: string; secondArg: string } {
	const tokens = segment.split(/\s+/);

	// Skip env variable assignments (KEY=value)
	let i = 0;
	while (i < tokens.length && /^[A-Za-z_][A-Za-z0-9_]*=/.test(tokens[i])) {
		i++;
	}

	// Skip sudo/su
	while (i < tokens.length && (tokens[i] === "sudo" || tokens[i] === "su")) {
		i++;
		// Skip sudo flags like -u user
		while (i < tokens.length && tokens[i].startsWith("-")) {
			i++;
			// If the flag takes a value (like -u root), skip that too
			if (i < tokens.length && !tokens[i].startsWith("-")) {
				i++;
			}
		}
	}

	const cmd = tokens[i] ?? "";
	const firstArg = tokens[i + 1] ?? "";
	const secondArg = tokens[i + 2] ?? "";
	return { cmd, firstArg, secondArg };
}

export type CommandSafety = "safe" | "destructive" | "unknown";

/**
 * User-configurable overrides loaded from settings.json "readonlyMode" key.
 */
export interface ReadonlyCommandConfig {
	safeCommands?: string[];
	safePrefixes?: string[];
	safeSubcommands?: Array<{ cmd: string; subs: string[] }>;
	destructiveCommands?: string[];
	destructivePrefixes?: string[];
}

// Resolved (merged) sets built from defaults + user config
let resolvedSafeCommands: Set<string> = DEFAULT_SAFE_COMMANDS;
let resolvedSafePrefixes: string[] = DEFAULT_SAFE_PREFIXES;
let resolvedSafeSubcommands: typeof SAFE_SUBCOMMANDS = SAFE_SUBCOMMANDS;
let resolvedDestructiveCommands: Set<string> = DESTRUCTIVE_COMMANDS;
let resolvedDestructivePrefixes: string[] = [];

/**
 * Apply user configuration to extend the built-in command lists.
 * Call once at startup after reading settings.json.
 */
export function applyCommandConfig(config: ReadonlyCommandConfig): void {
	// Safe commands
	resolvedSafeCommands = new Set(DEFAULT_SAFE_COMMANDS);
	if (config.safeCommands) {
		for (const cmd of config.safeCommands) resolvedSafeCommands.add(cmd);
	}

	// Safe prefixes
	resolvedSafePrefixes = [...DEFAULT_SAFE_PREFIXES];
	if (config.safePrefixes) {
		resolvedSafePrefixes.push(...config.safePrefixes);
	}

	// Safe subcommands
	resolvedSafeSubcommands = [...SAFE_SUBCOMMANDS];
	if (config.safeSubcommands) {
		for (const rule of config.safeSubcommands) {
			const pattern = new RegExp(`^(${rule.subs.join("|")})$`, "i");
			resolvedSafeSubcommands.push({ cmd: rule.cmd, subs: pattern });
		}
	}

	// Destructive commands
	resolvedDestructiveCommands = new Set(DESTRUCTIVE_COMMANDS);
	if (config.destructiveCommands) {
		for (const cmd of config.destructiveCommands) resolvedDestructiveCommands.add(cmd);
	}

	// Destructive prefixes
	resolvedDestructivePrefixes = config.destructivePrefixes ?? [];
}

/**
 * Classify a single segment as safe, destructive, or unknown.
 */
function classifySegment(segment: string): CommandSafety {
	// Check for redirects in the raw segment
	if (REDIRECT_PATTERN.test(segment)) return "destructive";

	const { cmd, firstArg, secondArg } = extractCommand(segment);
	if (!cmd) return "unknown";

	const cmdLower = cmd.toLowerCase();

	// --- Destructive checks ---

	// Single-word destructive commands (including sudo/su which extractCommand skips through)
	if (resolvedDestructiveCommands.has(cmdLower)) return "destructive";

	// Multi-word destructive (command + subcommand)
	for (const rule of DESTRUCTIVE_SUBCOMMANDS) {
		if (cmdLower === rule.cmd.toLowerCase() && rule.subs.test(firstArg)) {
			return "destructive";
		}
	}

	// Special case: git branch -d/-D
	if ((cmdLower === "git" || cmdLower === "git.exe") && firstArg === "branch" && DESTRUCTIVE_GIT_BRANCH.test(secondArg)) {
		return "destructive";
	}

	// Special case: service <name> start/stop/restart
	if (cmdLower === "service" && secondArg && /^(start|stop|restart)$/i.test(secondArg)) {
		return "destructive";
	}

	// Special case: dotnet.exe tool install
	if (cmdLower === "dotnet.exe" && firstArg === "tool" && /^install$/i.test(secondArg)) {
		return "destructive";
	}

	// Destructive prefixes (user-configured)
	if (resolvedDestructivePrefixes.some((p) => segment.startsWith(p))) return "destructive";

	// --- Safe checks ---

	// Single-word safe commands
	if (resolvedSafeCommands.has(cmdLower)) return "safe";

	// Multi-word safe (command + subcommand)
	for (const rule of resolvedSafeSubcommands) {
		if (cmdLower === rule.cmd.toLowerCase() && rule.subs.test(firstArg)) {
			return "safe";
		}
	}

	// Safe prefixes
	if (resolvedSafePrefixes.some((p) => segment.startsWith(p))) return "safe";

	return "unknown";
}

/**
 * Classify a full bash command string.
 *
 * The command is split into segments and each is classified independently.
 * If ANY segment is destructive, the whole command is destructive.
 * If ALL segments are safe, the whole command is safe.
 * Otherwise it's unknown (caller should prompt).
 */
export function classifyCommand(command: string): CommandSafety {
	const segments = splitSegments(command);
	if (segments.length === 0) return "unknown";

	let allSafe = true;

	for (const segment of segments) {
		const result = classifySegment(segment);
		if (result === "destructive") return "destructive";
		if (result !== "safe") allSafe = false;
	}

	return allSafe ? "safe" : "unknown";
}

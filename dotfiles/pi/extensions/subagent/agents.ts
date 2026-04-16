/**
 * Agent discovery with configurable directories and Claude Code compatibility.
 *
 * Reads agent directories from:
 *   1. ~/.pi/agent/agents/          (pi default user agents)
 *   2. .pi/agents/                  (pi default project agents)
 *   3. settings.json "agentDirs"    (custom directories)
 *
 * Strips Claude Code-specific frontmatter (tools, mcpServers, color, memory, skills)
 * so agents run with all available pi tools.
 */

import * as fs from "node:fs";
import * as os from "node:os";
import * as path from "node:path";
import { getAgentDir, parseFrontmatter } from "@mariozechner/pi-coding-agent";

export type AgentScope = "user" | "project" | "both";

export interface AgentConfig {
	name: string;
	description: string;
	tools?: string[];
	model?: string;
	systemPrompt: string;
	source: "user" | "project" | "custom";
	filePath: string;
}

export interface AgentDiscoveryResult {
	agents: AgentConfig[];
	projectAgentsDir: string | null;
}

/** Frontmatter fields we keep — everything else is stripped. */
const KEPT_FIELDS = new Set(["name", "description", "model"]);

/** Claude Code tools that do not exist in pi — silently dropped. */
const IGNORED_TOOL_PREFIXES = ["mcp__"];
const IGNORED_TOOLS = new Set([
	"Bash", "Read", "Grep", "Glob", "Write", "Edit",          // Claude Code built-in names
	"WebFetch", "WebSearch", "Task", "TodoRead", "TodoWrite",
]);

/**
 * Map Claude Code tool names to pi equivalents where possible.
 * Tools that cannot be mapped are dropped.
 */
function mapTools(raw: unknown): string[] | undefined {
	if (!raw) return undefined;

	let items: string[];
	if (Array.isArray(raw)) {
		items = raw.map(String);
	} else if (typeof raw === "string") {
		items = raw.split(",").map((t) => t.trim()).filter(Boolean);
	} else {
		return undefined;
	}

	const mapped: string[] = [];
	for (const tool of items) {
		// Skip MCP tools and Claude Code built-ins
		if (IGNORED_TOOLS.has(tool)) continue;
		if (IGNORED_TOOL_PREFIXES.some((p) => tool.startsWith(p))) continue;
		mapped.push(tool);
	}

	// Return undefined (= all tools) when nothing survives mapping,
	// since the original agent likely relied on built-in tools that pi already has.
	return mapped.length > 0 ? mapped : undefined;
}

function expandPath(p: string): string {
	if (p.startsWith("~/") || p === "~") {
		return path.join(os.homedir(), p.slice(2));
	}
	return p;
}

function loadAgentsFromDir(dir: string, source: "user" | "project" | "custom", modelOverride?: string): AgentConfig[] {
	const agents: AgentConfig[] = [];
	const resolved = expandPath(dir);

	if (!fs.existsSync(resolved)) return agents;

	let entries: fs.Dirent[];
	try {
		entries = fs.readdirSync(resolved, { withFileTypes: true });
	} catch {
		return agents;
	}

	for (const entry of entries) {
		if (!entry.name.endsWith(".md")) continue;
		if (!entry.isFile() && !entry.isSymbolicLink()) continue;

		const filePath = path.join(resolved, entry.name);
		let content: string;
		try {
			content = fs.readFileSync(filePath, "utf-8");
		} catch {
			continue;
		}

		const { frontmatter, body } = parseFrontmatter<Record<string, any>>(content);

		if (!frontmatter.name || !frontmatter.description) continue;

		const tools = mapTools(frontmatter.tools);

		// For custom (external) agents, strip the model from frontmatter —
		// Claude Code model names (e.g. "haiku") won't resolve correctly in pi.
		// User agents keep their model as they were written for pi.
		const effectiveModel = modelOverride
			?? (source === "custom" ? undefined : frontmatter.model);

		agents.push({
			name: frontmatter.name,
			description: frontmatter.description,
			tools,
			model: effectiveModel,
			systemPrompt: body,
			source,
			filePath,
		});
	}

	return agents;
}

function isDirectory(p: string): boolean {
	try {
		return fs.statSync(p).isDirectory();
	} catch {
		return false;
	}
}

function findNearestProjectAgentsDir(cwd: string): string | null {
	let currentDir = cwd;
	while (true) {
		const candidate = path.join(currentDir, ".pi", "agents");
		if (isDirectory(candidate)) return candidate;

		const parentDir = path.dirname(currentDir);
		if (parentDir === currentDir) return null;
		currentDir = parentDir;
	}
}

interface AgentSettings {
	agentDirs: string[];
	agentModel?: string;
}

/**
 * Read agent settings from ~/.pi/agent/settings.json.
 *   - agentDirs:  string[] of extra directories to scan for agent .md files
 *   - agentModel: optional model override for all discovered agents
 */
function getAgentSettings(): AgentSettings {
	const settingsPath = path.join(getAgentDir(), "settings.json");
	try {
		const raw = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
		return {
			agentDirs: Array.isArray(raw.agentDirs)
				? raw.agentDirs.filter((d: unknown) => typeof d === "string")
				: [],
			agentModel: typeof raw.agentModel === "string" ? raw.agentModel : undefined,
		};
	} catch {
		// No settings or invalid JSON — fine
	}
	return { agentDirs: [] };
}

export function discoverAgents(cwd: string, scope: AgentScope): AgentDiscoveryResult {
	const settings = getAgentSettings();
	const userDir = path.join(getAgentDir(), "agents");
	const projectAgentsDir = findNearestProjectAgentsDir(cwd);
	const customDirs = settings.agentDirs;

	const userAgents = scope === "project" ? [] : loadAgentsFromDir(userDir, "user", settings.agentModel);
	const projectAgents =
		scope === "user" || !projectAgentsDir ? [] : loadAgentsFromDir(projectAgentsDir, "project", settings.agentModel);
	const customAgents = customDirs.flatMap((dir) => loadAgentsFromDir(dir, "custom", settings.agentModel));

	// Merge: user < project < custom  (later wins on name collision)
	const agentMap = new Map<string, AgentConfig>();

	if (scope !== "project") {
		for (const agent of userAgents) agentMap.set(agent.name, agent);
	}
	if (scope !== "user") {
		for (const agent of projectAgents) agentMap.set(agent.name, agent);
	}
	// Custom dirs always included regardless of scope
	for (const agent of customAgents) agentMap.set(agent.name, agent);

	return { agents: Array.from(agentMap.values()), projectAgentsDir };
}

export function formatAgentList(
	agents: AgentConfig[],
	maxItems: number,
): { text: string; remaining: number } {
	if (agents.length === 0) return { text: "none", remaining: 0 };
	const listed = agents.slice(0, maxItems);
	const remaining = agents.length - listed.length;
	return {
		text: listed.map((a) => `${a.name} (${a.source}): ${a.description}`).join("; "),
		remaining,
	};
}

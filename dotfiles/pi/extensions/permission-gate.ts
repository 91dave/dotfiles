/**
 * Permission Gate Extension
 *
 * Prompts for confirmation before running gated commands.
 * Configure patterns in ~/.pi/agent/settings.json:
 *
 * {
 *   "permissionGate": [
 *     { "pattern": "\\bgit(?:\\.exe)?\\b.*\\bpush\\b", "label": "git push" }
 *   ]
 * }
 */

import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

interface GateEntry {
  pattern: string;
  label: string;
}

function loadGatedPatterns(): { pattern: RegExp; label: string }[] {
  const settingsPath = path.join(os.homedir(), ".pi", "agent", "settings.json");
  try {
    const raw = JSON.parse(fs.readFileSync(settingsPath, "utf-8"));
    const entries: GateEntry[] = raw.permissionGate;
    if (!Array.isArray(entries)) return [];
    return entries
      .filter((e) => typeof e.pattern === "string" && typeof e.label === "string")
      .map((e) => ({ pattern: new RegExp(e.pattern), label: e.label }));
  } catch {
    return [];
  }
}

export default function (pi: ExtensionAPI) {
  let gatedPatterns = loadGatedPatterns();

  // Reload config on session start (covers /reload)
  pi.on("session_start", async () => {
    gatedPatterns = loadGatedPatterns();
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName !== "bash") return undefined;

    const command = event.input.command as string;
    const match = gatedPatterns.find((g) => g.pattern.test(command));

    if (!match) return undefined;

    if (!ctx.hasUI) {
      return { block: true, reason: `${match.label} blocked (no UI for confirmation)` };
    }

    const choice = await ctx.ui.select(
      `🔒 Permission required: ${match.label}\n\n  ${command}\n\nAllow?`,
      ["Yes", "No"]
    );

    if (choice !== "Yes") {
      return { block: true, reason: `${match.label} blocked by user` };
    }

    return undefined;
  });
}

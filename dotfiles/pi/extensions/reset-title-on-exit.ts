/**
 * Reset Terminal Title on Exit
 *
 * Pi sets the terminal title but doesn't reset it when closing.
 * This extension hooks into process exit (which fires after all pi
 * cleanup) to reset the terminal title via ANSI escape sequence.
 *
 * Placement: ~/.pi/agent/extensions/reset-title-on-exit.ts
 */

import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";

export default function (_pi: ExtensionAPI) {
  process.on("exit", () => {
    // Reset terminal title using ANSI OSC sequence with empty title
    process.stdout.write("\x1b]0;\x07");
  });
}

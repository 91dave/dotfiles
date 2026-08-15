/**
 * Claude-UI — makes pi's TUI resemble Claude Code (superficially).
 *
 * Adds:
 *  - a Claude-style status footer:
 *      [model (window)] 📁 dir 🌸 tokens/window (NN%) 💰 $cost ⏱ HH:MM:SS 📄 +add/-del
 *  - an above-editor thinking-level ("effort") indicator: ● high · /effort
 *    (pi's thinking level IS the effort control — shift+tab cycles it)
 *  - a Claude-ish working spinner
 *
 * Pairs with the "claude" theme. Everything here maps to a real pi API;
 * no fake auto-mode / agents line (pi has no equivalent).
 *
 * Disable:
 *  - PI_CLAUDE_UI=0 pi             → off for that run
 *  - /claude-ui                    → toggle at runtime
 *  - settings.json "theme":"dark"  → drop the colours independently
 *  - or delete this file / unlink it
 *
 * Placement (symlinked from dotfiles): ~/.pi/agent/extensions/claude-ui/index.ts
 */

import type { AssistantMessage } from "@earendil-works/pi-ai";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";
import { truncateToWidth, visibleWidth } from "@earendil-works/pi-tui";
import { execFile } from "node:child_process";
import { basename } from "node:path";

const LEVEL_DOT_RGB: Record<string, string> = {
  off: "111;101;112",
  minimal: "154;143;149",
  low: "127;176;212",
  medium: "138;168;114",
  high: "224;164;88",
  xhigh: "217;119;87",
  max: "224;120;138",
};

/** ms → H:MM:SS (hours dropped when zero) */
function formatDuration(ms: number): string {
  const s = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const sec = s % 60;
  const pad = (n: number) => String(n).padStart(2, "0");
  return h > 0 ? `${h}:${pad(m)}:${pad(sec)}` : `${m}:${pad(sec)}`;
}

function envDisabled(): boolean {
  const v = (process.env.PI_CLAUDE_UI ?? "").toLowerCase();
  return v === "0" || v === "false" || v === "off" || v === "no";
}

/** "1M context" / "200K context" / "128K context" */
function windowLabel(window: number | undefined): string {
  if (!window || window <= 0) return "";
  if (window >= 1_000_000) {
    const m = window / 1_000_000;
    return `${Number.isInteger(m) ? m : m.toFixed(1)}M context`;
  }
  return `${Math.round(window / 1000)}K context`;
}

/** git working-tree changes vs HEAD → { add, del }, cached and refreshed on demand. */
function makeDiffTracker(cwd: string) {
  let add = 0;
  let del = 0;
  let branch: string | null = null;
  const refresh = () => {
    execFile(
      "git",
      ["diff", "--shortstat", "HEAD"],
      { cwd, timeout: 2000 },
      (err, stdout) => {
        if (err) {
          add = 0;
          del = 0;
          return;
        }
        add = Number(/(\d+) insertion/.exec(stdout)?.[1] ?? 0);
        del = Number(/(\d+) deletion/.exec(stdout)?.[1] ?? 0);
      },
    );
    execFile(
      "git",
      ["rev-parse", "--abbrev-ref", "HEAD"],
      { cwd, timeout: 2000 },
      (err, stdout) => {
        if (err) {
          branch = null;
          return;
        }
        const b = stdout.trim();
        branch = b === "HEAD" ? "detached" : b || null;
      },
    );
  };
  refresh();
  return { get: () => ({ add, del, branch }), refresh };
}

export default function (pi: ExtensionAPI) {
  let active = false;
  // biome-ignore lint/suspicious/noExplicitAny: TUI handle captured from footer factory
  let tuiRef: any;
  let diffRef: ReturnType<typeof makeDiffTracker> | undefined;
  let clock: ReturnType<typeof setInterval> | undefined;
  let sessionStart = 0;

  // biome-ignore lint/suspicious/noExplicitAny: event ctx type varies by event
  const apply = (ctx: any) => {
    if (active || ctx.mode !== "tui") return;
    active = true;

    const cwd = process.cwd();
    sessionStart = Date.now();
    diffRef = makeDiffTracker(cwd);

    // ---- Above-editor "effort" indicator: ● <level> · /effort (right-aligned) ----
    // biome-ignore lint/suspicious/noExplicitAny: theme type from pi-tui
    ctx.ui.setWidget("claude-effort", (_tui: any, theme: any) => ({
      invalidate() {},
      render(width: number): string[] {
        const level = ctx.thinkingLevel ?? "off";
        const rgb = LEVEL_DOT_RGB[level] ?? LEVEL_DOT_RGB.off;
        const label =
          `\x1b[38;2;${rgb}m● ${level}\x1b[0m` + theme.fg("dim", " · /effort");
        const pad = Math.max(0, width - visibleWidth(label));
        return [" ".repeat(pad) + label];
      },
    }));

    // ---- Status footer ----
    // biome-ignore lint/suspicious/noExplicitAny: TUI/theme/footerData types from pi
    ctx.ui.setFooter((tui: any, theme: any, footerData: any) => {
      tuiRef = tui;
      const unsubBranch = footerData.onBranchChange(() => tui.requestRender());
      clock = setInterval(() => tui.requestRender(), 1000);

      return {
        dispose: () => {
          unsubBranch();
          if (clock) clearInterval(clock);
          clock = undefined;
        },
        invalidate() {},
        render(width: number): string[] {
          const model = ctx.model;
          const modelId = model?.id ?? "no-model";

          // cost from session branch
          let cost = 0;
          for (const e of ctx.sessionManager.getBranch()) {
            if (e.type === "message" && e.message.role === "assistant") {
              cost += (e.message as AssistantMessage).usage.cost.total;
            }
          }

          const usage = ctx.getContextUsage?.();
          const window: number | undefined =
            usage?.contextWindow ?? model?.contextWindow;
          const tokens: number = usage?.tokens ?? 0;
          const pctNum: number =
            usage?.percent ??
            (window && window > 0 ? (tokens / window) * 100 : 0);
          // max one decimal place, drop trailing .0
          const pct = Number(pctNum.toFixed(1)).toString();

          const now = formatDuration(Date.now() - sessionStart);
          const { add, del, branch } = diffRef?.get() ?? {
            add: 0,
            del: 0,
            branch: null,
          };
          const wl = windowLabel(window);

          const seg: string[] = [];
          seg.push(theme.fg("accent", `[${modelId}${wl ? ` (${wl})` : ""}]`));
          // dir name in ls --color=auto blue (dircolors default di=01;34: bold blue)
          seg.push(`📁 \x1b[1;34m${basename(cwd)}\x1b[0m`);
          if (window)
            seg.push(
              theme.fg("mdListBullet", "🌸 ") +
                theme.fg("muted", `${tokens}/${window} (${pct}%)`),
            );
          seg.push(theme.fg("success", `💰 $${cost.toFixed(3)}`));
          seg.push(`⏱ \x1b[38;2;200;150;200m${now}\x1b[0m`);
          seg.push(
            "📄 " +
              theme.fg("toolDiffAdded", `+${add}`) +
              theme.fg("dim", "/") +
              theme.fg("toolDiffRemoved", `-${del}`),
          );

          const pad = "  ";
          const lines = [truncateToWidth(pad + seg.join("  "), width)];

          const line2: string[] = [];
          const statuses = footerData.getExtensionStatuses?.();
          if (statuses && statuses.size > 0) {
            line2.push(Array.from(statuses.values()).join("  "));
          }
          if (branch) {
            line2.push(theme.fg("success", `🌿 ${branch}`));
          }
          if (line2.length > 0) {
            lines.push(truncateToWidth(pad + line2.join("  "), width));
          }
          return lines;
        },
      };
    });

    // ---- Working spinner (Claude-ish pulse) ----
    const frames = ["✳", "✳", "✷", "✶", "✷", "✳"].map((f) =>
      ctx.ui.theme.fg("accent", f),
    );
    ctx.ui.setWorkingIndicator({ frames, intervalMs: 140 });
  };

  // biome-ignore lint/suspicious/noExplicitAny: ctx type varies by call site
  const restore = (ctx: any) => {
    if (!active) return;
    active = false;
    if (clock) clearInterval(clock);
    clock = undefined;
    ctx.ui.setWidget("claude-effort", undefined);
    ctx.ui.setFooter(undefined);
    ctx.ui.setWorkingIndicator();
    diffRef = undefined;
    tuiRef = undefined;
  };

  // Registered once; gated on `active`. pi.on returns void (no disposer).
  pi.on("turn_end", async () => {
    if (!active) return;
    diffRef?.refresh();
    tuiRef?.requestRender();
  });
  pi.on("thinking_level_select", async () => {
    if (active) tuiRef?.requestRender();
  });

  pi.on("session_start", async (_event, ctx) => {
    if (!envDisabled()) apply(ctx);
  });

  pi.registerCommand("claude-ui", {
    description: "Toggle the Claude Code look (footer, effort, spinner)",
    handler: async (_args, ctx) => {
      if (active) {
        restore(ctx);
        ctx.ui.notify("Claude UI off (default footer restored)", "info");
      } else {
        apply(ctx);
        ctx.ui.notify("Claude UI on", "info");
      }
    },
  });
}

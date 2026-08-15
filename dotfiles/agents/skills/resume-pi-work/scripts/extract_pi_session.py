#!/usr/bin/env python3
"""Extract a resume brief from a pi coding agent session.

Usage:
  extract_pi_session.py <uuid|path> [--tail N] [--full] [--json]

Reports what the session was trying to do, what it changed, and where it
stopped. Tool-result bodies, thinking blocks and exploration calls are omitted
by default: they dominate the file and rarely carry intent.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import pi_session as pi

PLAN_MIN_CHARS = 1500
DIFF_BUDGET = 6000
ERROR_EXCERPT = 300
TITLE_CHARS = 90


def demote_headings(text: str, levels: int = 3) -> str:
    """Push quoted markdown below the brief's own headings so the outline holds."""
    lines = []
    fenced = False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            fenced = not fenced
        elif not fenced and line.startswith("#"):
            hashes = len(line) - len(line.lstrip("#"))
            line = "#" * min(hashes + levels, 6) + line[hashes:]
        lines.append(line)
    return "\n".join(lines)


def one_line(text: str, limit: int) -> str:
    return " ".join(str(text).split())[:limit]


def collect(session: pi.Session, tail: int) -> dict:
    results = pi.tool_results(session)
    calls = pi.tool_calls(session)

    handovers = [
        {
            "type": entry["type"],
            "timestamp": entry.get("timestamp"),
            "summary": entry.get("summary") or "",
            "modified_files": ((entry.get("details") or {}).get("modifiedFiles") or []),
        }
        for entry in pi.compactions(session)
    ]

    prompts = [
        text
        for entry in session.messages("user")
        if (text := pi.text_of(entry["message"].get("content")).strip())
    ]

    assistant_texts = [
        text
        for entry in session.messages("assistant")
        if (text := pi.text_of(entry["message"].get("content")).strip())
    ]
    plans = [t for t in assistant_texts if len(t) >= PLAN_MIN_CHARS]
    if assistant_texts and assistant_texts[-1] not in plans:
        plans.append(assistant_texts[-1])

    thinking = [
        str(block.get("thinking") or "").strip()
        for entry in session.messages("assistant")
        for block in pi.blocks_of(entry["message"].get("content"), "thinking")
    ]

    commands = []
    for call in calls:
        if call.get("name") != "bash":
            continue
        arguments = call.get("arguments")
        command = arguments.get("command") if isinstance(arguments, dict) else None
        if command and command not in commands:
            commands.append(str(command))

    user_commands = [
        {"command": entry["message"].get("command"), "exit_code": entry["message"].get("exitCode")}
        for entry in session.messages("bashExecution")
    ]

    diffs = []
    for entry in session.messages("toolResult"):
        message = entry["message"]
        if message.get("toolName") != "edit":
            continue
        details = message.get("details")
        diff = details.get("diff") if isinstance(details, dict) else None
        if diff:
            diffs.append(str(diff))

    subagents = []
    for entry in session.messages("toolResult"):
        message = entry["message"]
        if message.get("toolName") != "subagent":
            continue
        details = message.get("details")
        for result in (details or {}).get("results") or []:
            if not isinstance(result, dict):
                continue
            subagents.append(
                {
                    "agent": result.get("agent"),
                    "task": str(result.get("task") or "")[:300],
                    "stop_reason": result.get("stopReason"),
                    "exit_code": result.get("exitCode"),
                }
            )

    modes = [
        {
            "timestamp": entry.get("timestamp"),
            "custom_type": entry.get("customType"),
            "mode": (entry.get("data") or {}).get("mode"),
        }
        for entry in session.entries
        if entry.get("type") in ("custom", "custom_message")
    ]

    errors = []
    for entry in session.messages("toolResult"):
        message = entry["message"]
        if not message.get("isError"):
            continue
        errors.append(
            {
                "tool": message.get("toolName"),
                "excerpt": one_line(pi.text_of(message.get("content")), ERROR_EXCERPT),
            }
        )

    ending = pi.finish_state(session)
    last_call = calls[-1] if calls else None
    if last_call:
        arguments = last_call.get("arguments") if isinstance(last_call.get("arguments"), dict) else {}
        ending["last_tool_call"] = {
            "name": last_call.get("name"),
            "arguments": str(arguments)[:300],
            "has_result": last_call.get("id") in results,
        }

    return {
        "session": {
            "path": str(session.path),
            "uuid": session.uuid,
            "cwd": session.cwd,
            "cwd_exists": bool(session.cwd) and Path(session.cwd).is_dir(),
            "name": session.name,
            "title": session.title().replace("\n", " ")[:200],
            "created": session.created,
            "last_active": datetime.fromtimestamp(session.path.stat().st_mtime).strftime("%Y-%m-%d %H:%M"),
            "model": session.model,
            "thinking_level": session.thinking_level,
            "parent_session": session.parent_session,
            "entries": len(session.entries),
            "messages": len(session.messages()),
            "usage": pi.usage_total(session),
        },
        "handovers": handovers,
        "prompts": prompts,
        "plans": plans,
        "assistant_texts": assistant_texts,
        "thinking": [t for t in thinking if t],
        "files_touched": pi.written_paths(session),
        "diffs": diffs,
        "commands": commands[-tail:],
        "commands_total": len(commands),
        "user_commands": user_commands,
        "subagents": subagents,
        "modes": modes,
        "errors": errors[-5:],
        "errors_total": len(errors),
        "ending": ending,
    }


def render(data: dict, full: bool) -> str:
    facts = data["session"]
    out: list[str] = [f"# pi session {facts['uuid'][:8]}: {one_line(facts['title'], TITLE_CHARS)}", ""]

    missing = "" if facts["cwd_exists"] else "  (no longer exists)"
    out += [
        f"- **Folder** `{facts['cwd']}`{missing}",
        f"- **File** `{facts['path']}`",
        f"- **Started** {facts['created']}  **Last active** {facts['last_active']}",
        f"- **Model** {facts['model'] or 'unknown'}  **Thinking** {facts['thinking_level'] or 'unknown'}",
        f"- **Size** {facts['entries']} entries, {facts['messages']} messages, "
        f"{facts['usage']['totalTokens']:,} tokens across all turns",
    ]
    if facts["parent_session"]:
        out.append(f"- **Forked from** `{facts['parent_session']}`")
    out.append("")

    ending = data["ending"]
    verdict = {
        "complete": "Ran to completion.",
        "interrupted": "Stopped mid-turn.",
        "error": "Died with an error.",
    }[ending["state"]]
    out += ["## Where it stopped", "", verdict]
    if ending["detail"]:
        out.append(f"Reason: {one_line(ending['detail'], 200)}.")
    if ending.get("error_message"):
        out.append(f"Error: {one_line(ending['error_message'], 300)}")
    last_call = ending.get("last_tool_call")
    if last_call:
        fate = "result returned" if last_call["has_result"] else "**no result, so this never completed**"
        out.append(f"Last tool call: `{last_call['name']}` ({fate}): {one_line(last_call['arguments'], 300)}")
    out.append("")

    if data["handovers"]:
        out += ["## Handover summaries", ""]
        for handover in data["handovers"]:
            out.append(f"### {handover['type']} at {handover['timestamp']}")
            out += ["", demote_headings(handover["summary"]), ""]
            if handover["modified_files"]:
                out += ["Files it recorded as modified:", ""]
                out += [f"- `{p}`" for p in handover["modified_files"]]
                out.append("")

    if data["prompts"]:
        out += ["## What was asked, in order", ""]
        for index, prompt in enumerate(data["prompts"], 1):
            out += [f"{index}. {demote_headings(prompt)}", ""]

    if data["plans"]:
        out += ["## Plans and closing statements", ""]
        for plan in data["plans"]:
            out += [demote_headings(plan), "", "---", ""]

    if data["files_touched"]:
        out += ["## Files written or edited", ""]
        out += [f"- `{p}`" for p in data["files_touched"]]
        out.append("")

    if data["diffs"]:
        out += ["## Diffs applied", ""]
        spent = 0
        shown = 0
        for diff in data["diffs"]:
            if spent + len(diff) > DIFF_BUDGET:
                break
            out += ["```diff", diff.rstrip(), "```", ""]
            spent += len(diff)
            shown += 1
        if shown < len(data["diffs"]):
            out += [f"_{len(data['diffs']) - shown} further diffs omitted._", ""]

    if data["commands"]:
        out += [f"## Commands run (last {len(data['commands'])} of {data['commands_total']})", ""]
        out += ["```bash", *data["commands"], "```", ""]

    if data["user_commands"]:
        out += ["## Commands the user ran directly", ""]
        for command in data["user_commands"]:
            out.append(f"- `{command['command']}` (exit {command['exit_code']})")
        out.append("")

    if data["subagents"]:
        out += ["## Subagents dispatched", ""]
        for agent in data["subagents"]:
            out.append(f"- `{agent['agent']}` ({agent['stop_reason']}): {agent['task']}")
        out.append("")

    if data["modes"]:
        out += ["## Mode timeline", ""]
        for mode in data["modes"]:
            label = mode["mode"] or mode["custom_type"]
            out.append(f"- {mode['timestamp']}: {label}")
        out.append("")

    if data["errors"]:
        out += [f"## Failed tool calls (last {len(data['errors'])} of {data['errors_total']})", ""]
        for error in data["errors"]:
            out.append(f"- `{error['tool']}`: {error['excerpt']}")
        out.append("")

    if full and data["assistant_texts"]:
        out += ["## Full assistant narration", ""]
        for text in data["assistant_texts"]:
            out += [demote_headings(text), "", "---", ""]

    if full and data["thinking"]:
        out += ["## Thinking", ""]
        for text in data["thinking"]:
            out += [demote_headings(text), "", "---", ""]

    out += [
        "---",
        "",
        "The above is what the session *intended*. Check the working tree "
        "(`git status`, `git log`, `git diff`) before acting on it: a session can agree a plan "
        "and write nothing.",
    ]
    return "\n".join(out)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("session", help="session file path or (partial) uuid")
    parser.add_argument("--tail", type=int, default=20, help="how many recent commands to show")
    parser.add_argument("--full", action="store_true", help="include every assistant message")
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    try:
        path = pi.resolve_session(args.session)
    except LookupError as error:
        print(error, file=sys.stderr)
        return 1

    data = collect(pi.load(path), args.tail)
    print(json.dumps(data, indent=2) if args.json else render(data, args.full))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

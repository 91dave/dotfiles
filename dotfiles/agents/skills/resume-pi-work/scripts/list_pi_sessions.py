#!/usr/bin/env python3
"""List pi coding agent sessions for a folder.

Usage:
  list_pi_sessions.py [folder] [--all] [--match TEXT] [--limit N] [--json]

Defaults to the current directory. Sessions started in a subdirectory of the
folder are included. Use --all to search every project, and --match to keep
only sessions whose transcript mentions TEXT.
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime
from pathlib import Path

import pi_session as pi

READ_CHUNK = 1 << 20


def candidate_files(folder: Path | None) -> list[Path]:
    files = pi.session_files()
    if folder is None:
        return files
    prefix = pi.encode_cwd(folder)[:-2]
    return [p for p in files if p.parent.name.startswith(prefix)]


def under(cwd: str, folder: Path) -> bool:
    if not cwd:
        return False
    target = str(folder)
    return cwd == target or cwd.startswith(target.rstrip("/") + "/")


def mentions(path: Path, needle: str) -> bool:
    lowered = needle.lower()
    overlap = len(lowered)
    carry = ""
    with path.open(encoding="utf-8", errors="replace") as handle:
        while chunk := handle.read(READ_CHUNK):
            if lowered in (carry + chunk).lower():
                return True
            carry = chunk[-overlap:]
    return False


def stamp(epoch: float) -> str:
    return datetime.fromtimestamp(epoch).strftime("%Y-%m-%d %H:%M")


def summarise(path: Path) -> dict:
    session = pi.load(path)
    ending = pi.finish_state(session)
    return {
        "uuid": session.uuid,
        "short": session.uuid[:8],
        "path": str(path),
        "cwd": session.cwd,
        "cwd_exists": bool(session.cwd) and Path(session.cwd).is_dir(),
        "title": session.title().replace("\n", " ")[:200],
        "named": session.name is not None,
        "created": session.created,
        "last_active": stamp(path.stat().st_mtime),
        "messages": len(session.messages()),
        "model": session.model,
        "thinking_level": session.thinking_level,
        "compacted": any(e.get("type") == "compaction" for e in session.entries),
        "files_touched": len(pi.written_paths(session)),
        "state": ending["state"],
        "state_detail": ending["detail"],
        "parent_session": session.parent_session,
    }


def render(rows: list[dict], show_cwd: bool) -> str:
    if not rows:
        return "No pi sessions found."
    marks = {"complete": "  ", "interrupted": "!!", "error": "XX"}
    width = max(len(r["title"][:64]) for r in rows)
    lines = []
    for row in rows:
        parts = [
            row["last_active"],
            row["short"],
            f"{row['messages']:>4} msg",
            marks.get(row["state"], "  "),
            row["title"][:64].ljust(width),
        ]
        if show_cwd:
            parts.append(row["cwd"])
        lines.append("  ".join(parts))
    legend = "\n\n!! unfinished   XX ended in error   resume with: extract_pi_session.py <id>"
    return "\n".join(lines) + legend


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", nargs="?", default=None)
    parser.add_argument("--all", action="store_true", help="search every project folder")
    parser.add_argument("--match", metavar="TEXT", help="keep sessions whose transcript mentions TEXT")
    parser.add_argument("--limit", type=int, default=20)
    parser.add_argument("--json", action="store_true")
    args = parser.parse_args(argv)

    folder = None if args.all else Path(args.folder or Path.cwd()).expanduser().resolve()
    files = candidate_files(folder)

    if args.match:
        files = [p for p in files if mentions(p, args.match)]

    files.sort(key=lambda p: p.stat().st_mtime, reverse=True)

    rows = []
    for path in files:
        if len(rows) >= args.limit:
            break
        header = pi.read_header(path)
        if header is None:
            continue
        if folder is not None and not under(str(header.get("cwd") or ""), folder):
            continue
        rows.append(summarise(path))

    if args.json:
        print(json.dumps(rows, indent=2))
    else:
        print(render(rows, show_cwd=folder is None))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

"""Read pi coding agent session files.

Session format reference: ``docs/session-format.md`` in the
``@earendil-works/pi-coding-agent`` package.
"""

from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Iterable, Iterator

NOISE_TOOLS = frozenset({"read", "ls", "grep", "find"})
WRITE_TOOLS = frozenset({"edit", "write"})
DEAD_STOP_REASONS = frozenset({"aborted", "error"})


def agent_dir() -> Path:
    return Path(os.environ.get("PI_CODING_AGENT_DIR") or Path.home() / ".pi" / "agent")


def sessions_root() -> Path:
    override = os.environ.get("PI_CODING_AGENT_SESSION_DIR")
    return Path(override) if override else agent_dir() / "sessions"


def encode_cwd(cwd: str | os.PathLike[str]) -> str:
    """Encode a working directory the way pi names its session folders.

    Mirrors ``getDefaultSessionDirPath`` in ``core/session-manager.js``. The
    encoding is many-to-one, so it must never be run in reverse: read ``cwd``
    from the session header instead.
    """
    resolved = str(Path(cwd).expanduser().resolve())
    return "--" + re.sub(r"[/\\:]", "-", re.sub(r"^[/\\]", "", resolved)) + "--"


def session_dir_for(cwd: str | os.PathLike[str], root: Path | None = None) -> Path:
    return (root or sessions_root()) / encode_cwd(cwd)


def session_files(root: Path | None = None) -> list[Path]:
    base = root or sessions_root()
    if not base.is_dir():
        return []
    return sorted(p for p in base.glob("*/*.jsonl") if p.is_file())


def session_uuid(path: Path) -> str:
    stem = path.stem
    return stem.split("_", 1)[1] if "_" in stem else stem


def resolve_session(ref: str, root: Path | None = None) -> Path:
    """Resolve a session file path or a (possibly partial) session UUID."""
    candidate = Path(ref).expanduser()
    if candidate.is_file():
        return candidate
    matches = [p for p in session_files(root) if ref in p.name]
    if not matches:
        raise LookupError(f"no pi session matching {ref!r}")
    if len(matches) > 1:
        listed = "\n  ".join(str(m) for m in matches)
        raise LookupError(f"{ref!r} matches {len(matches)} sessions:\n  {listed}")
    return matches[0]


def read_lines(path: Path) -> Iterator[dict[str, Any]]:
    with path.open(encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                entry = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(entry, dict):
                yield entry


def read_header(path: Path) -> dict[str, Any] | None:
    for entry in read_lines(path):
        return entry if entry.get("type") == "session" else None
    return None


def text_of(content: Any) -> str:
    """Flatten a message ``content`` field, which may be a string or a block list."""
    if isinstance(content, str):
        return content
    if not isinstance(content, list):
        return ""
    parts = [
        block.get("text") or ""
        for block in content
        if isinstance(block, dict) and block.get("type") == "text"
    ]
    return "\n".join(p for p in parts if p)


def blocks_of(content: Any, kind: str) -> list[dict[str, Any]]:
    if not isinstance(content, list):
        return []
    return [b for b in content if isinstance(b, dict) and b.get("type") == kind]


def role_of(entry: dict[str, Any]) -> str | None:
    message = entry.get("message")
    return message.get("role") if isinstance(message, dict) else None


@dataclass
class Session:
    path: Path
    header: dict[str, Any]
    entries: list[dict[str, Any]] = field(default_factory=list)

    @property
    def uuid(self) -> str:
        return str(self.header.get("id") or session_uuid(self.path))

    @property
    def cwd(self) -> str:
        return str(self.header.get("cwd") or "")

    @property
    def created(self) -> str:
        return str(self.header.get("timestamp") or "")

    @property
    def parent_session(self) -> str | None:
        parent = self.header.get("parentSession")
        return str(parent) if parent else None

    def last_of(self, entry_type: str, key: str) -> Any:
        value = None
        for entry in self.entries:
            if entry.get("type") == entry_type:
                value = entry.get(key)
        return value

    @property
    def name(self) -> str | None:
        for entry in reversed(self.entries):
            if entry.get("type") == "session_info":
                stated = (entry.get("name") or "").strip()
                return stated or None
        return None

    @property
    def model(self) -> str | None:
        model = self.last_of("model_change", "modelId")
        return str(model) if model else None

    @property
    def thinking_level(self) -> str | None:
        level = self.last_of("thinking_level_change", "thinkingLevel")
        return str(level) if level else None

    def messages(self, role: str | None = None) -> list[dict[str, Any]]:
        found = []
        for entry in self.entries:
            if entry.get("type") != "message":
                continue
            if role is None or role_of(entry) == role:
                found.append(entry)
        return found

    def first_prompt(self) -> str:
        for entry in self.messages("user"):
            text = text_of(entry["message"].get("content")).strip()
            if text:
                return text
        return ""

    def title(self) -> str:
        return self.name or self.first_prompt() or "(no prompt)"


def load(path: Path, active_only: bool = True) -> Session:
    """Load a session. By default only the entries pi itself would reload."""
    header: dict[str, Any] = {}
    entries: list[dict[str, Any]] = []
    for entry in read_lines(path):
        if entry.get("type") == "session" and not header:
            header = entry
            continue
        if entry.get("id"):
            entries.append(entry)
    if active_only:
        entries = apply_compaction(active_branch(entries))
    return Session(path=path, header=header, entries=entries)


def active_branch(entries: Iterable[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return root-to-leaf entries along the branch pi would reload.

    Entries form a tree: ``/tree`` appends children of earlier entries to the
    same file, so a flat read mixes in abandoned branches. pi treats the last
    entry in the file as the leaf and walks ``parentId`` back to the root
    (``buildSessionPath`` in ``core/session-manager.js``).
    """
    ordered = list(entries)
    if not ordered:
        return []
    by_id = {e["id"]: e for e in ordered if e.get("id")}
    branch: list[dict[str, Any]] = []
    seen: set[str] = set()
    current: dict[str, Any] | None = ordered[-1]
    while current is not None:
        entry_id = current.get("id")
        if entry_id in seen:
            break
        seen.add(entry_id)
        branch.append(current)
        parent = current.get("parentId")
        current = by_id.get(parent) if parent else None
    branch.reverse()
    return branch


def apply_compaction(branch: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Drop entries a compaction superseded, keeping the compaction itself."""
    last_index = None
    for index, entry in enumerate(branch):
        if entry.get("type") == "compaction":
            last_index = index
    if last_index is None:
        return branch

    compaction = branch[last_index]
    tail = branch[last_index:]
    if compaction.get("retainedTail") is not None:
        return tail

    first_kept = compaction.get("firstKeptEntryId")
    if first_kept:
        for index, entry in enumerate(branch[:last_index]):
            if entry.get("id") == first_kept:
                return branch[index:]
    return tail


def compactions(session: Session) -> list[dict[str, Any]]:
    return [e for e in session.entries if e.get("type") in ("compaction", "branch_summary")]


def tool_calls(session: Session) -> list[dict[str, Any]]:
    calls = []
    for entry in session.messages("assistant"):
        for block in blocks_of(entry["message"].get("content"), "toolCall"):
            calls.append(block)
    return calls


def tool_results(session: Session) -> dict[str, dict[str, Any]]:
    results = {}
    for entry in session.messages("toolResult"):
        message = entry["message"]
        call_id = message.get("toolCallId")
        if call_id:
            results[call_id] = message
    return results


def written_paths(session: Session) -> list[str]:
    """Deduped file paths from edit/write calls, in first-touched order."""
    seen: list[str] = []
    for call in tool_calls(session):
        if call.get("name") not in WRITE_TOOLS:
            continue
        arguments = call.get("arguments")
        path = arguments.get("path") if isinstance(arguments, dict) else None
        if path and path not in seen:
            seen.append(str(path))
    return seen


def usage_total(session: Session) -> dict[str, float]:
    total = {"input": 0, "output": 0, "cacheRead": 0, "cacheWrite": 0, "totalTokens": 0, "cost": 0.0}
    for entry in session.messages("assistant"):
        usage = entry["message"].get("usage")
        if not isinstance(usage, dict):
            continue
        for key in ("input", "output", "cacheRead", "cacheWrite", "totalTokens"):
            total[key] += usage.get(key) or 0
        cost = usage.get("cost")
        if isinstance(cost, dict):
            total["cost"] += cost.get("total") or 0
    return total


def finish_state(session: Session) -> dict[str, Any]:
    """Classify how the session ended, and flag a tool call left without a result."""
    state = "complete"
    detail = ""
    last_assistant = None
    for entry in session.messages("assistant"):
        last_assistant = entry["message"]

    if last_assistant:
        stop_reason = last_assistant.get("stopReason")
        error = last_assistant.get("errorMessage")
        if error:
            state, detail = "error", str(error)
        elif stop_reason in DEAD_STOP_REASONS:
            state, detail = "error", f"stopReason={stop_reason}"
        elif stop_reason == "toolUse":
            state, detail = "interrupted", "ended on a tool call"

    dangling = None
    calls = tool_calls(session)
    if calls:
        results = tool_results(session)
        last_call = calls[-1]
        if last_call.get("id") not in results:
            dangling = last_call.get("name")
            if state == "complete":
                state, detail = "interrupted", "last tool call has no result"

    last_entry = session.entries[-1] if session.entries else None
    if state == "complete" and last_entry and role_of(last_entry) == "toolResult":
        state, detail = "interrupted", "ended on a tool result"

    return {
        "state": state,
        "detail": detail,
        "dangling_tool": dangling,
        "stop_reason": (last_assistant or {}).get("stopReason"),
        "error_message": (last_assistant or {}).get("errorMessage"),
    }

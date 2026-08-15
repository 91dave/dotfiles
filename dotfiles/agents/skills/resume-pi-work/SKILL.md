---
name: resume-pi-work
description: >
  Pick up work that was started in the pi coding agent. Finds pi's saved sessions for a
  folder, extracts a resume brief from the right one (what was asked, what was planned,
  what changed on disk, where it stopped and why), reconciles it against the working tree,
  and carries the work on here. Use when the user says they were doing something in pi,
  asks to continue or resume pi work, refers to "the pi session" or a session id, or wants
  to know where an earlier pi run got to. Invoke manually: /resume-pi-work
argument-hint: "[what you were working on]"
---

# Resume work started in pi

Recover the intent and state of a pi coding agent session, then continue that work in this
session.

**Arguments:** `$ARGUMENTS`

The argument is a request in the user's own words, not a mode or a flag. It might be empty, a
description ("the atuin thing", "where we were fixing the ingest retry"), a session id, or a
folder. The two scripts are CLI tools; your job is to turn what was said into the right call.

Both scripts live in `scripts/` beside this file and need only Python 3.

## 1. Scope it to the current folder

Search the current working directory unless the request explicitly points somewhere else: a
path, a repo name, "across everything", "all my projects". Sessions started in a subdirectory
of the folder are already included.

- Current folder, the default: `python3 scripts/list_pi_sessions.py`
- A named folder: `python3 scripts/list_pi_sessions.py <path>`
- A repo the user named but did not path: resolve it first with `repos resolve <name>`
- Everywhere: `python3 scripts/list_pi_sessions.py --all`

## 2. Turn the words into a filter

| What the user gave you | What to run |
|---|---|
| Nothing | the bare lister, newest first |
| Distinctive topic words | add `--match "<words>"` (searches transcript text) |
| A uuid, partial uuid, or `.jsonl` path | skip to step 4 |

`--match` takes one substring, so pick the most distinctive term rather than the whole
sentence. If it returns nothing, widen with `--all --match`, then drop the match entirely.

## 3. Pick the session

Each row is `last active | short id | messages | state | title`, newest first. `!!` means the
session stopped mid-turn and `XX` means it died with an error. Those are the ones most likely
to have unfinished work in them.

Show the plausible candidates compactly. If one clearly matches what the user described, say
which and why, then use it. If several are plausible, ask rather than guess. Several sessions
minutes apart in one folder is normal, so lean on the title rather than the timestamp.

## 4. Extract the brief

```bash
python3 scripts/extract_pi_session.py <short-id> [--tail 40] [--full]
```

The brief carries the handover or compaction summaries verbatim, every user prompt in order,
the plan-sized assistant messages, the files written, the diffs applied, recent commands,
subagents dispatched, and a verdict on how the session ended.

Do not read the raw `.jsonl`. Sessions run past 500KB and are mostly tool output. If you need
one specific tool result, pull that single record by its `toolCallId`. Reach for `--full`
(every assistant message plus thinking) only when the session died mid-reasoning and the brief
does not explain what it was attempting.

## 5. Reconcile with the working tree

The brief records what the session **intended**. It is not evidence that anything shipped: a
session can agree a plan, get authorised to edit, and then die before writing a line.

In the session's folder, check `git status`, `git log` and `git diff` against the files the
brief lists. Establish which described changes actually landed. Skipping this is how the same
work gets done twice.

## 6. Report, then continue

Tell the user, briefly:

- what the session set out to do, and any constraints or decisions it recorded
- what actually landed on disk, as distinct from what was planned
- where it stopped and why, calling out a tool call that never returned
- the next concrete step

Then carry on with the work in this session. Follow `/writing-conventions` for the prose.

## Notes

- Read-only over `~/.pi/agent/sessions`. Nothing here writes to or deletes a pi session.
- Honours `PI_CODING_AGENT_DIR` and `PI_CODING_AGENT_SESSION_DIR` if pi is configured
  off the default location.
- `pi-sessions` (on PATH) is the interactive fzf picker across all projects, for when the
  user wants to browse and reopen a session in pi themselves.
- `scripts/test_pi_sessions.py` covers the parsing contract:
  `python3 -m unittest discover -s scripts`

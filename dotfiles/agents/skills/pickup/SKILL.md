---
name: pickup
description: >
  Pick up work from a handover document and continue it. Reads handover.todo.md, or a named
  .todo.md, checks it against the working tree, states the goal and the next steps, and asks
  before starting. Invoke manually: /pickup
argument-hint: "[name]"
disable-model-invocation: true
---

# Pick up a handover

Take over work described in a handover document and continue it in this session.

**Arguments:** `$ARGUMENTS`

- Empty: `handover.todo.md`.
- A name: `<name>.todo.md`, whether or not the user typed the suffix.

Look in the working directory, then at the git repo root. If the file is not there, do not
substitute a different one: say what was looked for, list any `*.todo.md` found nearby, and ask.

## 1. Read the document

The whole file, once.

## 2. Check it against reality

The document records what was true when it was written. Read-only checks, nothing deeper:

- Its age, from the `Written` timestamp in the header, against the current date and time.
- The current branch against the one recorded.
- `git status`.
- Whether the files under **Key files** still exist at those paths.

The branch diff is not worth spending before the user has approved anything.

## 3. Present it

Compactly, in chat:

- The session goal, in one line.
- The next steps as bullets, in the document's order.
- One warning line for each mismatch found above, because a stale handover otherwise sends a fresh
  agent to redo finished work: written more than 24 hours ago, giving the age; a different branch;
  a missing file.

## 4. Ask before starting

Confirm with `AskUserQuestion`: start on the first step, or adjust the plan first.

## 5. Work

Adopt the document's goal as the goal of this session. Execute the next steps rather than
re-planning from scratch, and re-derive nothing the document already states.

## Notes

- Read-only until the user approves.
- Do not modify or delete the handover file. A later `/handover` overwrites it in place.

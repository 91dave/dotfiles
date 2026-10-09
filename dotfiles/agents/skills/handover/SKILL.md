---
name: handover
description: >
  Write a handover document so a fresh agent can continue the current work. Captures the goal,
  the state as it now stands, and the next concrete steps, with no narrative of how the session
  got here. Not for capturing reusable learnings (use /write-up for that). Invoke manually: /handover
argument-hint: "[name] [what the next session should focus on] (to capture reusable learnings instead, use /write-up)"
disable-model-invocation: true
---

# Write a handover

Produce a document that lets an agent holding none of this session's context pick the work up and
carry it on.

**Arguments:** `$ARGUMENTS`

- Empty: write `handover.todo.md`.
- A single bare token with no whitespace: the filename stem, so `auth-fix` writes
  `auth-fix.todo.md`.
- Anything longer: steering, in the user's own words, for what the next session should focus on.
- The two combine, as in `auth-fix focus on the S3 flag`.

Write the file at the git repo root (`git rev-parse --show-toplevel`), falling back to the working
directory outside a repo.

## 0. Check this is the right skill

If the work is finished, or the session's value is mainly lessons learned rather than next steps,
`/write-up` fits better. Say so and ask via `AskUserQuestion`: switch to `/write-up`, or write the
handover anyway.

## 1. Fix on the goal

Restate the goal of the work in your own words rather than restating the current plan. Where the
plan in flight no longer serves that goal, the goal wins and the plan is what gets dropped. If the
argument carried steering text, treat it as the user's correction to your understanding.

## 2. State it and get approval

Before writing anything, say in chat, in a few lines: the goal for the next session, and where the
work stands now.

If the immediate goal is unclear, or "next" genuinely forks, ask via `AskUserQuestion` rather than
writing a document that guesses. Then confirm with `AskUserQuestion`: write it, or adjust first.

## 3. Check the target

If the file already exists, show its goal line and confirm overwriting it or using another name.

## 4. Write it

```markdown
# Handover: <short title>

Repo: <name> | Branch: <branch> | Work item: AB#<id> | Written: YYYY-MM-DD HH:MM

## Goal
What the next session is trying to achieve, and what "done" looks like. One or two sentences.

## State
Where the work stands now. What is on disk, what is committed, what passes and what fails.
Present tense, verified facts only, with the evidence (`path:line`, a test name, a command).

## Next steps
1. Concrete and ordered, enough to act on without re-deriving.

## Key files
- `path/to/file.cs:88` - why it matters

## Constraints
Decisions already locked in, and approaches that do not work, each with the reason.
```

Drop the work item from the header if there is not one, and drop **Constraints** entirely if there
is nothing to put in it. Take the timestamp from the system clock at the point of writing.

### Content rules

Write for an agent that has never seen this work. It cannot tell a current fact from a stale one,
so every line must be true right now.

Never write:

- How the goal, plan or approach changed. No "originally", no "we switched to", no "the plan was
  revised", no "this used to".
- A diary of the session. No "I first ran the tests, then", no tool-by-tool account.
- Status theatre. No "good progress was made", no percentages.
- A restatement of the conversation, or speculation beyond the goal.

The test for any sentence about the past: would a fresh agent do the wrong thing without it? If no,
delete it. If yes, it belongs under **Constraints**, written as a fact about the code rather than a
story about the session.

- Bad: "We tried caching in the middleware but it broke tenant resolution, so we moved the cache
  into the repository."
- Good: "The cache cannot live in middleware; tenant resolution has not run at that point."

Also:

- Separate the verified from the assumed. If something is believed but unchecked, say so, and say
  how to check it.
- Point at code rather than describing it. `path:line` beats a paragraph.
- Keep it short. A page is plenty. Length is a context cost paid by every session that reads it.

## 5. Summarise

In chat: the goal in one line, the next steps as bullets, and the file path. Do not paste the
document back.

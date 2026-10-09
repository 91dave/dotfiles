---
name: write-up
description: >
  Write up the key learnings from the current session as a reusable reference: how things
  actually work, gotchas, and decisions with their reasons. Not a plan for continuing the work
  (use /handover for that). Invoke manually: /write-up
argument-hint: "[name] [what to focus on] (for a plan to continue the work, use /handover)"
disable-model-invocation: true
---

# Write up the learnings

Produce a document that someone returning to this area later, human or agent, can read to avoid
re-learning what this session learned. It is a reference to keep, not instructions to act on.

**Arguments:** `$ARGUMENTS`

- Empty: write `write-up.md`.
- A single bare token with no whitespace: the filename stem, so `s3-flags` writes `s3-flags.md`.
- Anything longer: steering, in the user's own words, for what the write-up should focus on.
- The two combine, as in `s3-flags focus on the fallback behaviour`.

Write the file at the git repo root (`git rev-parse --show-toplevel`), falling back to the working
directory outside a repo. It is not a `.todo.md`: it is meant to be kept and may be committed.

## 0. Check this is the right skill

If the session's value is mainly unfinished work, with next steps someone should carry on now,
`/handover` fits better. Say so and ask via `AskUserQuestion`: switch to `/handover`, or write up
the learnings anyway.

## 1. Pick the learnings

Work out what a future reader of this area will need to know, rather than what happened in the
session. If the argument carried steering text, treat it as the user's correction to that.

Keep a learning only if a future reader would get something wrong, or waste real time, without
it. Facts that are obvious from the code, or only true of this session, do not qualify.

## 2. State them and get approval

Before writing anything, list the proposed learnings in chat, one line each, plus the next step if
there is one. Then confirm with
`AskUserQuestion`: write it, or adjust first.

## 3. Check the target

If the file already exists, show its title and summary and confirm overwriting it or using another
name.

## 4. Write it

```markdown
# Write-up: <topic>

Repo: <name> | Written: YYYY-MM-DD

## Summary
What this covers and why it matters. One or two sentences.

## Learnings
### <the learning, as a short claim>
The fact, the evidence (`path`, symbol, command), and why it matters.

## Decisions
- <decision>, because <reason>. Alternatives rejected, and why.

## Gotchas
- <trap>: the symptom, the cause, and how to avoid or fix it.

## References
- `path/to/file` or a link: what it shows.

## Open questions
- A belief not yet verified, and how to check it.

## Next steps
- The agreed or clearly indicated fix or follow-up, and the learning it comes from.
```

Drop any section with nothing to put in it. Take the date from the system clock.

**Next steps** is optional. Include it only when the session settled on a fix or follow-up, or the
learnings point at one unambiguously. Keep it to the what and why; do not speculate, and do not
turn it into a step-by-step plan. If it would need one, suggest `/handover` alongside the write-up.

### Content rules

Write for a reader who has never seen this session and may arrive months later. Every line must
be a fact about the system, not a story about the session.

Never write:

- A diary of the session. No "I first ran the tests, then", no tool-by-tool account.
- How the plan or approach changed. No "originally", no "we switched to".
- Status theatre. No "good progress was made".
- Session-specific trivia: temp paths, one-off IDs, the state of a branch.

- Bad: "We tried caching in the middleware but it broke tenant resolution, so we moved the cache
  into the repository."
- Good: "The cache cannot live in middleware; tenant resolution has not run at that point."

Also:

- Separate the verified from the assumed. Anything believed but unchecked goes under
  **Open questions**, with how to check it.
- Point at code rather than describing it. Prefer stable anchors (file and symbol names) over
  line numbers, which drift over a write-up's longer shelf life.
- Generalise where it helps reuse: state the rule, then the instance that showed it.
- Where a learning would be better placed somewhere permanent (agent instructions, a skill, a
  README), add a one-line suggestion beneath it. Do not edit those places.
- Keep it short. Length is a cost paid by every reader.

## 5. Summarise

In chat: the topic in one line, the learnings as bullets, any next step, any suggested permanent
homes, and the file path. Do not paste the document back.

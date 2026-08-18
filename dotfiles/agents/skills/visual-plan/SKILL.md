---
name: visual-plan
description: "Render an implementation plan as a reviewable document — mermaid diagrams, file trees, highlighted code, and a typed task breakdown — served on localhost for browser review. Use when a plan needs to be seen and approved rather than read as chat prose, or alongside /plan-tasks as the draft surface before tasks are written to Azure DevOps. Everything is local. Invoke manually: /visual-plan <request or AB#12345>"
argument-hint: "<request> [AB#<backlog-item-id>]"
---

# Visual Plan

Turn the plan you would normally write as chat prose into a document someone can
actually review: mermaid diagrams, a file tree of what the change touches,
syntax-highlighted code, and an ordered task breakdown. Written as MDX, rendered
locally, served on `127.0.0.1`.

Nothing is published, shared, or written to any hosted service.

## Read the situation

Two independent questions, answered before anything else. State both in one line
so the user can correct you.

### Are you in plan mode?

This decides where the plan is written and how it is approved. Never switch mode
either way: adapt to where you already are.

| | In plan mode | Outside plan mode |
|---|---|---|
| Plan file | the harness plan file, `~/.claude/plans/<name>.md` | `.plans/<slug>/plan.mdx` |
| Slug | handed to you; do not invent one | derive it, or reuse `/plan-tasks`'s plan name |
| Read-only research | enforced by the harness | your responsibility |
| Approval | `ExitPlanMode` | ask in chat |
| `--out` | **never** — it writes a file | fine |

**Plan mode works, and is the better host.** The MDX format is unaffected by the
`.md` extension. Serving only reads, so it does not breach the plan-mode
contract; `--out` is the one code path that writes, which is why it is barred
there. Starting the server is a `Bash` call and may raise a permission prompt
depending on the user's setup — that is expected, not a failure.

`ExitPlanMode` echoes the raw file to the terminal, so component tags appear
there as literal text. That is cosmetic. The browser is the review surface, so do
not strip components to make the echo tidier.

### What is the plan for?

| Signal | Situation |
|---|---|
| `/plan-tasks` in the invocation, or an `AB#` alongside it | **Draft surface** for `/plan-tasks` Step 5 |
| a request and nothing else | **Standalone**: the MDX is the plan |

The six steps below are the same in every combination. Only the plan's location,
where its content comes from, and what happens after approval differ.

## Workflow

1. **Research first.** Read the real files, actions, schema and symbols. Name
   actual paths and types rather than inventing them; check what already exists
   before proposing anything new. Delegate wide exploration to a sub-agent when
   the surface is large. Make no source edits.
2. **Ask before you compile.** Batch two to four high-leverage clarifying
   questions through the host's ask-user-question flow. Ask only what would
   change the design and cannot be resolved from the code. Everything still open
   after that is stated in the plan as an explicit assumption with a
   recommendation, not left implicit.
3. **Settle the plan file.** In plan mode it is the harness plan file, already
   named — use it and do not invent a slug. Outside plan mode, pick a short
   kebab-case slug of three to five words and use `.plans/<slug>/plan.mdx`, or
   reuse `/plan-tasks`'s plan name verbatim when it has one.
4. **Write the MDX.** See `references/components.md` for the component set and
   `references/document-quality.md` for the bar the document has to clear. In
   plan mode the harness file is the only file you may write.
5. **Serve it and hand off.**

   ```bash
   node <skill-dir>/lib/serve.mjs <plan-file-or-dir>
   ```

   Print the URL it returns, say in a line or two what the plan covers, and ask
   for approval or amendments. **Do not call `ExitPlanMode` on this turn**: the
   dialog covers the terminal, and the URL is what the user needs first. Run the
   server in the background so the session stays usable, and keep it running while
   the user reads — stopping it kills the URL, though not the page already open in
   their browser.

   It serves on `7842` and stops itself after 30 minutes with no requests, so
   one plan at a time needs no cleanup. If that port is taken it warns and uses
   a free one, which usually means an earlier plan is still being served.

6. **Iterate, and offer the gate every turn.** Amendments are edits to the same
   file. The server renders per request, so the user reloads to see them; no
   rebuild, no restart. Edit the block that changed, never regenerate the file.

   In plan mode, from the user's first reply onward, **end every turn by calling
   `ExitPlanMode`**: after making a requested change, after answering a question,
   after any reply at all. Repeat the URL as the last line before the call so the
   link survives the dialog. Declining is an ordinary "not yet" and costs the user
   nothing, while approving is the only route to starting work, so keep the door
   open on every turn rather than waiting for a signal you have to guess at. The
   served plan is what they approve.

   The exception is an explicit hold: the user says they are still reading, or asks
   you to wait. Reply and stop, then resume the cadence on their next message.

   Approval ends plan mode but does not stop the server. Leave it serving unless
   the user is finished with the page.

Outside plan mode, add `.plans/` to the repo's `.gitignore`. Plans are working
artefacts. Azure DevOps is the record. In plan mode the harness file is the
artefact, and no copy is written into the repo.

## Alongside `/plan-tasks`

Expected invocation:

```
/plan-tasks AB#12345 /visual-plan
```

| Step | Owner |
|---|---|
| 1-4 understand, confirm the backlog item, derive the plan name, design the typed tasks | `/plan-tasks` |
| 5 present the draft for approval | **this skill** |
| 6 write parent notes and child Tasks to AzDO, set Type and StackRank | `/plan-tasks` |

**Run this in plan mode.** `/plan-tasks` Step 2 says the requirements-in-BLI
context does its design work in plan mode with `ExitPlanMode` as the Step 5 gate.
Follow that as written: research under the harness gate, write the MDX to the
harness plan file, serve it, and let `ExitPlanMode` be the approval. Step 6 then
writes to Azure DevOps once you are out.

Rules for the seam:

- **Render what will actually be written.** The `<Tasks>` items carry the fields
  from `plan-tasks/references/templates.md`, in execution order, including the
  regression-first Test task and any Documentation task. Approving the rendered
  plan must mean approving what Azure DevOps receives. Read that file; never
  restate it here.
- **Never write to Azure DevOps.** On approval, hand back. `/plan-tasks` Step 6
  does the writing, one child Task at a time, and owns Type and StackRank.
- **`AB#12345` is correct in the plan**, because the plan is not AzDO content.
  Inside AzDO content `/plan-tasks` requires `#12345`.

## Standalone

Plan from the request and run the same six steps, ending at approval. Here the
MDX is not a rendering of something held elsewhere: it is the plan, and the only
artefact. In plan mode that is the harness file; outside it, derive a slug and
use `.plans/<slug>/plan.mdx`.

Include a `<Tasks>` block only when the work genuinely has an ordered breakdown.
A design note or an investigation write-up does not need one.

## Gate thoughtfully

A visual plan is for when someone needs to see, compare or approve a direction
before code, or when the shape of the change is easier to grasp as a diagram or a
file tree than as prose. That includes modest work.

Skip it for trivial, unambiguous changes — typos, one-line fixes, anything whose
diff you could describe in a sentence. Just make the change. Never pad a plan
with filler and never ship a single-step plan.

## Writing the plan

- **Lead with the outcome.** State the objective, what done means, the scope and
  non-goals, then the approach and the decisions behind it.
- **Decide the hard-to-reverse things first.** Wire format, public identifiers,
  data-model shape, auth and ownership boundaries. Get those right in the plan
  even when most of the work ships later, and say what is deferred.
- **Ground every step.** Name real files, symbols and data shapes. For each step,
  say what it reuses before what it adds.
- **Stand alone.** A reader who was not in the chat should understand it. No
  "as discussed above", "this revision", or "unlike the previous version".
- **The plan is the approval gate.** Presenting it and asking for sign-off is the
  approval step. Do not ask a separate "does this look good?" afterwards.

## Commands

Run with `node`; there is nothing to install.

| Command | Purpose |
|---|---|
| `node <skill-dir>/lib/serve.mjs ~/.claude/plans/<name>.md` | Serve the harness plan file, in plan mode |
| `node <skill-dir>/lib/serve.mjs .plans/<slug>` | Serve a plan folder, outside plan mode |
| `... <target> --port 8123` | Override the default `7842` |
| `... <target> --idle 60` | Idle minutes before it stops; `0` runs until stopped |
| `... <target> --out plan.html` | Write a standalone file to share or attach. **Writes to disk, so never in plan mode** |
| `node --test <skill-dir>/lib/render.test.mjs` | Self-check after changing the renderer |

The target may be a `.md` file, a `.mdx` file, or a directory containing
`plan.mdx`. Everything except `--out` only reads.

Servers stop themselves after 30 idle minutes, so they do not accumulate across
sessions. Do not hunt down and kill old ones by process name: that pattern
matches other sessions' servers and other people's work. If a port genuinely
needs freeing, find the listener with `ss -tlnp` and stop that one process.

The MDX is evaluated to render it, so only ever point these at a plan this skill
produced. Never at a file from an untrusted source.

## References

- `references/components.md` — the component set and how to author each one.
- `references/document-quality.md` — the quality bar for the document itself.
- `references/exemplar.md` — a worked example, and the anti-patterns.

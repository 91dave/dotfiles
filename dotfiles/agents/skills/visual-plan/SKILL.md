---
name: visual-plan
description: "Render an implementation plan as a reviewable document — mermaid diagrams, file trees, highlighted code, and a typed task breakdown — served on localhost for browser review. Use when a plan needs to be seen and approved rather than read as chat prose, or alongside /plan-tasks as the draft surface before tasks are written to Azure DevOps. Everything is local. Invoke manually: /visual-plan <request or AB#12345>"
argument-hint: "<request> [AB#<backlog-item-id>]"
---

# Visual Plan

Turn the plan you would normally write as chat prose into a document someone can
actually review: mermaid diagrams, a file tree of what the change touches,
syntax-highlighted code, and an ordered task breakdown. Written as MDX to
`.plans/<slug>/`, rendered locally, served on `127.0.0.1`.

Nothing is published, shared, or written to any hosted service.

## Do not invoke inside plan mode

This skill writes files and starts a server. Plan mode blocks both. If you are in
plan mode when the skill is invoked, leave it first.

That includes the `/plan-tasks` case below: `/plan-tasks` Step 2 says to do the
design work in plan mode with `ExitPlanMode` as the Step 5 gate. When
`/visual-plan` is part of the invocation, **skip plan mode entirely**. The served
plan is the gate, and approval comes back through the TUI.

The read-only discipline still applies, it is just carried here rather than by
the harness: research without editing, and write nothing outside
`.plans/<slug>/` until the plan is approved.

## Read the situation

Work out which of these you are in before doing anything else, and say which in
one line so the user can correct you:

| Signal | Situation |
|---|---|
| `/plan-tasks` in the invocation, or an `AB#` alongside it | **Draft surface** for `/plan-tasks` Step 5 |
| a request and nothing else | **Standalone**: the MDX is the plan |

Steps 1 to 6 below are the same either way. Only where the content comes from,
and what happens after approval, differ.

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
3. **Pick the slug.** Short, kebab-case, three to five words. In `/plan-tasks`
   mode use the plan name it already derived, verbatim.
4. **Write `.plans/<slug>/plan.mdx`.** See `references/components.md` for the
   component set and `references/document-quality.md` for the bar the document
   has to clear.
5. **Serve it and hand off.**

   ```bash
   node <skill-dir>/lib/serve.mjs .plans/<slug>
   ```

   Print the URL it returns and ask for approval or amendments. Run it in the
   background so the session stays usable, and keep it running while the user
   reads — stopping it kills the URL.

6. **Iterate.** Amendments are edits to `plan.mdx`. The server renders per
   request, so the user reloads to see them; no rebuild, no restart. Edit the
   block that changed, never regenerate the file.

Add `.plans/` to the repo's `.gitignore`. Plans are working artefacts. Azure
DevOps is the record.

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

Plan from the request. Derive the slug yourself, run the same six steps, end at
approval. Here the MDX is not a rendering of something held elsewhere: it is the
plan, and the only artefact.

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
| `node <skill-dir>/lib/serve.mjs .plans/<slug>` | Render and serve; prints the URL |
| `node <skill-dir>/lib/serve.mjs .plans/<slug> --port 8123` | Fixed port instead of a free one |
| `node <skill-dir>/lib/serve.mjs .plans/<slug> --out plan.html` | Write a standalone file to share or attach |
| `node --test <skill-dir>/lib/render.test.mjs` | Self-check after changing the renderer |

The MDX is evaluated to render it, so only ever point these at a plan folder this
skill produced. Never at an MDX file from an untrusted source.

## References

- `references/components.md` — the component set and how to author each one.
- `references/document-quality.md` — the quality bar for the document itself.
- `references/exemplar.md` — a worked example, and the anti-patterns.

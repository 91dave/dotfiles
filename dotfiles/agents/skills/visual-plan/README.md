# /visual-plan

Turn ordinary implementation plans into rich visual review surfaces, entirely on
your own machine.

`/visual-plan` turns the plan an agent would normally write in chat into a
human-optimized MDX document written to `.plans/<slug>/` and served for review.
Instead of a long wall of prose, reviewers get components built for
understanding: architecture diagrams, wireframes, file maps, annotated code,
OpenAPI-style API specs, visual schema maps, and open questions.

It solves for plans that are too important to bury in chat. The output is
scannable and intuitive enough for a human to approve before code changes start.

## What It Does

- Grounds plans in real repo files, schemas, actions, and symbols.
- Chooses the right visual surface: document-only, or a wireframe canvas for
  UI work.
- Uses MDX and custom components for diagrams, UI states, API specs, schema
  maps, diffs, code annotations, and reviewer questions.
- Renders the result as a reviewable document instead of inline chat Markdown.
- Keeps the plan as the approval gate before source edits begin.

## When To Use It

Use it for multi-file, ambiguous, risky, architecture-heavy, data-heavy, or
UI-heavy work where the wrong direction would be expensive. It is also useful
when a pasted text plan needs a richer review surface.

Skip it for trivial fixes, single-line changes, or anything whose diff is easier
to review than a plan.

## How It Runs

Everything is local. The plan is authored as MDX in `.plans/<slug>/` and
rendered through a localhost bridge started by the Agent-Native CLI:

```sh
npx @agent-native/core@latest plan blocks --out plan-blocks.md
npx @agent-native/core@latest plan local init --title "My plan" --kind plan --dir .plans/my-plan
npx @agent-native/core@latest plan local check --dir .plans/my-plan
npx @agent-native/core@latest plan local serve --dir .plans/my-plan --kind plan --open
```

Requirements: Node and `npx`. No account, no sign-in, no MCP connector, no API
key.

**"Local" means plan content never leaves the machine — not that it is
offline.** The CLI comes from npm, the block catalog is a public schema-only
route, and `plan local serve` opens the Plan renderer hosted at
`plan.agent-native.com`, which reads your MDX over the loopback bridge in the
browser. Nothing is written to their database and there is no share link. For a
genuinely offline render, run a local Plan app and pass
`--app-url http://localhost:8096`. `references/local-workflow.md` sets out the
boundary in full.

## Provenance

This is a local-only fork of the `visual-plan` skill from
[BuilderIO/skills](https://github.com/BuilderIO/skills/tree/main/skills/visual-plan),
built on [Agent-Native](https://github.com/BuilderIO/agent-native/).

Removed from the original:

- The hosted Plan MCP connector and its fourteen tools (`create-visual-plan`,
  `update-visual-plan`, `get-plan-feedback`, `export-visual-plan`, and the rest).
- OAuth setup, per-client reconnect steps, and auth error handling.
- Visibility, sharing, and hosted comment/anchor handling.
- Prototype-first and design-first modes, which needed renderer features beyond
  static wireframes.

Kept and retargeted: the plan-discipline rules and the wireframe, canvas,
document-quality, and exemplar guidance, which were always renderer-agnostic and
are the bulk of the skill's value.

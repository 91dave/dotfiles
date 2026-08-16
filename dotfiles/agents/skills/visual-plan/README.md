# /visual-plan

Render an implementation plan as a document someone can actually review, entirely
on your own machine.

The agent writes the plan as MDX to `.plans/<slug>/`, renders it, and serves it on
`127.0.0.1`. You review in the browser and approve or ask for changes in the
terminal.

## What you get

- **Mermaid diagrams** for architecture, data flow and state.
- **File trees** showing what the change touches, with change badges and notes.
- **Syntax-highlighted code** with filename headers.
- **A typed task breakdown** with dependencies, and a dependency graph derived
  from them.
- Prose, headings, tables and lists, because it is markdown underneath.

## Running it

Nothing to install beyond Node.

```sh
node lib/serve.mjs .plans/my-plan              # render and serve, prints the URL
node lib/serve.mjs ~/.claude/plans/foo.md      # a file works too
node lib/serve.mjs .plans/my-plan --port 8123  # fixed port
node lib/serve.mjs .plans/my-plan --out plan.html
node --test lib/render.test.mjs                # after changing the renderer
```

The target can be a `.md` file, a `.mdx` file, or a directory containing
`plan.mdx`. The server renders on every request, so editing the source and
reloading is the whole iteration loop. `--out` writes a standalone file you can
attach to a work item or email.

**In plan mode** the skill writes to the harness plan file rather than the repo,
serves that, and uses `ExitPlanMode` as the approval gate. Serving only reads, so
it does not breach the plan-mode contract; `--out` is the one thing that writes,
so it is not used there. Plan mode is the better host, because the read-only
research gate and the approval gate are both enforced rather than self-imposed.

## How local is it

Plans are never uploaded, shared, or written to any hosted service. There is no
account, no sign-in, and no MCP connector.

One qualifier, stated plainly: **mermaid is loaded from a CDN**, because the
bundle is 3.4 MB and too large to vendor sensibly. That script tag is emitted
**only when a plan actually contains a diagram**, is pinned to an exact version,
and carries a Subresource Integrity hash so the browser refuses to run
unexpected bytes.

A plan with no diagrams has zero external URLs and works with the network
disabled. A plan with diagrams degrades to readable diagram source if the CDN is
blocked, rather than showing an empty box.

`assets/LICENSES.md` covers the vendored libraries and how to regenerate the
integrity hash on a version bump.

## Alongside /plan-tasks

The main use is as the approval surface for `/plan-tasks`:

```
/plan-tasks AB#12345 /visual-plan
```

`/plan-tasks` designs the typed task breakdown, `/visual-plan` renders it for
review, and on approval `/plan-tasks` writes the child Tasks to Azure DevOps.
This skill never writes to Azure DevOps itself.

Invoked on its own it plans from the prompt, and the MDX is the plan artefact in
its own right.

## Provenance

A local-only fork of the `visual-plan` skill from
[BuilderIO/skills](https://github.com/BuilderIO/skills/tree/main/skills/visual-plan),
built on [Agent-Native](https://github.com/BuilderIO/agent-native/). Both MIT.

The original published through a hosted Plan app over an MCP connector. What
survives is the planning discipline and the document quality bar; the renderer is
new and local.

Removed along the way: the MCP connector and its fourteen tools, OAuth and
per-client reconnect handling, hosted comments and comment anchoring, sharing and
visibility controls, the wireframe canvas and prototype modes, and the in-document
question form. Clarifying questions are now asked in the terminal before the plan
is written, which is a faster loop and loses nothing.

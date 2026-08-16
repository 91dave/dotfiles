---
name: visual-plan
description: >-
  Turn ordinary text plans into rich interactive visual plans with diagrams,
  file maps, annotated code, wireframes, and open questions. Writes a local
  plan folder and serves it for review; nothing is published or shared.
---

# Visual Plans

Structured visual planning for coding agents. Build the plan you would normally
write in Markdown, but as a scannable document with editable blocks mixed in:
inline diagrams, code snippets, open questions, and an optional top wireframe
canvas. Architecture and backend plans stay document-only; UI and product plans
start with the top canvas (the Visual Surface Choice section owns that rule).

`/visual-plan` is the entry point. Choose the review mode from the task:
document-first when the work is architecture, backend, data, refactor, or API;
UI-first when the work is primarily product UI and review should start with
screens. When a Claude Code, Codex, Markdown, or pasted plan already exists,
`/visual-plan` uses that source plan as the starting point and builds the review
surface from it instead of starting over.

Everything is local. The plan is written to `.plans/<slug>/` as MDX and rendered
through a localhost bridge. There is no account, no publish, and no share link.
`references/local-workflow.md` states exactly what "local" does and does not
cover.

## When To Use

Create or adapt a visual plan whenever the plan would be better as a reviewable
artifact than a chat paragraph. This includes modest work such as a single UI
surface with states, a small workflow, a before/after product change, or a
component/API/data-shape decision that needs alignment, plus larger multi-file,
ambiguous, long-running, risky, or UI-heavy work. Use it when architecture /
data flow / UI direction / options / open questions would benefit from inline
diagrams or structured blocks, when the user needs to react to a direction
before you implement, or when an existing text plan needs a richer review
surface.

## Plan Discipline

- **Gate thoughtfully.** A visual plan is a richer review surface, not only a
  tool for giant projects. Use it when the user needs to see, compare, comment
  on, or approve a direction before code, even for a modest UI/state/workflow
  change. Skip it for truly trivial, unambiguous work — typos, one-line fixes, a
  single well-specified function, anything whose diff you could describe in one
  sentence — and just make the change. Never pad a plan with filler and never
  ship a single-step plan.
- **Research before you draft.** Read the real files, actions, schema, and
  patterns first; name actual files, symbols, and data shapes instead of
  inventing them. Check existing `actions/` before proposing endpoints and prefer
  named client helpers over raw fetch. Delegate wide exploration to a sub-agent.
  Lead with reuse: for each step, name what it reuses — existing actions, schema,
  components, helpers — before what it adds, so the plan explains the genuinely new
  delta instead of redescribing what already exists.
- **Decide the hard-to-reverse bets first.** For non-trivial backend, data, or API
  work, sketch where the feature is headed, then call out the decisions that are
  expensive to undo once data or callers depend on them — wire format, public ids,
  data-model shape, auth and ownership boundaries — and get those right in the plan
  even if most of the feature ships later. Then scope to the smallest first cut that
  proves the approach without foreclosing it, stating both what is in and what is
  explicitly deferred.
- **Keep examples at the right altitude.** When the user's idea is a broad
  framework, product, or operating-model change, do not collapse it into the
  first concrete example, provider, or sync path they mention. Separate the core
  abstraction from motivating examples and app/provider adapters. Use examples
  to make the plan legible, but label them as examples unless they are the whole
  requested scope.
- **Write standalone plans.** If the user pasted, referenced, or already has a
  Codex / Claude Code / Markdown plan, treat it as source material, but rewrite
  the plan as a clean standalone proposal. Preserve the source plan's useful
  intent and codebase facts, label inferred visuals as inferred, and avoid
  revision language such as "preserve the prior plan", "do not drop the old
  idea", "unlike the previous version", or "this revision changes...". A reader
  who never saw the chat or earlier drafts should understand the plan.
- **Make the first read concrete.** If the plan is meant to be read by someone
  outside the chat, or if the concept is abstract, lead near the top with
  one concrete product example before mode tables, architecture, or roadmaps. For
  UI-capable concepts, that usually means a top-canvas app state that shows the
  real user workflow in product terms. Do not rely on phrases that only make
  sense in conversation, and do not frame the plan as "not the old idea"; state
  the positive model directly.
- **Planning is read-only.** Make no source edits while building or reviewing the
  plan. The plan folder under `.plans/` is the one thing you write. Start editing
  source only after the user approves the direction.
- **Clarify vs. assume.** Do not ask how to build it — explore and present the
  approach and options in the plan. Ask a clarifying question only when an
  ambiguity would change the design and you cannot resolve it from the code; use
  the host agent's normal ask-user-question flow and batch 2-4 high-leverage
  questions before finalizing. Otherwise state the assumption explicitly and
  proceed, and keep anything unresolved in the plan's single bottom
  `question-form` Open Questions block. For complex plans, do a final
  open-question pass before handoff: if a decision would affect architecture,
  scope, UX, data shape, or rollout, either decide it in the plan with rationale
  or put it in that bottom form with a recommended default.
- **The plan is the approval gate.** After surfacing it, ask the user to review
  and approve before you write code, and name which files/areas the work touches.
  Presenting the plan and requesting sign-off is the approval step — do not ask a
  separate "does this look good?" question.
- **The document is the source of truth, not the chat.** When scope shifts,
  update the MDX rather than only changing course in chat, and make the updated
  document stand alone. Do not describe the update as a correction to an earlier
  draft inside the plan itself. Re-read the approved plan before major steps.

## The Deliverable Is A Served Plan — Never Inline

The deliverable is ALWAYS a checked, served plan folder and its bridge URL. Do
not hand the plan to the user as Markdown prose, an ASCII sketch, a table, or a
fenced "wireframe" in chat. The entire value is the scannable, inspectable
document; an inline summary is the thing a visual plan replaces, not a degraded
version of one.

Nothing about this requires a connector, an account, or a network service you
have to authenticate against, so there is no auth wall to fall back from. If the
`npx @agent-native/core@latest` CLI itself fails, report the actual error and
stop — do not improvise an inline plan in its place.

## Core Workflow

Read `references/local-workflow.md` before the first command; it is the single
source of truth for the CLI, the folder layout, the browser gotchas, and the
precise boundary of what stays on the machine.

1. Follow the host agent's normal planning flow: inspect the codebase, delegate
   wide exploration when useful, gather the info needed, and ask native
   clarifying questions as needed before generating the plan. If a source plan
   already exists, gather its exact text from the user's paste, a referenced
   file, or recent visible agent context; do not invent source text.
2. Fetch the authoritative block catalog and read it — do not author from
   memorized tags:

   ```bash
   npx @agent-native/core@latest plan blocks --out plan-blocks.md
   ```

3. Scaffold the folder, then author the MDX:

   ```bash
   npx @agent-native/core@latest plan local init --title "<Title>" --kind plan --dir .plans/<slug>
   ```

   For UI/product plans, compose `canvas.mdx` first with the primary wireframes
   and annotated states, then write `plan.mdx` with native blocks (see
   `references/canvas.md` and `references/document-quality.md`). For broad
   product architecture plans with a user-facing implication, add a concrete
   "what this looks like in the app" visual before the abstract architecture or
   mode tables. Keep the document close to the standalone Markdown plan the
   agent would normally output. If an existing plan was provided, carry forward
   the right facts and decisions without referring to the previous draft or
   explaining how this version differs. For non-visual plans, skip the canvas
   entirely (Visual Surface Choice below owns the rule) and put `diagram`,
   `data-model`, `api-endpoint`, `diff`, `file-tree`, `code`, and
   `annotated-code` blocks directly next to the relevant prose.

   Wide document layout is renderer-owned and intentionally allowlisted: only
   literal code-review surfaces (`diff`, `annotated-code`) and `tabs` blocks
   with vertical orientation or diff-like children break out wider than prose.
   Keep `api-endpoint`, `openapi-spec`, `data-model`, `json-explorer`,
   `wireframe`, question, and `custom-html` blocks in normal document flow unless
   their own renderer says otherwise.

4. Check, then serve:

   ```bash
   npx @agent-native/core@latest plan local check --dir .plans/<slug>
   npx @agent-native/core@latest plan local serve --dir .plans/<slug> --kind plan --open
   ```

   `check` is a lint over a subset of the renderer schema — green is not proof
   the plan renders. Look at the served page.

5. Surface the bridge URL in chat and ask the user to review. Always include the
   actual URL so the next step is a click in CLI or other text-only hosts. When
   the host exposes an embedded browser/preview panel and a tool can open
   arbitrary URLs there, open the URL automatically for convenient review — a
   convenience and smoke test, never the only handoff. For high-stakes plans
   (architecture, backend, data, multi-file, or risky), also kick off the
   self-review pass in **Self-Review Before Handoff** while the user reads,
   instead of blocking the handoff on it.
6. Iterate on feedback by editing the MDX directly and rerunning `plan local
   check`. The running bridge reads from disk, so the user reloads to see the
   change. Edit surgically; never regenerate the folder to change one block.
7. Before final handoff on a high-stakes plan, run `plan local verify --dir
   .plans/<slug> --kind plan` and fix any schema-path issues it reports.

## Self-Review Before Handoff

This adversarial self-review pass is opt-in, not default: run it only for
high-stakes plans — irreversible migrations, security-sensitive work, or when
the user explicitly asks for extra rigor — and skip it otherwise. It roughly
doubles the cost of plan generation, so the default for small, UI-only,
single-decision, or ordinary plans is to skip it, not to run it. Keep the pass
cheap and non-blocking when it does run:

- **Surface the plan first, review concurrently.** Post the link and let the user
  start reading, then run the review in parallel — never make the user wait on it.
- **Review the written plan; do not re-research.** Critique the plan text and its
  own blocks. The grounding was already done while drafting, so the review checks
  the output instead of re-exploring the repo.
- **Spawn one skeptical reviewer** whose only job is to find what is weak, missing,
  or wrong — not to praise. Point it at: hard-to-reverse decisions made implicitly
  or not at all (wire format, public ids, data-model shape, auth, ownership); steps
  not anchored in real files or symbols; a menu of options where the plan should
  commit to one; obvious missing decisions ("what happens when X?", "why not Y?");
  and padding or single-step filler.
- **Fix vs. ask.** Apply clear-cut fixes yourself by editing the MDX — vague
  non-goals, unanchored claims, an obvious missing decision. Route genuine
  judgment calls back to the user instead: add them to the bottom `question-form`
  Open Questions block or batch them into the normal ask-user-question flow. Do
  not silently decide them.
- **Do not surprise the user mid-read.** On a large plan, apply the edits before
  the page loads; otherwise note briefly that a self-review is running so the
  plan changing under them is expected. When you next respond, summarize what the
  review changed and what it surfaced for the user to decide.

## Visual Surface Choice

Choose the surface before authoring the plan or after reading the source plan. Do
not add visual chrome by default:

For UI/product plans, the top canvas is usually the primary review surface. Put
the first meaningful wireframes there, not buried as document-body blocks. Use
multiple canvas artboards when states matter, such as the default view, an
overflow menu or popover, a side panel, loading, or error. Put short annotations
beside frames with `targetId` plus `placement`; keep implementation details,
tradeoffs, file maps, data contracts, risks, and verification in the document
body below the canvas.

When the user asks for a flow, storyboard, journey, wireframe, canvas, or "what
this looks like", treat that as a canvas-first request. Make one artboard per
user-visible state, connect only adjacent transitions, and use short canvas
annotations for the product notes. Do not substitute a document-body `diagram`
block for the requested storyboard just because HTML diagrams are faster to
write; diagrams belong below the canvas for backend mechanics, architecture, or
data-flow explanation.

Keep product wireframes and explanatory/meta diagrams separate. Start with pure
screens that look like the app state under discussion, without callout prose or
architecture notes embedded inside the UI. Put arrows, labels, contracts, data
flow, and mode explanations in separate annotations, separate canvas diagrams,
or the document body.

When the plan touches an existing app, inspect the current shell/components
before drawing. The first artboard should look like the real app at the same
density: existing sidebars, toolbar placement, overflow menus, app chrome, and
framework agent chrome stay in their real places. Model secondary surfaces as
separate states, such as a top-right overflow popover, sheet, panel, loading
state, or separate AgentSidebar, rather than inventing a permanent inspector or
folding framework chrome into the product UI.

- **No visual surface** for architecture-only, backend-only, data migration,
  copy-only, or otherwise non-visual plans. Do not use the top canvas for
  architecture diagrams, dependency maps, file plans, API contracts, or
  data-flow-only reviews. Use a strong document with local inline diagrams
  only when relationships need a visual explanation, usually one spatial diagram
  per recommendation or decision. Prefer grouped regions, layers, quadrants,
  matrices, or before/after panels over a single-axis chain unless the
  relationship is truly sequential.
- **Canvas** for a static screen, a before/after comparison, a component state,
  a small popover, a multi-step UI flow, or a visual direction the reviewer needs
  to see. Put those wireframes in `canvas.mdx` as artboards, one per
  user-visible state, and connect only adjacent transitions.
- **Default to wireframes.** A clean, minimal UI, a high UX bar, or references
  to Linear/Vercel describe the content and density bar; they do not request
  full-fidelity design mode. Use renderer-owned wireframes throughout. This keeps
  every canvas screen inspectable and its full content visible. If the user asks
  for branded, pixel-accurate, production-like visual design, say plainly that
  this skill produces wireframes and offer the closest wireframe representation
  rather than faking fidelity with hand-written CSS.

## Wireframe quality — read `references/wireframe.md`

Wireframes must meet a strict quality bar — full-width chrome, pinned bottom
bars, real product content, before/after comparability, the right `surface`
preset, `--wf-*` tokens instead of hex, and no `<html>`/`<style>`/font tags.
Before authoring ANY wireframe / `<Screen>` / `WireframeBlock`, READ
`references/wireframe.md` in this skill directory — it is the single source of
truth for HTML wireframe quality. Do not author wireframes from memory.

## Canvas — read `references/canvas.md`

The canvas is the single source of truth for static UI mockups: the `surface`
locks each artboard's footprint, mixed surfaces lay out in lanes, annotations
are plain-text designer notes anchored by `targetId`/`placement`, and edits are
surgical. Before authoring or editing ANY canvas, artboard, or annotation, READ
`references/canvas.md` in this skill directory — it is the single source of truth
for canvas/artboard mechanics. Do not author canvas layouts from memory.
Canvas artboards use the same HTML wireframe path as document-body
`WireframeBlock` screens: author `<Screen surface="..." html={...} />` with a
semantic HTML fragment. Do not author fresh kit-tree children such as
`<FrameScreen>`, `<Card>`, `<Row>`, or `<Btn>` inside canvas `<Screen>` tags;
those are legacy compatibility markup for old plans and produce brittle canvas
layouts.

## Document quality — read `references/document-quality.md`

The document is a serious technical plan, not marketing: outcome-first,
prose-first, self-contained, built from the right native blocks, with open
questions in a single bottom `question-form` and a pre-handoff visual check.
Before authoring the plan document, READ `references/document-quality.md` in this
skill directory — it is the single source of truth for the document quality bar.
Do not write the document from memory.

## Good vs. bad exemplar — read `references/exemplar.md`

For a worked example of the bar — a great UI-first plan, plus the anti-patterns
to avoid — READ `references/exemplar.md` in this skill directory before
authoring a plan.

## Authoring invariants

Treat these as data-integrity checks, not optional polish:

- Edit the MDX surgically. Change the block, artboard, annotation, or wireframe
  you mean to change; do not regenerate `plan.mdx` or `canvas.mdx` wholesale to
  adjust one thing, because a regeneration silently drops the blocks you forgot
  to carry forward.
- A wireframe's scoped `css` is part of the artifact and travels with the screen
  it styles. Use renderer-owned `--wf-*` tokens for portable color and
  typography.
- Rich-text `markdown` must contain actual runtime line breaks. Do not hand a
  plan a one-line Markdown value containing literal `\n` escape text, which
  renders the whole section as one heading. Escaped newlines are fine in code
  examples when the surrounding Markdown still has real line breaks.
- Canvas artboards do not scroll. Keep wireframe HTML in natural flow and set a
  larger frame `height` when a screen exceeds the surface preset; preserve the
  surface width and inspect the bottom edge at default zoom before handoff.
- After every edit, rerun `plan local check` and reload the served plan. A clean
  lint is not proof that CSS loaded or that Markdown rendered into the intended
  heading, paragraph, and list structure.

## Local commands

Full detail in `references/local-workflow.md`. The four you need:

| Command | Purpose |
|---|---|
| `plan blocks --out plan-blocks.md` | Fetch the authoritative block catalog. Sends no plan content. |
| `plan local init --title "<T>" --kind plan --dir .plans/<slug>` | Scaffold the plan folder. |
| `plan local check --dir .plans/<slug>` | Offline lint. A subset of the renderer schema. |
| `plan local serve --dir .plans/<slug> --kind plan --open` | Start the localhost bridge and open the plan for review. |

`plan local verify` adds a headless loopback check, and against a local Plan app
(`--app-url http://localhost:8096`) it validates the real renderer schema. All
are prefixed `npx @agent-native/core@latest`.

When the user critiques a plan's look or structure, fix this skill's guidance —
never patch one stored plan by hand and leave the next one to repeat the fault.

## Setup

Node and `npx` on PATH. That is all — no account, no sign-in, no connector, no
API key. The CLI is fetched from npm on first run.

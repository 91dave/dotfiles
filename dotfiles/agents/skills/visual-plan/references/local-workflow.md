# Local plan workflow — single source of truth

This file is the canonical contract for authoring, checking, and previewing a
plan. There is no hosted mode: every plan `/visual-plan` produces is a local MDX
folder rendered through a localhost bridge. Read it in full before writing MDX.

## What "local" means here, precisely

Plan content never leaves this machine. There is no account, no sign-in, no
database write, and no share link. That is the guarantee. It is not the same as
offline, and the skill must not claim otherwise:

- `npx @agent-native/core@latest` downloads the CLI from npm on first use.
- `plan blocks` calls a public, no-auth block-catalog route. It sends no plan
  content — only the schema comes back.
- `plan local serve` opens the Plan renderer, which is hosted at
  `plan.agent-native.com`, and the renderer fetches the MDX from the localhost
  bridge in the browser. Their JavaScript runs in the page, and the local-plan
  route emits sanitized pageviews and error monitoring. The bridge token travels
  in the URL fragment, which browsers do not send to the origin.

If the user needs a genuinely offline render, there are two routes, both weaker
than `serve`:

- **A local Plan app.** Run it with the same `PLAN_LOCAL_DIR` and point at it
  with `--app-url http://localhost:8096`. This is the real renderer with no
  hosted origin, and it is the only fully offline path that renders blocks.
- **`plan local preview --out <file>.html`.** Writes a standalone static HTML
  file with no network dependency at all. Be aware of what it actually is: it
  renders the Markdown prose, then dumps every structured block as collapsed MDX
  source rather than rendering it. Useful as an archival or air-gapped handoff,
  never a substitute for `serve` when the point is to review wireframes.

## The workflow

### 1. Fetch the block catalog first

```bash
npx @agent-native/core@latest plan blocks --out plan-blocks.md
```

Read it before authoring. Never author from memorised tags — the registry is the
authority on tag names, required fields, and prop shapes. Use
`--format schema` when you need exact nested field types. If the network is
unavailable, fall back to the bundled `references/*.md` and lean on
`plan local check` to catch invalid tags.

Copy the catalog examples verbatim for the fields the summary table cannot
encode:

- `checklist` items need `id` and `label`.
- `question-form` questions need `id`, `title`, and `mode`; each option needs
  `id` and `label`.
- `Code` / `AnnotatedCode` / `Diff` are whitespace-sensitive. Encode multiline
  code as JSON string attributes such as `code={"const x =\n  y"}`. A static
  template literal is accepted only when it contains no `${...}` interpolation.
- `Columns` takes `<Column label="...">` children wrapping real nested blocks.
  A `columns=` attribute array fails schema validation.

Two traps in the catalog itself, because it is generated for the upstream hosted
product:

- Its authoring rules reference hosted concepts — a `content` full-replacement
  payload, `screens` / `states` convenience arrays, `set-visual-render-mode`,
  and `renderMode: "design"`. None of that applies here. Take block tags, fields,
  and examples from the catalog; take the workflow from this skill. Leave
  `renderMode` unset.
- Its `wireframe` example is authored as a **legacy kit tree**
  (`<Row><Sidebar><NavItem/></Sidebar></Row>`), which the catalog's own rules and
  `references/wireframe.md` both tell you not to write. Do not copy that example.
  Author `<Screen surface="..." html={...} />` with a semantic HTML fragment.

Block props are top-level MDX attributes, not a `data={{...}}` wrapper —
`<Code id="x" filename="..." code={"..."} />`, not `<Code data={{ code: ... }} />`.
`Callout` and `Diagram` take their body as children rather than attributes.

### 2. Scaffold the plan folder

Plans live in `.plans/<slug>/` in the repo under discussion, matching the
convention `/plan-tasks` and `/workflow` already use. Add `.plans/` to the
repo's `.gitignore` unless the user wants the plan checked in.

```bash
npx @agent-native/core@latest plan local init --title "<Plan title>" --kind plan --dir .plans/<slug>
```

This writes `plan.mdx` and `.plan-state.json`. Add `canvas.mdx` yourself when the
plan has a top wireframe canvas. The folder holds:

| File | Holds |
|---|---|
| `plan.mdx` | Frontmatter plus the document body blocks |
| `canvas.mdx` | `<DesignBoard>` / `<Section>` / `<Artboard>` / `<Screen>` / `<Annotation>` / `<Connector>` |
| `.plan-state.json` | Generated state; leave it alone |
| `.plan-url` | The served bridge URL. Treat as a local token file — never commit it |

### 3. Check, then serve

```bash
npx @agent-native/core@latest plan local check --dir .plans/<slug>
npx @agent-native/core@latest plan local serve --dir .plans/<slug> --kind plan --open
```

`check` is a quick offline lint covering a **subset** of the renderer schema. A
green `check` does not prove the plan renders — it catches invalid tags, not
invalid nested data. Always look at the served plan before handing it over.

Report the bridge URL from stdout or `.plans/<slug>/.plan-url`. Keep the serve
command running while the page is open; closing it kills the bridge.

Browser gotchas worth pre-empting rather than debugging live:

- Chrome and Edge prompt for **Local Network access** so the page can read the
  loopback bridge. If the user denies it, the plan hangs on "Loading plan" — they
  re-enable it in the `plan.agent-native.com` site settings and reload.
- Safari blocks the hosted HTTPS page from reading the HTTP localhost bridge
  entirely. Use a Chromium browser, or a local Plan app via `--app-url`.
- On macOS, `--open` already prefers Chromium browsers for this reason.

### 4. Verify before handoff

```bash
npx @agent-native/core@latest plan local verify --dir .plans/<slug> --kind plan
```

Runs headless: starts the bridge, checks the private-network preflight and the
JSON payload, entirely on loopback. It never sends MDX or assets anywhere.

With `--app-url` pointing at a loopback Plan app it also validates against that
app's real renderer schema, which is the authoritative check. A non-`ok` result
with `validation.valid: false` lists exact schema paths (e.g.
`blocks[1].data.tabs[0]...`) — fix those before handing off. If
`validation.ran` is `false`, verify fell back to the offline lint because no
local Plan app was reachable.

If the browser hangs on "Loading plan", fetch the `bridgeUrl` from the
verify/serve JSON to read the concrete validation error.

### 5. Iterate on feedback

Feedback arrives as chat or file comments, not as anchored comments on the
document. Edit the MDX directly, rerun `plan local check`, and reload the served
page — the bridge reads from disk, so a running `serve` picks up edits. Report
the URL again, or the checked `<plan-dir>` path when no preview is running.

Edit surgically. Do not regenerate the whole folder to change one block, one
wireframe, or one annotation.

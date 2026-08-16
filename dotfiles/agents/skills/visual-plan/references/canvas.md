# Canvas & artboard placement — single source of truth

This file is the canonical guide for how the visual-plan canvas works: artboard
placement, lane layout, annotations, patching, and the legacy kit tree. Read it
in full before authoring or editing any canvas/artboard content; do not author
canvas layouts from memory.

**The coordinate rule.** The `surface` sets each artboard's default footprint
and width — never set width or use coordinates inside the wireframe HTML.
Board-level artboard `x`/`y` IS allowed when it creates clear lanes. A
larger explicit artboard `height` is allowed when the screen's content needs
more vertical room; canvas frames do not scroll, so reserve enough height to
show the entire UI. Let canvas auto-placement handle simple one-row boards.

**Lay out mixed canvases in lanes.** When a canvas contains broad browser /
desktop frames plus compact `mobile`, `popover`, or `panel` surfaces, do not put
everything in one horizontal strip. Use board-level artboard `x`/`y` to reserve
lanes with generous empty space: main flow on one row, compact surfaces in their
own column or row, and loading/error states in a lower row. Keep at least 96px
between rendered artboard rectangles plus room for annotation gutters; when a
broad browser/desktop frame sits beside a compact panel/popover, leave at least
160px so frame borders, labels, and hover controls never touch. Connect only
neighboring steps; never draw a long connector that skips across unrelated
frames. Connector labels must sit in open canvas space. If the label would touch
or cross either artboard, remove the label and explain the transition with a
nearby annotation instead. Before handoff, inspect the top canvas at default zoom
and move any frame whose label, connector, or annotation crosses another frame.

**Board-unit spacing defaults.** The canvas coordinate system uses approximately 2 board units per screen pixel. `browser` frames occupy roughly 700 × 600 board units; `desktop` frames roughly 900 × 700 board units. Apply these minimum x/y gaps when placing frames explicitly — any less and frames will touch or overlap:

- x-gap between `browser` frames: **≥ 1100** (700-unit frame + 400-unit gutter)
- x-gap between `desktop` frames: **≥ 1300** (900-unit frame + 400-unit gutter)
- y-gap between rows of any surface: **≥ 1400** (includes frame height + section header + buffer)

When in doubt, use larger values — the canvas auto-zooms to fit everything.

**Full-content artboards.** Canvas frames are pan/zoom surfaces, not scroll
containers. Keep wireframe HTML in natural document flow without an inner
scroll region or fixed child height. If the screen is taller than the default
surface preset, set the artboard's `height` to the measured content height plus
breathing room; keep the surface width unchanged. Before handoff, inspect the
bottom edge of every artboard at default zoom and confirm no control, row, or
footer is clipped.

**Canvas annotations are designer notes on the artboard.** When a top canvas is
present, sprinkle design-review notes near the frames they explain: a short
heading, supporting text, and bullets — plain text layers, never bordered or
shadowed cards, and never a box around a frame. The renderer spaces notes away
from frames, so place each note by the frame it describes. Use an arrow only to
point at one specific control or transition; for a broad frame-level note, write
text beside the frame with no connector. Connectors are for real sequences only —
never fake "Step 1 → Step 2" lines between independent states.

**Do not create overlapping annotations.** Anchor each ordinary note to the
frame it explains with `targetId` + `placement` (top/right/bottom/left), and
omit `type` or use `type: "note"`. The renderer parks notes in a gutter beside
the frame and lays them out automatically. Do not use `type: "callout"`,
`type: "text"`, `type: "arrow"`, x/y, or points for ordinary notes; those are
freeform review-markup layers and must be reserved for intentional markup in
open canvas space. Reserve arrows for a note that must point at one specific
control inside a frame; a note that simply sits beside its frame needs no arrow.

**Editing.** The plan folder is the artifact: `plan.mdx` holds frontmatter plus
the markdown/document blocks, `canvas.mdx` holds
`<DesignBoard>/<Section>/<Artboard>/<Screen>/<Annotation>/<Connector>`. Edit one
wireframe, annotation, diagram, or block directly in the MDX and rerun
`plan local check` rather than regenerating the file. A regeneration is the
common way to lose work: blocks and artboards you forget to carry forward
disappear silently, and a clean lint will not tell you they are gone. If you do
have to rewrite a whole file, read it completely first and account for every
existing block and artboard in the replacement.

**Never emit a titled artboard with no interior wireframe content.** Every artboard
you place on the canvas must carry an `html` wireframe or reference a wireframe
block via `blockId`; when using `blockId`, the referenced `wireframe` /
`legacy-wireframe` block must remain in the plan. If you remove a duplicate
wireframe from the document body, first move its `data` inline onto the
corresponding `content.canvas.frames[*].wireframe` / `legacyWireframe`. A
label-only frame or a frame pointing at a deleted block renders empty and is
rejected at parse time. If you only have a title, write it as a section header or
annotation, not an empty artboard.

**UI mockups belong in the top visual review area.** Static UI/product visuals
live on the canvas. When the user asks for a mockup, UI state, loading state,
layout, screen, or visual comparison, make the canvas the primary home for that
visual, and give a multi-step flow one artboard per user-visible state.
Architecture/code diagrams stay inline in the document (the SKILL.md Visual
Surface Choice section owns that rule) unless the user explicitly asks for a
spatial board. Document blocks can explain, compare, or map implementation, but
they should not host the primary UI mockup just because `custom-html`,
screenshots, or prose are easier to produce. If the canvas cannot represent the
requested UI fidelity, still keep the closest canvas representation and say
plainly what the wireframe surface cannot show. A skeleton/loading mockup also
lives in a canvas artboard — never move a mockup out of the canvas.

**Storyboards are canvas artifacts, not document diagrams.** When the requested
output is a product flow, onboarding journey, "light storyboard", or canvas
wireframe, author the flow as multiple top-canvas artboards with real screen
content and neighboring connectors. Keep document-body `diagram` blocks for
architecture and mechanics that are not themselves user-visible screens. A
storyboard made from a single inline HTML diagram is the wrong surface.

For abstract product concepts, use the canvas to create the first "I get it"
moment: one real app state near the top showing how the concept appears to a
user, followed by separate annotations or diagrams for mechanics. Do not make
the first artboard a hybrid of app UI and architecture notes; the app screen
should be inspectable as product UI on its own.

**Legacy kit tree.** Older plans set a `screen` array of `{ el, ...props }` kit
nodes instead of `html`; the renderer still accepts and displays it so saved
plans round-trip, but new plans emit `html`. Do not author fresh kit-tree
screens, and do not put nested kit components such as `<FrameScreen>`, `<Card>`,
`<Row>`, `<Title>`, or `<Btn>` inside a canvas `<Screen>`. A new canvas artboard
with kit-tree children is a defect: replace it with
`<Screen surface="..." html={...} />` using the HTML wireframe rules. The HTML
path is the one that gets the renderer-owned surface sizing, theme tokens,
sketch/clean toggle, and safe text layout used by good document-body
wireframes. Likewise, old or imported plans may carry coordinate-based regions
or free-float x/y on notes; those are legacy escape hatches the renderer still
shows but you must never produce. The gutter parks notes by `targetId` +
`placement`, and the coordinate rule at the top of this file governs all
new-plan placement.

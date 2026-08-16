# Plan document quality

The bar the plan document has to clear. Read it before authoring.

## It is a technical plan, not a pitch

Write it the way a strong implementation plan reads: outcome first, prose first,
specific. State the objective and what done means, the scope and the non-goals,
the approach with the decisions and why they were taken, ordered steps naming
real files and symbols, the risks, and how it will be verified.

Replace vague prose with specifics. Never ship a step like "make it work". No
hero headings, value propositions, or marketing cards.

## It stands alone

A reader who was not in the chat, opening the URL cold, should understand it.

Do not write "as discussed above", "this revision", "unlike the previous
version", or "preserve the earlier plan". When you are revising, fold the right
decisions into the plan as ordinary objective, approach and scope prose. The
document is a plan to do the work, not a changelog of how the plan got here.

Avoid negative framing that only resolves against absent context. State the
positive model directly.

## Right component, real substance

Reach for a component only when markdown cannot carry the thing. `components.md`
is the reference; this is the judgement:

- **`mermaid`** when a relationship is two-dimensional and the shape is the
  point: architecture, data flow, state, ownership. Not to decorate, and never
  restating a list you already wrote.
- **`<FileTree>`** when the reader needs to see the blast radius. List the files
  worth reading, with a note on the load-bearing ones. Not an exhaustive dump of
  everything touched.
- **Code fences** for the smallest fragment that carries the point, with
  `title=` so the reader knows the file. A plan is not a patch.
- **`<Callout>`** for a decision and its rationale, or a risk the reader must
  weigh before approving. Two or three per plan. A page of callouts has no
  emphasis.
- **`<Tasks>`** when the work has a genuine ordered breakdown. A design note or
  an investigation write-up does not need one.
- **Tables** for comparisons and option matrices. Markdown handles them.

A component carrying nothing is worse than its absence, because it costs the
reader a look.

## Decide, or ask before you write

There is no question form in the rendered plan. Clarifying questions are asked in
the TUI before the document is compiled, so by the time the reader opens it every
decision is either made or explicitly flagged.

For anything still open, state the assumption and the recommendation in the
prose, in the section it affects. Do not collect them into a bottom "open
questions" wall, and do not silently leave a decision unmade: if it would affect
architecture, scope, data shape or rollout, either commit to it with rationale or
say plainly that it needs the reviewer's call and what you would choose.

## Verification exercises the real workflow

The closing section goes beyond "run the tests" when the change touches data,
storage, flags, browser behaviour, or anything multi-service. Include at least one
end-to-end check matching the real user journey, and name the command or the
manual path when it is known.

## Look at it before you hand it over

Open the URL yourself first. Check that diagrams rendered rather than sitting as
source, code blocks are highlighted and not overflowing, file-tree nesting looks
right, and nothing shows raw `<Tasks` or `<FileTree` text where a component
should be.

Check dark mode if the reader is likely to use it. A plan that only works in one
theme is a defect.

# Worked example, and the anti-patterns

## Good: a backend migration plan

Opens with the objective in two sentences and what done means. Then a
`decision` callout naming the approach and the alternative it beat, with the
reason. A `mermaid` flowchart of the read path showing the flag branch and the
fallback, because that branching is the thing a reviewer needs to check and it
does not read as prose.

A `<FileTree>` of the four files that matter, with a note on the one branch that
actually moves and nothing on the obvious test file. One code fence with
`title=StorageResolver.cs` showing the six lines that change, not the class.

A `<Tasks>` block with three items in execution order: the regression Test task
first, the Functional task depending on it, the Documentation task last. Each
carries an objective and success criteria; the dependency graph beneath is
derived, not written.

Closes with verification that names the container suite command and one manual
check against the real bucket. A reviewer who was not in the chat can approve or
push back without asking a question.

## Good: a small design note

Objective, two options as a markdown table, a `decision` callout committing to
one, and three paragraphs on the consequences. No diagram, because the
relationship is a straight choice. No `<Tasks>`, because it is one change.

Short is not lazy. This plan is right because everything it leaves out would have
been padding.

## Bad

A hero heading and a paragraph on why the work matters before saying what it is.

A `mermaid` diagram that redraws the numbered list directly above it, or a
left-to-right chain of three boxes labelled Start, Process, End.

A `<FileTree>` listing all thirty touched files with no notes, so the reader
cannot tell which two carry the change.

A code fence pasting an entire class, or one with no `title=` so the reader has
to guess the file.

Six callouts in a row, none of which record a decision.

A `<Tasks>` block on a one-commit change, or tasks whose `successCriteria` say
"works correctly".

A step reading "update the service as required". A plan that says "as discussed
above" or "unlike the previous version". A bottom "Open Questions" wall
collecting decisions that should have been asked in the TUI before the document
was written.

A plan handed over without opening the URL, so the reviewer is the one who finds
the raw `<Tasks items={[` text where a component should have rendered.

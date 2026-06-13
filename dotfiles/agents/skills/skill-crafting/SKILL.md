---
name: skill-crafting
description: >
  Principles and structure for authoring or editing a skill (any SKILL.md and the files it
  ships). Covers frontmatter, portability, when to split out load-on-demand reference files,
  how to structure a multi-mode CLI-style skill, and good use of argument-hint. Use whenever
  creating a new skill, editing an existing skill, restructuring a skill, or reviewing a
  SKILL.md before committing it.
---

# Crafting and Editing Skills

Apply this whenever you are creating or changing a skill: a `SKILL.md`, its frontmatter, or
any script, reference, or fixture it ships. The goal is a skill that is lean, portable, and
obvious to invoke.

This file carries the working principles. For a full pass/warn/fail audit of a whole skills
repo, the `review-helpers-repo` skill has the exhaustive checklist; the principles below are
the subset that govern an individual skill, restated so this skill stands alone.

## Frontmatter

Every `SKILL.md` needs YAML frontmatter with at least:

- **`name`** — kebab-case, matches the directory name.
- **`description`** — the single most important field. It is the only thing the model sees
  when deciding whether to auto-invoke the skill, so it must state **what the skill does** and
  **when to use it**. Lead with the capability, then trigger phrases ("Use when…", "Triggers
  when…"). Make the invocation flavour unambiguous:
  - **Agent-invoked** (auto-loaded / triggered by context): write rich "Use when…" triggers.
  - **User-invoked** (manual command): end with `Invoke manually: /name` or `Invoke with: /name`.

A description that implies neither flavour, or that lists features without trigger conditions,
will not fire when it should.

### `argument-hint`

Add `argument-hint` whenever the skill takes arguments, and **always** when it has
subcommands or modes. It is shown to the user as a usage hint, so it should read like a CLI
signature:

```yaml
# Single argument:
argument-hint: "AB#<backlog-item-id>"

# Subcommands / modes — list them explicitly:
argument-hint: "[init | run | audit | help]"

# Mode plus an argument:
argument-hint: "[review | fix] <pr-number>"
```

Keep the hint in sync with the modes the body actually handles. A stale hint is worse than
none.

## Core principles

These apply to the `SKILL.md` **and every file it ships or references** (scripts, helpers,
fixtures). A clean SKILL.md does not pass if a script it invokes breaks one of them.

### Portability and self-containment

- **Machine-agnostic** — no drive letters, no `C:\Users\<name>`, no `/home/<name>`, no
  hardcoded path into one person's working tree, no machine hostnames. Resolve locations from
  config or the environment.
- **OS-portable** — executable behaviour must not hard-code one OS. Prefer `pwsh` over
  `powershell`, resolve home/temp cross-platform rather than `$env:USERPROFILE` literals, and
  compose paths with `Join-Path` / `[System.IO.Path]` rather than baked-in separators. A
  deliberately OS-specific script must say so in its header and the skill must declare the
  constraint. Naming an OS in **prose** is fine; the rule governs executable behaviour.
- **Tool-surface-agnostic** — where an operation has more than one interface (an MCP server
  *and* a CLI, e.g. Azure DevOps via `mcp__azure-devops__*` or the `az` CLI, GitHub via MCP or
  `gh`), describe the operation by intent rather than mandating one surface, unless the skill
  genuinely only works one way.

### The one-way dependency

CLAUDE.md may reference skills by name; skills must **not** reference user-specific concepts
from anyone's CLAUDE.md or environment. Describe *when* a skill applies in terms of the work
itself ("when a scoped unit of work completes"), never "in step 3 of my workflow". A skill
must not reference a specific agent; a skill that only makes sense inside one agent has the
wrong shape.

### Scripts over narration, and test those scripts

Deterministic, reproducible work (parsing, JSON/CSV assembly, git-history extraction, path
resolution, arithmetic, filtering, validation against a fixed schema) belongs in a **script
the skill invokes**, not narrated as steps for the model to perform by hand. Narrated
deterministic logic varies run to run, wastes tokens re-deriving the same result, and cannot
be tested. Reserve model steps for judgement and generation (interpreting results, choosing
between options, drafting prose, conversing).

Every script a skill ships should have co-located tests covering its contract and key edge
cases (Pester `*.Tests.ps1`, a `*.test.js` / `*_test.py`, etc.). If you add or change a
script, capture its behaviour in tests in the same change.

## Keep skills lean: split out reference files

A `SKILL.md` is loaded in full whenever the skill is invoked, so length is a direct context
cost. If the skill is large, or holds detail that only some paths through it need, **split the
rarely-needed detail into reference files loaded on demand**:

- Keep the `SKILL.md` itself to the concepts, routing, and principles common to every use.
- Move per-mode playbooks, long lookup tables, troubleshooting guides, and worked examples
  into `references/<topic>.md` (or similar) and **link to them** from the body.
- Instruct the body to **load only the reference it needs** for the task at hand, not all of
  them.

```
skills/my-skill/
  SKILL.md                 # concepts + routing, always loaded
  references/
    init.md                # loaded only in init mode
    troubleshooting.md      # loaded only when diagnosing
  scripts/
    do-the-thing.ps1
    do-the-thing.Tests.ps1
```

Rule of thumb: if a section is only relevant to one branch of the skill, or you find yourself
scrolling past it on most invocations, it is a candidate for a reference file.

## Multi-mode / CLI-style skills

When a skill does several related things (plan / run / audit / help), structure it like a CLI
rather than one long linear procedure:

1. **Declare the modes in `argument-hint`** and in the `description` ("Modes: init, run,
   audit, help").
2. **First step is routing.** Read the chosen mode from arguments, or infer it from intent,
   then load the one matching reference file. Do not load every reference.
3. **A routing table** mapping each mode to its trigger signals and its reference file keeps
   the dispatch legible:

   | Mode | Trigger signals | Reference |
   |---|---|---|
   | `init` | "scaffold", "set up" | `references/init.md` |
   | `run` | "run it", "execute" | `references/operate.md` |

4. **A bare invocation with nothing to infer shows help**, rather than guessing. Provide a
   `help` mode that prints a usage block verbatim and stops without exploring or acting.
5. **When the mode is genuinely ambiguous, ask** before acting, rather than picking one.

This keeps each invocation cheap (only the relevant reference loads) and makes the skill's
surface self-documenting.

## Link out to prior art

When a skill encodes a change that has been done before, **link to the concrete prior
example** rather than only describing it: the repository, the specific PR, or the file that
implemented a similar change. A reader following the skill can then see a real, merged
instance of the pattern instead of reconstructing it from prose. This is especially valuable
for skills that drive a code change with an established shape (a migration, a wiring-up, a
conventional refactor). Keep such links current; a dead link to a moved PR is a maintenance
cost, so prefer stable references (a merged PR number, a path in a named repo) over volatile
ones.

## Before finishing

Quick self-check on the skill you just wrote or edited:

- [ ] `name` matches the directory; `description` states what + when, with a clear invocation
      flavour.
- [ ] `argument-hint` present and accurate if the skill takes arguments or has modes.
- [ ] No hardcoded user paths, machine names, or OS-locked executable constructs anywhere in
      the skill or the files it ships.
- [ ] No references to user-specific CLAUDE.md concepts or to a specific agent.
- [ ] Deterministic logic lives in scripts (with tests), not narrated steps.
- [ ] The body is lean; rarely-needed detail is in load-on-demand reference files.
- [ ] Prior art is linked where the skill mirrors a previous change.

For a fuller repo-wide audit (duplicate guidance, agent/skill boundaries, severity grading),
hand off to the `review-helpers-repo` skill.

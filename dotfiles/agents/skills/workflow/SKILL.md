---
name: workflow
description: >
  Pick the next task, implement it with the verification strategy for its type,
  then spawn an isolated subagent for unbiased code review. Works in two modes:
  a local plan folder (.plans/{name}/ produced by /plan-tasks) or an Azure DevOps
  backlog item. Use when the user says "next task", "work the plan", "work the
  backlog", "implement and review", or wants to pick up the next piece of work.
  Provide either a plan folder or a parent work item ID (AB#12345); the mode is
  auto-detected.
---

# Workflow: Implement and Review

Pick the next task, implement it, then delegate an isolated review. This is the
interactive, single-task counterpart to the `ralph` autonomous loop runner — it
shares ralph's mode/agent vocabulary, so a plan folder behaves the same whether
driven by hand here or in a loop with `ralph -s implement,review`.

**Arguments:** `$ARGUMENTS`

---

## Phase 0: Determine the Mode

A **mode** defines how tasks are tracked. Detect it before doing anything else:

1. If the argument or conversation context contains a work item reference of the
   form `AB#{number}` → **AzDo mode**. Bind `{workitem}` = that ID.
2. Otherwise look for a local plan folder: a `.plans/*/` directory containing a
   `PLAN.md` and one or more `task-*.md` files (the layout produced by
   `/plan-tasks`).
   - Exactly one match → **Plan-folder mode**. Bind `{project}` = that path.
   - Several matches → ask the user which plan to work.
   - None → ask the user to supply an `AB#` or run `/plan-tasks` first, then stop.

State the detected mode and target to the user before proceeding.

All concrete task operations below are defined per mode in
[Mode Mechanics](#mode-mechanics). The phases reference these operations by name
(discover, select, mark in-progress, mark complete, record progress, commit
reference, create follow-up) so the phase logic stays mode-agnostic.

---

## Phase 1: Orient

1. Read the plan context:
   - **Plan-folder mode:** read `{project}/PLAN.md` (problem, outcome,
     constraints) and `{project}/progress.md` (what previous iterations did).
   - **AzDo mode:** read `{workitem}` title, description, acceptance criteria,
     and all comments (progress from previous iterations).
2. **Discover** the tasks.
3. **Select** the next task to work (see selection rules per mode). In both
   modes: never select a task whose declared dependencies are not yet complete,
   prioritise bug/defect work, and otherwise take the first ready task in plan
   order.
4. **Tell the user** which task you're picking up and why. Wait for confirmation
   before proceeding.

If no incomplete, dependency-ready tasks remain, inform the user the plan is
complete (or blocked, naming the blocker) and stop.

---

## Phase 2: Implement

**Mark the selected task in-progress.**

Execute the task using the **verification strategy for its task type**, taken
from the task's own Success Criteria section (the `/plan-tasks` templates define
one per type). Do not assume TDD for every task:

| Task type | Strategy |
|---|---|
| **Functional** | TDD: write failing tests first (Red), implement to green, then refactor. |
| **Refactor** | No new tests. Record the passing test count as a baseline, change code, confirm the same tests still pass. |
| **Test** | Add/modify tests, run the full suite. An unexpected failure may be a real bug — flag it, do not silently patch app code. |
| **Infrastructure** | Follow the task's bespoke success criteria (smoke / functional / integration / teardown / idempotency checks). |

Throughout: use the available feedback loops (types, tests, linting). Then:

- **Verify acceptance criteria.** Walk through each criterion in the task. If any
  cannot be satisfied, stop and tell the user what is blocking and how you
  propose to proceed — do not mark the task complete.

If tests cannot be run (no framework configured), state this explicitly and ask
the user to verify manually before continuing.

---

## Phase 3: Commit

Once implementation is complete and all checks pass:

```bash
git.exe add -A
git.exe commit -m "<conventional-commit-message>"
```

Use conventional commit format. Apply the **commit reference** rule for the mode
(`AB#{number}` in AzDo mode; in plan-folder mode use `PLAN.md`'s Backlog Item if
it declares one, otherwise omit the reference — never invent a placeholder).

Run `git.exe commit` and `git.exe push` as separate commands. Do not commit
directly to `main`; if on `main`, create a work branch first and tell the user.

---

## Phase 4: Isolated Review

Spawn a subagent to review the changes with **no knowledge of the implementation
reasoning** (ralph's step-context handoff). The subagent receives ONLY:

- The task identity (the `task-*.md` path in plan-folder mode, or the `AB#` and
  task title in AzDo mode) — i.e. *what was supposed to be done*.
- The commit hash to review.
- The project directory path.

Use this prompt for the subagent:

> You are a code review agent. Review the most recent commit in the repository at
> `{project_path}`.
>
> **Context:** This commit implements the task "{task_identity}".
>
> Run `git.exe show --stat HEAD` and `git.exe show HEAD` to see the changes.
>
> Check for:
> - Code quality issues (naming, structure, duplication)
> - Potential bugs or edge cases
> - Missing error handling
> - Security concerns (secrets, injection, unsafe input)
> - Adherence to project conventions and patterns
> - Test coverage gaps
>
> If you find issues:
> - **Trivial** (typos, formatting, minor bugs): fix them directly and commit
>   with a conventional commit message (apply the same commit-reference rule as
>   the parent task).
> - **Non-trivial**: describe the issue clearly and suggest a fix, but do NOT make
>   the change.
>
> Produce a structured review summary:
> - ✅ What looks good
> - ⚠️ Issues found (with severity: trivial/non-trivial)
> - Actions taken (fixes committed)
> - Recommendations (for non-trivial issues)

---

## Phase 5: Process Review Results

After the subagent returns:

1. Present the review summary to the user.
2. If non-trivial issues were raised:
   - Ask the user whether to fix now or defer.
   - Fix now: make the changes, re-run the task's checks, and commit.
   - Defer: **create a follow-up task** (per mode) describing the issue.
3. If the review was clean or only trivial fixes were applied:
   - **Mark the task complete** (per mode).
   - **Record progress** (per mode) summarising what was done.

---

## Mode Mechanics

The concrete operations the phases reference, defined per mode. Align the
plan-folder format to the `/plan-tasks` `TEMPLATES.md` conventions — it is the
producer of these folders.

| Operation | Plan-folder mode (`{project}`) | AzDo mode (`{workitem}`) |
|---|---|---|
| **Discover** | List `{project}/task-*.md`; read each file's `> **Status:**`, `> **Type:**`, and `## Dependencies`. | Fetch child work items of `{workitem}`. |
| **Select** | Skip any task with `> **Status:** Complete`. Skip any whose Dependencies are not all Complete. Among the rest, bugs first, then first in plan order. | Skip Done/Resolved. Skip those whose dependency items aren't complete. Bugs first, then first logically. |
| **Mark in-progress** | Edit the task file: `> **Status:** Not Started` → `> **Status:** In Progress`. | Set the child item state to "In Progress"/"Doing". |
| **Mark complete** | Edit `> **Status:**` → `Complete`; tick every box in the task's Completion Checklist, including "This task marked as complete". Only if ALL success criteria are met. | Set the child item state to "Done"/"Resolved". Only if ALL acceptance criteria are met. |
| **Record progress** | Append a timestamped entry to `{project}/progress.md` (heading `## Task: {title} — YYYY-MM-DD HH:MM`, a summary, and an `**Issues:**` line for any deviations/blockers). | Add a well-structured markdown comment to `{workitem}` (bold outcome line, bullets for files/criteria/issues, code formatting for identifiers). |
| **Commit reference** | Use `PLAN.md`'s Backlog Item if declared; otherwise omit (no placeholder). | Include `AB#{number}` in the conventional commit scope. |
| **Create follow-up** | Create a new `{project}/task-{slug}.md` using the `/plan-tasks` Task Template (Status: Not Started, an appropriate Type, Dependencies, Success Criteria for that type). | Create a child work item under `{workitem}` (`Bug` for defects, else `Task`) with acceptance criteria. |

---

## Notes

- Only work on **one task** per invocation. Run the skill again for the next task.
- The plan-folder task format is the single source of truth shared with `ralph`'s
  `taskfile` mode. If you find a plan folder whose task files use an older format
  (inline `Status:`/`Priority:` rather than the blockquote + Completion Checklist
  shape), flag it rather than guessing.
- If the parent work item or plan folder has no tasks, offer to break the work
  down first (point the user at `/plan-tasks`).
- Never commit the `.plans/` directory to source control.

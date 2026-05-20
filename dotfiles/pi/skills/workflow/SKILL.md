---
name: workflow
description: >
  Pick the next task from an Azure DevOps backlog item, implement it with TDD,
  then spawn an isolated subagent for unbiased code review. Use when the user says
  "next task", "work the backlog", "implement and review", or wants to pick up the
  next piece of work. Requires a parent work item ID (AB#12345) either passed as an
  argument or inferred from conversation context.
---

# Workflow: Implement and Review

Pick the next task, implement it, then delegate an isolated review.

**Arguments:** `$ARGUMENTS`

The argument (or conversation context) must provide a parent Azure DevOps work item ID (e.g. `AB#12345`). If none is available, ask the user.

---

## Phase 1: Orient

1. Retrieve the parent work item details — read its title, description, and acceptance criteria.
2. Read all comments on the parent item for context from previous iterations.
3. Retrieve the child work items — these are your tasks.
4. Select the highest-priority incomplete task:
   - Prioritise bugs/defects over features.
   - Among equal priority, pick the first logically.
5. **Tell the user** which task you're picking up and why. Wait for confirmation before proceeding.

If no incomplete tasks remain, inform the user and stop.

---

## Phase 2: Implement (Red → Green → Refactor)

Mark the selected task as in-progress.

### 2a: Write Tests First

- Read the task's acceptance criteria carefully.
- Write unit/container tests that assert the required behaviour **before** writing implementation code.
- Run the tests — they should **fail** (Red).

### 2b: Implement

- Write the minimum code to make all tests pass (Green).
- Run tests again to confirm they pass.

### 2c: Refactor

- Clean up the implementation: naming, structure, duplication.
- Run tests once more to ensure nothing broke.
- Run the linter if one is configured.

### 2d: Verify Acceptance Criteria

- Walk through each acceptance criterion in the task.
- If **any** criterion cannot be satisfied, inform the user immediately with what's blocking and ask how to proceed.

---

## Phase 3: Commit

Once implementation is complete and all tests pass:

```bash
git.exe add -A
git.exe commit -m "<conventional-commit-message>"
```

Use conventional commit format with the work item reference (e.g. `feat(AB#12345): ...`).

---

## Phase 4: Isolated Review

Spawn a subagent to review the changes with **no knowledge of implementation reasoning**.

The subagent task should contain ONLY:
- The work item ID and task description (what was supposed to be done)
- The commit hash to review
- The project directory path

Use the following prompt for the subagent:

> You are a code review agent. Review the most recent commit in the repository at `{project_path}`.
>
> **Context:** This commit implements work item AB#{id} — "{task_title}".
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
> - **Trivial** (typos, formatting, minor bugs): fix them directly and commit with `fix(AB#{id}): <description>`.
> - **Non-trivial**: describe the issue clearly and suggest a fix, but do NOT make the change.
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
   - Ask the user whether to fix now or create a follow-up task.
   - If fixing now: make the changes, run tests, and commit.
   - If deferring: create a new child task under the parent work item describing the issue.
3. If the review was clean or only trivial fixes were applied:
   - Mark the task as complete.
   - Add a progress comment to the parent work item summarising what was done.

---

## Notes

- Only work on **one task** per invocation. Run the skill again for the next task.
- If tests cannot be run (no test framework configured), state this explicitly and ask the user to verify manually.
- If the parent work item has no child tasks, ask the user if they'd like help breaking the work down first.

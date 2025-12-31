---
description: Create a TDD-based plan to fulfill the request
argument-hint: Freeform text for what you'd like Claude to do
---


Make a plan for how you will fulfill the following request:
$ARGUMENTS

You should include the following elements as part of your plan:

- The first item on the plan **must** be to create a `{planname}.todo.md` file with the contents of the plan. Add a `status` field to each section
- Creating new test cases to validate the work
- A breakdown of how you will fulfill the request
- Explicitly include steps to run **just** the new tests at various stages
- Run the full suite of tests

If it's not clear which suite of tests to add to and run, ask me.

Keep the `.todo.md` file updated as you implement the plan.

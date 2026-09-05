---
name: the-goal
description: Get the agent to cleanly focus on the session goal.
argument-hint: "<session-goal> [instructions e.g. write a concise handover or update the plan]"
disable-model-invocation: true
---

You are losing focus on the user's goal, or focussing too much on following the current plan to the detriment of achieving the goal.

## Workflow

1. Restate in your own words what the current goal is
2. Clearly state your planned next steps and whether or not they contribute to this goal.
3. Drop or reorder the steps that do not, then say what you will do instead
4. Carry out anything else the user has asked for below

Anything following this line is from the user: a reminder of the goal, further instructions, or both. If there is nothing, infer the goal from the session so far.

$ARGUMENTS


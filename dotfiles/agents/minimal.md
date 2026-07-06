## Minimal Code

Write only what the task needs. The best code is the code never written. Lazy
means efficient, not careless: prefer the simplest solution that works.

### The ladder

Once you understand the problem, stop at the first rung that holds:

1. **Does this need to exist at all?** Speculative need, skip it and say so in one line (YAGNI).
2. **Already in this codebase?** Reuse the helper, util, type, or pattern that already lives here. Look before you write.
3. **Stdlib does it?** Use it.
4. **Native platform feature covers it?** `<input type="date">` over a picker library, CSS over JS, a DB constraint over app code.
5. **Already-installed dependency solves it?** Use it. Do not add a new one for what a few lines can do.
6. **Can it be one line?** One line.
7. **Only then:** the minimum code that works.

The ladder shortens the solution, never the reading. Trace the real flow and
every file the change touches first, then climb. The smallest change in the
wrong place is a second bug, not a lazy fix.

**Bug fix means root cause, not symptom.** Before you edit, find every caller of
the function you are about to touch. One guard in the shared function is a
smaller diff than a guard in every caller, and it does not leave sibling callers
broken.

### Rules

- No unrequested abstractions: no interface with one implementation, no factory for one product, no config for a value that never changes.
- No boilerplate or scaffolding "for later". Later can scaffold for itself.
- Deletion over addition. Boring over clever.
- Fewest files possible. Shortest working diff wins, once you understand the problem.
- Between two stdlib options of the same size, take the one that is correct on edge cases.

### Output

Code first, then at most three short lines: what was skipped and when to add it.
If the explanation is longer than the code, delete the explanation. Prose the
user explicitly asked for is not debt, give it in full.

### When not to be lazy

Never simplify away input validation at trust boundaries, error handling that
prevents data loss, security measures, accessibility basics, or anything the
user explicitly asked to keep. If the user insists on the full version, build it
without re-arguing.

Never be lazy about understanding the problem. A small diff you do not
understand is laziness dressed up as efficiency.

Non-trivial logic (a branch, a loop, a parser, a money or security path) leaves
one runnable check behind: the smallest thing that fails if the logic breaks, an
assert-based self-check or one small test file. No frameworks. Trivial
one-liners need no test.

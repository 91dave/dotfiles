---
name: ship-it
description: >
  Ship working tree changes: create a branch (if needed), commit, push, and open a PR.
  Determines whether main is acceptable or a work branch is required. Groups changes into
  logical commits with conventional commit messages. Use when the user says "ship it",
  "commit and push", "create a PR", or wants to wrap up current work.
---

Ship the current working tree changes: branch, commit, push, and PR.

**Arguments:** `$ARGUMENTS`

## Step 1: Check for Changes

```bash
git.exe status --porcelain
```

If there are **no changes** (working tree clean, nothing staged), inform the user and stop.

## Step 2: Determine Branch Strategy

### 2a: Check if already on a work branch

```bash
git.exe branch --show-current
```

If the current branch is NOT `main` (e.g. already on `work/...` or `feature/...`), skip to Step 3.

### 2b: Check if main is acceptable

Look for repo-level guidance that explicitly permits committing to main:

- Check for `AGENTS.md`, `CLAUDE.md`, or `.claude/CLAUDE.md` in the repo root
- Look for phrases like "main is fine", "commit to main", or "no branch required"

If main is **explicitly acceptable** per project instructions or the user has stated so, stay on main and skip to Step 3.

### 2c: Create a work branch

If committing to main is not permitted (the default), create a branch:

- **If a BLI is mentioned** (in `$ARGUMENTS`, conversation context, or commit message): `work/{bli-number}-{short-description}`
  - Example: `work/35254-verbose-deploy-jobs`
- **If no BLI**: `work/{short-description}`
  - Example: `work/fix-line-endings`

Derive `{short-description}` from the nature of the changes (kebab-case, 3-5 words max).

```bash
git.exe checkout -b "work/{branch-name}"
```

## Step 3: Commit Changes

### 3a: Analyse the working tree

Review all changes and determine whether they should be **one commit or multiple**:

- **Single commit** — all changes are related to one logical unit of work
- **Multiple commits** — changes span distinct concerns (e.g. a feature + a workflow update + a config fix)

Keep commits small (aim for <10 files, ~200 lines each). When in doubt, fewer commits is fine.

### 3b: Determine co-authoring

By default, co-author commits with `Co-authored-by: claude <claude@amdigital.co.uk>`
(per the standard guardrails).

**Exception:** if a repo-level agent file (`AGENTS.md`, `CLAUDE.md`, or `.claude/CLAUDE.md`
in the repo root) opts out of co-authoring — e.g. phrases like "do not co-author", "no
co-authoring", or "personal project" — **omit the trailer** for this repo. (You may
already have read these files in Step 2b; reuse that.)

### 3c: Stage and commit

For each logical group:

```bash
# With co-authoring (default):
git.exe add <files>
git.exe commit -m "{type}({ticket}): {description}" --trailer "Co-authored-by: claude <claude@amdigital.co.uk>"

# When the repo opts out (Step 3b), drop the --trailer:
git.exe add <files>
git.exe commit -m "{type}({ticket}): {description}"
```

**Commit message format:** `{type}(AB#{id}): {short-description}`

- If no BLI is available, omit the parenthetical: `{type}: {short-description}`
- Types: `feat`, `fix`, `refactor`, `style`, `ci`, `chore`, `docs`, `build`, `reg`
- Choose the type based on the nature of the changes

### 3d: Run linting (if available)

Before finalising, check for lint commands:

- Look for `package.json` scripts (`lint`, `format:check`)
- Look for `.editorconfig`, `dotnet format` availability
- If linting is available, run it and fix any issues before committing

## Step 4: Push

```bash
git.exe push -u origin HEAD
```

## Step 5: Create a Pull Request

```bash
gh.exe pr create --fill --head "$(git.exe branch --show-current)"
```

If more context is available, provide a better title and body:

```bash
gh.exe pr create \
  --title "{type}({ticket}): {description}" \
  --body "{summary of changes}" \
  --head "$(git.exe branch --show-current)"
```

- Include the BLI reference in the PR body if available (e.g. `Relates to AB#35254`)
- If targeting a branch other than main (e.g. a feature branch), add `--base {target}`

## Step 6: Confirm

Report to the user:
- Branch name
- Number of commits made (with short descriptions)
- PR URL

## Notes

- **Never force-push** unless explicitly asked
- If the branch already exists on the remote, inform the user and ask how to proceed
- If there are untracked files that look like they shouldn't be committed (e.g. `.todo.md`, build artifacts), ask before including them
- Respect `.gitignore` — never commit ignored files
- Exclude `*.todo.md` files from commits (per guardrails)

---
name: update-dotfiles
description: Update, commit and push dotfiles. Locates the dotfiles repo, pulls latest config from the system, analyses changes, commits and pushes. Suggests documentation updates when changes are significant. Use when the user wants to sync, save, backup, or push their dotfiles.
---

# Update Dotfiles

## Workflow

### 1. Locate the repo

```bash
DOTFILES_DIR=$(repo-find dotfiles)
cd "$DOTFILES_DIR"
```

If `repo-find` returns multiple matches, ask the user to disambiguate.

### 2. Check for changes

There is **no pull step**. Every dotfile is symlinked from its live location into the repo
by `install.sh`, so the repo working tree *is* the live config. Editing `~/.vimrc`, a
`lib` script, the `claude`/`pi` settings, or anything else edits the repo file directly,
and the edit already shows up as a working-tree change. Just go straight to analysing the
diff in step 3.

`install.sh` only needs running to (re)create the symlinks — on a new machine, or after
adding a brand-new dotfile to the repo. It does not "pull" existing config.

**Out of scope:** the home skill folders also contain symlinks pointing into the separate
`docs-claude-helpers` repo (the work skills and `CLAUDE-template.md`). Those belong to
that repo — never copy or commit them here. Only `agents/skills/` (your personal skills)
is part of dotfiles.

### 3. Analyse changes

```bash
git status
git diff --stat
git diff
```

- If there are **no changes**, inform the user and stop.
- Summarise what changed in plain language (group by theme: shell config, editor settings, tool config, etc.).

### 4. Rebuild agent files if their sources changed

The home `CLAUDE.md` / `AGENTS.md` are **generated** from `agents/template.md` and are not
stored in the repo. If the diff touches `agents/template.md`, or a skill was **added or
removed** under `agents/skills/`, regenerate them and refresh the skill symlinks:

```bash
bash agents/sync-agents.sh
```

Editing an *existing* skill's `SKILL.md` needs no rebuild — the home symlink already
points at it.

### 5. Commit and push

- Stage all changes: `git add -A`
- Write a conventional commit message:
  - Use type `chore` (or `feat` if new tooling/config is added)
  - Keep the subject line concise, e.g. `chore: update shell aliases and pi agent settings`
  - If changes span unrelated areas, consider multiple small commits
- Push: `git push`

### 6. Evaluate documentation impact

After committing, review the diff and consider whether the changes are **significant enough to warrant documentation updates** — for example:

- New tools or CLI utilities added to PATH / aliases
- Changed environment variables or shell behaviour
- New or removed **shared agent skills** (`agents/skills/`) or changes to the **agent template** (`agents/template.md`)
- Meaningful changes to editor or terminal configuration

If any apply, **suggest specific documentation updates** to the user (e.g. "You added a new pi skill — consider updating your team onboarding notes" or "New shell aliases were added — the dotfiles README may need updating").

If the changes are routine/minor (whitespace, version bumps, timestamps), simply confirm the push succeeded and move on.

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

### 2. Pull latest dotfiles from the system

```bash
./manage.sh get
```

This copies dotfiles from their live locations into the repo working tree.

### 3. Analyse changes

```bash
git.exe status
git.exe diff --stat
git.exe diff
```

- If there are **no changes**, inform the user and stop.
- Summarise what changed in plain language (group by theme: shell config, editor settings, tool config, etc.).

### 4. Commit and push

- Stage all changes: `git.exe add -A`
- Write a conventional commit message:
  - Use type `chore` (or `feat` if new tooling/config is added)
  - Keep the subject line concise, e.g. `chore: update shell aliases and pi agent settings`
  - If changes span unrelated areas, consider multiple small commits
- Push: `git.exe push`

### 5. Evaluate documentation impact

After committing, review the diff and consider whether the changes are **significant enough to warrant documentation updates** — for example:

- New tools or CLI utilities added to PATH / aliases
- Changed environment variables or shell behaviour
- New or removed pi skills, agents, or settings
- Meaningful changes to editor or terminal configuration

If any apply, **suggest specific documentation updates** to the user (e.g. "You added a new pi skill — consider updating your team onboarding notes" or "New shell aliases were added — the dotfiles README may need updating").

If the changes are routine/minor (whitespace, version bumps, timestamps), simply confirm the push succeeded and move on.

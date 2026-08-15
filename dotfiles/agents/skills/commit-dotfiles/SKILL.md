---
name: commit-dotfiles
description: >
  Commit and push changes to the dotfiles repo. Analyses the working tree, rebuilds the
  generated agent instruction files and skill symlinks when their sources changed, commits
  with conventional messages and pushes. Flags which docs pages the change should touch.
  Use when the user wants to save, sync, back up, commit or push their dotfiles.
  Invoke manually: /commit-dotfiles
---

# Commit Dotfiles

Every file under `dotfiles/` is symlinked to its home location by `install.sh`, so the repo
working tree **is** the live config: editing `~/.vimrc` edits the repo file, and vice versa.

## Workflow

### 1. Locate the repo

```bash
DOTFILES_DIR=$(repos resolve dotfiles)
cd "$DOTFILES_DIR"
```

If `repos resolve` returns multiple matches, ask the user to disambiguate.

### 2. Analyse changes

```bash
git status
git diff --stat
git diff
```

- If there are **no changes**, inform the user and stop.
- Summarise what changed in plain language, grouped by area: shell, git, pi, claude, agents,
  bin, docs.

If the change adds a **new file under `dotfiles/`**, check `install.sh` has a matching `link`
line for it, and tell the user to re-run `./install.sh` before it goes live. `link()` prints
`skip (not in repo)` and returns for a source it cannot find, so a missing line fails quietly.

### 3. Rebuild generated artefacts

Run the agent sync when the diff touches:

- `agents/template.md` or a file it includes (`output.md`, `minimal.md`), or
- a skill **added, removed or renamed** under `agents/skills/`.

```bash
bash dotfiles/agents/sync-agents.sh
```

Editing an *existing* skill's `SKILL.md` needs no rebuild — the home symlink already points at
the repo file. The exception is a skill whose frontmatter `description` exceeds
`MAX_DESC_CHARS` (1024): `sync-agents.sh` materialises those as a real folder with a rewritten
`SKILL.md` rather than symlinking, so editing one **does** need a re-run.

`sync-agents.sh` also runs from `install.sh` and from the `SessionStart` hook in
`dotfiles/claude/settings.json`, so a rebuild has often already happened.

### 4. Commit and push

This repo's conventions differ from the work defaults:

- Committing direct to `main` is fine. No branch, no PR, no backlog item.
- **No `Co-authored-by` trailer** — personal project.
- Conventional commits with a plain area scope, never `AB#`: `chore(dev):`, `feat(pi):`,
  `docs(agents):`, `perf(repos):`.
- Split unrelated areas into separate small commits.

```bash
git add <files>
git commit -m "<type>(<area>): <subject>"
git push
```

Run `git commit` and `git push` as separate commands.

### 5. Evaluate documentation impact

Review the diff against the areas below and tell the user which pages look stale:

| Change area | Docs to review |
|---|---|
| `bin/repos`, `lib/repos-*`, `lib/git*` | `docs/git.md`, `docs/tools.md`, `docs/README.md` |
| `bin/web` and other `bin/` scripts | `docs/tools.md` |
| `pi/` settings, extensions, themes | `docs/pi.md` |
| `agents/` template, includes, skills | `docs/agents.md` |
| `bash.sh`, `atuin/`, history and fzf config | `docs/shell.md`, `README.md` |
| aliases, `ce`, .NET and NuGet helpers | `docs/dev.md` |
| a new helper command or config variable | `README.md` quick reference |

For a fuller pass, the repo ships a `/update-docs` command that analyses the working tree and
writes a `docs-update.todo.md` plan.

If the change is routine (whitespace, a value tweak), confirm the push succeeded and stop.

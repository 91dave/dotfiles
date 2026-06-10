# Shared Agent Config

Configuration shared between **Claude Code** (`~/.claude`) and **pi-coding-agent**
(`~/.pi/agent`). Both agents are driven from one source of truth so their instructions
and skills stay in sync.

Anything specific to a single agent lives elsewhere:

- pi-only config (provider/model, extensions): [pi-coding-agent Setup](pi.md)
- Claude-only config: `dotfiles/claude/` (settings, commands)

## Layout

```
dotfiles/agents/
  sync-agents.sh    # builds both instruction files + links skills into both agents
  template.md       # the shared system-prompt source (with a {{HARNESS}} placeholder)
  skills/           # personal skills, symlinked into both agents
    ship-it/  update-dotfiles/  workflow/
```

## What `sync-agents.sh` does

Run it after editing `template.md`, or after adding/removing a personal skill:

```bash
bash agents/sync-agents.sh
```

It performs two jobs:

**1. Builds the per-agent instruction files** from `template.md`, expanding any
`@include.md` references and substituting the `{{HARNESS}}` placeholder per target:

| Output | `{{HARNESS}}` becomes |
|--------|-----------------------|
| `~/.claude/CLAUDE.md` | `Claude Code` |
| `~/.pi/agent/AGENTS.md` | `the pi-coding-agent harness` |

Both files are **auto-generated — never edit them directly.** Edit `template.md` (or the
shared work template, below) and rebuild.

**2. Symlinks skills** into both `~/.claude/skills/` and `~/.pi/agent/skills/`:

- every personal skill in `agents/skills/`, and
- every work skill in `$CLAUDE_ORG_REPO/skills/` (see below).

Personal skills are linked last, so a personal skill **overrides** a work skill of the
same name. Both agents auto-scan their home skills directory, so this is all that's
needed for a skill to be discovered (pi keeps its `skills` array in `settings.json` empty
and relies on the auto-scan).

## The shared work template

`template.md` ends with `@CLAUDE-template.md` — the AM-wide developer-experience
template, which lives in the separate **`docs-claude-helpers`** repo, not here.
`sync-agents.sh` resolves that include from `$CLAUDE_ORG_REPO` at build time, so the work
content is folded into both `CLAUDE.md` and `AGENTS.md`.

> Work skills and `CLAUDE-template.md` belong to `docs-claude-helpers` and are out of
> scope for this repo — they are only *referenced*, never copied or committed here.

## Machine-specific path

One value at the top of `sync-agents.sh` is hard-coded to this machine and must be
updated on a fresh install:

- **`CLAUDE_ORG_REPO`** — the local path of your `docs-claude-helpers` clone
  (e.g. `/mnt/c/Code/_docs/docs-claude-helpers`). Provides `CLAUDE-template.md` and the
  work skills.

## Install

`./manage.sh install` runs `sync-agents.sh` automatically after copying the
agent-specific config, so a normal install builds both instruction files and wires up all
skills. There is nothing to run by hand unless you edit `template.md` or a skill
afterwards.

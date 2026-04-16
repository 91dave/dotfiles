# pi-coding-agent Setup

Configuration and extensions for [pi-coding-agent](https://github.com/mariozechner/pi-coding-agent), a terminal-based coding agent.

## Files

All pi-related dotfiles live under `dotfiles/pi/` and install to `~/.pi/agent/`:

| File | Description |
|------|-------------|
| `settings.json` | Core pi config: provider, model, theme, packages, agent directories |
| `template.md` | Source file for the system prompt (`AGENTS.md`) |
| `build-agents-md.sh` | Script to regenerate `AGENTS.md` from `template.md` and its `@include` references |
| `extensions/subagent/index.ts` | Custom subagent tool — delegates tasks to specialised agents in isolated context windows |
| `extensions/subagent/agents.ts` | Agent discovery logic (reads from `~/.pi/agent/agents/` and `agentDirs` in settings) |

## System Prompt Workflow

The live system prompt (`~/.pi/agent/AGENTS.md`) is auto-generated — **don't edit it directly**.

The source files are:
- `template.md` — the main content, with `@filename.md` include directives
- `CLAUDE.md` / `CLAUDE-template.md` / `include/` — symlinks into a separate work repo (`docs-claude-helpers`), providing work-specific context

To rebuild `AGENTS.md` after editing `template.md`:

```bash
cd ~/.pi/agent
./build-agents-md.sh
```

## settings.json — Machine-Specific Paths

Two values in `settings.json` are hard-coded to this machine and will need updating on a fresh install:

- **`agentDirs`** — points to `/mnt/c/Code/_docs/docs-claude-helpers/agents` (work agents repo)
- **`skills`** — points to `/mnt/c/Code/_docs/docs-claude-helpers/skills`

Update these to match the local path of your `docs-claude-helpers` clone.

## Extensions

The `subagent` extension is a custom pi tool that spawns isolated `pi` subprocesses to handle parallel, sequential (chain), or single delegated tasks. It is loaded automatically from `~/.pi/agent/extensions/subagent/`.

It reads agent definitions (`.md` files with frontmatter) from:
1. `~/.pi/agent/agents/` — personal user agents
2. `.pi/agents/` — project-local agents (opt-in per invocation)
3. Any directories listed in `agentDirs` in `settings.json`

## Installing

```bash
./manage.sh install
```

This copies all files from `dotfiles/pi/` to `~/.pi/agent/` and creates the `extensions/subagent/` directory if needed. After installing, run `build-agents-md.sh` to regenerate `AGENTS.md`.

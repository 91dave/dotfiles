# Ralph - Autonomous Coding Agent Loop Runner

An autonomous loop runner that iterates Claude Code over a set of tasks until all work is complete or an error is encountered.

## Usage

```bash
source dotfiles/lib/ralph.sh

ralph [-p <prompt>] [-n <iterations>] [-i] [-l] [-v] [--pi|--claude] [--pause] [-- arg1 arg2 ...]
```

## Options

| Option | Description | Default |
|--------|-------------|---------|
| `-p <prompt>` | Prompt mode: `default`, `azure`, a file path, or literal text | `default` |
| `-n <count>` | Maximum iterations (implies `-i` when set to `1`) | `10` |
| `-i` | Interactive mode — launches Claude without headless `-p` flag (implies `-n 1`) | Off |
| `-l` | Use native Linux `claude` binary instead of Windows `claude.exe` | Windows mode |
| `-v, --verbose` | Show all tool calls in progress output (default shows only progress-relevant calls) | Off |
| `--claude` | Use Claude Code as the underlying agent (default) | Claude Code |
| `--pi` | Use pi-coding-agent as the underlying agent | Claude Code |
| `--pause` | Prompt for confirmation before each iteration | Off |
| `-h, --help` | Show help | |

Positional arguments after `--` are substituted into the prompt as `{{1}}`, `{{2}}`, etc.

## Prompt Modes

### default

Works with a task-file based workflow. Expects a project directory as the first positional argument containing:
- `PLAN.md` - The overall plan
- `progress.md` - Progress log (created automatically if missing)
- `task-*.md` files - Individual task definitions

Claude picks the highest-priority incomplete task, implements it, commits, and marks it done. Prioritises bug-fix/defect tasks.

**Exit signals:**
- `<status>COMPLETE</status>` - All tasks done
- `<status>ERROR: ...</status>` - Unable to fulfil success criteria

```bash
ralph -- /path/to/project
ralph -n 5 -- /path/to/project
```

### azure

Works with Azure DevOps work items. Automatically detected when the first positional argument matches `AB#nnn`.

Claude fetches the work item and its children, picks the next incomplete child task, implements it, commits, and updates Azure DevOps state and comments.

```bash
ralph -- AB#12345
ralph -p azure -- AB#12345
```

### Custom prompts

Provide a file path or literal text:

```bash
# From a file
ralph -p ./my-prompt.txt -- arg1 arg2

# Literal text
ralph -p "Review and fix all TODO comments in {{1}}" -- /path/to/project
```

## Controlling a Running Loop

From another terminal, navigate to the **same directory** the ralph loop is running in and use:

| Command | Effect |
|---------|--------|
| `ralph-pause` | Pause after the current iteration (prompts to continue) |
| `ralph-stop` | Stop after the current iteration |

These work by creating signal files (`.ralph-pause`, `.ralph-stop`) in the working directory, which ralph checks between iterations. Signal files are cleaned up automatically.

## Progress Output

In headless mode, ralph streams filtered progress rather than raw Claude output. Each line is prefixed with elapsed time:

```
[+ 0m05s]   ▶ Bash: git status
[+ 0m12s]   ◇ Updating the configuration file...
[+ 1m30s]   ✓ Done: 8 turns, $0.42, 90s
```

- **▶** — Tool call (name and key input)
- **◇** — Assistant text
- **✓** — Iteration summary (turns, cost, duration)
- **⏳** — API retry (on transient errors)

By default, low-noise tools (Glob, Read, Grep, ToolSearch, TodoWrite, and trivial Bash commands) are hidden. Use `-v` to show everything.

## How It Works

1. Resolves the prompt (built-in mode, file, or literal text)
2. Substitutes `{{1}}`, `{{2}}`, etc. with positional arguments
3. Runs Claude Code with `--permission-mode auto` for each iteration
4. After each iteration, checks output for exit signals:
   - **`<status>COMPLETE</status>`** - Exits successfully (return 0)
   - **`<status>ERROR...</status>`** - Exits with failure (return 1)
5. Repeats until complete, error, or max iterations reached

## Examples

```bash
# Run default task workflow against a project (up to 10 iterations)
ralph -- /path/to/project

# Limit to 5 iterations
ralph -n 5 -- /path/to/project

# Work on an Azure DevOps item
ralph -- AB#12345

# Pause between iterations for review
ralph --pause -- /path/to/project

# Single interactive iteration (equivalent to -n 1)
ralph -i -- /path/to/project

# Verbose output — see all tool calls
ralph -v -- /path/to/project

# Use pi-coding-agent instead of Claude Code
ralph --pi -- /path/to/project

# Use native Linux claude binary
ralph -l -- /path/to/project

# Custom prompt from file
ralph -p ./prompts/review.txt -- /path/to/project
```

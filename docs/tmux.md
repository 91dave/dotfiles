# tmux

Config lives in [`dotfiles/tmux.conf`](../dotfiles/tmux.conf), symlinked to `~/.tmux.conf`
by `install.sh`. Prefix is `Ctrl+w`, not the default `Ctrl+b`.

## Keys

| Key | Action |
|-----|--------|
| `prefix v` | Split vertically |
| `prefix h` | Split horizontally |
| `prefix r` | Rotate windows |
| `prefix t` | Scratch terminal in a popup |
| `prefix a` | Agent picker: jump to any AI agent pane in any session |

## Session helpers

Three fzf pickers, all with previews:

| Command | Alias | Lists |
|---------|-------|-------|
| `tmux-sessions` | `ts` | Live tmux sessions, previewing the active pane |
| `claude-sessions` | `cs` | Past Claude Code transcripts, to resume or fork |
| `agent-state pick` | `agents` | Agent panes across every session, by state |

`cc` and `pca` launch Claude Code and pi in a dedicated session named after the current
folder (`cc-dotfiles`, `pi-dotfiles`), picking the next free name if one is taken.

`claude-sessions` hides sessions that never got a turn, so a window opened only to run
`/login` or `/clear` never reaches the picker. A session counts as having a turn once it
holds an agent reply, or a prompt of your own beyond slash-command plumbing, so one
interrupted before the first reply is still listed. A live session is always listed
whatever its state, and `bash dotfiles/bin/claude-sessions.test.sh` covers the rules.

## Agent state

AI agents report what they are doing to tmux, so a glance at the status bar tells you
which sessions need you. This is a small local alternative to an agent-aware multiplexer
such as herdr, built on tmux primitives rather than replacing tmux.

### States

Most urgent first. The first four are the blocked family: the agent has stopped and cannot
continue without you.

| State | Glyph | Meaning |
|-------|-------|---------|
| `permission` | 🔐 | The agent wants permission to run something |
| `question` | ❓ | The agent has asked you a question |
| `plan` | 📝 | The agent has a plan waiting for review |
| `waiting` | ✋ | Blocked on you for some other reason, such as an MCP dialog |
| `done` | ✅ | The turn is over, so it is your move |
| `working` | ⏳ | The agent is busy |
| `idle` | 💤 | An agent process with no state recorded, such as a `pi` pane |

The glyph carries the state, so colour is free to carry location instead. See
**Status bar** below.

There is deliberately no separate state for "waiting for chat input". That is exactly what
`done` means, and `Stop` already fires there.

Every glyph is natively double-width. Avoid variation-selector emoji such as ⚙️ or 🗺️ if
you change the palette: terminals disagree about their width and the status bar will
misalign.

### How it works

| Event | Matcher | State |
|-------|---------|-------|
| `SessionStart` | all | `idle` |
| `UserPromptSubmit` | all | `working` |
| `PostToolUse` | all | `working` |
| `PreToolUse` | `AskUserQuestion` | `question` |
| `PreToolUse` | `ExitPlanMode` | `plan` |
| `Notification` | `permission_prompt` | `permission` |
| `Notification` | `agent_needs_input`, `elicitation_*` | `waiting` |
| `Stop` | all | `done` |
| `SessionEnd` | all | `end`, which clears everything |

`SessionStart` is what makes an agent appear the moment it boots, before it has done
anything. That is also why `idle` is shown in the status bar rather than hidden: a booted
agent with nothing to report is still worth seeing.

Every hook calls `agent-state hook <state>`, which writes two things.

**A state file**, at `~/.local/state/agent-state/<agent pid>`, three lines:

```
working                            the state
%7                                 its tmux pane, empty when not in tmux
/mnt/c/Code/_personal/dotfiles     its working directory
```

**Tmux options, only when the agent is in a pane**: `@agent` on the pane and `@agent_win`
on the window. These exist solely so tmux formats can colour window tabs, which they can
only do by reading an option directly.

### Reading starts from the state files, never from tmux

The state directory **is** the list of agents: one file per agent, so duplicates are not
possible. Reading walks that directory and maps each recorded pane back to its tmux
session, rather than the other way round.

Starting from tmux instead looks tempting, and is wrong. A grouped session shares its
windows, so `tmux list-panes -a` reports the same pane once per session in the group, and
every agent in a grouped session appears twice. Keyed by pane, those collapse to one
entry for free, and the session named after the group is the one shown.

The consequence to know about: an agent with no state file does not appear at all. There
is no process-name detection any more. Since `SessionStart` writes the file the moment an
agent boots, the only agents this hides are ones whose tool has no hooks wired up, `pi`
among them.

### Why the hook costs almost nothing

It reads no stdin, parses no JSON, and runs no `jq`. Everything it records is already in
its own environment:

| Needed | Taken from |
|--------|-----------|
| the agent's directory | `$PWD`, which the hook inherits |
| its tmux pane | `$TMUX_PANE` |
| its identity | the first ancestor process whose name is a known agent |

That last one is worth explaining. Claude runs hooks through `sh -c`, so `$PPID` is a
throwaway shell, not the agent. Rather than assume a fixed number of hops, `agent_pid`
walks up the process tree until it finds a process named in `AGENT_STATE_COMMANDS`. That
survives Claude changing how it spawns hooks, and it costs only a few `/proc` reads with
no subprocesses.

Keying the file by pid also gives **liveness for free**: a reader tests `kill -0` on the
filename. An agent killed with no chance to clean up leaves a file that the next read
notices is dead and removes. Nothing else needs to track whether an agent is alive.

### Agents that are not in tmux

An agent started in a plain terminal records an empty pane in its state file. It still
appears everywhere, because the state file does not care where the agent is running:

```
💤  idle        dave                    not in tmux           ~
```

The session column reads `not in tmux`, which is the signal that this one cannot be
jumped to. Pressing enter on it in the picker says so rather than doing nothing, and its
preview explains why instead of showing pane contents. In the status bar it is coloured
as "elsewhere", since it is definitionally never the session you are sitting in.

They sort last, after every reachable agent.

An agent that **is** in tmux is never listed twice: its state file names a pane, and a
single `list-panes` call confirms that pane is still alive.

The kinds are told apart **structurally**, by which event and matcher fired, never by
parsing notification text. `AskUserQuestion` and `ExitPlanMode` are ordinary tool calls,
so `PreToolUse` fires for them and the matching `PostToolUse` returns the pane to
`working` once you answer.

Approving a plan is itself a permission decision, so `ExitPlanMode` fires `PreToolUse`
(`plan`) and then a `permission_prompt` notification a moment later. Both describe the
same block, but `plan` says something useful and `permission` does not, so **`permission`
and `waiting` never replace `question` or `plan`**. Without that rule the 📝 flickers to
🔐 after a second or two. States outside the blocked family, `working` and `done`, always
apply, so a pane can never get stranded.

`Notification` matters most here. It fires for several unrelated reasons, including
`idle_prompt`, which is just the agent noting that nothing has been typed for a minute or
so. **`idle_prompt` is deliberately not wired to anything.** Mapping it to a blocked state
would turn every finished agent magenta a minute later and destroy the meaning of the
colour. Each Notification hook is scoped to an explicit matcher for that reason, and a
test asserts no unmatched Notification hook creeps back in.

`PostToolUse` exists so that approving a permission prompt clears the magenta immediately
rather than leaving it until the turn ends. It is the only hook on a hot path; drop it
from `dotfiles/claude/settings.json` if hook latency ever matters more than that.

`AGENT_STATE_COMMANDS` (default `claude:pi:codex:aider:opencode`) is the list of process
names treated as agents. It is used only when a hook identifies which ancestor process it
belongs to, not for discovering agents.

### Why there is a second, window-level option

A tmux window format resolves a pane option against the window's **active pane only**. An
agent working in a background pane would therefore never colour its window tab. So
`agent-state` also mirrors the state up to the window as `@agent_win`, recomputed from all
panes in that window on every change, taking the most urgent (`waiting` > `done` >
`working`). `window-status-format` reads `@agent_win`, and background agents show up.

### Surfaces

**Status bar**, refreshed every 5 seconds. One entry per agent, never collapsed into
counts:

```
🔐 qtms-publication   ❓ dotfiles   📝 qtms-search   ✅ icepanel-tags   ⏳ qtms-documents
```

Every non-idle agent is named, including the working ones, so the bar is a roster rather
than a summary. Two agents in the same folder appear as two entries. Only `idle` is left
out, since an agent with no state recorded has nothing to report.

**Colour means location, not state.** The glyph already says what the agent wants, so
colour answers the other question: which of these is the session I am in? That one is
white, the same colour as everything else on the status line, so it reads as part of the
bar. Agents elsewhere are black and recede against it. Backgrounds are deliberately left
alone so the bar stays an even block of colour.

Two things were tried first and abandoned. State-based colouring fails because the glyph
already carries the state, and the colours it needs collide with the bar itself. The bar
was also green (`bg=green,fg=black`), which made emoji muddy and rendered green text
invisible. It is now `bg=colour238,fg=white`, a grey bar that every glyph reads cleanly
against.

The status line passes `#{session_name}` into the job, which tmux expands per client, so
each attached session colours its own bar correctly. The colours are tmux options, so
they can be retuned live, without editing a file or reloading:

```bash
tmux set -g @agent_colour_here      white
tmux set -g @agent_colour_elsewhere black
```

The bar picks the change up on its next refresh. Unset either one to fall back to the
default.

**Order is stable**, by session then pane id, and never changes as states change. Sorting
the bar by urgency meant entries jumped sideways every time a hook fired, which made it
unreadable at a glance. The picker still leads with the most urgent, since it is read
deliberately rather than glanced at.

**Window tabs**, coloured by `@agent_win`, including agents in background panes.

**Picker** on `prefix a` (or `agents` in a shell), sorted most urgent first, with a live
`capture-pane` preview so you can read what an agent is asking before jumping. Enter
switches session, window and pane in one go.

### Acknowledging

Landing on a finished agent is the acknowledgement, so its `done` state is dropped and the
green ✅ disappears. A blocked agent keeps its state until the agent itself moves on,
because arriving at the pane is not the same as answering the question.

This is wired to the `after-select-pane` hook, so it works however you got there, not just
via the picker. Note that `pane-focus-in` does **not** fire without an attached client,
which is why `after-select-pane` is used instead.

### Commands

```bash
agent-state status cc-foo   # roll-up, colouring session cc-foo as "here"
agent-state list            # one row per agent pane, most urgent first
agent-state pick            # fzf picker (aliased to `agents`)
agent-state set plan %12    # stamp a pane by hand
agent-state clear %12       # drop a pane's state
agent-state --help
```

### Labelling: the folder, not the session

A session is named once, by `cc`, after the folder it was started in. Start an agent in a
different folder from inside that session, whether by running `claude` directly or
resuming with `cs`, and the session name is stale. It describes where tmux began, not
where the agent is working.

So panes are labelled by the folder the agent is actually in, as
`{folder}-w{window}-p{pane}`:

```
🔐  permission  dotfiles-w0-p1          cc-qtms-publication   /mnt/c/Code/_personal/dotfiles
⏳  working     dotfiles-w0-p1          cc-dotfiles           /mnt/c/Code/_personal/dotfiles
💤  idle        qtms-publication-w0-p0  cc-qtms-publication   /mnt/c/Code/quartex-services/qtms-publication
```

The first pane is an agent working on `dotfiles` inside a session called
`cc-qtms-publication`. The label tells you what it is working on, the second column tells
you where to find it, and the path disambiguates two worktrees sharing a basename.

The folder comes from the state file, recorded as the directory the hook itself was
running in. That is the agent's own working directory, and it survives any `cd` inside the
pane, since those happen in a subshell the agent never leaves.

The status bar names folders for the same reason:

```
🔐 qtms-publication   ✅ qtms-documents   ⏳ dotfiles
```

Labels are display only. Jumping always goes by tmux pane id, so the format is free to
change without touching navigation.

Every command is safe to run outside tmux and against a pane that has already closed, so a
hook can never fail the agent that called it.

### Tests

```bash
bash dotfiles/bin/agent-state.test.sh
```

Runs against a throwaway tmux server on a private socket, via a `tmux` shim on `PATH`, so
the real server is never touched.

### Gotchas

- Changes to `dotfiles/claude/settings.json` need a Claude Code restart to take effect.
- `tmux display-message -p` never executes `#()` jobs, so it cannot be used to check
  whether the status bar's shell command works. Run the command directly instead.
- A detached tmux server never draws a status line, so `#()` jobs never run on one.

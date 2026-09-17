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
| `prefix s` | Session picker: `tmux-sessions` in a popup, replacing the built-in `choose-tree` |

## Session helpers

Three fzf pickers, all with previews:

| Command | Alias | Lists |
|---------|-------|-------|
| `tmux-sessions` | `ts` | Live tmux sessions, previewing the active window |
| `claude-sessions` | `cs` | Past Claude Code transcripts, to resume or fork |
| `agent-state pick` | `agents` | Agent panes across every session, by state |

`cc` and `pca` launch Claude Code and pi in a dedicated session named after the current
folder (`cc-dotfiles`, `pi-dotfiles`), picking the next free name if one is taken.

`tmux-sessions` previews the whole active window, not just its active pane: one labelled
block per pane, `*` marking the active one, the visible lines split evenly between them. A
window with a single pane is shown unlabelled, since the label would say nothing the
window list above it does not.

`tmux-sessions` marks the session you are in with `●` and one attached on another terminal
with `○`. The distinction matters because the two do opposite things: enter on `●` only
closes the picker, while enter on `○` detaches that other terminal (see *One terminal per
session*). It hides views of a live session unless given `--include-views`.

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
| `idle` | 💤 | Up with nothing to report: freshly booted, or a finished turn you acknowledged |

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

The agent picker is the session picker with a pane on the end of it, so it does not own any
switching logic. `agent-state jump` selects the window and pane, then hands the session to
`tmux-sessions --attach`, which decides between a no-op, a takeover and a plain attach. An
agent already in the session you are sitting in therefore costs nothing but the two selects.

Selecting before attaching, rather than after, is what makes that delegation possible: both
commands work on a session with no client, so the session is already sitting on the right
pane when you arrive. Doing it the other way round meant `tmux-sessions` could never be
handed the attach, since it `exec`s, and outside tmux `attach-session` blocks until you
detach, so the selects landed after you had gone.

### One terminal per session

A session is only ever on one terminal. Arriving at one that another client holds detaches
that client first, so both pickers take the session over rather than sharing it. Nothing is
killed: the session, its windows and everything running in them are untouched, and the
other terminal drops back to whatever it was before it attached.

The alternative was a *view*: a grouped session (`tmux new-session -t cc-foo -s
cc-foo-view`) sharing the original's windows, so two clients could sit on the same session
with their own current window each. That is only worth having if you deliberately run two
terminals on one session, which this setup never does. It cost a filter in the picker to
hide the views, cleanup to stop them accumulating, and a whole class of bug where a jump
inside the current session saw its own client attached and stranded you in a view of the
session you were already in.

Taking over also fixes the usual reason a session looks busy: a stale client from a
terminal closed without tmux noticing. A view worked around that by spawning a second
session; detaching clears it. And with `window-size latest` (the default), two live clients
of different sizes on one session keep resizing its windows out from under each other.

Views are no longer created, but leftovers from before still exist on a long-lived server.
`tmux-sessions` hides a view while its original is alive, since listing both is the same
windows twice. `--include-views` lists them so `alt-d` can clear them out. Two sessions are
always listed whatever the flag says: the one you are in, so the `●` never goes missing,
and a view whose original has been killed, since it is the only way left to reach those
windows.

### Acknowledging

Landing on a finished agent is the acknowledgement, so it drops back to `idle` and the
green ✅ becomes 💤. A blocked agent keeps its state until the agent itself moves on,
because arriving at the pane is not the same as answering the question. Only `done` is
acknowledged this way.

It goes back to `idle` rather than being deleted. Deleting the state file would take the
agent out of the roster entirely, and a finished agent you have read is still an agent
worth seeing.

Acknowledging rewrites the **state file**, and unsets the pane option as well so the window
tab loses its colour. Doing only the latter is a silent no-op: nothing reads `@agent` except
the tab formats.

Arriving at a pane takes four different routes, and each fires its own tmux hook:

| Getting there | Hook |
|---------------|------|
| Selecting a pane, including with the mouse and via the picker | `after-select-pane` |
| Switching window | `after-select-window` |
| Switching session, and attaching | `pane-focus-in`, `client-session-changed` |

All four are wired to `agent-state ack #{pane_id}`, which resolves to the pane you have
landed on in every case. Acknowledging is idempotent, so the overlap between the last two
costs nothing.

`pane-focus-in` does not fire without an attached client, which is why it cannot be the
only hook. With a client attached it fires on every session switch, and needs no
`focus-events` setting to do it.

One case is deliberately left alone: an agent that finishes in the pane you are **already**
sitting in. No focus hook fires, because focus never changed, so its ✅ stands until you
leave and come back. Clearing it would mean treating "attached to that session" as "looking
at the screen", which is not the same thing.

### Alerts

Reaching a state that wants your attention flashes a one-line message on every attached
terminal:

```
✅ dotfiles: Quality of life updates for agent-state
```

It expires by itself after four seconds, so **there is never an alert to clear**, in one
session or twelve. That is the whole reason for the design. tmux's own `monitor-bell` and
`monitor-activity` were rejected for the opposite property: they raise a per-window `!`
flag that has to be cleared by visiting each window, and a grouped session shows the same
flag more than once.

Two rules keep it quiet:

- **A terminal already sitting on that agent is skipped.** You are looking at it; a toast
  telling you what you can see is noise.
- **The alert is edge-triggered**, raised by the hook on the transition into the state, not
  polled. The bar refreshes every five seconds, so a level-triggered alert would fire
  forever. Re-recording the same state, which `PostToolUse` does constantly, says nothing.

`working` and `idle` never alert. `permission`, `question`, `plan`, `waiting` and `done` all
do, which is the same set the glyphs mark as needing you.

An agent outside tmux alerts every attached terminal, since there is no pane of its own for
one of them to be sitting on.

This costs the hot path one extra read of a 45-byte file, to see what the previous state
was. The tmux calls that render the toast only happen on a transition that alerts, which is
once or twice a turn.

### Commands

```bash
agent-state status cc-foo   # roll-up, colouring session cc-foo as "here"
agent-state list            # one row per agent pane, most urgent first
agent-state pick            # fzf picker (aliased to `agents`)
agent-state set plan %12    # stamp a pane by hand
agent-state ack %12         # acknowledge it, if it had finished
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

### Session titles

Where Claude has given a session a title, that is shown instead of the folder:

```
✅ dave: Failed publish alert Production   ⏳ dotfiles: show-claude-session-title   💤 qtms-publication
```

The third has no title yet, so it falls back to the bare folder. There is never a dangling
`folder: ` prefix.

**Inside tmux the title is free.** Claude sets the pane title, so `pane_title` already
carries it and `load_panes()` picks it up from the `list-panes` call it was making anyway.
The leading status glyph (`✳ `) is stripped, and the literal `Claude Code` is treated as
"no title yet".

**Outside tmux it has to be read.** tmux fills `pane_title` from an escape sequence the
application emits; with no tmux in between that escape reaches the terminal and is gone.
Nothing in `/proc` or the session marker keeps it. So for those agents the `Stop` hook
reads the last `{"type":"ai-title"}` line from the transcript and caches it in
`<agent pid>.title` beside the state file.

That read only happens when the agent is **both** finishing a turn **and** outside tmux, so
the common path stays free. It tails the last 256KB rather than scanning the file: titles
are rewritten every turn and the last one sits a median 13 lines from the end, never more
than 30 across 87 transcripts here, while the files themselves run to megabytes.

Titles are free text, so a `#` is escaped to `##` before it can reach the status bar, where
tmux would otherwise read it as a format directive.

### Fitting the bar

`agent-state status --with-folder` renders `folder: title` rather than just the title, and
`--width` tells it how many columns the client has. `tmux.conf` passes both, taking the
width from `#{client_width}` so the bar adapts to the actual terminal.

**No agent is ever dropped to make room.** Letting the bar overflow would have tmux
truncate the right-hand end, and since entries are ordered by session, the agent that
vanished would be arbitrary rather than the least important. One needing your attention
could disappear. So detail is shed instead, in order of how little it tells you:

| Room | Shown | Roughly |
|------|-------|---------|
| Plenty | `service-00: Refactoring the storage laye` | up to ~4 agents |
| Less | `Refactoring the st` | ~8 agents |
| Less still | `Refactorin` | ~12 agents |
| Tight | `service-00` | ~16 agents |

The folder goes before the title does, because the title says more about what an agent is
doing. Titles are capped at 28 characters however much room there is, and are dropped
entirely rather than shown below 8, where they read as noise.

Those bands assume a 236-column terminal and short folder names; the calculation is
per-render, from the real width and the longest folder in play.

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

# Shell Helpers

Shell-level configuration: history capture and search, the fzf integration, and detection of the optional command-line tools those depend on. Loaded from `dotfiles/lib/shell.sh`.

Development aliases and functions live in [Development Helpers](dev.md).

## Configuration

Set these before `~/.bashrc` sources `~/.bash_prefs`, or export them and run `reload`.

| Variable | Values | Purpose |
|----------|--------|---------|
| `HISTORY_ATUIN` | `true` / `false` | Capture shell history into atuin's database and run its daemon |
| `HISTORY_SEARCH` | `default` / `fzf` / `atuin` | Which interface CTRL+r opens |
| `HISTORY_ATUIN_PTY` | `true` / `false` | Enable atuin's experimental pty-proxy |
| `WARN_MISSING_HELPERS` | `true` / `false` | Warn on shell startup when an optional tool is missing |

These are personal preferences rather than fixed settings, so the shipped values change. Run
`shell_help` to see what is currently in effect.

### Capture and search are independent

`HISTORY_ATUIN` controls whether commands are recorded. `HISTORY_SEARCH` controls only what CTRL+r opens. You can record everything into atuin while keeping the fzf picker: atuin is initialised with `--disable-ctrl-r` so it never claims the key.

The one combination that cannot work is `HISTORY_SEARCH=atuin` with `HISTORY_ATUIN=false`, since there would be no database to search. That falls back to the bash default and warns.

### Load order

`shell.sh` sources `~/.fzf.bash` first, because fzf binds CTRL+r as a side effect of loading. atuin is initialised second so it can take the key back when asked. `HISTORY_SEARCH=default` is reclaimed explicitly afterwards, because by that point fzf already owns the binding.

atuin's pty-proxy has to be initialised before `atuin init`, so it runs first inside `_init_atuin`. Builds without the `pty-proxy` subcommand fail quietly and the rest of the setup continues.

## atuin

[atuin](https://atuin.sh) replaces the flat `~/.bash_history` file with a SQLite database, giving searchable history with the working directory, exit code, and duration recorded against each command.

### Installation

Not installed by `install.sh` — it is a third-party binary, so it stays a deliberate choice:

```bash
curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh
exec bash
```

Until then, `shell.sh` warns once per shell and leaves history capture off. Run `atuin_help` for the same instructions from the prompt.

`~/.bash-preexec.sh` is not needed. Current atuin builds fall back to a built-in preexec implementation when it is absent.

### Configuration

`dotfiles/atuin/config.toml` is symlinked to `~/.config/atuin/config.toml`:

```toml
auto_sync = false
update_check = false
search_mode = "daemon-fuzzy"

[daemon]
enabled = true
autostart = true
```

**Sync is off.** atuin's sync is opt-in and inert until you run `atuin login` or `atuin register`, which these dotfiles never do. `auto_sync = false` is set anyway so an accidental login still will not push history to a server.

**AI is off.** atuin's AI features are opt-in and are configured through an `[ai]` block. There isn't one, so they stay off. There is nothing to disable.

**The daemon is on.** `autostart = true` matters on WSL: it makes the CLI start and manage the daemon itself rather than relying on systemd, which WSL does not run by default. `search_mode = "daemon-fuzzy"` uses the daemon's in-memory index.

### pty-proxy

pty-proxy is a lightweight PTY wrapper that lets the search interface draw over your terminal output instead of clearing the screen. It is **experimental** and wraps every interactive shell in a proxy PTY, which is worth knowing about when stacked underneath WSL and tmux.

It has its own toggle so you can drop it without losing history capture:

```bash
HISTORY_ATUIN_PTY=false
```

### Usage

```bash
atuin search <term>   # search history from the command line
atuin stats           # history statistics
atuin doctor          # diagnose a broken setup
```

## Bash history

Applies whether or not atuin is enabled, and keeps the plain history file usable as a fallback:

```bash
HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend
```

`histappend` matters most: without it, the last shell to exit overwrites the history of every other shell.

## fzf

The fzf integration and its preview configuration live here. See [Development Helpers](dev.md#fzf) for installation and general usage.

```bash
export EZA_PREVIEW="eza --tree -l --color=always --git-ignore --no-time --no-permissions --no-user"
export BAT_PREVIEW="batcat -n -S --color=always --line-range :500"
export BAT_THEME=Dracula

export FZF_PREVIEW="if [ -d {} ]; then $EZA_PREVIEW {} | head -200; else $BAT_PREVIEW {}; fi"
export FZF_DEFAULT_COMMAND="fdfind --no-ignore-parent --no-follow | sort"
export FZF_CTRL_T_OPTS="--height=70% --layout=reverse --preview-window=60% --preview '$FZF_PREVIEW'"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
```

| Binding / command | Effect |
|-------------------|--------|
| `CTRL+t` | Fuzzy file picker with preview |
| `CTRL+r` | History search, per `HISTORY_SEARCH` |
| `pf` | Same picker as CTRL+t, run directly |
| `cd **<TAB>` | Directory completion with a tree preview |

`_fzf_comprun` sets the preview per command: `eza` tree for `cd`, variable values for `export`/`unset`, `dig` output for `ssh`, and the standard file preview otherwise.

## Optional tools

Checked on interactive startup, warning once each when missing. Set `WARN_MISSING_HELPERS=false` to silence them.

| Tool | Install | Used for |
|------|---------|----------|
| `batcat` | `sudo apt install bat` | Syntax-highlighted file previews; aliased to `bat` |
| `eza` | `sudo apt install eza` | Directory tree previews |
| `fdfind` | `sudo apt install fd-find` | fzf's file-listing backend |
| `fzf` | `git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install` | The picker itself |
| `atuin` | `curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh \| sh` | History capture and search |

## Troubleshooting

**CTRL+r opens the wrong thing.** Check `shell_help` for the value actually in effect — an invalid combination silently falls back. `bind -X | grep C-r` shows which function currently owns the key.

**History is not being recorded.** Confirm `command -v atuin` resolves and that `HISTORY_ATUIN=true`. Then `atuin doctor`, and `atuin stats` to check rows are arriving.

**The shell feels slow or the display corrupts.** Set `HISTORY_ATUIN_PTY=false` and `exec bash`. pty-proxy is the experimental part and the first thing to rule out.

**A change to the vars does nothing.** They are read at load time. Run `reload`, or `exec bash` for anything that rebinds a key.

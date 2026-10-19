# Shell Helpers

Shell-level configuration: history capture and search, the fzf integration, and detection of the optional command-line tools those depend on. Loaded from `dotfiles/lib/shell.sh`.

Development aliases and functions live in [Development Helpers](dev.md).

## Configuration

Set these before `~/.bashrc` sources `~/.bash_prefs`, or export them and run `reload`.

| Variable | Values | Purpose |
|----------|--------|---------|
| `HISTORY_SEARCH` | `default` / `fzf` | Which interface CTRL+r opens |
| `WARN_MISSING_HELPERS` | `true` / `false` | Warn on shell startup when an optional tool is missing |

These are personal preferences rather than fixed settings, so the shipped values change. Run
`shell_help` to see what is currently in effect.

### Load order

`shell.sh` sources `~/.fzf.bash` first, because fzf binds CTRL+r as a side effect of loading. `HISTORY_SEARCH=default` is reclaimed explicitly afterwards, because by that point fzf already owns the binding. If fzf is missing, `HISTORY_SEARCH=fzf` falls back to the bash default.

## Bash history

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

## Troubleshooting

**CTRL+r opens the wrong thing.** Check `shell_help` for the value actually in effect — an invalid combination silently falls back. `bind -X | grep C-r` shows which function currently owns the key.

**A change to the vars does nothing.** They are read at load time. Run `reload`, or `exec bash` for anything that rebinds a key.

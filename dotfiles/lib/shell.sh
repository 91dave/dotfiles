#!/bin/bash

bash_debug "Loading shell.sh"

# Configuration
WARN_MISSING_HELPERS="${WARN_MISSING_HELPERS:-true}" # Set to FALSE to skip warning when missing useful helpers
HISTORY_SEARCH="${HISTORY_SEARCH:-fzf}"              # CTRL+r interface: default | fzf

HISTSIZE=100000
HISTFILESIZE=200000
HISTCONTROL=ignoreboth:erasedups
shopt -s histappend

function shell_help() {
    echo "🐚 Shell Helpers"
    echo ""
    echo "  pf                        Fuzzy file picker with preview"
    echo ""
    echo "💡 Config vars (set before sourcing ~/.bash_prefs):"
    echo "  HISTORY_SEARCH=$HISTORY_SEARCH        (default | fzf)"
}

export EZA_PREVIEW="eza --tree -l --color=always --git-ignore --no-time --no-permissions --no-user"
export BAT_PREVIEW="batcat -n -S --color=always --line-range :500"
export BAT_THEME=Dracula

export FZF_PREVIEW="if [ -d {} ]; then $EZA_PREVIEW {} | head -200; else $BAT_PREVIEW {}; fi"
export FZF_DEFAULT_COMMAND="fdfind --no-ignore-parent --no-follow | sort"
export FZF_CTRL_T_OPTS="--height=70% --layout=reverse --preview-window=60% --preview '$FZF_PREVIEW'"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

function _warn_shell_helper() {
    [ "$WARN_MISSING_HELPERS" = "true" ] && echo $@
}

_fzf_comprun() {
    local command=$1
    local height="--height=100%"
    shift

    case "$command" in
        cd)             fzf $height --preview "$EZA_PREVIEW {} | head -n200" "$@" ;;
        export|unset)   fzf $height --preview "eval 'echo $'{}"         "$@" ;;
        ssh)            fzf $height --preview 'dig {}' ;;
        *)              fzf $height --preview "$FZF_PREVIEW" "$@" ;;
    esac
}

function _shell_helpers() {
    if [ -z "$(which batcat)" ]; then
        _warn_shell_helper "batcat not found: install via 'sudo apt install bat'"
    else
        alias bat="batcat"
    fi

    if [ -z "$(which eza)" ]; then
        _warn_shell_helper "eza not found: install via 'sudo apt install eza'"
    fi

    if [ -z "$(which fdfind)" ]; then
        _warn_shell_helper "fdfind not found: install via 'sudo apt install fd-find'"
    fi
}

function _init_fzf() {
    if [ -f ~/.fzf.bash ]; then
        source ~/.fzf.bash
        alias pf="fzf $FZF_CTRL_T_OPTS"
        return 0
    fi

    _warn_shell_helper "fzf not found: install via 'git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install'"
    [ "$HISTORY_SEARCH" = "fzf" ] && HISTORY_SEARCH=default
    return 0
}

function _init_history() {
    _init_fzf

    [ "$HISTORY_SEARCH" = "default" ] && bind '"\C-r": reverse-search-history'
    return 0
}

if [[ $- == *i* ]]; then
    bind 'set bell-style none'
    _shell_helpers
    _init_history
fi

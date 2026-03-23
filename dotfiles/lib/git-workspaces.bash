#!/bin/bash
# Sourced by git.sh - do not run directly

_gws_help() {
    echo "🗂️  Git WorkSpaces"
    echo "Manage workspaces in $WORKSPACE_HOME"
    echo ""
    echo "Usage:"
    echo "  gws cd <workspace>      📂 pushd into matching workspace"
    echo "  gws claude <workspace>  🤖 Open Claude Code in matching workspace"
    echo "  gws edit <workspace>    🚀 Open VS Code in matching workspace"
    echo "  gws cmd <workspace>     💻 Open WSL window in matching workspace"
    echo "  gws help                📖 Show this help message"
}

# Find a workspace by search term, returns name if exactly one match
_gws_find() {
    local search="$1"

    if [[ -z "$search" ]]; then
        echo "❌ Error: workspace search term required" >&2
        return 1
    fi

    local matches=()
    for dir in "$WORKSPACE_HOME"/*/; do
        [[ -d "$dir" ]] || continue
        local name=$(basename "$dir")
        if [[ "$name" == *"$search"* ]]; then
            matches+=("$name")
        fi
    done

    if [[ ${#matches[@]} -eq 0 ]]; then
        echo "❌ No workspaces found for '$search'" >&2
        return 1
    elif [[ ${#matches[@]} -gt 1 ]]; then
        echo "❌ Multiple workspaces found for '$search':" >&2
        for m in "${matches[@]}"; do
            echo "   $m" >&2
        done
        return 1
    fi

    echo "${matches[0]}"
}

_gws_cd() {
    local search="$1"
    local ws=$(_gws_find "$search") || return 1

    local ws_path="$WORKSPACE_HOME/$ws"
    echo "📂 $ws"
    pushd "$ws_path" > /dev/null
}

_gws_claude() {
    local search="$1"
    local ws=$(_gws_find "$search") || return 1

    local ws_path="$WORKSPACE_HOME/$ws"
    echo "🤖 Opening Claude Code in $ws..."
    (cd "$ws_path" && cmd.exe /c claude)
}

_gws_edit() {
    local search="$1"
    local ws=$(_gws_find "$search") || return 1

    local ws_path="$WORKSPACE_HOME/$ws"
    echo "🚀 Opening VS Code in $ws..."
    (cd "$ws_path" && cmd.exe /c code .)
}

_gws_cmd() {
    local search="$1"
    local ws=$(_gws_find "$search") || return 1

    local ws_path="$WORKSPACE_HOME/$ws"
    echo "💻 Opening WSL in $ws..."
    (cd "$ws_path" && cmd.exe /c start wsl)
}

gws() {
    local cmd="${1:-help}"

    case "$cmd" in
        cd)             _gws_cd "$2" ;;
        claude)         _gws_claude "$2" ;;
        edit|code)      _gws_edit "$2" ;;
        cmd)            _gws_cmd "$2" ;;
        *)              _gws_help ;;
    esac
}

# fzf completion for gws command
_fzf_complete_gws() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[1]:-}"

    # First arg: complete subcommands
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "cd claude edit code cmd help" -- "$cur") )
        return
    fi

    # Second arg: use fzf to pick a workspace
    case "$cmd" in
        cd|claude|edit|code|cmd)
            local selected
            selected=$(ls -1d "$WORKSPACE_HOME"/*/ 2>/dev/null | xargs -n1 basename | \
                fzf --height=70% --layout=reverse --preview "$EZA_PREVIEW $WORKSPACE_HOME/{}")
            if [[ -n "$selected" ]]; then
                COMPREPLY=( "$selected" )
            fi
            printf '\e[5n'
            ;;
    esac
}
complete -F _fzf_complete_gws -o default -o bashdefault gws

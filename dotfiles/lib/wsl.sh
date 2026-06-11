#!/bin/bash


# Windows echo helper
function wecho() {
    OUTPUT=$(cmd.exe /c echo $@ 2> /dev/null)
    echo "$OUTPUT" | sed -e "s|\r||g"
}

## Windows Home variables
export USERPROFILE_WIN=$(wecho %USERPROFILE% | sed -e "s|\\\|/|g")
export USERPROFILE_WSL=$(wslpath $USERPROFILE_WIN)

bash_debug "Loading wsl.sh"

function wsl_help() {
    echo "🐧 WSL Helpers"
    echo ""
    echo "  wslexe <cmd>    Manage WSL interop (get, check, fix, help)"
    echo "  wecho <args>    Echo with windows variable substitution e.g. %USERPROFILE%"
}

function wslexe() {
    local cmd="${1:-help}"

    case "$cmd" in
        check)
            if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
                [ "$2" = "-v" ] && echo "✅ WSL interop enabled"
                return 0
            else
                echo "❌ WSL interop is not enabled. Run 'wslexe fix' to fix."
                return 1
            fi
            ;;
        fix)
            if [ -f "/proc/sys/fs/binfmt_misc/WSLInterop" ]; then
                echo "✅ WSL interop already enabled"
            else
                echo "🔧 Enabling WSL interop..."
                sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'
                echo "✅ WSL interop enabled"
            fi
            ;;
        get)
            shift
            if [ -z "$1" ]; then
                echo "Usage: wslexe get <binary...>"
                return 1
            fi
            for bin in "$@"; do
                if [ -n "$(which ${bin}.exe 2>/dev/null)" ]; then
                    echo ${bin}.exe
                    return
                fi
                if [ -n "$(which $bin 2>/dev/null)" ]; then
                    echo $bin
                    return
                fi
            done
            ;;
        -h|--help|help|*)
            echo "🔧 wslexe - WSL interop manager"
            echo ""
            echo "Usage: wslexe <command>"
            echo ""
            echo "Commands:"
            echo "  get <bin...>  Find first available binary (.exe or native)"
            echo "  check [-v]    Check if WSL interop is working (-v for verbose)"
            echo "  fix           Enable WSL interop for .exe files"
            echo "  help          Show this help message"
            ;;
    esac
}

# Check WSL interop on interactive shell startup
[[ $- == *i* ]] && wslexe check

# Restore the terminal title in the outer shell. tmux owns the title while
# attached (set-titles); this re-asserts it on every prompt once we're back
# out, so detaching/exiting tmux resets it. Skipped inside tmux so it never
# fights set-titles in the panes. Folder name only, matching the \W prompt.
_set_term_title() {
    [ -n "$TMUX" ] && return
    local dir
    [ "$PWD" = "$HOME" ] && dir="~" || dir="${PWD##*/}"
    printf '\033]0;%s@%s: %s\007' "$USER" "${HOST_NICKNAME:-${HOSTNAME%%.*}}" "$dir"
}
[[ "$PROMPT_COMMAND" == *_set_term_title* ]] || \
    PROMPT_COMMAND="_set_term_title${PROMPT_COMMAND:+; $PROMPT_COMMAND}"





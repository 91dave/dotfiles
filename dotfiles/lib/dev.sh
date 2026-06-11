#!/bin/bash

bash_debug "Loading dev.sh"

# Configuration
WARN_MISSING_HELPERS=true # Set to FALSE to skip warning when missing useful helpers

function dev_help() {
    echo "🛠️  Dev Helpers"
    echo ""
    echo "  ce <cmd>                  Manage container engine (check, fix, help)"
    echo "  epoch [timestamp]         Convert Unix timestamp to date"
    echo "  get_nuget_config          Get path to Windows NuGet.Config"
    echo "  push_docker               Build Docker image with NuGet config"
    echo ""
    echo "💡 Aliases:"
    echo "  docker, docker-compose → podman.exe"
    echo "  dotnet → dotnet.exe"
    echo "  gh → gh.exe"
}

alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias podman="podman.exe"
alias dotnet="dotnet.exe"
alias gh="gh.exe"

# Claude Code only reads CLAUDE.md, not the cross-tool AGENTS.md. If the folder
# has an AGENTS.md, drop a CLAUDE.md that imports it and keep that bridge out of
# git via the local exclude file. Pure bash + wslpath — never calls git, so it
# behaves the same on /mnt/c and WSL-native paths, and on worktrees.
_cc_ensure_agents_bridge() {
    [ -f AGENTS.md ] || return 0

    if [ ! -f CLAUDE.md ]; then
        echo "@AGENTS.md" > CLAUDE.md
        echo "🔗 cc: created CLAUDE.md -> @AGENTS.md"
    elif ! grep -qxF "@AGENTS.md" CLAUDE.md; then
        return 0   # a real, hand-written CLAUDE.md — leave it (and don't ignore it)
    fi

    # Locate the git exclude file. Normal repo: .git/info/exclude. Worktree: .git
    # is a file pointing at the gitdir; commondir locates the shared exclude.
    local exclude=""
    if [ -d .git ]; then
        exclude=".git/info/exclude"
    elif [ -f .git ]; then
        local gitdir
        gitdir=$(sed -n 's/^gitdir: //p' .git | tr -d '\r')
        [ -d "$gitdir" ] || gitdir=$(wslpath "$gitdir" 2>/dev/null)
        if [ -d "$gitdir" ]; then
            exclude=$(cd "$gitdir" && cd "$(tr -d '\r' < commondir 2>/dev/null || echo .)" && echo "$PWD/info/exclude")
        fi
    fi
    [ -n "$exclude" ] || return 0

    mkdir -p "$(dirname "$exclude")"
    grep -qE '^/?CLAUDE\.md$' "$exclude" 2>/dev/null || {
        echo "/CLAUDE.md" >> "$exclude"
        echo "🙈 cc: ignored /CLAUDE.md via git exclude (local, untracked)"
    }
}

function cc() {
    _cc_ensure_agents_bridge
    local folder=$(basename "$PWD")
    local base="cc-$folder"
    # Allow duplicates: pick the next free name (cc-foo, cc-foo-2, cc-foo-3...)
    local name="$base" n=2
    while tmux has-session -t "=$name" 2>/dev/null; do
        name="$base-$n"
        ((n++))
    done
    if [ -n "$TMUX" ]; then
        # Already inside tmux: create a detached session and switch to it
        tmux new-session -d -s "$name" claude "$@" && tmux switch-client -t "$name"
    else
        tmux new-session -s "$name" claude "$@"
    fi
}


function _warn_dev_helper() {
    [ "$WARN_MISSING_HELPERS" = "true" ] && echo $@
}

export EZA_PREVIEW="eza --tree -l --color=always --git-ignore --no-time --no-permissions --no-user"
export BAT_PREVIEW="batcat -n -S --color=always --line-range :500"
export BAT_THEME=Dracula

export FZF_PREVIEW="if [ -d {} ]; then $EZA_PREVIEW {} | head -200; else $BAT_PREVIEW {}; fi"
export FZF_DEFAULT_COMMAND="fdfind --no-ignore-parent --no-follow | sort"
export FZF_CTRL_T_OPTS="--height=70% --layout=reverse --preview-window=60% --preview '$FZF_PREVIEW'"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"

function _dev_helpers() {
    # Check for batcat
    if [ -z "$(which batcat)" ]; then
        _warn_dev_helper "batcat not found: install via 'sudo apt install bat'"
    else
        alias bat="batcat"
    fi

    # Check for eza
    if [ -z "$(which eza)" ]; then
        _warn_dev_helper "eza not found: install via 'sudo apt install eza'"
    fi

    # Check for fd
    if [ -z "$(which fdfind)" ]; then
        _warn_dev_helper "fdfind not found: install via 'sudo apt install fd-find'"
    fi

    # Check for fzf
    if [ -f ~/.fzf.bash ]; then
        source ~/.fzf.bash
        alias pf="fzf $FZF_CTRL_T_OPTS"
    else
        _warn_dev_helper "fzf not found: install via 'git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf && ~/.fzf/install'"
    fi
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

function epoch() {
    date -d "@$1"
}

function get_nuget_config() {

    wslpath "$(cmd.exe /k "echo %appdata%\\NuGet\\NuGet.Config & exit" 2>/dev/null)"

}

function push_docker() {

    nuget_conf=$(get_nuget_config)
    DOCKER_BIN=$(wslexe get docker podman)

    echo "🐳 Building Docker image..."
    cp $nuget_conf .
    $DOCKER_BIN build . -t temp
    rm $(basename $nuget_conf)
    echo "✅ Build complete"

}

function ce() {
    local cmd="${1:-help}"

    case "$cmd" in
        check)
            if podman.exe ps >/dev/null 2>&1; then
                [ "$2" = "-v" ] && echo "✅ Container engine running"
                return 0
            else
                echo "⚠️ Container engine not running. Run 'ce fix' to start."
                return 1
            fi
            ;;
        fix)
            echo "🔧 Starting container engine..."
            # Run from Windows path to avoid UNC path translation errors
            if (cd /mnt/c && podman.exe machine start); then
                echo "✅ Container engine started"
            else
                echo "❌ Failed to start container engine"
                return 1
            fi
            ;;
        -h|--help|help|*)
            echo "🐳 ce - Container engine manager"
            echo ""
            echo "Usage: ce <command>"
            echo ""
            echo "Commands:"
            echo "  check [-v]    Check if container engine is running (-v for verbose)"
            echo "  fix           Start the container engine"
            echo "  help          Show this help message"
            ;;
    esac
}

# Check container engine on interactive shell startup
[[ $- == *i* ]] && ce check
[[ $- == *i* ]] && _dev_helpers


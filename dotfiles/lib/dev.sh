#!/bin/bash

bash_debug "Loading dev.sh"

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
    echo "  ccs → vim ~/.claude/settings.json"
}

alias docker="podman.exe"
alias docker-compose="podman.exe compose"
alias podman="podman.exe"
alias dotnet="dotnet.exe"
alias ccs="vim ~/.claude/settings.json"
alias cs="claude-sessions"
alias ts="tmux-sessions"
alias pp="pca"
alias hank="hunk diff"

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

    # Already inside tmux: run Claude in the current pane. Spawning a new session
    # and switching to it would leave the session you're in detached.
    if [ -n "$TMUX" ]; then
        claude "$@"
        return
    fi

    # Outside tmux: launch in a dedicated session named after the current folder,
    # picking the next free name (cc-foo, cc-foo-2, ...) if one already exists.
    local base="cc-$(basename "$PWD")"
    local name="$base" n=2
    while tmux has-session -t "=$name" 2>/dev/null; do
        name="$base-$n"
        ((n++))
    done
    tmux new-session -s "$name" claude "$@"
}

alias pcs="pi-sessions"

function pca() {
    # Ensure Node v22+ via nvm (pi requires it)
    if command -v nvm >/dev/null 2>&1 || [ -s "$NVM_DIR/nvm.sh" ]; then
        [ -s "$NVM_DIR/nvm.sh" ] && . "$NVM_DIR/nvm.sh" 2>/dev/null
        local node_major
        node_major="$(node --version 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
        if [[ -z "$node_major" || "$node_major" -lt 22 ]]; then
            nvm use 22 2>/dev/null || nvm install 22
        fi
    fi

    if [ -n "$TMUX" ]; then
        pi "$@"
        return
    fi

    local base="pi-$(basename "$PWD")"
    local name="$base" n=2
    while tmux has-session -t "=$name" 2>/dev/null; do
        name="$base-$n"
        ((n++))
    done
    tmux new-session -s "$name" pi "$@"
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


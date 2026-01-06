#!/bin/bash

## Daily tips - shown once per day on shell startup
SHOW_DAILY_TIPS=true

_show_daily_tips() {
    local marker_file="$HOME/.cache/daily-tips-date"
    local today=$(date +%Y-%m-%d)

    # Create cache dir if needed
    mkdir -p "$HOME/.cache"


    if [[ "$1" == "rm" ]]; then
        rm $marker_file
        return
    fi


    # Check if already shown today
    if [[ -f "$marker_file" ]] && [[ "$(cat "$marker_file" 2>/dev/null)" == "$today" ]] && [[ "$1" != "-v" ]]; then
        return
    fi

    # Update marker
    echo "$today" > "$marker_file"

    # Display tips
    echo ""
    echo "┌──────────────────────────────────────────────────────────────────────────────┐"
    echo "│  📦 Git Repos (repos help)                                                   │"
    echo "│     repos fetch              Fetch all & pull where possible                 │"
    echo "│     repos ls                 Show repos not on main or dirty                 │"
    echo "│     repos code <repo>        Open VS Code in matching repo                   │"
    echo "├──────────────────────────────────────────────────────────────────────────────┤"
    echo "│  🌳 Git Worktrees (gwt help)                                                 │"
    echo "│     gwt ls                   List all worktrees                              │"
    echo "│     gwt add <repo> <branch>  Create worktree                                 │"
    echo "│     gwt code <repo> <branch> Create & open in VS Code                        │"
    echo "├──────────────────────────────────────────────────────────────────────────────┤"
    echo "│  🐳 Dev (dev_help) & 🔌 Telepresence (tphelp)                                │"
    echo "│     k8s [ns] [cmd]           Interactive pod manager (k8s help)              │"
    echo "│     ce check                 Check container engine status                   │"
    echo "│     wslexe check             Check WSL interop status                        │"
    echo "│     epoch [ts]               Convert timestamp to date                       │"
    echo "│     tpc <ns>                 Connect to namespace                            │"
    echo "│     tpi <component> <port>   Intercept traffic                               │"
    echo "├──────────────────────────────────────────────────────────────────────────────┤"
    echo "│  ☸️ Kubernetes (khelp)                                                       │"
    echo "│  ☁️ AWS (aws_help)                                                           │"
    echo "│  🏗️ Terraform (tfhelp)                                                       │"
    echo "└──────────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

# Show tips on shell startup (only for interactive shells)
[[ $- == *i* ]] && [ "$SHOW_DAILY_TIPS" == "true"  ]  &&_show_daily_tips

#!/bin/bash

## Daily tips - shown once per day on shell startup

_show_daily_tips() {
    local marker_file="$HOME/.cache/daily-tips-date"
    local today=$(date +%Y-%m-%d)

    # Create cache dir if needed
    mkdir -p "$HOME/.cache"

    # Check if already shown today
    if [[ -f "$marker_file" ]] && [[ "$(cat "$marker_file" 2>/dev/null)" == "$today" ]]; then
        return
    fi

    # Update marker
    echo "$today" > "$marker_file"

    # Display tips
    echo ""
    echo "┌─────────────────────────────────────────────────────────┐"
    echo "│  📦 Git Toolkit                                         │"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│  repos fetch    Fetch all & pull where possible         │"
    echo "│  repos status   Show repos not on main or with changes  │"
    echo "│  repos main     Switch all repos to main branch         │"
    echo "│  repos clear    Delete merged branches                  │"
    echo "├─────────────────────────────────────────────────────────┤"
    echo "│  gwt ls                  List all worktrees             │"
    echo "│  gwt add [repo] [branch] Create worktree                │"
    echo "│  gwt code [repo] [branch] Create & open in VS Code      │"
    echo "│  gwt rm [repo]           Remove worktree                │"
    echo "└─────────────────────────────────────────────────────────┘"
    echo ""
}

# Show tips on shell startup (only for interactive shells)
[[ $- == *i* ]] && _show_daily_tips

#!/bin/bash

bash_debug "Loading git-browse.sh"

## Shared helper

# Strip the 3-char status prefix (and any "old -> new" rename arrow) from a
# `git status --porcelain` line, leaving the path.
_gb_path() { echo "$1" | sed 's/^...//; s/.* -> //'; }

## Preview helpers (export -f so fzf's preview subshell can call them)

# gs preview: working-tree diff, falling back to staged diff, then file contents.
_gs_preview() {
    local f out
    f="$(_gb_path "$1")"
    out="$(git.exe diff --color=always -- "$f" 2>/dev/null)"
    [ -z "$out" ] && out="$(git.exe diff --cached --color=always -- "$f" 2>/dev/null)"
    if [ -n "$out" ]; then
        echo "$out"
    else
        batcat -n -S --color=always --line-range :500 "$f" 2>/dev/null
    fi
}

# gl layer-2 preview: a file's diff within the selected commit.
_gl_file_preview() { git.exe show --color=always "$1" -- "$2"; }

export -f _gb_path _gs_preview _gl_file_preview

## Commands

# Browse `git status` in fzf (preview = diff), Enter opens the file in batcat.
gs() {
    local line file
    line="$(git.exe status --porcelain |
        fzf --ansi --height=70% --layout=reverse --preview-window=60% \
            --preview '_gs_preview {}')" || return
    file="$(_gb_path "$line")"
    [ -n "$file" ] && batcat -n -S --color=always "$file"
}

# Browse `git log` in fzf (preview = commit message + stat); Enter on a commit
# drops into its changed files (preview = per-file diff); Enter there opens the
# file as it was at that commit in batcat.
gl() {
    local commit file
    commit="$(git.exe log --color=always --format='%C(auto)%h %s %C(dim)(%cr)%C(reset)' |
        fzf --ansi --height=70% --layout=reverse --preview-window=60% \
            --preview 'git.exe show --stat --color=always {1}' |
        awk '{print $1}')" || return
    [ -n "$commit" ] || return

    file="$(git.exe show --name-only --pretty=format: "$commit" | sed '/^$/d' |
        fzf --ansi --height=70% --layout=reverse --preview-window=60% \
            --preview "_gl_file_preview $commit {}")" || return

    [ -n "$file" ] && git.exe show "$commit:$file" | batcat -n -S --color=always
}

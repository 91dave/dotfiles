#!/bin/bash

## CONFIGURATION
REPO_HOME_WIN='C:\Code'
WORKTREE_HOME_WIN='C:\Code\workspace'

## Variables
REPO_HOME=$(wslpath $REPO_HOME_WIN)
REPO_CACHE=$REPO_HOME/repos-cache.lst
WORKTREE_HOME=$(wslpath $WORKTREE_HOME_WIN)

## Shared Helpers

is_repo() {
    git.exe status >& /dev/null && echo "true" || echo "false"
}

find_git_repos() {
    local folder="${1:-.}"
    local max_depth="${2:-3}"

    find "$folder" -maxdepth "$max_depth" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        dirname "$gitdir" | sed "s|^$folder/||"
    done
}

# Get the default branch (main or master) for the current repo
_git_get_default_branch() {
    if git.exe </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        echo "main"
    elif git.exe </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        echo "master"
    else
        return 1
    fi
}

## Source command files
_GIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_GIT_SCRIPT_DIR/git-repos.inc"
source "$_GIT_SCRIPT_DIR/git-gwt.inc"

#!/bin/bash

bash_debug "Loading git.sh"

_GIT_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$_GIT_SCRIPT_DIR/repos-config.sh"

export WORKTREE_HOME_WIN='C:\Code\worktrees'
export WORKSPACE_HOME_WIN='C:\Code\workspaces'
export WORKTREE_HOME=$(wslpath $WORKTREE_HOME_WIN)
export WORKSPACE_HOME=$(wslpath $WORKSPACE_HOME_WIN)

## Shared Helpers

is_repo() {
    git status >& /dev/null && echo "true" || echo "false"
}

## Source command files
source "$_GIT_SCRIPT_DIR/repos-core.bash"
source "$_GIT_SCRIPT_DIR/git-repos.bash"
source "$_GIT_SCRIPT_DIR/git-gwt.bash"
source "$_GIT_SCRIPT_DIR/git-workspaces.bash"

#!/bin/bash

export REPO_HOME_WIN='C:\Code'
export REPO_HOME=$(wslpath "$REPO_HOME_WIN")

# Named roots scanned by repos cache; list order breaks ties when a repo is in several
export REPO_ROOTS="wsl=$HOME/repos win=$REPO_HOME"
export REPO_PREFER=wsl
# Windows GUI apps (Visual Studio, GitHub Desktop) are slow or broken over \\wsl$
export REPO_PREFER_WINDOWS_APPS=win

export REPO_STATE=$HOME/.local/state/repos
export REPO_CACHE=$REPO_STATE/repos-cache.lst
export REPO_STATUS=$REPO_STATE/repos-status.json
export REPO_READONLY=$REPO_STATE/repos-readonly.lst
export REPO_IGNORE=$REPO_STATE/.reposignore
export REPO_GROUPS=$REPO_STATE/repos-groups.cfg

# GitHub owners searched when a repo is not cloned locally (repos resolve fallback)
export REPO_OWNERS="91dave amdigital-co-uk"

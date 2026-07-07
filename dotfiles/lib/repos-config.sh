#!/bin/bash

export REPO_HOME_WIN='C:\Code'
export REPO_HOME=$(wslpath "$REPO_HOME_WIN")
export REPO_CACHE=$REPO_HOME/repos-cache.lst
export REPO_STATUS=$REPO_HOME/repos-status.json
export REPO_READONLY=$REPO_HOME/repos-readonly.lst
export REPO_IGNORE=$REPO_HOME/.reposignore
export REPO_GROUPS=$REPO_HOME/repos-groups.cfg

# GitHub owners searched when a repo is not cloned locally (repos resolve fallback)
export REPO_OWNERS="91dave amdigital-co-uk"

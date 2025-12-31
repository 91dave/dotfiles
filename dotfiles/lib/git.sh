#!/bin/bash

## CONFIGURATION
REPO_HOME_WIN='C:\Code'
WORKTREE_HOME_WIN='C:\Code\workspace'

## Variables
REPO_HOME=$(wslpath $REPO_HOME_WIN)
REPO_CACHE=$REPO_HOME/repos-cache.lst
WORKTREE_HOME=$(wslpath $WORKTREE_HOME_WIN)


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

fetch_repos() {
    local folder="$REPO_HOME"
    local repo_list="$REPO_CACHE"

    if [[ ! -f "$repo_list" ]]; then
        echo "Error: repo list file not found: $repo_list"
        return 1
    fi

    while read -r repo; do
        [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue
        
        local repo_path="$folder/$repo"
        
        if [[ -d "$repo_path/.git" ]]; then
            echo "Fetching: $repo"
			pushd $repo_path >& /dev/null

            git.exe </dev/null fetch origin main 2>/dev/null || 
            git.exe </dev/null fetch origin master 2>/dev/null ||
            echo "  Warning: could not fetch main/master for $repo"
			
			local branch=$(git.exe </dev/null branch --show-current)
			local is_dirty=$(git.exe </dev/null status --porcelain)

			if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ -z "$is_dirty" ]]; then
				#echo "  Pulling: on $branch with clean working tree"
				git.exe </dev/null pull origin "$branch" >& /dev/null
			else
				echo "  Skipping pull: on '$branch', dirty: ${is_dirty:+yes}"
			fi


			popd >& /dev/null
        else
            echo "Skipping (not a git repo): $repo"
        fi
    done < "$repo_list"
}

update_repo_cache() {
	find_git_repos "$REPO_HOME" 4 | grep -v _backup | grep -v '\.bak' > $REPO_CACHE
}

gwt_usage() {

    echo "-- Git WorkTrees --"
    echo "Opinionated helper script for managing git worktrees"
    echo "Relies on having an up-to-date cache of repos in $REPO_HOME"
    echo "Update the repo cache by running: update_repo_cache"
    echo ""
    echo "Repo-scoped commands: (must be run from a repository folder)"
    echo "  gwt                     List worktrees in current repo"
    echo "  add [branch]            Create worktree of current repo in $WORKTREE_HOME on [branch]"
    echo "  rm [branch]             Delete worktree of current repo from $WORKTREE_HOME named [branch]"
    echo ""
    echo "Global commands:"
    echo "  rm|add [repo] [branch]  Find repo matching [repo] in the cache and create or delete workspace as if run from that repo"
    echo ""
    echo "Using 'code' instead of 'add' will spin up a VS Code instance inside $WORKTREE_HOME when complete"
}

gwt() {

    # If no args, print current work trees and exit
    if [ -z "$1" ]; then
        git.exe worktree list
        return
    fi

    # Arg parsing and usage
    [ -z "$2" ] && gwt_usage && return

    cmd=$1
    branch=$2

    # If we are not currently in a repo, find one using $2 as a search
	if [ "$(is_repo)" = "false" ]
    then
        search=$2
        branch=$3

        [ -z "$search" ] && gwt_usage && return
        results=$(cat $REPO_CACHE | grep $search | wc -l)
        echo "Found $results repos for '$search'" 

        [ "$results" = "1" ] || return

        result=$(cat $REPO_CACHE | grep $search)
        pushd $REPO_HOME/$result >& /dev/null
        gwt $cmd $branch
        popd >& /dev/null
        return
    fi

    ## ASSUMPTION: pwd is now a GIT repo

    # Get project name
    project=$(basename $(pwd))
    short=$(echo $project | cut -d- -f2-)
    [ -n "$short" ] && project=$short

    
    # Get branch and tag (i.e. last component of branch name)
    tag=$(echo $branch | rev | cut -d/ -f1 | rev)
    branch_exists=true
    [ "$(git.exe branch | grep $branch | wc -l)" = "0" ] && branch_exists=false
    
    # Get folder 
    folder=$project-$tag
    folder_exists=false
    worktree_exists=false
    if [ -d "$WORKTREE_HOME/$folder" ]
    then
        folder_exists=true

        wtc=$(git.exe worktree list | grep $folder | wc -l)

        [ "$wtc" = 0 ] || worktree_exists=true
    fi

    # Validate folder and worktree match
    [ "$worktree_exists" = "false" ] && [ "$folder_exists" = "true" ] && echo "Folder '$folder' exists in workspace, but is not a valid worktree"

    case "$cmd" in

        # TODO - new ls command that lists which repos/worktrees are in the workspace

        # TODO - new clear command (perhaps with a warning/confirm??) to safely delete out all worktrees
        #   does `git worktree remove .` work when inside a given worktree??

        rm)
            [ "$worktree_exists" = "true" ] && echo "Deleting worktree ${folder}..." && git.exe worktree remove "$(wslpath -w $WORKTREE_HOME/$folder)"
            [ "$worktree_exists" = "true" ] || echo "Worktree ${folder} does not exist, skipping..."
            ;;
        add|claude|code)
            branch_flag="-b"
            [ "$branch_exists" = "true" ] && branch_flag=""
            [ "$worktree_exists" = "true" ] && echo "Worktree ${folder} already exists, skipping..."
            [ "$worktree_exists" = "true" ] || echo "Creating worktree ${folder}..." && git.exe worktree add "$(wslpath -w $WORKTREE_HOME/$folder)" $branch_flag $branch
            ;;
        *)
            ;;

    esac

    [ "$cmd" = "code" ] && (cd $WORKTREE_HOME && cmd.exe /c code .)
    [ "$cmd" = "claude" ] && (cd $WORKTREE_HOME && cmd.exe /c claude)
}

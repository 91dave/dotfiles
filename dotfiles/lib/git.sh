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
        echo "❌ Error: repo list file not found: $repo_list"
        return 1
    fi

    while read -r repo; do
        [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

        local repo_path="$folder/$repo"

        if [[ -d "$repo_path/.git" ]]; then
            echo "🔄 $repo"
            pushd $repo_path >& /dev/null

            # Fetch (try main, then master)
            local fetch_branch="main"
            if ! git.exe </dev/null fetch origin main 2>/dev/null; then
                fetch_branch="master"
                if ! git.exe </dev/null fetch origin master 2>/dev/null; then
                    echo "   ⚠️  Could not fetch main/master"
                    popd >& /dev/null
                    continue
                fi
            fi

            # Count new commits
            local commits=$(git.exe </dev/null rev-list --count HEAD..origin/$fetch_branch 2>/dev/null || echo "0")
            [[ "$commits" -gt 0 ]] && echo "   📥 $commits new commit(s)"

            # Check if we can pull
            local branch=$(git.exe </dev/null branch --show-current)
            local is_dirty=$(git.exe </dev/null status --porcelain)

            if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ -z "$is_dirty" ]]; then
                git.exe </dev/null pull origin "$branch" >& /dev/null
                [[ "$commits" -gt 0 ]] && echo "   ✅ Pulled"
            else
                # Build skip reason
                local reason=""
                [[ "$branch" != "main" && "$branch" != "master" ]] && reason="on $branch"
                [[ -n "$is_dirty" ]] && reason="${reason:+$reason, }uncommitted changes"
                echo "   ⏭️  Skipped pull ($reason)"
            fi

            popd >& /dev/null
        else
            echo "⏭️  $repo (not a git repo)"
        fi
    done < "$repo_list"
}

update_repo_cache() {
	echo "🔍 Scanning for repos in $REPO_HOME..."
	find_git_repos "$REPO_HOME" 4 | grep -v _backup | grep -v '\.bak' > $REPO_CACHE
	local count=$(wc -l < $REPO_CACHE)
	echo "✅ Found $count repos, cache updated"
}

gwt_clear() {
    local count=$(find "$WORKTREE_HOME" -maxdepth 1 -mindepth 1 -type d ! -name '.*' 2>/dev/null | wc -l)

    if [ "$count" -eq 0 ]; then
        echo "📭 No worktrees found in $WORKTREE_HOME"
        return
    fi

    echo "🗑️  Found $count folder(s) in $WORKTREE_HOME:"
    ls -1d "$WORKTREE_HOME"/*/ 2>/dev/null | xargs -n1 basename
    echo ""
    read -p "Remove all worktrees? [y/N] " confirm

    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "❌ Aborted."
        return
    fi

    for folder in "$WORKTREE_HOME"/*/; do
        [ -d "$folder" ] || continue

        folder_name=$(basename "$folder")
        echo "🔄 Processing: $folder_name"

        pushd "$folder" >& /dev/null || continue

        main_worktree=$(git.exe worktree list 2>/dev/null | head -n1 | awk '{print $1}')

        if [ -z "$main_worktree" ]; then
            echo "  ⚠️  Not a git worktree, skipping"
            popd >& /dev/null
            continue
        fi

        popd >& /dev/null

        main_worktree_wsl=$(wslpath "$main_worktree" 2>/dev/null || echo "$main_worktree")
        pushd "$main_worktree_wsl" >& /dev/null || continue

        echo "  ✅ Removing from: $(basename "$main_worktree")"
        git.exe worktree remove "$(wslpath -w "$folder")"

        popd >& /dev/null
    done
}

gwt_usage() {
    echo "🌳 Git WorkTrees"
    echo "Opinionated helper script for managing git worktrees"
    echo "Relies on having an up-to-date cache of repos in $REPO_HOME"
    echo "Update the repo cache by running: update_repo_cache"
    echo ""
    echo "📍 Repo-scoped commands: (must be run from a repository folder)"
    echo "  gwt                     📋 List worktrees in current repo"
    echo "  gwt add [branch]        ➕ Create worktree on [branch]"
    echo "  gwt rm [branch]         ➖ Delete worktree named [branch]"
    echo ""
    echo "🌐 Global commands:"
    echo "  gwt ls                     📋 List all worktrees in workspace"
    echo "  gwt rm|add [repo] [branch] 🔍 Find repo and create/delete worktree"
    echo "  gwt_clear                  🗑️  Remove all worktrees"
    echo ""
    echo "💡 Use 'code' instead of 'add' to open VS Code when complete"
    echo "💡 Use 'claude' instead of 'add' to open Claude Code when complete"
}

gwt() {

    # If no args, print current work trees and exit
    if [ -z "$1" ]; then
        git.exe worktree list
        return
    fi

    cmd=$1
    branch=$2

    # ls command doesn't require additional args
    if [ "$cmd" = "ls" ]; then
        echo "📂 Worktrees in $WORKTREE_HOME:"
        echo ""
        for wt in "$WORKTREE_HOME"/*/; do
            [ -d "$wt" ] || continue
            wt_name=$(basename "$wt")
            pushd "$wt" >& /dev/null || continue

            main_worktree=$(git.exe worktree list 2>/dev/null | head -n1 | awk '{print $1}')
            wt_branch=$(git.exe branch --show-current 2>/dev/null)

            if [ -z "$main_worktree" ]; then
                echo "  ⚠️  $wt_name (not a git worktree)"
                popd >& /dev/null
                continue
            fi

            repo_name=$(basename "$main_worktree")
            popd >& /dev/null
            echo "  📁 $wt_name"
            echo "     └─ 🔗 $repo_name  🌿 $wt_branch"
        done
        return
    fi

    # Other commands require a branch argument
    [ -z "$2" ] && gwt_usage && return

    # If we are not currently in a repo, find one using $2 as a search
	if [ "$(is_repo)" = "false" ]
    then
        search=$2
        branch=$3

        [ -z "$search" ] && gwt_usage && return
        results=$(cat $REPO_CACHE | grep $search | wc -l)
        echo "🔍 Found $results repos for '$search'" 

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
    [ "$worktree_exists" = "false" ] && [ "$folder_exists" = "true" ] && echo "⚠️  Folder '$folder' exists in workspace, but is not a valid worktree"

    case "$cmd" in

        rm)
            [ "$worktree_exists" = "true" ] && echo "🗑️  Deleting worktree ${folder}..." && git.exe worktree remove "$(wslpath -w $WORKTREE_HOME/$folder)"
            [ "$worktree_exists" = "true" ] || echo "⏭️  Worktree ${folder} does not exist, skipping..."
            ;;
        add|claude|code)
            branch_flag="-b"
            [ "$branch_exists" = "true" ] && branch_flag=""
            [ "$worktree_exists" = "true" ] && echo "⏭️  Worktree ${folder} already exists, skipping..."
            [ "$worktree_exists" = "true" ] || echo "➕ Creating worktree ${folder}..." && git.exe worktree add "$(wslpath -w $WORKTREE_HOME/$folder)" $branch_flag $branch
            ;;
        *)
            ;;

    esac

    [ "$cmd" = "code" ] && echo "🚀 Opening VS Code..." && (cd $WORKTREE_HOME/$folder && cmd.exe /c code .)
    [ "$cmd" = "claude" ] && echo "🤖 Opening Claude Code..." && (cd $WORKTREE_HOME/$folder && cmd.exe /c claude)
}

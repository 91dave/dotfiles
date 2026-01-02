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

repos() {
    local cmd="${1:-help}"
    local folder="$REPO_HOME"
    local repo_list="$REPO_CACHE"
    local total_branches=0
    local total_repos=0

    if [[ ! -f "$repo_list" ]]; then
        echo "❌ Error: repo list file not found: $repo_list"
        return 1
    fi

    case "$cmd" in
        fetch)
            local -a skipped_dirty=()
            local -a skipped_branch=()

            while read -r repo; do
                [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

                local repo_path="$folder/$repo"
                [[ ! -d "$repo_path/.git" ]] && continue

                pushd $repo_path >& /dev/null

                # Fetch (try main, then master)
                local fetch_branch="main"
                if ! git.exe </dev/null fetch origin main 2>/dev/null; then
                    fetch_branch="master"
                    if ! git.exe </dev/null fetch origin master 2>/dev/null; then
                        popd >& /dev/null
                        continue
                    fi
                fi

                # Count new commits
                local commits=$(git.exe </dev/null rev-list --count HEAD..origin/$fetch_branch 2>/dev/null || echo "0")

                # Skip if no new commits
                if [[ "$commits" -eq 0 ]]; then
                    popd >& /dev/null
                    continue
                fi

                echo "🔄 $repo"
                echo "   📥 $commits new commit(s)"

                # Check if we can pull
                local branch=$(git.exe </dev/null branch --show-current)
                local is_dirty=$(git.exe </dev/null status --porcelain)

                if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ -z "$is_dirty" ]]; then
                    git.exe </dev/null pull origin "$branch" >& /dev/null
                    echo "   ✅ Pulled"
                else
                    # Categorize skip reason (dirty takes priority)
                    if [[ -n "$is_dirty" ]]; then
                        skipped_dirty+=("$repo")
                    else
                        skipped_branch+=("$repo ($branch)")
                    fi
                fi

                popd >& /dev/null
            done < "$repo_list"

            # Print summary of skipped repos grouped by reason
            local total_skipped=$(( ${#skipped_dirty[@]} + ${#skipped_branch[@]} ))
            if [[ $total_skipped -gt 0 ]]; then
                echo ""
                echo "⏭️  Skipped pull for $total_skipped repo(s):"

                if [[ ${#skipped_dirty[@]} -gt 0 ]]; then
                    echo ""
                    echo "   Uncommitted changes:"
                    printf '%s\n' "${skipped_dirty[@]}" | sort | while read -r r; do
                        echo "      $r"
                    done
                fi

                if [[ ${#skipped_branch[@]} -gt 0 ]]; then
                    echo ""
                    echo "   Different branch:"
                    printf '%s\n' "${skipped_branch[@]}" | sort | while read -r r; do
                        echo "      $r"
                    done
                fi
            fi
            ;;

        cache)
            echo "🔍 Scanning for repos in $REPO_HOME..."
            find_git_repos "$REPO_HOME" 4 | grep -v _backup | grep -v '\.bak' > "$REPO_CACHE"
            local count=$(wc -l < "$REPO_CACHE")
            echo "✅ Found $count repos, cache updated"
            ;;

        ls)
            echo "🔍 Scanning repos for merged branches..."
            echo ""

            while read -r repo; do
                [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

                local repo_path="$folder/$repo"
                [[ ! -d "$repo_path/.git" ]] && continue

                pushd "$repo_path" >& /dev/null

                # Determine default branch
                local default_branch="main"
                if ! git.exe </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
                    default_branch="master"
                    if ! git.exe </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
                        popd >& /dev/null
                        continue
                    fi
                fi

                # Get merged branches (exclude default, master, main, and current)
                local merged=$(git.exe </dev/null branch --merged "$default_branch" 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')

                if [[ -n "$merged" ]]; then
                    echo "📁 $repo"
                    local repo_counted=false
                    while IFS= read -r branch; do
                        [[ -z "$branch" ]] && continue
                        echo "   🌿 $branch"
                        ((total_branches++))
                        repo_counted=true
                    done <<< "$merged"
                    [[ "$repo_counted" = true ]] && ((total_repos++))
                fi

                popd >& /dev/null
            done < "$repo_list"

            echo ""
            if [[ $total_branches -gt 0 ]]; then
                echo "✅ Found $total_branches merged branch(es) across $total_repos repo(s)"
            else
                echo "✅ No merged branches found"
            fi
            ;;

        clear)
            echo "🗑️  Deleting merged branches..."
            echo ""

            while read -r repo; do
                [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

                local repo_path="$folder/$repo"
                [[ ! -d "$repo_path/.git" ]] && continue

                pushd "$repo_path" >& /dev/null

                # Determine default branch
                local default_branch="main"
                if ! git.exe </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
                    default_branch="master"
                    if ! git.exe </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
                        popd >& /dev/null
                        continue
                    fi
                fi

                # Get merged branches (exclude default, master, main, and current)
                local merged=$(git.exe </dev/null branch --merged "$default_branch" 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')

                if [[ -n "$merged" ]]; then
                    echo "📁 $repo"
                    while IFS= read -r branch; do
                        [[ -z "$branch" ]] && continue
                        if git.exe </dev/null branch -d "$branch" >& /dev/null; then
                            echo "   ✅ Deleted: $branch"
                            ((total_branches++))
                        else
                            echo "   ❌ Failed: $branch"
                        fi
                    done <<< "$merged"
                fi

                popd >& /dev/null
            done < "$repo_list"

            echo ""
            if [[ $total_branches -gt 0 ]]; then
                echo "✅ Deleted $total_branches branch(es)"
            else
                echo "✅ No merged branches to delete"
            fi
            ;;

        status)
            echo "🔍 Checking repo status..."
            echo ""
            local -a off_main=()
            local -a dirty=()

            while read -r repo; do
                [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

                local repo_path="$folder/$repo"
                [[ ! -d "$repo_path/.git" ]] && continue

                pushd "$repo_path" >& /dev/null

                # Determine default branch
                local default_branch="main"
                if ! git.exe </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
                    default_branch="master"
                    if ! git.exe </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
                        popd >& /dev/null
                        continue
                    fi
                fi

                local current_branch=$(git.exe </dev/null branch --show-current 2>/dev/null)
                local is_dirty=$(git.exe </dev/null status --porcelain 2>/dev/null)

                if [[ "$current_branch" != "$default_branch" ]]; then
                    off_main+=("📁 $repo ($current_branch)")
                fi

                if [[ -n "$is_dirty" ]]; then
                    local file_count=$(echo "$is_dirty" | wc -l | tr -d ' ')
                    dirty+=("📁 $repo ($current_branch, $file_count file(s))")
                fi

                popd >& /dev/null
            done < "$repo_list"

            if [[ ${#off_main[@]} -gt 0 ]]; then
                echo "🌿 Not on main (${#off_main[@]}):"
                printf '%s\n' "${off_main[@]}" | sort | while read -r item; do
                    echo "   $item"
                done
                echo ""
            fi

            if [[ ${#dirty[@]} -gt 0 ]]; then
                echo "✏️  Uncommitted changes (${#dirty[@]}):"
                printf '%s\n' "${dirty[@]}" | sort | while read -r item; do
                    echo "   $item"
                done
                echo ""
            fi

            if [[ ${#off_main[@]} -eq 0 ]] && [[ ${#dirty[@]} -eq 0 ]]; then
                echo "✅ All repos are clean and on main"
            fi
            ;;

        main)
            echo "🔄 Switching repos to main branch..."
            echo ""
            local switched=0
            local skipped_dirty=()
            local skipped_unmerged=()

            while read -r repo; do
                [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]] && continue

                local repo_path="$folder/$repo"
                [[ ! -d "$repo_path/.git" ]] && continue

                pushd "$repo_path" >& /dev/null

                # Determine default branch
                local default_branch="main"
                if ! git.exe </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
                    default_branch="master"
                    if ! git.exe </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
                        popd >& /dev/null
                        continue
                    fi
                fi

                # Skip if already on default branch
                local current_branch=$(git.exe </dev/null branch --show-current 2>/dev/null)
                if [[ "$current_branch" == "$default_branch" ]]; then
                    popd >& /dev/null
                    continue
                fi

                # Check for uncommitted changes
                local is_dirty=$(git.exe </dev/null status --porcelain 2>/dev/null)
                if [[ -n "$is_dirty" ]]; then
                    skipped_dirty+=("$repo ($current_branch)")
                    popd >& /dev/null
                    continue
                fi

                # Check for unmerged commits
                local unmerged=$(git.exe </dev/null rev-list --count "$default_branch..HEAD" 2>/dev/null || echo "0")
                if [[ "$unmerged" -gt 0 ]]; then
                    skipped_unmerged+=("$repo ($current_branch, $unmerged commit(s))")
                    popd >& /dev/null
                    continue
                fi

                # Safe to switch
                if git.exe </dev/null checkout "$default_branch" >& /dev/null; then
                    echo "✅ $repo: $current_branch → $default_branch"
                    ((switched++))
                else
                    echo "❌ $repo: failed to switch"
                fi

                popd >& /dev/null
            done < "$repo_list"

            # Summary
            echo ""
            if [[ $switched -gt 0 ]]; then
                echo "✅ Switched $switched repo(s) to main"
            else
                echo "✅ No repos needed switching"
            fi

            local total_skipped=$(( ${#skipped_dirty[@]} + ${#skipped_unmerged[@]} ))
            if [[ $total_skipped -gt 0 ]]; then
                echo ""
                echo "⏭️  Skipped $total_skipped repo(s):"

                if [[ ${#skipped_dirty[@]} -gt 0 ]]; then
                    echo ""
                    echo "   Uncommitted changes:"
                    printf '%s\n' "${skipped_dirty[@]}" | sort | while read -r item; do
                        echo "      $item"
                    done
                fi

                if [[ ${#skipped_unmerged[@]} -gt 0 ]]; then
                    echo ""
                    echo "   Unmerged commits:"
                    printf '%s\n' "${skipped_unmerged[@]}" | sort | while read -r item; do
                        echo "      $item"
                    done
                fi
            fi
            ;;

        help|-h|--help|*)
            echo "📦 Repos"
            echo "Manage all repos in cache"
            echo ""
            echo "Usage:"
            echo "  repos fetch   🔁 Fetch all repos and pull where possible"
            echo "  repos status  📍 List repos not on main/master or with uncommitted changes"
            echo "  repos main    🔄 Switch all repos to main/master branch"
            echo "  repos ls      📋 List branches merged into main/master"
            echo "  repos clear   🗑️  Delete branches merged into main/master"
            echo "  repos cache   📂 Update cache of repos"
            echo "  repos help    📖 Show this help message"
            ;;
    esac
}

alias repo='repos'

gwt_usage() {
    echo "🌳 Git WorkTrees"
    echo "Opinionated helper script for managing git worktrees"
    echo "Relies on having an up-to-date cache of repos in $REPO_HOME"
    echo "Update the repo cache by running: repos cache"
    echo ""
    echo "🌐 Global commands:"
    echo "  gwt ls                        📋 List all worktrees in workspace"
    echo "  gwt add [repo] [branch]       ➕ Find repo and create worktree (repo name as folder)"
    echo "  gwt add [repo] -b [branch]    ➕ Find repo and create worktree (repo-branch as folder)"
    echo "  gwt rm [repo]                 ➖ Find repo and delete tagless worktree"
    echo "  gwt rm [repo] [branch]        ➖ Find repo and delete tagged worktree"
    echo "  gwt clear                     🗑️  Remove all worktrees"
    echo ""
    echo "📍 Repo-scoped commands: (must be run from a repository folder)"
    echo "  gwt                        📋 List worktrees in current repo"
    echo "  gwt add [branch]           ➕ Create worktree (uses repo name as folder)"
    echo "  gwt add -b [branch]        ➕ Create worktree (uses repo-branch as folder)"
    echo "  gwt rm                     ➖ Delete tagless worktree for this repo"
    echo "  gwt rm [branch]            ➖ Delete worktree named repo-branch"
    echo ""
    echo "💡 Use 'code' instead of 'add' to open 🚀 VS Code when complete"
    echo "💡 Use 'claude' instead of 'add' to open 🤖 Claude Code when complete"
    echo ""
    echo "🎮 Related commands"
    echo "  repos                      📦 Manage all repos (fetch, status, main, ls, clear, cache)"
}

gwt() {

    # If no args, print current work trees and exit
    if [ -z "$1" ]; then
        git.exe worktree list
        return
    fi

    cmd=$1
    branch=$2

    # Handle argument-less commands
    case "$cmd" in
        help|usage|-h|--help)
            gwt_usage
            return
            ;;
        ls)
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
            ;;
        code)
            # code command without other args just spawns VS code in WORKTREE_HOME
            if [ "$#" = "1" ]; then
                echo "🚀 Opening VS Code..."
                (cd $WORKTREE_HOME && cmd.exe /c code .)
                return
            fi
            ;;
        clear)
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
            return
            ;;
    esac

    # Validate arguments based on context and command
    if [ -z "$2" ]; then
        # No second arg - only valid for 'rm' from within a repo
        if [ "$(is_repo)" = "true" ] && [ "$cmd" = "rm" ]; then
            : # OK - tagless rm from repo context
        else
            gwt_usage && return
        fi
    fi

    # If we are not currently in a repo, find one using $2 as a search
    if [ "$(is_repo)" = "false" ]; then
        search=$2
        branch=$3
        use_tag_flag=""

        # Handle -b flag in global context: gwt add [repo] -b [branch]
        if [ "$branch" = "-b" ]; then
            use_tag_flag="-b"
            branch=$4
        fi

        [ -z "$search" ] && gwt_usage && return

        # For add/code/claude, branch is required
        # For rm, branch is optional (tagless removal)
        if [ -z "$branch" ] && [ "$cmd" != "rm" ]; then
            gwt_usage && return
        fi

        results=$(cat $REPO_CACHE | grep $search | wc -l)
        echo "🔍 Found $results repos for '$search'"

        [ "$results" = "1" ] || return

        result=$(cat $REPO_CACHE | grep $search)
        pushd $REPO_HOME/$result >& /dev/null
        gwt $cmd $use_tag_flag $branch  # Pass -b flag if set, branch may be empty for rm
        popd >& /dev/null
        return
    fi

    ## ASSUMPTION: pwd is now a GIT repo

    # Parse -b flag for add/code/claude commands
    use_tag_format=false
    actual_branch=$branch
    if [ "$branch" = "-b" ]; then
        use_tag_format=true
        actual_branch=$3
    fi
    branch=$actual_branch

    # Get project name
    project=$(basename $(pwd))
    short=$(echo $project | cut -d- -f2-)
    [ -n "$short" ] && project=$short

    # Get branch and tag (i.e. last component of branch name)
    # Handle empty branch case (for tagless rm)
    if [ -z "$branch" ]; then
        tag=""
        branch_exists=false
        folder=$project
    else
        tag=$(echo $branch | rev | cut -d/ -f1 | rev)
        branch_exists=true
        [ "$(git.exe branch | grep $branch | wc -l)" = "0" ] && branch_exists=false

        # Determine folder name based on flags and existing folders
        if [ "$use_tag_format" = "true" ]; then
            folder=$project-$tag
        elif [ -d "$WORKTREE_HOME/$project" ]; then
            echo "📁 Folder '$project' exists, using '$project-$tag' instead"
            folder=$project-$tag
        else
            folder=$project
        fi
    fi

    # Check folder and worktree existence
    folder_exists=false
    worktree_exists=false
    if [ -d "$WORKTREE_HOME/$folder" ]; then
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
            # Check if main repo is currently on this branch
            current_branch=$(git.exe branch --show-current)
            if [ "$current_branch" = "$branch" ]; then
                # Check if working tree is clean
                is_dirty=$(git.exe status --porcelain)
                if [ -n "$is_dirty" ]; then
                    echo "❌ Cannot create worktree for branch '$branch' - it is currently checked out with uncommitted changes."
                    echo "   Hint: Commit or stash your changes first, then try again."
                    return 1
                fi

                # Find default branch (try main, then master)
                default_branch="main"
                if ! git.exe show-ref --verify --quiet refs/heads/main; then
                    default_branch="master"
                    if ! git.exe show-ref --verify --quiet refs/heads/master; then
                        echo "❌ Cannot auto-switch: no 'main' or 'master' branch found."
                        return 1
                    fi
                fi

                echo "🔄 Switching main worktree from '$branch' to '$default_branch'..."
                git.exe checkout "$default_branch"
            fi
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

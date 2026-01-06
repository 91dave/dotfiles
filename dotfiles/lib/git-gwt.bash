#!/bin/bash
# Sourced by git.sh - do not run directly

_gwt_help() {
    echo "🌳 Git WorkTrees"
    echo "Opinionated helper script for managing git worktrees"
    echo "Relies on having an up-to-date cache of repos in $REPO_HOME"
    echo "Update the repo cache by running: repos cache"
    echo ""
    echo "🌐 Global commands:"
    echo "  gwt ls                        📋 List all worktrees in workspace"
    echo "  gwt add <repo> <branch>       ➕ Find repo and create worktree (repo name as folder)"
    echo "  gwt add <repo> -b <branch>    ➕ Find repo and create worktree (repo-branch as folder)"
    echo "  gwt edit <repo> [branch]      🚀 Open worktree in VS Code (create branch if given)"
    echo "  gwt rm <repo>                 ➖ Find repo and delete default worktree"
    echo "  gwt rm <repo> [branch]        ➖ Find repo and delete tagged worktree"
    echo "  gwt clear                     🗑️  Remove all worktrees"
    echo ""
    echo "📍 Repo-scoped commands: (must be run from a repository folder)"
    echo "  gwt                        📋 List worktrees in current repo"
    echo "  gwt add <branch>           ➕ Create worktree (uses repo name as folder)"
    echo "  gwt add -b <branch>        ➕ Create worktree (uses repo-branch as folder)"
    echo "  gwt edit [branch]          🚀 Open worktree in VS Code (create branch if given)"
    echo "  gwt rm                     ➖ Delete default worktree for this repo"
    echo "  gwt rm [branch]            ➖ Delete worktree named repo-branch"
    echo ""
    echo "💡 Use 'code' as a synonym for 'edit'"
    echo "💡 Use 'claude' instead of 'add' to open 🤖 Claude Code when complete"
    echo ""
    echo "🎮 Related commands"
    echo "  repos                      📦 Manage all repos (fetch, status, main, ls, clear, cache)"
}

_gwt_ls() {
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
}

_gwt_clear() {
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

_gwt_code_home() {
    echo "🚀 Opening VS Code..."
    (cd $WORKTREE_HOME && cmd.exe /c code .)
}

# Execute worktree operation in current repo context
# Args: cmd branch use_tag_format
_gwt_execute() {
    local cmd="$1"
    local branch="$2"
    local use_tag_format="$3"

    # Get project name
    local project=$(basename $(pwd))
    local short=$(echo $project | cut -d- -f2-)
    [ -n "$short" ] && project=$short

    # Get branch and tag (i.e. last component of branch name)
    # Handle empty branch case (for default rm)
    local tag folder branch_exists
    if [ -z "$branch" ]; then
        tag=""
        branch_exists=false
        folder=$project
    else
        tag=$(echo $branch | rev | cut -d/ -f1 | rev)
        branch_exists=true
        [ "$(git.exe branch | grep $branch | wc -l)" = "0" ] && branch_exists=false

        # Determine folder name based on flags and existing worktrees
        if [ "$use_tag_format" = "true" ]; then
            folder=$project-$tag
        elif [ -f "$WORKTREE_HOME/$project-$tag/.git" ]; then
            folder=$project-$tag
        else
            folder=$project
        fi
    fi

    # Check folder and worktree existence
    local folder_exists=false
    local worktree_exists=false
    if [ -d "$WORKTREE_HOME/$folder" ]; then
        folder_exists=true
        local wtc=$(git.exe worktree list | grep $branch | wc -l)
        if [ "$wtc" = 0 ]; then
            worktree_exists=false
            folder=$project-$tag
            [ -d "$WORKTREE_HOME/$folder" ] || folder_exists=false
        else
            worktree_exists=true
        fi
    fi

    #echo -e "  folder_exists=$folder_exists\n  worktree_exists=$worktree_exists\n  folder=$folder"

    # Validate folder and worktree match
    [ "$worktree_exists" = "false" ] && [ "$folder_exists" = "true" ] && echo "⚠️  Folder '$folder' exists in workspace, but is not a valid worktree"

    case "$cmd" in
        rm)
            if [ "$worktree_exists" = "true" ]; then
                echo "🗑️  Deleting worktree ${folder}..."
                git.exe worktree remove "$(wslpath -w $WORKTREE_HOME/$folder)"
            else
                echo "⏭️  Worktree ${folder} does not exist, skipping..."
            fi
            ;;
        add|claude|code|edit)
            # For code/edit without branch, just open existing default worktree
            if [ -z "$branch" ] && [[ "$cmd" =~ ^(code|edit)$ ]]; then
                if [ "$worktree_exists" = "true" ]; then
                    : # Will open via post-command action
                else
                    echo "❌ No default worktree found for $project"
                    echo "   Hint: Create one first with 'gwt add <branch>'"
                    return 1
                fi
            else
                # Check if main repo is currently on this branch
                local current_branch=$(git.exe branch --show-current)
                if [ "$current_branch" = "$branch" ]; then
                    # Check if working tree is clean
                    local is_dirty=$(git.exe status --porcelain)
                    if [ -n "$is_dirty" ]; then
                        echo "❌ Cannot create worktree for branch '$branch' - it is currently checked out with uncommitted changes."
                        echo "   Hint: Commit or stash your changes first, then try again."
                        return 1
                    fi

                    # Find default branch (try main, then master)
                    local default_branch=$(_git_get_default_branch)
                    if [ -z "$default_branch" ]; then
                        echo "❌ Cannot auto-switch: no 'main' or 'master' branch found."
                        return 1
                    fi

                    echo "🔄 Switching main worktree from '$branch' to '$default_branch'..."
                    git.exe checkout "$default_branch"
                fi

                # Fetch and pull latest before creating worktree
                echo "🔄 Fetching latest..."
                git.exe fetch
                if [ -z "$(git.exe status --porcelain)" ]; then
                    echo "🔄 Pulling..."
                    git.exe pull
                fi

                local branch_flag="-b"
                [ "$branch_exists" = "true" ] && branch_flag=""

                if [ "$worktree_exists" = "true" ]; then
                    echo "⏭️  Worktree ${folder} already exists, skipping..."
                else
                    echo "➕ Creating worktree ${folder}..."
                    git.exe worktree add "$(wslpath -w $WORKTREE_HOME/$folder)" $branch_flag $branch
                fi
            fi
            ;;
    esac

    # Post-command actions
    [[ "$cmd" =~ ^(code|edit)$ ]] && echo "🚀 Opening VS Code..." && (cd $WORKTREE_HOME/$folder && cmd.exe /c code .)
    [ "$cmd" = "claude" ] && echo "🤖 Opening Claude Code..." && (cd $WORKTREE_HOME/$folder && cmd.exe /c claude)
}

# Handle commands that require repo context (add/code/claude/rm)
# Finds repo if not in one, then executes the operation
_gwt_dispatch() {
    local cmd="$1"
    local arg2="$2"
    local arg3="$3"
    local arg4="$4"

    # Validate arguments based on context and command
    if [ -z "$arg2" ]; then
        # No second arg - valid for 'rm' or 'code/edit' from within a repo
        if [ "$(is_repo)" = "true" ] && [[ "$cmd" =~ ^(rm|code|edit)$ ]]; then
            : # OK - operation on default worktree from repo context
        else
            _gwt_help && return
        fi
    fi

    # If we are not currently in a repo, find one using arg2 as a search
    if [ "$(is_repo)" = "false" ]; then
        local search="$arg2"
        local branch="$arg3"
        local use_tag_flag=""

        # Handle -b flag in global context: gwt add [repo] -b [branch]
        if [ "$branch" = "-b" ]; then
            use_tag_flag="-b"
            branch="$arg4"
        fi

        [ -z "$search" ] && echo "Error: current contxt is global. cmd=$cmd search=$search branch=$branch"  && _gwt_help && return

        # For add/claude, branch is required
        # For rm/code/edit, branch is optional (default worktree operation)
        if [ -z "$branch" ] && [[ "$cmd" =~ ^(add|claude)$ ]]; then
            _gwt_help && return
        fi

        local results=$(cat $REPO_CACHE | grep $search | wc -l)
        echo "🔍 Found $results repos for '$search'"

        [ "$results" = "1" ] || return

        local result=$(cat $REPO_CACHE | grep $search)
        pushd $REPO_HOME/$result >& /dev/null

        # Determine use_tag_format from flag
        local use_tag_format="false"
        [ "$use_tag_flag" = "-b" ] && use_tag_format="true"

        _gwt_execute "$cmd" "$branch" "$use_tag_format"
        popd >& /dev/null
        return
    fi

    # We're in a repo - parse -b flag for add/code/claude commands
    local branch="$arg2"
    local use_tag_format="false"
    if [ "$branch" = "-b" ]; then
        use_tag_format="true"
        branch="$arg3"
    fi

    _gwt_execute "$cmd" "$branch" "$use_tag_format"
}

gwt() {
    # Verify WSL interop is working
    wslexe check || return 1

    local cmd="${1:-}"

    # No args - list current repo's worktrees
    if [ -z "$cmd" ]; then
        git.exe worktree list
        return
    fi

    case "$cmd" in
        help|usage|-h|--help)
            _gwt_help
            ;;
        ls)
            _gwt_ls
            ;;
        clear)
            _gwt_clear
            ;;
        code|edit)
            # code command without other args just spawns VS code in WORKTREE_HOME
            if [ "$#" = "1" ]; then
                _gwt_code_home
                return
            fi
            _gwt_dispatch "$@"
            ;;
        add|claude|rm)
            _gwt_dispatch "$@"
            ;;
        *)
            _gwt_help
            ;;
    esac
}

# fzf completion for gwt command
_fzf_complete_gwt() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[1]:-}"

    # First arg: complete subcommands
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "ls add rm clear code edit claude help" -- "$cur") )
        return
    fi

    local selected

    # Second arg: context-dependent completion
    case "$cmd" in
        rm)
            # Show existing worktrees
            selected=$(ls -1d "$WORKTREE_HOME"/*/ 2>/dev/null | xargs -n1 basename | \
                fzf --height=70% --layout=reverse --preview "$EZA_PREVIEW $WORKTREE_HOME/{}")
            ;;
        add|code|edit|claude)
            # Show repos from cache
            selected=$(fzf --height=70% --layout=reverse --preview "$EZA_PREVIEW $REPO_HOME/{}" < "$REPO_CACHE")
            ;;
    esac

    if [[ -n "$selected" ]]; then
        COMPREPLY=( "$selected" )
    fi
    printf '\e[5n'
}
complete -F _fzf_complete_gwt -o default -o bashdefault gwt

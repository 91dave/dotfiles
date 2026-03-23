#!/bin/bash
# Sourced by git.sh - do not run directly

_repos_help() {
    echo "📦 Repos"
    echo "Manage all repos in cache"
    echo ""
    echo "Usage:"
    echo "  repos fetch        🔁 Fetch all repos and pull where possible"
    echo "  repos ls           📍 List repos not on main/master or with uncommitted changes"
    echo "  repos main         🔄 Switch all repos to main/master branch"
    echo "  repos clear        🗑️  Delete branches merged into main/master"
    echo "  repos code <repo>  🚀 Open VS Code in matching repo"
    echo "  repos cmd <repo>   💻 Open WSL window in matching repo"
    echo "  repos cd <repo>    📂 pushd into matching repo"
    echo "  repos claude <repo> 🤖 Open Claude Code in matching repo"
    echo "  repos view <repo>  📂 Open GitHub desktop in matching repo"
    echo "  repos work <repo>  📚 Open VS Code and GitHub desktop in matching repo"
    echo "  repos cache        📦 Update cache of repos"
    echo "  repos help         📖 Show this help message"
}

# Check if a repo matches any pattern in .reposignore
# Pattern syntax:
#   pattern    - substring match (e.g., '.bak' matches 'foo.bak/bar')
#   =pattern   - exact basename match (e.g., '=eve' matches only repo named 'eve')
_repos_match_ignore() {
    local repo="$1"
    local basename=$(basename "$repo")

    [[ ! -f "$REPO_IGNORE" ]] && return 1

    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        # Skip empty lines and comments
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

        if [[ "$pattern" =~ ^= ]]; then
            # Exact basename match (strip leading =)
            local exact="${pattern#=}"
            [[ "$basename" == "$exact" ]] && return 0
        else
            # Substring match
            [[ "$repo" =~ $pattern ]] && return 0
        fi
    done < "$REPO_IGNORE"

    return 1
}

# Check if a repo line from cache should be skipped
_repos_should_skip() {
    local repo="$1"
    [[ -z "$repo" || "$repo" =~ ^# ]] && return 0
    _repos_match_ignore "$repo"
}

# Find a repo by search term, returns path if exactly one match
_repos_find() {
    local search="$1"

    if [[ -z "$search" ]]; then
        echo "❌ Error: repo search term required" >&2
        return 1
    fi

    local results=$(grep "$search" "$REPO_CACHE" | wc -l)

    if [[ "$results" -eq 0 ]]; then
        echo "❌ No repos found for '$search'" >&2
        return 1
    elif [[ "$results" -gt 1 ]]; then
        echo "❌ Multiple repos found for '$search':" >&2
        grep "$search" "$REPO_CACHE" | while read -r r; do
            echo "   $r" >&2
        done
        return 1
    fi

    grep "$search" "$REPO_CACHE"
}

_repos_cache() {
    echo "🔍 Scanning for repos in $REPO_HOME..."

    # Filter repos through ignore patterns
    local tmpfile=$(mktemp)
    while IFS= read -r repo; do
        _repos_match_ignore "$repo" || echo "$repo"
    done < <(find_git_repos "$REPO_HOME" 4) > "$tmpfile"
    mv "$tmpfile" "$REPO_CACHE"

    local count=$(wc -l < "$REPO_CACHE")
    echo "✅ Found $count repos, cache updated"
}

_repos_fetch() {
    echo "🔄 Fetching repos..."
    echo ""

    local -a skipped_dirty=()
    local -a skipped_branch=()

    while read -r repo; do
        _repos_should_skip "$repo" && continue

        local repo_path="$REPO_HOME/$repo"
        [[ ! -d "$repo_path/.git" ]] && continue

        printf '\r\e[K⏳ Processing %s...' "$repo"

        pushd "$repo_path" >& /dev/null

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

        printf '\r\e[K'
        echo "📁 $repo"
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
    done < "$REPO_CACHE"

    printf '\r\e[K'

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
}

_repos_clear() {
    local total_branches=0

    echo "🗑️  Deleting merged branches..."
    echo ""

    while read -r repo; do
        _repos_should_skip "$repo" && continue

        local repo_path="$REPO_HOME/$repo"
        [[ ! -d "$repo_path/.git" ]] && continue

        printf '\r\e[K⏳ Processing %s...' "$repo"

        pushd "$repo_path" >& /dev/null

        local default_branch=$(_git_get_default_branch)
        if [[ -z "$default_branch" ]]; then
            popd >& /dev/null
            continue
        fi

        local current_branch=$(git.exe </dev/null branch --show-current 2>/dev/null)
        local repo_printed=false

        # Check if current branch is merged and switch to default if so
        if [[ "$current_branch" != "$default_branch" ]]; then
            local cherry=$(git.exe </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
            local has_unmerged=$(echo "$cherry" | grep -c '^+' || true)

            if [[ "$has_unmerged" -eq 0 ]]; then
                # Current branch is merged - check for uncommitted changes
                local is_dirty=$(git.exe </dev/null status --porcelain 2>/dev/null)
                if [[ -z "$is_dirty" ]]; then
                    # Safe to switch and delete
                    if git.exe </dev/null checkout "$default_branch" >& /dev/null; then
                        printf '\r\e[K'
                        echo "📁 $repo"
                        repo_printed=true
                        echo "   🔄 Switched: $current_branch → $default_branch"
                        if git.exe </dev/null branch -D "$current_branch" >& /dev/null; then
                            echo "   ✅ Deleted: $current_branch"
                            ((total_branches++))
                            git.exe </dev/null pull >& /dev/null
                        else
                            echo "   ❌ Failed to delete: $current_branch"
                        fi
                    fi
                fi
            fi
        fi

        # Get all local branches except default, master, main, and current
        local branches=$(git.exe </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')

        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue

            # Use git cherry to detect merged branches (handles squash/rebase merges)
            # If all lines start with '-' or output is empty, branch is fully merged
            local cherry=$(git.exe </dev/null cherry "origin/$default_branch" "$branch" 2>/dev/null)
            local has_unmerged=$(echo "$cherry" | grep -c '^+' || true)

            if [[ "$has_unmerged" -eq 0 ]]; then
                if [[ "$repo_printed" == false ]]; then
                    printf '\r\e[K'
                    echo "📁 $repo"
                    repo_printed=true
                fi
                if git.exe </dev/null branch -D "$branch" >& /dev/null; then
                    echo "   ✅ Deleted: $branch"
                    ((total_branches++))
                else
                    echo "   ❌ Failed: $branch"
                fi
            fi
        done <<< "$branches"

        popd >& /dev/null
    done < "$REPO_CACHE"

    printf '\r\e[K'

    if [[ $total_branches -gt 0 ]]; then
        echo "✅ Deleted $total_branches branch(es)"
    else
        echo "✅ No merged branches to delete"
    fi
}

_repos_status() {
    echo "🔍 Checking repo status..."
    echo ""
    local -a off_main=()
    local -a dirty=()
    local -a has_merged=()

    while read -r repo; do
        _repos_should_skip "$repo" && continue

        local repo_path="$REPO_HOME/$repo"
        [[ ! -d "$repo_path/.git" ]] && continue

        printf '\r\e[K⏳ Processing %s...' "$repo"

        pushd "$repo_path" >& /dev/null
        [ -f "bash.exe.stackdump" ] && rm bash.exe.stackdump

        local default_branch=$(_git_get_default_branch)
        if [[ -z "$default_branch" ]]; then
            popd >& /dev/null
            continue
        fi

        local current_branch=$(git.exe </dev/null branch --show-current 2>/dev/null)
        local is_dirty=$(git.exe </dev/null status --porcelain 2>/dev/null)
        local repo_name=$(basename "$repo")

        if [[ "$current_branch" != "$default_branch" ]]; then
            # Check if branch has unmerged commits (using git cherry for squash/rebase detection)
            local cherry=$(git.exe </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
            local unmerged=$(echo "$cherry" | grep -c '^+' || true)
            if [[ "$unmerged" -eq 0 ]]; then
                off_main+=("📁 $repo_name ($current_branch) ✅ merged")
            else
                off_main+=("📁 $repo_name ($current_branch) ⚠️  $unmerged unmerged commit(s)")
            fi
        fi

        if [[ -n "$is_dirty" ]] && [[ "$current_branch" == "$default_branch" ]]; then
            local file_count=$(echo "$is_dirty" | wc -l | tr -d ' ')
            dirty+=("📁 $repo_name ($current_branch, $file_count file(s))")
        fi

        # Check for merged branches that can be cleared (using git cherry for squash/rebase detection)
        local branches=$(git.exe </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')
        local merged_count=0
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            local cherry=$(git.exe </dev/null cherry "origin/$default_branch" "$branch" 2>/dev/null)
            local has_unmerged=$(echo "$cherry" | grep -c '^+' || true)
            [[ "$has_unmerged" -eq 0 ]] && ((merged_count++))
        done <<< "$branches"
        if [[ $merged_count -gt 0 ]]; then
            has_merged+=("📁 $repo_name ($merged_count branch(es))")
        fi

        popd >& /dev/null
    done < "$REPO_CACHE"

    printf '\r\e[K'

    if [[ ${#off_main[@]} -gt 0 ]]; then
        echo "🌿 Not on main (${#off_main[@]}):"
        printf '%s\n' "${off_main[@]}" | sort | while read -r item; do
            echo "   $item"
        done
        echo ""
    fi

    if [[ ${#dirty[@]} -gt 0 ]]; then
        echo "📝 Uncommitted changes (${#dirty[@]}):"
        printf '%s\n' "${dirty[@]}" | sort | while read -r item; do
            echo "   $item"
        done
        echo ""
    fi

    if [[ ${#has_merged[@]} -gt 0 ]]; then
        echo "🧹 Merged branches to clear (${#has_merged[@]}):"
        printf '%s\n' "${has_merged[@]}" | sort | while read -r item; do
            echo "   $item"
        done
        echo ""
    fi

    if [[ ${#off_main[@]} -eq 0 ]] && [[ ${#dirty[@]} -eq 0 ]] && [[ ${#has_merged[@]} -eq 0 ]]; then
        echo "✅ All repos are clean and on main"
    fi
}

_repos_main() {
    echo "🔄 Switching repos to main branch..."
    echo ""
    local switched=0
    local skipped_dirty=()
    local skipped_unmerged=()

    while read -r repo; do
        _repos_should_skip "$repo" && continue

        local repo_path="$REPO_HOME/$repo"
        [[ ! -d "$repo_path/.git" ]] && continue

        pushd "$repo_path" >& /dev/null

        local default_branch=$(_git_get_default_branch)
        if [[ -z "$default_branch" ]]; then
            popd >& /dev/null
            continue
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

        # Check for unmerged commits (using git cherry for squash/rebase detection)
        local cherry=$(git.exe </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
        local unmerged=$(echo "$cherry" | grep -c '^+' || true)
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
    done < "$REPO_CACHE"

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
}

_repos_edit() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    echo "🚀 Opening VS Code in $repo..."
    (cd "$repo_path" && cmd.exe /c code .)
}

_repos_view() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    echo "📁 Opening $repo in GitHub Desktop"
    (cd "$repo_path" && cmd.exe /c github)
}

_repos_cmd() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    local repo_path_win=$(wslpath -w "$repo_path")
    echo "💻 Opening CMD in $repo..."
    (cd "$repo_path" && cmd.exe /c start wsl)
}

_repos_cd() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    echo "📂 $repo"
    pushd "$repo_path" > /dev/null
}

_repos_claude() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    echo "🤖 Opening Claude Code in $repo..."
    (cd "$repo_path" && cmd.exe /c claude)
}

repos() {
    local cmd="${1:-help}"

    if [[ ! -f "$REPO_CACHE" ]]; then
        echo "❌ Error: repo list file not found: $REPO_CACHE"
        return 1
    fi

    case "$cmd" in
        view)           _repos_view "$2" ;;
        work)           _repos_view "$2" ; _repos_edit "$2" ;;
        fetch)          _repos_fetch ;;
        reset)          _repos_fetch; echo ""; _repos_clear; echo ""; _repos_status ;;
        cache)          _repos_cache ;;
        clear)          _repos_clear ;;
        status|ls)      _repos_status ;;
        main)           _repos_main ;;
        edit|code)      _repos_edit "$2" ;;
        cmd)            _repos_cmd "$2" ;;
        cd)             _repos_cd "$2" ;;
        claude)         _repos_claude "$2" ;;
        *)              _repos_help ;;
    esac
}

alias repo='repos'

# fzf completion for repos command
_fzf_complete_repos() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[1]:-}"

    # First arg: complete subcommands
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "fetch ls main clear code cmd cd claude cache help view" -- "$cur") )
        return
    fi

    # Second arg after repo-selecting commands: use fzf to pick a repo
    case "$cmd" in
        code|cmd|cd|claude|edit|view)
            local selected
            selected=$(fzf --height=70% --layout=reverse --preview "$EZA_PREVIEW $REPO_HOME/{}" < "$REPO_CACHE")
            if [[ -n "$selected" ]]; then
                COMPREPLY=( "$selected" )
            fi
            printf '\e[5n'
            ;;
    esac
}
complete -F _fzf_complete_repos -o default -o bashdefault repos repo

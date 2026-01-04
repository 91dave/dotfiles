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
    echo "  repos code [repo]  🚀 Open VS Code in matching repo"
    echo "  repos cmd [repo]   💻 Open CMD window in matching repo"
    echo "  repos cache        📂 Update cache of repos"
    echo "  repos help         📖 Show this help message"
}

# Check if a repo line from cache should be skipped
_repos_should_skip() {
    local repo="$1"
    [[ -z "$repo" || "$repo" =~ ^# || "$repo" =~ '\.bak' || "$repo" =~ "_backup" ]]
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
    find_git_repos "$REPO_HOME" 4 | grep -v _backup | grep -v '\.bak' > "$REPO_CACHE"
    local count=$(wc -l < "$REPO_CACHE")
    echo "✅ Found $count repos, cache updated"
}

_repos_fetch() {
    local -a skipped_dirty=()
    local -a skipped_branch=()

    while read -r repo; do
        _repos_should_skip "$repo" && continue

        local repo_path="$REPO_HOME/$repo"
        [[ ! -d "$repo_path/.git" ]] && continue

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
    done < "$REPO_CACHE"

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

        pushd "$repo_path" >& /dev/null

        local default_branch=$(_git_get_default_branch)
        if [[ -z "$default_branch" ]]; then
            popd >& /dev/null
            continue
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
    done < "$REPO_CACHE"

    echo ""
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

        local current_branch=$(git.exe </dev/null branch --show-current 2>/dev/null)
        local is_dirty=$(git.exe </dev/null status --porcelain 2>/dev/null)
        local repo_name=$(basename "$repo")

        if [[ "$current_branch" != "$default_branch" ]]; then
            # Check if branch has unmerged commits
            local unmerged=$(git.exe </dev/null rev-list --count "$default_branch..HEAD" 2>/dev/null || echo "0")
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

        popd >& /dev/null
    done < "$REPO_CACHE"

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

    if [[ ${#off_main[@]} -eq 0 ]] && [[ ${#dirty[@]} -eq 0 ]]; then
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
    #ghd=$(wslpath "$(cmd.exe /k "echo %localappdata%\\GitHubDesktop\\GitHubDesktop.exe & exit" 2>/dev/null)")
    #if [ -f "$ghd" ]; then
    #    :
    #else
    #    echo "❌ Error: can't find GitHubDesktop.exe: BIN=$ghd"
    #    return 1
    #fi
    echo "📁 Opening in $repo in GitHub Desktop"
    (cd "$repo_path" && cmd.exe /c github)
}

_repos_cmd() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    local repo_path_win=$(wslpath -w "$repo_path")
    echo "💻 Opening CMD in $repo..."
    (cd "$repo_path" && cmd.exe /c start cmd.exe)
}

repos() {
    local cmd="${1:-help}"

    if [[ ! -f "$REPO_CACHE" ]]; then
        echo "❌ Error: repo list file not found: $REPO_CACHE"
        return 1
    fi

    case "$cmd" in
        view)      _repos_view "$2" ;;
        fetch)     _repos_fetch ;;
        cache)     _repos_cache ;;
        clear)     _repos_clear ;;
        status|ls) _repos_status ;;
        main)      _repos_main ;;
        edit|code)      _repos_edit "$2" ;;
        cmd)       _repos_cmd "$2" ;;
        *)         _repos_help ;;
    esac
}

alias repo='repos'

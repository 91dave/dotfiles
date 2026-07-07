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
    echo "  repos clear        🗑️  Reset to main; delete branches with no unmerged work of yours"
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

# Emit the unmerged ('+') commit SHAs of a ref relative to the default branch on origin
_repos_unmerged_shas() {
    local default_branch="$1" ref="$2"
    git.exe </dev/null cherry "origin/$default_branch" "$ref" 2>/dev/null | awk '/^\+/ { print $2 }'
}

# Succeed if any of the given commit SHAs was authored by the current git user.
# An unknown local identity is treated as "mine" so nothing gets auto-deleted.
_repos_authored_by_me() {
    local me
    me=$(git.exe </dev/null config user.email 2>/dev/null)
    [[ -z "$me" ]] && return 0
    [[ $# -eq 0 ]] && return 1
    git.exe </dev/null show -s --format='%ae' "$@" 2>/dev/null | grep -qxF "$me"
}

# Succeed if the ref has unmerged commits authored by the current git user
_repos_own_unmerged() {
    local default_branch="$1" ref="$2"
    local -a unmerged
    mapfile -t unmerged < <(_repos_unmerged_shas "$default_branch" "$ref")
    [[ ${#unmerged[@]} -eq 0 ]] && return 1
    _repos_authored_by_me "${unmerged[@]}"
}

# Succeed if every commit on the ref already exists on some remote-tracking branch
_repos_all_on_remote() {
    [[ -z "$(git.exe </dev/null rev-list "$1" --not --remotes 2>/dev/null)" ]]
}

# Delete a local branch when nothing of yours would be lost: it is fully merged, or its
# unmerged commits are someone else's and already on a remote. Prints the outcome and
# returns 0 only when the branch is deleted; stays silent when it is your own unmerged work.
_repos_clear_branch() {
    local default_branch="$1" branch="$2"
    local -a unmerged
    mapfile -t unmerged < <(_repos_unmerged_shas "$default_branch" "$branch")

    local reason
    if [[ ${#unmerged[@]} -eq 0 ]]; then
        reason="merged"
    elif _repos_authored_by_me "${unmerged[@]}"; then
        return 2
    elif _repos_all_on_remote "$branch"; then
        reason="others' unmerged work, safe on remote"
    else
        echo "   ⏭️  Kept: $branch (others' unmerged commits, not yet on a remote)"
        return 1
    fi

    if git.exe </dev/null branch -D "$branch" >& /dev/null; then
        echo "   ✅ Deleted: $branch ($reason)"
        return 0
    fi
    echo "   ❌ Failed to delete: $branch"
    return 1
}

_repos_clear() {
    local total_branches=0

    echo "🗑️  Clearing branches with no unmerged work of yours..."
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

        # Leave the current branch for main when it holds no unmerged work of yours.
        # Only off-default repos need the working-tree status, so it is not computed otherwise.
        if [[ "$current_branch" != "$default_branch" ]]; then
            local status=$(git.exe </dev/null status --porcelain 2>/dev/null)

            # Only a dirty tree can hold an untracked swap file. git status has already listed
            # them, so pull the stale (>6h) ones from its output rather than walking the tree.
            if [[ -n "$status" ]]; then
                local now=$(date +%s) rel mtime
                while IFS= read -r rel; do
                    [[ "$rel" == *.swp ]] || continue
                    mtime=$(stat -c %Y "$repo_path/$rel" 2>/dev/null) || continue
                    (( now - mtime > 21600 )) || continue
                    rm -f "$repo_path/$rel" 2>/dev/null || continue
                    if [[ "$repo_printed" == false ]]; then
                        printf '\r\e[K'
                        echo "📁 $repo"
                        repo_printed=true
                    fi
                    echo "   🧹 Removed stale swap file: $rel"
                done < <(printf '%s\n' "$status" | awk '/^\?\? / { print substr($0, 4) }')
            fi

            # Tracked changes block a switch; untracked cruft (swap files, stray notes) does not
            local tracked_dirty=$(printf '%s\n' "$status" | grep -vE '^(\?\?|[[:space:]]*$)')

            if [[ -z "$tracked_dirty" ]] && ! _repos_own_unmerged "$default_branch" HEAD; then
                if git.exe </dev/null checkout "$default_branch" >& /dev/null; then
                    if [[ "$repo_printed" == false ]]; then
                        printf '\r\e[K'
                        echo "📁 $repo"
                        repo_printed=true
                    fi
                    echo "   🔄 Switched: $current_branch → $default_branch"
                    local out rc
                    out=$(_repos_clear_branch "$default_branch" "$current_branch"); rc=$?
                    [[ -n "$out" ]] && echo "$out"
                    [[ $rc -eq 0 ]] && total_branches=$((total_branches + 1))
                    git.exe </dev/null pull >& /dev/null
                fi
            fi
        fi

        # Get all local branches except default, master, main, and current
        local branches=$(git.exe </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')

        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue

            local out rc
            out=$(_repos_clear_branch "$default_branch" "$branch"); rc=$?
            if [[ -n "$out" ]]; then
                if [[ "$repo_printed" == false ]]; then
                    printf '\r\e[K'
                    echo "📁 $repo"
                    repo_printed=true
                fi
                echo "$out"
            fi
            [[ $rc -eq 0 ]] && total_branches=$((total_branches + 1))
        done <<< "$branches"

        popd >& /dev/null
    done < "$REPO_CACHE"

    printf '\r\e[K'

    if [[ $total_branches -gt 0 ]]; then
        echo "✅ Deleted $total_branches branch(es)"
    else
        echo "✅ Nothing to clear"
    fi
}

_repos_wip_record() {
    local records_file="$1" repo_name="$2" repo_rel="$3" branch="$4" \
          default_branch="$5" dirty_count="$6" unmerged="$7" merged="$8"
    command -v jq >/dev/null 2>&1 || return 0

    local commits_raw=""
    if [[ "$branch" != "$default_branch" ]]; then
        commits_raw=$(git.exe </dev/null log -n 50 --format='%h%x1f%ad%x1f%s' \
            --date=short "origin/$default_branch..HEAD" 2>/dev/null)
    fi

    local changed_raw=$(git.exe </dev/null status --porcelain 2>/dev/null \
        | sed -e 's/^...//' -e 's/^.* -> //')
    local last_activity=$(git.exe </dev/null log -1 --format=%ad --date=short HEAD 2>/dev/null)

    jq -c -n \
        --arg name "$repo_name" \
        --arg path "$repo_rel" \
        --arg branch "$branch" \
        --arg default "$default_branch" \
        --argjson dirty "$dirty_count" \
        --argjson unmerged "$unmerged" \
        --arg merged "$merged" \
        --arg last "$last_activity" \
        --arg commits "$commits_raw" \
        --arg changed "$changed_raw" \
        '{
            name: $name,
            path: $path,
            branch: $branch,
            default_branch: $default,
            merged: ($merged == "true"),
            dirty_files: $dirty,
            unmerged_commits: $unmerged,
            last_activity: $last,
            commits: ($commits | split("\n") | map(select(length > 0))
                        | map(split("") | {sha: .[0], date: .[1], subject: .[2]})),
            changed_files: ($changed | split("\n") | map(select(length > 0)))
        }' >> "$records_file"
}

_repos_status() {
    echo "🔍 Checking repo status..."
    echo ""
    local -a off_main=()
    local -a dirty=()
    local -a has_merged=()

    local records_file=$(mktemp)

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
        local dirty_count=0
        [[ -n "$is_dirty" ]] && dirty_count=$(echo "$is_dirty" | wc -l | tr -d ' ')

        local is_wip=false unmerged=0 merged=false
        if [[ "$current_branch" != "$default_branch" ]]; then
            is_wip=true
            # Check if branch has unmerged commits (using git cherry for squash/rebase detection)
            local cherry=$(git.exe </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
            unmerged=$(echo "$cherry" | grep -c '^+' || true)
            if [[ "$unmerged" -eq 0 ]]; then
                merged=true
                off_main+=("📁 $repo_name ($current_branch) ✅ merged")
            else
                off_main+=("📁 $repo_name ($current_branch) ⚠️  $unmerged unmerged commit(s)")
            fi
        fi

        if [[ -n "$is_dirty" ]] && [[ "$current_branch" == "$default_branch" ]]; then
            is_wip=true
            dirty+=("📁 $repo_name ($current_branch, $dirty_count file(s))")
        fi

        [[ "$is_wip" == true ]] && _repos_wip_record "$records_file" "$repo_name" \
            "$repo" "$current_branch" "$default_branch" "$dirty_count" "$unmerged" "$merged"

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

    if command -v jq >/dev/null 2>&1; then
        jq -s --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg home "$REPO_HOME" \
            '{generated: $generated, repo_home: $home, repos: .}' \
            "$records_file" > "$REPO_STATUS" 2>/dev/null \
            && echo "💾 Wrote WIP snapshot to $REPO_STATUS"
    fi
    rm -f "$records_file"

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

    if [[ -z "$search" || "$search" == "." ]]; then
        echo "🚀 Opening VS Code in current folder..."
        cmd.exe /c code .
        return
    fi

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

    # Second arg after repo-selecting commands: pick a repo, pre-filtered by what is typed
    case "$cmd" in
        code|cmd|cd|claude|edit|view)
            local -a matches
            mapfile -t matches < <(grep -- "$cur" "$REPO_CACHE")

            if [[ ${#matches[@]} -eq 1 ]]; then
                COMPREPLY=( "${matches[0]}" )
                return
            fi

            local selected
            selected=$(fzf --height=70% --layout=reverse --query="$cur" \
                --preview "$EZA_PREVIEW $REPO_HOME/{}" < "$REPO_CACHE")
            if [[ -n "$selected" ]]; then
                COMPREPLY=( "$selected" )
            fi
            printf '\e[5n'
            ;;
    esac
}
complete -F _fzf_complete_repos -o default -o bashdefault repos repo

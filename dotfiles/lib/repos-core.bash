#!/bin/bash
# Sharable repos logic sourced by lib/git.sh and bin/repos; config from lib/repos-config.sh

find_git_repos() {
    local folder="${1:-.}"
    local max_depth="${2:-3}"

    find "$folder" -maxdepth "$max_depth" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        dirname "$gitdir" | sed "s|^$folder/||"
    done
}

_git_get_default_branch() {
    if git </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        echo "main"
    elif git </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
        echo "master"
    else
        return 1
    fi
}

_repos_help() {
    echo "📦 Repos"
    echo "Manage all repos in cache"
    echo ""
    echo "Usage:"
    echo "  repos ls [search]   📂 List repos (🔒 readonly, 📝 modified, 🌿 branch)"
    echo "  repos find [search] 🔎 Raw grep of the cache (plain paths, no decoration)"
    echo "  repos status        📍 Report repos not on main/master or with uncommitted changes"
    echo "  repos fetch         🔁 Fetch all repos and pull where possible"
    echo "  repos main          🔄 Switch all repos to main/master branch"
    echo "  repos clear [--all] 🗑️  Reset current branch to main and delete it when it holds no unmerged work of yours (--all sweeps every branch)"
    echo "  repos reset         ♻️  fetch, then clear, then status"
    echo "  repos code <repo>   🚀 Open VS Code in matching repo"
    echo "  repos cmd <repo>    💻 Open WSL window in matching repo"
    echo "  repos cd <repo>     📂 pushd into matching repo (prints path when non-interactive)"
    echo "  repos resolve <r>   📍 Print absolute path to matching repo (GitHub search fallback)"
    echo "  repos claude <repo> 🤖 Open Claude Code in matching repo"
    echo "  repos view <repo>   📂 Open GitHub Desktop in matching repo"
    echo "  repos work <repo>   📚 Open VS Code and GitHub Desktop in matching repo"
    echo "  repos cache         📦 Rebuild repo cache and refresh archived/readonly list"
    echo "  repos help          📖 Show this help message"
    echo ""
    echo "ls flags:"
    echo "  -r, --readonly      Only archived/readonly repos"
    echo "  -m, --modified      Only repos with uncommitted changes"
    echo "  -a, --active        Only repos with work in progress"
}

# Match a repo against .reposignore: substring patterns, or =name for exact basename
_repos_match_ignore() {
    local repo="$1"
    local basename=$(basename "$repo")

    [[ ! -f "$REPO_IGNORE" ]] && return 1

    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
        [[ -z "$pattern" || "$pattern" =~ ^# ]] && continue

        if [[ "$pattern" =~ ^= ]]; then
            local exact="${pattern#=}"
            [[ "$basename" == "$exact" ]] && return 0
        else
            [[ "$repo" =~ $pattern ]] && return 0
        fi
    done < "$REPO_IGNORE"

    return 1
}

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

# Extract owner/repo from a git remote URL (scp-like or scheme URL forms)
_repos_owner_repo() {
    local url="${1%.git}"
    if [[ "$url" =~ ^[^@]+@[^:]+:(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    elif [[ "$url" =~ ^[a-z]+://[^/]+/(.+)$ ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        return 1
    fi
}

# Record local paths of GitHub-archived repos in $REPO_READONLY, querying gh per owner
_repos_readonly_refresh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "⚠️  gh not found; skipping archived/readonly detection" >&2
        return 0
    fi

    echo "🔍 Checking GitHub for archived repos..."

    local -A repo_owner_name=()
    local -A owners=()
    local repo url owner_name
    while IFS= read -r repo; do
        _repos_should_skip "$repo" && continue
        [[ -d "$REPO_HOME/$repo/.git" ]] || continue
        url=$(git -C "$REPO_HOME/$repo" </dev/null config --get remote.origin.url 2>/dev/null)
        [[ -z "$url" ]] && continue
        owner_name=$(_repos_owner_repo "$url") || continue
        repo_owner_name["$repo"]="$owner_name"
        owners["${owner_name%%/*}"]=1
    done < "$REPO_CACHE"

    local -A archived=()
    local owner line
    for owner in "${!owners[@]}"; do
        while IFS= read -r line; do
            [[ -n "$line" ]] && archived["$line"]=1
        done < <(gh repo list "$owner" --archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null)
    done

    local tmpfile=$(mktemp)
    for repo in "${!repo_owner_name[@]}"; do
        [[ -n "${archived[${repo_owner_name[$repo]}]:-}" ]] && echo "$repo"
    done | sort > "$tmpfile"
    mv "$tmpfile" "$REPO_READONLY"

    echo "🔒 $(wc -l < "$REPO_READONLY") archived (readonly) repo(s) recorded"
}

_repos_is_readonly() {
    [[ -f "$REPO_READONLY" ]] || return 1
    grep -qxF "$1" "$REPO_READONLY"
}

# Search GitHub when a repo is not cloned locally
_repos_github_fallback() {
    local search="$1"
    if ! command -v gh >/dev/null 2>&1; then
        echo "❌ No repos found for '$search'" >&2
        return 1
    fi

    local owner hits gh_matches=""
    for owner in $REPO_OWNERS; do
        hits=$(gh search repos "$search" --owner "$owner" --json fullName --jq '.[].fullName' 2>/dev/null)
        [[ -n "$hits" ]] && gh_matches="${gh_matches:+$gh_matches$'\n'}$hits"
    done

    if [[ -n "$gh_matches" ]]; then
        echo "⚠️  Not cloned locally. Found on GitHub:" >&2
        printf '%s\n' "$gh_matches" | while read -r r; do echo "   $r" >&2; done
        return 2
    fi

    echo "❌ No repos found for '$search' (local cache or GitHub)" >&2
    return 1
}

# Print the absolute path of the single matching repo; GitHub fallback when none local
_repos_resolve() {
    local search="$1"
    if [[ -z "$search" ]]; then
        echo "❌ Error: repo search term required" >&2
        return 1
    fi

    local matches count
    matches=$(grep -i -- "$search" "$REPO_CACHE")
    count=$(printf '%s' "$matches" | grep -c . || true)

    if [[ "$count" -eq 0 ]]; then
        _repos_github_fallback "$search"
        return $?
    elif [[ "$count" -gt 1 ]]; then
        echo "❌ Multiple repos found for '$search':" >&2
        printf '%s\n' "$matches" | while read -r r; do echo "   $REPO_HOME/$r" >&2; done
        return 1
    fi

    _repos_is_readonly "$matches" && echo "🔒 $matches is readonly (archived on GitHub)" >&2
    echo "$REPO_HOME/$matches"
}

# Raw grep of the cache (no emoji, no state lookup); whole cache when no term
_repos_find_cmd() {
    local search="$1"
    if [[ -n "$search" ]]; then
        grep -i -- "$search" "$REPO_CACHE"
    else
        cat "$REPO_CACHE"
    fi
}

# List repos from the cache with a status emoji, optional filtering by flag/search
_repos_ls() {
    local filter="all" search=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -r|--readonly) filter="readonly" ;;
            -m|--modified) filter="modified" ;;
            -a|--active)   filter="active" ;;
            -*)            echo "❌ Unknown flag: $1" >&2; return 1 ;;
            *)             search="$1" ;;
        esac
        shift
    done

    local modified_set="" active_set=""
    if command -v jq >/dev/null 2>&1 && [[ -f "$REPO_STATUS" ]]; then
        modified_set=$(jq -r '.repos[] | select(.dirty_files > 0) | .path' "$REPO_STATUS" 2>/dev/null)
        active_set=$(jq -r '.repos[].path' "$REPO_STATUS" 2>/dev/null)
    fi

    local repo
    while IFS= read -r repo; do
        _repos_should_skip "$repo" && continue
        [[ -n "$search" ]] && ! grep -iq -- "$search" <<< "$repo" && continue

        local readonly=false modified=false active=false
        _repos_is_readonly "$repo" && readonly=true
        grep -qxF "$repo" <<< "$modified_set" && modified=true
        grep -qxF "$repo" <<< "$active_set" && active=true

        case "$filter" in
            readonly) [[ "$readonly" == true ]] || continue ;;
            modified) [[ "$modified" == true ]] || continue ;;
            active)   [[ "$active" == true ]]   || continue ;;
        esac

        local emoji="📁"
        if [[ "$readonly" == true ]]; then emoji="🔒"
        elif [[ "$modified" == true ]]; then emoji="📝"
        elif [[ "$active" == true ]]; then emoji="🌿"
        fi
        echo "$emoji $repo"
    done < "$REPO_CACHE" | sort -k2
}

_repos_cache() {
    echo "🔍 Scanning for repos in $REPO_HOME..."

    local tmpfile=$(mktemp)
    while IFS= read -r repo; do
        _repos_match_ignore "$repo" || echo "$repo"
    done < <(find_git_repos "$REPO_HOME" 4) > "$tmpfile"
    mv "$tmpfile" "$REPO_CACHE"

    local count=$(wc -l < "$REPO_CACHE")
    echo "✅ Found $count repos, cache updated"

    _repos_readonly_refresh
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
        if ! git </dev/null fetch origin main 2>/dev/null; then
            fetch_branch="master"
            if ! git </dev/null fetch origin master 2>/dev/null; then
                popd >& /dev/null
                continue
            fi
        fi

        local commits=$(git </dev/null rev-list --count HEAD..origin/$fetch_branch 2>/dev/null || echo "0")

        if [[ "$commits" -eq 0 ]]; then
            popd >& /dev/null
            continue
        fi

        printf '\r\e[K'
        echo "📁 $repo"
        echo "   📥 $commits new commit(s)"

        local branch=$(git </dev/null branch --show-current)
        local is_dirty=$(git </dev/null status --porcelain)

        if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ -z "$is_dirty" ]]; then
            git </dev/null pull origin "$branch" >& /dev/null
            echo "   ✅ Pulled"
        else
            # Dirty takes priority over branch mismatch
            if [[ -n "$is_dirty" ]]; then
                skipped_dirty+=("$repo")
            else
                skipped_branch+=("$repo ($branch)")
            fi
        fi

        popd >& /dev/null
    done < "$REPO_CACHE"

    printf '\r\e[K'

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
    git </dev/null cherry "origin/$default_branch" "$ref" 2>/dev/null | awk '/^\+/ { print $2 }'
}

# Unknown local identity is treated as "mine" so nothing gets auto-deleted
_repos_authored_by_me() {
    local me
    me=$(git </dev/null config user.email 2>/dev/null)
    [[ -z "$me" ]] && return 0
    [[ $# -eq 0 ]] && return 1
    git </dev/null show -s --format='%ae' "$@" 2>/dev/null | grep -qxF "$me"
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
    [[ -z "$(git </dev/null rev-list "$1" --not --remotes 2>/dev/null)" ]]
}

# Delete a branch only when nothing of yours is lost (merged, or others' work safe on remote)
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

    if git </dev/null branch -D "$branch" >& /dev/null; then
        echo "   ✅ Deleted: $branch ($reason)"
        return 0
    fi
    echo "   ❌ Failed to delete: $branch"
    return 1
}

_repos_clear() {
    local all=false
    [[ "$1" == "--all" ]] && all=true
    local total_branches=0

    if [[ "$all" == true ]]; then
        echo "🗑️  Clearing all branches with no unmerged work of yours..."
    else
        echo "🗑️  Clearing the current branch where it holds no unmerged work of yours..."
    fi
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

        local current_branch=$(git </dev/null branch --show-current 2>/dev/null)
        local repo_printed=false

        # On a non-default branch: switch to main and delete it when it holds no work of yours
        if [[ "$current_branch" != "$default_branch" ]]; then
            local status=$(git </dev/null status --porcelain 2>/dev/null)

            # git status already lists untracked files; pull stale (>6h) swap files from its output
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

            # Tracked changes block a switch; untracked cruft does not
            local tracked_dirty=$(printf '%s\n' "$status" | grep -vE '^(\?\?|[[:space:]]*$)')

            if [[ -z "$tracked_dirty" ]] && ! _repos_own_unmerged "$default_branch" HEAD; then
                if git </dev/null checkout "$default_branch" >& /dev/null; then
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
                    git </dev/null pull >& /dev/null
                fi
            fi
        elif [[ "$all" != true ]]; then
            # Already on the default branch and not sweeping: nothing to clear, skip the cost
            popd >& /dev/null
            continue
        fi

        # --all: also sweep every remaining local branch, not just the current one
        if [[ "$all" == true ]]; then
            local branches=$(git </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')
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
        fi

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
        commits_raw=$(git </dev/null log -n 50 --format='%h%x1f%ad%x1f%s' \
            --date=short "origin/$default_branch..HEAD" 2>/dev/null)
    fi

    local changed_raw=$(git </dev/null status --porcelain 2>/dev/null \
        | sed -e 's/^...//' -e 's/^.* -> //')
    local last_activity=$(git </dev/null log -1 --format=%ad --date=short HEAD 2>/dev/null)

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
                        | map(split("") | {sha: .[0], date: .[1], subject: .[2]})),
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

        local current_branch=$(git </dev/null branch --show-current 2>/dev/null)
        local is_dirty=$(git </dev/null status --porcelain 2>/dev/null)
        local repo_name=$(basename "$repo")
        local dirty_count=0
        [[ -n "$is_dirty" ]] && dirty_count=$(echo "$is_dirty" | wc -l | tr -d ' ')

        local is_wip=false unmerged=0 merged=false
        if [[ "$current_branch" != "$default_branch" ]]; then
            is_wip=true
            # git cherry detects squash/rebase-merged commits
            local cherry=$(git </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
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

        local branches=$(git </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')
        local merged_count=0
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            local cherry=$(git </dev/null cherry "origin/$default_branch" "$branch" 2>/dev/null)
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

        local current_branch=$(git </dev/null branch --show-current 2>/dev/null)
        if [[ "$current_branch" == "$default_branch" ]]; then
            popd >& /dev/null
            continue
        fi

        local is_dirty=$(git </dev/null status --porcelain 2>/dev/null)
        if [[ -n "$is_dirty" ]]; then
            skipped_dirty+=("$repo ($current_branch)")
            popd >& /dev/null
            continue
        fi

        local cherry=$(git </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
        local unmerged=$(echo "$cherry" | grep -c '^+' || true)
        if [[ "$unmerged" -gt 0 ]]; then
            skipped_unmerged+=("$repo ($current_branch, $unmerged commit(s))")
            popd >& /dev/null
            continue
        fi

        if git </dev/null checkout "$default_branch" >& /dev/null; then
            echo "✅ $repo: $current_branch → $default_branch"
            ((switched++))
        else
            echo "❌ $repo: failed to switch"
        fi

        popd >& /dev/null
    done < "$REPO_CACHE"

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
    if _repos_is_readonly "$repo"; then
        echo "🔒 $repo (readonly — archived on GitHub)"
    else
        echo "📂 $repo"
    fi
    pushd "$repo_path" > /dev/null
}

_repos_claude() {
    local search="$1"
    local repo=$(_repos_find "$search") || return 1

    local repo_path="$REPO_HOME/$repo"
    echo "🤖 Opening Claude Code in $repo..."
    (cd "$repo_path" && cmd.exe /c claude)
}

_repos_dispatch() {
    local cmd="${1:-help}"

    if [[ "$cmd" != "cache" && "$cmd" != "help" && ! -f "$REPO_CACHE" ]]; then
        echo "❌ Error: repo cache not found: $REPO_CACHE" >&2
        echo "   Run 'repos cache' to build it" >&2
        return 1
    fi

    case "$cmd" in
        view)           _repos_view "$2" ;;
        work)           _repos_view "$2" ; _repos_edit "$2" ;;
        fetch)          _repos_fetch ;;
        reset)          _repos_fetch; echo ""; _repos_clear; echo ""; _repos_status ;;
        cache)          _repos_cache ;;
        clear)          shift; _repos_clear "$@" ;;
        status)         _repos_status ;;
        ls)             shift; _repos_ls "$@" ;;
        find)           _repos_find_cmd "$2" ;;
        main)           _repos_main ;;
        edit|code)      _repos_edit "$2" ;;
        cmd)            _repos_cmd "$2" ;;
        cd|resolve)     _repos_resolve "$2" ;;
        claude)         _repos_claude "$2" ;;
        *)              _repos_help ;;
    esac
}

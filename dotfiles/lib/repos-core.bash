#!/bin/bash
# Sharable repos logic sourced by lib/git.sh and bin/repos; config from lib/repos-config.sh

find_git_repos() {
    local folder="${1:-.}"
    local max_depth="${2:-3}"

    find "$folder" -maxdepth "$max_depth" -type d -name ".git" 2>/dev/null | while read -r gitdir; do
        dirname "$gitdir" | sed "s|^$folder/||"
    done
}

_REPOS_GIT_EXE=$(command -v git.exe 2>/dev/null)

# Windows git reads NTFS directly; Linux git over the WSL 9P bridge is ~50x slower on large repos
_repos_git() {
    if [[ -n "$_REPOS_GIT_EXE" && "${REPOS_WINDOWS_GIT:-1}" == 1 && "$PWD" == /mnt/[a-z]/* ]]; then
        "$_REPOS_GIT_EXE" "$@" | tr -d '\r'
        return "${PIPESTATUS[0]}"
    fi
    git "$@"
}

_git_get_default_branch() {
    if _repos_git </dev/null show-ref --verify --quiet refs/heads/main 2>/dev/null; then
        echo "main"
    elif _repos_git </dev/null show-ref --verify --quiet refs/heads/master 2>/dev/null; then
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
    echo "  repos find [search] 🔎 Absolute paths of matching repos (no decoration)"
    echo "  repos status [--all]📍 Report repos not on main/master or with uncommitted changes (--all also lists merged branches to clear)"
    echo "  repos fetch         🔁 Fetch all repos and pull where possible"
    echo "  repos main          🔄 Switch all repos to main/master branch"
    echo "  repos clear [--all] 🗑️  Reset current branch to main and delete it when it holds no unmerged work of yours (--all sweeps every branch)"
    echo "  repos reset [repo]  ♻️  fetch, then clear, then status; with a repo (or .) discard its changes, return to main, pull and delete the branch"
    echo "  repos code [repo]   🚀 Open VS Code in matching repo (current repo if omitted)"
    echo "  repos ide [repo]    🏗️  Open the repo's solution in Visual Studio (current repo if omitted)"
    echo "  repos cmd <repo>    💻 Open WSL window in matching repo"
    echo "  repos cd <repo>     📂 pushd into matching repo (prints path when non-interactive)"
    echo "  repos resolve <r>   📍 Print absolute path to matching repo (GitHub search fallback)"
    echo "  repos claude [repo] 🤖 Open Claude Code via cc (tmux) in matching repo (current repo if omitted; alias: cc)"
    echo "  repos view [repo]   📂 Open GitHub Desktop in matching repo (current repo if omitted)"
    echo "  repos work [repo]   📚 Open VS Code and GitHub Desktop in matching repo (current repo if omitted)"
    echo "  repos cache         📦 Rebuild repo cache and refresh archived/readonly list"
    echo "  repos help          📖 Show this help message"
    echo ""
    echo "ls flags:"
    echo "  -r, --readonly      Only archived/readonly repos"
    echo "  -m, --modified      Only repos with uncommitted changes"
    echo "  -a, --active        Only repos with work in progress"
    echo ""
    echo "Roots ($REPO_ROOTS, preferred: $REPO_PREFER):"
    echo "  Prefix a search with a root name to pick that copy, e.g. 'repos cc win:documents'"
    echo "  ⇄ in 'repos ls' marks a repo cloned in more than one root"
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

_repos_root_names() {
    local entry
    for entry in $REPO_ROOTS; do echo "${entry%%=*}"; done
}

_repos_root_path() {
    local entry
    for entry in $REPO_ROOTS; do
        [[ "${entry%%=*}" == "$1" ]] && { echo "${entry#*=}"; return 0; }
    done
    return 1
}

_repos_label() {
    local path="$1" entry root_path
    for entry in $REPO_ROOTS; do
        root_path="${entry#*=}"
        [[ "$path" == "$root_path"/* ]] && { echo "[${entry%%=*}] ${path#"$root_path/"}"; return; }
    done
    echo "$path"
}

_repos_term_without_root() {
    if [[ "$1" =~ ^([^:/]+):(.*)$ ]] && _repos_root_path "${BASH_REMATCH[1]}" >/dev/null; then
        echo "${BASH_REMATCH[2]}"
    else
        echo "$1"
    fi
}

_repos_matches() {
    local search="$1" root=""
    local term=$(_repos_term_without_root "$search")
    [[ "$term" != "$search" ]] && root="${search%%:*}"
    awk -F'\t' -v root="$root" -v s="$term" \
        '!/^#/ && NF >= 4 && (root == "" || $1 == root) && tolower($2) ~ tolower(s)' "$REPO_CACHE"
}

_repos_select() {
    local search="$1" prefer="${2:-$REPO_PREFER}"
    local matches
    matches=$(_repos_matches "$search")
    [[ -z "$matches" ]] && return 2

    local term=$(_repos_term_without_root "$search")
    local exact=$(awk -F'\t' -v s="$term" '{
        name = $2; sub(/.*\//, "", name)
        if (tolower($2) == tolower(s) || tolower(name) == tolower(s)) print $3
    }' <<< "$matches" | sort -u)
    if [[ -n "$exact" && $(wc -l <<< "$exact") -eq 1 ]]; then
        matches=$(awk -F'\t' -v id="$exact" '$3 == id' <<< "$matches")
    fi

    if [[ $(cut -f3 <<< "$matches" | sort -u | wc -l) -gt 1 ]]; then
        echo "❌ Multiple repos found for '$search':" >&2
        awk -F'\t' '{ print "   [" $1 "] " $4 }' <<< "$matches" >&2
        return 1
    fi

    local root chosen=""
    for root in "$prefer" $(_repos_root_names); do
        chosen=$(awk -F'\t' -v r="$root" '$1 == r' <<< "$matches")
        [[ -n "$chosen" ]] && break
    done

    if [[ $(wc -l <<< "$chosen") -gt 1 ]]; then
        echo "❌ Multiple copies of '$search' in $root:" >&2
        cut -f4 <<< "$chosen" | sed 's/^/   /' >&2
        return 1
    fi

    local others=$(awk -F'\t' -v r="$root" '$1 != r { print "   [" $1 "] " $4 }' <<< "$matches")
    if [[ -n "$others" ]]; then
        echo "⚠️  $(wc -l <<< "$matches") copies of $(cut -f3 <<< "$chosen"); using [$root] $(cut -f4 <<< "$chosen"), also:" >&2
        printf '%s\n' "$others" >&2
    fi
    echo "$chosen"
}

# Absolute path of the matching repo, or the current git repo when no term (or ".") is given
_repos_target_path() {
    local search="$1" prefer="${2:-$REPO_PREFER}"
    if [[ -n "$search" && "$search" != "." ]]; then
        local entry rc
        entry=$(_repos_select "$search" "$prefer"); rc=$?
        [[ $rc -eq 2 ]] && echo "❌ No repos found for '$search'" >&2
        [[ $rc -ne 0 ]] && return 1
        cut -f4 <<< "$entry"
        return
    fi

    if ! git </dev/null rev-parse --show-toplevel 2>/dev/null; then
        echo "❌ Error: not inside a git repo; pass a repo search term" >&2
        return 1
    fi
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

# Record owner/name ids of GitHub-archived repos in $REPO_READONLY, querying gh per owner
_repos_readonly_refresh() {
    if ! command -v gh >/dev/null 2>&1; then
        echo "⚠️  gh not found; skipping archived/readonly detection" >&2
        return 0
    fi

    echo "🔍 Checking GitHub for archived repos..."

    local -A ids=()
    local -A owners=()
    local id
    while IFS= read -r id; do
        [[ "$id" == */* ]] || continue
        ids["$id"]=1
        owners["${id%%/*}"]=1
    done < <(cut -f3 "$REPO_CACHE")

    local -A archived=()
    local owner line
    for owner in "${!owners[@]}"; do
        while IFS= read -r line; do
            [[ -n "$line" ]] && archived["$line"]=1
        done < <(gh repo list "$owner" --archived --limit 1000 --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null)
    done

    local tmpfile=$(mktemp)
    for id in "${!ids[@]}"; do
        [[ -n "${archived[$id]:-}" ]] && echo "$id"
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

    local entry rc
    entry=$(_repos_select "$search"); rc=$?
    if [[ $rc -eq 2 ]]; then
        _repos_github_fallback "$search"
        return $?
    fi
    [[ $rc -ne 0 ]] && return 1

    local id=$(cut -f3 <<< "$entry")
    _repos_is_readonly "$id" && echo "🔒 $id is readonly (archived on GitHub)" >&2
    cut -f4 <<< "$entry"
}

# Absolute paths of every matching copy (no emoji, no state lookup); whole cache when no term
_repos_find_cmd() {
    _repos_matches "$1" | cut -f4
}

# "root:relpath<TAB>abspath" per cached repo, for fzf pickers that preview the path
_repos_picker_list() {
    awk -F'\t' '!/^#/ && NF >= 4 { print $1 ":" $2 "\t" $4 }' "$REPO_CACHE"
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
        modified_set=$(jq -r '.repos[] | select(.dirty_files > 0) | .abs_path' "$REPO_STATUS" 2>/dev/null)
        active_set=$(jq -r '.repos[].abs_path' "$REPO_STATUS" 2>/dev/null)
    fi
    local duplicated_ids=$(cut -f3 "$REPO_CACHE" | sort | uniq -d)

    local root repo id abs
    while IFS=$'\t' read -r root repo id abs; do
        _repos_should_skip "$repo" && continue

        local readonly=false modified=false active=false
        _repos_is_readonly "$id" && readonly=true
        grep -qxF "$abs" <<< "$modified_set" && modified=true
        grep -qxF "$abs" <<< "$active_set" && active=true

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
        local copies=""
        grep -qxF "$id" <<< "$duplicated_ids" && copies=" ⇄"
        echo "$emoji [$root] $repo$copies"
    done < <(if [[ -n "$search" ]]; then _repos_matches "$search"; else cat "$REPO_CACHE"; fi) | sort -k3
}

_repos_id() {
    local url name
    url=$(git -C "$1" </dev/null config --get remote.origin.url 2>/dev/null)
    if [[ -n "$url" ]] && name=$(_repos_owner_repo "$url"); then
        echo "$name"
    else
        basename "$1"
    fi
}

_repos_cache_build() {
    mkdir -p "$(dirname "$REPO_CACHE")"
    local tmpfile=$(mktemp)
    local root root_path repo
    for root in $(_repos_root_names); do
        root_path=$(_repos_root_path "$root")
        if [[ ! -d "$root_path" ]]; then
            echo "⚠️  Root $root ($root_path) not found; skipping" >&2
            continue
        fi
        echo "🔍 Scanning $root ($root_path)..."
        while IFS= read -r repo; do
            _repos_match_ignore "$repo" && continue
            printf '%s\t%s\t%s\t%s\n' "$root" "$repo" "$(_repos_id "$root_path/$repo")" "$root_path/$repo"
        done < <(find_git_repos "$root_path" 4) >> "$tmpfile"
    done
    mv "$tmpfile" "$REPO_CACHE"

    local count=$(wc -l < "$REPO_CACHE")
    local copies=$(cut -f3 "$REPO_CACHE" | sort | uniq -d | wc -l)
    echo "✅ Found $count repos ($copies with copies in several roots), cache updated"
}

_repos_cache() {
    _repos_cache_build
    _repos_readonly_refresh
}

_repos_fan_out() {
    local max_jobs="$1" workdir="$2" worker="$3"
    shift 3

    # Subshell contains job-control notifications so they never reach the interactive shell
    (
        idx=0
        while IFS=$'\t' read -r root repo id repo_path; do
            _repos_should_skip "$repo" && continue
            [[ ! -d "$repo_path/.git" ]] && continue

            idx=$((idx + 1))
            { "$worker" "$repo_path" "$repo" "$root" "$workdir/$idx" "$@"; : > "$workdir/$idx.done"; } &

            while (( $(jobs -r -p | wc -l) >= max_jobs )); do wait -n; done
            printf '\r\e[K⏳ %s/%s repos...' "$(ls "$workdir"/*.done 2>/dev/null | wc -l)" "$idx"
        done < "$REPO_CACHE"
        wait
    )
    printf '\r\e[K'
}

_repos_fetch_worker() {
    local repo_path="$1" repo="[$3] $2" out="$4"

    cd "$repo_path" 2>/dev/null || return

    # Fetch (try main, then master)
    local fetch_branch="main"
    if ! _repos_git </dev/null fetch origin main 2>/dev/null; then
        fetch_branch="master"
        _repos_git </dev/null fetch origin master 2>/dev/null || return
    fi

    local commits=$(_repos_git </dev/null rev-list --count HEAD..origin/$fetch_branch 2>/dev/null || echo "0")
    [[ "$commits" -eq 0 ]] && return

    local branch=$(_repos_git </dev/null branch --show-current)
    local is_dirty=$(_repos_git </dev/null status --porcelain)

    if [[ "$branch" == "main" || "$branch" == "master" ]] && [[ -z "$is_dirty" ]]; then
        _repos_git </dev/null pull origin "$branch" >& /dev/null
        { echo "📁 $repo"; echo "   📥 $commits new commit(s)"; echo "   ✅ Pulled"; } > "$out.out"
    else
        { echo "📁 $repo"; echo "   📥 $commits new commit(s)"; } > "$out.out"
        # Dirty takes priority over branch mismatch
        if [[ -n "$is_dirty" ]]; then
            printf 'DIRTY\t%s\n' "$repo" >> "$out.cat"
        else
            printf 'BRANCH\t%s (%s)\n' "$repo" "$branch" >> "$out.cat"
        fi
    fi

    return 0
}

_repos_fetch() {
    echo "🔄 Fetching repos..."
    echo ""

    # Each repo is I/O and network-bound, so fan them out concurrently
    local workdir=$(mktemp -d)
    _repos_fan_out "${REPOS_FETCH_JOBS:-16}" "$workdir" _repos_fetch_worker

    local f
    while IFS= read -r f; do cat "$f"; done < <(ls "$workdir"/*.out 2>/dev/null | sort -V)

    local all_cat=$(cat "$workdir"/*.cat 2>/dev/null)
    rm -rf "$workdir"

    local -a skipped_dirty skipped_branch
    mapfile -t skipped_dirty  < <(printf '%s\n' "$all_cat" | awk -F'\t' '$1=="DIRTY"{print $2}'  | sort)
    mapfile -t skipped_branch < <(printf '%s\n' "$all_cat" | awk -F'\t' '$1=="BRANCH"{print $2}' | sort)

    local total_skipped=$(( ${#skipped_dirty[@]} + ${#skipped_branch[@]} ))
    if [[ $total_skipped -gt 0 ]]; then
        echo ""
        echo "⏭️  Skipped pull for $total_skipped repo(s):"

        if [[ ${#skipped_dirty[@]} -gt 0 ]]; then
            echo ""
            echo "   Uncommitted changes:"
            printf '      %s\n' "${skipped_dirty[@]}"
        fi

        if [[ ${#skipped_branch[@]} -gt 0 ]]; then
            echo ""
            echo "   Different branch:"
            printf '      %s\n' "${skipped_branch[@]}"
        fi
    fi
}

# Emit the unmerged ('+') commit SHAs of a ref relative to the default branch on origin
_repos_unmerged_shas() {
    local default_branch="$1" ref="$2"
    _repos_git </dev/null cherry "origin/$default_branch" "$ref" 2>/dev/null | awk '/^\+/ { print $2 }'
}

# Unknown local identity is treated as "mine" so nothing gets auto-deleted
_repos_authored_by_me() {
    local me
    me=$(_repos_git </dev/null config user.email 2>/dev/null)
    [[ -z "$me" ]] && return 0
    [[ $# -eq 0 ]] && return 1
    _repos_git </dev/null show -s --format='%ae' "$@" 2>/dev/null | grep -qxF "$me"
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
    [[ -z "$(_repos_git </dev/null rev-list "$1" --not --remotes 2>/dev/null)" ]]
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

    if _repos_git </dev/null branch -D "$branch" >& /dev/null; then
        echo "   ✅ Deleted: $branch ($reason)"
        return 0
    fi
    echo "   ❌ Failed to delete: $branch"
    return 1
}

_repos_clear_worker() {
    local repo_path="$1" repo="[$3] $2" out="$4" all="$5"

    cd "$repo_path" 2>/dev/null || return
    local default_branch=$(_git_get_default_branch)
    [[ -z "$default_branch" ]] && return

    local current_branch=$(_repos_git </dev/null branch --show-current 2>/dev/null)
    local deleted=0 body=""

    if [[ "$current_branch" != "$default_branch" ]]; then
        local status=$(_repos_git </dev/null status --porcelain 2>/dev/null)

        # git status already lists untracked files; pull stale (>6h) swap files from its output
        if [[ -n "$status" ]]; then
            local now=$(date +%s) rel mtime
            while IFS= read -r rel; do
                [[ "$rel" == *.swp ]] || continue
                mtime=$(stat -c %Y "$rel" 2>/dev/null) || continue
                (( now - mtime > 21600 )) || continue
                rm -f "$rel" 2>/dev/null || continue
                body+="   🧹 Removed stale swap file: $rel"$'\n'
            done < <(printf '%s\n' "$status" | awk '/^\?\? / { print substr($0, 4) }')
        fi

        # Tracked changes block a switch; untracked cruft does not
        local tracked_dirty=$(printf '%s\n' "$status" | grep -vE '^(\?\?|[[:space:]]*$)')

        if [[ -n "$tracked_dirty" ]]; then
            body+="   ⏭️  Kept: $current_branch (uncommitted changes)"$'\n'
        elif _repos_own_unmerged "$default_branch" HEAD; then
            body+="   ⏭️  Kept: $current_branch (unmerged commits of yours)"$'\n'
        elif _repos_git </dev/null checkout "$default_branch" >& /dev/null; then
            body+="   🔄 Switched: $current_branch → $default_branch"$'\n'
            local o rc
            o=$(_repos_clear_branch "$default_branch" "$current_branch"); rc=$?
            [[ -n "$o" ]] && body+="$o"$'\n'
            [[ $rc -eq 0 ]] && deleted=$((deleted + 1))
            _repos_git </dev/null pull >& /dev/null
        else
            body+="   ❌ Failed to switch: $current_branch → $default_branch"$'\n'
        fi
    elif [[ "$all" != true ]]; then
        return
    fi

    if [[ "$all" == true ]]; then
        local branches=$(_repos_git </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            local o rc
            o=$(_repos_clear_branch "$default_branch" "$branch"); rc=$?
            [[ -n "$o" ]] && body+="$o"$'\n'
            [[ $rc -eq 0 ]] && deleted=$((deleted + 1))
        done <<< "$branches"
    fi

    [[ -n "$body" ]] && { echo "📁 $repo"; printf '%s' "$body"; } > "$out.out"
    echo "$deleted" > "$out.count"
    return 0
}

_repos_clear() {
    local all=false
    [[ "${1:-}" == "--all" ]] && all=true

    if [[ "$all" == true ]]; then
        echo "🗑️  Clearing all branches with no unmerged work of yours..."
    else
        echo "🗑️  Clearing the current branch where it holds no unmerged work of yours..."
    fi
    echo ""

    # Each repo mutates only its own working tree, so it is safe to fan them out concurrently
    local workdir=$(mktemp -d)
    _repos_fan_out "${REPOS_CLEAR_JOBS:-16}" "$workdir" _repos_clear_worker "$all"

    local f
    while IFS= read -r f; do cat "$f"; done < <(ls "$workdir"/*.out 2>/dev/null | sort -V)

    local total_branches=0 c
    while read -r c; do total_branches=$((total_branches + c)); done < <(cat "$workdir"/*.count 2>/dev/null)
    rm -rf "$workdir"

    if [[ $total_branches -gt 0 ]]; then
        echo "✅ Deleted $total_branches branch(es)"
    else
        echo "✅ Nothing to clear"
    fi
}

_repos_confirm() {
    local answer
    read -r -p "$1 [y/N] " answer || { echo ""; return 1; }
    [[ "$answer" =~ ^[Yy]$ ]]
}

# Discard all local changes in one repo, return to an up-to-date default branch and drop the old branch
_repos_reset_one() {
    local repo_path
    repo_path=$(_repos_target_path "$1") || return 1
    cd "$repo_path" || return 1

    local default_branch
    if ! default_branch=$(_git_get_default_branch); then
        echo "❌ No main/master branch in $(_repos_label "$repo_path")" >&2
        return 1
    fi

    echo "♻️  Resetting $(_repos_label "$repo_path")..."
    _repos_git </dev/null fetch -q origin "$default_branch" 2>/dev/null || echo "   ⚠️  Fetch failed; continuing with local state"

    _repos_git </dev/null reset -q --hard HEAD
    _repos_git </dev/null clean -q -fd
    echo "   🧹 Discarded uncommitted changes"

    local branch
    branch=$(_repos_git </dev/null branch --show-current)

    if [[ "$branch" != "$default_branch" ]]; then
        if ! _repos_git </dev/null checkout -q "$default_branch" 2>/dev/null; then
            echo "   ❌ Failed to switch: ${branch:-detached HEAD} → $default_branch" >&2
            return 1
        fi
        echo "   🔄 Switched: ${branch:-detached HEAD} → $default_branch"
    fi

    if _repos_git </dev/null pull -q --ff-only origin "$default_branch" >& /dev/null; then
        echo "   📥 Pulled $default_branch"
    else
        echo "   ⚠️  Pull failed on $default_branch"
    fi

    [[ -z "$branch" || "$branch" == "$default_branch" ]] && return 0

    local -a unmerged
    mapfile -t unmerged < <(_repos_unmerged_shas "$default_branch" "$branch")
    if [[ ${#unmerged[@]} -gt 0 ]]; then
        _repos_git </dev/null log --oneline --no-walk "${unmerged[@]}" | sed 's/^/      /'
        if ! _repos_confirm "   ⚠️  $branch has ${#unmerged[@]} unmerged commit(s). Delete it?"; then
            echo "   ⏭️  Kept: $branch"
            return 0
        fi
    fi

    if _repos_git </dev/null branch -q -D "$branch" >& /dev/null; then
        echo "   ✅ Deleted: $branch"
    else
        echo "   ❌ Failed to delete: $branch" >&2
        return 1
    fi
}

_repos_reset() {
    if [[ $# -gt 0 ]]; then
        (_repos_reset_one "$1")
        return
    fi
    _repos_fetch; echo ""; _repos_clear; echo ""; _repos_status
}

_repos_wip_record() {
    local records_file="$1" repo_name="$2" repo_rel="$3" root="$4" repo_path="$5" branch="$6" \
          default_branch="$7" dirty_count="$8" unmerged="$9" merged="${10}"
    command -v jq >/dev/null 2>&1 || return 0

    local commits_raw=""
    if [[ "$branch" != "$default_branch" ]]; then
        commits_raw=$(_repos_git </dev/null log -n 50 --format='%h%x1f%ad%x1f%s' \
            --date=short "origin/$default_branch..HEAD" 2>/dev/null)
    fi

    local changed_raw=$(_repos_git </dev/null status --porcelain 2>/dev/null \
        | sed -e 's/^...//' -e 's/^.* -> //')
    local last_activity=$(_repos_git </dev/null log -1 --format=%ad --date=short HEAD 2>/dev/null)

    jq -c -n \
        --arg name "$repo_name" \
        --arg path "$repo_rel" \
        --arg root "$root" \
        --arg abs_path "$repo_path" \
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
            root: $root,
            abs_path: $abs_path,
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

_repos_status_worker() {
    local repo_path="$1" repo="$2" root="$3" out="$4" all="$5"

    cd "$repo_path" 2>/dev/null || return
    [ -f "bash.exe.stackdump" ] && rm bash.exe.stackdump

    local default_branch=$(_git_get_default_branch)
    [[ -z "$default_branch" ]] && return

    local current_branch=$(_repos_git </dev/null branch --show-current 2>/dev/null)
    local is_dirty=$(_repos_git </dev/null status --porcelain 2>/dev/null)
    local repo_name=$(basename "$repo")
    local label="[$root] $repo_name"
    local dirty_count=0
    [[ -n "$is_dirty" ]] && dirty_count=$(echo "$is_dirty" | wc -l | tr -d ' ')

    local is_wip=false unmerged=0 merged=false
    if [[ "$current_branch" != "$default_branch" ]]; then
        is_wip=true
        # git cherry detects squash/rebase-merged commits
        local cherry=$(_repos_git </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
        unmerged=$(echo "$cherry" | grep -c '^+' || true)
        local dirty_note=""
        [[ "$dirty_count" -gt 0 ]] && dirty_note=" 📝 $dirty_count file(s)"
        if [[ "$unmerged" -eq 0 ]]; then
            merged=true
            printf 'OFF\t📁 %s (%s) ✅ merged%s\n' "$label" "$current_branch" "$dirty_note" >> "$out.cat"
        else
            printf 'OFF\t📁 %s (%s) ⚠️  %s unmerged commit(s)%s\n' "$label" "$current_branch" "$unmerged" "$dirty_note" >> "$out.cat"
        fi
    fi

    if [[ -n "$is_dirty" ]] && [[ "$current_branch" == "$default_branch" ]]; then
        is_wip=true
        printf 'DIRTY\t📁 %s (%s, %s file(s))\n' "$label" "$current_branch" "$dirty_count" >> "$out.cat"
    fi

    [[ "$is_wip" == true ]] && _repos_wip_record "$out.json" "$repo_name" "$repo" "$root" "$repo_path" \
        "$current_branch" "$default_branch" "$dirty_count" "$unmerged" "$merged"

    if [[ "$all" == true ]]; then
        local branches=$(_repos_git </dev/null branch 2>/dev/null | grep -v -E '^\*|^\s*(main|master)\s*$' | sed 's/^[ \t]*//')
        local merged_count=0
        while IFS= read -r branch; do
            [[ -z "$branch" ]] && continue
            local cherry=$(_repos_git </dev/null cherry "origin/$default_branch" "$branch" 2>/dev/null)
            local has_unmerged=$(echo "$cherry" | grep -c '^+' || true)
            [[ "$has_unmerged" -eq 0 ]] && ((merged_count++))
        done <<< "$branches"
        [[ $merged_count -gt 0 ]] && printf 'MERGED\t📁 %s (%s branch(es))\n' "$label" "$merged_count" >> "$out.cat"
    fi

    return 0
}

_repos_status() {
    local all=false
    [[ "${1:-}" == "--all" ]] && all=true

    echo "🔍 Checking repo status..."
    echo ""

    # Each repo is I/O-bound on the WSL↔Windows boundary, so fan them out concurrently
    local workdir=$(mktemp -d)
    _repos_fan_out "${REPOS_STATUS_JOBS:-16}" "$workdir" _repos_status_worker "$all"

    local records_file=$(mktemp)
    cat "$workdir"/*.json > "$records_file" 2>/dev/null

    if command -v jq >/dev/null 2>&1; then
        local roots_json=$(for root in $(_repos_root_names); do
            jq -n --arg k "$root" --arg v "$(_repos_root_path "$root")" '{($k): $v}'
        done | jq -s 'add // {}')
        mkdir -p "$(dirname "$REPO_STATUS")"
        jq -s --arg generated "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson roots "$roots_json" \
            '{generated: $generated, roots: $roots, repos: .}' \
            "$records_file" > "$REPO_STATUS" 2>/dev/null \
            && echo "💾 Wrote WIP snapshot to $REPO_STATUS"
    fi
    rm -f "$records_file"

    local all_cat=$(cat "$workdir"/*.cat 2>/dev/null)
    rm -rf "$workdir"

    local -a off_main dirty has_merged
    mapfile -t off_main   < <(printf '%s\n' "$all_cat" | awk -F'\t' '$1=="OFF"{print $2}'    | sort)
    mapfile -t dirty      < <(printf '%s\n' "$all_cat" | awk -F'\t' '$1=="DIRTY"{print $2}'  | sort)
    mapfile -t has_merged < <(printf '%s\n' "$all_cat" | awk -F'\t' '$1=="MERGED"{print $2}' | sort)

    if [[ ${#off_main[@]} -gt 0 ]]; then
        echo "🌿 Not on main (${#off_main[@]}):"
        printf '   %s\n' "${off_main[@]}"
        echo ""
    fi

    if [[ ${#dirty[@]} -gt 0 ]]; then
        echo "📝 Uncommitted changes (${#dirty[@]}):"
        printf '   %s\n' "${dirty[@]}"
        echo ""
    fi

    if [[ ${#has_merged[@]} -gt 0 ]]; then
        echo "🧹 Merged branches to clear (${#has_merged[@]}) — run 'repos clear --all':"
        printf '   %s\n' "${has_merged[@]}"
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

    local root rel id repo_path
    while IFS=$'\t' read -r root rel id repo_path; do
        _repos_should_skip "$rel" && continue
        [[ ! -d "$repo_path/.git" ]] && continue
        local repo="[$root] $rel"

        pushd "$repo_path" >& /dev/null

        local default_branch=$(_git_get_default_branch)
        if [[ -z "$default_branch" ]]; then
            popd >& /dev/null
            continue
        fi

        local current_branch=$(_repos_git </dev/null branch --show-current 2>/dev/null)
        if [[ "$current_branch" == "$default_branch" ]]; then
            popd >& /dev/null
            continue
        fi

        local is_dirty=$(_repos_git </dev/null status --porcelain 2>/dev/null)
        if [[ -n "$is_dirty" ]]; then
            skipped_dirty+=("$repo ($current_branch)")
            popd >& /dev/null
            continue
        fi

        local cherry=$(_repos_git </dev/null cherry "origin/$default_branch" HEAD 2>/dev/null)
        local unmerged=$(echo "$cherry" | grep -c '^+' || true)
        if [[ "$unmerged" -gt 0 ]]; then
            skipped_unmerged+=("$repo ($current_branch, $unmerged commit(s))")
            popd >& /dev/null
            continue
        fi

        if _repos_git </dev/null checkout "$default_branch" >& /dev/null; then
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

_repos_is_windows_path() {
    [[ "$1" == /mnt/[a-z]/* ]]
}

_repos_edit() {
    local repo_path
    repo_path=$(_repos_target_path "$1" "${2:-$REPO_PREFER}") || return 1

    echo "🚀 Opening VS Code in $(_repos_label "$repo_path")..."
    if _repos_is_windows_path "$repo_path"; then
        (cd "$repo_path" && cmd.exe /c code .)
    else
        code "$repo_path"
    fi
}

_repos_solutions() {
    find "$1" -maxdepth "$2" -not -path '*/.git/*' \( -name '*.sln' -o -name '*.slnx' \) 2>/dev/null | sort
}

_repos_devenv() {
    local vswhere="/mnt/c/Program Files (x86)/Microsoft Visual Studio/Installer/vswhere.exe"
    [[ -f "$vswhere" ]] || return 1

    local devenv=$("$vswhere" -latest -prerelease -property productPath 2>/dev/null | tr -d '\r')
    [[ -n "$devenv" ]] || return 1
    echo "$devenv"
}

_repos_ide() {
    local repo_path
    repo_path=$(_repos_target_path "$1" "$REPO_PREFER_WINDOWS_APPS") || return 1

    local repo=$(_repos_label "$repo_path")
    local -a solutions
    mapfile -t solutions < <(_repos_solutions "$repo_path" 1)
    [[ ${#solutions[@]} -eq 0 ]] && mapfile -t solutions < <(_repos_solutions "$repo_path" 3)

    if [[ ${#solutions[@]} -eq 0 ]]; then
        echo "❌ No solution file found in $repo" >&2
        return 1
    elif [[ ${#solutions[@]} -gt 1 ]]; then
        echo "❌ Multiple solution files found in $repo:" >&2
        printf '   %s\n' "${solutions[@]#"$repo_path/"}" >&2
        return 1
    fi

    local -a launch=(cmd.exe /c start "")
    local devenv
    devenv=$(_repos_devenv) && launch+=("$devenv")
    launch+=("$(wslpath -w "${solutions[0]}")")

    echo "🏗️  Opening $(basename "${solutions[0]}") in Visual Studio..."
    (cd /mnt/c && "${launch[@]}" >/dev/null 2>&1 &)
}

_repos_view() {
    local repo_path
    repo_path=$(_repos_target_path "$1" "$REPO_PREFER_WINDOWS_APPS") || return 1

    echo "📁 Opening $(_repos_label "$repo_path") in GitHub Desktop"
    # cmd.exe cannot start in a \\wsl$ UNC directory, so launch from a Windows drive and pass the path
    (cd /mnt/c && cmd.exe /c github "$(wslpath -w "$repo_path")")
}

_repos_cmd() {
    local repo_path
    repo_path=$(_repos_target_path "$1") || return 1

    echo "💻 Opening CMD in $(_repos_label "$repo_path")..."
    (cd /mnt/c && cmd.exe /c start wsl.exe --cd "$repo_path")
}

_repos_cd() {
    local search="$1" entry rc
    entry=$(_repos_select "$search"); rc=$?
    [[ $rc -eq 2 ]] && echo "❌ No repos found for '$search'" >&2
    [[ $rc -ne 0 ]] && return 1

    local root repo id repo_path
    IFS=$'\t' read -r root repo id repo_path <<< "$entry"
    if _repos_is_readonly "$id"; then
        echo "🔒 [$root] $repo (readonly — archived on GitHub)"
    else
        echo "📂 [$root] $repo"
    fi
    pushd "$repo_path" > /dev/null
}

# Delegates to the interactive cc function, which owns tmux session handling
_repos_claude() {
    if ! declare -F cc >/dev/null; then
        echo "❌ Error: cc not loaded; run 'repos claude' from an interactive shell" >&2
        return 1
    fi

    local repo_path
    repo_path=$(_repos_target_path "$1") || return 1

    echo "🤖 Opening Claude Code in $(_repos_label "$repo_path")..."
    (cd "$repo_path" && cc)
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
        work)           _repos_view "$2" ; _repos_edit "$2" "$REPO_PREFER_WINDOWS_APPS" ;;
        fetch)          _repos_fetch ;;
        reset)          shift; _repos_reset "$@" ;;
        cache)          _repos_cache ;;
        clear)          shift; _repos_clear "$@" ;;
        status)         shift; _repos_status "$@" ;;
        ls)             shift; _repos_ls "$@" ;;
        find)           _repos_find_cmd "$2" ;;
        main)           _repos_main ;;
        edit|code)      _repos_edit "$2" ;;
        ide|vs)         _repos_ide "$2" ;;
        cmd)            _repos_cmd "$2" ;;
        cd|resolve)     _repos_resolve "$2" ;;
        claude|cc)      _repos_claude "$2" ;;
        *)              _repos_help ;;
    esac
}

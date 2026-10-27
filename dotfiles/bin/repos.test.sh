#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"

PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export REPO_HOME="$WORK/home"
export WSL_ROOT="$WORK/wsl"
export REPO_ROOTS="wsl=$WSL_ROOT win=$REPO_HOME"
export REPO_PREFER=wsl
export REPO_PREFER_WINDOWS_APPS=win
export REPO_CACHE="$WORK/repos-cache.lst"
export REPO_STATUS="$WORK/repos-status.json"
export REPO_READONLY="$WORK/repos-readonly.lst"
export REPO_IGNORE="$WORK/.reposignore"
export GIT_CONFIG_GLOBAL="$WORK/gitconfig"
export GIT_CONFIG_NOSYSTEM=1

git config --global user.email "me@example.com"
git config --global user.name "Me"
git config --global init.defaultBranch main
git config --global advice.detachedHead false

source "$SELF_DIR/../lib/repos-core.bash"

check() {  # check <name> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       expected: %q\n       actual:   %q\n' "$1" "$2" "$3"
    fi
}

contains() {  # contains <name> <needle> <haystack>
    if [[ "$3" == *"$2"* ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       %q not found in: %q\n' "$1" "$2" "$3"
    fi
}

# Fresh origin + clone at $REPO_HOME/$1, with one commit on main
make_repo() {
    local name="$1"
    rm -rf "$WORK/origin-$name.git" "$REPO_HOME/$name"
    git init -q --bare "$WORK/origin-$name.git"
    git clone -q "$WORK/origin-$name.git" "$REPO_HOME/$name" 2>/dev/null
    (
        cd "$REPO_HOME/$name"
        echo base > base.txt
        git add base.txt
        git commit -q -m base
        git push -q origin main 2>/dev/null
    )
    _repos_cache_build >/dev/null
}

# Second clone of an existing origin at $WSL_ROOT/$2 (defaults to the same name)
clone_into_wsl() {
    local name="$1" rel="${2:-$1}"
    git clone -q "$WORK/origin-$name.git" "$WSL_ROOT/$rel" 2>/dev/null
    _repos_cache_build >/dev/null
}

# Push a commit to origin/main from a second clone so the local clone is behind
advance_origin() {
    local name="$1" other="$WORK/other-$1"
    rm -rf "$other"
    git clone -q "$WORK/origin-$name.git" "$other" 2>/dev/null
    (cd "$other" && echo upstream > upstream.txt && git add . && git commit -q -m upstream && git push -q origin main 2>/dev/null)
}

branch_of() { git -C "$REPO_HOME/$1" branch --show-current; }
has_branch() { git -C "$REPO_HOME/$1" show-ref --verify --quiet "refs/heads/$2" && echo yes || echo no; }
porcelain() { git -C "$REPO_HOME/$1" status --porcelain; }

mkdir -p "$REPO_HOME" "$WSL_ROOT"
: > "$REPO_CACHE"

echo "reset . discards uncommitted changes on main and pulls"
make_repo alpha
advance_origin alpha
(cd "$REPO_HOME/alpha" && echo dirty >> base.txt && echo junk > untracked.txt)
out=$(cd "$REPO_HOME/alpha" && _repos_dispatch reset . </dev/null 2>&1)
check "working tree clean" "" "$(porcelain alpha)"
check "on main" "main" "$(branch_of alpha)"
check "pulled upstream commit" "yes" "$([[ -f "$REPO_HOME/alpha/upstream.txt" ]] && echo yes || echo no)"

echo "reset . on a merged branch switches to main, pulls and deletes it"
make_repo beta
(cd "$REPO_HOME/beta" && git checkout -q -b feature && echo wip > wip.txt)
advance_origin beta
out=$(cd "$REPO_HOME/beta" && _repos_dispatch reset . </dev/null 2>&1)
check "on main" "main" "$(branch_of beta)"
check "branch deleted" "no" "$(has_branch beta feature)"
check "working tree clean" "" "$(porcelain beta)"
check "pulled upstream commit" "yes" "$([[ -f "$REPO_HOME/beta/upstream.txt" ]] && echo yes || echo no)"

echo "reset . with unmerged commits deletes the branch when confirmed"
make_repo gamma
(cd "$REPO_HOME/gamma" && git checkout -q -b feature && echo c > c.txt && git add . && git commit -q -m unmerged)
out=$(cd "$REPO_HOME/gamma" && _repos_dispatch reset . <<< "y" 2>&1)
contains "prompts about unmerged commits" "unmerged" "$out"
check "on main" "main" "$(branch_of gamma)"
check "branch deleted" "no" "$(has_branch gamma feature)"

echo "reset . with unmerged commits keeps the branch when declined"
make_repo delta
(cd "$REPO_HOME/delta" && git checkout -q -b feature && echo c > c.txt && git add . && git commit -q -m unmerged)
out=$(cd "$REPO_HOME/delta" && _repos_dispatch reset . <<< "n" 2>&1)
check "on main" "main" "$(branch_of delta)"
check "branch kept" "yes" "$(has_branch delta feature)"
contains "reports branch kept" "Kept" "$out"

echo "reset . with unmerged commits keeps the branch with no answer"
make_repo epsilon
(cd "$REPO_HOME/epsilon" && git checkout -q -b feature && echo c > c.txt && git add . && git commit -q -m unmerged)
out=$(cd "$REPO_HOME/epsilon" && _repos_dispatch reset . </dev/null 2>&1)
check "branch kept" "yes" "$(has_branch epsilon feature)"

echo "reset <term> targets the matching repo from elsewhere"
make_repo zeta-service
(cd "$REPO_HOME/zeta-service" && git checkout -q -b feature && echo dirty >> base.txt)
out=$(cd "$WORK" && _repos_dispatch reset zeta </dev/null 2>&1)
check "on main" "main" "$(branch_of zeta-service)"
check "branch deleted" "no" "$(has_branch zeta-service feature)"
check "working tree clean" "" "$(porcelain zeta-service)"

echo "reset . outside a git repo fails"
out=$(cd "$WORK" && _repos_dispatch reset . </dev/null 2>&1); rc=$?
check "non-zero exit" "1" "$rc"
contains "explains" "not inside a git repo" "$out"

echo "reset <term> with no match fails"
out=$(cd "$WORK" && _repos_dispatch reset nomatch </dev/null 2>&1); rc=$?
check "non-zero exit" "1" "$rc"

echo "cache indexes every root and links copies of the same repo"
make_repo omega
clone_into_wsl omega
make_repo omega-barrels
mkdir -p "$REPO_HOME/nested"
make_repo nested/theta
clone_into_wsl nested/theta theta
check "win copy cached" "1" "$(awk -F'\t' -v p="$REPO_HOME/omega" '$1 == "win" && $4 == p' "$REPO_CACHE" | wc -l)"
check "wsl copy cached" "1" "$(awk -F'\t' -v p="$WSL_ROOT/omega" '$1 == "wsl" && $4 == p' "$REPO_CACHE" | wc -l)"
check "copies share an id" "1" "$(awk -F'\t' '$2 == "omega"' "$REPO_CACHE" | cut -f3 | sort -u | wc -l)"

echo "resolve prefers the wsl copy and warns about the other"
out=$(_repos_dispatch resolve omega 2>"$WORK/err"); err=$(cat "$WORK/err")
check "wsl path" "$WSL_ROOT/omega" "$out"
contains "warns about win copy" "[win] $REPO_HOME/omega" "$err"

echo "resolve matches copies at different relative paths"
out=$(_repos_dispatch resolve theta 2>/dev/null)
check "wsl path" "$WSL_ROOT/theta" "$out"

echo "resolve with a root prefix picks that copy without warning"
out=$(_repos_dispatch resolve win:omega 2>"$WORK/err")
check "win path" "$REPO_HOME/omega" "$out"
check "no warning" "" "$(cat "$WORK/err")"

echo "Windows apps prefer the win copy"
check "win path" "$REPO_HOME/omega" "$(_repos_target_path omega "$REPO_PREFER_WINDOWS_APPS" 2>/dev/null)"

echo "a term ambiguous between different repos fails"
out=$(_repos_dispatch resolve omeg 2>&1); rc=$?
check "non-zero exit" "1" "$rc"
contains "lists candidates" "omega-barrels" "$out"

echo "find prints absolute paths of every copy"
check "both copies" "$REPO_HOME/omega
$WSL_ROOT/omega" "$(_repos_dispatch find '^omega$' | sort)"

echo "ls tags the root and marks repos with several copies"
out=$(_repos_dispatch ls omega)
contains "wsl copy marked" "[wsl] omega ⇄" "$out"
contains "win copy marked" "[win] omega ⇄" "$out"
contains "single copy unmarked" "[win] omega-barrels"$'\n' "$out"$'\n'
check "sorted by name, copies together" "omega omega omega-barrels" "$(awk '{print $3}' <<< "$out" | paste -sd' ')"

echo "status reports each copy and records its root"
(cd "$WSL_ROOT/omega" && echo dirty >> base.txt)
(cd "$REPO_HOME/omega" && git checkout -q -b feature)
out=$(_repos_dispatch status 2>&1)
contains "dirty wsl copy" "[wsl] omega (main, 1 file(s))" "$out"
contains "win copy on branch" "[win] omega (feature)" "$out"
check "status json abs paths" "$REPO_HOME/omega
$WSL_ROOT/omega" "$(jq -r '.repos[] | select(.name == "omega") | .abs_path' "$REPO_STATUS" | sort)"
check "status json roots" "$WSL_ROOT" "$(jq -r '.roots.wsl' "$REPO_STATUS")"

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

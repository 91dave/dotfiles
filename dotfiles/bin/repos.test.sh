#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK="$(mktemp -d)"

PASS=0
FAIL=0

cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

export REPO_HOME="$WORK/home"
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
    echo "$name" >> "$REPO_CACHE"
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

mkdir -p "$REPO_HOME"
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

echo
echo "$PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]

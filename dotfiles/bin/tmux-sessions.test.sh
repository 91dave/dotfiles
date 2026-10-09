#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SELF_DIR/tmux-sessions"
SOCKET="tmux-sessions-test-$$"
SHIM="$(mktemp -d)"

PASS=0
FAIL=0

cleanup() {
    command tmux -L "$SOCKET" kill-server 2>/dev/null
    rm -rf "$SHIM"
}
trap cleanup EXIT

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

cat > "$SHIM/tmux" <<EOF
#!/bin/bash
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

tmux -f /dev/null new-session -d -s here -c "$SHIM" 'cat'
tmux new-window -d -t here: 'cat'
tmux new-session -d -s elsewhere 'cat'
tmux new-session -d -s view -t here

export TMUX="/tmp/fake,1,$(tmux display-message -p -t here '#{session_id}' | tr -d '$')"

echo "listing"

out="$("$SUT" --list)"
check "one row per session, views of a live session hidden" "elsewhere here" \
    "$(cut -f2 <<<"$out" | sort | paste -sd' ')"
contains "marks the session you are in" "● " "$(rg $'\there$' <<<"$out")"

echo "rows"

rows="$("$SUT" --rows)"
check "rows give the same sessions as the list" "$(cut -f2 <<<"$out")" "$(cut -f1 <<<"$rows")"
check "rows give raw fields: name, windows, directory, activity, mark" \
    "here	2	$SHIM	$(tmux display-message -p -t here '#{session_activity}')	●" \
    "$(rg '^here' <<<"$rows")"
check "an unattached session has no mark" "" "$(rg '^elsewhere' <<<"$rows" | cut -f5)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

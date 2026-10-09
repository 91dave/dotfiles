#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SELF_DIR/tmux-windows"
FIXTURES="$(mktemp -d)"
SOCKET="tmux-windows-test-$$"

PASS=0
FAIL=0

cleanup() {
    command tmux -L "$SOCKET" kill-server 2>/dev/null
    rm -rf "$FIXTURES"
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

lacks() {  # lacks <name> <needle> <haystack>
    if [[ "$3" != *"$2"* ]]; then
        PASS=$((PASS + 1))
        printf '  ok   %s\n' "$1"
    else
        FAIL=$((FAIL + 1))
        printf '  FAIL %s\n       %q unexpectedly found in: %q\n' "$1" "$2" "$3"
    fi
}

SHIM="$FIXTURES/shim"
mkdir -p "$SHIM"
cat > "$SHIM/tmux" <<EOF
#!/bin/bash
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"

tmux -f /dev/null new-session -d -s here -x 81 -y 20 -n editor 'cat'
tmux new-window -d -t here: -n logs 'cat'
tmux new-session -d -s elsewhere -n hidden 'cat'
tmux split-window -d -h -t here:editor 'cat'
tmux resize-pane -t here:editor.0 -x 40
tmux respawn-pane -k -t here:editor.0 "printf '\033[31mleft\033[0m-🧠⏱️-pane-text\n'; cat"

export TMUX="/tmp/fake,1,$(tmux display-message -p -t here '#{session_id}' | tr -d '$')"

echo "listing"

out="$("$SUT" --list)"
contains "lists windows in the current session" "editor" "$out"
contains "lists every window in the current session" "logs" "$out"
lacks "omits windows from other sessions" "hidden" "$out"
check "one row per window" "2" "$(wc -l <<<"$out" | tr -d ' ')"
contains "marks the active window" "● " "$(head -n1 <<<"$out")"
lacks "leaves inactive windows unmarked" "●" "$(tail -n1 <<<"$out")"
check "keys each row by window id" \
    "$(tmux display-message -p -t here:logs '#{window_id}')" "$(tail -n1 <<<"$out" | cut -f2)"

rows="$("$SUT" --rows)"
check "rows give raw fields: id, index, name, panes, active" \
    "$(tmux display-message -p -t here:editor '#{window_id}')	0	editor	2	1" "$(head -n1 <<<"$rows" | cut -f1-4,7)"
check "rows include the window's directory" "$PWD" "$(head -n1 <<<"$rows" | cut -f6)"

echo "preview"

left="$(tmux display-message -p -t here:editor.0 '#{pane_id}')"
right="$(tmux display-message -p -t here:editor.1 '#{pane_id}')"
tmux send-keys -t "$right" -l 'right-pane-text'
tmux send-keys -t "$right" Enter
for _ in $(seq 20); do
    tmux capture-pane -p -t "$right" | rg -q right-pane-text && break
    sleep 0.1
done

editor="$(tmux display-message -p -t here:editor '#{window_id}')"
out="$(FZF_PREVIEW_LINES=40 "$SUT" --preview "$editor")"
contains "heads the preview with the window" "0: editor" "$out"
first="$(rg -m1 'pane-text' <<<"$out")"
plain="$(sed 's/\x1b\[[0-9;]*m//g' <<<"$first")"
contains "places panes side by side on the same row" "right-pane-text" "$plain"
contains "separates side-by-side panes with a border" "│" "$plain"
contains "keeps the pane's colours" $'\e[31mleft' "$first"
check "counts wide characters as two columns" "41" \
    "$(LC_ALL=C.UTF-8 wc -L <<<"${plain%%right-pane-text*}" | tr -d ' ')"

out="$(FZF_PREVIEW_LINES=5 "$SUT" --preview "$editor")"
check "fits the layout into the preview height" "5" "$(wc -l <<<"$out" | tr -d ' ')"

out="$("$SUT" --preview '@999')"
contains "reports a window that has gone" "No such window" "$out"

echo "actions"

out="$(TMUX_WINDOWS_DRYRUN=1 "$SUT" --select "$editor")"
check "selects the chosen window" "tmux select-window -t $editor" "$out"

logs="$(tmux display-message -p -t here:logs '#{window_id}')"
"$SUT" --kill "$logs"
lacks "kills the chosen window" "logs" "$("$SUT" --list)"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

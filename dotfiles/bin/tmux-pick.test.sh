#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SELF_DIR/tmux-pick"
FIXTURES="$(mktemp -d)"
SOCKET="tmux-pick-test-$$"

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
mkdir -p "$SHIM" "$FIXTURES/state"
cat > "$SHIM/tmux" <<EOF
#!/bin/bash
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM/tmux"
export PATH="$SHIM:$PATH"
export AGENT_STATE_DIR="$FIXTURES/state"

WORKDIR="$FIXTURES/work"
mkdir -p "$WORKDIR"
tmux -f /dev/null new-session -d -s here -n editor -c "$WORKDIR" 'cat'
tmux new-window -d -t here: -n logs -c "$WORKDIR" 'cat'
tmux new-session -d -s elsewhere -n hidden -c "$WORKDIR" 'cat'

export TMUX="/tmp/fake,1,$(tmux display-message -p -t here '#{session_id}' | tr -d '$')"

agent_pane="$(tmux display-message -p -t elsewhere:hidden '#{pane_id}')"
printf 'question\n%s\n%s\n' "$agent_pane" "$WORKDIR" > "$AGENT_STATE_DIR/$$"

kinds() { cut -f3 <<<"$1" | paste -sd' '; }
of_kind() { rg $'\t'"$1"$'\t' <<<"$2"; }
plain() { sed 's/\x1b\[[0-9;]*m//g'; }

echo "listing"

out="$("$SUT" --list)"
check "heads each group, agents then sessions then windows" \
    "header agent header session session header window window" "$(kinds "$out")"
check "names each group in its header" "Agents Sessions Windows" \
    "$(of_kind header "$out" | cut -f2 | plain | rg -o '[A-Z][a-z]+' | paste -sd' ')"
check "leaves a header's searchable text empty" "" "$(of_kind header "$out" | cut -f1 | tr -d '\n')"
check "leaves an item's header text empty" "" "$(rg -v $'\theader\t' <<<"$out" | cut -f2 | tr -d '\n')"
check "keys an agent by its pane" "$agent_pane" "$(of_kind agent "$out" | cut -f4)"
check "keys a session by its name" "here elsewhere" \
    "$(of_kind session "$out" | cut -f4 | sort -r | paste -sd' ')"
check "keys a window by its id" "$(tmux list-windows -t here -F '#{window_id}' | paste -sd' ')" \
    "$(of_kind window "$out" | cut -f4 | paste -sd' ')"
contains "includes the window you are on" "editor" "$(of_kind window "$out")"
lacks "leaves out windows from other sessions" "hidden" "$(of_kind window "$out")"

echo "layout"

contains "leads an agent with its state glyph" "❓" "$(of_kind agent "$out" | cut -f1 | cut -c1-6)"
contains "leads a session with a folder" "📁" "$(of_kind session "$out" | cut -f1 | head -n1 | cut -c1-6)"
contains "leads a window with a square" "🔲" "$(of_kind window "$out" | cut -f1 | cut -c1-6)"
contains "marks the session you are in" "●" "$(of_kind session "$out" | rg $'\there$' | cut -f1)"
contains "marks the window you are on" "🔲  ●           0:editor" "$(of_kind window "$out" | cut -f1 | plain)"
contains "leaves other windows unmarked" "🔲              1:logs" "$(of_kind window "$out" | cut -f1 | plain)"
lacks "drops the type column" "session" "$(of_kind session "$out" | cut -f1)"
contains "shows only the mark in the state column" "📁  ●           here" "$(of_kind session "$out" | cut -f1 | plain)"
widths="$(rg -v $'\theader\t' <<<"$out" | cut -f1 | plain \
    | while IFS= read -r line; do printf '%s\n' "${line%%"$WORKDIR"*}" | LC_ALL=C.UTF-8 wc -L; done \
    | sort -u | wc -l)"
check "lines up the directory column across every group" "1" "$widths"

rm -f "$AGENT_STATE_DIR/$$"
tmux kill-window -t here:logs
out="$("$SUT" --list)"
check "drops a group and its header when it is empty" "header session session" "$(kinds "$out")"

tmux new-window -d -t here: -n logs 'cat'
printf 'question\n%s\n/home/dave/project\n' "$agent_pane" > "$AGENT_STATE_DIR/$$"

echo "preview"

tmux send-keys -t "$agent_pane" -l 'agent-pane-text'
tmux send-keys -t "$agent_pane" Enter
for _ in $(seq 20); do
    tmux capture-pane -p -t "$agent_pane" | rg -q agent-pane-text && break
    sleep 0.1
done
contains "shows the agent pane's contents" "agent-pane-text" \
    "$(FZF_PREVIEW_LINES=10 "$SUT" --preview agent "$agent_pane")"
contains "previews a session" "Windows" "$(FZF_PREVIEW_LINES=20 "$SUT" --preview session elsewhere)"
logs="$(tmux display-message -p -t here:logs '#{window_id}')"
contains "previews a window" ": logs" "$(FZF_PREVIEW_LINES=20 "$SUT" --preview window "$logs")"

echo "actions"

check "attaches to the chosen session" \
    $'tmux detach-client -s =elsewhere\ntmux switch-client -t =elsewhere' \
    "$(TMUX_SESSIONS_DRYRUN=1 "$SUT" --go session elsewhere)"
check "selects the chosen window" "tmux select-window -t $logs" \
    "$(TMUX_WINDOWS_DRYRUN=1 "$SUT" --go window "$logs")"

"$SUT" --kill agent "$agent_pane"
check "never kills an agent" "$agent_pane" "$(tmux display-message -p -t "$agent_pane" '#{pane_id}')"
"$SUT" --kill window "$logs"
lacks "kills the chosen window" "logs" "$(tmux list-windows -t here -F '#{window_name}')"
"$SUT" --kill session elsewhere
lacks "kills the chosen session" "elsewhere" "$(tmux list-sessions -F '#{session_name}')"

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))

#!/bin/bash

set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SELF_DIR/agent-state"
SOCKET="agent-state-test-$$"
SHIM_DIR="$(mktemp -d)"

PASS=0
FAIL=0

STATE_ROOT="$(mktemp -d)"
export AGENT_STATE_DIR="$STATE_ROOT"

cleanup() {
    command tmux -L "$SOCKET" kill-server 2>/dev/null
    rm -rf "$SHIM_DIR" "$STATE_ROOT"
}
trap cleanup EXIT

cat > "$SHIM_DIR/tmux" <<EOF
#!/bin/bash
exec $(command -v tmux) -L "$SOCKET" "\$@"
EOF
chmod +x "$SHIM_DIR/tmux"
PATH="$SHIM_DIR:$PATH"

export AGENT_STATE_COMMANDS="sleep"

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

pane_opt() { tmux display-message -p -t "$1" "#{$2}"; }

WORK_ROOT="$(mktemp -d)"

hook_in() {  # hook_in <folder name> <state> <pane>
    mkdir -p "$WORK_ROOT/$1"
    ( cd "$WORK_ROOT/$1" && "$SUT" hook "$2" "$3" )
}

new_agent_session() {  # new_agent_session <name> [pane count]
    tmux new-session -d -s "$1" 'sleep 600'
    local i
    for (( i = 1; i < ${2:-1}; i++ )); do
        tmux split-window -d -t "$1:0" 'sleep 600'
    done
}

reset_server() {
    command tmux -L "$SOCKET" kill-server 2>/dev/null
    rm -f "$STATE_ROOT"/* 2>/dev/null
    tmux new-session -d -s scaffold 'sleep 600'
}

echo "agent-state"
echo
echo "set"

reset_server
new_agent_session alpha
P=$(tmux list-panes -t alpha -F '#{pane_id}' | head -1)
"$SUT" set working "$P"
check "stamps the pane option" "working" "$(pane_opt "$P" @agent)"

"$SUT" set waiting "$P"
check "overwrites an existing state" "waiting" "$(pane_opt "$P" @agent)"

echo
echo "window stamp"

reset_server
new_agent_session beta 2
P1=$(tmux list-panes -t beta -F '#{pane_id}' | sed -n 1p)
P2=$(tmux list-panes -t beta -F '#{pane_id}' | sed -n 2p)
"$SUT" set working "$P1"
check "follows a single pane" "working" "$(pane_opt beta:0 @agent_win)"

"$SUT" set waiting "$P2"
check "waiting outranks working" "waiting" "$(pane_opt beta:0 @agent_win)"

"$SUT" set done "$P2"
check "done outranks working" "done" "$(pane_opt beta:0 @agent_win)"

"$SUT" set question "$P1"
check "a pending question outranks done" "question" "$(pane_opt beta:0 @agent_win)"

"$SUT" set plan "$P1"
check "a plan awaiting review outranks done" "plan" "$(pane_opt beta:0 @agent_win)"

"$SUT" set done "$P1"
"$SUT" set permission "$P2"
check "a permission prompt outranks done" "permission" "$(pane_opt beta:0 @agent_win)"

"$SUT" set working "$P1"
"$SUT" set done "$P2"

tmux select-pane -t "$P1"
check "is independent of which pane is active" "done" "$(pane_opt beta:0 @agent_win)"

echo
echo "clear"

"$SUT" clear "$P2"
check "removes the pane state" "" "$(pane_opt "$P2" @agent)"
check "recomputes the window from the panes left" "working" "$(pane_opt beta:0 @agent_win)"

"$SUT" clear "$P1"
check "unsets the window once no pane holds a state" "" "$(pane_opt beta:0 @agent_win)"

echo
echo "status"

reset_server
new_agent_session gamma
new_agent_session delta
new_agent_session epsilon
G=$(tmux list-panes -t gamma -F '#{pane_id}' | head -1)
D=$(tmux list-panes -t delta -F '#{pane_id}' | head -1)
E=$(tmux list-panes -t epsilon -F '#{pane_id}' | head -1)
hook_in alpha-proj permission "$G"
hook_in beta-proj  done       "$D"
hook_in gamma-proj working    "$E"
STATUS="$("$SUT" status)"
contains "names the agent awaiting permission" "🔐 alpha-proj" "$STATUS"
contains "names the agent that is done" "✅ beta-proj" "$STATUS"
contains "names the agent that is working" "⏳ gamma-proj" "$STATUS"
reset_server
new_agent_session freshly-booted
F=$(tmux list-panes -t freshly-booted -F '#{pane_id}' | head -1)
hook_in booted-proj idle "$F"
contains "an agent shows up as soon as it boots" "💤 booted-proj" "$("$SUT" status)"
check "a booted agent records its state like any other" "idle" "$(pane_opt "$F" @agent)"

echo
echo "status colouring"

reset_server
new_agent_session here-session
new_agent_session there-session
HERE=$(tmux list-panes -t here-session -F '#{pane_id}' | head -1)
THERE=$(tmux list-panes -t there-session -F '#{pane_id}' | head -1)
hook_in here-proj  done    "$HERE"
hook_in there-proj working "$THERE"

STATUS="$("$SUT" status here-session)"
contains "the agent in the current session matches the bar's own text" "#[fg=white]✅ here-proj" "$STATUS"
contains "an agent elsewhere is dimmed against it" "#[fg=black]⏳ there-proj" "$STATUS"

STATUS="$("$SUT" status there-session)"
contains "the colouring follows whichever session is asking" "#[fg=white]⏳ there-proj" "$STATUS"
contains "the other agent is dimmed instead" "#[fg=black]✅ here-proj" "$STATUS"

check "no colour collides with the bar's own background" "" \
    "$(printf '%s' "$("$SUT" status here-session)" | rg -o 'fg=colour238' || true)"

check "no entry sets a background, so the bar stays even" "" \
    "$(printf '%s' "$("$SUT" status here-session)" | rg -o 'bg=' || true)"

STATUS="$("$SUT" status)"
check "with no session named, nothing claims to be here" "" \
    "$(printf '%s' "$STATUS" | rg -o 'fg=white' || true)"

tmux set -g @agent_colour_here 'red'
tmux set -g @agent_colour_elsewhere 'colour244'
STATUS="$("$SUT" status here-session)"
contains "the here colour can be retuned live" "#[fg=red]✅ here-proj" "$STATUS"
contains "the elsewhere colour can be retuned live" "#[fg=colour244]⏳ there-proj" "$STATUS"
tmux set -gu @agent_colour_here
tmux set -gu @agent_colour_elsewhere
contains "unsetting restores the default" "#[fg=white]✅ here-proj" "$("$SUT" status here-session)"

echo
echo "status ordering"

reset_server
new_agent_session order-a
new_agent_session order-b
new_agent_session order-c
OA=$(tmux list-panes -t order-a -F '#{pane_id}' | head -1)
OB=$(tmux list-panes -t order-b -F '#{pane_id}' | head -1)
OC=$(tmux list-panes -t order-c -F '#{pane_id}' | head -1)
hook_in aaa working "$OA"
hook_in bbb working "$OB"
hook_in ccc working "$OC"

ORDER_BEFORE="$("$SUT" status | rg -o 'aaa|bbb|ccc' | tr '\n' ' ')"
check "orders by session, not by state" "aaa bbb ccc " "$ORDER_BEFORE"

"$SUT" set permission "$OC"
"$SUT" set done "$OA"
ORDER_AFTER="$("$SUT" status | rg -o 'aaa|bbb|ccc' | tr '\n' ' ')"
check "the order does not move when states change" "$ORDER_BEFORE" "$ORDER_AFTER"

"$SUT" set working "$OC"
"$SUT" set permission "$OB"
check "nor when a different agent becomes the urgent one" "$ORDER_BEFORE" \
    "$("$SUT" status | rg -o 'aaa|bbb|ccc' | tr '\n' ' ')"

check "the picker still leads with the most urgent" "bbb" \
    "$("$SUT" list | head -1 | rg -o 'aaa|bbb|ccc' | head -1)"

reset_server
new_agent_session kindq
new_agent_session kindp
Q=$(tmux list-panes -t kindq -F '#{pane_id}' | head -1)
L=$(tmux list-panes -t kindp -F '#{pane_id}' | head -1)
hook_in asking-proj   question "$Q"
hook_in planning-proj plan     "$L"
tmux kill-session -t scaffold
STATUS="$("$SUT" status)"
contains "a pending question shows its own glyph" "❓ asking-proj" "$STATUS"
contains "a plan awaiting review shows its own glyph" "📝 planning-proj" "$STATUS"
check "the kinds are reported separately, not merged" "2" \
    "$(printf '%s' "$STATUS" | rg -o '#\[fg=' | wc -l)"

reset_server
tmux kill-session -t scaffold
check "is empty when there are no agents at all" "" "$("$SUT" status)"

reset_server
new_agent_session zeta 2
Z1=$(tmux list-panes -t zeta -F '#{pane_id}' | sed -n 1p)
Z2=$(tmux list-panes -t zeta -F '#{pane_id}' | sed -n 2p)
hook_in shared-proj permission "$Z1"
hook_in shared-proj permission "$Z2"
check "shows each agent separately, even in a shared folder" "2" \
    "$("$SUT" status | rg -o 'shared-proj' | wc -l)"

echo
echo "list"

reset_server
new_agent_session eta
new_agent_session theta
H=$(tmux list-panes -t eta -F '#{pane_id}' | head -1)
"$SUT" set permission "$H"
LIST="$("$SUT" list)"
contains "includes the stamped pane" "permission" "$LIST"
contains "shows the state's glyph" "🔐" "$LIST"
contains "reports an unstamped agent pane as idle" "idle" "$LIST"
contains "shows the idle glyph" "💤" "$LIST"
contains "labels a pane by folder, window and pane" "$(basename "$PWD")-w0-p0" "$LIST"
check "never renders the session:window.pane form" "" "$(printf '%s' "$LIST" | rg -o 'eta:0\.0' || true)"
contains "keeps the session name in its own column" "eta" "$LIST"
check "emits one row per agent pane" "3" "$(printf '%s\n' "$LIST" | wc -l)"
check "ends each row with the pane id" "$H" "$(printf '%s\n' "$LIST" | rg permission | cut -f2)"

tmux new-window -d -t eta -n editor 'cat'
check "excludes panes not running an agent" "3" "$("$SUT" list | wc -l)"

echo
echo "jump"

reset_server
new_agent_session iota
new_agent_session kappa
I=$(tmux list-panes -t iota -F '#{pane_id}' | head -1)
K=$(tmux list-panes -t kappa -F '#{pane_id}' | head -1)
"$SUT" set done "$I"
"$SUT" set waiting "$K"
"$SUT" jump "$I" >/dev/null 2>&1
check "acknowledges a finished agent" "" "$(pane_opt "$I" @agent)"
"$SUT" jump "$K" >/dev/null 2>&1
check "leaves a blocked agent blocked" "waiting" "$(pane_opt "$K" @agent)"

echo
echo "agent directory"

reset_server
tmux new-session -d -s tenant-alpha 'sleep 600'
N=$(tmux list-panes -t tenant-alpha -F '#{pane_id}' | head -1)

hook_in qtms-widget working "$N"
check "a hook records the directory the agent is working in" \
    "$WORK_ROOT/qtms-widget" "$(pane_opt "$N" @agent_dir)"
check "a hook still records the state" "working" "$(pane_opt "$N" @agent)"

LABELLED="$("$SUT" list | rg qtms-widget)"
contains "the label follows the agent, not the session it sits in" "qtms-widget-w0-p0" "$LABELLED"
contains "the session it sits in stays visible" "tenant-alpha" "$LABELLED"

hook_in qtms-widget waiting "$N"
STATUS="$("$SUT" status)"
contains "status names the folder the agent is in" "qtms-widget" "$STATUS"
check "status does not name the session" "" "$(printf '%s' "$STATUS" | rg -o 'tenant-alpha' || true)"

hook_in qtms-relocated working "$N"
check "the recorded directory follows the agent if it moves" \
    "$WORK_ROOT/qtms-relocated" "$(pane_opt "$N" @agent_dir)"

reset_server
new_agent_session tenant-beta
B=$(tmux list-panes -t tenant-beta -F '#{pane_id}' | head -1)
"$SUT" set working "$B"
contains "an unstamped pane falls back to its own path" "$(basename "$PWD")-w0-p0" "$("$SUT" list)"

echo
echo "state precedence"

reset_server
new_agent_session precedence
R=$(tmux list-panes -t precedence -F '#{pane_id}' | head -1)

"$SUT" set plan "$R"
"$SUT" set permission "$R"
check "a permission prompt does not replace a plan awaiting review" "plan" "$(pane_opt "$R" @agent)"

"$SUT" set question "$R"
"$SUT" set permission "$R"
check "a permission prompt does not replace a pending question" "question" "$(pane_opt "$R" @agent)"

"$SUT" set plan "$R"
"$SUT" set waiting "$R"
check "a generic block does not replace a plan awaiting review" "plan" "$(pane_opt "$R" @agent)"

"$SUT" set working "$R"
"$SUT" set permission "$R"
check "a permission prompt does block a working agent" "permission" "$(pane_opt "$R" @agent)"

"$SUT" set done "$R"
"$SUT" set permission "$R"
check "a permission prompt does block a finished agent" "permission" "$(pane_opt "$R" @agent)"

"$SUT" set plan "$R"
"$SUT" set working "$R"
check "a plan never strands the pane: working still applies" "working" "$(pane_opt "$R" @agent)"

"$SUT" set question "$R"
"$SUT" set done "$R"
check "a question never strands the pane: done still applies" "done" "$(pane_opt "$R" @agent)"

echo
echo "preview"

reset_server
tmux new-session -d -s previewed bash
V=$(tmux list-panes -t previewed -F '#{pane_id}' | head -1)
hook_in preview-proj plan "$V"
tmux send-keys -t "$V" 'echo PANEOUTPUTMARKER' Enter
sleep 1

PREVIEW="$("$SUT" preview "$V" 2>&1)"
check "renders without error" "0" "$?"
contains "shows what the pane actually contains" "PANEOUTPUTMARKER" "$PREVIEW"
check "does not repeat the state the picker row already shows" "" \
    "$(printf '%s' "$PREVIEW" | rg -o '📝|^plan' || true)"
check "does not repeat the pane label the picker row already shows" "" \
    "$(printf '%s' "$PREVIEW" | rg -o 'preview-proj-w0-p0' || true)"
check "does not leak a shell error" "" "$(printf '%s' "$PREVIEW" | rg -o 'unbound variable' || true)"

GONE="$("$SUT" preview %999 2>&1)"
check "a closed pane does not error" "0" "$?"
contains "a closed pane is reported plainly" "has gone" "$GONE"
check "a closed pane does not leak a shell error" "" "$(printf '%s' "$GONE" | rg -o 'unbound variable' || true)"

echo
echo "agents outside tmux"

STATE_DIR="$STATE_ROOT"

sleep 600 &
LIVE_PID=$!
DEAD_PID=$(( LIVE_PID + 40000 ))
while kill -0 "$DEAD_PID" 2>/dev/null; do DEAD_PID=$(( DEAD_PID + 1 )); done

reset_server
printf 'working\n\n/home/dave\n' > "$STATE_DIR/$LIVE_PID"

LIST="$("$SUT" list)"
contains "an agent outside tmux is listed" "dave" "$LIST"
contains "it is flagged as unreachable" "not in tmux" "$LIST"
contains "it keeps its own state" "working" "$LIST"
check "it is identified by its process, not by a pane" "1" \
    "$(printf '%s\n' "$LIST" | rg -c "!$LIVE_PID" || echo 0)"

contains "it appears in the status bar too" "⏳ dave" "$("$SUT" status)"
contains "it is never coloured as here" "#[fg=black]⏳ dave" "$("$SUT" status scaffold)"

printf 'working\n\n/home/dave/gone\n' > "$STATE_DIR/$DEAD_PID"
check "an agent whose process has gone is not listed" "" \
    "$("$SUT" list | rg -o 'gone' || true)"
check "its leftover state file is tidied away" "1" \
    "$([[ -f "$STATE_DIR/$DEAD_PID" ]] && echo 0 || echo 1)"

printf 'junk\n' > "$STATE_DIR/not-a-pid"
check "a state file that is not a process id is ignored" "0" \
    "$("$SUT" list | rg -c 'junk' || echo 0)"
rm -f "$STATE_DIR/not-a-pid"

SCAFFOLD_PANE=$(tmux list-panes -t scaffold -F '#{pane_id}' | head -1)
printf 'plan\n%s\n/home/dave\n' "$SCAFFOLD_PANE" > "$STATE_DIR/$LIVE_PID"
check "an agent that is in tmux is not also listed as outside it" "0" \
    "$("$SUT" list | rg -c 'not in tmux' || echo 0)"
printf 'working\n\n/home/dave\n' > "$STATE_DIR/$LIVE_PID"

PREVIEW="$("$SUT" preview "!$LIVE_PID" 2>&1)"
check "previewing one does not error" "0" "$?"
contains "the preview says why it cannot be shown" "not running in tmux" "${PREVIEW,,}"

"$SUT" jump "!$LIVE_PID" >/dev/null 2>&1
check "jumping to one fails safely" "0" "$?"

kill "$LIVE_PID" 2>/dev/null
rm -f "$STATE_DIR"/* 2>/dev/null

echo
echo "jumping into a session someone is already viewing"

reset_server
new_agent_session shared-a
SP=$(tmux list-panes -t shared-a -F '#{pane_id}' | head -1)

TMUX=fake "$SUT" jump "$SP" >/dev/null 2>&1
check "with nobody viewing it, no extra session is made" "0" \
    "$(tmux list-sessions -F '#{session_name}' | rg -c 'shared-a-view' || echo 0)"

script -qc "$(command -v tmux) -L $SOCKET attach -t shared-a" /dev/null >/dev/null 2>&1 &
VIEWER=$!
sleep 2
TMUX=fake "$SUT" jump "$SP" >/dev/null 2>&1
check "with someone viewing it, a grouped view session is made" "1" \
    "$(tmux list-sessions -F '#{session_name}' | rg -c 'shared-a-view' || echo 0)"
check "the view session shares the original's windows" "shared-a" \
    "$(tmux list-sessions -f '#{==:#{session_name},shared-a-view}' -F '#{session_group}')"

TMUX=fake "$SUT" jump "$SP" >/dev/null 2>&1
check "a second jump reuses that view rather than stacking up" "1" \
    "$(tmux list-sessions -F '#{session_name}' | rg -c 'shared-a-view' || echo 0)"
kill "$VIEWER" 2>/dev/null

echo
echo "hook configuration"

SETTINGS="$SELF_DIR/../claude/settings.json"

matcher_state() {  # matcher_state <event> <matcher>
    jq -r --arg e "$1" --arg m "$2" '
        (.hooks[$e] // [])
        | map(select(.matcher == $m))
        | map(.hooks[].command | select(test("agent-state")) | sub(".*agent-state "; ""))
        | join(",")
    ' "$SETTINGS" 2>/dev/null
}

check "settings.json is valid JSON" "0" "$(jq -e . "$SETTINGS" >/dev/null 2>&1; echo $?)"

check "a permission prompt is recorded as such" "hook permission" \
    "$(matcher_state Notification permission_prompt)"

check "an idle nudge is not wired to any state" "" \
    "$(jq -r '[.hooks.Notification[]? | select(.matcher // "" | test("idle"))] | length | select(. > 0) // ""' "$SETTINGS")"

check "no Notification hook runs without a matcher" "" \
    "$(jq -r '[.hooks.Notification[]? | select(has("matcher") | not)] | length | select(. > 0) // ""' "$SETTINGS")"

check "a pending question is recorded as such" "hook question" \
    "$(matcher_state PreToolUse AskUserQuestion)"

check "a plan awaiting review is recorded as such" "hook plan" \
    "$(matcher_state PreToolUse ExitPlanMode)"

check "the existing AskUserQuestion guard is still wired up" "1" \
    "$(jq -r '[.hooks.PreToolUse[]? | select(.matcher == "AskUserQuestion") | .hooks[] | select(.command | test("preview-guard"))] | length' "$SETTINGS")"

echo
echo "ack"

reset_server
new_agent_session lambda 2
L1=$(tmux list-panes -t lambda -F '#{pane_id}' | sed -n 1p)
L2=$(tmux list-panes -t lambda -F '#{pane_id}' | sed -n 2p)
"$SUT" set done "$L1"
"$SUT" set waiting "$L2"
"$SUT" ack "$L1"
check "drops a finished state" "" "$(pane_opt "$L1" @agent)"
"$SUT" ack "$L2"
check "leaves every other state alone" "waiting" "$(pane_opt "$L2" @agent)"
check "restamps the window after acknowledging" "waiting" "$(pane_opt lambda:0 @agent_win)"

echo
echo "hook safety"

reset_server
"$SUT" set nonsense "$(tmux list-panes -t scaffold -F '#{pane_id}' | head -1)" >/dev/null 2>&1
check "rejects an unknown state" "2" "$?"

(unset TMUX TMUX_PANE; "$SUT" set working >/dev/null 2>&1)
check "is a silent no-op outside tmux" "0" "$?"

"$SUT" set working "%999" >/dev/null 2>&1
check "survives a pane that has already gone" "0" "$?"

(unset TMUX TMUX_PANE; PATH=/nonexistent "$SUT" set working >/dev/null 2>&1)
check "survives tmux not being installed" "0" "$?"

echo
printf '%d passed, %d failed\n' "$PASS" "$FAIL"
[[ $FAIL -eq 0 ]]

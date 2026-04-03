#!/usr/bin/env bash
# ralph - Autonomous Claude Code loop runner
# Source this file to use: source ralph.sh
# Usage: ralph [-p <prompt>] [-n <iterations>] [-i] [-l] [-v] [-- arg1 arg2 ...]
#   -i  Interactive mode (also implied by -n 1)
#   -l  Use native Linux claude binary (default: Windows claude.exe)
#   -v  Verbose output (show all tool calls)

# --- Progress filter for stream-json output ---
# Args: $1 = "true"|"false" (verbose mode), $2 = epoch start time
_ralph_progress_filter() {
    local filter_verbose="${1:-false}"
    local filter_start="${2:-$(date +%s)}"

    jq --unbuffered -r --argjson verbose "$filter_verbose" --argjson start "$filter_start" '
        def elapsed:
            ((now | floor) - $start) |
            if . < 0 then . + 1 else . end |  # clock skew guard
            "[+\(. / 60 | floor | tostring | if length < 2 then " " + . else . end)m\(. % 60 | tostring | if length < 2 then "0" + . else . end)s]";


        def is_verbose_only:
            .name as $n |
            if ($n == "Glob" or $n == "Read" or $n == "Grep"
                or $n == "ToolSearch" or $n == "TodoWrite") then true
            elif $n == "Bash" then
                (.input.command // "") | test("^(find |ls |cat |head |tail |grep |rg |sleep )")
            else false end;

        def tool_detail:
            if .name == "Bash" then ": " + (.input.command // "")
            elif .name == "Read" then ": " + (.input.file_path // "")
            elif .name == "Edit" then ": " + (.input.file_path // "")
            elif .name == "Write" then ": " + (.input.file_path // "")
            elif .name == "Grep" then ": " + (.input.pattern // "")
            elif .name == "Glob" then ": " + (.input.pattern // "")
            elif .name == "Agent" then ": " + (.input.description // "")
            else ": " + (.input.description // .input.file_path // "")
            end;

        if .type == "assistant" then
            (.message.content[] |
                if .type == "tool_use" then
                    if ($verbose or (is_verbose_only | not)) then
                        "\(elapsed)   \u25b6 \(.name)\(tool_detail)"                     else empty end
                elif .type == "text" then
                    (.text | split("\n") | map(select(length > 0)) | .[0] // empty) |
                    "\(elapsed)   \u25c7 \(.)"                 else empty end)
        elif .type == "result" then
            "\(elapsed)   \u2713 Done: \(.num_turns) turns, $\(.total_cost_usd // 0 | . * 100 | round / 100), \((.duration_ms // 0) / 1000 | round)s"
        elif .type == "system" and .subtype == "api_retry" then
            "\(elapsed)   \u23f3 Retry \(.attempt)/\(.max_retries) (\(.error))"
        else empty end
    '
}

# --- Signal file helpers ---
ralph-pause() { touch .ralph-pause; echo "Ralph will pause after the current iteration."; }
ralph-stop()  { touch .ralph-stop;  echo "Ralph will stop after the current iteration."; }

ralph() {
    local prompt_mode="default"
    local iterations=10
    local mode="windows"
    local pause=false
    local interactive=false
    local ralph_verbose=false
    local extra_args=()

    # Parse flags
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                cat <<'HELP'
ralph - Autonomous Claude Code loop runner

Usage: ralph [-p <prompt>] [-n <iterations>] [-i] [-l] [-v] [--pause] [-- arg1 arg2 ...]

Options:
  -p <prompt>   Prompt mode: "default", "azure", a file path, or literal text
  -n <count>    Max iterations (default: 10, implies -i when 1)
  -i            Interactive mode (no headless -p flag)
  -l            Use native Linux claude binary (default: Windows claude.exe)
  -v, --verbose Show all tool calls (default: only progress-relevant output)
  --pause       Prompt for confirmation before each iteration
  -h, --help    Show this help

Control a running loop from another terminal:
  ralph-pause   Pause after the current iteration
  ralph-stop    Stop after the current iteration

Positional args after -- are substituted into the prompt as {{1}}, {{2}}, etc.

Examples:
  ralph -- /path/to/project          # Run default prompt against a project
  ralph -n 5 -- /path/to/project     # Limit to 5 iterations
  ralph -n 1 -- /path/to/project     # Single interactive iteration
  ralph -i -- /path/to/project       # Interactive mode
  ralph -p azure -- AB#12345         # Work on Azure DevOps work item
  ralph -p ./my-prompt.txt -- arg1   # Use a custom prompt file
HELP
                return 0
                ;;
            -p)
                prompt_mode="$2"
                shift 2
                ;;
            -n)
                iterations="$2"
                shift 2
                ;;
            -i)
                interactive=true
                shift
                ;;
            -v|--verbose)
                ralph_verbose=true
                shift
                ;;
            -l)
                mode="native"
                shift
                ;;
            --pause)
                pause=true
                shift
                ;;
            --)
                shift
                extra_args=("$@")
                break
                ;;
            *)
                extra_args+=("$1")
                shift
                ;;
        esac
    done

    # -n 1 implies interactive, -i implies single iteration
    if [[ "$iterations" -eq 1 ]]; then
        interactive=true
    fi
    if [[ "$interactive" == true ]]; then
        iterations=1
    fi

    # Auto-detect azure prompt mode from AB#nnn pattern
    if [[ "$prompt_mode" == "default" && ${#extra_args[@]} -gt 0 && "${extra_args[0]}" =~ ^AB#[0-9]+ ]]; then
        prompt_mode="azure"
    fi

    # Resolve prompt content
    local prompt
    case "$prompt_mode" in
        default)
            # Ensure progress.md exists in the target directory
            if [[ ${#extra_args[@]} -gt 0 && -d "${extra_args[0]}" && ! -f "${extra_args[0]}/progress.md" ]]; then
                touch "${extra_args[0]}/progress.md"
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Created ${extra_args[0]}/progress.md"
            fi
            prompt=$(cat <<'RALPH_PROMPT'
@{{1}}/PLAN.md @{{1}}/progress.md
Your tasks are defined as task-*.md files

## Execution
1. Review the task files and decide which task to work on next.
   Pick the highest priority item that is not already complete.
   - Not necessarily the first in the list — use your judgement.
   - Always prioritise bug-fix or defect tasks first.
   - Mark the task as in progress by updating the file.
2. Implement the task, checking any feedback loops (types, tests, linting).
3. Append your progress to the progress.md file, including documenting any issues or blockers encountered.
4. Make a git commit for the completed work.
5. Mark the task as complete by updating the file.
   - ONLY do this if you are able to fulfill ALL the success criteria defined in the task.

ONLY WORK ON A SINGLE TASK PER ITERATION.

If unable to satisfy ALL success criteria, immediately print the following then exit
`<status>ERROR: Unable to fulfill all success criteria for TASK</status>`

If all tasks are complete, output `<status>COMPLETE</status>`.
RALPH_PROMPT
            )
            ;;
        azure)
            prompt=$(cat <<'RALPH_PROMPT'
You are working on Azure DevOps work item {{1}}.

## Setup
1. Fetch the work item {{1}} — this is your plan. Read its title, description, and acceptance criteria.
   - The Azure DevOps MCP server may take a moment to become available. If your first attempt
     fails because the tool is not found or the server is not ready, wait 5 seconds and retry.
     Make up to 3 attempts before giving up.
   - If after retrying you still cannot retrieve the work item details (e.g. authentication failure,
     server unavailable, or the item does not exist), output `<status>ERROR: Cannot access Azure DevOps</status>`
     and exit immediately. Do not attempt any further work.
2. Read all comments on {{1}} — these contain progress notes from previous iterations.
3. Fetch the child work items of {{1}} — these are your tasks.

## Execution
1. Review the child items and decide which task to work on next.
   Pick the highest priority item that is not already Done or Closed.
   Always prioritise "Defect" work items first.
2. Set that child item's state to "In Progress" (or "Doing").
3. Implement the task, checking any feedback loops (types, tests, linting).
4. Make a git commit for the completed work.
5. Set the child item's state to "Done" (or "Resolved").
   - ONLY do this if you are able to fulfill ALL the success criteria
6. Add a comment to the parent work item {{1}} with a progress update:
   - Prefix the comment with "[ralph]" for attribution.
   - Summarise what was done, any issues encountered, and what remains.

ONLY WORK ON A SINGLE TASK PER ITERATION.

If unable to satisfy ALL success criteria, immediately print the following then exit
`<status>ERROR: Unable to fulfill all success criteria for TASK N</status>`

If when attempting to update AzureD Devops on completion, print the following then exit
`<status>ERROR: Cannot update Azure DevOps for {{1}}</status>`

If all child items are Done/Closed, output `<status>COMPLETE</status>`.
RALPH_PROMPT
            )
            ;;
        *)
            if [[ -f "$prompt_mode" ]]; then
                prompt=$(<"$prompt_mode")
            else
                prompt="$prompt_mode"
            fi
            ;;
    esac

    # Substitute {{1}}..{{9}} with positional args
    for i in $(seq 1 ${#extra_args[@]}); do
        prompt="${prompt//\{\{$i\}\}/${extra_args[$((i-1))]}}"
    done

    # Clean up any stale signal files
    rm -f .ralph-pause .ralph-stop

    local tmpfile
    tmpfile=$(mktemp)
    trap "rm -f '$tmpfile' .ralph-pause .ralph-stop" RETURN

    for ((i = 1; i <= iterations; i++)); do
        # Check for signal files between iterations
        if [[ -f .ralph-stop ]]; then
            rm -f .ralph-stop
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped by signal before iteration $i."
            return 0
        fi
        if [[ -f .ralph-pause ]]; then
            rm -f .ralph-pause
            pause=true
        fi

        if [[ "$pause" == true && $i -gt 1 ]]; then
            read -rp "Continue to iteration $i/$iterations? [Y/n] " answer
            if [[ "$answer" =~ ^[Nn] ]]; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Stopped by user before iteration $i."
                return 0
            fi
        fi
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Iteration $i of $iterations ---"

        local iter_start
        iter_start=$(date +%s)

        local prompt_file
        local claude_bin
        if [[ "$mode" == "windows" ]]; then
            local win_temp="/mnt/c/Users/DaveA/AppData/Local/Temp"
            prompt_file=$(mktemp "$win_temp/ralph-XXXXXX")
            claude_bin="claude.exe"
        else
            prompt_file=$(mktemp)
            claude_bin="claude"
        fi

        printf '%s' "$prompt" > "$prompt_file"

        if [[ "$interactive" == true ]]; then
            # Interactive mode: no -p, pass prompt as initial message
            $claude_bin --permission-mode auto \
                --allowedTools "Bash(git commit:*)" \
                < "$prompt_file"
            rm -f "$prompt_file"
            # In interactive mode, user controls the session — no status detection
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] Interactive session ended."
        else
            # Headless mode: stream-json for real-time progress
            $claude_bin --permission-mode auto \
                --allowedTools "Bash(git commit:*)" \
                --output-format stream-json --verbose \
                -p < "$prompt_file" 2>&1 | tee "$tmpfile" | _ralph_progress_filter "$ralph_verbose" "$iter_start"

            rm -f "$prompt_file"

            # Extract result from stream-json output
            local result_text
            result_text=$(jq -r 'select(.type == "result") | .result // ""' "$tmpfile" 2>/dev/null)

            if echo "$result_text" | grep -q '<status>COMPLETE</status>' 2>/dev/null; then
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] Plan completed, exiting."
                return 0
            fi

            if echo "$result_text" | grep -q '<status>ERROR' 2>/dev/null; then
                local error_msg
                error_msg=$(echo "$result_text" | grep -o '<status>ERROR[^<]*</status>' | head -1 | sed 's/<[^>]*>//g')
                echo "[$(date '+%Y-%m-%d %H:%M:%S')] $error_msg"
                return 1
            fi
        fi
    done

    echo "[$(date '+%Y-%m-%d %H:%M:%S')] Reached max iterations ($iterations) without completion."
    return 1
}

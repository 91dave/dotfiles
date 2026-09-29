#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

drop_heredoc_bodies_they_are_file_content_not_commands() {
  awk '
    in_body { if ($0 == terminator) in_body = 0; next }
    {
      if (match($0, /<<-?[[:space:]]*[\047"]?[A-Za-z_][A-Za-z0-9_]*[\047"]?/)) {
        terminator = substr($0, RSTART, RLENGTH)
        sub(/^<<-?[[:space:]]*/, "", terminator)
        gsub(/[\047"]/, "", terminator)
        in_body = 1
      }
      print
    }
  '
}

NORMALISED=$(printf '%s\n' "$COMMAND" | drop_heredoc_bodies_they_are_file_content_not_commands | tr '\n' ';')

US=$'\x1f'

where_a_command_can_start() { printf '(^|[|&;(][[:space:]]*)%s([[:space:]]|;|$)' "$1"; }

RULES=(
  "$(where_a_command_can_start '(e|f|z)?grep')${US}REJECTED: Use 'rg' (ripgrep), not grep - it is recursive by default and faster. As a pipe filter, 'rg <pattern>' replaces piping into grep. rg flags differ: -n for line numbers (NOT -r, which means --replace), -g '<glob>' to filter files (no --include), and no -R."
  "$(where_a_command_can_start 'find')${US}REJECTED: Use 'fdfind' instead of find to locate files - e.g. 'fdfind <pattern>' or 'fdfind -e cs' by extension. If you genuinely need a find-only feature (-exec, -newer, -mtime), say why and run it by hand."
  "$(where_a_command_can_start 'docker(-compose)?')${US}REJECTED: Use 'podman' for all container operations. Compose is a subcommand: 'podman compose ...' replaces both 'docker compose' and the 'docker-compose' binary."
  "$(where_a_command_can_start 'dotnet')${US}REJECTED: Use 'dotnet.exe', not 'dotnet' - the Windows SDK builds these solutions."
  "$(where_a_command_can_start 'pwsh')${US}REJECTED: Use 'pwsh.exe', not 'pwsh'. Note that .exe commands cannot resolve WSL paths: pass Windows-style paths (C:/Code/...) and \$USERPROFILE_WIN rather than \$USERPROFILE."
  "[[:space:]](-rn|-nr)([[:space:]]|;|\$)${US}REJECTED: In rg, '-r' means --replace, not recursive - 'rg -rn <pattern>' silently replaces every match with 'n' and prints garbage. rg is recursive by default; use 'rg -n' for line numbers."
  "$(where_a_command_can_start 'git[[:space:]]+commit').*$(where_a_command_can_start 'git[[:space:]]+push')${US}REJECTED: Run 'git commit' and 'git push' as separate commands, not chained in one call."
)

for rule in "${RULES[@]}"; do
  if [[ "$NORMALISED" =~ ${rule%%"$US"*} ]]; then
    echo "${rule#*"$US"}" >&2
    exit 2
  fi
done

LOOKS_LIKE_A_JEST_RUN='(^|[|&;(][[:space:]]*)(npx[[:space:]]+)?(nx[[:space:]]+(test|run-many|run[[:space:]]+[^[:space:];]+:test)|jest)([[:space:]]|;|$)'
WORKER_COUNT_ALREADY_BOUNDED='--maxWorkers|--runInBand|--workerIdleMemoryLimit|[[:space:]]-w[[:space:]=]'

if [[ "$NORMALISED" =~ $LOOKS_LIKE_A_JEST_RUN ]] && [[ ! "$NORMALISED" =~ $WORKER_COUNT_ALREADY_BOUNDED ]]; then
  echo "REJECTED: An unbounded jest run spawns nproc-1 workers that grow to ~750MB each, exhausting the WSL VM. The OOM killer then fails init.scope, which SIGKILLs tmux and every interactive session. Append '--maxWorkers=6 --workerIdleMemoryLimit=1GB'." >&2
  exit 2
fi

DISPOSABLE_WRITE_TARGET='(/dev/null|/dev/std(out|err)|/tmp/[^[:space:];|&]*)'

WRITES_LEFT_AFTER_DISCOUNTING_DISPOSABLE_TARGETS=$(printf '%s' "$NORMALISED" \
  | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g" \
  | sed -E 's/[0-9]*>&[0-9-]+//g' \
  | sed -E "s#(&|[0-9])?>>?[[:space:]]*${DISPOSABLE_WRITE_TARGET}##g" \
  | sed -E "s#([|&;(][[:space:]]*|^)tee([[:space:]]+-a)?[[:space:]]+${DISPOSABLE_WRITE_TARGET}#\1#g")

SHELL_WRITES_A_FILE='(^|[^=<>!-])>>?[[:space:]]*[^[:space:];|&>]|([|&;(][[:space:]]*|^)tee([[:space:]]|$)'
EDITS_A_FILE_IN_PLACE='([|&;(][[:space:]]*|^)(sed|perl|awk)[[:space:]][^;|]*-([a-zA-Z]*i([[:space:]]|$|\.)|-in-place)'
RUNS_AN_INLINE_SCRIPT='([|&;(][[:space:]]*|^)(python3?|node|ruby|perl)([[:space:]]|$)'
INLINE_SCRIPT_WRITES_A_FILE="(open\\([^)]*['\"](w|a)|writeFileSync|write_text\\(|writelines\\()"

if [[ "$WRITES_LEFT_AFTER_DISCOUNTING_DISPOSABLE_TARGETS" =~ $SHELL_WRITES_A_FILE ]] \
  || [[ "$NORMALISED" =~ $EDITS_A_FILE_IN_PLACE ]] \
  || { [[ "$NORMALISED" =~ $RUNS_AN_INLINE_SCRIPT ]] && [[ "$COMMAND" =~ $INLINE_SCRIPT_WRITES_A_FILE ]]; }; then
  echo "REJECTED: Change files with the Write, Edit or MultiEdit tools, not shell redirection, 'sed -i' or an inline script - those route around the PreToolUse hooks that inspect what is being written. Writing to /tmp and /dev/null is still fine." >&2
  exit 2
fi

ANYWHERE_A_WORD_CAN_START='(^|[|&;([:space:]/])'
PUSHES_WITH_GIT="${ANYWHERE_A_WORD_CAN_START}git(\.exe)?[[:space:]]([^|&;]*[[:space:]])?push([[:space:]]|;|$)"
MERGES_A_PULL_REQUEST="${ANYWHERE_A_WORD_CAN_START}gh(\.exe)?[[:space:]]+pr[[:space:]]+merge([[:space:]]|;|$)"

WITHOUT_LOCAL_STASH_PUSH=$(printf '%s' "$NORMALISED" | sed -E 's/stash[[:space:]]+push/stash/g')

if [[ "$WITHOUT_LOCAL_STASH_PUSH" =~ $PUSHES_WITH_GIT ]] || [[ "$NORMALISED" =~ $MERGES_A_PULL_REQUEST ]]; then
  jq -n '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "ask", permissionDecisionReason: "Outward-facing git push or gh pr merge: needs approval regardless of how it is spelled"}}'
  exit 0
fi

exit 0

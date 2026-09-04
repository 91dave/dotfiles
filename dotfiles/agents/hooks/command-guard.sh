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
  "$(where_a_command_can_start 'docker(-compose)?')${US}REJECTED: Use 'podman.exe' for all container operations. Compose is a subcommand: 'podman.exe compose ...' replaces both 'docker compose' and the 'docker-compose' binary."
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

exit 0

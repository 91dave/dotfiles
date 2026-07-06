#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

COMMAND=$(jq -r '.tool_input.command // empty' 2>/dev/null)
[[ -z "$COMMAND" ]] && exit 0

NORMALISED=${COMMAND//$'\n'/; }
GREP_AT_BOUNDARY='(^|[|&;(][[:space:]]*)(e|f|z)?grep([[:space:]]|$)'
FIND_AT_BOUNDARY='(^|[|&;(][[:space:]]*)find([[:space:]]|$)'

REASON=""
if [[ "$NORMALISED" =~ $GREP_AT_BOUNDARY ]]; then
  REASON="REJECTED: Use 'rg' (ripgrep), not grep - it is recursive by default and faster. As a pipe filter, 'rg <pattern>' replaces '| grep <pattern>'. rg flags differ from grep: -n for line numbers (NOT -r, which means --replace), -g '<glob>' to filter files (no --include), and no -R."
elif [[ "$NORMALISED" =~ $FIND_AT_BOUNDARY ]]; then
  REASON="REJECTED: Use 'fdfind' instead of find to locate files - e.g. 'fdfind <pattern>' or 'fdfind -e cs' by extension. If you genuinely need a find-only feature (-exec, -newer, -mtime), say why and run it by hand."
fi

if [[ -n "$REASON" ]]; then
  echo "$REASON" >&2
  exit 2
fi
exit 0

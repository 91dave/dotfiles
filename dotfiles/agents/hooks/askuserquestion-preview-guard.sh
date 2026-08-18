#!/usr/bin/env bash
command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat)
jq -e '[.tool_input.questions[]?.options[]?.preview // empty] | length > 0' >/dev/null 2>&1 <<<"$INPUT" || exit 0

echo "REJECTED: Do not attach 'preview' to AskUserQuestion options. The preview layout replaces the free-text row with a notes field, so the user cannot supply their own answer. Re-ask the same question with no preview on any option; put the comparison detail in each option's description, or in your message before the question." >&2
exit 2

#!/usr/bin/env bash
# PostToolUse hook (Bash): capture codeflash optimization output and surface
# results back to Claude Code via additionalContext.

set -euo pipefail

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only process actual codeflash optimization runs, not --version or init checks
if ! echo "$COMMAND" | grep -qE 'codeflash.*(--worktree|--file|--all|--agent)'; then
  exit 0
fi

# Extract tool response — handle both structured {output: ...} and raw string
RESPONSE=$(echo "$INPUT" | jq -r '
  if .tool_response | type == "object" then
    .tool_response.output // (.tool_response | tostring)
  else
    .tool_response // empty
  end
')

if [ -z "$RESPONSE" ]; then
  exit 0
fi

jq -nc --arg ctx "$RESPONSE" \
  '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": ("Codeflash optimization output:\n" + $ctx)}}'

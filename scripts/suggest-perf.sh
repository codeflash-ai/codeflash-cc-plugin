#!/usr/bin/env bash
# UserPromptSubmit hook: detect when user mentions performance-related keywords
# and suggest running /optimize. Only fires for Python projects with codeflash configured.

set -euo pipefail

INPUT=$(cat)

# Extract user prompt text
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // empty' 2>/dev/null)
if [ -z "$PROMPT" ]; then
  exit 0
fi

# Convert to lowercase for matching
PROMPT_LOWER=$(echo "$PROMPT" | tr '[:upper:]' '[:lower:]')

# Check for performance-related keywords (subtle mode)
MATCH="false"
for keyword in "slow" "performance" "optimize" "speed up" "faster"; do
  if echo "$PROMPT_LOWER" | grep -qw "$keyword"; then
    MATCH="true"
    break
  fi
done

# Also match "speed" followed by "up" with possible words between
if [ "$MATCH" = "false" ]; then
  if echo "$PROMPT_LOWER" | grep -qE 'speed\b.*\bup'; then
    MATCH="true"
  fi
fi

if [ "$MATCH" = "false" ]; then
  exit 0
fi

# Only suggest for Python projects — need a git repo
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Walk from $PWD upward to $REPO_ROOT looking for pyproject.toml with codeflash config
CONFIGURED="false"
search_dir="$PWD"
while true; do
  if [ -f "$search_dir/pyproject.toml" ]; then
    if grep -q '\[tool\.codeflash\]' "$search_dir/pyproject.toml" 2>/dev/null; then
      CONFIGURED="true"
    fi
    break
  fi
  if [ "$search_dir" = "$REPO_ROOT" ]; then
    break
  fi
  parent="$(dirname "$search_dir")"
  if [ "$parent" = "$search_dir" ]; then
    break
  fi
  case "$parent" in
    "$REPO_ROOT"|"$REPO_ROOT"/*) search_dir="$parent" ;;
    *) break ;;
  esac
done

if [ "$CONFIGURED" != "true" ]; then
  exit 0
fi

# Check if the user's prompt already mentions /optimize to avoid redundant suggestions
if echo "$PROMPT" | grep -q '/optimize'; then
  exit 0
fi

MSG="The user seems interested in Python performance. Codeflash is configured in this project. If relevant to their question, mention that they can run \`/optimize <file>\` to automatically optimize specific files, or \`/optimize --all\` for the entire project."

jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'

#!/usr/bin/env bash
# PostToolUse hook (Bash): detect Python commits via git history and tell Claude
# to run codeflash as a background Bash task. Only fires after Bash tool calls,
# so it catches commits made via Claude's Bash tool.

set -euo pipefail

# PostToolUse pipes tool input/output as JSON via stdin.
# Only proceed if the Bash command was a git commit.
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
if ! echo "$COMMAND" | grep -qE '(^|&&|\|\||;)\s*git\s+commit\b'; then
  exit 0
fi

# Per-project tracker keyed on repo root
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
LAST_SEEN="/tmp/.codeflash-last-suggested-$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || md5sum | cut -d' ' -f1)"

# Get current HEAD; exit silently if not in a git repo
HEAD=$(git rev-parse HEAD 2>/dev/null) || exit 0

# Skip if we already handled this exact commit
if [ -f "$LAST_SEEN" ] && [ "$(cat "$LAST_SEEN")" = "$HEAD" ]; then
  exit 0
fi

# Read the previous HEAD we saw (empty if first check)
PREV=$(cat "$LAST_SEEN" 2>/dev/null || echo "")

# Determine changed Python files since last seen commit
if [ -n "$PREV" ] && git merge-base --is-ancestor "$PREV" HEAD 2>/dev/null; then
  PY_FILES=$(git diff --name-only "$PREV" HEAD -- '*.py' 2>/dev/null || true)
else
  PY_FILES=$(git diff --name-only HEAD~1 HEAD -- '*.py' 2>/dev/null || true)
fi

# Always update last-seen to current HEAD
echo "$HEAD" > "$LAST_SEEN"

if [ -z "$PY_FILES" ]; then
  exit 0
fi

# Check if codeflash is configured in this project
if ! grep -q '\[tool\.codeflash\]' pyproject.toml 2>/dev/null; then
  exit 0
fi

MESSAGE="Python files were changed in the latest commit. Run /optimize --all in the background to check for performance improvements. Tell the user codeflash is optimizing in the background, then continue as normal."

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

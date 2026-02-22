#!/usr/bin/env bash
# PostToolUse hook (Bash): detect Python commits via git history and tell Claude
# to run codeflash as a background Bash task. Only fires after Bash tool calls,
# so it catches commits made via Claude's Bash tool.

set -euo pipefail

# Consume stdin (PostToolUse pipes tool input/output via stdin)
cat > /dev/null

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

# Detect project runner
if [ -f "uv.lock" ]; then
  RUNNER="uv run"
elif [ -f "poetry.lock" ]; then
  RUNNER="poetry run"
elif [ -f "pdm.lock" ]; then
  RUNNER="pdm run"
elif [ -f "Pipfile.lock" ]; then
  RUNNER="pipenv run"
else
  RUNNER=""
fi

MESSAGE="Python files were changed in the latest commit. Run the following command as a background Bash task (run_in_background: true):

  ${RUNNER} codeflash --subagent

Tell the user codeflash is optimizing in the background, then continue as normal."

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

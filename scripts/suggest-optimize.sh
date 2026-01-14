#!/usr/bin/env bash
# UserPromptSubmit hook: detect Python commits via git history and tell Claude
# to run codeflash as a background Bash task. Works regardless of how the commit
# was made (direct, skill, agent, external).

set -euo pipefail

LAST_SEEN="/tmp/.codeflash-last-suggested"

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

read -r -d '' MESSAGE << 'ENDMSG' || true
<user-prompt-submit-hook>
BLOCKING REQUIREMENT — you MUST do this BEFORE responding to the user's message:

Run the following command as a background Bash task (run_in_background: true):

ENDMSG

MESSAGE="${MESSAGE}  ${RUNNER} codeflash

Tell the user codeflash is optimizing in the background, then answer their prompt as normal.
</user-prompt-submit-hook>"

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'

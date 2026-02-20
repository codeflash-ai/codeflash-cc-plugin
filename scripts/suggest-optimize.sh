#!/usr/bin/env bash
# UserPromptSubmit hook: detect Python commits via git history and tell Claude
# to spawn the optimizer agent in the background. Works regardless of how the
# commit was made (direct, skill, agent, external).

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

read -r -d '' MESSAGE << ENDMSG || true
<user-prompt-submit-hook>
Python files were changed in a recent commit. Use the Task tool to spawn the codeflash:optimizer agent in the background (run_in_background: true) with this prompt:

"Optimize Python code using the workflow in your system prompt. Arguments: --all"

Tell the user codeflash is optimizing in the background, then answer their prompt as normal. Do NOT wait for the background task to finish before responding.

Later, when the background task completes, check its output and present results:
1. If optimizations were found, show what was optimized, why it is faster, and the performance numbers.
2. Apply each optimized change using the Edit tool so the user gets the accept/reject prompt.
3. If no optimizations were found, let the user know briefly.
</user-prompt-submit-hook>
ENDMSG

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'

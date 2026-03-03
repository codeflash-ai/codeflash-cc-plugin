#!/usr/bin/env bash
# PostToolUse hook (Bash): detect Python commits via git history and tell Claude
# to run codeflash as a background Bash task. Only fires after Bash tool calls,
# so it catches commits made via Claude's Bash tool.

set -euo pipefail

# Read stdin (PostToolUse pipes tool input/output as JSON via stdin)
INPUT=$(cat)

# Only fire when the Bash command was a git commit
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if ! echo "$TOOL_INPUT" | grep -q 'git commit'; then
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

# Check if codeflash is configured in this project
if ! grep -q '\[tool\.codeflash\]' pyproject.toml 2>/dev/null; then
  SETUP_MSG="Python files were changed in the latest commit, but codeflash is not configured yet.

Ask the user the following two questions to set up codeflash:
1. What is the relative path to the root of their Python module? (e.g. \".\", \"src\", \"src/mypackage\")
2. What is the relative path to their tests folder? (e.g. \"tests\", \"test\", \"src/tests\")

After getting the answers:
- If the tests folder does not exist, create it with mkdir -p.
- Append the following to pyproject.toml (create the file if it does not exist), substituting the user's answers:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

Then run: ${RUNNER} codeflash --subagent"

  jq -nc --arg ctx "$SETUP_MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

MESSAGE="Python files were changed in the latest commit. Run the following command as a background Bash task (run_in_background: true):

  ${RUNNER} codeflash --subagent

Tell the user codeflash is optimizing in the background, then continue as normal."

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

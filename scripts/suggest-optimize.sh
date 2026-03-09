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

# Walk from $PWD upward to $REPO_ROOT looking for pyproject.toml.
# Sets: PYPROJECT_DIR, PYPROJECT_PATH, PYPROJECT_CONFIGURED
find_pyproject() {
  PYPROJECT_DIR=""
  PYPROJECT_PATH=""
  PYPROJECT_CONFIGURED="false"
  local search_dir="$PWD"
  while true; do
    if [ -f "$search_dir/pyproject.toml" ]; then
      PYPROJECT_PATH="$search_dir/pyproject.toml"
      PYPROJECT_DIR="$search_dir"
      if grep -q '\[tool\.codeflash\]' "$search_dir/pyproject.toml" 2>/dev/null; then
        PYPROJECT_CONFIGURED="true"
      fi
      break
    fi
    if [ "$search_dir" = "$REPO_ROOT" ]; then
      break
    fi
    local parent
    parent="$(dirname "$search_dir")"
    if [ "$parent" = "$search_dir" ]; then
      break
    fi
    case "$parent" in
      "$REPO_ROOT"|"$REPO_ROOT"/*) search_dir="$parent" ;;
      *) break ;;
    esac
  done
}

# Detect project runner from lock files near pyproject.toml (or CWD as fallback).
# Sets: RUNNER
detect_runner() {
  local check_dir="${PYPROJECT_DIR:-$PWD}"
  if [ -f "$check_dir/uv.lock" ]; then
    RUNNER="uv run"
  elif [ -f "$check_dir/poetry.lock" ]; then
    RUNNER="poetry run"
  elif [ -f "$check_dir/pdm.lock" ]; then
    RUNNER="pdm run"
  elif [ -f "$check_dir/Pipfile.lock" ]; then
    RUNNER="pipenv run"
  else
    RUNNER=""
  fi
}

# Get current HEAD; exit silently if not in a git repo
HEAD=$(git rev-parse HEAD 2>/dev/null) || exit 0

# Read the previous HEAD we saw (empty if first check)
PREV=$(cat "$LAST_SEEN" 2>/dev/null || echo "")

# Determine changed Python files since last seen commit
if [ -n "$PREV" ] && [ "$PREV" != "$HEAD" ] && git merge-base --is-ancestor "$PREV" HEAD 2>/dev/null; then
  PY_FILES=$(git diff --name-only "$PREV" HEAD -- '*.py' 2>/dev/null || true)
else
  PY_FILES=$(git diff --name-only HEAD~1 HEAD -- '*.py' 2>/dev/null || true)
fi

# Always update last-seen to current HEAD
echo "$HEAD" > "$LAST_SEEN"

if [ -z "$PY_FILES" ]; then
  exit 0
fi

# Discover pyproject.toml and project runner
find_pyproject
detect_runner

# Determine the correct install command based on the runner
CHECK_DIR="${PYPROJECT_DIR:-$PWD}"
case "$RUNNER" in
  "uv run")      INSTALL_CMD="uv add --dev codeflash" ;;
  "poetry run")   INSTALL_CMD="poetry add --group dev codeflash" ;;
  "pdm run")      INSTALL_CMD="pdm add -dG dev codeflash" ;;
  "pipenv run")   INSTALL_CMD="pipenv install --dev codeflash" ;;
  *)              INSTALL_CMD="pip install codeflash" ;;
esac

# Check if codeflash is installed
CODEFLASH_INSTALLED="false"
if (cd "$CHECK_DIR" && ${RUNNER} codeflash --version) >/dev/null 2>&1; then
  CODEFLASH_INSTALLED="true"
fi

# Check if codeflash is configured in this project
if [ "$PYPROJECT_CONFIGURED" != "true" ]; then
  # Build a human-friendly target path for the setup message
  if [ -n "$PYPROJECT_PATH" ]; then
    TARGET_MSG="Append to \`$PYPROJECT_PATH\`"
  else
    TARGET_MSG="Create \`$REPO_ROOT/pyproject.toml\`"
  fi

  # Include install step if codeflash is not installed
  INSTALL_STEP=""
  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    INSTALL_STEP="
- First, install codeflash by running \`${INSTALL_CMD}\` in \`${CHECK_DIR}\`."
  fi

  SETUP_MSG="Python files were changed in the latest commit, but codeflash is not configured yet.

Ask the user the following two questions to set up codeflash:
1. What is the relative path to the root of their Python module? (e.g. \".\", \"src\", \"src/mypackage\")
2. What is the relative path to their tests folder? (e.g. \"tests\", \"test\", \"src/tests\")

After getting the answers:${INSTALL_STEP}
- If the tests folder does not exist, create it with mkdir -p.
- ${TARGET_MSG} (create the file if it does not exist), adding the following section with the user's answers substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

Then run: ${RUNNER} codeflash --subagent as a background Bash task (run_in_background: true)"

  jq -nc --arg ctx "$SETUP_MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

# Codeflash is configured but not installed
if [ "$CODEFLASH_INSTALLED" != "true" ]; then
  INSTALL_MSG="Python files were changed in the latest commit, but codeflash is not installed.

Ask the user if they'd like to install codeflash. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`, then proceed to run codeflash via /optimize."

  jq -nc --arg ctx "$INSTALL_MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

# Build codeflash command, adding cd when pyproject.toml is in a parent directory
if [ -n "$PYPROJECT_DIR" ] && [ "$PYPROJECT_DIR" != "$PWD" ]; then
  CMD="cd $PYPROJECT_DIR && ${RUNNER} codeflash --subagent"
else
  CMD="${RUNNER} codeflash --subagent"
fi

MESSAGE="Python files were changed in the latest commit. Run the following command as a background Bash task (run_in_background: true):

  ${CMD}

Tell the user codeflash is optimizing in the background, then continue as normal."

jq -nc --arg ctx "$MESSAGE" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

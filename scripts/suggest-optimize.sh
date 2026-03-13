#!/usr/bin/env bash
# PostToolUse hook (Bash): detect Python commits via git history and tell Claude
# to run codeflash as a background Bash task. Only fires after Bash tool calls,
# so it catches commits made via Claude's Bash tool.

set -euo pipefail

LOGFILE="/tmp/codeflash-hook-debug.log"
exec 2>>"$LOGFILE"
set -x
# Read stdin (PostToolUse pipes tool input/output as JSON via stdin)
INPUT=$(cat)

# Only fire when the Bash command was a git commit
TOOL_INPUT=$(echo "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
if ! echo "$TOOL_INPUT" | grep -q 'git commit'; then
  exit 0
fi

# Per-project tracker keyed on repo root (resolve symlinks so PWD and REPO_ROOT share a prefix)
REPO_ROOT=$(cd "$(git rev-parse --show-toplevel 2>/dev/null)" && pwd -P) || exit 0
cd "$(pwd -P)"
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

# Discover pyproject.toml
find_pyproject

CHECK_DIR="${PYPROJECT_DIR:-$PWD}"
INSTALL_CMD="pip install codeflash"

# Only use codeflash from the current virtual environment.
# If no venv is active, try to find and activate one automatically.
# shellcheck disable=SC1091
source "$(dirname "$0")/find-venv.sh"

if [ -z "${VIRTUAL_ENV:-}" ]; then
  exit 0
fi

CODEFLASH_BIN="${VIRTUAL_ENV}/bin/codeflash"

# Check if codeflash is installed in the venv
CODEFLASH_INSTALLED="false"
if [ -x "$CODEFLASH_BIN" ] && "$CODEFLASH_BIN" --version >/dev/null 2>&1; then
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

  SETUP_MSG="ACTION REQUIRED: Python files were changed in the latest commit, but codeflash is not configured yet.

You MUST ask the user the following two questions before proceeding with anything else:
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

Once the pyproject.toml configuration is written, you MUST immediately run \`codeflash --subagent\` as a background Bash task (run_in_background: true). Do NOT skip this step."

  # Set flag so the Stop hook can enforce this if Claude ignores additionalContext
  FLAG_FILE="/tmp/.codeflash-needs-config-$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || md5sum | cut -d' ' -f1)"
  echo "1" > "$FLAG_FILE"

  jq -nc --arg ctx "$SETUP_MSG" '{"decision": "block", "reason": $ctx, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

# Codeflash is configured but not installed in the venv
if [ "$CODEFLASH_INSTALLED" != "true" ]; then
  INSTALL_MSG="ACTION REQUIRED: Python files were changed in the latest commit, but codeflash is not installed in the active virtual environment (\`$VIRTUAL_ENV\`).

You MUST ask the user if they'd like to install codeflash before proceeding with anything else. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`, then proceed to run codeflash via \`codeflash --subagent\`."

  jq -nc --arg ctx "$INSTALL_MSG" '{"decision": "block", "reason": $ctx, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

# Build codeflash command, activating the venv and adding cd when pyproject.toml is in a parent directory
ACTIVATE_CMD="source $VIRTUAL_ENV/bin/activate"
if [ -n "$PYPROJECT_DIR" ] && [ "$PYPROJECT_DIR" != "$PWD" ]; then
  CMD="$ACTIVATE_CMD && cd $PYPROJECT_DIR && $CODEFLASH_BIN --subagent"
else
  CMD="$ACTIVATE_CMD && $CODEFLASH_BIN --subagent"
fi

MESSAGE="ACTION REQUIRED: Python files were changed in the latest commit.

You MUST run the following command as a background Bash task (run_in_background: true) before proceeding with anything else:

  ${CMD}

Tell the user codeflash is optimizing in the background, then continue as normal."

jq -nc --arg ctx "$MESSAGE" '{"decision": "block", "reason": $ctx, "hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

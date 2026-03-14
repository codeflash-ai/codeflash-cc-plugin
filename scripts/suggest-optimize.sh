#!/usr/bin/env bash
# Stop hook: detect Python changes and ask the user if they'd like to run
# codeflash to optimize their code. Fires when Claude is about to finish its response.

set -euo pipefail

# Read stdin (Stop hook pipes context as JSON via stdin)
INPUT=$(cat)

# If the stop hook is already active (Claude already responded to a previous block),
# allow the stop to proceed to avoid an infinite block loop.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

## Per-project tracker keyed on repo root (resolve symlinks so PWD and REPO_ROOT share a prefix)
REPO_ROOT=$(cd "$(git rev-parse --show-toplevel 2>/dev/null)" && pwd -P) || exit 0
cd "$(pwd -P)"

# Only trigger if Python files have changed in the current diff (staged + unstaged vs HEAD)
PY_CHANGED=$(git diff HEAD --name-only -- '*.py' 2>/dev/null || true)
if [ -z "$PY_CHANGED" ]; then
  exit 0
fi

# Don't trigger more than once for the same diff.
# Use a hash of the Python-file diff content as the dedup key.
DIFF_HASH=$(git diff HEAD -- '*.py' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
SEEN_MARKER="/tmp/codeflash-seen-${REPO_ROOT//\//_}"
if [ -f "$SEEN_MARKER" ] && grep -qF "$DIFF_HASH" "$SEEN_MARKER" 2>/dev/null; then
  exit 0
fi
echo "$DIFF_HASH" >> "$SEEN_MARKER"

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

# Discover pyproject.toml
find_pyproject

CHECK_DIR="${PYPROJECT_DIR:-$PWD}"
INSTALL_CMD="pip install codeflash"

# Only use codeflash from the current virtual environment.
# If no venv is active, try to find and activate one automatically.
# shellcheck disable=SC1091
source "$(dirname "$0")/find-venv.sh"

if [ -z "${VIRTUAL_ENV:-}" ]; then
  # No venv found — instruct Claude to create one, install codeflash, configure, and run

  # Discover pyproject.toml for setup instructions
  find_pyproject

  # Build pyproject setup instructions if not configured
  PYPROJECT_SETUP=""
  if [ "$PYPROJECT_CONFIGURED" != "true" ]; then
    if [ -n "$PYPROJECT_PATH" ]; then
      TARGET_MSG="Append to \`$PYPROJECT_PATH\`"
    else
      TARGET_MSG="Create \`$REPO_ROOT/pyproject.toml\`"
    fi

    PYPROJECT_SETUP="
3. Ask the user the following two questions:
   a. What is the relative path to the root of their Python module? (e.g. \".\", \"src\", \"src/mypackage\")
   b. What is the relative path to their tests folder? (e.g. \"tests\", \"test\", \"src/tests\")

4. After getting the answers:
   - If the tests folder does not exist, create it with mkdir -p.
   - ${TARGET_MSG} (create the file if it does not exist), adding the following section with the user's answers substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

5. Run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."
  else
    PYPROJECT_SETUP="
3. Run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."
  fi

  VENV_MSG="Python files were changed in the latest commit, but no Python virtual environment was found.

Ask the user if they'd like to set up codeflash to optimize their Python code for performance. If they agree, perform the following steps:

1. Create a virtual environment by running: \`python3 -m venv .venv\` in \`$REPO_ROOT\`, then activate it by running: \`source $REPO_ROOT/.venv/bin/activate\`.

2. Install codeflash by running: \`${INSTALL_CMD}\`.
${PYPROJECT_SETUP}

If the user declines, do nothing and continue normally."

  jq -nc --arg reason "$VENV_MSG" '{"decision": "block", "reason": $reason}'
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

  SETUP_MSG="Python files were changed in the latest commit, but codeflash is not configured yet.

Ask the user if they'd like to set up codeflash to optimize their Python code for performance. If they agree, ask them:
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

Once the pyproject.toml configuration is written, run \`codeflash --subagent\` as a background Bash task (run_in_background: true).

If the user declines, do nothing and continue normally."

  jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# Codeflash is configured but not installed in the venv
if [ "$CODEFLASH_INSTALLED" != "true" ]; then
  INSTALL_MSG="Python files were changed in the latest commit, but codeflash is not installed in the active virtual environment (\`$VIRTUAL_ENV\`).

Ask the user if they'd like to install codeflash to optimize their Python code for performance. The install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`, then run \`codeflash --subagent\` as a background Bash task (run_in_background: true).

If the user declines, do nothing and continue normally."

  jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# Instruct Claude to run codeflash as a background subagent
if [ -n "$PYPROJECT_DIR" ] && [ "$PYPROJECT_DIR" != "$PWD" ]; then
  RUN_CMD="cd $PYPROJECT_DIR && $CODEFLASH_BIN --subagent"
else
  RUN_CMD="$CODEFLASH_BIN --subagent"
fi

MESSAGE="Python files were changed in the latest commit. Ask the user if they'd like to run codeflash to optimize their Python code for performance. If they agree, run \`${RUN_CMD}\` as a background Bash task (run_in_background: true). If they decline, do nothing and continue normally."

jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason}'

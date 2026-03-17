#!/usr/bin/env bash
# Stop hook: detect new Python commits since the session started and ask the
# user if they'd like to run codeflash to optimize their code.
# Fires when Claude is about to finish its response.

set -euo pipefail

LOGFILE="/tmp/codeflash-hook-debug.log"
exec 2>>"$LOGFILE"
set -x

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

# --- Detect new Python commits since session started ---

# Extract transcript_path from hook input to determine session start time
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi

# Get the transcript file's creation (birth) time as the session start timestamp.
# This predates any commits Claude could have made in this session.
get_file_birth_time() {
  local file="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %B "$file"
  else
    local btime
    btime=$(stat -c %W "$file" 2>/dev/null || echo "0")
    if [ "$btime" = "0" ] || [ -z "$btime" ]; then
      stat -c %Y "$file"
    else
      echo "$btime"
    fi
  fi
}

SESSION_START=$(get_file_birth_time "$TRANSCRIPT_PATH")
if [ -z "$SESSION_START" ] || [ "$SESSION_START" = "0" ]; then
  exit 0
fi

# Find commits with Python files made after the session started
PY_COMMITS=$(git log --after="@$SESSION_START" --name-only --diff-filter=ACMR --pretty=format: -- '*.py' 2>/dev/null | sort -u | grep -v '^$' || true)
if [ -z "$PY_COMMITS" ]; then
  exit 0
fi

# Dedup: don't trigger twice for the same set of changes across sessions.
# Use the project directory from transcript_path for state storage.
PROJECT_DIR=$(dirname "$TRANSCRIPT_PATH")
SEEN_MARKER="$PROJECT_DIR/codeflash-seen"

COMMIT_HASH=$(git log --after="@$SESSION_START" --pretty=format:%H -- '*.py' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
if [ -f "$SEEN_MARKER" ] && grep -qF "$COMMIT_HASH" "$SEEN_MARKER" 2>/dev/null; then
  exit 0
fi
echo "$COMMIT_HASH" >> "$SEEN_MARKER"

# --- From here on, we know there are new Python commits to optimize ---

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
3. Automatically determine the following two values by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user — discover the correct paths yourself):
   a. The relative path with respect to pyproject.toml to the root of the Python module — the module root is where tests import from. for example, if the module root is abc/ then the tests would be importing code as \`from abc import xyz\`.
   b. The relative path with respect to pyproject.toml to the tests folder — look for existing directories named \`tests\` or \`test\`, or folders containing files that start with \`test_\`. If none exist, default to \`tests\`.

4. Once determined:
   - If the tests folder does not exist, create it with mkdir -p.
   - ${TARGET_MSG} (create the file if it does not exist), adding the following section with the discovered values substituted:

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

  VENV_MSG="Python files were changed in a recent commit, but no Python virtual environment was found.

Set up codeflash to optimize the Python code for performance. Perform the following steps:

1. Create a virtual environment by running: \`python3 -m venv .venv\` in \`$REPO_ROOT\`, then activate it by running: \`source $REPO_ROOT/.venv/bin/activate\`.

2. Install codeflash by running: \`${INSTALL_CMD}\`.
${PYPROJECT_SETUP}
"

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

  SETUP_MSG="Python files were changed in a recent commit, but codeflash is not configured yet.

Set up codeflash to optimize the Python code for performance. Automatically determine the following by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user — discover the correct paths yourself):
1. The relative path with respect to pyproject.toml to the root of the Python module — the module root is where tests import from. for example, if the module root is abc/ then the tests would be importing code as \`from abc import xyz\`.
2. The relative path with respect to pyproject.toml to the tests folder — look for existing directories named \`tests\` or \`test\`, or folders containing files that start with \`test_\`. If none exist, default to \`tests\`.

Once determined:${INSTALL_STEP}
- If the tests folder does not exist, create it with mkdir -p.
- ${TARGET_MSG} (create the file if it does not exist), adding the following section with the discovered values substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

Once the pyproject.toml configuration is written, run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."

  jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# Codeflash is configured but not installed in the venv
if [ "$CODEFLASH_INSTALLED" != "true" ]; then
  INSTALL_MSG="Python files were changed in a recent commit, but codeflash is not installed in the active virtual environment (\`$VIRTUAL_ENV\`).

Install codeflash to optimize the Python code for performance by running:

  ${INSTALL_CMD}

in \`${CHECK_DIR}\`, then run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."

  jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# Instruct Claude to run codeflash as a background subagent
if [ -n "$PYPROJECT_DIR" ] && [ "$PYPROJECT_DIR" != "$PWD" ]; then
  RUN_CMD="cd $PYPROJECT_DIR && $CODEFLASH_BIN --subagent"
else
  RUN_CMD="$CODEFLASH_BIN --subagent"
fi

MESSAGE="Python files were changed in a recent commit. Run \`${RUN_CMD}\` as a background Bash task (run_in_background: true) to optimize the Python code for performance."

jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason}'
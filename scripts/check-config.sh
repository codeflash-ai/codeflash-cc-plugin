#!/usr/bin/env bash
# PostToolUse hook (all tools): once-per-session check that codeflash is
# configured and installed for the current Python project.  Uses a flag file
# so every invocation after the first is a single stat() call (~4ms).

set -euo pipefail

# Consume stdin (PostToolUse always pipes JSON on stdin)
cat >/dev/null

# --- fast path -----------------------------------------------------------
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
REPO_HASH=$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || md5sum | cut -d' ' -f1)
SESSION_FLAG="/tmp/.codeflash-config-checked-${REPO_HASH}"

if [ -f "$SESSION_FLAG" ]; then
  exit 0
fi

# If the Stop hook flag already exists (set by suggest-optimize.sh), avoid
# duplicate prompts – just mark session as checked.
STOP_FLAG="/tmp/.codeflash-needs-config-${REPO_HASH}"
if [ -f "$STOP_FLAG" ]; then
  touch "$SESSION_FLAG"
  exit 0
fi

# --- Python project detection --------------------------------------------
is_python_project() {
  for marker in pyproject.toml setup.py setup.cfg requirements.txt Pipfile; do
    if [ -f "$REPO_ROOT/$marker" ]; then
      return 0
    fi
  done
  # Fallback: look for .py files up to 2 levels deep
  if find "$REPO_ROOT" -maxdepth 2 -name '*.py' -print -quit 2>/dev/null | grep -q .; then
    return 0
  fi
  return 1
}

if ! is_python_project; then
  touch "$SESSION_FLAG"
  exit 0
fi

# --- locate pyproject.toml with [tool.codeflash] -------------------------
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

find_pyproject

CHECK_DIR="${PYPROJECT_DIR:-$PWD}"
INSTALL_CMD="pip install codeflash"

# --- locate codeflash binary ---------------------------------------------
find_codeflash() {
  CODEFLASH_BIN=""
  CODEFLASH_VENV_ACTIVATE=""
  if command -v codeflash >/dev/null 2>&1; then
    CODEFLASH_BIN="codeflash"
    return
  fi
  local search_dir
  for search_dir in "$CHECK_DIR" "$REPO_ROOT" "$PWD"; do
    for venv in ".venv" "venv" ".env" "env"; do
      if [ -x "$search_dir/$venv/bin/codeflash" ]; then
        CODEFLASH_BIN="$search_dir/$venv/bin/codeflash"
        if [ -f "$search_dir/$venv/bin/activate" ]; then
          CODEFLASH_VENV_ACTIVATE="$search_dir/$venv/bin/activate"
        fi
        return
      fi
    done
  done
}

find_codeflash

CODEFLASH_INSTALLED="false"
if [ -n "$CODEFLASH_BIN" ] && "$CODEFLASH_BIN" --version >/dev/null 2>&1; then
  CODEFLASH_INSTALLED="true"
fi

# --- both configured and installed → nothing to do -----------------------
if [ "$PYPROJECT_CONFIGURED" = "true" ] && [ "$CODEFLASH_INSTALLED" = "true" ]; then
  touch "$SESSION_FLAG"
  exit 0
fi

# --- not configured → prompt for config (+ install if needed) ------------
if [ "$PYPROJECT_CONFIGURED" != "true" ]; then
  if [ -n "$PYPROJECT_PATH" ]; then
    TARGET_MSG="Append to \`$PYPROJECT_PATH\`"
  else
    TARGET_MSG="Create \`$REPO_ROOT/pyproject.toml\`"
  fi

  INSTALL_STEP=""
  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    INSTALL_STEP="
- First, install codeflash by running \`${INSTALL_CMD}\` in \`${CHECK_DIR}\`."
  fi

  ACTIVATE_STEP=""
  if [ -n "$CODEFLASH_VENV_ACTIVATE" ]; then
    ACTIVATE_STEP="
- Before running codeflash, activate the virtualenv: \`source ${CODEFLASH_VENV_ACTIVATE}\`"
  fi

  SETUP_MSG="ACTION REQUIRED: This is a Python project but codeflash is not configured yet.

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
${ACTIVATE_STEP}
Once the pyproject.toml configuration is written, you MUST immediately run \`codeflash --subagent\` as a background Bash task (run_in_background: true). Do NOT skip this step."

  touch "$SESSION_FLAG"
  echo "1" > "$STOP_FLAG"

  jq -nc --arg ctx "$SETUP_MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'
  exit 0
fi

# --- configured but not installed → prompt for install -------------------
ACTIVATE_NOTE=""
if [ -n "$CODEFLASH_VENV_ACTIVATE" ]; then
  ACTIVATE_NOTE="

Before running codeflash, activate the virtualenv: \`source ${CODEFLASH_VENV_ACTIVATE}\`"
fi

INSTALL_MSG="ACTION REQUIRED: This is a Python project with codeflash configured, but the codeflash package is not installed.

You MUST ask the user if they'd like to install codeflash before proceeding with anything else. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`, then proceed to run codeflash via \`codeflash --subagent\`.${ACTIVATE_NOTE}"

touch "$SESSION_FLAG"

jq -nc --arg ctx "$INSTALL_MSG" '{"hookSpecificOutput": {"hookEventName": "PostToolUse", "additionalContext": $ctx}}'

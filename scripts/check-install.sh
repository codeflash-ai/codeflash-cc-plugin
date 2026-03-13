#!/usr/bin/env bash
# SessionStart hook: check if the codeflash PyPI package is installed and
# prompt the user to install it if missing.  Runs once per session start;
# exits silently when codeflash is already available.

set -euo pipefail

# We need a git repo to locate pyproject.toml and lock files.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# Clear per-session config-check flag so check-config.sh re-evaluates fresh
REPO_HASH=$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || md5sum | cut -d' ' -f1)
rm -f "/tmp/.codeflash-config-checked-${REPO_HASH}"

# Walk from $PWD upward to $REPO_ROOT looking for pyproject.toml.
find_pyproject() {
  PYPROJECT_DIR=""
  PYPROJECT_PATH=""
  local search_dir="$PWD"
  while true; do
    if [ -f "$search_dir/pyproject.toml" ]; then
      PYPROJECT_PATH="$search_dir/pyproject.toml"
      PYPROJECT_DIR="$search_dir"
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

# Only use codeflash from the current virtual environment.
# If no venv is active, try to find and activate one automatically.
if [ -z "${VIRTUAL_ENV:-}" ]; then
  for candidate in "$CHECK_DIR/.venv" "$CHECK_DIR/venv" "$REPO_ROOT/.venv" "$REPO_ROOT/venv"; do
    if [ -f "$candidate/bin/activate" ]; then
      # shellcheck disable=SC1091
      source "$candidate/bin/activate"
      break
    fi
  done
fi

if [ -z "${VIRTUAL_ENV:-}" ]; then
  MSG="ACTION REQUIRED: The codeflash plugin requires an active Python virtual environment, but none was found.

You MUST inform the user about this before proceeding with anything else. Tell them:

1. No Python virtual environment was found. Codeflash must be installed in a virtual environment.
2. They should create and activate one, for example:
   \`\`\`
   python -m venv .venv
   source .venv/bin/activate   # On macOS/Linux
   # or: .venv\\\\Scripts\\\\activate  # On Windows
   \`\`\`
3. Then install codeflash: \`pip install codeflash\`
4. Then restart Claude Code from within the activated virtual environment."

  jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'
  exit 0
fi

CODEFLASH_BIN="${VIRTUAL_ENV}/bin/codeflash"

# If codeflash is already installed in the venv, nothing to do.
if [ -x "$CODEFLASH_BIN" ] && "$CODEFLASH_BIN" --version >/dev/null 2>&1; then
  exit 0
fi

INSTALL_CMD="pip install codeflash"

MSG="ACTION REQUIRED: The codeflash plugin is installed but the \`codeflash\` Python package is missing from the active virtual environment (\`$VIRTUAL_ENV\`).

You MUST inform the user about this and ask if they'd like to install it now, before proceeding with anything else. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`."

jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'

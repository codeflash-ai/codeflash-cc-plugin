#!/usr/bin/env bash
# SessionStart hook: check if the codeflash PyPI package is installed and
# prompt the user to install it if missing.  Runs once per session start;
# exits silently when codeflash is already available.

set -euo pipefail

# We need a git repo to locate pyproject.toml and lock files.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

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

# If codeflash is already installed, nothing to do.
if (cd "$CHECK_DIR" && codeflash --version) >/dev/null 2>&1; then
  exit 0
fi

INSTALL_CMD="pip install codeflash"

MSG="ACTION REQUIRED: The codeflash plugin is installed but the \`codeflash\` Python package is missing.

You MUST inform the user about this and ask if they'd like to install it now, before proceeding with anything else. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`."

jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'

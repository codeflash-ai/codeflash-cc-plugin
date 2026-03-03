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

# Detect project runner from lock files near pyproject.toml (or CWD as fallback).
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

find_pyproject
detect_runner

CHECK_DIR="${PYPROJECT_DIR:-$PWD}"

# If codeflash is already installed, nothing to do.
if (cd "$CHECK_DIR" && ${RUNNER} codeflash --version) >/dev/null 2>&1; then
  exit 0
fi

# Determine the correct install command based on the runner.
case "$RUNNER" in
  "uv run")      INSTALL_CMD="uv add --dev codeflash" ;;
  "poetry run")   INSTALL_CMD="poetry add --group dev codeflash" ;;
  "pdm run")      INSTALL_CMD="pdm add -dG dev codeflash" ;;
  "pipenv run")   INSTALL_CMD="pipenv install --dev codeflash" ;;
  *)              INSTALL_CMD="pip install codeflash" ;;
esac

MSG="The codeflash plugin is installed but the \`codeflash\` Python package is missing.

Ask the user if they'd like to install it now. The detected install command is:

  ${INSTALL_CMD}

If the user agrees, run the install command in \`${CHECK_DIR}\`."

jq -nc --arg ctx "$MSG" '{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $ctx}}'

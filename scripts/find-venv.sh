#!/usr/bin/env bash
# Shared helper: find and activate a Python virtual environment.
#
# Requires: REPO_ROOT and CHECK_DIR to be set before sourcing.
# Effect:   If no venv is active, searches common locations relative to
#           CHECK_DIR and REPO_ROOT, and activates the first one found.
#           After return, VIRTUAL_ENV will be set if a venv was found.
#
# Note: This helper is only used for Python projects. JS/TS projects
# do not require a virtual environment — they use npx/npm instead.

if [ -z "${VIRTUAL_ENV:-}" ]; then
  for candidate in "$CHECK_DIR/.venv" "$CHECK_DIR/venv" "$REPO_ROOT/.venv" "$REPO_ROOT/venv"; do
    if [ -f "$candidate/bin/activate" ]; then
      # shellcheck disable=SC1091
      source "$candidate/bin/activate"
      break
    fi
  done
fi

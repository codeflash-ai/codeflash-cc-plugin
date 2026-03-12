#!/usr/bin/env bash
# Stop hook: ensures Claude doesn't finish without asking the user about
# codeflash configuration when a Python commit was detected but pyproject.toml
# is not yet configured. Returns decision:"block" to force Claude to continue.

set -euo pipefail

REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
FLAG_FILE="/tmp/.codeflash-needs-config-$(echo -n "$REPO_ROOT" | md5 -q 2>/dev/null || md5sum | cut -d' ' -f1)"

# No flag means no pending configuration prompt needed
if [ ! -f "$FLAG_FILE" ]; then
  exit 0
fi

# Check if pyproject.toml has been configured since the flag was set
find_pyproject_configured() {
  local search_dir="$PWD"
  while true; do
    if [ -f "$search_dir/pyproject.toml" ] && grep -q '\[tool\.codeflash\]' "$search_dir/pyproject.toml" 2>/dev/null; then
      return 0
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
  return 1
}

# If already configured, clean up the flag and let Claude stop
if find_pyproject_configured; then
  rm -f "$FLAG_FILE"
  exit 0
fi

# Remove the flag so we only block once (avoid infinite loop)
rm -f "$FLAG_FILE"

jq -nc '{
  "decision": "block",
  "reason": "Python files were changed in a recent commit but codeflash is not configured. You MUST ask the user these two questions before finishing:\n1. What is the relative path to the root of their Python module? (e.g. \".\", \"src\", \"src/mypackage\")\n2. What is the relative path to their tests folder? (e.g. \"tests\", \"test\", \"src/tests\")"
}'

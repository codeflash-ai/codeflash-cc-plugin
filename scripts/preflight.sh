#!/bin/bash
# Codeflash preflight check — verifies API key, venv, and project configuration.
# Usage: bash preflight.sh <project_dir>
set -euo pipefail

project_dir="${1:-.}"

echo "=== codeflash preflight ==="

# API key
printf "api_key="
if [ -n "${CODEFLASH_API_KEY:-}" ] && [[ "${CODEFLASH_API_KEY}" == cf-* ]]; then
  echo "ok"
else
  echo "missing"
fi

# Virtual environment
printf "venv="
echo "${VIRTUAL_ENV:-none}"

# Git root
git_root=$(git -C "$project_dir" rev-parse --show-toplevel 2>/dev/null || true)
echo "git_root=${git_root:-unknown}"

# Codeflash binary
printf "codeflash_path="
command -v codeflash 2>/dev/null || echo "not_found"

# npx codeflash (JS/TS)
printf "npx_codeflash="
npx codeflash --version 2>/dev/null || echo "not_found"

# Config files
if [ -n "$git_root" ]; then
  for f in codeflash.toml pyproject.toml package.json; do
    [ -f "$git_root/$f" ] && echo "found=$f"
  done
  grep -q '\[tool\.codeflash\]' "$git_root/pyproject.toml" 2>/dev/null && echo "python_configured=yes" || true
  grep -q '\[tool\.codeflash\]' "$git_root/codeflash.toml" 2>/dev/null && echo "java_configured=yes" || true
  python3 -c "import json; d=json.load(open('$git_root/package.json')); print('jsts_configured=yes' if 'codeflash' in d else '')" 2>/dev/null || true
fi

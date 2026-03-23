#!/bin/bash
# Wrapper to cd into a project directory and run codeflash.
# Usage: bash run-codeflash.sh <project_dir> <codeflash_binary> [args...]
# Example: bash run-codeflash.sh /path/to/project /path/.venv/bin/codeflash --subagent --file src/foo.py
set -euo pipefail

project_dir="$1"
shift

cd "$project_dir"
exec "$@"

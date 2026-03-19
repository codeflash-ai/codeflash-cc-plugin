#!/usr/bin/env bash

# Shared setup for suggest-optimize.sh bats tests

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK_SCRIPT="$SCRIPT_DIR/scripts/suggest-optimize.sh"

setup() {
  TEST_DIR="$(mktemp -d)"
  export REPO_ROOT="$TEST_DIR"
  cd "$TEST_DIR" || return 1
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Source only the function definitions (guard prevents main flow)
load_hook_functions() {
  source "$HOOK_SCRIPT"
}

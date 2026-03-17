#!/usr/bin/env bats
# Tests for scripts/find-venv.sh — Python virtual environment discovery.
#
# find-venv.sh expects CHECK_DIR and REPO_ROOT to be set.
# If VIRTUAL_ENV is already set, it does nothing.
# Otherwise it searches CHECK_DIR/{.venv,venv} then REPO_ROOT/{.venv,venv}.

load helpers/setup

setup() {
  export REPO="$BATS_TEST_TMPDIR/repo"
  export CHECK_DIR="$REPO"
  export REPO_ROOT="$REPO"
  mkdir -p "$REPO"
}

# Helper: source find-venv.sh in a subshell and print resulting VIRTUAL_ENV.
# Usage: run_find_venv [initial_virtual_env]
run_find_venv() {
  local initial_venv="${1:-}"
  (
    if [ -n "$initial_venv" ]; then
      export VIRTUAL_ENV="$initial_venv"
    else
      unset VIRTUAL_ENV
    fi
    export CHECK_DIR REPO_ROOT
    source "$FIND_VENV_SCRIPT"
    echo "${VIRTUAL_ENV:-__EMPTY__}"
  )
}

# ─────────────────────────────────────────────────────────────────────────────

@test "preserves existing VIRTUAL_ENV" {
  create_fake_venv "$REPO/.venv"

  run run_find_venv "/some/existing/venv"
  [ "$status" -eq 0 ]
  [ "$output" = "/some/existing/venv" ]
}

@test "discovers .venv in CHECK_DIR" {
  create_fake_venv "$CHECK_DIR/.venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.venv" ]]
  [ "$output" != "__EMPTY__" ]
}

@test "discovers venv/ in CHECK_DIR" {
  create_fake_venv "$CHECK_DIR/venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == */venv ]]
  [ "$output" != "__EMPTY__" ]
}

@test "prefers CHECK_DIR/.venv over CHECK_DIR/venv" {
  create_fake_venv "$CHECK_DIR/.venv"
  create_fake_venv "$CHECK_DIR/venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.venv" ]]
}

@test "discovers .venv in REPO_ROOT when CHECK_DIR has none" {
  local subdir="$REPO/src/subdir"
  mkdir -p "$subdir"
  export CHECK_DIR="$subdir"
  create_fake_venv "$REPO_ROOT/.venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.venv" ]]
  [ "$output" != "__EMPTY__" ]
}

@test "discovers venv/ in REPO_ROOT when CHECK_DIR has none" {
  local subdir="$REPO/src/subdir"
  mkdir -p "$subdir"
  export CHECK_DIR="$subdir"
  create_fake_venv "$REPO_ROOT/venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == */venv ]]
  [ "$output" != "__EMPTY__" ]
}

@test "returns empty when no venv found anywhere" {
  run run_find_venv
  [ "$status" -eq 0 ]
  [ "$output" = "__EMPTY__" ]
}
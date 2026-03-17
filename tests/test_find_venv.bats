#!/usr/bin/env bats
# Tests for scripts/find-venv.sh — Python virtual environment discovery.
#
# find-venv.sh expects CHECK_DIR and REPO_ROOT to be set before sourcing.
# If VIRTUAL_ENV is already set, it does nothing.
# Otherwise it searches these locations in order:
#   1. CHECK_DIR/.venv
#   2. CHECK_DIR/venv
#   3. REPO_ROOT/.venv
#   4. REPO_ROOT/venv
# and activates (sources bin/activate) the first one found.

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

# Setup:    VIRTUAL_ENV="/some/existing/venv" is set before sourcing.
#           A real .venv directory also exists in the repo.
# Validates: When a venv is already active (VIRTUAL_ENV is non-empty), the
#           script must not override it. Users who explicitly activated a
#           specific venv should keep using it.
# Expected: VIRTUAL_ENV remains "/some/existing/venv" (unchanged).
@test "preserves existing VIRTUAL_ENV" {
  create_fake_venv "$REPO/.venv"

  run run_find_venv "/some/existing/venv"
  [ "$status" -eq 0 ]
  [ "$output" = "/some/existing/venv" ]
}

# Setup:    VIRTUAL_ENV is unset. A fake venv exists at CHECK_DIR/.venv
#           (the project directory). CHECK_DIR == REPO_ROOT.
# Validates: The script's first search candidate is CHECK_DIR/.venv. When it
#           finds bin/activate there, it sources it, which sets VIRTUAL_ENV.
# Expected: VIRTUAL_ENV is set to the .venv path.
@test "discovers .venv in CHECK_DIR" {
  create_fake_venv "$CHECK_DIR/.venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.venv" ]]
  [ "$output" != "__EMPTY__" ]
}

# Setup:    VIRTUAL_ENV is unset. A fake venv exists at CHECK_DIR/venv
#           (the "venv" naming convention instead of ".venv").
# Validates: The script also checks the "venv" directory name (second
#           candidate in the search order).
# Expected: VIRTUAL_ENV is set to the venv path.
@test "discovers venv/ in CHECK_DIR" {
  create_fake_venv "$CHECK_DIR/venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == */venv ]]
  [ "$output" != "__EMPTY__" ]
}

# Setup:    VIRTUAL_ENV is unset. Both .venv and venv directories exist in
#           CHECK_DIR, each with a valid activate script.
# Validates: The search order is deterministic — CHECK_DIR/.venv is checked
#           before CHECK_DIR/venv. The first match wins and the loop breaks.
# Expected: VIRTUAL_ENV points to .venv (not venv).
@test "prefers CHECK_DIR/.venv over CHECK_DIR/venv" {
  create_fake_venv "$CHECK_DIR/.venv"
  create_fake_venv "$CHECK_DIR/venv"

  run run_find_venv
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.venv" ]]
}

# Setup:    VIRTUAL_ENV is unset. CHECK_DIR is a subdirectory (src/subdir)
#           with no venv. REPO_ROOT has a .venv directory.
# Validates: When CHECK_DIR has no venv candidates, the script falls back to
#           REPO_ROOT. This covers monorepo setups where the venv lives at
#           the repo root but CWD is deep in the tree.
# Expected: VIRTUAL_ENV is set to REPO_ROOT/.venv.
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

# Setup:    Same as above but REPO_ROOT has "venv/" instead of ".venv/".
# Validates: REPO_ROOT/venv is the last candidate in the search order.
# Expected: VIRTUAL_ENV is set to REPO_ROOT/venv.
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

# Setup:    VIRTUAL_ENV is unset. No .venv or venv directory exists anywhere
#           in CHECK_DIR or REPO_ROOT.
# Validates: When no venv is found after exhausting all candidates, VIRTUAL_ENV
#           must remain unset. The caller (suggest-optimize.sh) will then
#           detect this and prompt the user to create one.
# Expected: VIRTUAL_ENV is empty (__EMPTY__ sentinel).
@test "returns empty when no venv found anywhere" {
  run run_find_venv
  [ "$status" -eq 0 ]
  [ "$output" = "__EMPTY__" ]
}
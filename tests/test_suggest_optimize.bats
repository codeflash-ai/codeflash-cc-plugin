#!/usr/bin/env bats
# Integration tests for scripts/suggest-optimize.sh
#
# Each test creates an isolated git repo + transcript in $BATS_TEST_TMPDIR.
# Commits use future timestamps to guarantee they are "after" the session start
# without needing sleep.

load helpers/setup

setup() {
  setup_test_repo
}

# ═══════════════════════════════════════════════════════════════════════════════
# Early exits — hook should produce no output and exit 0
# ═══════════════════════════════════════════════════════════════════════════════

@test "exits when stop_hook_active is true" {
  add_python_commit
  create_pyproject
  create_fake_venv "$REPO/.venv"

  run run_hook true "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block
}

@test "exits when transcript_path is empty" {
  add_python_commit

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc '{transcript_path: "", stop_hook_active: false}' > "$input_file"
  cd "$REPO"
  run bash "$SUGGEST_OPTIMIZE" < "$input_file"
  assert_no_block
}

@test "exits when transcript file does not exist" {
  add_python_commit

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc --arg tp "/nonexistent/path/transcript.jsonl" \
    '{transcript_path: $tp, stop_hook_active: false}' > "$input_file"
  cd "$REPO"
  run bash "$SUGGEST_OPTIMIZE" < "$input_file"
  assert_no_block
}

@test "exits when no commits have py/js/ts files" {
  add_irrelevant_commit

  run run_hook false
  assert_no_block
}

@test "exits on second run (dedup via seen marker)" {
  add_python_commit
  create_pyproject
  create_fake_venv "$REPO/.venv"

  # First run — should block
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block

  # Second run with same commits — dedup marker exists
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block
}

@test "triggers again after a new commit (dedup hash changes)" {
  create_pyproject
  create_fake_venv "$REPO/.venv"

  add_python_commit "first.py"
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block

  # New commit changes the dedup hash
  add_python_commit "second.py"
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
}

# ═══════════════════════════════════════════════════════════════════════════════
# Python projects
# ═══════════════════════════════════════════════════════════════════════════════

@test "python: configured + codeflash installed → run codeflash" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash --subagent"
  assert_reason_contains "run_in_background"
}

@test "python: configured + codeflash NOT installed → install prompt" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" false

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "pip install codeflash"
}

@test "python: NOT configured + codeflash installed → setup prompt" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "[tool.codeflash]"
  assert_reason_contains "module-root"
}

@test "python: NOT configured + NOT installed → setup + install prompt" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv" false

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "[tool.codeflash]"
  assert_reason_contains "install codeflash"
}

@test "python: no venv + configured → create venv prompt" {
  add_python_commit
  create_pyproject true
  # No venv created, no VIRTUAL_ENV set

  run run_hook false
  assert_block
  assert_reason_contains "virtual environment"
  assert_reason_contains "python3 -m venv"
}

@test "python: no venv + NOT configured → create venv + setup prompt" {
  add_python_commit
  create_pyproject false

  run run_hook false
  assert_block
  assert_reason_contains "virtual environment"
  assert_reason_contains "python3 -m venv"
  assert_reason_contains "[tool.codeflash]"
}

@test "python: auto-discovers .venv when VIRTUAL_ENV not set" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" true
  # Don't pass VIRTUAL_ENV — script should find .venv itself

  run run_hook false
  assert_block
  assert_reason_contains "codeflash --subagent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# JavaScript / TypeScript projects
# ═══════════════════════════════════════════════════════════════════════════════

@test "js: configured + codeflash installed → run codeflash" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "npx codeflash --subagent"
  assert_reason_contains "run_in_background"
}

@test "js: configured + NOT installed → install prompt" {
  add_js_commit
  create_package_json true
  setup_mock_npx false

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "npm install --save-dev codeflash"
}

@test "js: NOT configured + installed → setup prompt" {
  add_js_commit
  create_package_json false
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "moduleRoot"
  assert_reason_contains "testsRoot"
}

@test "js: NOT configured + NOT installed → setup + install prompt" {
  add_js_commit
  create_package_json false
  setup_mock_npx false

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "moduleRoot"
  assert_reason_contains "npm install --save-dev codeflash"
}

@test "js: typescript file triggers JS path" {
  add_ts_commit "utils.ts"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "npx codeflash --subagent"
}

@test "js: jsx file triggers JS path" {
  add_js_commit "Component.jsx"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "npx codeflash --subagent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Permissions — auto-allow instructions
# ═══════════════════════════════════════════════════════════════════════════════

@test "includes auto-allow instructions when settings.json missing" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "permissions.allow"
  assert_reason_contains 'Bash(*codeflash*)'
}

@test "omits auto-allow when already configured" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"
  create_auto_allow

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_not_contains "permissions.allow"
}

@test "js: includes auto-allow instructions when settings.json missing" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "permissions.allow"
}

@test "js: omits auto-allow when already configured" {
  add_js_commit
  create_package_json true
  setup_mock_npx true
  create_auto_allow

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_not_contains "permissions.allow"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Project detection precedence
# ═══════════════════════════════════════════════════════════════════════════════

@test "pyproject.toml takes precedence over package.json in same directory" {
  add_python_commit
  create_pyproject true
  create_package_json true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  # Python path: uses bare codeflash, not npx
  assert_reason_contains "codeflash --subagent"
  assert_reason_not_contains "npx"
}

@test "detects package.json when no pyproject.toml exists" {
  add_js_commit
  # Only package.json, no pyproject.toml
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "npx codeflash --subagent"
}
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

# Setup:    Fully configured Python project with a .py commit.
#           Hook input has stop_hook_active=true.
# Validates: When Claude Code signals that the stop hook has already fired
#           (e.g., Claude already responded to a previous block), the hook
#           must exit immediately to avoid an infinite block loop.
# Expected: Exit 0, no JSON output (no block).
@test "exits when stop_hook_active is true" {
  add_python_commit
  create_pyproject
  create_fake_venv "$REPO/.venv"

  run run_hook true "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block
}

# Setup:    Git repo with a .py commit. Hook input has an empty transcript_path.
# Validates: The hook uses the transcript file's birth time to determine when
#           the session started. Without a valid path, it cannot compute session
#           start and must bail out.
# Expected: Exit 0, no JSON output.
@test "exits when transcript_path is empty" {
  add_python_commit

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc '{transcript_path: "", stop_hook_active: false}' > "$input_file"
  cd "$REPO"
  run bash "$SUGGEST_OPTIMIZE" < "$input_file"
  assert_no_block
}

# Setup:    Git repo with a .py commit. Hook input points to a transcript file
#           that does not exist on disk.
# Validates: The hook checks `[ ! -f "$TRANSCRIPT_PATH" ]` before proceeding.
#           A stale or incorrect transcript path must not cause errors.
# Expected: Exit 0, no JSON output.
@test "exits when transcript file does not exist" {
  add_python_commit

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc --arg tp "/nonexistent/path/transcript.jsonl" \
    '{transcript_path: $tp, stop_hook_active: false}' > "$input_file"
  cd "$REPO"
  run bash "$SUGGEST_OPTIMIZE" < "$input_file"
  assert_no_block
}

# Setup:    Git repo with a commit that only touches a .txt file (no .py/.js/.ts).
#           Valid transcript exists.
# Validates: The hook scans `git log` for commits touching *.py, *.js, *.ts,
#           *.jsx, *.tsx. When no matching files are found, there is nothing
#           to optimize.
# Expected: Exit 0, no JSON output.
@test "exits when no commits have py/js/ts files" {
  add_irrelevant_commit

  run run_hook false
  assert_no_block
}

# Setup:    Fully configured Python project with one .py commit.
#           Run the hook twice with the exact same commit state.
# Validates: The hook writes a dedup marker (SHA-256 of commit hashes) to
#           $TRANSCRIPT_DIR/codeflash-seen. On the second invocation with
#           identical commits, it finds the marker and skips to avoid
#           suggesting optimization twice for the same changes.
# Expected: First run blocks; second run exits silently (dedup).
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

# Setup:    Fully configured Python project. Make one commit, run hook (blocks).
#           Then make a second commit and run hook again.
# Validates: The dedup marker is a hash of all relevant commit SHAs. When a
#           new commit is added, the hash changes, so the hook correctly
#           recognizes there are new changes to optimize.
# Expected: Both runs produce a block decision.
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

# Setup:    pyproject.toml with [tool.codeflash] section. Fake venv at .venv/
#           with a mock codeflash binary. VIRTUAL_ENV pointed at the fake venv.
#           One .py file committed after session start.
# Validates: The "happy path" — everything is set up, codeflash should just run.
#           The hook instructs Claude to execute `codeflash --subagent` as a
#           background task.
# Expected: Block with reason containing "codeflash --subagent" and
#           "run_in_background".
@test "python: configured + codeflash installed → run codeflash" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash --subagent"
  assert_reason_contains "run_in_background"
}

# Setup:    pyproject.toml with [tool.codeflash]. Fake venv exists but does NOT
#           contain a codeflash binary. VIRTUAL_ENV set.
# Validates: When codeflash is configured but not installed in the venv, the
#           hook should prompt the user to install it before optimization can run.
# Expected: Block with reason containing "pip install codeflash".
@test "python: configured + codeflash NOT installed → install prompt" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" false
  local restricted_path
  restricted_path=$(not_installed_path)

  run run_hook false "VIRTUAL_ENV=$REPO/.venv" "PATH=$restricted_path"
  assert_block
  assert_reason_contains "pip install codeflash"
}

# Setup:    pyproject.toml exists but has NO [tool.codeflash] section. Fake venv
#           with codeflash binary installed. VIRTUAL_ENV set.
# Validates: When codeflash is installed but not configured, the hook should
#           instruct Claude to discover the project structure (module root,
#           tests folder) and write the [tool.codeflash] config section.
# Expected: Block with reason containing "[tool.codeflash]" and "module-root"
#           (the config fields to be written).
@test "python: NOT configured + codeflash installed → setup prompt" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "[tool.codeflash]"
  assert_reason_contains "module-root"
}

# Setup:    pyproject.toml without [tool.codeflash]. Fake venv WITHOUT codeflash
#           binary. VIRTUAL_ENV set.
# Validates: When configuration is missing, the unified hook takes the
#           NOT CONFIGURED path with per-language setup instructions.
#           The setup message includes the [tool.codeflash] config template.
# Expected: Block with reason containing "[tool.codeflash]" (config template)
#           and "module-root" (config field).
@test "python: NOT configured + NOT installed → setup prompt" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv" false

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "[tool.codeflash]"
  assert_reason_contains "module-root"
}

# Setup:    pyproject.toml with [tool.codeflash]. No .venv or venv directory
#           anywhere. VIRTUAL_ENV not set. No codeflash in PATH/uv/npx.
# Validates: The unified hook uses find_codeflash_binary which checks venv,
#           PATH, uv run, and npx. When none are found, it shows a generic
#           "not installed" message with install instructions.
# Expected: Block with reason containing "pip install codeflash".
@test "python: no venv + configured → install prompt" {
  add_python_commit
  create_pyproject true
  local restricted_path
  restricted_path=$(not_installed_path)
  # No venv created, no VIRTUAL_ENV set

  run run_hook false "PATH=$restricted_path"
  assert_block
  assert_reason_contains "pip install codeflash"
}

# Setup:    pyproject.toml WITHOUT [tool.codeflash]. No venv anywhere.
#           VIRTUAL_ENV not set.
# Validates: When nothing is set up, the unified hook takes the NOT CONFIGURED
#           path with per-language setup instructions including the config
#           template. Install is handled implicitly when the user tries to run.
# Expected: Block with reason containing "[tool.codeflash]" and "module-root".
@test "python: no venv + NOT configured → setup prompt" {
  add_python_commit
  create_pyproject false

  run run_hook false
  assert_block
  assert_reason_contains "[tool.codeflash]"
  assert_reason_contains "module-root"
}

# Setup:    pyproject.toml with [tool.codeflash]. Fake venv at $REPO/.venv with
#           codeflash binary. VIRTUAL_ENV is NOT set (not passed to env).
# Validates: The hook sources find-venv.sh which searches CHECK_DIR/.venv,
#           CHECK_DIR/venv, REPO_ROOT/.venv, REPO_ROOT/venv for an activate
#           script. It should find .venv, activate it (setting VIRTUAL_ENV),
#           and then find_codeflash_binary picks up the venv binary.
# Expected: Block with reason containing "codeflash --subagent" (same as the
#           happy path — auto-discovery is transparent).
@test "python: auto-discovers .venv when VIRTUAL_ENV not set" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" true
  # Don't pass VIRTUAL_ENV — find-venv.sh should discover .venv

  run run_hook false
  assert_block
  assert_reason_contains "codeflash --subagent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# JavaScript / TypeScript projects
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    package.json with "codeflash" config key. Mock npx that returns
#           success for `codeflash --version`. PATH includes mock bin.
#           One .js file committed after session start. No pyproject.toml.
# Validates: The JS "happy path" — package.json is configured, codeflash is
#           available. The unified hook instructs Claude to run
#           `codeflash --subagent` in the background.
# Expected: Block with reason containing "codeflash --subagent" and
#           "run_in_background".
@test "js: configured + codeflash installed → run codeflash" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash --subagent"
  assert_reason_contains "run_in_background"
}

# Setup:    package.json with "codeflash" key. Mock npx returns failure for
#           `codeflash --version` (package not installed). One .js commit.
# Validates: When codeflash is configured but the binary is not found by
#           find_codeflash_binary, the unified hook shows a generic install
#           message with "pip install codeflash".
# Expected: Block with reason containing "pip install codeflash".
@test "js: configured + NOT installed → install prompt" {
  add_js_commit
  create_package_json true
  local restricted_path
  restricted_path=$(not_installed_path)

  run run_hook false "PATH=$restricted_path"
  assert_block
  assert_reason_contains "pip install codeflash"
}

# Setup:    package.json exists but has NO "codeflash" key. Mock npx returns
#           success (codeflash is installed). One .js commit.
# Validates: When codeflash is not configured, the unified hook takes the
#           NOT CONFIGURED path and shows per-language JS/TS setup instructions
#           with the package.json config template.
# Expected: Block with reason containing "moduleRoot" and "testsRoot".
@test "js: NOT configured + installed → setup prompt" {
  add_js_commit
  create_package_json false
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "moduleRoot"
  assert_reason_contains "testsRoot"
}

# Setup:    package.json without "codeflash" key. Mock npx fails (not installed).
#           One .js commit.
# Validates: When configuration is missing, the unified hook takes the
#           NOT CONFIGURED path regardless of installation state. Shows
#           JS/TS setup instructions with config template.
# Expected: Block with reason containing "moduleRoot" and "testsRoot".
@test "js: NOT configured + NOT installed → setup prompt" {
  add_js_commit
  create_package_json false
  setup_mock_npx false

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "moduleRoot"
  assert_reason_contains "testsRoot"
}

# Setup:    Configured package.json + mock npx. Commit touches a .ts file
#           instead of .js.
# Validates: TypeScript files (*.ts) are detected by the git log filter.
#           The unified hook finds package.json config and runs codeflash.
# Expected: Block with reason containing "codeflash --subagent".
@test "js: typescript file triggers JS path" {
  add_ts_commit "utils.ts"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash --subagent"
}

# Setup:    Configured package.json + mock npx. Commit touches a .jsx file.
# Validates: JSX files (*.jsx) are also detected by the git log filter
#           (-- '*.jsx'). The unified hook finds package.json config and
#           runs codeflash.
# Expected: Block with reason containing "codeflash --subagent".
@test "js: jsx file triggers JS path" {
  add_js_commit "Component.jsx"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash --subagent"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Permissions — auto-allow instructions
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    Fully configured Python project. No .claude/settings.json exists.
# Validates: When codeflash is not yet auto-allowed, the hook appends
#           instructions telling Claude to add `Bash(*codeflash*)` to the
#           permissions.allow array in .claude/settings.json. This enables
#           future runs to execute without user permission prompts.
# Expected: Block reason contains "permissions.allow" and "Bash(*codeflash*)".
@test "includes auto-allow instructions when settings.json missing" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv" "CODEFLASH_API_KEY=cf-test-key"
  assert_block
  assert_reason_contains "permissions.allow"
  assert_reason_contains 'Bash(*codeflash*)'
}

# Setup:    Fully configured Python project. .claude/settings.json exists and
#           already has "Bash(*codeflash*)" in permissions.allow.
# Validates: When auto-allow is already configured, the hook should NOT include
#           the permissions setup instructions. The message should only contain
#           the "run codeflash" instruction.
# Expected: Block reason does NOT contain "permissions.allow".
@test "omits auto-allow when already configured" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"
  create_auto_allow

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_not_contains "permissions.allow"
}

# Setup:    Fully configured JS project. No .claude/settings.json exists.
# Validates: The unified hook appends auto-allow instructions when
#           .claude/settings.json doesn't have codeflash permitted.
# Expected: Block reason contains "permissions.allow".
@test "js: includes auto-allow instructions when settings.json missing" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "permissions.allow"
}

# Setup:    Fully configured JS project. .claude/settings.json has
#           "Bash(*codeflash*)" in permissions.allow.
# Validates: Unified hook correctly omits auto-allow instructions when already set.
# Expected: Block reason does NOT contain "permissions.allow".
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

# Setup:    BOTH pyproject.toml (with [tool.codeflash]) and package.json (with
#           "codeflash" key) exist in the same directory. Fake venv with
#           codeflash installed. One .py commit.
# Validates: The unified detect_any_config finds both configs. When the project
#           is configured, find_codeflash_binary locates the venv binary.
#           The hook fires a single `codeflash --subagent` — the CLI handles
#           multi-language dispatch.
# Expected: Block with "codeflash --subagent" and "run_in_background".
@test "pyproject.toml takes precedence over package.json in same directory" {
  add_python_commit
  create_pyproject true
  create_package_json true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash --subagent"
}

# Setup:    Only package.json exists (no pyproject.toml). Configured with
#           "codeflash" key. Mock npx available. One .js commit.
# Validates: When pyproject.toml is absent, detect_any_config correctly finds
#           package.json. The unified hook runs codeflash --subagent.
# Expected: Block with "codeflash --subagent".
@test "detects package.json when no pyproject.toml exists" {
  add_js_commit
  # Only package.json, no pyproject.toml
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash --subagent"
}
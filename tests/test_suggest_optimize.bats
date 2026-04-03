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
# Between-sessions detection — commits made before a new session starts
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    Fully configured Python project. Session A runs the hook (caching HEAD).
#           A new commit is made. Session B starts (new transcript, born AFTER the
#           commit). Session B's hook runs.
# Validates: When a user makes a commit in another terminal between sessions,
#           the hook uses the cached PREV_HEAD..HEAD range (not --after=session_start)
#           to detect the commit even though it predates Session B's transcript.
# Expected: Session B blocks with optimization suggestion.
@test "detects commit made between sessions (before new session starts)" {
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  # Session A: run hook to cache HEAD
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block

  # User makes commit (uses future timestamp to be after session A)
  add_python_commit "app.py"

  # Session B: new transcript file (born AFTER the commit, via future_timestamp trick)
  local session_b_transcript="$TRANSCRIPT_DIR/session_b.jsonl"
  touch "$session_b_transcript"

  # Session B's hook should detect the commit via PREV_HEAD..HEAD range
  run run_hook_with_transcript "$session_b_transcript" false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash"
}

# Setup:    Same as above but the between-sessions commit is a non-target file (.txt).
# Validates: The PREV_HEAD..HEAD range still correctly filters by file extension.
# Expected: No block (commit has no target-language files).
@test "ignores non-target between-sessions commit" {
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  # Session A
  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block

  # Non-target commit
  add_irrelevant_commit "notes.txt"

  # Session B
  local session_b_transcript="$TRANSCRIPT_DIR/session_b.jsonl"
  touch "$session_b_transcript"

  run run_hook_with_transcript "$session_b_transcript" false "VIRTUAL_ENV=$REPO/.venv"
  assert_no_block
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
# Expected: Block with reason containing "codeflash:optimize".
@test "python: configured + codeflash installed → run codeflash" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml with [tool.codeflash]. Fake venv exists but does NOT
#           contain a codeflash binary. VIRTUAL_ENV set.
# Validates: The simplified hook delegates all setup/install logic to the
#           codeflash:optimize skill. Regardless of installation state, the
#           hook should block and point to the skill.
# Expected: Block with reason containing "codeflash:optimize".
@test "python: configured + codeflash NOT installed → delegates to skill" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" false

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml exists but has NO [tool.codeflash] section. Fake venv
#           with codeflash binary installed. VIRTUAL_ENV set.
# Validates: The hook no longer checks configuration state — it delegates to
#           the skill which handles setup fallback internally.
# Expected: Block with reason containing "codeflash:optimize".
@test "python: NOT configured + codeflash installed → delegates to skill" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml without [tool.codeflash]. Fake venv WITHOUT codeflash
#           binary. VIRTUAL_ENV set.
# Validates: Even when both installation and configuration are missing, the hook
#           delegates to the skill (which handles setup fallback).
# Expected: Block with reason containing "codeflash:optimize".
@test "python: NOT configured + NOT installed → delegates to skill" {
  add_python_commit
  create_pyproject false
  create_fake_venv "$REPO/.venv" false

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml with [tool.codeflash]. No .venv or venv directory
#           anywhere. VIRTUAL_ENV not set.
# Validates: The simplified hook no longer inspects venv state — it just detects
#           Python file changes and delegates to the skill.
# Expected: Block with reason containing "codeflash:optimize".
@test "python: no venv + configured → delegates to skill" {
  add_python_commit
  create_pyproject true
  # No venv created, no VIRTUAL_ENV set

  run run_hook false
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml WITHOUT [tool.codeflash]. No venv anywhere.
#           VIRTUAL_ENV not set.
# Validates: Same as above — hook delegates regardless of project state.
# Expected: Block with reason containing "codeflash:optimize".
@test "python: no venv + NOT configured → delegates to skill" {
  add_python_commit
  create_pyproject false

  run run_hook false
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    pyproject.toml with [tool.codeflash]. Fake venv at $REPO/.venv with
#           codeflash binary. VIRTUAL_ENV is NOT set (not passed to env).
# Validates: The hook sources find-venv.sh which searches CHECK_DIR/.venv,
#           CHECK_DIR/venv, REPO_ROOT/.venv, REPO_ROOT/venv for an activate
#           script. It should find .venv, activate it (setting VIRTUAL_ENV),
#           and then proceed as if the venv was active from the start.
# Expected: Block with reason containing "codeflash:optimize" (same as the
#           happy path — auto-discovery is transparent).
@test "python: auto-discovers .venv when VIRTUAL_ENV not set" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv" true
  # Don't pass VIRTUAL_ENV — script should find .venv itself

  run run_hook false
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# ═══════════════════════════════════════════════════════════════════════════════
# JavaScript / TypeScript projects
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    package.json with "codeflash" config key. Mock npx that returns
#           success for `codeflash --version`. PATH includes mock bin.
#           One .js file committed after session start. No pyproject.toml.
# Validates: The JS "happy path" — package.json is configured, codeflash npm
#           package is available via npx. The hook instructs Claude to run
#           `npx codeflash --subagent` in the background.
# Expected: Block with reason containing "codeflash:optimize".
@test "js: configured + codeflash installed → run codeflash" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    package.json with "codeflash" key. Mock npx returns failure for
#           `codeflash --version` (package not installed). One .js commit.
# Validates: The simplified hook delegates all setup/install logic to the
#           codeflash:optimize skill regardless of installation state.
# Expected: Block with reason containing "codeflash:optimize".
@test "js: configured + NOT installed → delegates to skill" {
  add_js_commit
  create_package_json true
  setup_mock_npx false

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    package.json exists but has NO "codeflash" key. Mock npx returns
#           success (codeflash is installed). One .js commit.
# Validates: The hook no longer checks configuration state — it delegates to
#           the skill which handles setup fallback internally.
# Expected: Block with reason containing "codeflash:optimize".
@test "js: NOT configured + installed → delegates to skill" {
  add_js_commit
  create_package_json false
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    package.json without "codeflash" key. Mock npx fails (not installed).
#           One .js commit.
# Validates: Even when both installation and configuration are missing, the hook
#           delegates to the skill (which handles setup fallback).
# Expected: Block with reason containing "codeflash:optimize".
@test "js: NOT configured + NOT installed → delegates to skill" {
  add_js_commit
  create_package_json false
  setup_mock_npx false

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    Configured package.json + mock npx. Commit touches a .ts file
#           instead of .js.
# Validates: TypeScript files (*.ts) are detected by the git log filter and
#           route through the JS project path (since package.json is the
#           project config). The hook should treat .ts the same as .js.
# Expected: Block with reason containing "codeflash:optimize".
@test "js: typescript file triggers JS path" {
  add_ts_commit "utils.ts"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# Setup:    Configured package.json + mock npx. Commit touches a .jsx file.
# Validates: JSX files (*.jsx) are also detected by the git log filter
#           (-- '*.jsx') and processed via the JS path. Ensures React
#           component files trigger optimization.
# Expected: Block with reason containing "codeflash:optimize".
@test "js: jsx file triggers JS path" {
  add_js_commit "Component.jsx"
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Java projects
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    One .java file committed after session start.
# Validates: The hook detects Java file changes and produces a block decision
#           pointing to the codeflash:optimize skill.
# Expected: Block with reason containing "codeflash:optimize" and "Java".
@test "java: .java commit triggers Java path" {
  add_java_commit

  run run_hook false
  assert_block
  assert_reason_contains "codeflash:optimize"
  assert_reason_contains "Java"
}

# Setup:    One .java file committed. Run the hook twice.
# Validates: Dedup logic works for Java commits (same as Python/JS).
# Expected: First run blocks; second run exits silently.
@test "java: dedup prevents double trigger" {
  add_java_commit

  run run_hook false
  assert_block

  run run_hook false
  assert_no_block
}

# Setup:    One .java file committed. Verify the message does NOT mention JS/TS
#           or Python — it should be Java-specific.
# Validates: Java commits route through the Java branch, not JS or Python.
# Expected: Block reason contains "Java", not "JS/TS" or "Python".
@test "java: message is Java-specific, not JS or Python" {
  add_java_commit

  run run_hook false
  assert_block
  assert_reason_contains "Java"
  assert_reason_not_contains "JS/TS"
  assert_reason_not_contains "Python"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Permissions — auto-allow instructions
# ═══════════════════════════════════════════════════════════════════════════════

# Setup:    Fully configured Python project. No .claude/settings.json exists.
# Validates: Auto-allow instructions are currently disabled (commented out in
#           the script). The hook should still block but NOT include
#           permissions.allow instructions.
# Expected: Block reason does NOT contain "permissions.allow".
@test "omits auto-allow instructions when settings.json missing (feature disabled)" {
  add_python_commit
  create_pyproject true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv" "CODEFLASH_API_KEY=cf-test-key"
  assert_block
  assert_reason_not_contains "permissions.allow"
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
# Validates: Auto-allow instructions are currently disabled (commented out in
#           the script). The hook should still block but NOT include
#           permissions.allow instructions.
# Expected: Block reason does NOT contain "permissions.allow".
@test "js: omits auto-allow instructions when settings.json missing (feature disabled)" {
  add_js_commit
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_not_contains "permissions.allow"
}

# Setup:    Fully configured JS project. .claude/settings.json has
#           "Bash(*codeflash*)" in permissions.allow.
# Validates: JS path correctly omits auto-allow instructions when already set.
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
# Validates: The detect_project function checks pyproject.toml before
#           package.json at each directory level. When both exist, the Python
#           path should be chosen. This ensures Python projects with a
#           package.json (e.g., for JS tooling) don't accidentally take the
#           JS path.
# Expected: Block with "Python files" (Python-style) and
#           NOT "JS/TS" (which would indicate the JS path).
@test "pyproject.toml takes precedence over package.json in same directory" {
  add_python_commit
  create_pyproject true
  create_package_json true
  create_fake_venv "$REPO/.venv"

  run run_hook false "VIRTUAL_ENV=$REPO/.venv"
  assert_block
  # Python path: message mentions Python, not JS/TS
  assert_reason_contains "Python"
  assert_reason_not_contains "JS/TS"
}

# Setup:    Only package.json exists (no pyproject.toml). Configured with
#           "codeflash" key. Mock npx available. One .js commit.
# Validates: When pyproject.toml is absent, detect_project correctly falls
#           through to package.json and identifies the project as JS/TS.
# Expected: Block with "JS/TS" and "codeflash:optimize" (JS-style path).
@test "detects package.json when no pyproject.toml exists" {
  add_js_commit
  # Only package.json, no pyproject.toml
  create_package_json true
  setup_mock_npx true

  run run_hook false "PATH=$MOCK_BIN:$PATH"
  assert_block
  assert_reason_contains "codeflash:optimize"
}
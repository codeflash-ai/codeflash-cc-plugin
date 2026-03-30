#!/usr/bin/env bash
# Shared test helpers for codeflash-cc-plugin tests

PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SUGGEST_OPTIMIZE="$PLUGIN_ROOT/scripts/suggest-optimize.sh"
FIND_VENV_SCRIPT="$PLUGIN_ROOT/scripts/find-venv.sh"

# ---------------------------------------------------------------------------
# Repo & session setup
# ---------------------------------------------------------------------------

# Create a minimal git repo with an initial commit (no py/js files)
# and a transcript file representing the session start.
# Sets: REPO, TRANSCRIPT_DIR, TRANSCRIPT, MOCK_BIN
setup_test_repo() {
  export REPO="$BATS_TEST_TMPDIR/repo"
  export TRANSCRIPT_DIR="$BATS_TEST_TMPDIR/session"
  export TRANSCRIPT="$TRANSCRIPT_DIR/transcript.jsonl"
  export MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"

  mkdir -p "$REPO" "$TRANSCRIPT_DIR" "$MOCK_BIN"

  git init "$REPO" >/dev/null 2>&1
  git -C "$REPO" config user.email "test@test.com"
  git -C "$REPO" config user.name "Test"

  echo "# Test project" > "$REPO/README.md"
  git -C "$REPO" add -A >/dev/null 2>&1
  git -C "$REPO" commit -m "initial commit" >/dev/null 2>&1

  # Transcript file — its mtime (or birth time) marks "session start"
  touch "$TRANSCRIPT"
}

# ---------------------------------------------------------------------------
# Portable timestamp helpers
# ---------------------------------------------------------------------------

# Returns a Unix timestamp 60 seconds in the future.
# Commits created with this timestamp will always be "after" the session start.
future_timestamp() {
  if [[ "$(uname)" == "Darwin" ]]; then
    date -v+60S +%s
  else
    date -d '60 seconds' +%s
  fi
}

# ---------------------------------------------------------------------------
# Commit helpers (use future timestamps to avoid needing sleep)
# ---------------------------------------------------------------------------

add_python_commit() {
  local file="${1:-app.py}"
  mkdir -p "$REPO/$(dirname "$file")"
  echo "x = 1" > "$REPO/$file"
  git -C "$REPO" add -A >/dev/null 2>&1
  local ts
  ts=$(future_timestamp)
  GIT_COMMITTER_DATE="@$ts" GIT_AUTHOR_DATE="@$ts" \
    git -C "$REPO" commit -m "add $file" >/dev/null 2>&1
}

add_js_commit() {
  local file="${1:-app.js}"
  mkdir -p "$REPO/$(dirname "$file")"
  echo "const x = 1;" > "$REPO/$file"
  git -C "$REPO" add -A >/dev/null 2>&1
  local ts
  ts=$(future_timestamp)
  GIT_COMMITTER_DATE="@$ts" GIT_AUTHOR_DATE="@$ts" \
    git -C "$REPO" commit -m "add $file" >/dev/null 2>&1
}

add_ts_commit() {
  local file="${1:-app.ts}"
  mkdir -p "$REPO/$(dirname "$file")"
  echo "const x: number = 1;" > "$REPO/$file"
  git -C "$REPO" add -A >/dev/null 2>&1
  local ts
  ts=$(future_timestamp)
  GIT_COMMITTER_DATE="@$ts" GIT_AUTHOR_DATE="@$ts" \
    git -C "$REPO" commit -m "add $file" >/dev/null 2>&1
}

add_irrelevant_commit() {
  local file="${1:-data.txt}"
  echo "some data" > "$REPO/$file"
  git -C "$REPO" add -A >/dev/null 2>&1
  local ts
  ts=$(future_timestamp)
  GIT_COMMITTER_DATE="@$ts" GIT_AUTHOR_DATE="@$ts" \
    git -C "$REPO" commit -m "add $file" >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Project configuration helpers
# ---------------------------------------------------------------------------

# Create a fake Python venv with an activate script.
# Usage: create_fake_venv /path/to/venv [with_codeflash=true]
create_fake_venv() {
  local venv_dir="$1"
  local with_codeflash="${2:-true}"

  mkdir -p "$venv_dir/bin"
  local abs_venv
  abs_venv="$(cd "$venv_dir" && pwd)"

  # Minimal activate script — just sets VIRTUAL_ENV and PATH
  cat > "$venv_dir/bin/activate" << ACTIVATE
export VIRTUAL_ENV="$abs_venv"
export PATH="\$VIRTUAL_ENV/bin:\$PATH"
ACTIVATE

  if [ "$with_codeflash" = "true" ]; then
    cat > "$venv_dir/bin/codeflash" << 'BIN'
#!/bin/bash
echo "codeflash 0.1.0"
exit 0
BIN
    chmod +x "$venv_dir/bin/codeflash"
  fi
}

# Create pyproject.toml. configured=true adds [tool.codeflash].
create_pyproject() {
  local configured="${1:-true}"
  if [ "$configured" = "true" ]; then
    cat > "$REPO/pyproject.toml" << 'EOF'
[project]
name = "test-project"

[tool.codeflash]
module-root = "src"
tests-root = "tests"
ignore-paths = []
formatter-cmds = ["disabled"]
EOF
  else
    cat > "$REPO/pyproject.toml" << 'EOF'
[project]
name = "test-project"
EOF
  fi
  git -C "$REPO" add -A >/dev/null 2>&1
  git -C "$REPO" commit -m "add pyproject.toml" --allow-empty >/dev/null 2>&1
}

# Create package.json. configured=true adds "codeflash" key.
create_package_json() {
  local configured="${1:-true}"
  if [ "$configured" = "true" ]; then
    cat > "$REPO/package.json" << 'EOF'
{
  "name": "test-project",
  "codeflash": {
    "moduleRoot": "src",
    "testsRoot": "tests",
    "formatterCmds": ["disabled"],
    "ignorePaths": ["dist"]
  }
}
EOF
  else
    cat > "$REPO/package.json" << 'EOF'
{
  "name": "test-project"
}
EOF
  fi
  git -C "$REPO" add -A >/dev/null 2>&1
  git -C "$REPO" commit -m "add package.json" --allow-empty >/dev/null 2>&1
}

# Create .claude/settings.json with Bash(*codeflash*) auto-allowed
create_auto_allow() {
  mkdir -p "$REPO/.claude"
  cat > "$REPO/.claude/settings.json" << 'EOF'
{
  "permissions": {
    "allow": ["Bash(*codeflash*)"]
  }
}
EOF
}

# ---------------------------------------------------------------------------
# Mock npx for JS/TS tests
# ---------------------------------------------------------------------------

# Create a mock npx binary in MOCK_BIN.
# Usage: setup_mock_npx [installed=true]
setup_mock_npx() {
  local installed="${1:-true}"
  mkdir -p "$MOCK_BIN"

  if [ "$installed" = "true" ]; then
    cat > "$MOCK_BIN/npx" << 'MOCK'
#!/bin/bash
if [[ "$1" == "codeflash" ]]; then
  echo "codeflash 0.1.0"
  exit 0
fi
exit 127
MOCK
  else
    cat > "$MOCK_BIN/npx" << 'MOCK'
#!/bin/bash
if [[ "$1" == "codeflash" ]]; then
  exit 1
fi
exit 127
MOCK
  fi
  chmod +x "$MOCK_BIN/npx"
}

# ---------------------------------------------------------------------------
# Hook runner
# ---------------------------------------------------------------------------

# Run suggest-optimize.sh with controlled environment.
# Usage: run_hook <stop_active> [ENV_VAR=value ...]
#   stop_active: "true" or "false" (JSON boolean for stop_hook_active)
#   remaining args: passed to env (e.g. VIRTUAL_ENV=/path, PATH=...)
#
# Always unsets VIRTUAL_ENV unless explicitly re-set via args.
run_hook() {
  local stop_active="${1:-false}"
  shift || true

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc \
    --arg tp "$TRANSCRIPT" \
    --argjson sa "$stop_active" \
    '{transcript_path: $tp, stop_hook_active: $sa}' > "$input_file"

  cd "$REPO"
  env -u VIRTUAL_ENV "$@" bash "$SUGGEST_OPTIMIZE" < "$input_file"
}

# Run hook with a custom transcript path (for multi-session tests).
# Usage: run_hook_with_transcript <transcript_path> <stop_active> [ENV_VAR=value ...]
run_hook_with_transcript() {
  local transcript="$1"
  local stop_active="${2:-false}"
  shift 2 || true

  local input_file="$BATS_TEST_TMPDIR/hook_input.json"
  jq -nc \
    --arg tp "$transcript" \
    --argjson sa "$stop_active" \
    '{transcript_path: $tp, stop_hook_active: $sa}' > "$input_file"

  cd "$REPO"
  env -u VIRTUAL_ENV "$@" bash "$SUGGEST_OPTIMIZE" < "$input_file"
}

# ---------------------------------------------------------------------------
# Assertions
# ---------------------------------------------------------------------------

assert_block() {
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  local decision
  decision=$(echo "$output" | jq -r '.decision')
  [ "$decision" = "block" ]
}

assert_no_block() {
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

assert_reason_contains() {
  local expected="$1"
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  if [[ "$reason" != *"$expected"* ]]; then
    echo "Expected reason to contain: $expected" >&2
    echo "Actual reason: $reason" >&2
    return 1
  fi
}

assert_reason_not_contains() {
  local unexpected="$1"
  local reason
  reason=$(echo "$output" | jq -r '.reason')
  if [[ "$reason" == *"$unexpected"* ]]; then
    echo "Expected reason NOT to contain: $unexpected" >&2
    echo "Actual reason: $reason" >&2
    return 1
  fi
}
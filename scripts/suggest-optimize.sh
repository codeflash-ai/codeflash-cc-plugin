#!/usr/bin/env bash
# Stop hook: detect new Python/Java/JS/TS commits since the session started and ask the
# user if they'd like to run codeflash to optimize their code.
# Fires when Claude is about to finish its response.

set -euo pipefail

LOGFILE="/tmp/codeflash-hook-debug.log"
exec 2>>"$LOGFILE"
set -x

# ---- Helper functions (above BASH_SOURCE guard for testability) ----

get_file_birth_time() {
  local file="$1"
  if [[ "$(uname)" == "Darwin" ]]; then
    stat -f %B "$file"
  else
    local btime
    btime=$(stat -c %W "$file" 2>/dev/null || echo "0")
    if [ "$btime" = "0" ] || [ -z "$btime" ]; then
      stat -c %Y "$file"
    else
      echo "$btime"
    fi
  fi
}

# Walk from $PWD upward to $REPO_ROOT checking ALL config types at each level.
# Sets: PROJECT_CONFIGURED, FOUND_CONFIGS (space-separated), PROJECT_DIR
detect_any_config() {
  PROJECT_CONFIGURED="false"
  FOUND_CONFIGS=""
  PROJECT_DIR=""
  local search_dir="$PWD"
  while true; do
    # Check codeflash.toml (Java projects)
    if [ -f "$search_dir/codeflash.toml" ]; then
      if grep -q '\[tool\.codeflash\]' "$search_dir/codeflash.toml" 2>/dev/null; then
        PROJECT_CONFIGURED="true"
        FOUND_CONFIGS="${FOUND_CONFIGS:+$FOUND_CONFIGS }codeflash.toml"
        [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$search_dir"
      fi
    fi
    # Check pyproject.toml (Python projects)
    if [ -f "$search_dir/pyproject.toml" ]; then
      if grep -q '\[tool\.codeflash\]' "$search_dir/pyproject.toml" 2>/dev/null; then
        PROJECT_CONFIGURED="true"
        FOUND_CONFIGS="${FOUND_CONFIGS:+$FOUND_CONFIGS }pyproject.toml"
        [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$search_dir"
      fi
    fi
    # Check package.json (JS/TS projects)
    if [ -f "$search_dir/package.json" ]; then
      if jq -e '.codeflash' "$search_dir/package.json" >/dev/null 2>&1; then
        PROJECT_CONFIGURED="true"
        FOUND_CONFIGS="${FOUND_CONFIGS:+$FOUND_CONFIGS }package.json"
        [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$search_dir"
      fi
    fi
    # Check Java build files (zero-config: pom.xml/build.gradle are sufficient)
    if [ -f "$search_dir/pom.xml" ] || [ -f "$search_dir/build.gradle" ] || [ -f "$search_dir/build.gradle.kts" ]; then
      PROJECT_CONFIGURED="true"
      FOUND_CONFIGS="${FOUND_CONFIGS:+$FOUND_CONFIGS }java-build-file"
      [ -z "$PROJECT_DIR" ] && PROJECT_DIR="$search_dir"
    fi
    # Move to parent directory
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
}

# Unified binary resolution: venv -> PATH -> uv run -> npx
# Sets: CODEFLASH_BIN, CODEFLASH_INSTALLED
find_codeflash_binary() {
  CODEFLASH_BIN=""
  CODEFLASH_INSTALLED="false"
  # a. Active venv
  if [ -n "${VIRTUAL_ENV:-}" ] && [ -x "${VIRTUAL_ENV}/bin/codeflash" ]; then
    CODEFLASH_BIN="${VIRTUAL_ENV}/bin/codeflash"
    CODEFLASH_INSTALLED="true"
    return
  fi
  # b. PATH
  if command -v codeflash >/dev/null 2>&1; then
    CODEFLASH_BIN="codeflash"
    CODEFLASH_INSTALLED="true"
    return
  fi
  # c. uv run
  if uv run codeflash --version >/dev/null 2>&1; then
    CODEFLASH_BIN="uv run codeflash"
    CODEFLASH_INSTALLED="true"
    return
  fi
  # d. npx
  if npx codeflash --version >/dev/null 2>&1; then
    CODEFLASH_BIN="npx codeflash"
    CODEFLASH_INSTALLED="true"
    return
  fi
}

# Parse changed files to detect which languages have changes.
# Sets: CHANGED_LANGS (space-separated: python java javascript)
detect_changed_languages() {
  CHANGED_LANGS=""
  if echo "$CHANGED_FILES" | grep -q '\.py$'; then
    CHANGED_LANGS="python"
  fi
  if echo "$CHANGED_FILES" | grep -q '\.java$'; then
    CHANGED_LANGS="${CHANGED_LANGS:+$CHANGED_LANGS }java"
  fi
  if echo "$CHANGED_FILES" | grep -qE '\.(js|ts|jsx|tsx)$'; then
    CHANGED_LANGS="${CHANGED_LANGS:+$CHANGED_LANGS }javascript"
  fi
}

# Check if CODEFLASH_API_KEY is available in env or shell RC files
has_api_key() {
  # Check env var
  if [ -n "${CODEFLASH_API_KEY:-}" ] && [[ "${CODEFLASH_API_KEY}" == cf-* ]]; then
    return 0
  fi
  # Check Unix shell RC files
  for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.profile" "$HOME/.kshrc" "$HOME/.cshrc"; do
    if [ -f "$rc" ] && grep -q '^export CODEFLASH_API_KEY="cf-' "$rc" 2>/dev/null; then
      return 0
    fi
  done
  # Check Windows-specific files (PowerShell / CMD, matching codeflash CLI)
  for rc in "$HOME/codeflash_env.ps1" "$HOME/codeflash_env.bat"; do
    if [ -f "$rc" ] && grep -q 'CODEFLASH_API_KEY.*cf-' "$rc" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# ---- BASH_SOURCE guard: everything below only runs when executed, not sourced ----
if [[ "${BASH_SOURCE[0]}" != "${0}" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Read stdin (Stop hook pipes context as JSON via stdin)
INPUT=$(cat)

# If the stop hook is already active (Claude already responded to a previous block),
# allow the stop to proceed to avoid an infinite block loop.
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null || echo "false")
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  exit 0
fi

## Per-project tracker keyed on repo root (resolve symlinks so PWD and REPO_ROOT share a prefix)
REPO_ROOT=$(cd "$(git rev-parse --show-toplevel 2>/dev/null)" && pwd -P) || exit 0
cd "$(pwd -P)"

# --- Check if codeflash is already auto-allowed in .claude/settings.json ---
CODEFLASH_AUTO_ALLOWED="false"
SETTINGS_JSON="$REPO_ROOT/.claude/settings.json"
if [ -f "$SETTINGS_JSON" ]; then
  if jq -e '.permissions.allow // [] | any(test("codeflash"))' "$SETTINGS_JSON" >/dev/null 2>&1; then
    CODEFLASH_AUTO_ALLOWED="true"
  fi
fi

# --- Detect new commits with Python/Java/JS/TS files since session started ---

# Extract transcript_path from hook input to determine session start time
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)
if [ -z "$TRANSCRIPT_PATH" ] || [ ! -f "$TRANSCRIPT_PATH" ]; then
  exit 0
fi
TRANSCRIPT_DIR=$(dirname "$TRANSCRIPT_PATH")

# --- Cheap gate: skip if HEAD hasn't changed since last check ---
CURRENT_HEAD=$(git rev-parse HEAD 2>/dev/null) || exit 0
LAST_HEAD_FILE="$TRANSCRIPT_DIR/codeflash-last-head"
PREV_HEAD=""
if [ -f "$LAST_HEAD_FILE" ]; then
  PREV_HEAD=$(cat "$LAST_HEAD_FILE")
  if [ "$PREV_HEAD" = "$CURRENT_HEAD" ]; then
    exit 0
  fi
fi
echo "$CURRENT_HEAD" > "$LAST_HEAD_FILE"

# --- Find new commits with target-language files ---
# Strategy: when a previous HEAD is cached (from a prior hook invocation), use
# `git log PREV_HEAD..HEAD` to catch commits made both *during* and *between*
# sessions. Fall back to transcript-birth-time-based detection only on the very
# first invocation (no cached HEAD yet).

COMMIT_RANGE_ARGS=()
if [ -n "$PREV_HEAD" ] && git merge-base --is-ancestor "$PREV_HEAD" "$CURRENT_HEAD" 2>/dev/null; then
  # PREV_HEAD is an ancestor of current HEAD — use the range
  COMMIT_RANGE_ARGS=("$PREV_HEAD..$CURRENT_HEAD")
else
  # First run or history rewritten (rebase/force-push) — fall back to session start time
  SESSION_START=$(get_file_birth_time "$TRANSCRIPT_PATH")
  if [ -z "$SESSION_START" ] || [ "$SESSION_START" = "0" ]; then
    exit 0
  fi
  COMMIT_RANGE_ARGS=("--after=@$SESSION_START")
fi

CHANGED_FILES=$(git log "${COMMIT_RANGE_ARGS[@]}" --name-only --diff-filter=ACMR --pretty=format: -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | sort -u | grep -v '^$' || true)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Dedup: don't trigger twice for the same set of changes.
SEEN_MARKER="$TRANSCRIPT_DIR/codeflash-seen"

COMMIT_HASH=$(git log "${COMMIT_RANGE_ARGS[@]}" --pretty=format:%H -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
if [ -f "$SEEN_MARKER" ] && grep -qF "$COMMIT_HASH" "$SEEN_MARKER" 2>/dev/null; then
  exit 0
fi
echo "$COMMIT_HASH" >> "$SEEN_MARKER"

# --- From here on, we know there are new commits to optimize ---

# OAuth login script path
OAUTH_SCRIPT="$(dirname "$0")/oauth-login.sh"

LOGIN_STEP=""
if ! has_api_key; then
  LOGIN_STEP="
- Run \`${OAUTH_SCRIPT}\` to log in to Codeflash. If it exits with code 0, the key is saved. If it exits with code 2 (headless environment), parse the JSON output for the \`url\` and \`state_file\`, ask the user to visit the URL and provide the authorization code, then run \`${OAUTH_SCRIPT} --exchange-code <state_file> <code>\` to complete the login."
fi

# ---- Main flow ----

detect_any_config

# Source find-venv.sh for Python venv detection (requires CHECK_DIR and REPO_ROOT)
CHECK_DIR="${PROJECT_DIR:-$PWD}"
# shellcheck disable=SC1091
source "$(dirname "$0")/find-venv.sh"

if [ "$PROJECT_CONFIGURED" = "true" ]; then
  find_codeflash_binary

  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    # Show install instructions (language-agnostic)
    INSTALL_MSG="Code was changed in a recent commit, but codeflash is not installed.
${LOGIN_STEP}
Install codeflash to optimize your code for performance:

  pip install codeflash

Then run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."

    # Append auto-allow if needed
    if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
      INSTALL_MSG="${INSTALL_MSG}

Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
    fi

    jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason}'
    exit 0
  fi

  # Check for API key before running codeflash
  if ! has_api_key; then
    LOGIN_MSG="Code was changed in a recent commit, but no Codeflash API key was found.

Run \`${OAUTH_SCRIPT}\` to log in to Codeflash. If it exits with code 0, the key is saved. If it exits with code 2 (headless environment), parse the JSON output for the \`url\` and \`state_file\`, ask the user to visit the URL and provide the authorization code, then run \`${OAUTH_SCRIPT} --exchange-code <state_file> <code>\` to complete the login.

After login, run \`codeflash --subagent\` as a background Bash task (run_in_background: true) to optimize the code."

    jq -nc --arg reason "$LOGIN_MSG" '{"decision": "block", "reason": $reason}'
    exit 0
  fi

  # Build run command
  if [ -n "$PROJECT_DIR" ] && [ "$PROJECT_DIR" != "$PWD" ]; then
    RUN_CMD="cd $PROJECT_DIR && $CODEFLASH_BIN --subagent"
  else
    RUN_CMD="$CODEFLASH_BIN --subagent"
  fi

  MESSAGE="Code was changed in a recent commit. Run \`${RUN_CMD}\` as a background Bash task (run_in_background: true) to optimize the code for performance."

  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
    MESSAGE="${MESSAGE}

Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
  fi

  jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# --- NOT CONFIGURED path: language-aware setup instructions ---
detect_changed_languages

for LANG in $CHANGED_LANGS; do
  # Build per-language setup message
  case "$LANG" in
    python)
      SETUP_MSG="Python files were changed in a recent commit, but codeflash is not configured yet.

Set up codeflash to optimize the Python code for performance. Automatically determine the following by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user -- discover the correct paths yourself):
${LOGIN_STEP}
1. The relative path with respect to pyproject.toml to the root of the Python module -- the module root is where tests import from. for example, if the module root is abc/ then the tests would be importing code as \`from abc import xyz\`.
2. The relative path with respect to pyproject.toml to the tests folder -- look for existing directories named \`tests\` or \`test\`, or folders containing files that start with \`test_\`. If none exist, default to \`tests\`.

Once determined:
- If the tests folder does not exist, create it with mkdir -p.
- Create or update \`pyproject.toml\` adding the following section with the discovered values substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

Once the configuration is written, run \`codeflash --subagent\` as a background Bash task (run_in_background: true)."
      ;;
    java)
      SETUP_MSG="Java files were changed in a recent commit, but codeflash is not configured yet.
${LOGIN_STEP}
Run \`codeflash init --yes\` to automatically detect and configure the Java project, then run \`codeflash --subagent\` as a background Bash task (run_in_background: true) to optimize the code for performance."
      ;;
    javascript)
      SETUP_MSG="JS/TS files were changed in a recent commit, but codeflash is not configured yet.

Set up codeflash to optimize the JavaScript/TypeScript code for performance. Automatically determine the following by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user -- discover the correct paths yourself):
${LOGIN_STEP}
1. The relative path with respect to package.json to the root of the JS/TS module -- typically \".\" for the root directory or \"src\".
2. The relative path with respect to package.json to the tests folder -- look for existing directories named \`tests\`, \`test\`, \`__tests__\`, or folders containing files that start with \`test_\` or end with \`.test.js\`/\`.spec.ts\`. If none exist, default to \`tests\`.

Once determined:
- If the tests folder does not exist, create it with mkdir -p.
- Add/update the \"codeflash\" key in \`package.json\`:

{
  \"codeflash\": {
    \"moduleRoot\": \"<module root>\",
    \"testsRoot\": \"<tests folder>\",
    \"formatterCmds\": [\"disabled\"],
    \"ignorePaths\": [\"dist\", \"**/node_modules\", \"**/__tests__\"]
  }
}

Once the configuration is written, run \`npx codeflash --subagent\` as a background Bash task (run_in_background: true)."
      ;;
    *) continue ;;
  esac

  # Append auto-allow setup instructions if not already configured
  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
    SETUP_MSG="${SETUP_MSG}

Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
  fi

  jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
done

# No recognized languages in changed files -- exit silently
exit 0

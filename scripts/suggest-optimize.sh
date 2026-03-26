#!/usr/bin/env bash
# Stop hook: detect new Python/Java/JS/TS commits since the session started and ask the
# user if they'd like to run codeflash to optimize their code.
# Fires when Claude is about to finish its response.

set -euo pipefail

LOGFILE="/tmp/codeflash-hook-debug.log"
exec 2>>"$LOGFILE"
set -x

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
if [ -f "$LAST_HEAD_FILE" ] && [ "$(cat "$LAST_HEAD_FILE")" = "$CURRENT_HEAD" ]; then
  exit 0
fi
echo "$CURRENT_HEAD" > "$LAST_HEAD_FILE"

# Get the transcript file's creation (birth) time as the session start timestamp.
# This predates any commits Claude could have made in this session.
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

SESSION_START=$(get_file_birth_time "$TRANSCRIPT_PATH")
if [ -z "$SESSION_START" ] || [ "$SESSION_START" = "0" ]; then
  exit 0
fi

# Find commits with Python/Java/JS/TS files made after the session started
CHANGED_COMMITS=$(git log --after="@$SESSION_START" --name-only --diff-filter=ACMR --pretty=format: -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | sort -u | grep -v '^$' || true)
if [ -z "$CHANGED_COMMITS" ]; then
  exit 0
fi

# Determine which language families actually had changes
HAS_PYTHON_CHANGES="false"
HAS_JS_CHANGES="false"
if echo "$CHANGED_COMMITS" | grep -qE '\.py$'; then
  HAS_PYTHON_CHANGES="true"
fi
if echo "$CHANGED_COMMITS" | grep -qE '\.(js|ts|jsx|tsx)$'; then
  HAS_JS_CHANGES="true"
fi

# Dedup: don't trigger twice for the same set of changes across sessions.
SEEN_MARKER="$TRANSCRIPT_DIR/codeflash-seen"

COMMIT_HASH=$(git log --after="@$SESSION_START" --pretty=format:%H -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
if [ -f "$SEEN_MARKER" ] && grep -qF "$COMMIT_HASH" "$SEEN_MARKER" 2>/dev/null; then
  exit 0
fi
echo "$COMMIT_HASH" >> "$SEEN_MARKER"

# --- From here on, we know there are new commits to optimize ---

# --- Check if CODEFLASH_API_KEY is available ---
OAUTH_SCRIPT="$(dirname "$0")/oauth-login.sh"

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

LOGIN_STEP=""
if ! has_api_key; then
  LOGIN_STEP="
- Run \`${OAUTH_SCRIPT}\` to log in to Codeflash. If it exits with code 0, the key is saved. If it exits with code 2 (headless environment), parse the JSON output for the \`url\` and \`state_file\`, ask the user to visit the URL and provide the authorization code, then run \`${OAUTH_SCRIPT} --exchange-code <state_file> <code>\` to complete the login."
fi

# Walk from $PWD upward to $REPO_ROOT looking for project config.
# Sets: PROJECT_TYPE, PROJECT_DIR, PROJECT_CONFIG_PATH, PROJECT_CONFIGURED
detect_project() {
  PROJECT_TYPE=""
  PROJECT_DIR=""
  PROJECT_CONFIG_PATH=""
  PROJECT_CONFIGURED="false"
  local search_dir="$PWD"
  while true; do
    # Check codeflash.toml first (Java projects)
    if [ -f "$search_dir/codeflash.toml" ]; then
      PROJECT_TYPE="java"
      PROJECT_DIR="$search_dir"
      PROJECT_CONFIG_PATH="$search_dir/codeflash.toml"
      if grep -q '\[tool\.codeflash\]' "$search_dir/codeflash.toml" 2>/dev/null; then
        PROJECT_CONFIGURED="true"
      fi
      break
    fi
    if [ -f "$search_dir/pyproject.toml" ]; then
      PROJECT_TYPE="python"
      PROJECT_DIR="$search_dir"
      PROJECT_CONFIG_PATH="$search_dir/pyproject.toml"
      if grep -q '\[tool\.codeflash\]' "$search_dir/pyproject.toml" 2>/dev/null; then
        PROJECT_CONFIGURED="true"
      fi
      break
    fi
    if [ -f "$search_dir/package.json" ]; then
      PROJECT_TYPE="js"
      PROJECT_DIR="$search_dir"
      PROJECT_CONFIG_PATH="$search_dir/package.json"
      if jq -e '.codeflash' "$search_dir/package.json" >/dev/null 2>&1; then
        PROJECT_CONFIGURED="true"
      fi
      break
    fi
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

# Discover project config
detect_project

CHECK_DIR="${PROJECT_DIR:-$PWD}"

# --- JS/TS project path ---------------------------------------------------
if [ "$PROJECT_TYPE" = "js" ] && [ "$HAS_JS_CHANGES" = "true" ]; then
  INSTALL_CMD="npm install --save-dev codeflash"

  # Check if codeflash npm package is available
  CODEFLASH_INSTALLED="false"
  if (cd "$CHECK_DIR" && npx codeflash --version >/dev/null 2>&1); then
    CODEFLASH_INSTALLED="true"
  fi

  # Not configured → prompt for config (+ install if needed)
  if [ "$PROJECT_CONFIGURED" != "true" ]; then
    if [ -n "$PROJECT_CONFIG_PATH" ]; then
      TARGET_MSG="Add a \`\"codeflash\"\` key to \`$PROJECT_CONFIG_PATH\`"
    else
      TARGET_MSG="Create \`$REPO_ROOT/package.json\` (via \`npm init -y\`) and add a \`\"codeflash\"\` key"
    fi

    INSTALL_STEP=""
    if [ "$CODEFLASH_INSTALLED" != "true" ]; then
      INSTALL_STEP="
- First, install codeflash by running \`${INSTALL_CMD}\` in \`${CHECK_DIR}\`."
    fi

    SETUP_MSG="JS/TS files were changed in a recent commit, but codeflash is not configured yet.

Set up codeflash to optimize the JavaScript/TypeScript code for performance. Automatically determine the following by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user — discover the correct paths yourself):
1. The relative path with respect to package.json to the root of the JS/TS module — typically \".\" for the root directory or \"src\".
2. The relative path with respect to package.json to the tests folder — look for existing directories named \`tests\`, \`test\`, \`__tests__\`, or folders containing files that start with \`test_\` or end with \`.test.js\`/\`.spec.ts\`. If none exist, default to \`tests\`.

Once determined:${INSTALL_STEP}
- If the tests folder does not exist, create it with mkdir -p.
- ${TARGET_MSG}. Read the existing package.json, parse it, add/update the \"codeflash\" key with the discovered values, and write back with 2-space indentation:

{
  \"codeflash\": {
    \"moduleRoot\": \"<module root>\",
    \"testsRoot\": \"<tests folder>\",
    \"formatterCmds\": [\"disabled\"],
    \"ignorePaths\": [\"dist\", \"**/node_modules\", \"**/__tests__\"]
  }
}

Once the configuration is written, run \`npx codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."

#    # Append auto-allow setup instructions if not already configured
#    if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#      SETUP_MSG="${SETUP_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#    fi

    jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
    exit 0
  fi

  # Configured but not installed
  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    INSTALL_MSG="JS/TS files were changed in a recent commit, but the codeflash npm package is not installed.

Install codeflash to optimize the JavaScript/TypeScript code for performance by running:

  ${INSTALL_CMD}

in \`${CHECK_DIR}\`, then run \`npx codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."

#    # Append auto-allow setup instructions if not already configured
#    if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#      INSTALL_MSG="${INSTALL_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#    fi

    jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
    exit 0
  fi

  # Build codeflash command for JS/TS — must run from project root
  if [ -n "$PROJECT_DIR" ] && [ "$PROJECT_DIR" != "$PWD" ]; then
    RUN_CMD="cd $PROJECT_DIR && npx codeflash --subagent"
  else
    RUN_CMD="npx codeflash --subagent"
  fi

  MESSAGE="JS/TS files were changed in a recent commit. Use the codeflash:optimize skill WITHOUT ANY ARGUMENTS to to optimize the JavaScript/TypeScript code for performance."

#  # Append auto-allow setup instructions if not already configured
#  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#    MESSAGE="${MESSAGE}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#  fi

  jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

# --- Java project path -----------------------------------------------------
if [ "$PROJECT_TYPE" = "java" ]; then
  INSTALL_CMD="pip install codeflash"

  # Find codeflash binary: check PATH first, then uv run (Java projects don't use venvs)
  CODEFLASH_BIN=""
  CODEFLASH_INSTALLED="false"
  if command -v codeflash >/dev/null 2>&1; then
    CODEFLASH_BIN="codeflash"
    CODEFLASH_INSTALLED="true"
  elif uv run codeflash --version >/dev/null 2>&1; then
    CODEFLASH_BIN="uv run codeflash"
    CODEFLASH_INSTALLED="true"
  fi

  # Not installed
  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    INSTALL_MSG="Java files were changed in a recent commit, but codeflash is not installed.

Install codeflash to optimize the Java code for performance by running:

  ${INSTALL_CMD}

Then run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."

#    if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#      INSTALL_MSG="${INSTALL_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#    fi

    jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
    exit 0
  fi

  # Not configured
  if [ "$PROJECT_CONFIGURED" != "true" ]; then
    SETUP_MSG="Java files were changed in a recent commit, but codeflash is not configured yet.

Run \`${CODEFLASH_BIN} init --yes\` in \`${CHECK_DIR}\` to automatically detect and configure the Java project, then run \`${CODEFLASH_BIN} --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout to optimize the code for performance."

#    if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#      SETUP_MSG="${SETUP_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#    fi

    jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
    exit 0
  fi

  # Everything ready — build codeflash command for Java
  if [ -n "$PROJECT_DIR" ] && [ "$PROJECT_DIR" != "$PWD" ]; then
    RUN_CMD="cd $PROJECT_DIR && $CODEFLASH_BIN --subagent"
  else
    RUN_CMD="$CODEFLASH_BIN --subagent"
  fi

  MESSAGE="Java files were changed in a recent commit. Use the codeflash:optimize skill WITHOUT ANY ARGUMENTS to to optimize the Java code for performance."

#  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#    MESSAGE="${MESSAGE}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#  fi

  jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

# --- Python project path ---------------------------------------------------
if [ "$HAS_PYTHON_CHANGES" != "true" ]; then
  exit 0
fi

INSTALL_CMD="pip install codeflash"

# Only use codeflash from the current virtual environment.
# If no venv is active, try to find and activate one automatically.
# shellcheck disable=SC1091
source "$(dirname "$0")/find-venv.sh"

if [ -z "${VIRTUAL_ENV:-}" ]; then
  # No venv found — instruct Claude to create one, install codeflash, configure, and run

  # Build config setup instructions if not configured
  PYPROJECT_SETUP=""
  if [ "$PROJECT_CONFIGURED" != "true" ]; then
    if [ -n "$PROJECT_CONFIG_PATH" ]; then
      TARGET_MSG="Append to \`$PROJECT_CONFIG_PATH\`"
    else
      TARGET_MSG="Create \`$REPO_ROOT/pyproject.toml\`"
    fi

    PYPROJECT_SETUP="
3. Automatically determine the following two values by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user — discover the correct paths yourself):
   a. The relative path with respect to pyproject.toml to the root of the Python module — the module root is where tests import from. for example, if the module root is abc/ then the tests would be importing code as \`from abc import xyz\`.
   b. The relative path with respect to pyproject.toml to the tests folder — look for existing directories named \`tests\` or \`test\`, or folders containing files that start with \`test_\`. If none exist, default to \`tests\`.

4. Once determined:
   - If the tests folder does not exist, create it with mkdir -p.
   - ${TARGET_MSG} (create the file if it does not exist), adding the following section with the discovered values substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

5. Run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."
  else
    PYPROJECT_SETUP="
3. Run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."
  fi

#  # Build auto-allow setup step if not already configured
#  SETUP_PERMISSIONS_STEP=""
#  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#    SETUP_PERMISSIONS_STEP="
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#  fi

  VENV_MSG="Python files were changed in a recent commit, but no Python virtual environment was found.

Set up codeflash to optimize the Python code for performance. Perform the following steps:
${LOGIN_STEP}
1. Create a virtual environment by running: \`python3 -m venv .venv\` in \`$REPO_ROOT\`, then activate it by running: \`source $REPO_ROOT/.venv/bin/activate\`.

2. Install codeflash by running: \`${INSTALL_CMD}\`.
${PYPROJECT_SETUP}
${SETUP_PERMISSIONS_STEP}"

  jq -nc --arg reason "$VENV_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

CODEFLASH_BIN="${VIRTUAL_ENV}/bin/codeflash"

# Check if codeflash is installed in the venv
CODEFLASH_INSTALLED="false"
if [ -x "$CODEFLASH_BIN" ] && "$CODEFLASH_BIN" --version >/dev/null 2>&1; then
  CODEFLASH_INSTALLED="true"
fi

# Check if codeflash is configured in this project
if [ "$PROJECT_CONFIGURED" != "true" ]; then
  # Build a human-friendly target path for the setup message
  if [ -n "$PROJECT_CONFIG_PATH" ]; then
    TARGET_MSG="Append to \`$PROJECT_CONFIG_PATH\`"
  else
    TARGET_MSG="Create \`$REPO_ROOT/pyproject.toml\`"
  fi

  # Include install step if codeflash is not installed
  INSTALL_STEP=""
  if [ "$CODEFLASH_INSTALLED" != "true" ]; then
    INSTALL_STEP="
- First, install codeflash by running \`${INSTALL_CMD}\` in \`${CHECK_DIR}\`."
  fi

  SETUP_MSG="Python files were changed in a recent commit, but codeflash is not configured yet.

Set up codeflash to optimize the Python code for performance:
${LOGIN_STEP}
Automatically determine the following by exploring the project's actual directory structure using Glob and Read (do NOT present options to the user — discover the correct paths yourself):
1. The relative path with respect to pyproject.toml to the root of the Python module — the module root is where tests import from. for example, if the module root is abc/ then the tests would be importing code as \`from abc import xyz\`.
2. The relative path with respect to pyproject.toml to the tests folder — look for existing directories named \`tests\` or \`test\`, or folders containing files that start with \`test_\`. If none exist, default to \`tests\`.

Once determined:${INSTALL_STEP}
- If the tests folder does not exist, create it with mkdir -p.
- ${TARGET_MSG} (create the file if it does not exist), adding the following section with the discovered values substituted:

[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = \"<module root>\"
tests-root = \"<tests folder>\"
ignore-paths = []
formatter-cmds = [\"disabled\"]

Once the pyproject.toml configuration is written, run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."

#  # Append auto-allow setup instructions if not already configured
#  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#    SETUP_MSG="${SETUP_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#  fi

  jq -nc --arg reason "$SETUP_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

# Codeflash is configured but not installed in the venv
if [ "$CODEFLASH_INSTALLED" != "true" ]; then
  INSTALL_MSG="Python files were changed in a recent commit, but codeflash is not installed in the active virtual environment (\`$VIRTUAL_ENV\`).
${LOGIN_STEP}
Install codeflash to optimize the Python code for performance by running:

  ${INSTALL_CMD}

in \`${CHECK_DIR}\`, then run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout."

#  # Append auto-allow setup instructions if not already configured
#  if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#    INSTALL_MSG="${INSTALL_MSG}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#  fi

  jq -nc --arg reason "$INSTALL_MSG" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

# Check for API key before running codeflash
if ! has_api_key; then
  LOGIN_MSG="Python files were changed in a recent commit, but no Codeflash API key was found.

Run \`${OAUTH_SCRIPT}\` to log in to Codeflash. If it exits with code 0, the key is saved. If it exits with code 2 (headless environment), parse the JSON output for the \`url\` and \`state_file\`, ask the user to visit the URL and provide the authorization code, then run \`${OAUTH_SCRIPT} --exchange-code <state_file> <code>\` to complete the login.

After login, run \`codeflash --subagent\` as a non-blocking background Bash task (run_in_background: true) with a 10min timeout to optimize the code."

  jq -nc --arg reason "$LOGIN_MSG" '{"decision": "block", "reason": $reason}'
  exit 0
fi

# Instruct Claude to run codeflash as a background subagent
if [ -n "$PROJECT_DIR" ] && [ "$PROJECT_DIR" != "$PWD" ]; then
  RUN_CMD="cd $PROJECT_DIR && $CODEFLASH_BIN --subagent"
else
  RUN_CMD="$CODEFLASH_BIN --subagent"
fi

MESSAGE="Python files were changed in a recent commit. Use the codeflash:optimize skill WITHOUT ANY ARGUMENTS to to optimize the Python code for performance."

## Append auto-allow setup instructions if not already configured
#if [ "$CODEFLASH_AUTO_ALLOWED" != "true" ]; then
#  MESSAGE="${MESSAGE}
#
#Then, add \`Bash(*codeflash*)\` to the \`permissions.allow\` array in \`$SETTINGS_JSON\` (create the file and \`.claude\` directory if they don't exist, and preserve any existing settings). This allows codeflash to run automatically in the background without prompting for permission each time."
#fi

jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'

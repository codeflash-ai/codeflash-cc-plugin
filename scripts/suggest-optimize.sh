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
  COMMIT_RANGE_ARGS=("--after=@$SESSION_START")
fi

CHANGED_FILES=$(git log "${COMMIT_RANGE_ARGS[@]}" --name-only --diff-filter=ACMR --pretty=format: -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | sort -u | grep -v '^$' || true)
if [ -z "$CHANGED_FILES" ]; then
  exit 0
fi

# Determine which language families actually had changes
HAS_PYTHON_CHANGES="false"
HAS_JS_CHANGES="false"
if echo "$CHANGED_FILES" | grep -qE '\.py$'; then
  HAS_PYTHON_CHANGES="true"
fi
if echo "$CHANGED_FILES" | grep -qE '\.(js|ts|jsx|tsx)$'; then
  HAS_JS_CHANGES="true"
fi

# Dedup: don't trigger twice for the same set of changes.
SEEN_MARKER="$TRANSCRIPT_DIR/codeflash-seen"

COMMIT_HASH=$(git log "${COMMIT_RANGE_ARGS[@]}" --pretty=format:%H -- '*.py' '*.java' '*.js' '*.ts' '*.jsx' '*.tsx' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)
if [ -f "$SEEN_MARKER" ] && grep -qF "$COMMIT_HASH" "$SEEN_MARKER" 2>/dev/null; then
  exit 0
fi
echo "$COMMIT_HASH" >> "$SEEN_MARKER"

# Dedup: skip if all changed files were already sent to codeflash in this session.
# This prevents re-triggering when codeflash's own optimized changes are committed.
OPTIMIZED_FILES_MARKER="$TRANSCRIPT_DIR/codeflash-optimized-files"
if [ -f "$OPTIMIZED_FILES_MARKER" ]; then
  UNSEEN_FILES=$(comm -23 <(echo "$CHANGED_FILES" | sort) <(sort "$OPTIMIZED_FILES_MARKER"))
  if [ -z "$UNSEEN_FILES" ]; then
    exit 0
  fi
fi
# Record the files we're about to send to codeflash
echo "$CHANGED_FILES" >> "$OPTIMIZED_FILES_MARKER"

# --- JS/TS project path ---------------------------------------------------
if [ "$HAS_JS_CHANGES" = "true" ]; then
  MESSAGE="JS/TS files were changed in a recent commit. Use the codeflash:optimize skill WITHOUT ANY ARGUMENTS to to optimize the JavaScript/TypeScript code for performance. Use npx to execute codeflash"
  jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'
  exit 0
fi

# --- Python project path ---------------------------------------------------
if [ "$HAS_PYTHON_CHANGES" != "true" ]; then
  exit 0
fi

MESSAGE="Python files were changed in a recent commit. Use the codeflash:optimize skill WITHOUT ANY ARGUMENTS to to optimize the Python code for performance."

jq -nc --arg reason "$MESSAGE" '{"decision": "block", "reason": $reason, "systemMessage": $reason}'

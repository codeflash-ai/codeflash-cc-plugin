# Hook Lifecycle

## UserPromptSubmit Event

The `UserPromptSubmit` event fires every time the user submits a prompt in Claude Code. Hooks registered on this event can inject additional context into the agent's input before the prompt is processed.

## hooks.json Structure

Located at `hooks/hooks.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/suggest-optimize.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- The outer array under `UserPromptSubmit` contains hook groups.
- Each group has a `hooks` array of individual hook definitions.
- `type: "command"` runs a shell command.
- `timeout` is in seconds. Keep hooks fast (5s or less) since they block prompt processing.
- `${CLAUDE_PLUGIN_ROOT}` resolves to the plugin's installation directory at runtime.

## suggest-optimize.sh Flow

### 1. HEAD Tracking

```bash
HEAD=$(git rev-parse HEAD 2>/dev/null) || exit 0
```

Get the current commit SHA. Exit silently if not in a git repo.

### 2. Duplicate Check

```bash
LAST_SEEN="/tmp/.codeflash-last-suggested"
if [ -f "$LAST_SEEN" ] && [ "$(cat "$LAST_SEEN")" = "$HEAD" ]; then
  exit 0
fi
```

Skip if we already processed this exact commit. Prevents suggesting optimization on every prompt after a single commit.

### 3. Diff Detection

```bash
if [ -n "$PREV" ] && git merge-base --is-ancestor "$PREV" HEAD 2>/dev/null; then
  PY_FILES=$(git diff --name-only "$PREV" HEAD -- '*.py' 2>/dev/null || true)
else
  PY_FILES=$(git diff --name-only HEAD~1 HEAD -- '*.py' 2>/dev/null || true)
fi
```

Compare against the last-seen commit to find changed Python files. Falls back to `HEAD~1` if the previous commit is not an ancestor (e.g., after a rebase).

### 4. State Update

Always write the current HEAD to the tracking file, regardless of whether Python files changed.

### 5. Configuration Check

Verify `[tool.codeflash]` exists in pyproject.toml. Exit silently if not configured.

### 6. Runner Detection

Same lock-file priority as the optimizer agent: uv → poetry → pdm → pipenv → bare.

### 7. JSON Output

```bash
jq -nc --arg ctx "$MESSAGE" \
  '{"hookSpecificOutput": {"hookEventName": "UserPromptSubmit", "additionalContext": $ctx}}'
```

Emits a JSON object with `hookSpecificOutput` containing the context message wrapped in `<user-prompt-submit-hook>` tags. Claude Code treats content in these tags as blocking requirements — the agent must execute them before responding to the user's actual prompt.

The injected message instructs Claude to run `<runner> codeflash --worktree --no-pr` as a background Bash task, then continue answering the user's prompt normally.

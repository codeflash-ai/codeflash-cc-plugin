# Hook and Script Patterns

## hooks.json Format

`hooks/hooks.json` registers commands on Claude Code lifecycle events:

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

- `type` is always `"command"` for shell script hooks.
- `command` uses `${CLAUDE_PLUGIN_ROOT}` to resolve the plugin's install directory.
- `timeout` is in seconds. The suggest script uses 5 seconds — keep hooks fast.

## UserPromptSubmit Hook

The `UserPromptSubmit` event fires every time the user submits a prompt. The hook script can inject additional context into the agent's input by outputting JSON to stdout.

## suggest-optimize.sh Logic

The script follows this flow:

1. **HEAD tracking** — Read current `git rev-parse HEAD`. Compare against `/tmp/.codeflash-last-suggested` to detect new commits.
2. **Skip duplicate** — If HEAD matches the last-seen commit, exit silently.
3. **Python file detection** — `git diff --name-only` between previous and current HEAD, filtering for `*.py` files.
4. **Update tracker** — Write current HEAD to the tracking file regardless of outcome.
5. **Configuration check** — Grep for `[tool.codeflash]` in pyproject.toml. Exit if not configured.
6. **Runner detection** — Same lock-file priority as the agent: uv.lock → poetry.lock → pdm.lock → Pipfile.lock.
7. **jq output** — Emit JSON with `hookSpecificOutput` containing a `<user-prompt-submit-hook>` wrapped message instructing Claude to run codeflash as a background task.

## Output Format

The script outputs a single JSON object via `jq -nc`:

```json
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "<user-prompt-submit-hook>...</user-prompt-submit-hook>"
  }
}
```

The `additionalContext` string wraps the instruction in `<user-prompt-submit-hook>` tags, which Claude Code treats as blocking requirements.

## Script Conventions

- Scripts must be executable (`chmod +x`).
- Use `set -euo pipefail` at the top.
- Exit silently (exit 0) when there's nothing to suggest — don't output anything.
- State files go in `/tmp/` with a `.codeflash-` prefix.

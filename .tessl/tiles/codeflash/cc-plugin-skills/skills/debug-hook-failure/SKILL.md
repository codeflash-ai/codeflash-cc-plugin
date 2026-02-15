---
name: debug-hook-failure
description: Use when the UserPromptSubmit hook is not working — auto-suggest not firing after commits, hook producing wrong output, or submit event not triggering. Diagnoses hook config, script permissions, HEAD tracking, and JSON output.
---

# Debug Hook Failure

Use this skill when the UserPromptSubmit hook (auto-suggest optimization after commits) is not working correctly.

## Trigger

- The hook doesn't fire after Python commits
- The hook fires but doesn't suggest optimization
- The hook produces incorrect or malformed output

## Steps

### 1. Check hooks.json path

Verify `hooks/hooks.json` has the correct structure and the command path uses `${CLAUDE_PLUGIN_ROOT}`:

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

### 2. Verify script permissions

Check that `scripts/suggest-optimize.sh` is executable:

```bash
ls -la scripts/suggest-optimize.sh
```

If not executable, fix with `chmod +x scripts/suggest-optimize.sh`.

### 3. Test script manually

Run the script directly to see its output:

```bash
bash scripts/suggest-optimize.sh
echo "Exit code: $?"
```

If it exits 0 with no output, the script determined there's nothing to suggest. Check:
- Is there a recent Python commit? (`git log --oneline -5`)
- Does `/tmp/.codeflash-last-suggested` match the current HEAD?
- Is `[tool.codeflash]` present in pyproject.toml?

### 4. Check jq output

If the script runs but the output is malformed, verify jq is installed and test the output format:

```bash
echo '{"hookSpecificOutput": {"hookEventName": "test"}}' | jq .
```

The script output must be valid JSON with the `hookSpecificOutput` structure.

### 5. Verify HEAD tracking

Check the state file:

```bash
cat /tmp/.codeflash-last-suggested
git rev-parse HEAD
```

If they match, the script thinks it already processed this commit. Remove the file to force re-evaluation:

```bash
rm /tmp/.codeflash-last-suggested
```

## Common Issues

- **Script not executable** — `chmod +x scripts/suggest-optimize.sh`
- **jq not installed** — Install jq (`brew install jq`, `apt install jq`)
- **Stale HEAD tracker** — Remove `/tmp/.codeflash-last-suggested`
- **No `[tool.codeflash]`** — Run `codeflash init` in the project
- **No Python files in diff** — The hook only triggers for commits that touch `.py` files

# Scenario 2: Hook Doesn't Detect Poetry Projects

## Context

A user reports that the auto-suggest hook works in their uv-managed project but not in their poetry-managed project. After committing Python changes in the poetry project, no optimization suggestion appears.

The user confirms:
- poetry.lock exists in the project root
- `[tool.codeflash]` is in pyproject.toml
- `/optimize --all` works manually
- jq is installed

## Task

Follow the debug-hook-failure skill workflow to diagnose the issue:

1. Check hooks.json path and structure
2. Verify script permissions
3. Test the script manually and inspect output
4. Check jq output format
5. Verify HEAD tracking state

Provide a diagnosis and fix for the most likely cause.

## Expected Outputs

- Verification that hooks.json structure is correct
- Script permissions check (should be executable)
- Manual script execution with output inspection
- HEAD tracking state check (/tmp/.codeflash-last-suggested vs current HEAD)
- Diagnosis of the root cause and specific fix

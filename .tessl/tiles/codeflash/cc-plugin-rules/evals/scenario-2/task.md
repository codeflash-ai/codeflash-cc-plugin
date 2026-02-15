# Scenario 2: Modify the Commit Hook to Support Monorepos

## Context

The codeflash-cc-plugin's `suggest-optimize.sh` script currently detects Python file changes by comparing the entire repository HEAD. In monorepo setups, this can trigger false positives when Python files change in unrelated packages.

## Task

1. Update `scripts/suggest-optimize.sh` to:
   - Accept an optional `CODEFLASH_SCOPE` environment variable that limits Python file detection to a specific subdirectory
   - Only detect Python changes within the scoped directory (e.g., `packages/backend/`)
   - Maintain backward compatibility (if no scope is set, detect all Python files as before)

2. Update `hooks/hooks.json` to:
   - Pass the scope configuration to the script via environment
   - Maintain the correct hooks.json structure with type: command, ${CLAUDE_PLUGIN_ROOT} paths, and timeout

3. Ensure the hook output still follows the correct JSON format with `hookSpecificOutput` and `<user-prompt-submit-hook>` wrapper.

## Expected Outputs

- Updated `scripts/suggest-optimize.sh` with scope support
- Updated `hooks/hooks.json` with environment configuration
- Output format unchanged: JSON with hookSpecificOutput containing additionalContext

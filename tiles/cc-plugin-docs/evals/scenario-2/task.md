# Scenario 2: Troubleshoot Hook Not Suggesting Optimization

## Context

A user reports that after committing Python code changes, Claude Code doesn't suggest running codeflash optimization. The plugin is installed and `/optimize` works manually, but the automatic suggestion after commits never appears.

The user confirms:
- They have `[tool.codeflash]` in pyproject.toml
- They use poetry as their package manager
- They just committed changes to `src/models.py`

## Task

Walk through the hook lifecycle to diagnose potential causes. Explain:

1. How the UserPromptSubmit hook is supposed to trigger
2. The hooks.json structure and how the script is invoked
3. Each step of suggest-optimize.sh and where it could fail:
   - HEAD tracking and the /tmp state file
   - Duplicate commit detection
   - Python file diff detection
   - pyproject.toml config check
   - Runner detection
   - JSON output format
4. The most likely causes and how to verify each one

## Expected Outputs

- Explanation of UserPromptSubmit event and when it fires
- hooks.json structure with ${CLAUDE_PLUGIN_ROOT} path resolution
- Complete suggest-optimize.sh flow with each decision point
- Identification of likely failure points: stale /tmp/.codeflash-last-suggested, script not executable, jq not installed

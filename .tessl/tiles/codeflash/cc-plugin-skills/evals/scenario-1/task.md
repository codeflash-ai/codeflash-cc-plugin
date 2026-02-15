# Scenario 1: Add --timeout Flag

## Context

The codeflash CLI has added a new `--timeout` flag that allows users to set a custom timeout in seconds for the optimization process (default: 600). The plugin needs to expose this flag through the `/optimize` skill.

## Task

Follow the add-cli-flag skill workflow:

1. Update `skills/optimize/SKILL.md` to add `--timeout` to the argument-hint
2. Update `agents/optimizer.md` Step 4 (Parse Task Prompt) to document the --timeout flag extraction
3. Update `agents/optimizer.md` Step 5 (Run Codeflash) to include --timeout in command templates
4. Update `README.md` to mention the new flag in usage examples

## Expected Outputs

- `skills/optimize/SKILL.md` with `--timeout <seconds>` in argument-hint
- `agents/optimizer.md` with --timeout in parse step extraction list and run step command templates
- `README.md` with --timeout mentioned in usage examples

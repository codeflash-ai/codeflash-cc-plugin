# Scenario 3: Add Package Manager Support for Conda

## Context

The codeflash-cc-plugin currently supports four package managers: uv, poetry, pdm, and pipenv. Users with conda-managed environments cannot use the auto-detection feature and must run codeflash manually.

## Task

1. Update `agents/optimizer.md` to:
   - Add conda detection in the runner detection step (check for `environment.yml` → use `conda run -n <env>`)
   - Add conda installation instructions in the error handling section
   - Place conda detection at the end of the priority list (after pipenv)

2. Update `scripts/suggest-optimize.sh` to:
   - Add the same conda detection logic in the runner detection section
   - Maintain the lock-file priority order with conda last

3. Bump the version in both `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` to reflect the new feature (minor version bump).

## Expected Outputs

- Updated `agents/optimizer.md` with conda support in detect and error handling steps
- Updated `scripts/suggest-optimize.sh` with conda runner detection
- Updated `.claude-plugin/plugin.json` with bumped version
- Updated `.claude-plugin/marketplace.json` with both version fields bumped and matching

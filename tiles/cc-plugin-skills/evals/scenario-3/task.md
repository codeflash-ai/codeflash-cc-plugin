# Scenario 3: Release v0.2.0

## Context

The plugin has accumulated several improvements since v0.1.1: conda support, a new --timeout flag, and improved error messages. It's time to release v0.2.0.

## Task

Follow the publish-new-version skill workflow:

1. Bump `.claude-plugin/plugin.json` version to `0.2.0`
2. Bump `.claude-plugin/marketplace.json` — both `metadata.version` and `plugins[0].version` to `0.2.0`
3. Verify all three version fields match
4. Update README.md if there are user-facing changes to document
5. Create an atomic commit: `chore: bump version to 0.2.0`
6. Create git tag `v0.2.0`

## Expected Outputs

- `.claude-plugin/plugin.json` with version `"0.2.0"`
- `.claude-plugin/marketplace.json` with both version fields set to `"0.2.0"`
- All three versions in sync
- Commit message: `chore: bump version to 0.2.0`
- Git tag: `v0.2.0`

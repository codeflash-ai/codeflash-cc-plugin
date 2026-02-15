---
name: publish-new-version
description: Use when releasing, publishing, or bumping a version of the codeflash plugin. Updates plugin.json, marketplace.json version fields, README, creates atomic commit and git tag.
---

# Publish New Version

Use this skill when releasing a new version of the plugin.

## Trigger

A new feature, bug fix, or change is ready to be released.

## Steps

### 1. Bump plugin.json version

Edit `.claude-plugin/plugin.json` and update the `version` field:

```json
{
  "version": "0.2.0"
}
```

Use semver: patch for fixes, minor for features, major for breaking changes.

### 2. Bump marketplace.json versions

Edit `.claude-plugin/marketplace.json` and update **both** version fields:

- `metadata.version`
- `plugins[0].version`

Both must match the new plugin.json version.

### 3. Update README if needed

If the new version includes user-facing changes (new flags, new skills, changed behavior), update the relevant sections in `README.md`.

### 4. Commit

Create a single atomic commit with all version bumps:

```
chore: bump version to 0.2.0
```

### 5. Tag

Create a git tag matching the version:

```bash
git tag v0.2.0
```

## Checklist

- [ ] plugin.json version updated
- [ ] marketplace.json metadata.version updated
- [ ] marketplace.json plugins[0].version updated
- [ ] All three versions match
- [ ] README updated if needed
- [ ] Single commit with version bump
- [ ] Git tag created

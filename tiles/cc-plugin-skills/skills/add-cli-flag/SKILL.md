---
name: add-cli-flag
description: Use when extending the /optimize command with new CLI flags, arguments, or options. Updates SKILL.md argument-hint, optimizer agent parse and run sections, and README.
---

# Add CLI Flag

Use this skill when a new codeflash CLI flag needs to be supported in the plugin.

## Trigger

A new flag has been added to the `codeflash` CLI and needs to be exposed through the plugin's `/optimize` skill.

## Steps

### 1. Update SKILL.md argument-hint

Edit `skills/optimize/SKILL.md` frontmatter to add the new flag to the `argument-hint` field:

```yaml
argument-hint: "[file] [function] [--all] [--no-pr] [--effort low|medium|high] [--new-flag value]"
```

### 2. Update optimizer agent — parse section

Edit `agents/optimizer.md` Step 4 (Parse Task Prompt) to document the new flag:

- Add the flag to the extraction list with its description
- Document the flag's default behavior if omitted

### 3. Update optimizer agent — run section

Edit `agents/optimizer.md` Step 5 (Run Codeflash) to include the new flag in the command templates:

```bash
<runner> codeflash --worktree --file <path> [--new-flag <value>] [flags]
```

### 4. Update README

Add the new flag to the usage examples in `README.md` so users know it's available.

## Verification

1. Grep `skills/optimize/SKILL.md` for the new flag name to confirm it appears in argument-hint
2. Grep `agents/optimizer.md` for the new flag name to confirm it appears in both parse and run sections
3. Grep `README.md` for the new flag name to confirm it appears in usage examples

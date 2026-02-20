# Agent Design

## Frontmatter Conventions

Agent files in `agents/` use YAML frontmatter with these fields:

```yaml
---
name: optimizer              # Agent identifier (lowercase, no spaces)
description: |               # Multi-line description of when to use this agent
  Optimizes Python code for performance using Codeflash.
model: inherit               # Always "inherit" — use caller's model
maxTurns: 15                 # Maximum agentic turns before stopping
color: cyan                  # Terminal spinner color
tools: Read, Glob, Grep, Bash  # Comma-separated tool list
---
```

- `model` should always be `inherit` — agents don't override the caller's model.
- `tools` should be the minimum set needed. The optimizer needs file inspection (Read, Glob, Grep) and CLI execution (Bash).
- `maxTurns` of 15 allows for the 6-step workflow plus retries.

## Workflow Pattern

All agents follow a detect-verify-execute pattern:

1. **Detect runner** — Check lock files (uv.lock, poetry.lock, pdm.lock, Pipfile.lock) to determine the package runner.
2. **Verify setup** — Confirm `[tool.codeflash]` exists in pyproject.toml. Stop with instructions if missing.
3. **Verify install** — Run `<runner> codeflash --worktree --version`. Stop with install instructions if it fails.
4. **Parse prompt** — Extract file path, function name, and flags from the task arguments.
5. **Run codeflash** — Execute the CLI command with a 10-minute timeout (`timeout: 600000`).
6. **Report results** — Summarize what was optimized, performance gains, and PR status.

Always pass `--worktree` and `--no-pr` to all codeflash CLI invocations.

## Error Handling

- **Exit 127** → codeflash not installed. Provide runner-specific install command.
- **Not configured** → Tell user to run `codeflash init`.
- **No optimizations found** → Normal outcome, report clearly. Not all code can be optimized.
- **"Attempting to repair broken tests..."** → Normal codeflash behavior, not an error.

## What Agents Don't Do

- No multiple optimization rounds or augmented mode.
- No profiling data analysis.
- No linting/formatting (codeflash handles this internally).
- No PR creation (codeflash handles PR creation).
- No code simplification or refactoring.

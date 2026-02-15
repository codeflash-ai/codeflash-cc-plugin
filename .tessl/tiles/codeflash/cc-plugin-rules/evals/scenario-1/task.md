# Scenario 1: Add a New Agent for Code Review

## Context

The codeflash-cc-plugin currently has a single agent (`agents/optimizer.md`) that optimizes Python code. The team wants to add a second agent that reviews Python code quality before optimization, checking for common anti-patterns that affect performance.

## Task

1. Create a new agent file at `agents/reviewer.md` that:
   - Uses correct YAML frontmatter with name, description, model: inherit, maxTurns, color, and tools
   - Follows the detect-verify-execute workflow pattern (detect runner, verify setup, verify install, parse, execute, report)
   - Handles known error cases (exit 127, missing config, no issues found)
   - Uses the minimum necessary toolset

2. Create a matching skill at `skills/review/SKILL.md` that:
   - Maps to the new agent via `agent: codeflash:reviewer`
   - Has appropriate argument-hint for file/function targeting
   - Uses `context: fork` for isolated execution

3. Ensure all new files are placed in the correct plugin directories.

## Expected Outputs

- `agents/reviewer.md` — Agent with proper frontmatter and 6-step workflow
- `skills/review/SKILL.md` — Skill with proper frontmatter linking to the agent

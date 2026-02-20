# Scenario 1: Explain How /optimize Works End-to-End

## Context

A new developer has joined the team and wants to understand the full path from a user typing `/optimize src/utils.py my_func --effort high` to seeing optimization results.

## Task

Write a technical walkthrough that explains:

1. What happens when the user types `/optimize src/utils.py my_func --effort high` in Claude Code
2. How the SKILL.md frontmatter determines what happens (which agent, what context mode, what tools)
3. How the skill body template processes the arguments ($ARGUMENTS substitution)
4. How the optimizer agent's 6-step workflow executes:
   - How it detects the project's package manager
   - How it verifies codeflash is configured and installed
   - How it parses the arguments to build the codeflash command
   - The exact command it would run (including --worktree --no-pr flag and timeout)
   - How it reports results

## Expected Outputs

- Clear explanation of SKILL.md frontmatter fields: name, user-invocable, argument-hint, context: fork, agent: codeflash:optimizer, allowed-tools
- Understanding that context: fork creates an isolated conversation
- Correct 6-step workflow description with runner detection priority (uv > poetry > pdm > pipenv)
- The command: `<runner> codeflash --worktree --no-pr --file src/utils.py --function my_func --effort high` with 10-minute timeout

---
name: optimize
description: Optimize Python code for performance using Codeflash. Use when asked to optimize, speed up, or improve performance of Python functions, files, or projects.
user-invocable: true
argument-hint: "[file] [function] [--all] [--no-pr]"
context: fork
agent: codeflash:optimizer
allowed-tools: Task
---

Optimize Python code using Codeflash.

Pass the following to the optimizer agent:

```
Optimize Python code using the workflow in your system prompt.

Arguments: $ARGUMENTS

If no arguments were provided, run codeflash without --file — it detects changed files itself.
If a file path was provided without a function name, optimize all functions in that file.
If both file and function were provided, optimize that specific function.
If --all was provided, optimize the entire project.
Add the --subagent flag to the codeflash command.
```

## Common Usage Patterns

- `/optimize` — optimize recently changed files (auto-detected)
- `/optimize src/utils.py` — optimize all functions in a file
- `/optimize src/utils.py parse_data` — optimize a specific function
- `/optimize --all` — optimize the entire project
- `/optimize src/utils.py --no-pr` — optimize without creating a PR

## After Optimization

When codeflash completes, use `/optimize-review` to get a detailed analysis of the optimization results, including explanations of what changed and safety assessments.

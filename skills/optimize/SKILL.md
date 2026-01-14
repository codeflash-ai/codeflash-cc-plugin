---
name: optimize
description: Optimize Python code for performance using Codeflash
user-invocable: true
argument-hint: "[file] [function] [--all] [--no-pr] [--effort low|medium|high]"
context: fork
agent: codeflash:optimizer
allowed-tools: Task
---

Optimize Python code using Codeflash.

Pass the following to the optimizer agent:

```
Optimize Python code using the workflow in your system prompt.

Arguments: $ARGUMENTS

If no arguments were provided, run with --all to optimize the entire project.
If a file path was provided without a function name, optimize all functions in that file.
If both file and function were provided, optimize that specific function.
Pass through any flags (--no-pr, --effort, etc.) to the codeflash command.
```

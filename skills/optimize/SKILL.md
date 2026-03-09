---
name: optimize
description: Optimize Python code for performance using Codeflash
user-invocable: true
argument-hint: "[--file] [--function] [--subagent]"
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
Pass through the --subagent flag to the codeflash command.
```

---
name: optimize
description: Optimize Python, Java, JavaScript, or TypeScript code for performance using Codeflash
user-invocable: true
argument-hint: "[--file] [--function] [--subagent]"
---

Dispatch all optimization work to a subagent to keep the main context clean.

Use the Agent tool with the following configuration:

- **subagent_type**: code
- **agent**: codeflash:optimizer
- **prompt**: The message below

```
Optimize code using the workflow in your system prompt.

Arguments: $ARGUMENTS

If no arguments were provided, run codeflash without --file — it detects changed files itself.
If a file path was provided without a function name, optimize all functions in that file.
If both file and function were provided, optimize that specific function.
Add the --subagent flag to the codeflash command.

IMPORTANT: When you finish, return ONLY a concise summary:
- Which files/functions were analyzed
- Whether optimizations were found (and what speedups)
- Any errors encountered
Do NOT include full command output, logs, or intermediate steps.
```

Do NOT do any optimization work in the main context. The subagent handles everything: preflight checks, environment setup, configuration, running codeflash, and reporting results.
---
name: optimize
description: Optimize Python code for performance using Codeflash
user-invocable: true
argument-hint: "[file] [function] [--all] [--no-pr] [--effort low|medium|high]"
allowed-tools: Task, Read, Edit, Glob, Grep
---

Optimize Python code using Codeflash.

Follow these steps in order:

### 1. Launch background optimization

Use the Task tool to spawn the `codeflash:optimizer` agent **in the background** (`run_in_background: true`). Pass it this prompt:

```
Optimize Python code using the workflow in your system prompt.

Arguments: $ARGUMENTS

If no arguments were provided, run with --all to optimize the entire project.
If a file path was provided without a function name, optimize all functions in that file.
If both file and function were provided, optimize that specific function.
Pass through any flags (--effort, etc.) to the codeflash command.
```

### 2. Notify the user

Tell the user that codeflash is optimizing in the background and they can continue working.

### 3. Present results when ready

Once the background task completes, read its output and present the results:

1. **If optimizations were found**: show what was optimized, the explanation of why the new code is faster, and the performance numbers.
2. **Critique the change** — Read both the original code and the proposed replacement, then present your own independent assessment covering correctness, claimed speedup plausibility, readability, trade-offs, and a clear verdict (accept / accept with caveats / reject).
3. **Apply changes via Edit tool** — For each optimized function, use the Edit tool to replace the original code with the optimized version so the user gets the standard Claude Code diff acceptance prompt.
4. **If no optimizations were found**, let the user know briefly.

**IMPORTANT**: Do NOT just print the diff as text. Use the Edit tool to apply changes so the user gets the accept/reject prompt.

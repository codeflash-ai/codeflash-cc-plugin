---
description: "Set up codeflash permissions so optimization runs automatically without prompting"
argument-hint: ""
allowed-tools: Bash, Read, Write, Edit, Task, Grep, Glob, Bash(*codeflash*), Bash(git *)
---

Help the user configure their project so that `codeflash --subagent` runs automatically without permission prompts.

## Steps

1. Check if `.claude/settings.json` exists in the project root (use `git rev-parse --show-toplevel` to find it).

2. If the file exists, read it and check if `Bash(*codeflash*)` is already in `permissions.allow`.

3. If already configured, tell the user: "Codeflash is already configured to run automatically. No changes needed."

4. If not configured, add `Bash(*codeflash*)` to the `permissions.allow` array in `.claude/settings.json`. Create the file and any necessary parent directories if they don't exist. Preserve any existing settings.

5. Confirm to the user what was added and explain: "Codeflash will now run automatically in the background after commits that change code files, without prompting for permission each time."

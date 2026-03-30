---
name: optimize
description: Optimize Python, Java, JavaScript, or TypeScript code for performance using Codeflash
user-invocable: true
argument-hint: "[--file path] [--function name]"
allowed-tools: ["Bash"]
---

Run the `codeflash` CLI to optimize code for performance.

## Build the command

Start with: `codeflash --subagent` for Python and Java Code
Start with: `npx codeflash --subagent`for JS/TS Code

Then add flags based on `$ARGUMENTS`:
- If a `--file` path was provided: add `--file <path>`
- If a `--function` name was also provided: add `--function <name>`
- If no arguments were provided, run `codeflash --subagent` as-is (it detects changed files automatically)

## Execute

Run the command as a **non-blocking background** Bash call (`run_in_background: true`) with a **10-minute timeout** (`timeout: 600000`).

If the command fails (not installed, not authenticated, or missing config), invoke the `codeflash:setup` skill to resolve the issue, then retry.

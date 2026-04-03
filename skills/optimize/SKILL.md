---
name: optimize
description: Optimize code for performance using Codeflash
user-invocable: true
argument-hint: "[--file path] [--function name]"
allowed-tools: ["Bash"]
---

Run the `codeflash` CLI to optimize code for performance.

## File and Function disambiguation

Disambiguate the file and function from `$ARGUMENTS` if --file and/or --function are not provided explicitly.

## Correct cwd

Based on the language of the file/s of concern, find the config file closest to the file/files of concern (the file passed to codeflash --file or the files which changed in the diff):
- **Python**: `pyproject.toml`
- **JS/TS**: `package.json`
- **Java**: `pom.xml` or `build.gradle`/`build.gradle.kts`

`cd` into the directory where you found the config file.

## Build the command

Start with: `codeflash --subagent` for Python and Java Code or `uv run codeflash --subagent` if a `uv.lock` file is present.
Start with: `npx codeflash --subagent`for JS/TS Code

Then add flags based on `$ARGUMENTS`:
- If a `--file` path was provided: add `--file <path>`
- If a `--function` name was also provided: add `--function <name>`
- If no arguments were provided, run `codeflash --subagent` as-is (it detects changed files automatically)

## Execute

Run the command as a **non-blocking background** Bash call (`run_in_background: true`) with a **10-minute timeout** (`timeout: 600000`).

If the command fails (not installed, not authenticated, or missing config), invoke the `codeflash:setup` skill to resolve the issue, then retry.

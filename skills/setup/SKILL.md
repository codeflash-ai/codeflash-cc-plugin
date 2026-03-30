---
name: setup
description: "This skill should be used when codeflash fails to run due to missing installation, authentication issues, or missing project configuration. It handles installing codeflash (via pip or uv), authenticating, and configuring pyproject.toml. Trigger phrases: \"setup codeflash\", \"configure codeflash\", \"codeflash is not installed\", \"codeflash auth failed\", \"fix codeflash setup\"."
color: cyan
tools: ["Read", "Glob", "Grep", "Bash", "Write", "Task"]
---

# Codeflash Setup

Set up codeflash when it is missing, unauthenticated, or unconfigured. This skill is typically invoked as a fallback when running codeflash fails.

## Workflow

Run the following diagnostic checks and fix only the ones that fail.

### Check 0: Valid Git Repo

If cwd is not part of a valid git repo then exit early, codeflash only works on git repos.

### Check 1: Installation

For python and java code, if no virtual environment is active activate the closest virtual environment and do
```bash
which codeflash
```
or
```bash
uv run codeflash --version
```
if a `uv.lock` file is present in the directory.
For JS/TS code
```bash
npx codeflash --version
```

If this fails, codeflash is not installed. Detect the project's package manager and install accordingly:

- If a `uv.lock` file exists or `pyproject.toml` uses `[tool.uv]`: run `uv add --dev codeflash`
- Otherwise: activate the closest virtual environment if no virtual environment is active and do `pip install codeflash` or just `uv pip install codeflash` if there is a `uv.lock` file present in the directory.
- For js/ts code, run `npm install --dev codeflash`

**Never** use `uv tool install` to install codeflash.

### Check 2: Authentication

For python and java code
```bash
codeflash auth status
```
or
```bash
uv run codeflash auth status
```
if `uv.lock` is present.

for js/ts code
```bash
npx codeflash auth status
```

If this fails, the user is not authenticated. Run `codeflash auth login` or `uv run codeflash auth login` if `uv.lock` is present for python and java code and `npx codeflash auth login` for js/ts code interactively. This requires user interaction, so let them know the login flow is starting.

### Check 3a: Project Configuration (Python)

Find the `pyproject.toml` file closest to the file/files of concern (the file passed to codeflash --file or the files which changed in the diff). Confirm that a `[tool.codeflash]` section exists in the pyproject file found.

- If the `pyproject.toml` file exists but lacks `[tool.codeflash]`, run **Configuration Discovery (Python)** below and append the section.
- If no `pyproject.toml` exists, run **Configuration Discovery (Python)** below and create one.

#### Configuration Discovery (Python)

Perform the following discovery steps relative to the directory containing the target `pyproject.toml`:

**Discover module root:**
Find the relative path to the root of the Python module. The module root is where tests import from. For example, if the module root is `abc/` then tests would import code as `from abc import xyz`. Look for directories containing `__init__.py` files at the top level. Common patterns: `src/package_name/`, `package_name/`, or the project root itself.

**Discover tests folder:**
Find the relative path to the tests directory. Look for:
1. Existing directories named `tests` or `test`
2. Folders containing files matching `test_*.py`
If no tests directory exists, default to `tests`.

**Write the configuration:**
Append the `[tool.codeflash]` section to the target `pyproject.toml`. Use exactly this format:

```toml
[tool.codeflash]
# All paths are relative to this pyproject.toml's directory.
module-root = "<discovered module root>"
tests-root = "<discovered tests folder>"
ignore-paths = ["dist", "**/node_modules", "**/__tests__"]
formatter-cmds = ["disabled"]
```

After writing, confirm the configuration with the user before proceeding.

### Check 3b: Project Configuration (Javascript/Typescript)

Find the `package.json` file closest to the file/files of concern (the file passed to codeflash --file or the files which changed in the diff). Confirm that a `codeflash` key exists in the package.json file found.

- If a `package.json` exists but lacks the `codeflash` key, run **Configuration Discovery (Javascript/Typescript)** below and append the section.
- If no `package.json` exists, run **Configuration Discovery (Javascript/Typescript)** and create one at the git repository root.

#### Configuration Discovery (Javascript/Typescript)

Perform the following discovery steps relative to the directory containing the target `package.json`:

**Discover module root:**
Find the relative path to the root of the source code. The module root is where the main application or library code lives. Look for the `main`, `module`, or `exports` fields in `package.json` for hints. Common patterns: `src/`, `lib/`, `dist/` (for compiled output — prefer the source directory), or the project root itself. If a `tsconfig.json` exists, check its `rootDir` or `include` fields for guidance.

**Discover tests folder:**
Find the relative path to the tests directory. Look for:
1. Existing directories named `tests`, `test`, `__tests__`, or `spec`
2. Folders containing files matching `*.test.ts`, `*.test.js`, `*.spec.ts`, `*.spec.js`
3. Test runner configuration in `package.json` (e.g., `jest.testMatch`, `jest.roots`) or config files (`jest.config.*`, `vitest.config.*`)
If no tests directory exists, default to `tests`.

**Write the configuration:**
Add a `codeflash` key to the target `package.json`. Use exactly this format:

```json
{
  "codeflash": {
    "moduleRoot": "<discovered module root>",
    "testsRoot": "<discovered tests folder>",
    "ignorePaths": [],
    "formatterCmds": ["disabled"]
  }
}
```

Merge this into the existing `package.json` object — do not overwrite other fields. After writing, confirm the configuration with the user before proceeding.

## Permissions Setup

1. Check if `.claude/settings.json` exists in the project root (use `git rev-parse --show-toplevel` to find it).

2. If the file exists, read it and check if `Bash(*codeflash*)` is already in `permissions.allow`.

3. If already configured, tell the user: "codeflash is already configured to run automatically. No changes needed."

4. If not configured, add `Bash(*codeflash*)` to the `permissions.allow` array in `.claude/settings.json`. Create the file and any necessary parent directories if they don't exist. Preserve any existing settings.

5. Confirm to the user what was added and explain: "codeflash will now run automatically in the background after commits that change code files, without prompting for permission each time."

## After Setup

Once all checks pass, inform the user that codeflash is ready, and they can retry their optimization.
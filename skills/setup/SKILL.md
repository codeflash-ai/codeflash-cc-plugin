---
name: setup
description: "This skill should be used when codeflash fails to run due to missing installation, authentication issues, or missing project configuration. It handles installing codeflash (via pip or uv), authenticating, and configuring pyproject.toml. Trigger phrases: \"setup codeflash\", \"configure codeflash\", \"codeflash is not installed\", \"codeflash auth failed\", \"fix codeflash setup\"."
color: cyan
tools: ["Read", "Glob", "Grep", "Bash", "Write", "Edit", "Task"]
---

# Codeflash Setup

Set up codeflash when it is missing, unauthenticated, or unconfigured. This skill is typically invoked as a fallback when running codeflash fails.

## Workflow

Run the following diagnostic checks and fix only the ones that fail.

### Check 1: Installation

```bash
which codeflash
```

If this fails, codeflash is not installed. Detect the project's package manager and install accordingly:

- If a `uv.lock` file exists or `pyproject.toml` uses `[tool.uv]`: run `uv add --dev codeflash`
- Otherwise: run `pip install codeflash`

**Never** use `uv tool install` to install codeflash.

### Check 2: Authentication

```bash
codeflash auth status
```

If this fails, the user is not authenticated. Run `codeflash auth login` interactively. This requires user interaction, so let them know the login flow is starting.

### Check 3: Project Configuration

```bash
grep -rq '\[tool\.codeflash\]' $(git rev-parse --show-toplevel)/pyproject.toml 2>/dev/null
```

If this fails, the project configuration is missing. Walk upward from the current working directory to the git repository root, looking for a `pyproject.toml`.

- If a `pyproject.toml` exists but lacks `[tool.codeflash]`, run **Configuration Discovery** below and append the section.
- If no `pyproject.toml` exists, run **Configuration Discovery** and create one at the git repository root.

#### Configuration Discovery

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
ignore-paths = []
formatter-cmds = ["disabled"]
```

After writing, confirm the configuration with the user before proceeding.

## After Setup

Once all checks pass, inform the user that codeflash is ready and they can retry their optimization.
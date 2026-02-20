# Optimizer Agent Workflow

The optimizer agent (`agents/optimizer.md`) follows a strict 6-step workflow to run the codeflash CLI.

## Step 1: Detect Runner

Check for package manager lock files at the project root, in priority order:

| Lock File | Runner Command |
|-----------|---------------|
| `uv.lock` | `uv run` |
| `poetry.lock` | `poetry run` |
| `pdm.lock` | `pdm run` |
| `Pipfile.lock` | `pipenv run` |
| None found | Run `codeflash` directly |

First match wins. This ensures the correct virtual environment is used.

## Step 2: Verify Setup

Grep `pyproject.toml` for `[tool.codeflash]`. If the section is missing, the agent stops and tells the user to run `codeflash init`.

## Step 3: Verify Installation

Run `<runner> codeflash --worktree --version`. If the command fails (non-zero exit code), the agent stops and provides runner-specific installation instructions:
- uv: `uv add codeflash`
- poetry: `poetry add codeflash`
- pip: `pip install codeflash`

## Step 4: Parse Prompt

Extract from the task arguments:
- **file path** — Python file to optimize (e.g., `src/utils.py`)
- **function name** — Specific function to target (optional)
- **--all** — Optimize all functions in the project
- **--no-pr** — Skip automatic PR creation
- **--effort low|medium|high** — Optimization effort level
- Any other flags are passed through to codeflash

If no file and no `--all` flag is provided, default to `--all`.

## Step 5: Run Codeflash

Execute with a **10-minute timeout** (`timeout: 600000` in Bash tool):

```bash
# Specific file
<runner> codeflash --worktree --no-pr --file <path> [--function <name>] [flags]

# All files
<runner> codeflash --worktree --no-pr --all [flags]
```

The `--worktree` flag is **always** passed. It tells codeflash to work in a separate git worktree to avoid interfering with the user's working directory. --no-pr flag is always used.

## Step 6: Report Results

After codeflash completes, the agent summarizes:
1. Whether optimizations were found
2. Which files and functions were optimized
3. Performance improvements (if reported by codeflash)
4. Whether a PR was created

## CLI Flags Reference

| Flag | Description                                  |
|------|----------------------------------------------|
| `--worktree` | Run in a separate git worktree (always used) |
| `--file <path>` | Target a specific Python file                |
| `--function <name>` | Target a specific function within the file   |
| `--all` | Optimize all functions in the project        |
| `--no-pr` | Skip PR creation (always used)               |
| `--effort low\|medium\|high` | Set optimization effort level                |

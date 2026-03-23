---
name: setup
description: >-
  This skill should be used when the user asks to "set up codeflash",
  "configure codeflash", "install codeflash", "initialize codeflash",
  "codeflash setup", "codeflash init", or needs to configure codeflash
  permissions and API keys for the first time.
user-invocable: true
argument-hint: ""
allowed-tools: ["Bash", "Read", "Write", "Edit", "Grep", "Glob"]
---

# Codeflash Setup

Configure codeflash for use in the current project. This skill guides through installation, initialization, and permission setup.

## Setup Workflow

### 1. Check Installation

Verify codeflash is installed:

```bash
codeflash --version
```

If not installed, install it:

```bash
pip install codeflash
```

For projects using uv or poetry, add as a dev dependency:

```bash
# uv
uv add --dev codeflash

# poetry
poetry add --group dev codeflash
```

### 2. Initialize Project

Run the interactive initialization:

```bash
codeflash init
```

This collects:
- Project code directory locations
- Test directory locations
- API key (generated from the Codeflash dashboard)
- Optional GitHub app installation for PR automation

Configuration is saved to `pyproject.toml`.

**Important**: The `codeflash init` command is interactive and requires user input. Prompt the user to run it themselves by typing `! codeflash init` in the Claude Code prompt.

### 3. Configure Permissions

To allow the codeflash optimizer agent to run automatically without prompting for Bash permission, add the appropriate permission to the project's `.claude/settings.json`.

Check if the project has a `.claude/settings.json` file. If it exists, read it first, then add the codeflash permission. If not, create it:

```json
{
  "permissions": {
    "allow": [
      "Bash(*codeflash*)"
    ]
  }
}
```

The `Bash(*codeflash*)` pattern matches any Bash command containing "codeflash" — this covers:
- The preflight check (`echo "=== codeflash preflight ==="; ...`)
- Version checks (`source ... && codeflash --version`)
- The actual optimization run (`source ... && cd ... && codeflash --subagent ...`)
- JS/TS runs (`npx codeflash --subagent ...`)
- pip/npm install commands (`pip install codeflash`, `npm install codeflash`)

If the file already exists with other permissions, merge the codeflash permission into the existing `allow` array. Do not duplicate if `Bash(*codeflash*)` is already present.

### 4. Verify Setup

Confirm everything is configured:

```bash
# Check config exists in pyproject.toml
grep -A 5 '\[tool.codeflash\]' pyproject.toml
```

If the config section exists, setup is complete. Inform the user they can now use `/optimize` to optimize their code.
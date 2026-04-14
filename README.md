# Codeflash Claude Code Plugin

A minimal Claude Code plugin that runs [Codeflash](https://codeflash.ai) as a background agent to optimize Python, Java, JavaScript, and TypeScript code for performance.

## Prerequisites

- Claude Code v2.1.38 or later (check with `/status` if needed within claude code)
- **Python projects**: [codeflash](https://pypi.org/project/codeflash/) installed in a virtual environment, configured via `[tool.codeflash]` in `pyproject.toml`
- **Java projects**: [codeflash](https://pypi.org/project/codeflash/) installed (`pip install codeflash`)
- **JS/TS projects**: [codeflash](https://www.npmjs.com/package/codeflash) installed as a dev dependency (`npm install --save-dev codeflash`), configured via a `"codeflash"` key in `package.json`

## Installation

### From GitHub

Add the plugin marketplace and install:

```bash
/plugin marketplace add codeflash-ai/codeflash-cc-plugin
/plugin install codeflash
```

### Installation scope (optional)

By default, plugins are installed at the user level (available across all projects). You can change this:

```bash
/plugin install codeflash --scope project  # shared with team via .claude/settings.json
/plugin install codeflash --scope local    # this project only, gitignored
```

### Verify installation (optional)

Run `/plugin` to open the plugin manager and confirm codeflash appears under the **Installed** tab.

## Usage

### Optimize a file

```
/optimize --file src/utils.py
/optimize --file src/main/java/com/example/Fibonacci.java
```

### Optimize a specific function

```
/optimize --file src/utils.py --function my_function
/optimize --file src/main/java/com/example/Fibonacci.java --function fibonacci
```

### Optimize via Natural language instruction

```
make my_function run faster
```

### Auto-suggest after commits

When you make a git commit that includes Python, Java, JavaScript, or TypeScript file changes, the plugin suggests running `/optimize` on those files.

## Plugin Structure

```
codeflash-cc-plugin/
├── .claude-plugin/
│   ├── marketplace.json         # Marketplace manifest
│   └── plugin.json              # Plugin manifest
├── hooks/
│   └── hooks.json               # Stop hook for commit detection
├── scripts/
│   ├── find-venv.sh             # Shared helper: find and activate a Python venv
│   └── suggest-optimize.sh      # Detects Python/Java/JS/TS changes, suggests /optimize
├── skills/
│   ├── optimize/
│   │   └── SKILL.md             # /optimize slash command
│   └── setup/
│       └── SKILL.md             # /setup command for installation and configuration
└── README.md
```

## How It Works

The plugin is a thin wrapper around the `codeflash` CLI:

1. `/optimize` spawns a background optimizer agent
2. Verifies codeflash is installed (`pip install codeflash` for Python/Java, `npm install --save-dev codeflash` for JS/TS) and configured
3. Runs the `codeflash` CLI with the appropriate flags
4. Reports results (optimizations found, PRs created)

Codeflash handles everything else: analysis, benchmarking, test generation, and PR creation.

## Supported Languages

| Language | Config File | Project Markers |
|----------|------------|-----------------|
| Python | `pyproject.toml` | `pyproject.toml`, `setup.py` |
| Java | N/A | `pom.xml`, `build.gradle` |
| JavaScript | `package.json` | `package.json` |
| TypeScript | `package.json` | `package.json`, `tsconfig.json` |

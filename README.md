# Codeflash Claude Code Plugin

A minimal Claude Code plugin that runs [Codeflash](https://codeflash.ai) as a background agent to optimize Python code for performance.

## Installation

```bash
claude plugins add /path/to/codeflash-cc-plugin
```

## Prerequisites

- [codeflash](https://pypi.org/project/codeflash/) installed in your project
- Project initialized with `codeflash init` (creates `[tool.codeflash]` in `pyproject.toml`)

## Usage

### Optimize a file

```
/optimize src/utils.py
```

### Optimize a specific function

```
/optimize src/utils.py my_function
```

### Optimize the entire project

```
/optimize --all
```

### Additional flags

```
/optimize src/utils.py --no-pr          # Skip PR creation
/optimize src/utils.py --effort high    # Set optimization effort level
```

### Auto-suggest after commits

When you make a git commit that includes Python file changes, the plugin suggests running `/optimize` on those files.

## Plugin Structure

```
codeflash-cc-plugin/
├── .claude-plugin/
│   └── plugin.json              # Plugin manifest
├── agents/
│   └── optimizer.md             # Background optimization agent
├── hooks/
│   └── hooks.json               # UserPromptSubmit hook for commit detection
├── scripts/
│   └── suggest-optimize.sh      # Detects Python commits, suggests /optimize
├── skills/
│   └── optimize/
│       └── SKILL.md             # /optimize slash command
└── README.md
```

## How It Works

The plugin is a thin wrapper around the `codeflash` CLI:

1. `/optimize` spawns a background optimizer agent
2. The agent detects your project's package manager (uv, poetry, pdm, pipenv)
3. Verifies codeflash is installed and configured
4. Runs the `codeflash` CLI with the appropriate flags
5. Reports results (optimizations found, PRs created)

Codeflash handles everything else: analysis, benchmarking, test generation, and PR creation.

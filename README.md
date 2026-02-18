# Codeflash Claude Code Plugin

A minimal Claude Code plugin that runs [Codeflash](https://codeflash.ai) as a background agent to optimize Python code for performance.

## Prerequisites

- Claude Code v2.1.38 or later
- [codeflash](https://pypi.org/project/codeflash/) installed in your project
- If your project isn't initialized yet, the plugin will automatically run `codeflash init` when needed

## Installation

### From GitHub

Add the plugin marketplace and install:

```bash
/plugin marketplace add codeflash-ai/codeflash-cc-plugin
/plugin install codeflash
```

### From a local clone

```bash
git clone https://github.com/codeflash-ai/codeflash-cc-plugin.git
/plugin marketplace add ./codeflash-cc-plugin
/plugin install codeflash
```

### Installation scope

By default, plugins are installed at the user level (available across all projects). You can change this:

```bash
/plugin install codeflash --scope project  # shared with team via .claude/settings.json
/plugin install codeflash --scope local    # this project only, gitignored
```

### Verify installation

Run `/plugin` to open the plugin manager and confirm codeflash appears under the **Installed** tab.

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
│   ├── marketplace.json         # Marketplace manifest
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
3. Verifies codeflash is installed; if not configured, automatically runs `codeflash init`
4. Runs the `codeflash` CLI with the appropriate flags
5. Reports results (optimizations found, PRs created)

Codeflash handles everything else: analysis, benchmarking, test generation, and PR creation.

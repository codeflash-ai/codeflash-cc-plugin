# Plugin Architecture

## Directory Layout

```
codeflash-cc-plugin/
├── .claude-plugin/
│   ├── plugin.json          # Plugin identity and metadata
│   └── marketplace.json     # Marketplace registration manifest
├── agents/
│   └── optimizer.md         # Background optimizer agent definition
├── skills/
│   └── optimize/
│       └── SKILL.md         # /optimize slash command definition
├── hooks/
│   └── hooks.json           # Event hook registrations
├── scripts/
│   └── suggest-optimize.sh  # UserPromptSubmit hook script
└── README.md
```

## File Roles

- **`.claude-plugin/plugin.json`** — Plugin identity: name, version, author, license, keywords. This is what Claude Code reads to register the plugin.
- **`.claude-plugin/marketplace.json`** — Marketplace listing with owner info, `source` field pointing to `"./"`, and category `"development"`. Version here must stay in sync with plugin.json.
- **`agents/optimizer.md`** — YAML frontmatter + markdown body defining the optimizer agent. Frontmatter sets name, model, maxTurns, tools. Body contains the step-by-step workflow.
- **`skills/optimize/SKILL.md`** — YAML frontmatter defining the `/optimize` slash command. Maps to the optimizer agent via `agent: codeflash:optimizer`.
- **`hooks/hooks.json`** — Registers shell commands on Claude Code lifecycle events. Uses `${CLAUDE_PLUGIN_ROOT}` for portable paths.
- **`scripts/suggest-optimize.sh`** — Executable bash script invoked by the UserPromptSubmit hook. Detects Python commits and emits JSON to inject context.

## Versioning

- Version lives in two places: `plugin.json` and `marketplace.json`. Both must be updated together.
- Follow semver: patch for bug fixes, minor for new features, major for breaking changes.
- The `marketplace.json` has versions at both the top-level `metadata.version` and per-plugin `plugins[0].version`.

## Conventions

- All paths in hooks use `${CLAUDE_PLUGIN_ROOT}` — never hardcode absolute paths.
- The plugin is a thin wrapper around the `codeflash` CLI. It does not contain optimization logic itself.
- Agent markdown files use YAML frontmatter delimited by `---`.
- Skill SKILL.md files also use YAML frontmatter with specific fields (see agent-design rule).

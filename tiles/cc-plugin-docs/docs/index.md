# Codeflash Claude Code Plugin — Internal Docs

Internal documentation for the codeflash Claude Code plugin. This plugin wraps the `codeflash` CLI to optimize Python code for performance directly from Claude Code.

## Pages

- [Plugin Manifest](plugin-manifest.md) — plugin.json and marketplace.json schema, fields, and versioning
- [Skill System](skill-system.md) — SKILL.md frontmatter, how skills spawn agents, fork context
- [Optimizer Agent Workflow](optimizer-agent-workflow.md) — 6-step detect-verify-execute workflow
- [Hook Lifecycle](hook-lifecycle.md) — UserPromptSubmit event, hooks.json, suggest-optimize.sh flow

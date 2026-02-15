# Skill System

## SKILL.md Frontmatter

Skills are defined in `skills/<name>/SKILL.md` with YAML frontmatter:

```yaml
---
name: optimize
description: Optimize Python code for performance using Codeflash
user-invocable: true
argument-hint: "[file] [function] [--all] [--no-pr] [--effort low|medium|high]"
context: fork
agent: codeflash:optimizer
allowed-tools: Task
---
```

### Field Reference

| Field | Type | Description |
|-------|------|-------------|
| `name` | string | Slash command name (e.g., `optimize` → `/optimize`). |
| `description` | string | One-line description shown in help. |
| `user-invocable` | boolean | If `true`, users can trigger via `/name`. |
| `argument-hint` | string | Shown after `/name` in autocomplete. Documents accepted args. |
| `context` | `"fork"` or `"inline"` | `fork` runs in a separate context; `inline` runs in the current conversation. |
| `agent` | string | Agent to spawn, in format `<plugin>:<agent-name>`. |
| `allowed-tools` | string | Comma-separated tools the skill can use. |

## How Skills Spawn Agents

When a user invokes `/optimize src/foo.py my_func --effort high`:

1. Claude Code reads `skills/optimize/SKILL.md` frontmatter.
2. `context: fork` causes a new conversation fork (separate context).
3. `agent: codeflash:optimizer` spawns the agent defined in `agents/optimizer.md`.
4. The skill body template is rendered with `$ARGUMENTS` replaced by user input.
5. The rendered prompt is sent to the agent as its task.

## Fork Context

With `context: fork`, the skill runs in isolation:
- It gets its own conversation context, separate from the user's main thread.
- The agent's tool calls don't appear in the user's conversation history.
- Results are reported back to the user when the agent completes.
- This is ideal for long-running operations like codeflash optimization.

## Adding a New Skill

1. Create `skills/<name>/SKILL.md` with appropriate frontmatter.
2. If the skill needs a dedicated agent, create `agents/<name>.md`.
3. Set `agent: codeflash:<agent-name>` to link the skill to the agent.
4. Set `user-invocable: true` if users should trigger it directly.

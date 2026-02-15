# Plugin Manifest

## plugin.json

Located at `.claude-plugin/plugin.json`. This is the primary identity file Claude Code reads when registering a plugin.

### Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Plugin identifier. Must match across plugin.json and marketplace.json. |
| `description` | string | Yes | One-line description shown in plugin listings. |
| `version` | string | Yes | Semver version (e.g., `"0.1.1"`). |
| `author.name` | string | Yes | Author display name. |
| `author.url` | string | No | Author website URL. |
| `repository` | string | No | GitHub repository URL. |
| `homepage` | string | No | Project homepage URL. |
| `license` | string | Yes | SPDX license identifier (e.g., `"MIT"`). |
| `keywords` | string[] | No | Tags for discovery. |

### Example

```json
{
  "name": "codeflash",
  "description": "Run codeflash as a background agent to optimize Python code for performance",
  "version": "0.1.1",
  "author": {
    "name": "Codeflash",
    "url": "https://codeflash.ai"
  },
  "repository": "https://github.com/codeflash-ai/codeflash-cc-plugin",
  "homepage": "https://codeflash.ai",
  "license": "MIT",
  "keywords": ["python", "optimization", "performance", "codeflash"]
}
```

## marketplace.json

Located at `.claude-plugin/marketplace.json`. Used for marketplace registration and discovery.

### Top-Level Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `$schema` | string | Yes | Always `"https://anthropic.com/claude-code/marketplace.schema.json"`. |
| `name` | string | Yes | Marketplace listing name. Must match plugin name. |
| `owner.name` | string | Yes | Organization or individual name. |
| `owner.email` | string | Yes | Contact email. |
| `metadata.description` | string | Yes | Marketplace description. |
| `metadata.version` | string | Yes | Must match the plugin version. |
| `plugins` | array | Yes | Array of plugin entries (usually one). |

### Plugin Entry Fields

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `name` | string | Yes | Must match top-level name. |
| `description` | string | Yes | Plugin description. |
| `version` | string | Yes | Must match metadata.version. |
| `author.name` | string | Yes | Author display name. |
| `author.email` | string | Yes | Author contact email. |
| `source` | string | Yes | Relative path to plugin root. Use `"./"` for root-level plugins. |
| `category` | string | Yes | Plugin category (e.g., `"development"`). |

## Versioning Rules

1. All three version fields must be in sync: `plugin.json:version`, `marketplace.json:metadata.version`, `marketplace.json:plugins[0].version`.
2. Use semver: `MAJOR.MINOR.PATCH`.
3. Bump patch for bug fixes, minor for new features, major for breaking changes.

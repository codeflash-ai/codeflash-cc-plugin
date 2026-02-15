# Scenario 3: Register Plugin in a New Marketplace

## Context

A hypothetical new Claude Code marketplace has launched with slightly different requirements. You need to prepare the codeflash plugin for registration by understanding the current manifest structure and adapting it.

The new marketplace requires:
- A `registry.json` file with fields: `name`, `version`, `author_email`, `description`, `source_url`, `license`, `tags`
- The version must match the plugin's canonical version

## Task

1. Identify all version fields in the current plugin manifests and their current values
2. Explain the relationship between plugin.json and marketplace.json
3. Create the `registry.json` by mapping fields from the existing manifests:
   - `name` from plugin.json name
   - `version` from plugin.json version (canonical source)
   - `author_email` from marketplace.json owner.email
   - `description` from plugin.json description
   - `source_url` from plugin.json repository
   - `license` from plugin.json license
   - `tags` from plugin.json keywords

## Expected Outputs

- Identification of all 3 version locations: plugin.json version, marketplace.json metadata.version, marketplace.json plugins[0].version
- Correct field mapping from both manifest files
- Valid registry.json with correct values extracted from current manifests

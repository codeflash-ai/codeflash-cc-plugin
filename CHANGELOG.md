# Changelog

All notable changes to the CodeFlash Claude Code Plugin will be documented in this file.

## [0.2.0] - 2026-03-05

### Added
- **Session-based deduplication**: Hook now tracks Claude session ID and only prompts once per session, preventing repetitive suggestions when making multiple commits
- **Environment variable opt-out**: Added `CODEFLASH_NO_AUTO_OPTIMIZE=1` to disable auto-suggestions for current session
- **Project-level opt-out**: Added `auto-optimize = false` configuration option in `[tool.codeflash]` section of `pyproject.toml`
- **Improved messaging**: Hook messages are now more conversational and less directive, giving Claude more judgment about when to interrupt the user
- **Opt-out documentation**: Hook output now includes instructions for disabling auto-optimization

### Changed
- Moved git commit check earlier in script for better performance (early exit before expensive operations)
- Updated hook message tone to be suggestive rather than directive

### Fixed
- Fixed issue where hook would trigger on every commit in a session, causing annoying repetitive prompts
- Reduced hook overhead for non-commit Bash commands by checking for git commit earlier

## Previous Versions

Prior to this changelog, the plugin was at version 0.1.5.
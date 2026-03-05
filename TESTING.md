# Testing Guide

This guide helps verify the improved hook behavior after the UX improvements.

## Prerequisites

1. Install the plugin from the local source:
   ```bash
   cd /Users/aseemsaxena/Downloads/codeflash_dev/codeflash-cc-plugin
   /plugin marketplace add .
   /plugin install codeflash
   ```

2. Have a test Python project with git initialized

## Test Cases

### Test 1: Session-based Deduplication

**Objective:** Verify hook only triggers once per Claude session

**Steps:**
1. Start a new Claude Code session in a Python git repository
2. Make a commit that changes Python files (e.g., `echo "# test" >> test.py && git add test.py && git commit -m "test: first commit"`)
3. Observe that Claude suggests running codeflash optimization
4. Make another commit with Python changes (e.g., `echo "# test2" >> test.py && git add test.py && git commit -m "test: second commit"`)
5. Observe that Claude does NOT suggest optimization again

**Expected Result:**
- First commit: Hook triggers, Claude suggests optimization
- Second commit: Hook does NOT trigger (same session)
- New session + commit: Hook triggers again

**Pass Criteria:** Hook only triggers once per session ID

---

### Test 2: Early Exit Performance

**Objective:** Verify hook exits quickly for non-git-commit Bash commands

**Steps:**
1. Use Bash tool for various commands:
   ```bash
   ls -la
   cat some_file.py
   grep "pattern" *.py
   git status
   git diff
   ```
2. None of these should trigger the hook

**Expected Result:** Hook exits immediately without expensive operations (git, jq, grep)

**Pass Criteria:** Hook only proceeds past line 15 for `git commit` commands

---

### Test 3: Environment Variable Opt-out

**Objective:** Verify `CODEFLASH_NO_AUTO_OPTIMIZE=1` disables the hook

**Steps:**
1. Set environment variable: `export CODEFLASH_NO_AUTO_OPTIMIZE=1`
2. Make a git commit with Python changes
3. Observe that Claude does NOT suggest optimization
4. Unset variable: `unset CODEFLASH_NO_AUTO_OPTIMIZE`
5. Make another commit with Python changes
6. Observe that Claude DOES suggest optimization

**Expected Result:**
- With env var set: Hook exits silently at line 18-20
- Without env var: Hook proceeds normally

**Pass Criteria:** Environment variable successfully disables hook

---

### Test 4: Project Configuration Opt-out

**Objective:** Verify `auto-optimize = false` in pyproject.toml disables hook

**Steps:**
1. Add to `pyproject.toml`:
   ```toml
   [tool.codeflash]
   auto-optimize = false
   ```
2. Make a git commit with Python changes
3. Observe that Claude does NOT suggest optimization
4. Remove or set to `true`:
   ```toml
   [tool.codeflash]
   auto-optimize = true
   ```
5. Make another commit
6. Observe that Claude DOES suggest optimization

**Expected Result:**
- With `auto-optimize = false`: Hook exits at line 115-117
- With `auto-optimize = true` or absent: Hook proceeds normally

**Pass Criteria:** Configuration successfully disables hook

---

### Test 5: Improved Messaging

**Objective:** Verify hook messages are conversational and include opt-out instructions

**Steps:**
1. Trigger the hook by making a Python commit in a configured project
2. Read Claude's response

**Expected Result:**
Message should include:
- "You can optimize them for performance by running:" (suggestive, not directive)
- "Consider running this in the background..." (gives Claude discretion)
- "This is optional and only if relevant..." (non-intrusive)
- Instructions for disabling via `auto-optimize = false`
- Instructions for session-level disable via `CODEFLASH_NO_AUTO_OPTIMIZE=1`

**Pass Criteria:** Message tone is helpful but not pushy, includes opt-out info

---

### Test 6: Cross-session Persistence

**Objective:** Verify per-commit tracking still works across sessions

**Steps:**
1. Make commit with HEAD abc123 in session 1
2. Hook triggers, session marker created
3. Exit Claude, start new session 2
4. DO NOT make a new commit (same HEAD)
5. Run a different Bash command that might trigger hook evaluation

**Expected Result:**
- Session 1: Hook triggers
- Session 2 (same HEAD): Hook exits at line 88-90 (already handled this commit)
- Session 2 (new commit): Hook triggers again (new HEAD, new session)

**Pass Criteria:** Per-commit tracking prevents duplicate suggestions across sessions for same commit

---

## Debugging

### Check session marker files
```bash
ls -la /tmp/.codeflash-session-*
```

### Check per-commit tracker files
```bash
ls -la /tmp/.codeflash-last-suggested-*
cat /tmp/.codeflash-last-suggested-<hash>  # Should show last seen commit SHA
```

### Manually test hook script
```bash
# Simulate hook input
echo '{"session_id": "test-session-123", "tool_input": {"command": "git commit -m test"}}' | \
  /Users/aseemsaxena/Downloads/codeflash_dev/codeflash-cc-plugin/scripts/suggest-optimize.sh
```

### Enable debug mode
Add `set -x` after `set -euo pipefail` in `suggest-optimize.sh` to see execution trace:
```bash
set -euo pipefail
set -x  # Enable debug trace
```

## Performance Verification

### Baseline (non-commit commands)
Should exit in <10ms:
```bash
time echo '{"tool_input": {"command": "ls"}}' | \
  /path/to/suggest-optimize.sh
```

### With commit (session dedup)
First call: 100-500ms (runs full logic)
Second call: <10ms (exits at session check)

## Rollback

If issues occur, revert to previous version:
```bash
cd /Users/aseemsaxena/Downloads/codeflash_dev/codeflash-cc-plugin
git log --oneline  # Find previous commit
git checkout <previous-commit-sha> scripts/suggest-optimize.sh
```
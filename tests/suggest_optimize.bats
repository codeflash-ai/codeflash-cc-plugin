#!/usr/bin/env bats

load test_helper

# --- detect_any_config tests ---

@test "detect_any_config finds codeflash.toml" {
  mkdir -p "$TEST_DIR"
  printf '[tool.codeflash]\nmodule-root = "src/main/java"\n' > "$TEST_DIR/codeflash.toml"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"codeflash.toml"* ]]
  [ "$PROJECT_DIR" = "$TEST_DIR" ]
}

@test "detect_any_config finds pyproject.toml" {
  mkdir -p "$TEST_DIR"
  printf '[tool.codeflash]\nmodule-root = "src"\n' > "$TEST_DIR/pyproject.toml"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"pyproject.toml"* ]]
}

@test "detect_any_config finds package.json with codeflash key" {
  mkdir -p "$TEST_DIR"
  echo '{"codeflash": {"moduleRoot": "src"}}' > "$TEST_DIR/package.json"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"package.json"* ]]
}

@test "detect_any_config finds multiple config types" {
  mkdir -p "$TEST_DIR"
  printf '[tool.codeflash]\nmodule-root = "src"\n' > "$TEST_DIR/pyproject.toml"
  printf '[tool.codeflash]\nmodule-root = "src/main/java"\n' > "$TEST_DIR/codeflash.toml"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"pyproject.toml"* ]]
  [[ "$FOUND_CONFIGS" == *"codeflash.toml"* ]]
}

@test "detect_any_config returns false when no config found" {
  mkdir -p "$TEST_DIR"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "false" ]
  [ -z "$FOUND_CONFIGS" ]
}

@test "detect_any_config skips package.json without codeflash key" {
  mkdir -p "$TEST_DIR"
  echo '{"name": "my-project", "version": "1.0.0"}' > "$TEST_DIR/package.json"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "false" ]
}

@test "detect_any_config skips pyproject.toml without codeflash section" {
  mkdir -p "$TEST_DIR"
  printf '[tool.black]\nline-length = 120\n' > "$TEST_DIR/pyproject.toml"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "false" ]
}

@test "detect_any_config finds pom.xml (Java zero-config)" {
  mkdir -p "$TEST_DIR"
  printf '<project><modelVersion>4.0.0</modelVersion></project>\n' > "$TEST_DIR/pom.xml"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"java-build-file"* ]]
  [ "$PROJECT_DIR" = "$TEST_DIR" ]
}

@test "detect_any_config finds build.gradle (Java zero-config)" {
  mkdir -p "$TEST_DIR"
  printf 'plugins { id "java" }\n' > "$TEST_DIR/build.gradle"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"java-build-file"* ]]
}

@test "detect_any_config finds all three config types" {
  mkdir -p "$TEST_DIR"
  printf '[tool.codeflash]\nmodule-root = "src"\n' > "$TEST_DIR/pyproject.toml"
  printf '[tool.codeflash]\nmodule-root = "src/main/java"\n' > "$TEST_DIR/codeflash.toml"
  echo '{"codeflash": {"moduleRoot": "src"}}' > "$TEST_DIR/package.json"
  load_hook_functions
  detect_any_config
  [ "$PROJECT_CONFIGURED" = "true" ]
  [[ "$FOUND_CONFIGS" == *"codeflash.toml"* ]]
  [[ "$FOUND_CONFIGS" == *"pyproject.toml"* ]]
  [[ "$FOUND_CONFIGS" == *"package.json"* ]]
}

# --- find_codeflash_binary tests ---

@test "find_codeflash_binary finds binary in PATH" {
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho "codeflash 1.0"\n' > "$TEST_DIR/bin/codeflash"
  chmod +x "$TEST_DIR/bin/codeflash"
  export PATH="$TEST_DIR/bin:$PATH"
  load_hook_functions
  find_codeflash_binary
  [ "$CODEFLASH_INSTALLED" = "true" ]
  [ "$CODEFLASH_BIN" = "codeflash" ]
}

@test "find_codeflash_binary finds binary in venv" {
  mkdir -p "$TEST_DIR/venv/bin"
  printf '#!/bin/bash\necho "codeflash 1.0"\n' > "$TEST_DIR/venv/bin/codeflash"
  chmod +x "$TEST_DIR/venv/bin/codeflash"
  export VIRTUAL_ENV="$TEST_DIR/venv"
  load_hook_functions
  find_codeflash_binary
  [ "$CODEFLASH_INSTALLED" = "true" ]
  [ "$CODEFLASH_BIN" = "$TEST_DIR/venv/bin/codeflash" ]
}

@test "find_codeflash_binary reports not installed when missing" {
  load_hook_functions
  # Save PATH and use an empty directory so codeflash/uv/npx are all unavailable
  local saved_path="$PATH"
  mkdir -p "$TEST_DIR/empty_bin"
  export PATH="$TEST_DIR/empty_bin"
  unset VIRTUAL_ENV
  hash -r 2>/dev/null || true
  find_codeflash_binary
  # Restore PATH before assertions so teardown can work
  export PATH="$saved_path"
  [ "$CODEFLASH_INSTALLED" = "false" ]
  [ -z "$CODEFLASH_BIN" ]
}

@test "find_codeflash_binary prefers venv over PATH" {
  mkdir -p "$TEST_DIR/venv/bin"
  printf '#!/bin/bash\necho "venv codeflash"\n' > "$TEST_DIR/venv/bin/codeflash"
  chmod +x "$TEST_DIR/venv/bin/codeflash"
  mkdir -p "$TEST_DIR/bin"
  printf '#!/bin/bash\necho "path codeflash"\n' > "$TEST_DIR/bin/codeflash"
  chmod +x "$TEST_DIR/bin/codeflash"
  export VIRTUAL_ENV="$TEST_DIR/venv"
  export PATH="$TEST_DIR/bin:$PATH"
  load_hook_functions
  find_codeflash_binary
  [ "$CODEFLASH_INSTALLED" = "true" ]
  [ "$CODEFLASH_BIN" = "$TEST_DIR/venv/bin/codeflash" ]
}

# --- detect_changed_languages tests ---

@test "detect_changed_languages detects python" {
  export CHANGED_FILES="src/main.py
tests/test_utils.py"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"python"* ]]
}

@test "detect_changed_languages detects java" {
  export CHANGED_FILES="src/Main.java"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"java"* ]]
}

@test "detect_changed_languages detects javascript from ts and jsx" {
  export CHANGED_FILES="src/App.tsx
src/utils.js"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"javascript"* ]]
}

@test "detect_changed_languages detects mixed languages" {
  export CHANGED_FILES="src/main.py
src/Main.java
src/app.ts"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"python"* ]]
  [[ "$CHANGED_LANGS" == *"java"* ]]
  [[ "$CHANGED_LANGS" == *"javascript"* ]]
}

@test "detect_changed_languages returns empty for no recognized files" {
  export CHANGED_FILES="README.md
Makefile"
  load_hook_functions
  detect_changed_languages
  [ -z "$CHANGED_LANGS" ]
}

@test "detect_changed_languages detects js from .jsx files" {
  export CHANGED_FILES="src/Component.jsx"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"javascript"* ]]
}

@test "detect_changed_languages detects js from .tsx files" {
  export CHANGED_FILES="src/Page.tsx"
  load_hook_functions
  detect_changed_languages
  [[ "$CHANGED_LANGS" == *"javascript"* ]]
}

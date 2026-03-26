#!/usr/bin/env bash
# lib/claude.sh - Claude CLI installation validation

set -euo pipefail

# claude_is_installed
# Returns 0 if the claude binary is found in PATH, 1 otherwise.
claude_is_installed() {
  command -v claude >/dev/null 2>&1
}

# claude_validate
# Validates that claude CLI is installed and callable.
# Prints actionable error messages to stderr and returns 1 if not found.
claude_validate() {
  if claude_is_installed; then
    return 0
  fi
  echo "ERROR: Claude CLI is not installed or not found in PATH." >&2
  echo "Install Claude CLI: https://claude.ai/download" >&2
  echo "Then ensure the claude binary is available in your PATH." >&2
  echo "Current PATH: ${PATH}" >&2
  return 1
}

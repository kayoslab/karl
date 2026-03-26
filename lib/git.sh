#!/usr/bin/env bash
# git.sh - Git repository detection and initialization

set -euo pipefail

# git_repo_check <dir>
# Returns 0 if <dir> is inside a git repository, 1 otherwise.
# Prints a warning to stderr when no repository is detected.
git_repo_check() {
  local dir="${1:?directory required}"

  if git -C "${dir}" rev-parse --git-dir > /dev/null 2>&1; then
    return 0
  fi

  echo "WARNING: No git repository found in ${dir}. Git is required for branch-based workflow." >&2
  return 1
}

# git_init_repo <dir> [auto_init]
# Initialize a new git repository in <dir> with a default 'main' branch.
# If auto_init is "true", initializes without prompting.
# Otherwise, prompts the operator for confirmation.
# Prints an error and returns 1 on failure.
git_init_repo() {
  local dir="${1:?directory required}"
  local auto_init="${2:-false}"

  if [[ "${auto_init}" != "true" ]]; then
    echo "WARNING: No git repository in ${dir}. Initialize a new repository? [y/N]: " >&2
    local answer
    read -r answer
    if [[ "${answer}" != "y" && "${answer}" != "Y" ]]; then
      echo "ERROR: Git initialization declined. Aborting." >&2
      return 1
    fi
  fi

  if ! git -C "${dir}" init -b main > /dev/null 2>&1; then
    echo "ERROR: git init failed in ${dir}. Aborting." >&2
    return 1
  fi

  git -C "${dir}" config user.email "karl@localhost" > /dev/null 2>&1 || true
  git -C "${dir}" config user.name "karl" > /dev/null 2>&1 || true

  # Stage all existing workspace files so main starts with the full baseline
  git -C "${dir}" add -A > /dev/null 2>&1 || true

  if ! git -C "${dir}" commit --allow-empty -m "chore: initialize repository" > /dev/null 2>&1; then
    echo "ERROR: Failed to create initial commit in ${dir}. Aborting." >&2
    return 1
  fi

  echo "karl: git repository initialized with branch 'main' in ${dir}"
  return 0
}

# git_ensure_repo <dir> [auto_init]
# Checks for a git repository; initializes one if absent.
# Returns 1 and exits with error if initialization fails.
git_ensure_repo() {
  local dir="${1:?directory required}"
  local auto_init="${2:-false}"

  if git_repo_check "${dir}"; then
    return 0
  fi

  git_init_repo "${dir}" "${auto_init}"
}

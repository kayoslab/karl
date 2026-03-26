#!/usr/bin/env bash
# branch.sh - Deterministic gitflow branch naming and creation for karl

set -euo pipefail

# branch_name <ticket_id> <ticket_title>
# Produces a deterministic branch name: feature/<ticket_id>-<slug>
# Slug rules: lowercase, spaces/underscores to hyphens, strip non-alphanumeric,
# collapse consecutive hyphens, trim leading/trailing hyphens.
branch_name() {
  local ticket_id="${1:?ticket_id required}"
  local ticket_title="${2:?ticket_title required}"

  local slug
  slug=$(printf '%s' "${ticket_title}" \
    | tr '[:upper:]' '[:lower:]' \
    | tr '_' '-' \
    | tr ' ' '-' \
    | sed -E 's/[^a-z0-9-]//g' \
    | sed -E 's/-+/-/g' \
    | sed -E 's/^-+|-+$//g')

  printf 'feature/%s-%s\n' "${ticket_id}" "${slug}"
}

# branch_ensure <workspace_root> <branch> <base> [worktree_mode]
# Creates the branch from base if it does not exist, or checks it out if it does.
# When worktree_mode is "true", skips checkout (worktree already has the branch).
# Returns 0 on success, 1 on failure with ERROR message.
branch_ensure() {
  local workspace_root="${1:?workspace_root required}"
  local branch="${2:?branch required}"
  local base="${3:-main}"
  local worktree_mode="${4:-false}"

  # In worktree mode, the branch is already set up by worktree_create
  if [[ "${worktree_mode}" == "true" ]]; then
    echo "Worktree mode: branch ${branch} managed by worktree"
    return 0
  fi

  # Untrack LOCK if git is still tracking it (prevents checkout conflicts)
  if git -C "${workspace_root}" ls-files --error-unmatch LOCK > /dev/null 2>&1; then
    git -C "${workspace_root}" rm --cached LOCK > /dev/null 2>&1 || true
  fi

  # Commit any outstanding changes so checkout doesn't fail
  if ! git -C "${workspace_root}" diff --quiet 2>/dev/null || \
     ! git -C "${workspace_root}" diff --cached --quiet 2>/dev/null; then
    git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
    git -C "${workspace_root}" commit \
      -m "chore: commit outstanding changes before branch switch" \
      > /dev/null 2>&1 || true
  fi

  if git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    echo "Reusing existing branch: ${branch}"
    if ! git -C "${workspace_root}" checkout "${branch}" 2>&1; then
      echo "ERROR: failed to checkout existing branch: ${branch}"
      return 1
    fi
    return 0
  fi

  echo "Creating branch: ${branch} from ${base}"
  if ! git -C "${workspace_root}" checkout -b "${branch}" "${base}" 2>&1; then
    echo "ERROR: failed to create branch '${branch}' from base '${base}'"
    return 1
  fi
  return 0
}

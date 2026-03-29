#!/usr/bin/env bash
# worktree.sh - Git worktree lifecycle management for karl multi-instance mode

set -euo pipefail

# worktree_base_dir <workspace_root> [custom_dir]
# Returns the base directory for karl worktrees.
# Defaults to ../.karl-worktrees relative to workspace_root.
worktree_base_dir() {
  local workspace_root="${1:?workspace_root required}"
  local custom_dir="${2:-}"

  if [[ -n "${custom_dir}" ]]; then
    printf '%s\n' "${custom_dir}"
  else
    local resolved
    resolved=$(cd "${workspace_root}" && pwd -P)
    printf '%s-worktrees\n' "${resolved}"
  fi
}

# worktree_path <ticket_id> [base_dir]
# Returns the expected worktree path for a ticket without creating it.
worktree_path() {
  local ticket_id="${1:?ticket_id required}"
  local base_dir="${2:?base_dir required}"

  # Sanitize ticket_id for use as directory name (replace dots with dashes)
  local safe_id
  safe_id=$(printf '%s' "${ticket_id}" | tr '.' '-')
  printf '%s/%s\n' "${base_dir}" "${safe_id}"
}

# worktree_create <workspace_root> <ticket_id> <branch> [base_dir]
# Creates a git worktree for the given ticket branching from main.
# Returns 0 on success, 1 on failure.
worktree_create() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local branch="${3:?branch required}"
  local base_dir="${4:-}"

  if [[ -z "${base_dir}" ]]; then
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  local wt_path
  wt_path=$(worktree_path "${ticket_id}" "${base_dir}")

  mkdir -p "${base_dir}"

  if [[ -d "${wt_path}" ]]; then
    echo "[worktree] Worktree already exists at ${wt_path}" >&2
    return 0
  fi

  # Clean up stale branch from a previous failed run if needed
  if git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
    echo "[worktree] Removing stale branch ${branch}" >&2
    git -C "${workspace_root}" branch -D "${branch}" 2>/dev/null || true
  fi

  if ! git -C "${workspace_root}" worktree add -b "${branch}" "${wt_path}" main 2>&1; then
    echo "ERROR: Failed to create worktree for ${ticket_id} at ${wt_path}" >&2
    return 1
  fi

  echo "[worktree] Created worktree for ${ticket_id} at ${wt_path}"
  return 0
}

# worktree_remove <workspace_root> <ticket_id> [base_dir]
# Removes the worktree for the given ticket and prunes.
# Returns 0 on success (idempotent).
worktree_remove() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local base_dir="${3:-}"

  if [[ -z "${base_dir}" ]]; then
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  local wt_path
  wt_path=$(worktree_path "${ticket_id}" "${base_dir}")

  if [[ -d "${wt_path}" ]]; then
    git -C "${workspace_root}" worktree remove --force "${wt_path}" 2>/dev/null || \
      rm -rf "${wt_path}"
  fi

  git -C "${workspace_root}" worktree prune 2>/dev/null || true

  echo "[worktree] Removed worktree for ${ticket_id}"
  return 0
}

# worktree_exists <workspace_root> <ticket_id> [base_dir]
# Returns 0 if the worktree for the ticket exists, 1 otherwise.
worktree_exists() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local base_dir="${3:-}"

  if [[ -z "${base_dir}" ]]; then
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  local wt_path
  wt_path=$(worktree_path "${ticket_id}" "${base_dir}")

  [[ -d "${wt_path}" ]]
}

# worktree_list <workspace_root>
# Lists active karl worktrees (paths under the worktree base directory).
# Prints one path per line.
worktree_list() {
  local workspace_root="${1:?workspace_root required}"

  # Resolve the main workspace path for reliable comparison (macOS symlinks)
  local resolved_root
  resolved_root=$(cd "${workspace_root}" && pwd -P)

  git -C "${workspace_root}" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { sub(/^worktree /, ""); print }' \
    | while IFS= read -r wt; do
        # Skip the main worktree
        local resolved_wt
        resolved_wt=$(cd "${wt}" 2>/dev/null && pwd -P) || continue
        if [[ "${resolved_wt}" != "${resolved_root}" ]]; then
          printf '%s\n' "${wt}"
        fi
      done
}

# worktree_cleanup_all <workspace_root> [base_dir]
# Remove all karl worktrees under the base directory and prune.
worktree_cleanup_all() {
  local workspace_root="${1:?workspace_root required}"
  local base_dir="${2:-}"

  if [[ -z "${base_dir}" ]]; then
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  if [[ -d "${base_dir}" ]]; then
    # Remove each worktree via git
    local wt
    for wt in "${base_dir}"/*/; do
      if [[ -d "${wt}" ]]; then
        git -C "${workspace_root}" worktree remove --force "${wt}" 2>/dev/null || \
          rm -rf "${wt}"
      fi
    done

    git -C "${workspace_root}" worktree prune 2>/dev/null || true

    # Remove the base directory if empty
    rmdir "${base_dir}" 2>/dev/null || true
  fi

  echo "[worktree] Cleaned up all worktrees"
  return 0
}

#!/usr/bin/env bash
# clean.sh - Repository recovery: reset to clean baseline after broken ticket

set -euo pipefail

# clean_checkout_main <workspace>
# Checks out the main branch in the given workspace.
# Returns 0 on success, 1 if main branch does not exist.
clean_checkout_main() {
  local workspace="${1:?workspace required}"

  if ! git -C "${workspace}" checkout main > /dev/null 2>&1; then
    echo "ERROR: Failed to checkout main branch in ${workspace}" >&2
    return 1
  fi
  echo "karl clean: checked out main branch"
}

# clean_discard_changes <workspace>
# Discards all uncommitted tracked file changes.
clean_discard_changes() {
  local workspace="${1:?workspace required}"

  git -C "${workspace}" checkout -- . 2>/dev/null || true
  echo "karl clean: discard uncommitted changes complete"
}

# clean_delete_branch <workspace> <branch>
# Deletes a feature branch. Returns 0 if deleted or branch does not exist.
# Returns 1 if the branch is currently checked out.
clean_delete_branch() {
  local workspace="${1:?workspace required}"
  local branch="${2:?branch required}"

  if ! git -C "${workspace}" rev-parse --verify "${branch}" > /dev/null 2>&1; then
    echo "karl clean: Nothing to delete — branch does not exist: ${branch}"
    return 0
  fi

  local current_branch
  current_branch=$(git -C "${workspace}" rev-parse --abbrev-ref HEAD)
  if [ "${current_branch}" = "${branch}" ]; then
    echo "ERROR: Cannot delete currently checked-out branch: ${branch}" >&2
    return 1
  fi

  if ! git -C "${workspace}" branch -D "${branch}" > /dev/null 2>&1; then
    echo "ERROR: Failed to delete branch: ${branch}" >&2
    return 1
  fi
  echo "karl clean: Deleted branch ${branch}"
}

# clean_remove_lock <workspace>
# Removes LOCK files including Finder/iCloud sync duplicates (LOCK 2, LOCK 3, etc.)
clean_remove_lock() {
  local workspace="${1:?workspace required}"
  local found=0

  # Use find to handle filenames with spaces (LOCK 2, LOCK 3, etc.)
  while IFS= read -r -d '' f; do
    rm -f "${f}"
    found=1
  done < <(find "${workspace}" -maxdepth 1 -name 'LOCK*' -print0 2>/dev/null)

  if [[ "${found}" -eq 1 ]]; then
    echo "karl clean: Removed LOCK file(s)"
  else
    echo "karl clean: No LOCK file present"
  fi
}

# clean_remove_lockdirs <workspace>
# Removes .prd.lockdir and .merge.lockdir if present.
clean_remove_lockdirs() {
  local workspace="${1:?workspace required}"

  if [ -d "${workspace}/.prd.lockdir" ]; then
    rmdir "${workspace}/.prd.lockdir" 2>/dev/null || rm -rf "${workspace}/.prd.lockdir"
    echo "karl clean: Removed .prd.lockdir"
  fi

  if [ -d "${workspace}/.merge.lockdir" ]; then
    rmdir "${workspace}/.merge.lockdir" 2>/dev/null || rm -rf "${workspace}/.merge.lockdir"
    echo "karl clean: Removed .merge.lockdir"
  fi
}

# clean_worktrees <workspace>
# Enumerates and removes orphaned karl worktrees.
clean_worktrees() {
  local workspace="${1:?workspace required}"

  # Check for worktrees from git, skipping the main worktree
  local resolved_workspace
  resolved_workspace=$(cd "${workspace}" 2>/dev/null && pwd -P) || resolved_workspace="${workspace}"

  local wt_count=0
  while IFS= read -r wt; do
    if [[ -z "${wt}" ]]; then
      continue
    fi
    local resolved_wt
    resolved_wt=$(cd "${wt}" 2>/dev/null && pwd -P) || resolved_wt="${wt}"
    if [[ "${resolved_wt}" != "${resolved_workspace}" ]]; then
      git -C "${workspace}" worktree remove --force "${wt}" 2>/dev/null || \
        rm -rf "${wt}"
      wt_count=$((wt_count + 1))
    fi
  done < <(git -C "${workspace}" worktree list --porcelain 2>/dev/null \
    | awk '/^worktree / { sub(/^worktree /, ""); print }')

  git -C "${workspace}" worktree prune 2>/dev/null || true

  # Also try to clean up the default worktree base directory
  local parent_dir
  parent_dir=$(cd "${workspace}" 2>/dev/null && cd .. 2>/dev/null && pwd) || true
  if [[ -n "${parent_dir}" && -d "${parent_dir}/.karl-worktrees" ]]; then
    rm -rf "${parent_dir}/.karl-worktrees"
    echo "karl clean: Removed .karl-worktrees directory"
  fi

  if [[ "${wt_count}" -gt 0 ]]; then
    echo "karl clean: Removed ${wt_count} worktree(s)"
  fi
}

# clean_run <workspace> <force>
# Orchestrates full cleanup workflow.
# force=true: also discards uncommitted tracked changes
# force=false: warns about uncommitted changes but leaves them intact
clean_run() {
  local workspace="${1:?workspace required}"
  local force="${2:-false}"

  echo "karl clean: starting repository recovery"

  # Capture active branch before checking out main so we can delete it after
  local active_branch
  active_branch=$(git -C "${workspace}" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

  # Clean up worktrees before branch operations
  clean_worktrees "${workspace}"

  clean_checkout_main "${workspace}"
  clean_remove_lock "${workspace}"
  clean_remove_lockdirs "${workspace}"

  # Delete the previously active feature branch when it is safe to do so
  if [[ "${active_branch}" == feature/* ]]; then
    clean_delete_branch "${workspace}" "${active_branch}" || true
  fi

  if ! git -C "${workspace}" diff --quiet 2>/dev/null || \
     ! git -C "${workspace}" diff --cached --quiet 2>/dev/null; then
    if [ "${force}" = "true" ]; then
      clean_discard_changes "${workspace}"
    else
      echo "WARNING: Uncommitted changes present. Use --force to discard them."
    fi
  fi

  echo "karl clean: recovery complete — workspace reset to baseline"
}

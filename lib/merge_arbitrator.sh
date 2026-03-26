#!/usr/bin/env bash
# merge_arbitrator.sh - Serialized merge with conflict resolution for multi-instance karl

set -euo pipefail

# merge_arbitrator_acquire <workspace_root>
# Acquire the merge lock via mkdir (POSIX-atomic).
# Spins with timeout (~60s). Returns 0 on success, 1 on timeout.
merge_arbitrator_acquire() {
  local workspace_root="${1:?workspace_root required}"
  local lockdir="${workspace_root}/.merge.lockdir"
  local attempts=0
  local max_attempts=120

  while ! mkdir "${lockdir}" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${max_attempts}" ]]; then
      echo "ERROR: Timed out waiting for merge lock at ${lockdir}" >&2
      return 1
    fi
    sleep 0.5
  done

  return 0
}

# merge_arbitrator_release <workspace_root>
# Release the merge lock.
merge_arbitrator_release() {
  local workspace_root="${1:?workspace_root required}"
  local lockdir="${workspace_root}/.merge.lockdir"

  rmdir "${lockdir}" 2>/dev/null || true
}

# merge_arbitrator_merge <workspace_root> <worktree_path> <ticket_id> <branch>
# Serialized merge workflow:
#   1. Acquire merge lock
#   2. Dry-run merge-tree check
#   3. If conflicts: log warning (agent invocation optional)
#   4. If clean: merge to main, update prd, append progress
#   5. Release lock
# Returns 0 on success, 1 on failure.
merge_arbitrator_merge() {
  local workspace_root="${1:?workspace_root required}"
  local wt_path="${2:?worktree_path required}"
  local ticket_id="${3:?ticket_id required}"
  local branch="${4:?branch required}"

  echo "[merge_arbitrator] Acquiring merge lock for ${ticket_id}..."
  if ! merge_arbitrator_acquire "${workspace_root}"; then
    echo "ERROR: Could not acquire merge lock for ${ticket_id}" >&2
    return 1
  fi

  # Ensure we always release the lock
  local merge_rc=0
  _merge_arbitrator_do_merge "${workspace_root}" "${wt_path}" "${ticket_id}" "${branch}" || merge_rc=$?

  merge_arbitrator_release "${workspace_root}"

  return "${merge_rc}"
}

# _merge_arbitrator_do_merge <workspace_root> <worktree_path> <ticket_id> <branch>
# Internal: performs the actual merge while lock is held.
_merge_arbitrator_do_merge() {
  local workspace_root="${1:?workspace_root required}"
  local wt_path="${2:?worktree_path required}"
  local ticket_id="${3:?ticket_id required}"
  local branch="${4:?branch required}"

  # Commit any outstanding changes in the worktree
  if git -C "${wt_path}" rev-parse --git-dir > /dev/null 2>&1; then
    if ! git -C "${wt_path}" diff --quiet 2>/dev/null || \
       ! git -C "${wt_path}" diff --cached --quiet 2>/dev/null; then
      git -C "${wt_path}" add -A > /dev/null 2>&1 || true
      git -C "${wt_path}" commit \
        -m "chore: [${ticket_id}] commit outstanding changes before merge" \
        > /dev/null 2>&1 || true
    fi
  fi

  # Dry-run merge check via merge-tree
  local merge_base
  if ! merge_base=$(git -C "${workspace_root}" merge-base main "${branch}" 2>/dev/null); then
    echo "ERROR: Could not determine merge base for ${branch}" >&2
    return 1
  fi

  local merge_output
  merge_output=$(git -C "${workspace_root}" merge-tree "${merge_base}" main "${branch}" 2>/dev/null) || true

  if printf '%s' "${merge_output}" | grep -q '<<<<<<'; then
    echo "WARNING: Merge conflicts detected for ${ticket_id} on branch ${branch}" >&2
    echo "[merge_arbitrator] Conflicts detected — marking ticket as failed" >&2
    return 1
  fi

  # Perform the actual merge on main
  echo "[merge_arbitrator] Merging ${branch} to main for ${ticket_id}..."
  git -C "${workspace_root}" checkout main > /dev/null 2>&1 || return 1
  if ! git -C "${workspace_root}" merge "${branch}" -m "feat: [${ticket_id}] merge from worktree" > /dev/null 2>&1; then
    echo "ERROR: Merge failed for ${ticket_id}" >&2
    # Abort the merge if it's in a conflicted state
    git -C "${workspace_root}" merge --abort 2>/dev/null || true
    return 1
  fi

  # Update prd.json: mark ticket as complete
  if type -t prd_complete_ticket > /dev/null 2>&1; then
    prd_complete_ticket "${workspace_root}" "${ticket_id}" || true
  else
    # Fallback: use commit_update_prd if available
    if type -t commit_update_prd > /dev/null 2>&1; then
      commit_update_prd "${workspace_root}" "${ticket_id}" || true
    fi
  fi

  # Append to progress.md
  mkdir -p "${workspace_root}/Output"
  printf '## %s: merged from worktree\n\n' "${ticket_id}" >> "${workspace_root}/Output/progress.md"

  # Commit prd and progress updates
  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit \
    -m "chore: [${ticket_id}] mark passes=true and update progress log" \
    > /dev/null 2>&1 || true

  # Clean up the feature branch
  git -C "${workspace_root}" branch -d "${branch}" > /dev/null 2>&1 || true

  echo "[merge_arbitrator] Successfully merged ${ticket_id}"
  return 0
}

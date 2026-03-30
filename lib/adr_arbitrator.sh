#!/usr/bin/env bash
# adr_arbitrator.sh - Serialized ADR synchronization for multi-instance karl
#
# In multi-instance mode, each worker's architect runs in an isolated worktree.
# Without synchronization, parallel architects cannot see each other's ADRs.
# This module serializes architect invocations and fast-tracks new ADRs to main
# using git plumbing (no checkout required).

set -euo pipefail

# adr_arbitrator_acquire <main_repo_root>
# Acquire the ADR lock via mkdir (POSIX-atomic).
# Spins with timeout (~60s). Returns 0 on success, 1 on timeout.
adr_arbitrator_acquire() {
  local main_repo_root="${1:?main_repo_root required}"
  local lockdir="${main_repo_root}/.adr.lockdir"
  local attempts=0
  local max_attempts=120

  while ! mkdir "${lockdir}" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${max_attempts}" ]]; then
      echo "ERROR: Timed out waiting for ADR lock at ${lockdir}" >&2
      return 1
    fi
    sleep 0.5
  done

  return 0
}

# adr_arbitrator_release <main_repo_root>
# Release the ADR lock.
adr_arbitrator_release() {
  local main_repo_root="${1:?main_repo_root required}"
  local lockdir="${main_repo_root}/.adr.lockdir"

  rmdir "${lockdir}" 2>/dev/null || true
}

# adr_sync_from_main <main_repo_root> <worktree_path>
# Copy all ADRs from the main branch into the worktree so the architect
# sees decisions made by other workers since the branch point.
adr_sync_from_main() {
  local main_repo_root="${1:?main_repo_root required}"
  local wt_path="${2:?worktree_path required}"

  # List ADR files on main (may be empty if no ADRs exist yet)
  local adr_files
  adr_files=$(git -C "${main_repo_root}" ls-tree --name-only main Output/ADR/ 2>/dev/null || true)

  if [[ -z "${adr_files}" ]]; then
    return 0
  fi

  mkdir -p "${wt_path}/Output/ADR"

  local filepath
  while IFS= read -r filepath; do
    [[ -z "${filepath}" ]] && continue
    local filename
    filename=$(basename "${filepath}")
    git -C "${main_repo_root}" show "main:${filepath}" > "${wt_path}/Output/ADR/${filename}" 2>/dev/null || true
  done <<< "${adr_files}"

  git -C "${wt_path}" add Output/ADR/ > /dev/null 2>&1 || true
}

# adr_fast_track_to_main <main_repo_root> <adr_file_path> <story_id>
# Commit the ADR file directly to the main branch using git plumbing.
# This avoids checking out main, which is unsafe when worktrees are active.
adr_fast_track_to_main() {
  local main_repo_root="${1:?main_repo_root required}"
  local adr_file_path="${2:?adr_file_path required}"
  local story_id="${3:?story_id required}"

  local tmp_index="${main_repo_root}/.adr-index.$$"
  local rc=0

  _adr_fast_track_plumbing "${main_repo_root}" "${adr_file_path}" "${story_id}" "${tmp_index}" || rc=$?

  # Always clean up temp index
  rm -f "${tmp_index}"

  return "${rc}"
}

# _adr_fast_track_plumbing <main_repo_root> <adr_file_path> <story_id> <tmp_index>
# Internal: git plumbing operations for fast-tracking an ADR to main.
_adr_fast_track_plumbing() {
  local main_repo_root="${1}"
  local adr_file_path="${2}"
  local story_id="${3}"
  local tmp_index="${4}"

  # Create blob from the ADR file
  local blob
  blob=$(git -C "${main_repo_root}" hash-object -w "${adr_file_path}")

  # Read current main tree into a temporary index
  GIT_INDEX_FILE="${tmp_index}" git -C "${main_repo_root}" read-tree main

  # Add/update the ADR file in the temp index
  GIT_INDEX_FILE="${tmp_index}" git -C "${main_repo_root}" \
    update-index --add --cacheinfo "100644,${blob},Output/ADR/${story_id}.md"

  # Write the tree object
  local tree
  tree=$(GIT_INDEX_FILE="${tmp_index}" git -C "${main_repo_root}" write-tree)

  # Create a commit with the current main as parent
  local parent
  parent=$(git -C "${main_repo_root}" rev-parse main)

  local commit
  commit=$(echo "adr: [${story_id}] fast-track ADR to main" | \
    git -C "${main_repo_root}" commit-tree "${tree}" -p "${parent}")

  # Atomically update main to point to the new commit
  git -C "${main_repo_root}" update-ref refs/heads/main "${commit}"
}

# adr_arbitrator_run <main_repo_root> <worktree_path> <story_json> <plan_json>
# Top-level entry point: acquire lock, run architect with synced ADRs,
# fast-track any new ADR to main, release lock.
# Returns 0 on success, 1 on failure. Lock is always released.
adr_arbitrator_run() {
  local main_repo_root="${1:?main_repo_root required}"
  local wt_path="${2:?worktree_path required}"
  local story_json="${3:?story_json required}"
  local plan_json="${4:-}"

  echo "[adr_arbitrator] Acquiring ADR lock..."
  if ! adr_arbitrator_acquire "${main_repo_root}"; then
    echo "ERROR: Could not acquire ADR lock" >&2
    return 1
  fi

  local rc=0
  _adr_arbitrator_do_run "${main_repo_root}" "${wt_path}" "${story_json}" "${plan_json}" || rc=$?

  adr_arbitrator_release "${main_repo_root}"

  return "${rc}"
}

# _adr_arbitrator_do_run <main_repo_root> <worktree_path> <story_json> <plan_json>
# Internal: runs while the ADR lock is held.
_adr_arbitrator_do_run() {
  local main_repo_root="${1:?main_repo_root required}"
  local wt_path="${2:?worktree_path required}"
  local story_json="${3:?story_json required}"
  local plan_json="${4:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')

  # Pull latest ADRs from main into the worktree
  adr_sync_from_main "${main_repo_root}" "${wt_path}"

  # Run the architect agent (operates on the worktree)
  if ! architect_run "${wt_path}" "${story_json}" "${plan_json}"; then
    echo "ERROR: Architect agent failed for ${story_id}" >&2
    return 1
  fi

  # If a new ADR was created, fast-track it to main
  local adr_file="${wt_path}/Output/ADR/${story_id}.md"
  if [[ -f "${adr_file}" ]]; then
    echo "[adr_arbitrator] Fast-tracking ADR for ${story_id} to main..."
    if ! adr_fast_track_to_main "${main_repo_root}" "${adr_file}" "${story_id}"; then
      echo "ERROR: Failed to fast-track ADR for ${story_id}" >&2
      return 1
    fi
  fi

  return 0
}

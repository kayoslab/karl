#!/usr/bin/env bash
# lib/commit.sh - Commit, merge to main, and record iteration results (US-016)

set -euo pipefail

# commit_update_prd <workspace_root> <ticket_id>
# Sets passes=true for the given ticket_id in Input/prd.json.
# Returns 0 on success, non-zero if prd.json is absent.
commit_update_prd() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  local updated
  updated=$(jq --arg id "${ticket_id}" \
    'if type == "array"
     then [.[] | if .id == $id then .passes = true else . end]
     else .userStories = [.userStories[] | if .id == $id then .passes = true else . end]
     end' \
    "${prd_file}")

  printf '%s\n' "${updated}" > "${prd_file}"
}

# commit_merge_to_main <workspace_root> <branch>
# Merges the given branch into main and switches HEAD to main.
# Returns 0 on success, non-zero if the branch does not exist or merge fails.
commit_merge_to_main() {
  local workspace_root="${1:?workspace_root required}"
  local branch="${2:?branch required}"

  if ! git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/${branch}"; then
    echo "ERROR: branch '${branch}' does not exist" >&2
    return 1
  fi

  git -C "${workspace_root}" checkout main > /dev/null 2>&1 || return 1
  git -C "${workspace_root}" merge "${branch}" > /dev/null 2>&1 || return 1
}

# commit_finalize <workspace_root> <ticket_id> <branch> <summary> [worktree_path]
# Orchestrates the full post-success commit workflow:
#   1. Merge feature branch to main via commit_merge_to_main
#   2. Update passes=true in prd.json via commit_update_prd (only after merge succeeds)
#   3. Append concise entry to Output/progress.md
#   4. Delete the feature branch (and worktree if worktree_path is set)
# Returns 0 on success, non-zero if the merge fails (PRD and progress are not modified).
commit_finalize() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local branch="${3:?branch required}"
  local summary="${4:?summary required}"
  local wt_path="${5:-}"

  # Step 1: Merge feature branch to main; halt here on failure so PRD and
  # progress are never modified unless the merge has actually landed on main.
  if ! commit_merge_to_main "${workspace_root}" "${branch}"; then
    echo "ERROR: Merge failed for ${ticket_id}" >&2
    return 1
  fi

  # Step 2: Update passes=true in prd.json (commit_update_prd is called here,
  # after merge succeeds — not before).
  commit_update_prd "${workspace_root}" "${ticket_id}" || return 1

  # Step 3: Append iteration summary to Output/progress.md
  mkdir -p "${workspace_root}/Output"
  printf '## %s: %s\n\n' "${ticket_id}" "${summary}" >> "${workspace_root}/Output/progress.md"

  # Step 4: Commit prd.json and progress.md updates to main
  local prd_file="${workspace_root}/Input/prd.json"
  local progress_file="${workspace_root}/Output/progress.md"
  git -C "${workspace_root}" add "${prd_file}" "${progress_file}" 2>/dev/null || true
  git -C "${workspace_root}" commit \
    -m "chore: [${ticket_id}] mark passes=true and update progress log" \
    > /dev/null 2>&1 || true

  # Step 5: Clean up feature branch (best-effort; ignore if already gone)
  git -C "${workspace_root}" branch -d "${branch}" > /dev/null 2>&1 || true

  # Step 6: Clean up worktree if running in worktree mode
  if [[ -n "${wt_path}" && -d "${wt_path}" ]]; then
    git -C "${workspace_root}" worktree remove --force "${wt_path}" 2>/dev/null || \
      rm -rf "${wt_path}"
    git -C "${workspace_root}" worktree prune 2>/dev/null || true
  fi

  return 0
}

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

# merge_arbitrator_merge <workspace_root> <worktree_path> <ticket_id> <branch> [summary]
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
  local summary="${5:-merged from worktree}"

  echo "[merge_arbitrator] Acquiring merge lock for ${ticket_id}..."
  if ! merge_arbitrator_acquire "${workspace_root}"; then
    echo "ERROR: Could not acquire merge lock for ${ticket_id}" >&2
    return 1
  fi

  # Ensure we always release the lock
  local merge_rc=0
  _merge_arbitrator_do_merge "${workspace_root}" "${wt_path}" "${ticket_id}" "${branch}" "${summary}" || merge_rc=$?

  merge_arbitrator_release "${workspace_root}"

  return "${merge_rc}"
}

# _merge_arbitrator_do_merge <workspace_root> <worktree_path> <ticket_id> <branch> <summary>
# Internal: performs the actual merge while lock is held.
_merge_arbitrator_do_merge() {
  local workspace_root="${1:?workspace_root required}"
  local wt_path="${2:?worktree_path required}"
  local ticket_id="${3:?ticket_id required}"
  local branch="${4:?branch required}"
  local summary="${5:-merged from worktree}"

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

  if printf '%s\n' "${merge_output}" | grep -q '<<<<<<'; then
    echo "[merge_arbitrator] Potential conflicts detected for ${ticket_id} — will attempt resolution" >&2
  fi

  # Perform the actual merge on main
  echo "[merge_arbitrator] Merging ${branch} to main for ${ticket_id}..."

  # Stash dirty workspace state (prd.json modified by ticket claiming, or
  # index out of sync from ADR fast-track commits via update-ref)
  local stashed="false"
  if ! git -C "${workspace_root}" diff --quiet 2>/dev/null || \
     ! git -C "${workspace_root}" diff --cached --quiet 2>/dev/null; then
    git -C "${workspace_root}" stash push -q --include-untracked 2>/dev/null && stashed="true"
  fi

  # Reset index to match HEAD before checkout (update-ref from ADR fast-track
  # can leave the index pointing at an older tree)
  git -C "${workspace_root}" reset --mixed HEAD > /dev/null 2>&1 || true

  if ! git -C "${workspace_root}" checkout main > /dev/null 2>&1; then
    echo "ERROR: Could not checkout main in ${workspace_root}" >&2
    [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash pop -q 2>/dev/null || true
    return 1
  fi

  local merge_err
  if ! merge_err=$(git -C "${workspace_root}" merge "${branch}" -m "feat: [${ticket_id}] merge from worktree" 2>&1); then
    # Merge has conflicts — try agent-based resolution
    echo "[merge_arbitrator] Merge conflicts for ${ticket_id} — invoking merge-resolver agent..." >&2

    # Get list of conflicted files
    local conflicted_files
    conflicted_files=$(git -C "${workspace_root}" diff --name-only --diff-filter=U 2>/dev/null || true)

    if [[ -z "${conflicted_files}" ]]; then
      echo "ERROR: Merge failed for ${ticket_id} (non-conflict error): ${merge_err}" >&2
      git -C "${workspace_root}" merge --abort 2>/dev/null || true
      [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash pop -q 2>/dev/null || true
      return 1
    fi

    # Gather context for the merge-resolver
    local main_diff
    main_diff=$(git -C "${workspace_root}" diff HEAD 2>/dev/null || true)

    # What the feature branch was implementing (plan + ticket context from worktree)
    local feature_context=""
    local plan_file="${wt_path}/Output/${ticket_id}/plan.json"
    if [[ -f "${plan_file}" ]]; then
      feature_context=$(jq -r '
        "Ticket: " + (.ticket // "unknown") + "\n" +
        "Summary: " + (.summary // .title // "unknown") + "\n" +
        "Steps: " + ((.steps // []) | map(if type == "string" then . else (.description // .title // tostring) end) | join("; "))
      ' "${plan_file}" 2>/dev/null) || true
    fi
    [[ -z "${feature_context}" ]] && feature_context="Ticket ${ticket_id}: ${summary}"

    # What changed on main since the branch point (other merged features)
    local main_changes=""
    main_changes=$(git -C "${workspace_root}" log --oneline "${merge_base}..main" 2>/dev/null | head -20) || true

    # Invoke the merge-resolver agent to fix conflicts
    local resolve_prompt
    resolve_prompt="Resolve the merge conflicts in this repository. The working directory is ${workspace_root}.

## Feature Branch Context
This branch implements:
${feature_context}

## Changes on main since this branch was created
${main_changes:-No other changes}

## Conflicted files
${conflicted_files}

## Conflict diff
${main_diff}

## Resolution instructions
For each conflicted file:
1. Read the file and find the conflict markers (<<<<<<< ======= >>>>>>>)
2. Resolve the conflict by combining both sides appropriately — both the feature branch changes AND the main branch changes should be preserved
3. Remove all conflict markers
4. Stage the resolved file with git add

For Input/prd.json: keep the main branch version (use git checkout --theirs Input/prd.json then git add).
For Output/progress.md: keep the main branch version.

After resolving ALL conflicts, return your JSON summary."

    local resolve_response
    if resolve_response=$(cd "${workspace_root}" && subagent_invoke_json "merge-resolver" "${resolve_prompt}" "${SCHEMA_MERGE_RESOLVER:-}" 2>/dev/null); then
      local resolution
      resolution=$(printf '%s' "${resolve_response}" | jq -r '
        (.resolution // .status // .result // "unresolvable")
        | if test("^resolve"; "i") then "resolved" else "unresolvable" end' 2>/dev/null) || resolution="unresolvable"

      if [[ "${resolution}" == "resolved" ]]; then
        # Check if all conflicts are actually resolved (no remaining markers)
        local remaining_conflicts
        remaining_conflicts=$(git -C "${workspace_root}" diff --name-only --diff-filter=U 2>/dev/null || true)

        if [[ -z "${remaining_conflicts}" ]]; then
          echo "[merge_arbitrator] Conflicts resolved by agent for ${ticket_id}" >&2
          git -C "${workspace_root}" commit -m "feat: [${ticket_id}] merge from worktree (conflicts resolved)" > /dev/null 2>&1
          # Drop stash and continue to post-merge steps
          [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash drop -q 2>/dev/null || true
        else
          echo "ERROR: Agent claimed resolution but conflicts remain for ${ticket_id}" >&2
          git -C "${workspace_root}" merge --abort 2>/dev/null || true
          [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash pop -q 2>/dev/null || true
          return 1
        fi
      else
        echo "ERROR: Agent could not resolve conflicts for ${ticket_id}" >&2
        git -C "${workspace_root}" merge --abort 2>/dev/null || true
        [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash pop -q 2>/dev/null || true
        return 1
      fi
    else
      echo "ERROR: Merge-resolver agent failed for ${ticket_id}" >&2
      git -C "${workspace_root}" merge --abort 2>/dev/null || true
      [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash pop -q 2>/dev/null || true
      return 1
    fi
  else
    # Clean merge — drop stash
    [[ "${stashed}" == "true" ]] && git -C "${workspace_root}" stash drop -q 2>/dev/null || true
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
  printf '## %s: %s\n\n' "${ticket_id}" "${summary}" >> "${workspace_root}/Output/progress.md"

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

#!/usr/bin/env bash
# loop.sh - Main ticket loop for karl

set -euo pipefail

# loop_run_ticket <workspace_root> <story_json> <branch> [max_retries] [skip_finalize] [main_repo_root]
# Runs the full agent pipeline for a single ticket via subagents.
# When skip_finalize is "true", stops after the pipeline (caller handles merge).
# When main_repo_root is set and differs from workspace_root (worktree mode),
# the architect phase uses adr_arbitrator_run for synchronized ADR access.
# Returns 0 on success (ticket complete), 1 on failure.
loop_run_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local branch="${3:?branch required}"
  local max_retries="${4:-10}"
  local skip_finalize="${5:-false}"
  local main_repo_root="${6:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')

  local tech=""
  [[ -f "${workspace_root}/Output/tech.md" ]] && tech=$(cat "${workspace_root}/Output/tech.md")

  # --- Planning ---
  echo "[loop] Running planning for ${story_id}..."
  if ! planning_run_loop "${workspace_root}" "${story_json}" "${tech}"; then
    echo "ERROR: Planning failed for ${story_id}" >&2
    return 1
  fi

  local plan_json=""
  [[ -f "${workspace_root}/Output/${story_id}/plan.json" ]] && plan_json=$(cat "${workspace_root}/Output/${story_id}/plan.json")

  # --- Architecture ---
  echo "[loop] Running architect for ${story_id}..."
  if [[ -n "${main_repo_root}" && "${main_repo_root}" != "${workspace_root}" ]]; then
    # Multi-instance: serialized ADR access via arbitrator
    if ! adr_arbitrator_run "${main_repo_root}" "${workspace_root}" "${story_json}" "${plan_json}"; then
      echo "ERROR: Architect failed for ${story_id}" >&2
      return 1
    fi
  else
    # Single-instance: direct architect call (no locking needed)
    if ! architect_run "${workspace_root}" "${story_json}" "${plan_json}"; then
      echo "ERROR: Architect failed for ${story_id}" >&2
      return 1
    fi
  fi

  # --- Test generation ---
  echo "[loop] Generating tests for ${story_id}..."
  if ! tester_generate "${workspace_root}" "${story_json}" "${plan_json}" "${tech}"; then
    echo "ERROR: Test generation failed for ${story_id}" >&2
    return 1
  fi

  # --- Rework loop (developer + tester) ---
  echo "[loop] Starting rework loop for ${story_id}..."
  if ! rework_loop "${workspace_root}" "${story_id}" "${story_json}" "${max_retries}"; then
    echo "ERROR: Rework loop exhausted for ${story_id}" >&2
    return 1
  fi

  # --- Deployment gate ---
  echo "[loop] Running deployment gate for ${story_id}..."
  if ! deploy_gate "${workspace_root}" "${story_json}" "${plan_json}" "${tech}"; then
    echo "ERROR: Deployment gate failed for ${story_id}" >&2
    return 1
  fi

  # --- Commit outstanding changes ---
  if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
    if ! git -C "${workspace_root}" diff --quiet 2>/dev/null || \
       ! git -C "${workspace_root}" diff --cached --quiet 2>/dev/null; then
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit \
        -m "chore: [${story_id}] commit outstanding changes before merge" \
        > /dev/null 2>&1 || true
    fi
  fi

  # In worktree mode, the supervisor handles merge
  if [[ "${skip_finalize}" == "true" ]]; then
    echo "[loop] Ticket ${story_id} pipeline complete (merge deferred to supervisor)"
    return 0
  fi

  # --- Merge safety check ---
  echo "[loop] Checking merge safety for ${story_id}..."
  if ! merge_safe_check "${workspace_root}" "${story_id}" "${branch}"; then
    echo "ERROR: Merge safety check failed for ${story_id}" >&2
    return 1
  fi

  # --- Finalize ---
  echo "[loop] Finalizing ${story_id}..."
  local summary
  summary=$(printf '%s' "${story_json}" | jq -r '.title // "completed"')
  if ! commit_finalize "${workspace_root}" "${story_id}" "${branch}" "${summary}"; then
    echo "ERROR: Finalize failed for ${story_id}" >&2
    return 1
  fi

  echo "[loop] Ticket ${story_id} complete"
  return 0
}

# loop_run_iteration <workspace_root> [max_retries]
loop_run_iteration() {
  local workspace_root="${1:?workspace_root required}"
  local max_retries="${2:-10}"

  local story rc=0
  story=$(prd_select_next "${workspace_root}") || rc=$?

  if [[ "${rc}" -eq 2 ]] || [[ "${rc}" -eq 3 ]]; then
    echo "karl: all stories complete — nothing left to do"
    return 2
  fi
  [[ "${rc}" -ne 0 ]] && return 1

  local story_id story_title branch
  story_id=$(printf '%s' "${story}" | jq -r '.id // "unknown"')
  story_title=$(printf '%s' "${story}" | jq -r '.title // ""')
  echo "karl: selected story ${story_id}"
  echo "karl: Retry limit for this ticket: ${max_retries}"

  branch=$(branch_name "${story_id}" "${story_title}")

  if ! branch_ensure "${workspace_root}" "${branch}" "main"; then
    echo "ERROR: failed to prepare branch for story ${story_id}"
    return 1
  fi

  if ! loop_run_ticket "${workspace_root}" "${story}" "${branch}" "${max_retries}"; then
    echo "ERROR: Ticket ${story_id} failed"
    return 1
  fi

  return 0
}

# loop_run <workspace_root> [max_retries]
loop_run() {
  local workspace_root="${1:?workspace_root required}"
  local max_retries="${2:-10}"

  while true; do
    local rc=0
    loop_run_iteration "${workspace_root}" "${max_retries}" || rc=$?
    [[ "${rc}" -eq 2 ]] && return 0
    [[ "${rc}" -ne 0 ]] && return 1
  done
}

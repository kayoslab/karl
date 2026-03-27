#!/usr/bin/env bash
# loop.sh - Main ticket loop for karl

set -euo pipefail

# loop_run_ticket <workspace_root> <story_json> <branch> [max_retries] [skip_finalize]
# Runs the full agent pipeline for a single ticket on the current feature branch.
# When skip_finalize is "true", stops after the deployment gate (caller handles merge).
# Returns 0 on success (ticket complete), 1 on failure.
loop_run_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local branch="${3:?branch required}"
  local max_retries="${4:-10}"
  local skip_finalize="${5:-false}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')

  local agents_dir="${KARL_DIR}/Agents"

  # Read tech context (may be empty on first run; tech_discover will create it)
  local tech=""
  if [[ -f "${workspace_root}/Output/tech.md" ]]; then
    tech=$(cat "${workspace_root}/Output/tech.md")
  fi

  # --- Planning ---
  echo "[loop] Running planning for ${story_id}..."
  if ! planning_run_loop "${agents_dir}" "${workspace_root}" "${story_json}" "${tech}"; then
    echo "ERROR: Planning failed for ${story_id}" >&2
    return 1
  fi

  local plan_json=""
  if [[ -f "${workspace_root}/Output/${story_id}/plan.json" ]]; then
    plan_json=$(cat "${workspace_root}/Output/${story_id}/plan.json")
  fi

  # --- Architecture ---
  echo "[loop] Running architect for ${story_id}..."
  if ! architect_run "${agents_dir}" "${workspace_root}" "${story_json}" "${plan_json}"; then
    echo "ERROR: Architect failed for ${story_id}" >&2
    return 1
  fi

  # --- Test generation ---
  echo "[loop] Generating tests for ${story_id}..."
  if ! tester_generate "${agents_dir}" "${workspace_root}" "${story_json}" "${plan_json}" "${tech}"; then
    echo "ERROR: Test generation failed for ${story_id}" >&2
    return 1
  fi

  # --- Rework loop (developer ↔ tester) ---
  echo "[loop] Starting rework loop for ${story_id}..."
  if ! rework_loop "${workspace_root}" "${story_id}" "${story_json}" "${max_retries}"; then
    echo "ERROR: Rework loop exhausted for ${story_id}" >&2
    return 1
  fi

  # --- Deployment gate ---
  echo "[loop] Running deployment gate for ${story_id}..."
  if ! deploy_gate "${agents_dir}" "${workspace_root}" "${story_json}" "${plan_json}" "${tech}"; then
    echo "ERROR: Deployment gate failed for ${story_id}" >&2
    return 1
  fi

  # --- Commit any outstanding changes before merge ---
  if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
    if ! git -C "${workspace_root}" diff --quiet 2>/dev/null || \
       ! git -C "${workspace_root}" diff --cached --quiet 2>/dev/null; then
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit \
        -m "chore: [${story_id}] commit outstanding changes before merge" \
        > /dev/null 2>&1 || true
    fi
  fi

  # In worktree mode, the supervisor handles merge via merge_arbitrator_merge
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

  # --- Finalize: merge to main, mark passes=true, update progress ---
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
# Selects the next unfinished story and runs it.
# Returns 0 if a story was selected and processed.
# Returns 2 if all stories are complete (clean exit).
# Returns 1 on error.
loop_run_iteration() {
  local workspace_root="${1:?workspace_root required}"
  local max_retries="${2:-10}"

  local story rc=0
  story=$(prd_select_next "${workspace_root}") || rc=$?

  if [[ "${rc}" -eq 2 ]] || [[ "${rc}" -eq 3 ]]; then
    echo "karl: all stories complete — nothing left to do"
    return 2
  fi

  if [[ "${rc}" -ne 0 ]]; then
    return 1
  fi

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
# Runs the ticket loop until all stories are complete or an error occurs.
# Exits cleanly (return 0) when all stories pass.
loop_run() {
  local workspace_root="${1:?workspace_root required}"
  local max_retries="${2:-10}"

  while true; do
    local rc=0
    loop_run_iteration "${workspace_root}" "${max_retries}" || rc=$?

    if [[ "${rc}" -eq 2 ]]; then
      return 0
    fi

    if [[ "${rc}" -ne 0 ]]; then
      return 1
    fi
  done
}

#!/usr/bin/env bash
# supervisor.sh - Spawn and monitor N parallel workers for multi-instance karl

set -euo pipefail

# supervisor_worker_loop <workspace_root> <instance_id> <max_retries> [worktree_dir]
# Worker loop: claim ticket → create worktree → run ticket → merge → cleanup → repeat.
# Returns 0 when no more tickets are available, 1 on fatal error.
supervisor_worker_loop() {
  local workspace_root="${1:?workspace_root required}"
  local instance_id="${2:?instance_id required}"
  local max_retries="${3:-10}"
  local worktree_dir="${4:-}"

  local base_dir
  if [[ -n "${worktree_dir}" ]]; then
    base_dir="${worktree_dir}"
  else
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  echo "[worker-${instance_id}] Starting worker loop"

  while true; do
    # Find the next available ticket
    local story rc=0
    story=$(prd_select_next "${workspace_root}") || rc=$?

    if [[ "${rc}" -eq 2 ]]; then
      echo "[worker-${instance_id}] All stories complete"
      return 0
    fi

    if [[ "${rc}" -ne 0 ]]; then
      echo "[worker-${instance_id}] Error reading PRD" >&2
      return 1
    fi

    local story_id story_title
    story_id=$(printf '%s' "${story}" | jq -r '.id // "unknown"')
    story_title=$(printf '%s' "${story}" | jq -r '.title // ""')

    # Try to claim the ticket atomically
    if ! prd_claim_ticket "${workspace_root}" "${story_id}" "worker-${instance_id}" 2>/dev/null; then
      # Another worker claimed it; try next
      sleep 0.2
      continue
    fi

    echo "[worker-${instance_id}] Claimed ticket ${story_id}"

    # Create feature branch name and worktree
    local branch
    branch=$(branch_name "${story_id}" "${story_title}")

    local wt_path
    wt_path=$(worktree_path "${story_id}" "${base_dir}")

    if ! worktree_create "${workspace_root}" "${story_id}" "${branch}" "${base_dir}" 2>/dev/null; then
      echo "[worker-${instance_id}] Failed to create worktree for ${story_id}" >&2
      prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      continue
    fi

    # Bootstrap workspace in the worktree (ensure Output/ etc. exist)
    workspace_init "${wt_path}" 2>/dev/null || true

    # Run the ticket pipeline in the worktree
    local ticket_rc=0
    if ! loop_run_ticket "${wt_path}" "${story}" "${branch}" "${max_retries}"; then
      ticket_rc=1
    fi

    if [[ "${ticket_rc}" -eq 0 ]]; then
      # Merge to main via the arbitrator
      echo "[worker-${instance_id}] Merging ${story_id} to main..."
      if ! merge_arbitrator_merge "${workspace_root}" "${wt_path}" "${story_id}" "${branch}"; then
        echo "[worker-${instance_id}] Merge failed for ${story_id}" >&2
        prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      fi
    else
      echo "[worker-${instance_id}] Ticket ${story_id} failed" >&2
      prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
    fi

    # Clean up worktree
    worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true

    echo "[worker-${instance_id}] Done with ${story_id}"
  done
}

# supervisor_run <workspace_root> <num_instances> <max_retries> [worktree_dir]
# Spawn N background worker subshells, periodically run coordinator checks,
# and wait for all workers to complete.
# Returns 0 if all workers exit cleanly, 1 if any worker fails.
supervisor_run() {
  local workspace_root="${1:?workspace_root required}"
  local num_instances="${2:?num_instances required}"
  local max_retries="${3:-10}"
  local worktree_dir="${4:-}"

  local base_dir
  if [[ -n "${worktree_dir}" ]]; then
    base_dir="${worktree_dir}"
  else
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  echo "[supervisor] Starting ${num_instances} worker(s)"
  mkdir -p "${base_dir}"

  local -a worker_pids=()
  local i

  for ((i = 1; i <= num_instances; i++)); do
    supervisor_worker_loop "${workspace_root}" "${i}" "${max_retries}" "${base_dir}" &
    local pid=$!
    worker_pids+=("${pid}")
    echo "[supervisor] Spawned worker-${i} (PID ${pid})"
  done

  # Monitor workers and run periodic coordinator checks
  local any_failed=0
  local check_interval=60
  local last_check=0

  while true; do
    local all_done=true
    for pid in "${worker_pids[@]}"; do
      if kill -0 "${pid}" 2>/dev/null; then
        all_done=false
        break
      fi
    done

    if [[ "${all_done}" == "true" ]]; then
      break
    fi

    # Periodic coordinator check
    local now
    now=$(date +%s)
    if [[ $((now - last_check)) -ge ${check_interval} ]]; then
      coordinator_run "${workspace_root}" "${base_dir}" 2>/dev/null || true
      last_check="${now}"
    fi

    sleep 2
  done

  # Collect exit codes
  for pid in "${worker_pids[@]}"; do
    if ! wait "${pid}"; then
      any_failed=1
    fi
  done

  # Clean up all worktrees
  echo "[supervisor] Cleaning up worktrees..."
  worktree_cleanup_all "${workspace_root}" "${base_dir}" 2>/dev/null || true

  if [[ "${any_failed}" -ne 0 ]]; then
    echo "[supervisor] One or more workers failed" >&2
    return 1
  fi

  echo "[supervisor] All workers completed successfully"
  return 0
}

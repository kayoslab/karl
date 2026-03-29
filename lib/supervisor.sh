#!/usr/bin/env bash
# supervisor.sh - Spawn and monitor N parallel workers for multi-instance karl

set -euo pipefail

# supervisor_worker_loop <workspace_root> <instance_id> <max_retries> [worktree_dir]
# Worker loop: claim ticket -> worktree -> run pipeline -> merge -> cleanup -> repeat.
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

  local consecutive_failures=0
  local max_consecutive_failures=3
  local fail_dir="${base_dir}/.fail-counts"
  mkdir -p "${fail_dir}"

  while true; do
    local story rc=0
    story=$(prd_select_next "${workspace_root}") || rc=$?

    if [[ "${rc}" -eq 2 ]]; then
      echo "[worker-${instance_id}] All stories complete"
      return 0
    fi
    if [[ "${rc}" -eq 3 ]]; then
      # Only log the first wait, then stay quiet
      if [[ "${waiting_logged:-false}" == "false" ]]; then
        echo "[worker-${instance_id}] Waiting for dependencies..."
        waiting_logged="true"
      fi
      sleep 10
      continue
    fi
    waiting_logged="false"
    [[ "${rc}" -ne 0 ]] && { echo "[worker-${instance_id}] Error reading PRD" >&2; return 1; }

    local story_id story_title
    story_id=$(printf '%s' "${story}" | jq -r '.id // "unknown"')
    story_title=$(printf '%s' "${story}" | jq -r '.title // ""')

    if ! prd_claim_ticket "${workspace_root}" "${story_id}" "worker-${instance_id}" 2>/dev/null; then
      sleep 0.2
      continue
    fi

    echo "[worker-${instance_id}] Claimed ticket ${story_id}"
    local branch
    branch=$(branch_name "${story_id}" "${story_title}")

    local wt_path
    wt_path=$(worktree_path "${story_id}" "${base_dir}")

    if ! worktree_create "${workspace_root}" "${story_id}" "${branch}" "${base_dir}"; then
      echo "[worker-${instance_id}] Failed to create worktree for ${story_id}" >&2
      prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      consecutive_failures=$((consecutive_failures + 1))
      [[ "${consecutive_failures}" -ge "${max_consecutive_failures}" ]] && return 1
      sleep 2
      continue
    fi

    workspace_init "${wt_path}" 2>/dev/null || true

    local ticket_rc=0
    loop_run_ticket "${wt_path}" "${story}" "${branch}" "${max_retries}" "true" || ticket_rc=1

    if [[ "${ticket_rc}" -eq 0 ]]; then
      echo "[worker-${instance_id}] Merging ${story_id} to main..."
      if ! merge_arbitrator_merge "${workspace_root}" "${wt_path}" "${story_id}" "${branch}"; then
        worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true
        prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      else
        consecutive_failures=0
        rm -f "${fail_dir}/${story_id}" 2>/dev/null || true
        worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true
      fi
    else
      echo "[worker-${instance_id}] Ticket ${story_id} failed" >&2
      local fail_count=0
      [[ -f "${fail_dir}/${story_id}" ]] && fail_count=$(cat "${fail_dir}/${story_id}")
      fail_count=$((fail_count + 1))
      printf '%d' "${fail_count}" > "${fail_dir}/${story_id}"

      # Clean worktree before releasing to prevent race conditions
      worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true

      if [[ "${fail_count}" -ge "${max_retries}" ]]; then
        echo "[worker-${instance_id}] Ticket ${story_id} permanently failed (${fail_count}/${max_retries})" >&2
        prd_fail_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      else
        echo "[worker-${instance_id}] Ticket ${story_id} failed (${fail_count}/${max_retries}) — releasing" >&2
        prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      fi
    fi
    echo "[worker-${instance_id}] Done with ${story_id}"
  done
}

# supervisor_run <workspace_root> <num_instances> <max_retries> [worktree_dir]
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

  # Kill all child processes (workers + their claude subprocesses) on interrupt
  _supervisor_cleanup() {
    echo "" >&2
    echo "[supervisor] Interrupted — killing all workers..." >&2
    for pid in "${worker_pids[@]}"; do
      # Kill the worker's entire process group
      kill -- -"${pid}" 2>/dev/null || kill "${pid}" 2>/dev/null || true
    done
    # Also kill any claude processes spawned by this session
    pkill -P $$ 2>/dev/null || true
    echo "[supervisor] Cleaning up worktrees..." >&2
    worktree_cleanup_all "${workspace_root}" "${base_dir}" 2>/dev/null || true
    echo "[supervisor] Shutdown complete" >&2
  }
  trap '_supervisor_cleanup; exit 130' INT TERM

  for ((i = 1; i <= num_instances; i++)); do
    supervisor_worker_loop "${workspace_root}" "${i}" "${max_retries}" "${base_dir}" &
    worker_pids+=("$!")
    echo "[supervisor] Spawned worker-${i} (PID $!)"
  done

  # Wait for all workers
  local any_failed=0
  for pid in "${worker_pids[@]}"; do
    if ! wait "${pid}"; then
      any_failed=1
    fi
  done

  # Clear the trap
  trap - INT TERM

  echo "[supervisor] Cleaning up worktrees..."
  worktree_cleanup_all "${workspace_root}" "${base_dir}" 2>/dev/null || true

  if [[ "${any_failed}" -ne 0 ]]; then
    echo "[supervisor] One or more workers failed" >&2
    return 1
  fi

  echo "[supervisor] All workers completed successfully"
  return 0
}

#!/usr/bin/env bash
# supervisor.sh - Spawn and monitor N parallel workers for multi-instance karl

set -euo pipefail

# _supervisor_kill_tree <pid>
# Recursively kill a process and all its descendants.
_supervisor_kill_tree() {
  local pid="${1}"
  local children
  children=$(pgrep -P "${pid}" 2>/dev/null) || true
  for child in ${children}; do
    _supervisor_kill_tree "${child}"
  done
  kill "${pid}" 2>/dev/null || true
}

# _supervisor_kill_orphans <workspace_root>
# Kill any orphaned node/vitest processes with cwd inside the workspace or its worktrees.
_supervisor_kill_orphans() {
  local workspace_root="${1}"
  # Kill node processes whose command line references the workspace worktrees
  local wt_base="${workspace_root}-worktrees"
  # Find node/vitest processes referencing the worktree directory
  pgrep -f "node.*${wt_base}" 2>/dev/null | while IFS= read -r pid; do
    kill "${pid}" 2>/dev/null || true
  done
  pgrep -f "vitest.*${wt_base}" 2>/dev/null | while IFS= read -r pid; do
    kill "${pid}" 2>/dev/null || true
  done
  # Also catch processes referencing the main workspace
  pgrep -f "node.*${workspace_root}" 2>/dev/null | while IFS= read -r pid; do
    kill "${pid}" 2>/dev/null || true
  done
}

# _supervisor_backoff <instance_id> <consecutive_failures>
# Exponential backoff: 30s, 60s, 120s, 240s, capped at 300s (5 min).
_supervisor_backoff() {
  local instance_id="${1}"
  local consecutive="${2}"
  local wait_time=$((30 * (2 ** (consecutive - 1))))
  [[ "${wait_time}" -gt 300 ]] && wait_time=300
  echo "[worker-${instance_id}] Backing off for ${wait_time}s (${consecutive} consecutive failures)" >&2
  sleep "${wait_time}"
}

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
      _supervisor_backoff "${instance_id}" "${consecutive_failures}"
      continue
    fi

    workspace_init "${wt_path}" 2>/dev/null || true

    local ticket_rc=0
    loop_run_ticket "${wt_path}" "${story}" "${branch}" "${max_retries}" "true" "${workspace_root}" || ticket_rc=1

    if [[ "${ticket_rc}" -eq 0 ]]; then
      echo "[worker-${instance_id}] Merging ${story_id} to main..."
      if ! merge_arbitrator_merge "${workspace_root}" "${wt_path}" "${story_id}" "${branch}" "${story_title}"; then
        worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true
        prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      else
        consecutive_failures=0
        rm -f "${fail_dir}/${story_id}" 2>/dev/null || true
        worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true
      fi
    else
      consecutive_failures=$((consecutive_failures + 1))

      # Clean worktree before releasing to prevent race conditions
      worktree_remove "${workspace_root}" "${story_id}" "${base_dir}" 2>/dev/null || true

      # Always count against retry budget
      local fail_count=0
      [[ -f "${fail_dir}/${story_id}" ]] && fail_count=$(cat "${fail_dir}/${story_id}")
      fail_count=$((fail_count + 1))
      printf '%d' "${fail_count}" > "${fail_dir}/${story_id}"

      if [[ "${fail_count}" -ge "${max_retries}" ]]; then
        echo "[worker-${instance_id}] Ticket ${story_id} permanently failed (${fail_count}/${max_retries})" >&2
        prd_fail_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
      else
        echo "[worker-${instance_id}] Ticket ${story_id} failed (${fail_count}/${max_retries}) — releasing" >&2
        prd_release_ticket "${workspace_root}" "${story_id}" 2>/dev/null || true
        # Back off on consecutive failures to avoid tight retry loops
        if [[ "${consecutive_failures}" -ge 2 ]]; then
          _supervisor_backoff "${instance_id}" "${consecutive_failures}"
        fi
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

  # Clear stale fail counts from previous runs so reset tickets get a fresh budget
  rm -rf "${base_dir}/.fail-counts" 2>/dev/null || true

  local -a worker_pids=()
  local i

  # Kill all child processes (workers + their claude subprocesses) on interrupt
  _supervisor_cleanup() {
    echo "" >&2
    echo "[supervisor] Interrupted — killing all workers..." >&2
    for pid in "${worker_pids[@]}"; do
      _supervisor_kill_tree "${pid}"
    done
    # Kill any orphaned node/vitest processes from subagents
    _supervisor_kill_orphans "${workspace_root}" 2>/dev/null || true
    echo "[supervisor] Cleaning up locks and worktrees..." >&2
    adr_arbitrator_release "${workspace_root}" 2>/dev/null || true
    merge_arbitrator_release "${workspace_root}" 2>/dev/null || true
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

  echo "[supervisor] Cleaning up worktrees and orphaned processes..."
  _supervisor_kill_orphans "${workspace_root}" 2>/dev/null || true
  worktree_cleanup_all "${workspace_root}" "${base_dir}" 2>/dev/null || true

  if [[ "${any_failed}" -ne 0 ]]; then
    echo "[supervisor] One or more workers failed" >&2
    return 1
  fi

  echo "[supervisor] All workers completed successfully"
  return 0
}

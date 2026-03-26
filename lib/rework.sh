#!/usr/bin/env bash
# rework.sh - Developer/tester rework loop for karl

set -euo pipefail

# rework_loop <workspace_root> <ticket_id> <ticket_json> [max_retries]
# Runs the developer+tester rework cycle until tests pass or the retry limit
# is reached.
# Returns 0 when the ticket passes.
# Returns 1 when the retry limit is reached.
rework_loop() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local ticket_json="${3:?ticket_json required}"
  local max_retries="${4:-10}"

  echo "[rework] Starting rework loop for [${ticket_id}] (max-retries=${max_retries})..."

  local skip_developer=0
  local cycle=0

  while true; do
    cycle=$(( cycle + 1 ))
    echo "[rework] Verification cycle ${cycle}/${max_retries}"

    # Check limit before attempting a cycle.
    if ! retry_check "${workspace_root}" "${ticket_id}" "${max_retries}"; then
      echo "[rework] Retry limit reached for ticket ${ticket_id} (max-retries=${max_retries}). Stopping."
      retry_exceeded_persist "${workspace_root}" "${ticket_id}" "${max_retries}"
      return 1
    fi

    # Run the developer agent (skipped when the previous failure was a test fix).
    if [[ "${skip_developer}" -eq 0 ]]; then
      # Read failures from last tester run so the developer knows what to fix
      local failures=""
      local failures_file="${workspace_root}/Output/${ticket_id}/last_failures"
      if [[ -f "${failures_file}" ]]; then
        failures=$(cat "${failures_file}")
      fi

      local mode="implement"
      if [[ "${cycle}" -gt 1 ]]; then
        mode="fix"
      fi

      if ! developer_run "${workspace_root}" "${ticket_id}" "${ticket_json}" "${failures}" "${mode}"; then
        retry_increment "${workspace_root}" "${ticket_id}"
        continue
      fi
    fi
    skip_developer=0

    # Run the tester agent.
    if tester_run "${workspace_root}" "${ticket_id}" "${ticket_json}"; then
      # Tests pass — commit and complete.
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit --allow-empty \
        -m "feat: [${ticket_id}] rework complete — all tests passing" \
        > /dev/null 2>&1 || true
      return 0
    fi

    # Tests failed — check whether the failure is in the test or implementation.
    local failure_source_file="${workspace_root}/Output/${ticket_id}/last_failure_source"
    local failure_source="implementation"
    if [[ -f "${failure_source_file}" ]]; then
      failure_source=$(cat "${failure_source_file}")
    fi

    if [[ "${failure_source}" == "test" ]]; then
      # Tester-fix path: let the tester correct the incorrect test.
      tester_fix_run "${workspace_root}" "${ticket_id}" "${ticket_json}" || true
      skip_developer=1
    fi

    # Increment and try again.
    retry_increment "${workspace_root}" "${ticket_id}"
  done
}

#!/usr/bin/env bats
# tests/rework.bats - Tests for lib/rework.sh (US-012)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
REWORK_SH="${KARL_DIR}/lib/rework.sh"
RETRY_SH="${KARL_DIR}/lib/retry.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  TICKET_ID="US-012"
  TICKET_JSON='{"id":"US-012","title":"Test ticket","passes":false}'
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  # shellcheck source=../lib/retry.sh
  source "${RETRY_SH}"
  # shellcheck source=../lib/rework.sh
  source "${REWORK_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# rework_loop - retry limit already reached at cycle start
# ---------------------------------------------------------------------------

@test "rework_loop returns 1 when retry count equals max_retries at cycle start" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  # Pre-fill counter so it equals max_retries=2
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 2
  [ "${status}" -eq 1 ]
}

@test "rework_loop prints 'Retry limit reached' when limit is hit at cycle start" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 2
  [[ "${output}" == *"Retry limit reached"* ]]
}

@test "rework_loop creates retry_exceeded.json when limit is hit at cycle start" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 1
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json" ]
}

# ---------------------------------------------------------------------------
# rework_loop - immediate limit (max_retries=0)
# ---------------------------------------------------------------------------

@test "rework_loop returns 1 immediately when max_retries is 0" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 0
  [ "${status}" -eq 1 ]
}

@test "rework_loop output contains 'Retry limit reached' when max_retries is 0" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 0
  [[ "${output}" == *"Retry limit reached"* ]]
}

@test "rework_loop creates retry_exceeded.json when max_retries is 0" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 0
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json" ]
}

# ---------------------------------------------------------------------------
# rework_loop - starting log message
# ---------------------------------------------------------------------------

@test "rework_loop logs starting message containing max-retries value" {
  # Stub inner agents so rework completes without real invocations
  developer_run() { return 0; }
  tester_run() { return 0; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [[ "${output}" == *"max-retries=5"* ]]
}

# ---------------------------------------------------------------------------
# rework_loop - per-cycle verification log (US-022 AC#1)
# ---------------------------------------------------------------------------

@test "rework_loop logs verification cycle number on the first cycle" {
  developer_run() { return 0; }
  tester_run() { return 0; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [[ "${output}" == *"Verification cycle 1"* ]]
}

@test "rework_loop includes max in verification cycle log line" {
  developer_run() { return 0; }
  tester_run() { return 0; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [[ "${output}" == *"1/5"* ]]
}

@test "rework_loop logs verification cycle number when tester fails then passes" {
  developer_run() { return 0; }
  local call_file="${WORKSPACE_ROOT}/tester_calls"
  echo 0 > "${call_file}"
  tester_run() {
    local n
    n=$(cat "${call_file}")
    n=$((n + 1))
    echo "${n}" > "${call_file}"
    [ "${n}" -ge 2 ]
  }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
  # Should see cycle 1 and cycle 2 in output
  [[ "${output}" == *"Verification cycle 1"* ]]
  [[ "${output}" == *"Verification cycle 2"* ]]
}

# ---------------------------------------------------------------------------
# rework_loop - respects custom max_retries over multiple cycles
# ---------------------------------------------------------------------------

@test "rework_loop with max_retries=2 stops after 2 failed cycles" {
  # Stub inner agents to always report failure so retry counter increments
  local cycle_count=0
  developer_run() { cycle_count=$((cycle_count + 1)); return 0; }
  tester_run() { return 1; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 2
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Retry limit reached"* ]]
}

# ---------------------------------------------------------------------------
# rework_loop - green on first try
# ---------------------------------------------------------------------------

@test "rework_loop returns 0 when developer and tester succeed on first cycle" {
  developer_run() { return 0; }
  tester_run() { return 0; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# rework_loop - developer fix path (tester fails, developer retries and passes)
# ---------------------------------------------------------------------------

@test "rework_loop returns 0 when tester fails once then passes on second cycle" {
  developer_run() { return 0; }
  local call_file="${WORKSPACE_ROOT}/tester_call_count"
  echo 0 > "${call_file}"
  tester_run() {
    local n
    n=$(cat "${call_file}")
    n=$((n + 1))
    echo "${n}" > "${call_file}"
    [ "${n}" -ge 2 ]
  }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
}

@test "rework_loop returns 0 when developer fails once then passes on second attempt" {
  local dev_file="${WORKSPACE_ROOT}/dev_call_count"
  echo 0 > "${dev_file}"
  developer_run() {
    local n
    n=$(cat "${dev_file}")
    n=$((n + 1))
    echo "${n}" > "${dev_file}"
    [ "${n}" -ge 2 ]
  }
  tester_run() { return 0; }
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# rework_loop - tester-fix path (failure_source=test)
# ---------------------------------------------------------------------------

@test "rework_loop calls tester_fix_run when tester_run writes failure_source=test" {
  local fix_call_file="${WORKSPACE_ROOT}/fix_calls"
  echo 0 > "${fix_call_file}"

  developer_run() { return 0; }

  local tester_call_file="${WORKSPACE_ROOT}/tester_calls"
  echo 0 > "${tester_call_file}"
  tester_run() {
    local n
    n=$(cat "${tester_call_file}")
    n=$((n + 1))
    echo "${n}" > "${tester_call_file}"
    if [ "${n}" -eq 1 ]; then
      echo "test" > "${WORKSPACE_ROOT}/Output/${TICKET_ID}/last_failure_source"
      return 1
    fi
    return 0
  }

  tester_fix_run() {
    local n
    n=$(cat "${fix_call_file}")
    n=$((n + 1))
    echo "${n}" > "${fix_call_file}"
    return 0
  }

  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
  [ "$(cat "${fix_call_file}")" -ge 1 ]
}

@test "rework_loop does not call developer_run on second cycle when failure_source=test" {
  local dev_call_file="${WORKSPACE_ROOT}/dev_calls"
  echo 0 > "${dev_call_file}"

  developer_run() {
    local n
    n=$(cat "${dev_call_file}")
    n=$((n + 1))
    echo "${n}" > "${dev_call_file}"
    return 0
  }

  local tester_call_file="${WORKSPACE_ROOT}/tester_calls"
  echo 0 > "${tester_call_file}"
  tester_run() {
    local n
    n=$(cat "${tester_call_file}")
    n=$((n + 1))
    echo "${n}" > "${tester_call_file}"
    if [ "${n}" -eq 1 ]; then
      echo "test" > "${WORKSPACE_ROOT}/Output/${TICKET_ID}/last_failure_source"
      return 1
    fi
    return 0
  }

  tester_fix_run() { return 0; }

  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
  # developer_run called once for initial implementation only, not again for test fix
  [ "$(cat "${dev_call_file}")" -eq 1 ]
}

@test "rework_loop still calls developer_run when failure_source=implementation" {
  local dev_call_file="${WORKSPACE_ROOT}/dev_calls"
  echo 0 > "${dev_call_file}"

  developer_run() {
    local n
    n=$(cat "${dev_call_file}")
    n=$((n + 1))
    echo "${n}" > "${dev_call_file}"
    return 0
  }

  local tester_call_file="${WORKSPACE_ROOT}/tester_calls"
  echo 0 > "${tester_call_file}"
  tester_run() {
    local n
    n=$(cat "${tester_call_file}")
    n=$((n + 1))
    echo "${n}" > "${tester_call_file}"
    if [ "${n}" -eq 1 ]; then
      echo "implementation" > "${WORKSPACE_ROOT}/Output/${TICKET_ID}/last_failure_source"
      return 1
    fi
    return 0
  }

  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]
  # developer_run called at least twice: initial + fix cycle
  [ "$(cat "${dev_call_file}")" -ge 2 ]
}

# ---------------------------------------------------------------------------
# rework_loop - commit on success (AC-6)
# ---------------------------------------------------------------------------

@test "rework_loop creates a commit when tests pass on success" {
  git -C "${WORKSPACE_ROOT}" init -q
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com"
  git -C "${WORKSPACE_ROOT}" config user.name "Test"
  # Create an initial commit so HEAD exists
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "init" -q

  developer_run() { return 0; }
  tester_run() { return 0; }

  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run rework_loop "${WORKSPACE_ROOT}" "${TICKET_ID}" "${TICKET_JSON}" 5
  [ "${status}" -eq 0 ]

  local log
  log=$(git -C "${WORKSPACE_ROOT}" log --oneline)
  [[ "${log}" == *"${TICKET_ID}"* ]]
}

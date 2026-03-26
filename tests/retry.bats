#!/usr/bin/env bats
# tests/retry.bats - Tests for lib/retry.sh (US-012)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RETRY_SH="${KARL_DIR}/lib/retry.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  TICKET_ID="US-012"
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  # shellcheck source=../lib/retry.sh
  source "${RETRY_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# retry_init / retry_get_count
# ---------------------------------------------------------------------------

@test "retry_init sets count to 0" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_get_count "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [ "${output}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# retry_increment
# ---------------------------------------------------------------------------

@test "retry_increment increases count by 1" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_get_count "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${output}" -eq 1 ]
}

@test "retry_increment accumulates over multiple calls" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_get_count "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${output}" -eq 3 ]
}

# ---------------------------------------------------------------------------
# retry_check
# ---------------------------------------------------------------------------

@test "retry_check returns 0 when count is below max_retries" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_check "${WORKSPACE_ROOT}" "${TICKET_ID}" 10
  [ "${status}" -eq 0 ]
}

@test "retry_check returns 1 when count equals max_retries" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_check "${WORKSPACE_ROOT}" "${TICKET_ID}" 3
  [ "${status}" -eq 1 ]
}

@test "retry_check returns 1 when count exceeds max_retries" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_check "${WORKSPACE_ROOT}" "${TICKET_ID}" 1
  [ "${status}" -eq 1 ]
}

@test "retry_check returns 0 when count is zero and max_retries is positive" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  run retry_check "${WORKSPACE_ROOT}" "${TICKET_ID}" 10
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# retry_exceeded_persist
# ---------------------------------------------------------------------------

@test "retry_exceeded_persist writes retry_exceeded.json" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_exceeded_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" 5
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json" ]
}

@test "retry_exceeded_persist JSON contains max_retries field" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_exceeded_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" 7
  run jq -r '.max_retries' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json"
  [ "${output}" = "7" ]
}

@test "retry_exceeded_persist JSON contains count field" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_increment "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_exceeded_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" 2
  run jq -r '.count' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json"
  [ "${output}" = "2" ]
}

@test "retry_exceeded_persist JSON contains non-empty message field" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_exceeded_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" 10
  run jq -r '.message' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" != "null" ]]
  [[ -n "${output}" ]]
}

@test "retry_exceeded_persist JSON is valid JSON" {
  retry_init "${WORKSPACE_ROOT}" "${TICKET_ID}"
  retry_exceeded_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" 5
  run jq empty "${WORKSPACE_ROOT}/Output/${TICKET_ID}/retry_exceeded.json"
  [ "${status}" -eq 0 ]
}

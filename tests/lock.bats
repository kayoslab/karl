#!/usr/bin/env bats
# tests/lock.bats - Tests for lib/lock.sh

LOCK_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/lock.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  # shellcheck source=../lib/lock.sh
  source "${LOCK_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# lock_path
# ---------------------------------------------------------------------------

@test "lock_path returns <workspace>/LOCK" {
  run lock_path "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ "$output" = "${WORKSPACE_ROOT}/LOCK" ]
}

# ---------------------------------------------------------------------------
# lock_exists
# ---------------------------------------------------------------------------

@test "lock_exists returns 1 when LOCK is absent" {
  run lock_exists "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
}

@test "lock_exists returns 0 when LOCK file is present" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_exists "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# lock_acquire
# ---------------------------------------------------------------------------

@test "lock_acquire creates LOCK file" {
  run lock_acquire "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/LOCK" ]
}

@test "lock_acquire writes PID to LOCK file" {
  lock_acquire "${WORKSPACE_ROOT}"
  local pid
  pid="$(cat "${WORKSPACE_ROOT}/LOCK")"
  # PID should be a non-empty number
  [[ "${pid}" =~ ^[0-9]+$ ]]
}

@test "lock_acquire fails when LOCK already exists (no force)" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_acquire "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
}

@test "lock_acquire prints ERROR when LOCK already exists" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_acquire "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "lock_acquire prints --force-lock hint when LOCK already exists" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_acquire "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"--force-lock"* ]]
}

@test "lock_acquire with force=true succeeds even when LOCK exists" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_acquire "${WORKSPACE_ROOT}" "true"
  [ "$status" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/LOCK" ]
}

@test "lock_acquire with force=true prints WARNING" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run lock_acquire "${WORKSPACE_ROOT}" "true"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]]
}

# ---------------------------------------------------------------------------
# lock_release
# ---------------------------------------------------------------------------

@test "lock_release removes LOCK file" {
  lock_acquire "${WORKSPACE_ROOT}"
  run lock_release "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ ! -f "${WORKSPACE_ROOT}/LOCK" ]
}

@test "lock_release is idempotent when LOCK is already absent" {
  run lock_release "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

#!/usr/bin/env bats
# tests/workspace.bats - Tests for lib/workspace.sh

WORKSPACE_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/workspace.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  # shellcheck source=../lib/workspace.sh
  source "${WORKSPACE_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# bootstrap_workspace
# ---------------------------------------------------------------------------

@test "bootstrap_workspace creates all required directories" {
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Input" ]
  [ -d "${WORKSPACE_ROOT}/Output" ]
  [ -d "${WORKSPACE_ROOT}/Output/ADR" ]
}

@test "bootstrap_workspace creates placeholder output files when absent" {
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/progress.md" ]
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

@test "bootstrap_workspace creates .gitignore with LOCK entry" {
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/.gitignore" ]
  grep -qx 'LOCK' "${WORKSPACE_ROOT}/.gitignore"
}

@test "bootstrap_workspace appends LOCK to existing .gitignore" {
  echo "*.log" > "${WORKSPACE_ROOT}/.gitignore"
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  grep -qx 'LOCK' "${WORKSPACE_ROOT}/.gitignore"
  grep -qx '\*.log' "${WORKSPACE_ROOT}/.gitignore"
}

@test "bootstrap_workspace does not duplicate LOCK in .gitignore" {
  echo "LOCK" > "${WORKSPACE_ROOT}/.gitignore"
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local count
  count=$(grep -cx 'LOCK' "${WORKSPACE_ROOT}/.gitignore")
  [ "$count" -eq 1 ]
}

@test "bootstrap_workspace does not overwrite existing output files" {
  mkdir -p "${WORKSPACE_ROOT}/Output"
  echo "existing content" > "${WORKSPACE_ROOT}/Output/progress.md"
  run bootstrap_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  run grep -q "existing content" "${WORKSPACE_ROOT}/Output/progress.md"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# validate_workspace
# ---------------------------------------------------------------------------

@test "validate_workspace returns 0 when all dirs and required inputs exist" {
  bootstrap_workspace "${WORKSPACE_ROOT}"
  echo '{}' > "${WORKSPACE_ROOT}/Input/prd.json"
  touch "${WORKSPACE_ROOT}/CLAUDE.md"
  run validate_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

@test "validate_workspace returns 1 and prints ERROR when a required directory is missing" {
  bootstrap_workspace "${WORKSPACE_ROOT}"
  echo '{}' > "${WORKSPACE_ROOT}/Input/prd.json"
  touch "${WORKSPACE_ROOT}/CLAUDE.md"
  rm -rf "${WORKSPACE_ROOT}/Output"
  run validate_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "validate_workspace returns 1 and prints ERROR when Input/prd.json is missing" {
  bootstrap_workspace "${WORKSPACE_ROOT}"
  touch "${WORKSPACE_ROOT}/CLAUDE.md"
  run validate_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"prd.json"* ]]
}

@test "validate_workspace returns 1 and prints ERROR when CLAUDE.md is missing" {
  bootstrap_workspace "${WORKSPACE_ROOT}"
  echo '{}' > "${WORKSPACE_ROOT}/Input/prd.json"
  run validate_workspace "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"CLAUDE.md"* ]]
}

# ---------------------------------------------------------------------------
# workspace_init
# ---------------------------------------------------------------------------

@test "workspace_init succeeds when required inputs are present" {
  mkdir -p "${WORKSPACE_ROOT}/Input"
  echo '{}' > "${WORKSPACE_ROOT}/Input/prd.json"
  touch "${WORKSPACE_ROOT}/CLAUDE.md"
  run workspace_init "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Output/ADR" ]
}

@test "workspace_init fails when required inputs are absent" {
  run workspace_init "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

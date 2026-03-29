#!/usr/bin/env bats
# tests/worktree.bats - Tests for lib/worktree.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
WORKTREE_SH="${KARL_DIR}/lib/worktree.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  WORKTREE_BASE="$(mktemp -d)"
  # shellcheck source=../lib/worktree.sh
  source "${WORKTREE_SH}"

  # Initialize a real git repo
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  echo "init" > "${WORKSPACE_ROOT}/README.md"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial" > /dev/null 2>&1
}

teardown() {
  # Clean up worktrees before removing dirs
  git -C "${WORKSPACE_ROOT}" worktree prune 2>/dev/null || true
  rm -rf "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
}

# ---------------------------------------------------------------------------
# worktree_base_dir
# ---------------------------------------------------------------------------

@test "worktree_base_dir returns default path when no custom dir given" {
  local result
  result=$(worktree_base_dir "${WORKSPACE_ROOT}")
  [[ "${result}" == *"-worktrees" ]]
}

@test "worktree_base_dir returns custom dir when provided" {
  local result
  result=$(worktree_base_dir "${WORKSPACE_ROOT}" "/custom/path")
  [ "${result}" = "/custom/path" ]
}

# ---------------------------------------------------------------------------
# worktree_path
# ---------------------------------------------------------------------------

@test "worktree_path returns expected path" {
  local result
  result=$(worktree_path "US-001" "${WORKTREE_BASE}")
  [ "${result}" = "${WORKTREE_BASE}/US-001" ]
}

@test "worktree_path sanitizes dots in ticket ID" {
  local result
  result=$(worktree_path "US-001.1" "${WORKTREE_BASE}")
  [ "${result}" = "${WORKTREE_BASE}/US-001-1" ]
}

# ---------------------------------------------------------------------------
# worktree_create
# ---------------------------------------------------------------------------

@test "worktree_create creates a worktree directory" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  [ -d "${WORKTREE_BASE}/US-001" ]
}

@test "worktree_create returns 0 on success" {
  run worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

@test "worktree_create creates a git checkout in the worktree" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  local branch
  branch=$(git -C "${WORKTREE_BASE}/US-001" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "feature/US-001-test" ]
}

@test "worktree_create returns 0 if worktree already exists" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  run worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-dup" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

@test "worktree_create succeeds when stale branch exists from previous failed run" {
  # Simulate a stale branch left behind by a failed worktree creation
  git -C "${WORKSPACE_ROOT}" branch "feature/US-003-stale" main
  run worktree_create "${WORKSPACE_ROOT}" "US-003" "feature/US-003-stale" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
  [ -d "${WORKTREE_BASE}/US-003" ]
}

@test "worktree_create contains files from main" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  [ -f "${WORKTREE_BASE}/US-001/README.md" ]
}

# ---------------------------------------------------------------------------
# worktree_exists
# ---------------------------------------------------------------------------

@test "worktree_exists returns 0 when worktree exists" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  worktree_exists "${WORKSPACE_ROOT}" "US-001" "${WORKTREE_BASE}"
}

@test "worktree_exists returns 1 when worktree does not exist" {
  run worktree_exists "${WORKSPACE_ROOT}" "US-999" "${WORKTREE_BASE}"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# worktree_remove
# ---------------------------------------------------------------------------

@test "worktree_remove removes the worktree directory" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  worktree_remove "${WORKSPACE_ROOT}" "US-001" "${WORKTREE_BASE}"
  [ ! -d "${WORKTREE_BASE}/US-001" ]
}

@test "worktree_remove returns 0 on success" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  run worktree_remove "${WORKSPACE_ROOT}" "US-001" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

@test "worktree_remove is idempotent" {
  run worktree_remove "${WORKSPACE_ROOT}" "US-999" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# worktree_list
# ---------------------------------------------------------------------------

@test "worktree_list returns empty when no worktrees" {
  local result
  result=$(worktree_list "${WORKSPACE_ROOT}")
  [ -z "${result}" ]
}

@test "worktree_list shows created worktrees" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  local result
  result=$(worktree_list "${WORKSPACE_ROOT}")
  [[ "${result}" == *"US-001"* ]]
}

# ---------------------------------------------------------------------------
# worktree_cleanup_all
# ---------------------------------------------------------------------------

@test "worktree_cleanup_all removes all worktrees" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test" "${WORKTREE_BASE}"
  worktree_create "${WORKSPACE_ROOT}" "US-002" "feature/US-002-test" "${WORKTREE_BASE}"
  worktree_cleanup_all "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
  [ ! -d "${WORKTREE_BASE}/US-001" ]
  [ ! -d "${WORKTREE_BASE}/US-002" ]
}

@test "worktree_cleanup_all returns 0 when no worktrees exist" {
  run worktree_cleanup_all "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

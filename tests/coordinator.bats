#!/usr/bin/env bats
# tests/coordinator.bats - Tests for lib/coordinator.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  WORKTREE_BASE="$(mktemp -d)"

  # shellcheck source=../lib/worktree.sh
  source "${KARL_DIR}/lib/worktree.sh"
  # shellcheck source=../lib/coordinator.sh
  source "${KARL_DIR}/lib/coordinator.sh"

  # Initialize git repo
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  echo "init" > "${WORKSPACE_ROOT}/README.md"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial" > /dev/null 2>&1
}

teardown() {
  git -C "${WORKSPACE_ROOT}" worktree prune 2>/dev/null || true
  rm -rf "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
}

# ---------------------------------------------------------------------------
# coordinator_check
# ---------------------------------------------------------------------------

@test "coordinator_check returns valid JSON with no worktrees" {
  local result
  result=$(coordinator_check "${WORKSPACE_ROOT}" "${WORKTREE_BASE}")
  printf '%s' "${result}" | jq . > /dev/null 2>&1
  local num
  num=$(printf '%s' "${result}" | jq '.num_workers')
  [ "${num}" -eq 0 ]
}

@test "coordinator_check reports zero overlaps for non-overlapping worktrees" {
  # Create two worktrees with different files
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-a" "${WORKTREE_BASE}" > /dev/null 2>&1
  worktree_create "${WORKSPACE_ROOT}" "US-002" "feature/US-002-b" "${WORKTREE_BASE}" > /dev/null 2>&1

  echo "file_a" > "${WORKTREE_BASE}/US-001/file_a.txt"
  git -C "${WORKTREE_BASE}/US-001" add . > /dev/null 2>&1
  git -C "${WORKTREE_BASE}/US-001" commit -m "add a" > /dev/null 2>&1

  echo "file_b" > "${WORKTREE_BASE}/US-002/file_b.txt"
  git -C "${WORKTREE_BASE}/US-002" add . > /dev/null 2>&1
  git -C "${WORKTREE_BASE}/US-002" commit -m "add b" > /dev/null 2>&1

  local result
  result=$(coordinator_check "${WORKSPACE_ROOT}" "${WORKTREE_BASE}")
  local overlap_count
  overlap_count=$(printf '%s' "${result}" | jq '.overlaps | length')
  [ "${overlap_count}" -eq 0 ]
}

@test "coordinator_check detects overlapping files" {
  worktree_create "${WORKSPACE_ROOT}" "US-001" "feature/US-001-a" "${WORKTREE_BASE}" > /dev/null 2>&1
  worktree_create "${WORKSPACE_ROOT}" "US-002" "feature/US-002-b" "${WORKTREE_BASE}" > /dev/null 2>&1

  # Both modify the same file
  echo "change_a" > "${WORKTREE_BASE}/US-001/README.md"
  git -C "${WORKTREE_BASE}/US-001" add . > /dev/null 2>&1
  git -C "${WORKTREE_BASE}/US-001" commit -m "modify readme" > /dev/null 2>&1

  echo "change_b" > "${WORKTREE_BASE}/US-002/README.md"
  git -C "${WORKTREE_BASE}/US-002" add . > /dev/null 2>&1
  git -C "${WORKTREE_BASE}/US-002" commit -m "modify readme" > /dev/null 2>&1

  local result
  result=$(coordinator_check "${WORKSPACE_ROOT}" "${WORKTREE_BASE}")
  local overlap_count
  overlap_count=$(printf '%s' "${result}" | jq '.overlaps | length')
  [ "${overlap_count}" -eq 1 ]

  local overlap_file
  overlap_file=$(printf '%s' "${result}" | jq -r '.overlaps[0].overlapping_files[0]')
  [ "${overlap_file}" = "README.md" ]
}

# ---------------------------------------------------------------------------
# coordinator_run
# ---------------------------------------------------------------------------

@test "coordinator_run returns 0 with no worktrees" {
  run coordinator_run "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
}

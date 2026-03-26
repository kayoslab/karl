#!/usr/bin/env bats
# tests/clean.bats - Tests for lib/clean.sh

CLEAN_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/clean.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  # shellcheck source=../lib/clean.sh
  source "${CLEAN_SH}"

  # Initialize a real git repo for all tests
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# clean_checkout_main
# ---------------------------------------------------------------------------

@test "clean_checkout_main checks out main branch" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/test > /dev/null 2>&1
  clean_checkout_main "${WORKSPACE_ROOT}"
  local branch
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "clean_checkout_main returns 0 on success" {
  run clean_checkout_main "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "clean_checkout_main prints confirmation message" {
  run clean_checkout_main "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"main"* ]]
}

@test "clean_checkout_main returns 1 when main branch does not exist" {
  git -C "${WORKSPACE_ROOT}" branch -m main notmain > /dev/null 2>&1
  run clean_checkout_main "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# clean_discard_changes
# ---------------------------------------------------------------------------

@test "clean_discard_changes returns 0 when tree is clean" {
  run clean_discard_changes "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "clean_discard_changes removes uncommitted tracked file changes" {
  printf 'original\n' > "${WORKSPACE_ROOT}/file.txt"
  git -C "${WORKSPACE_ROOT}" add file.txt
  git -C "${WORKSPACE_ROOT}" commit -m "add file" > /dev/null 2>&1
  printf 'modified\n' > "${WORKSPACE_ROOT}/file.txt"
  clean_discard_changes "${WORKSPACE_ROOT}"
  local content
  content=$(cat "${WORKSPACE_ROOT}/file.txt")
  [ "${content}" = "original" ]
}

@test "clean_discard_changes prints confirmation message" {
  run clean_discard_changes "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"discard"* ]] || [[ "${output}" == *"clean"* ]] || [[ "${output}" == *"Uncommitted"* ]]
}

# ---------------------------------------------------------------------------
# clean_delete_branch
# ---------------------------------------------------------------------------

@test "clean_delete_branch deletes a feature branch" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/to-delete > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1
  clean_delete_branch "${WORKSPACE_ROOT}" "feature/to-delete"
  local branches
  branches=$(git -C "${WORKSPACE_ROOT}" branch)
  [[ "${branches}" != *"feature/to-delete"* ]]
}

@test "clean_delete_branch returns 0 when branch is deleted successfully" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/del-ok > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1
  run clean_delete_branch "${WORKSPACE_ROOT}" "feature/del-ok"
  [ "${status}" -eq 0 ]
}

@test "clean_delete_branch returns 0 when branch does not exist" {
  run clean_delete_branch "${WORKSPACE_ROOT}" "feature/nonexistent"
  [ "${status}" -eq 0 ]
}

@test "clean_delete_branch prints message when branch does not exist" {
  run clean_delete_branch "${WORKSPACE_ROOT}" "feature/nonexistent"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"not exist"* ]] || [[ "${output}" == *"Nothing"* ]]
}

@test "clean_delete_branch returns 1 when trying to delete the current branch" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/current > /dev/null 2>&1
  run clean_delete_branch "${WORKSPACE_ROOT}" "feature/current"
  [ "${status}" -eq 1 ]
}

@test "clean_delete_branch prints deleted message on success" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/del-msg > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1
  run clean_delete_branch "${WORKSPACE_ROOT}" "feature/del-msg"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Deleted"* ]]
}

# ---------------------------------------------------------------------------
# clean_remove_lock
# ---------------------------------------------------------------------------

@test "clean_remove_lock removes LOCK file when present" {
  touch "${WORKSPACE_ROOT}/LOCK"
  clean_remove_lock "${WORKSPACE_ROOT}"
  [ ! -f "${WORKSPACE_ROOT}/LOCK" ]
}

@test "clean_remove_lock returns 0 when LOCK exists" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run clean_remove_lock "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "clean_remove_lock returns 0 when LOCK is absent" {
  run clean_remove_lock "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "clean_remove_lock prints removed message when LOCK existed" {
  touch "${WORKSPACE_ROOT}/LOCK"
  run clean_remove_lock "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Removed"* ]] || [[ "${output}" == *"LOCK"* ]]
}

@test "clean_remove_lock prints no-lock message when LOCK absent" {
  run clean_remove_lock "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No LOCK"* ]] || [[ "${output}" == *"No"* ]]
}

# ---------------------------------------------------------------------------
# clean_run
# ---------------------------------------------------------------------------

@test "clean_run returns 0 on a clean workspace" {
  run clean_run "${WORKSPACE_ROOT}" false
  [ "${status}" -eq 0 ]
}

@test "clean_run checks out main branch" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/test-run > /dev/null 2>&1
  clean_run "${WORKSPACE_ROOT}" false
  local branch
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "clean_run removes LOCK file" {
  touch "${WORKSPACE_ROOT}/LOCK"
  clean_run "${WORKSPACE_ROOT}" false
  [ ! -f "${WORKSPACE_ROOT}/LOCK" ]
}

@test "clean_run with force=true discards uncommitted changes" {
  printf 'original\n' > "${WORKSPACE_ROOT}/tracked.txt"
  git -C "${WORKSPACE_ROOT}" add tracked.txt
  git -C "${WORKSPACE_ROOT}" commit -m "add tracked" > /dev/null 2>&1
  printf 'modified\n' > "${WORKSPACE_ROOT}/tracked.txt"
  clean_run "${WORKSPACE_ROOT}" true
  local content
  content=$(cat "${WORKSPACE_ROOT}/tracked.txt")
  [ "${content}" = "original" ]
}

@test "clean_run with force=false does not discard uncommitted changes" {
  printf 'original\n' > "${WORKSPACE_ROOT}/tracked.txt"
  git -C "${WORKSPACE_ROOT}" add tracked.txt
  git -C "${WORKSPACE_ROOT}" commit -m "add tracked" > /dev/null 2>&1
  printf 'modified\n' > "${WORKSPACE_ROOT}/tracked.txt"
  clean_run "${WORKSPACE_ROOT}" false
  local content
  content=$(cat "${WORKSPACE_ROOT}/tracked.txt")
  [ "${content}" = "modified" ]
}

@test "clean_run prints starting message" {
  run clean_run "${WORKSPACE_ROOT}" false
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"clean"* ]]
}

@test "clean_run prints completion message" {
  run clean_run "${WORKSPACE_ROOT}" false
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"complete"* ]] || [[ "${output}" == *"recovery"* ]]
}

@test "clean_run warns about uncommitted changes without force" {
  printf 'data\n' > "${WORKSPACE_ROOT}/tracked.txt"
  git -C "${WORKSPACE_ROOT}" add tracked.txt
  git -C "${WORKSPACE_ROOT}" commit -m "add tracked" > /dev/null 2>&1
  printf 'modified\n' > "${WORKSPACE_ROOT}/tracked.txt"
  run clean_run "${WORKSPACE_ROOT}" false
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARNING"* ]] || [[ "${output}" == *"force"* ]]
}

@test "clean_run deletes the previously active feature branch" {
  git -C "${WORKSPACE_ROOT}" checkout -b feature/stale-work > /dev/null 2>&1
  clean_run "${WORKSPACE_ROOT}" false
  local branches
  branches=$(git -C "${WORKSPACE_ROOT}" branch)
  [[ "${branches}" != *"feature/stale-work"* ]]
}

@test "clean_run does not delete non-feature branches" {
  git -C "${WORKSPACE_ROOT}" checkout -b hotfix/patch > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout hotfix/patch > /dev/null 2>&1
  clean_run "${WORKSPACE_ROOT}" false
  local branches
  branches=$(git -C "${WORKSPACE_ROOT}" branch)
  [[ "${branches}" == *"hotfix/patch"* ]]
}

@test "clean_run succeeds when already on main with no feature branch" {
  run clean_run "${WORKSPACE_ROOT}" false
  [ "${status}" -eq 0 ]
}

#!/usr/bin/env bats
# tests/merge.bats - Tests for lib/merge.sh (US-014)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
MERGE_SH="${KARL_DIR}/lib/merge.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  TICKET_ID="US-014"
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  # shellcheck source=../lib/merge.sh
  source "${MERGE_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Helper: initialize a real git repo
# ---------------------------------------------------------------------------
_init_repo() {
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
}

_add_feature_branch() {
  local branch="${1:-feature/US-014-test}"
  git -C "${WORKSPACE_ROOT}" checkout -b "${branch}" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# merge_check_clean_tree
# ---------------------------------------------------------------------------

@test "merge_check_clean_tree returns 0 for a clean working tree" {
  _init_repo
  run merge_check_clean_tree "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "merge_check_clean_tree returns 1 when there are unstaged modifications" {
  _init_repo
  echo "dirty" > "${WORKSPACE_ROOT}/file.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/file.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "add file" > /dev/null 2>&1
  echo "modified" > "${WORKSPACE_ROOT}/file.txt"
  run merge_check_clean_tree "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

@test "merge_check_clean_tree returns 1 when there are staged changes" {
  _init_repo
  echo "new content" > "${WORKSPACE_ROOT}/staged.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/staged.txt" > /dev/null 2>&1
  run merge_check_clean_tree "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

@test "merge_check_clean_tree prints a message indicating dirty state" {
  _init_repo
  echo "content" > "${WORKSPACE_ROOT}/file.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/file.txt" > /dev/null 2>&1
  run merge_check_clean_tree "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [ -n "${output}" ]
}

@test "merge_check_clean_tree ignores untracked files" {
  _init_repo
  echo "untracked" > "${WORKSPACE_ROOT}/untracked.txt"
  run merge_check_clean_tree "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "merge_check_clean_tree requires workspace_root argument" {
  run merge_check_clean_tree
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# merge_check_main_exists
# ---------------------------------------------------------------------------

@test "merge_check_main_exists returns 0 when main branch exists" {
  _init_repo
  run merge_check_main_exists "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "merge_check_main_exists returns 1 when main branch does not exist" {
  git -C "${WORKSPACE_ROOT}" init -b other > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
  run merge_check_main_exists "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

@test "merge_check_main_exists prints error message when main is absent" {
  git -C "${WORKSPACE_ROOT}" init -b other > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
  run merge_check_main_exists "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [ -n "${output}" ]
}

@test "merge_check_main_exists requires workspace_root argument" {
  run merge_check_main_exists
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# merge_check_no_conflicts
# ---------------------------------------------------------------------------

@test "merge_check_no_conflicts returns 0 when feature branch merges cleanly onto main" {
  _init_repo
  _add_feature_branch
  echo "feature content" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/feature.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature commit" > /dev/null 2>&1
  run merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/US-014-test" "main"
  [ "${status}" -eq 0 ]
}

@test "merge_check_no_conflicts returns 2 when merge conflicts exist" {
  _init_repo
  # Create a conflicting change on main
  echo "main content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "main adds conflict.txt" > /dev/null 2>&1

  # Create feature branch from the initial commit (before main's change)
  git -C "${WORKSPACE_ROOT}" checkout -b feature/US-014-conflict "HEAD~1" > /dev/null 2>&1
  echo "feature content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature adds conflict.txt differently" > /dev/null 2>&1

  run merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/US-014-conflict" "main"
  [ "${status}" -eq 2 ]
}

@test "merge_check_no_conflicts returns 1 when feature branch does not exist" {
  _init_repo
  run merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/nonexistent" "main"
  [ "${status}" -eq 1 ]
}

@test "merge_check_no_conflicts returns 1 when base branch does not exist" {
  _init_repo
  _add_feature_branch
  run merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/US-014-test" "nonexistent"
  [ "${status}" -eq 1 ]
}

@test "merge_check_no_conflicts does not modify working tree on conflict check" {
  _init_repo
  _add_feature_branch
  echo "feature content" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/feature.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature commit" > /dev/null 2>&1

  local before_branch
  before_branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)

  merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/US-014-test" "main" || true

  local after_branch
  after_branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${before_branch}" = "${after_branch}" ]
}

@test "merge_check_no_conflicts prints conflict message when conflicts detected" {
  _init_repo
  echo "main content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "main adds conflict.txt" > /dev/null 2>&1

  git -C "${WORKSPACE_ROOT}" checkout -b feature/US-014-conflict "HEAD~1" > /dev/null 2>&1
  echo "feature content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature adds conflict.txt differently" > /dev/null 2>&1

  run merge_check_no_conflicts "${WORKSPACE_ROOT}" "feature/US-014-conflict" "main"
  [ "${status}" -eq 2 ]
  [ -n "${output}" ]
}

@test "merge_check_no_conflicts requires workspace_root argument" {
  run merge_check_no_conflicts
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# merge_safe_check - artifact creation
# ---------------------------------------------------------------------------

@test "merge_safe_check creates merge_check.json in the ticket output directory" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test" || true
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/merge_check.json" ]
}

@test "merge_safe_check writes checks field to merge_check.json" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test" || true
  local json
  json=$(cat "${WORKSPACE_ROOT}/Output/${TICKET_ID}/merge_check.json")
  printf '%s' "${json}" | jq -e '.checks' > /dev/null 2>&1
}

@test "merge_safe_check writes all_passed field to merge_check.json" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test" || true
  local json
  json=$(cat "${WORKSPACE_ROOT}/Output/${TICKET_ID}/merge_check.json")
  printf '%s' "${json}" | jq -e 'has("all_passed")' > /dev/null 2>&1
}

@test "merge_safe_check sets all_passed=true when all checks pass" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  local all_passed
  all_passed=$(jq -r '.all_passed' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/merge_check.json")
  [ "${all_passed}" = "true" ]
}

@test "merge_safe_check sets all_passed=false when conflict is detected" {
  _init_repo
  echo "main content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "main adds conflict.txt" > /dev/null 2>&1

  git -C "${WORKSPACE_ROOT}" checkout -b feature/US-014-conflict "HEAD~1" > /dev/null 2>&1
  echo "feature content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature adds conflict.txt differently" > /dev/null 2>&1

  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-conflict" || true
  local all_passed
  all_passed=$(jq -r '.all_passed' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/merge_check.json")
  [ "${all_passed}" = "false" ]
}

# ---------------------------------------------------------------------------
# merge_safe_check - return codes
# ---------------------------------------------------------------------------

@test "merge_safe_check returns 0 when all checks pass" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  [ "${status}" -eq 0 ]
}

@test "merge_safe_check returns 2 when merge conflict is detected" {
  _init_repo
  echo "main content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "main adds conflict.txt" > /dev/null 2>&1

  git -C "${WORKSPACE_ROOT}" checkout -b feature/US-014-conflict "HEAD~1" > /dev/null 2>&1
  echo "feature content" > "${WORKSPACE_ROOT}/conflict.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/conflict.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature adds conflict.txt differently" > /dev/null 2>&1

  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-conflict"
  [ "${status}" -eq 2 ]
}

@test "merge_safe_check returns 1 when working tree is dirty" {
  _init_repo
  _add_feature_branch
  echo "committed" > "${WORKSPACE_ROOT}/file.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/file.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "add file" > /dev/null 2>&1
  echo "dirty" > "${WORKSPACE_ROOT}/file.txt"

  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  [ "${status}" -eq 1 ]
}

@test "merge_safe_check returns 1 when main branch does not exist" {
  git -C "${WORKSPACE_ROOT}" init -b other > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout -b feature/US-014-test > /dev/null 2>&1
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"

  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  [ "${status}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# merge_safe_check - logging
# ---------------------------------------------------------------------------

@test "merge_safe_check logs the ticket id in its output" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  [[ "${output}" == *"${TICKET_ID}"* ]]
}

@test "merge_safe_check logs a merge check result message" {
  _init_repo
  _add_feature_branch
  echo "feature" > "${WORKSPACE_ROOT}/f.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/f.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feature" > /dev/null 2>&1

  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-014-test"
  [ -n "${output}" ]
}

@test "merge_safe_check requires workspace_root argument" {
  run merge_safe_check
  [ "${status}" -ne 0 ]
}

@test "merge_safe_check requires ticket_id argument" {
  run merge_safe_check "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

@test "merge_safe_check requires branch argument" {
  run merge_safe_check "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -ne 0 ]
}

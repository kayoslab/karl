#!/usr/bin/env bats
# tests/branch.bats - Tests for lib/branch.sh

BRANCH_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/branch.sh"

setup() {
  # shellcheck source=../lib/branch.sh
  source "${BRANCH_SH}"
  WORKSPACE_ROOT="$(mktemp -d)"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# branch_name - format and slug generation
# ---------------------------------------------------------------------------

@test "branch_name produces feature/<id>-<slug> format" {
  run branch_name "US-006" "Create deterministic gitflow feature branch"
  [ "${status}" -eq 0 ]
  [[ "${output}" == feature/US-006-* ]]
}

@test "branch_name produces correct full slug for known input" {
  run branch_name "US-006" "Create deterministic gitflow feature branch"
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-006-create-deterministic-gitflow-feature-branch" ]
}

@test "branch_name lowercases the title slug" {
  run branch_name "US-006" "My Feature TITLE"
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-006-my-feature-title" ]
}

@test "branch_name replaces spaces with hyphens" {
  run branch_name "US-001" "hello world"
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-001-hello-world" ]
}

@test "branch_name strips non-alphanumeric characters" {
  run branch_name "US-007" "Load agent: registry (from files)"
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-007-load-agent-registry-from-files" ]
}

@test "branch_name collapses multiple consecutive hyphens into one" {
  run branch_name "US-008" "  leading  and  trailing  "
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-008-leading-and-trailing" ]
}

@test "branch_name replaces underscores with hyphens" {
  run branch_name "US-009" "some_under_score_title"
  [ "${status}" -eq 0 ]
  [ "${output}" = "feature/US-009-some-under-score-title" ]
}

@test "branch_name is deterministic - same inputs always produce same output" {
  local first second
  first=$(branch_name "US-006" "Create deterministic gitflow feature branch")
  second=$(branch_name "US-006" "Create deterministic gitflow feature branch")
  [ "${first}" = "${second}" ]
}

@test "branch_name requires ticket_id argument" {
  run branch_name
  [ "${status}" -ne 0 ]
}

@test "branch_name requires ticket_title argument" {
  run branch_name "US-006"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# branch_ensure - branch creation and reuse
# ---------------------------------------------------------------------------

_init_repo() {
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
}

@test "branch_ensure creates a new branch from base and returns 0" {
  _init_repo
  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-test" "main"
  [ "${status}" -eq 0 ]
}

@test "branch_ensure switches HEAD to the created branch" {
  _init_repo
  branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-test" "main"
  local current_branch
  current_branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${current_branch}" = "feature/US-006-test" ]
}

@test "branch_ensure prints creating message for new branch" {
  _init_repo
  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-new" "main"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Creating branch"* ]]
}

@test "branch_ensure reuses existing branch and returns 0" {
  _init_repo
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-006-test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-test" "main"
  [ "${status}" -eq 0 ]
}

@test "branch_ensure prints reusing message when branch already exists" {
  _init_repo
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-006-test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-test" "main"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Reusing existing branch"* ]]
}

@test "branch_ensure returns 1 for invalid base branch" {
  _init_repo
  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-new" "nonexistent-base"
  [ "${status}" -ne 0 ]
}

@test "branch_ensure prints ERROR when base branch does not exist" {
  _init_repo
  run branch_ensure "${WORKSPACE_ROOT}" "feature/US-006-new" "nonexistent-base"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "branch_ensure requires directory argument" {
  run branch_ensure
  [ "${status}" -ne 0 ]
}

@test "branch_ensure requires branch argument" {
  _init_repo
  run branch_ensure "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

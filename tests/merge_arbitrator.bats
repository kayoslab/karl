#!/usr/bin/env bats
# tests/merge_arbitrator.bats - Tests for lib/merge_arbitrator.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input" "${WORKSPACE_ROOT}/Output"

  # shellcheck source=../lib/prd_claim.sh
  source "${KARL_DIR}/lib/prd_claim.sh"
  # shellcheck source=../lib/commit.sh
  source "${KARL_DIR}/lib/commit.sh"
  # shellcheck source=../lib/merge_arbitrator.sh
  source "${KARL_DIR}/lib/merge_arbitrator.sh"

  # Initialize git repo
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1

  cat > "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Test story", "priority": 1, "passes": false}
  ]
}
EOF
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial" > /dev/null 2>&1
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# merge_arbitrator_acquire / release
# ---------------------------------------------------------------------------

@test "merge_arbitrator_acquire creates .merge.lockdir" {
  merge_arbitrator_acquire "${WORKSPACE_ROOT}"
  [ -d "${WORKSPACE_ROOT}/.merge.lockdir" ]
  merge_arbitrator_release "${WORKSPACE_ROOT}"
}

@test "merge_arbitrator_release removes .merge.lockdir" {
  merge_arbitrator_acquire "${WORKSPACE_ROOT}"
  merge_arbitrator_release "${WORKSPACE_ROOT}"
  [ ! -d "${WORKSPACE_ROOT}/.merge.lockdir" ]
}

@test "merge_arbitrator_release is idempotent" {
  run merge_arbitrator_release "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# merge_arbitrator_merge
# ---------------------------------------------------------------------------

@test "merge_arbitrator_merge merges a clean feature branch" {
  # Create a feature branch with changes
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-001-test" > /dev/null 2>&1
  echo "feature work" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feat: add feature" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  run merge_arbitrator_merge "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test"
  [ "$status" -eq 0 ]
}

@test "merge_arbitrator_merge leaves HEAD on main" {
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-001-test" > /dev/null 2>&1
  echo "feature work" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feat: add feature" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  merge_arbitrator_merge "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test"
  local branch
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "merge_arbitrator_merge releases lock on success" {
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-001-test" > /dev/null 2>&1
  echo "feature" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feat" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  merge_arbitrator_merge "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test"
  [ ! -d "${WORKSPACE_ROOT}/.merge.lockdir" ]
}

@test "merge_arbitrator_merge releases lock on failure" {
  # No feature branch exists — will fail
  merge_arbitrator_merge "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}" "US-001" "feature/nonexistent" || true
  [ ! -d "${WORKSPACE_ROOT}/.merge.lockdir" ]
}

@test "merge_arbitrator_merge appends to progress.md" {
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/US-001-test" > /dev/null 2>&1
  echo "feature" > "${WORKSPACE_ROOT}/feature.txt"
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feat" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout main > /dev/null 2>&1

  merge_arbitrator_merge "${WORKSPACE_ROOT}" "${WORKSPACE_ROOT}" "US-001" "feature/US-001-test"
  [ -f "${WORKSPACE_ROOT}/Output/progress.md" ]
  grep -q "US-001" "${WORKSPACE_ROOT}/Output/progress.md"
}

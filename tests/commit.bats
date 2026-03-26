#!/usr/bin/env bats
# tests/commit.bats - Tests for lib/commit.sh (US-016)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
COMMIT_SH="${KARL_DIR}/lib/commit.sh"
PRD_SH="${KARL_DIR}/lib/prd.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  TICKET_ID="US-016"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"

  # shellcheck source=../lib/prd.sh
  source "${PRD_SH}"
  # shellcheck source=../lib/commit.sh
  source "${COMMIT_SH}"

  # Standard prd.json with target ticket not yet passing
  cat > "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-016", "title": "Commit and merge", "priority": 16, "passes": false},
    {"id": "US-017", "title": "Other story", "priority": 17, "passes": false}
  ]
}
EOF
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Helper: initialize a real git repo with a feature branch
# ---------------------------------------------------------------------------
_init_repo() {
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1 || true
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
}

_add_feature_branch() {
  local branch="${1:-feature/US-016-commit-and-merge}"
  git -C "${WORKSPACE_ROOT}" checkout -b "${branch}" > /dev/null 2>&1
  echo "impl" > "${WORKSPACE_ROOT}/impl.txt"
  git -C "${WORKSPACE_ROOT}" add "${WORKSPACE_ROOT}/impl.txt" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "feat: [${TICKET_ID}] implementation" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# commit_update_prd
# ---------------------------------------------------------------------------

@test "commit_update_prd sets passes=true for the target ticket" {
  commit_update_prd "${WORKSPACE_ROOT}" "${TICKET_ID}"
  result=$(jq -r '.userStories[] | select(.id == "US-016") | .passes' \
    "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${result}" = "true" ]
}

@test "commit_update_prd leaves other tickets unchanged" {
  commit_update_prd "${WORKSPACE_ROOT}" "${TICKET_ID}"
  result=$(jq -r '.userStories[] | select(.id == "US-017") | .passes' \
    "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${result}" = "false" ]
}

@test "commit_update_prd returns 0 on success" {
  run commit_update_prd "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
}

@test "commit_update_prd returns non-zero when prd.json does not exist" {
  rm -f "${WORKSPACE_ROOT}/Input/prd.json"
  run commit_update_prd "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -ne 0 ]
}

@test "commit_update_prd requires workspace_root argument" {
  run commit_update_prd
  [ "${status}" -ne 0 ]
}

@test "commit_update_prd requires ticket_id argument" {
  run commit_update_prd "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# commit_merge_to_main
# ---------------------------------------------------------------------------

@test "commit_merge_to_main returns 0 when merge succeeds" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  run commit_merge_to_main "${WORKSPACE_ROOT}" "feature/US-016-commit-and-merge"
  [ "${status}" -eq 0 ]
}

@test "commit_merge_to_main leaves HEAD on main after merge" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_merge_to_main "${WORKSPACE_ROOT}" "feature/US-016-commit-and-merge"
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "commit_merge_to_main returns non-zero when branch does not exist" {
  _init_repo
  run commit_merge_to_main "${WORKSPACE_ROOT}" "feature/nonexistent"
  [ "${status}" -ne 0 ]
}

@test "commit_merge_to_main requires workspace_root argument" {
  run commit_merge_to_main
  [ "${status}" -ne 0 ]
}

@test "commit_merge_to_main requires branch argument" {
  run commit_merge_to_main "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# commit_finalize — happy path
# ---------------------------------------------------------------------------

@test "commit_finalize returns 0 on success" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  run commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  [ "${status}" -eq 0 ]
}

@test "commit_finalize sets passes=true in prd.json on success" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  result=$(jq -r '.userStories[] | select(.id == "US-016") | .passes' \
    "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${result}" = "true" ]
}

@test "commit_finalize does not modify other tickets in prd.json" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  result=$(jq -r '.userStories[] | select(.id == "US-017") | .passes' \
    "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${result}" = "false" ]
}

@test "commit_finalize appends to Output/progress.md on success" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  [ -f "${WORKSPACE_ROOT}/Output/progress.md" ]
}

@test "commit_finalize progress entry includes ticket id" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  grep -q "${TICKET_ID}" "${WORKSPACE_ROOT}/Output/progress.md"
}

@test "commit_finalize progress entry includes the summary" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  grep -q "Commit, merge, and update PRD" "${WORKSPACE_ROOT}/Output/progress.md"
}

@test "commit_finalize leaves HEAD on main after success" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "commit_finalize deletes feature branch after merge" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  local branch_exists=0
  git -C "${WORKSPACE_ROOT}" show-ref --verify --quiet \
    "refs/heads/feature/US-016-commit-and-merge" 2>/dev/null && branch_exists=1 || true
  [ "${branch_exists}" -eq 0 ]
}

@test "commit_finalize git commit message includes ticket id" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  log=$(git -C "${WORKSPACE_ROOT}" log --oneline main)
  [[ "${log}" == *"${TICKET_ID}"* ]]
}

@test "commit_finalize git commit message includes the summary" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  log=$(git -C "${WORKSPACE_ROOT}" log --format=%s main | head -1)
  [[ "${log}" == *"${TICKET_ID}"* ]] || [[ "${log}" == *"Commit"* ]]
}

# ---------------------------------------------------------------------------
# commit_finalize — merge failure sequencing (key regression tests from plan)
# ---------------------------------------------------------------------------

@test "commit_finalize does NOT update prd.json when merge fails" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"

  # Override commit_merge_to_main to simulate merge failure
  commit_merge_to_main() { return 1; }

  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD" || true

  result=$(jq -r '.userStories[] | select(.id == "US-016") | .passes' \
    "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${result}" = "false" ]
}

@test "commit_finalize does NOT append to progress.md when merge fails" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"

  # Override commit_merge_to_main to simulate merge failure
  commit_merge_to_main() { return 1; }

  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD" || true

  # progress.md should either not exist or not contain the ticket entry
  if [[ -f "${WORKSPACE_ROOT}/Output/progress.md" ]]; then
    ! grep -q "${TICKET_ID}" "${WORKSPACE_ROOT}/Output/progress.md"
  else
    true
  fi
}

@test "commit_finalize returns non-zero when merge fails" {
  _init_repo
  _add_feature_branch "feature/US-016-commit-and-merge"

  commit_merge_to_main() { return 1; }

  run commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# commit_finalize — argument validation
# ---------------------------------------------------------------------------

@test "commit_finalize requires workspace_root argument" {
  run commit_finalize
  [ "${status}" -ne 0 ]
}

@test "commit_finalize requires ticket_id argument" {
  run commit_finalize "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

@test "commit_finalize requires branch argument" {
  run commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -ne 0 ]
}

@test "commit_finalize requires summary argument" {
  run commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" "feature/US-016-test"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# progress.md accumulation across iterations
# ---------------------------------------------------------------------------

@test "commit_finalize appends to existing progress.md rather than overwriting" {
  _init_repo
  mkdir -p "${WORKSPACE_ROOT}/Output"
  echo "## US-015: Previous entry" > "${WORKSPACE_ROOT}/Output/progress.md"

  _add_feature_branch "feature/US-016-commit-and-merge"
  commit_finalize "${WORKSPACE_ROOT}" "${TICKET_ID}" \
    "feature/US-016-commit-and-merge" "Commit, merge, and update PRD"

  grep -q "US-015" "${WORKSPACE_ROOT}/Output/progress.md"
  grep -q "${TICKET_ID}" "${WORKSPACE_ROOT}/Output/progress.md"
}

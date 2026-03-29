#!/usr/bin/env bats
# tests/supervisor.bats - Tests for lib/supervisor.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  WORKTREE_BASE="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input" "${WORKSPACE_ROOT}/Output"

  # Source required libs
  # shellcheck source=../lib/prd.sh
  source "${KARL_DIR}/lib/prd.sh"
  # shellcheck source=../lib/prd_claim.sh
  source "${KARL_DIR}/lib/prd_claim.sh"
  # shellcheck source=../lib/branch.sh
  source "${KARL_DIR}/lib/branch.sh"
  # shellcheck source=../lib/worktree.sh
  source "${KARL_DIR}/lib/worktree.sh"
  # shellcheck source=../lib/workspace.sh
  source "${KARL_DIR}/lib/workspace.sh"
  # shellcheck source=../lib/merge_arbitrator.sh
  source "${KARL_DIR}/lib/merge_arbitrator.sh"
  # shellcheck source=../lib/commit.sh
  source "${KARL_DIR}/lib/commit.sh"
  # shellcheck source=../lib/supervisor.sh
  source "${KARL_DIR}/lib/supervisor.sh"
}

teardown() {
  git -C "${WORKSPACE_ROOT}" worktree prune 2>/dev/null || true
  rm -rf "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
}

@test "supervisor_worker_loop returns 0 when all stories are already complete" {
  cat > "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Done", "priority": 1, "passes": true}
  ]
}
EOF

  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial" > /dev/null 2>&1

  run supervisor_worker_loop "${WORKSPACE_ROOT}" "1" "3" "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All stories complete"* ]]
}

@test "supervisor_run completes when all stories are already done" {
  cat > "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Done", "priority": 1, "passes": true}
  ]
}
EOF

  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial" > /dev/null 2>&1

  run supervisor_run "${WORKSPACE_ROOT}" 2 3 "${WORKTREE_BASE}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"All workers completed"* ]]
}

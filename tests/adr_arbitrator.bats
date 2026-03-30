#!/usr/bin/env bats
# tests/adr_arbitrator.bats - Tests for lib/adr_arbitrator.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  WORKTREE_BASE="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input" "${WORKSPACE_ROOT}/Output/ADR"

  # shellcheck source=../lib/adr_arbitrator.sh
  source "${KARL_DIR}/lib/adr_arbitrator.sh"
  # shellcheck source=../lib/architect.sh
  source "${KARL_DIR}/lib/architect.sh"
  # shellcheck source=../lib/subagent.sh
  source "${KARL_DIR}/lib/subagent.sh"

  # Initialize git repo on main
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1

  # Seed ADR on main
  cat > "${WORKSPACE_ROOT}/Output/ADR/US-001.md" <<'EOF'
# ADR-001: Seed Decision

## Status
Accepted

## Context
Seed ADR for testing.

## Decision
Use this as a baseline.

## Consequences
Tests can verify sync behavior.
EOF

  cat > "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Seed", "priority": 1, "passes": true},
    {"id": "US-002", "title": "Test A", "priority": 2, "passes": false},
    {"id": "US-003", "title": "Test B", "priority": 3, "passes": false}
  ]
}
EOF

  git -C "${WORKSPACE_ROOT}" add . > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit -m "initial with seed ADR" > /dev/null 2>&1
}

teardown() {
  # Clean up worktrees before removing directories
  git -C "${WORKSPACE_ROOT}" worktree prune 2>/dev/null || true
  rm -rf "${WORKSPACE_ROOT}" "${WORKTREE_BASE}"
}

# Helper: create a worktree branching from main
_create_worktree() {
  local ticket_id="${1}"
  local branch="feature/${ticket_id}-test"
  local wt_path="${WORKTREE_BASE}/${ticket_id}"
  git -C "${WORKSPACE_ROOT}" worktree add -b "${branch}" "${wt_path}" main > /dev/null 2>&1
  echo "${wt_path}"
}

# Helper: add a new ADR directly to main (simulating another worker's fast-track)
_add_adr_to_main() {
  local story_id="${1}"
  local content="${2}"
  local adr_file
  adr_file="$(mktemp)"
  printf '%s\n' "${content}" > "${adr_file}"
  # Use the same plumbing approach to add directly to main
  local blob
  blob=$(git -C "${WORKSPACE_ROOT}" hash-object -w "${adr_file}")
  local tmp_index="${WORKSPACE_ROOT}/.test-index.$$"
  GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" read-tree main
  GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" \
    update-index --add --cacheinfo "100644,${blob},Output/ADR/${story_id}.md"
  local tree
  tree=$(GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" write-tree)
  local parent
  parent=$(git -C "${WORKSPACE_ROOT}" rev-parse main)
  local commit
  commit=$(echo "test: add ${story_id} ADR" | \
    git -C "${WORKSPACE_ROOT}" commit-tree "${tree}" -p "${parent}")
  git -C "${WORKSPACE_ROOT}" update-ref refs/heads/main "${commit}"
  rm -f "${tmp_index}" "${adr_file}"
}

# ---------------------------------------------------------------------------
# adr_arbitrator_acquire / release
# ---------------------------------------------------------------------------

@test "adr_arbitrator_acquire creates .adr.lockdir" {
  adr_arbitrator_acquire "${WORKSPACE_ROOT}"
  [ -d "${WORKSPACE_ROOT}/.adr.lockdir" ]
  adr_arbitrator_release "${WORKSPACE_ROOT}"
}

@test "adr_arbitrator_release removes .adr.lockdir" {
  adr_arbitrator_acquire "${WORKSPACE_ROOT}"
  adr_arbitrator_release "${WORKSPACE_ROOT}"
  [ ! -d "${WORKSPACE_ROOT}/.adr.lockdir" ]
}

@test "adr_arbitrator_release is idempotent" {
  run adr_arbitrator_release "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# adr_sync_from_main
# ---------------------------------------------------------------------------

@test "adr_sync_from_main copies ADRs created after branch point into worktree" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  # Add a new ADR to main after the worktree was branched
  _add_adr_to_main "US-099" "# ADR: New decision after branch"

  # Worktree should NOT have it yet
  [ ! -f "${wt_path}/Output/ADR/US-099.md" ]

  # Sync should bring it in
  adr_sync_from_main "${WORKSPACE_ROOT}" "${wt_path}"

  [ -f "${wt_path}/Output/ADR/US-099.md" ]
  grep -q "New decision after branch" "${wt_path}/Output/ADR/US-099.md"
}

@test "adr_sync_from_main preserves seed ADR in worktree" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  adr_sync_from_main "${WORKSPACE_ROOT}" "${wt_path}"

  [ -f "${wt_path}/Output/ADR/US-001.md" ]
  grep -q "Seed Decision" "${wt_path}/Output/ADR/US-001.md"
}

@test "adr_sync_from_main handles empty ADR directory gracefully" {
  # Remove all ADRs from main
  local tmp_index="${WORKSPACE_ROOT}/.test-index.$$"
  GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" read-tree main
  GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" \
    rm --cached -r Output/ADR/ > /dev/null 2>&1 || true
  local tree
  tree=$(GIT_INDEX_FILE="${tmp_index}" git -C "${WORKSPACE_ROOT}" write-tree)
  local parent
  parent=$(git -C "${WORKSPACE_ROOT}" rev-parse main)
  local commit
  commit=$(echo "test: remove ADRs" | \
    git -C "${WORKSPACE_ROOT}" commit-tree "${tree}" -p "${parent}")
  git -C "${WORKSPACE_ROOT}" update-ref refs/heads/main "${commit}"
  rm -f "${tmp_index}"

  local wt_path
  wt_path=$(_create_worktree "US-002")

  run adr_sync_from_main "${WORKSPACE_ROOT}" "${wt_path}"
  [ "$status" -eq 0 ]
}

@test "adr_sync_from_main is idempotent" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  _add_adr_to_main "US-099" "# ADR: Idempotency test"

  adr_sync_from_main "${WORKSPACE_ROOT}" "${wt_path}"
  adr_sync_from_main "${WORKSPACE_ROOT}" "${wt_path}"

  [ -f "${wt_path}/Output/ADR/US-099.md" ]
  grep -q "Idempotency test" "${wt_path}/Output/ADR/US-099.md"
}

# ---------------------------------------------------------------------------
# adr_fast_track_to_main
# ---------------------------------------------------------------------------

@test "adr_fast_track_to_main commits ADR to main without checkout" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  # Create an ADR file in the worktree
  mkdir -p "${wt_path}/Output/ADR"
  echo "# ADR: Fast-tracked decision" > "${wt_path}/Output/ADR/US-002.md"

  adr_fast_track_to_main "${WORKSPACE_ROOT}" "${wt_path}/Output/ADR/US-002.md" "US-002"

  # Verify it's on main via git show
  local content
  content=$(git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-002.md")
  echo "${content}" | grep -q "Fast-tracked decision"
}

@test "adr_fast_track_to_main preserves main history" {
  local before_count
  before_count=$(git -C "${WORKSPACE_ROOT}" rev-list --count main)

  local wt_path
  wt_path=$(_create_worktree "US-002")
  mkdir -p "${wt_path}/Output/ADR"
  echo "# ADR: History test" > "${wt_path}/Output/ADR/US-002.md"

  adr_fast_track_to_main "${WORKSPACE_ROOT}" "${wt_path}/Output/ADR/US-002.md" "US-002"

  local after_count
  after_count=$(git -C "${WORKSPACE_ROOT}" rev-list --count main)

  # Exactly one new commit
  [ "$((after_count - before_count))" -eq 1 ]

  # Seed ADR still exists on main
  git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-001.md" | grep -q "Seed Decision"
}

@test "adr_fast_track_to_main cleans up temp index" {
  local wt_path
  wt_path=$(_create_worktree "US-002")
  mkdir -p "${wt_path}/Output/ADR"
  echo "# ADR: Cleanup test" > "${wt_path}/Output/ADR/US-002.md"

  adr_fast_track_to_main "${WORKSPACE_ROOT}" "${wt_path}/Output/ADR/US-002.md" "US-002"

  # No leftover .adr-index.* files
  local leftover
  leftover=$(find "${WORKSPACE_ROOT}" -maxdepth 1 -name '.adr-index.*' | wc -l)
  [ "${leftover}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# adr_arbitrator_run (full flow)
# ---------------------------------------------------------------------------

@test "adr_arbitrator_run releases lock on success" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  # Stub architect_run to create an ADR
  architect_run() {
    local ws="${1}"
    local sj="${2}"
    mkdir -p "${ws}/Output/ADR" "${ws}/Output/US-002"
    echo '{"approved":true,"adr_entry":"# ADR: Stub"}' > "${ws}/Output/US-002/architect.json"
    echo "# ADR: Stub decision" > "${ws}/Output/ADR/US-002.md"
    git -C "${ws}" add -A > /dev/null 2>&1 || true
    git -C "${ws}" commit -m "arch: stub" > /dev/null 2>&1 || true
    return 0
  }

  local story_json='{"id":"US-002","title":"Test A"}'
  adr_arbitrator_run "${WORKSPACE_ROOT}" "${wt_path}" "${story_json}" "{}"

  [ ! -d "${WORKSPACE_ROOT}/.adr.lockdir" ]
}

@test "adr_arbitrator_run releases lock on failure" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  # Stub architect_run to fail
  architect_run() {
    return 1
  }

  local story_json='{"id":"US-002","title":"Test A"}'
  run adr_arbitrator_run "${WORKSPACE_ROOT}" "${wt_path}" "${story_json}" "{}"

  [ ! -d "${WORKSPACE_ROOT}/.adr.lockdir" ]
}

@test "adr_arbitrator_run fast-tracks ADR to main" {
  local wt_path
  wt_path=$(_create_worktree "US-002")

  # Stub architect_run to create an ADR
  architect_run() {
    local ws="${1}"
    mkdir -p "${ws}/Output/ADR" "${ws}/Output/US-002"
    echo '{"approved":true}' > "${ws}/Output/US-002/architect.json"
    echo "# ADR: Worker decision" > "${ws}/Output/ADR/US-002.md"
    git -C "${ws}" add -A > /dev/null 2>&1 || true
    git -C "${ws}" commit -m "arch: stub" > /dev/null 2>&1 || true
    return 0
  }

  local story_json='{"id":"US-002","title":"Test A"}'
  adr_arbitrator_run "${WORKSPACE_ROOT}" "${wt_path}" "${story_json}" "{}"

  # ADR should be on main
  git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-002.md" | grep -q "Worker decision"
}

@test "sequential fast-tracks from two worktrees both visible on main" {
  local wt_a wt_b
  wt_a=$(_create_worktree "US-002")
  wt_b=$(_create_worktree "US-003")

  # Stub architect_run per story_id
  architect_run() {
    local ws="${1}"
    local sj="${2}"
    local sid
    sid=$(printf '%s' "${sj}" | jq -r '.id')
    mkdir -p "${ws}/Output/ADR" "${ws}/Output/${sid}"
    echo '{"approved":true}' > "${ws}/Output/${sid}/architect.json"
    echo "# ADR: Decision for ${sid}" > "${ws}/Output/ADR/${sid}.md"
    git -C "${ws}" add -A > /dev/null 2>&1 || true
    git -C "${ws}" commit -m "arch: ${sid}" > /dev/null 2>&1 || true
    return 0
  }

  # Run arbitrator for US-002 first
  adr_arbitrator_run "${WORKSPACE_ROOT}" "${wt_a}" '{"id":"US-002","title":"A"}' "{}"
  # Then for US-003
  adr_arbitrator_run "${WORKSPACE_ROOT}" "${wt_b}" '{"id":"US-003","title":"B"}' "{}"

  # Both ADRs should be on main
  git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-002.md" | grep -q "Decision for US-002"
  git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-003.md" | grep -q "Decision for US-003"

  # Seed ADR should still be there
  git -C "${WORKSPACE_ROOT}" show "main:Output/ADR/US-001.md" | grep -q "Seed Decision"
}

#!/usr/bin/env bats
# tests/loop.bats - Tests for lib/loop.sh (US-005)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LOOP_SH="${KARL_DIR}/lib/loop.sh"
PRD_SH="${KARL_DIR}/lib/prd.sh"
BRANCH_SH="${KARL_DIR}/lib/branch.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  # shellcheck source=../lib/prd.sh
  source "${PRD_SH}"
  # shellcheck source=../lib/branch.sh
  source "${BRANCH_SH}"
  # shellcheck source=../lib/loop.sh
  source "${LOOP_SH}"

  # Default stubs: branch operations and pipeline succeed
  # (tests that need real/failing behavior override these)
  branch_name() { printf 'feature/%s-stub\n' "${1}"; }
  branch_ensure() { return 0; }
  loop_run_ticket() { return 0; }
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_prd() {
  cat > "${WORKSPACE_ROOT}/Input/prd.json"
}

# ---------------------------------------------------------------------------
# loop_run_iteration
# ---------------------------------------------------------------------------

@test "loop_run_iteration returns 0 and prints story id when unfinished story exists" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"US-001"* ]]
}

@test "loop_run_iteration returns 2 and prints completion message when all stories pass" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"all stories complete"* ]]
}

@test "loop_run_iteration returns 1 when prd.json is malformed" {
  printf 'not-json' > "${WORKSPACE_ROOT}/Input/prd.json"
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# loop_run
# ---------------------------------------------------------------------------

@test "loop_run returns 0 (clean exit) when all stories already pass" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true}
  ]
}
EOF
  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "loop_run returns 0 after processing the one unfinished story (story marked passing mid-loop via prd update)" {
  # Write a prd with one unfinished story; after first iteration update it to passing
  # to prevent an infinite loop in this test.
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false}
  ]
}
EOF

  # Override loop_run_iteration to simulate: first call returns 0, second returns 2.
  local call_count=0
  loop_run_iteration() {
    call_count=$((call_count + 1))
    if [[ "${call_count}" -eq 1 ]]; then
      echo "karl: selected story US-001"
      return 0
    fi
    echo "karl: all stories complete — nothing left to do"
    return 2
  }

  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "loop_run returns 1 when iteration returns an error" {
  # Override loop_run_iteration to simulate an error
  loop_run_iteration() {
    return 1
  }

  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# loop_run_iteration - branch integration (US-006)
# ---------------------------------------------------------------------------

@test "loop_run_iteration logs configured retry limit for the active ticket" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-012", "priority": 12, "passes": false, "title": "Configurable retry limit"}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}" 7
  [[ "${output}" == *"Retry limit for this ticket: 7"* ]]
}

@test "loop_run_iteration uses default max_retries of 10 when not specified" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-012", "priority": 12, "passes": false, "title": "Configurable retry limit"}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [[ "${output}" == *"Retry limit for this ticket: 10"* ]]
}

@test "loop_run accepts max_retries parameter and threads it to iteration" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true}
  ]
}
EOF
  run loop_run "${WORKSPACE_ROOT}" 5
  [ "${status}" -eq 0 ]
}

@test "loop_run_iteration returns 1 with ERROR output when branch_ensure fails" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-006", "priority": 6, "passes": false, "title": "Create deterministic gitflow feature branch"}
  ]
}
EOF
  # Stub branch_ensure to simulate a git failure
  branch_ensure() {
    echo "ERROR: git checkout failed"
    return 1
  }

  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# loop_run_iteration - priority selection (US-019 AC#2)
# ---------------------------------------------------------------------------

@test "loop_run_iteration selects the story with the lowest priority number first" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-003", "priority": 3, "passes": false, "title": "Third"},
    {"id": "US-001", "priority": 1, "passes": false, "title": "First"},
    {"id": "US-002", "priority": 2, "passes": false, "title": "Second"}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"US-001"* ]]
}

@test "loop_run_iteration skips already-passing stories and selects next unfinished" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true, "title": "Done"},
    {"id": "US-002", "priority": 2, "passes": false, "title": "Pending"}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"US-002"* ]]
}

# ---------------------------------------------------------------------------
# loop_run - continuous loop behavior (US-019 AC#1, AC#2)
# ---------------------------------------------------------------------------

@test "loop_run calls iteration multiple times until all tickets are done" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false, "title": "First"},
    {"id": "US-002", "priority": 2, "passes": false, "title": "Second"}
  ]
}
EOF

  local counter_file="${WORKSPACE_ROOT}/call_count"
  printf '0\n' > "${counter_file}"

  loop_run_iteration() {
    local count
    count=$(cat "${counter_file}")
    count=$(( count + 1 ))
    printf '%d\n' "${count}" > "${counter_file}"

    if [ "${count}" -le 2 ]; then
      # Simulate processing a ticket
      echo "karl: selected story US-00${count}"
      return 0
    fi
    # Third call: signal all done
    echo "karl: all stories complete — nothing left to do"
    return 2
  }

  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${counter_file}")" -eq 3 ]
}

# ---------------------------------------------------------------------------
# loop_run - error handling without PRD corruption (US-019 AC#4)
# ---------------------------------------------------------------------------

@test "loop_run stops on iteration error but does not modify prd.json" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false, "title": "First"}
  ]
}
EOF

  local prd_before
  prd_before=$(cat "${WORKSPACE_ROOT}/Input/prd.json")

  loop_run_iteration() { return 1; }

  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]

  local prd_after
  prd_after=$(cat "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${prd_before}" = "${prd_after}" ]
}

# ---------------------------------------------------------------------------
# loop_run - clean exit message (US-019 AC#3)
# ---------------------------------------------------------------------------

@test "loop_run prints completion message when all stories are done" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true, "title": "Done"}
  ]
}
EOF
  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"complete"* ]]
}

@test "loop_run exits with code 0 after continuous iteration until all done" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false, "title": "Story"}
  ]
}
EOF

  local called_file="${WORKSPACE_ROOT}/called"
  printf '0\n' > "${called_file}"

  loop_run_iteration() {
    local n
    n=$(cat "${called_file}")
    n=$(( n + 1 ))
    printf '%d\n' "${n}" > "${called_file}"
    if [ "${n}" -eq 1 ]; then
      echo "karl: selected story US-001"
      return 0
    fi
    # Second call: all done
    echo "karl: all stories complete — nothing left to do"
    return 2
  }

  run loop_run "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "loop_run_iteration returns 0 and logs story id for the selected ticket" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-019", "priority": 19, "passes": false, "title": "Keep terminal loop running continuously"}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"US-019"* ]]
}

# ---------------------------------------------------------------------------
# loop_run_iteration - final result line on all code paths (US-022 AC#1)
# ---------------------------------------------------------------------------

@test "loop_run_iteration emits a result line containing 'complete' when all stories pass" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": true}
  ]
}
EOF
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 2 ]
  [[ "${output}" == *"complete"* ]]
}

@test "loop_run_iteration emits an ERROR line when branch_ensure fails" {
  write_prd <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false, "title": "Story"}
  ]
}
EOF
  branch_ensure() { return 1; }
  run loop_run_iteration "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ERROR"* ]]
}

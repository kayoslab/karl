#!/usr/bin/env bats
# tests/prd_claim.bats - Tests for lib/prd_claim.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PRD_CLAIM_SH="${KARL_DIR}/lib/prd_claim.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  # shellcheck source=../lib/prd_claim.sh
  source "${PRD_CLAIM_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

make_prd() {
  local file="${1}"
  cat > "${file}"
}

# ---------------------------------------------------------------------------
# _prd_lock_acquire / _prd_lock_release
# ---------------------------------------------------------------------------

@test "_prd_lock_acquire creates .prd.lockdir" {
  _prd_lock_acquire "${WORKSPACE_ROOT}"
  [ -d "${WORKSPACE_ROOT}/.prd.lockdir" ]
  _prd_lock_release "${WORKSPACE_ROOT}"
}

@test "_prd_lock_release removes .prd.lockdir" {
  _prd_lock_acquire "${WORKSPACE_ROOT}"
  _prd_lock_release "${WORKSPACE_ROOT}"
  [ ! -d "${WORKSPACE_ROOT}/.prd.lockdir" ]
}

@test "_prd_lock_release is idempotent" {
  run _prd_lock_release "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# prd_claim_ticket
# ---------------------------------------------------------------------------

@test "prd_claim_ticket sets status=in_progress for available ticket" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false}
  ]
}
EOF
  prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  local status_val
  status_val=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${status_val}" = "in_progress" ]
}

@test "prd_claim_ticket sets claimed_by field" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false}
  ]
}
EOF
  prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  local claimed
  claimed=$(jq -r '.userStories[0].claimed_by' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${claimed}" = "worker-1" ]
}

@test "prd_claim_ticket fails when ticket is already in_progress" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress"}
  ]
}
EOF
  run prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-2"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not available"* ]]
}

@test "prd_claim_ticket fails when ticket already passed" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": true}
  ]
}
EOF
  run prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  [ "$status" -ne 0 ]
}

@test "prd_claim_ticket does not modify other tickets" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false},
    {"id": "US-002", "title": "Story two", "priority": 2, "passes": false}
  ]
}
EOF
  prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  local other_status
  other_status=$(jq -r '.userStories[1].status // "none"' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${other_status}" = "none" ]
}

@test "prd_claim_ticket returns 1 when prd.json missing" {
  run prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  [ "$status" -ne 0 ]
}

@test "prd_claim_ticket releases lock even on failure" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story", "priority": 1, "passes": true}
  ]
}
EOF
  prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "w1" || true
  [ ! -d "${WORKSPACE_ROOT}/.prd.lockdir" ]
}

# ---------------------------------------------------------------------------
# prd_release_ticket
# ---------------------------------------------------------------------------

@test "prd_release_ticket sets status=available" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress", "claimed_by": "worker-1"}
  ]
}
EOF
  prd_release_ticket "${WORKSPACE_ROOT}" "US-001"
  local status_val
  status_val=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${status_val}" = "available" ]
}

@test "prd_release_ticket removes claimed_by" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress", "claimed_by": "worker-1"}
  ]
}
EOF
  prd_release_ticket "${WORKSPACE_ROOT}" "US-001"
  local claimed
  claimed=$(jq -r '.userStories[0].claimed_by // "none"' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${claimed}" = "none" ]
}

@test "prd_release_ticket returns 1 when prd.json missing" {
  run prd_release_ticket "${WORKSPACE_ROOT}" "US-001"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# prd_complete_ticket
# ---------------------------------------------------------------------------

@test "prd_complete_ticket sets status=pass and passes=true" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress"}
  ]
}
EOF
  prd_complete_ticket "${WORKSPACE_ROOT}" "US-001"
  local status_val passes_val
  status_val=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  passes_val=$(jq -r '.userStories[0].passes' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${status_val}" = "pass" ]
  [ "${passes_val}" = "true" ]
}

@test "prd_complete_ticket removes claimed_by" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress", "claimed_by": "worker-1"}
  ]
}
EOF
  prd_complete_ticket "${WORKSPACE_ROOT}" "US-001"
  local claimed
  claimed=$(jq -r '.userStories[0].claimed_by // "none"' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${claimed}" = "none" ]
}

@test "prd_complete_ticket does not modify other tickets" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress"},
    {"id": "US-002", "title": "Story two", "priority": 2, "passes": false}
  ]
}
EOF
  prd_complete_ticket "${WORKSPACE_ROOT}" "US-001"
  local other_passes
  other_passes=$(jq -r '.userStories[1].passes' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${other_passes}" = "false" ]
}

@test "prd_complete_ticket returns 1 when prd.json missing" {
  run prd_complete_ticket "${WORKSPACE_ROOT}" "US-001"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# Flat array format support
# ---------------------------------------------------------------------------

@test "prd_claim_ticket works with flat array format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "title": "Story one", "priority": 1, "passes": false}
]
EOF
  prd_claim_ticket "${WORKSPACE_ROOT}" "US-001" "worker-1"
  local status_val
  status_val=$(jq -r '.[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${status_val}" = "in_progress" ]
}

# ---------------------------------------------------------------------------
# prd_reset_in_progress
# ---------------------------------------------------------------------------

@test "prd_reset_in_progress resets in_progress tickets to available" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "status": "in_progress", "claimed_by": "worker-1"},
    {"id": "US-002", "title": "Story two", "priority": 2, "status": "pass", "passes": true}
  ]
}
EOF
  run prd_reset_in_progress "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local s1 s2 claimed
  s1=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  s2=$(jq -r '.userStories[1].status' "${WORKSPACE_ROOT}/Input/prd.json")
  claimed=$(jq -r '.userStories[0].claimed_by // "null"' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${s1}" = "available" ]
  [ "${s2}" = "pass" ]
  [ "${claimed}" = "null" ]
}

@test "prd_reset_in_progress is a no-op when no tickets are in_progress" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "status": "available"}
  ]
}
EOF
  run prd_reset_in_progress "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local s1
  s1=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${s1}" = "available" ]
}

@test "prd_reset_in_progress returns 0 when prd.json does not exist" {
  run prd_reset_in_progress "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# prd_reset_failed
# ---------------------------------------------------------------------------

@test "prd_reset_failed resets fail tickets to available" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "status": "fail"},
    {"id": "US-002", "title": "Story two", "priority": 2, "status": "pass", "passes": true},
    {"id": "US-003", "title": "Story three", "priority": 3, "status": "fail"}
  ]
}
EOF
  run prd_reset_failed "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local s1 s2 s3
  s1=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  s2=$(jq -r '.userStories[1].status' "${WORKSPACE_ROOT}/Input/prd.json")
  s3=$(jq -r '.userStories[2].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${s1}" = "available" ]
  [ "${s2}" = "pass" ]
  [ "${s3}" = "available" ]
}

@test "prd_reset_failed is a no-op when no tickets are failed" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "status": "available"}
  ]
}
EOF
  run prd_reset_failed "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local s1
  s1=$(jq -r '.userStories[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${s1}" = "available" ]
}

@test "prd_reset_failed returns 0 when prd.json does not exist" {
  run prd_reset_failed "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
}

@test "prd_reset_failed works with flat array format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "title": "Story one", "priority": 1, "status": "fail"}
]
EOF
  run prd_reset_failed "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  local s1
  s1=$(jq -r '.[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${s1}" = "available" ]
}

@test "prd_complete_ticket works with flat array format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "title": "Story one", "priority": 1, "passes": false, "status": "in_progress"}
]
EOF
  prd_complete_ticket "${WORKSPACE_ROOT}" "US-001"
  local status_val
  status_val=$(jq -r '.[0].status' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${status_val}" = "pass" ]
}

#!/usr/bin/env bats
# tests/prd.bats - Tests for lib/prd.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PRD_SH="${KARL_DIR}/lib/prd.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  # shellcheck source=../lib/prd.sh
  source "${PRD_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_prd() {
  local file="${1}"
  cat > "${file}"
}

# ---------------------------------------------------------------------------
# prd_validate
# ---------------------------------------------------------------------------

@test "prd_validate returns 0 for valid prd.json with userStories" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story one", "priority": 1, "passes": false}
  ]
}
EOF
  run prd_validate "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
}

@test "prd_validate returns 1 when file does not exist" {
  run prd_validate "${WORKSPACE_ROOT}/Input/missing.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "prd_validate returns 1 for malformed JSON" {
  echo "not valid json {{{" > "${WORKSPACE_ROOT}/Input/prd.json"
  run prd_validate "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "prd_validate returns 1 when userStories key is missing" {
  echo '{"project": "test"}' > "${WORKSPACE_ROOT}/Input/prd.json"
  run prd_validate "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "prd_validate returns 1 when userStories array is empty" {
  echo '{"userStories": []}' > "${WORKSPACE_ROOT}/Input/prd.json"
  run prd_validate "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# prd_next_story
# ---------------------------------------------------------------------------

@test "prd_next_story returns the story with the lowest priority among passes=false" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "First",  "priority": 1, "passes": true},
    {"id": "US-002", "title": "Second", "priority": 2, "passes": false},
    {"id": "US-003", "title": "Third",  "priority": 3, "passes": false}
  ]
}
EOF
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"US-002"'* ]]
}

@test "prd_next_story skips stories where passes=true" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Done",    "priority": 1, "passes": true},
    {"id": "US-002", "title": "Pending", "priority": 5, "passes": false}
  ]
}
EOF
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"US-002"'* ]]
  [[ "$output" != *'"US-001"'* ]]
}

@test "prd_next_story returns 2 when all stories pass" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Done one", "priority": 1, "passes": true},
    {"id": "US-002", "title": "Done two", "priority": 2, "passes": true}
  ]
}
EOF
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 2 ]
}

@test "prd_next_story output is valid JSON parseable by jq" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "My Story", "priority": 1, "passes": false}
  ]
}
EOF
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
  # Output must be parseable by jq and have expected id field
  result=$(echo "$output" | jq -r '.id')
  [ "$result" = "US-001" ]
}

@test "prd_next_story returns 1 for invalid prd file" {
  echo "not json" > "${WORKSPACE_ROOT}/Input/prd.json"
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# prd_select_next
# ---------------------------------------------------------------------------

@test "prd_select_next reads from workspace_root/Input/prd.json and returns story" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-005", "title": "Target", "priority": 5, "passes": false}
  ]
}
EOF
  run prd_select_next "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]
  [[ "$output" == *'"US-005"'* ]]
}

@test "prd_select_next returns 2 and prints completion message when all stories pass" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Done", "priority": 1, "passes": true}
  ]
}
EOF
  run prd_select_next "${WORKSPACE_ROOT}"
  [ "$status" -eq 2 ]
  [[ "$output" == *"all stories complete"* ]]
}

@test "prd_next_story returns 3 when tickets exist but all are blocked by dependencies" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Setup", "priority": 1, "status": "in_progress"},
    {"id": "US-002", "title": "Feature", "priority": 2, "passes": false, "depends_on": ["US-001"]}
  ]
}
EOF
  run prd_next_story "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 3 ]
}

@test "prd_select_next returns 3 when tickets are pending but none available" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Setup", "priority": 1, "status": "in_progress"},
    {"id": "US-002", "title": "Feature", "priority": 2, "passes": false, "depends_on": ["US-001"]}
  ]
}
EOF
  run prd_select_next "${WORKSPACE_ROOT}"
  [ "$status" -eq 3 ]
}

@test "prd_select_next returns 1 when prd.json is malformed" {
  echo "invalid" > "${WORKSPACE_ROOT}/Input/prd.json"
  run prd_select_next "${WORKSPACE_ROOT}"
  [ "$status" -eq 1 ]
}

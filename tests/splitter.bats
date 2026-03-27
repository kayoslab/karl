#!/usr/bin/env bats
# tests/splitter.bats - Tests for lib/splitter.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SPLITTER_SH="${KARL_DIR}/lib/splitter.sh"
AGENTS_SH="${KARL_DIR}/lib/agents.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  # shellcheck source=../lib/agents.sh
  source "${AGENTS_SH}"
  # shellcheck source=../lib/splitter.sh
  source "${SPLITTER_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

make_prd() {
  local file="${1}"
  cat > "${file}"
}

# ---------------------------------------------------------------------------
# splitter_apply_decisions
# ---------------------------------------------------------------------------

@test "splitter_apply_decisions replaces parent with sub-tickets on split action" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Complex story", "priority": 1, "passes": false},
    {"id": "US-002", "title": "Simple story", "priority": 2, "passes": false}
  ]
}
EOF

  local decisions='{"split_decisions":[{"parent_id":"US-001","action":"split","reason":"test","sub_tickets":[{"id":"US-001.1","title":"Part A","priority":1,"passes":false,"status":"available","depends_on":[],"split_from":"US-001"},{"id":"US-001.2","title":"Part B","priority":2,"passes":false,"status":"available","depends_on":["US-001.1"],"split_from":"US-001"}]}]}'

  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  # US-001 should be gone, replaced by US-001.1 and US-001.2
  local count
  count=$(jq '.userStories | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 3 ]

  # Original US-001 should not exist
  local original
  original=$(jq '[.userStories[] | select(.id == "US-001")] | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${original}" -eq 0 ]

  # Sub-tickets should exist
  local sub1 sub2
  sub1=$(jq '[.userStories[] | select(.id == "US-001.1")] | length' "${WORKSPACE_ROOT}/Input/prd.json")
  sub2=$(jq '[.userStories[] | select(.id == "US-001.2")] | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${sub1}" -eq 1 ]
  [ "${sub2}" -eq 1 ]
}

@test "splitter_apply_decisions preserves untouched tickets on keep action" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Simple story", "priority": 1, "passes": false}
  ]
}
EOF

  local decisions='{"split_decisions":[{"parent_id":"US-001","action":"keep","reason":"Already atomic"}]}'

  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  local count
  count=$(jq '.userStories | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 1 ]

  local id
  id=$(jq -r '.userStories[0].id' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${id}" = "US-001" ]
}

@test "splitter_apply_decisions preserves split_from and depends_on fields" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Complex", "priority": 1, "passes": false}
  ]
}
EOF

  local decisions='{"split_decisions":[{"parent_id":"US-001","action":"split","reason":"test","sub_tickets":[{"id":"US-001.1","title":"Part A","priority":1,"passes":false,"status":"available","depends_on":[],"split_from":"US-001"},{"id":"US-001.2","title":"Part B","priority":2,"passes":false,"status":"available","depends_on":["US-001.1"],"split_from":"US-001"}]}]}'

  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  local split_from depends_on
  split_from=$(jq -r '.userStories[] | select(.id == "US-001.2") | .split_from' "${WORKSPACE_ROOT}/Input/prd.json")
  depends_on=$(jq -r '.userStories[] | select(.id == "US-001.2") | .depends_on[0]' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${split_from}" = "US-001" ]
  [ "${depends_on}" = "US-001.1" ]
}

@test "splitter_apply_decisions returns 1 when prd.json missing" {
  local decisions='{"split_decisions":[]}'
  run splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"
  [ "$status" -ne 0 ]
}

@test "splitter_apply_decisions handles empty split_decisions" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "title": "Story", "priority": 1, "passes": false}
  ]
}
EOF

  local decisions='{"split_decisions":[]}'
  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  local count
  count=$(jq '.userStories | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 1 ]
}

@test "splitter_apply_decisions works with flat array format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "title": "Complex story", "priority": 1, "passes": false}
]
EOF

  local decisions='{"split_decisions":[{"parent_id":"US-001","action":"split","reason":"test","sub_tickets":[{"id":"US-001.1","title":"Part A","priority":1,"passes":false,"status":"available","depends_on":[],"split_from":"US-001"}]}]}'

  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  local count
  count=$(jq 'length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 1 ]

  local id
  id=$(jq -r '.[0].id' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${id}" = "US-001.1" ]
}

# ---------------------------------------------------------------------------
# splitter_validate_deps
# ---------------------------------------------------------------------------

@test "splitter_validate_deps passes for valid DAG" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001.1", "priority": 1, "passes": false, "depends_on": []},
  {"id": "US-001.2", "priority": 2, "passes": false, "depends_on": ["US-001.1"]},
  {"id": "US-002.1", "priority": 3, "passes": false, "depends_on": ["US-001.2"]}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
}

@test "splitter_validate_deps passes with cross-story dependencies" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001.1", "priority": 1, "passes": false, "depends_on": []},
  {"id": "US-001.2", "priority": 1, "passes": false, "depends_on": ["US-001.1"]},
  {"id": "US-002.1", "priority": 2, "passes": false, "depends_on": []},
  {"id": "US-002.2", "priority": 2, "passes": false, "depends_on": ["US-002.1", "US-001.2"]}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
}

@test "splitter_validate_deps fails on dangling depends_on reference" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001.1", "priority": 1, "passes": false, "depends_on": ["US-999"]}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"non-existent"* ]]
}

@test "splitter_validate_deps fails on circular dependency" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "A", "priority": 1, "passes": false, "depends_on": ["B"]},
  {"id": "B", "priority": 2, "passes": false, "depends_on": ["A"]}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Circular"* ]]
}

@test "splitter_validate_deps fails on transitive cycle" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "A", "priority": 1, "passes": false, "depends_on": ["C"]},
  {"id": "B", "priority": 2, "passes": false, "depends_on": ["A"]},
  {"id": "C", "priority": 3, "passes": false, "depends_on": ["B"]}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Circular"* ]]
}

@test "splitter_validate_deps passes with no depends_on fields" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false}
]
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
}

@test "splitter_validate_deps works with userStories format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001.1", "priority": 1, "passes": false, "depends_on": []},
    {"id": "US-001.2", "priority": 2, "passes": false, "depends_on": ["US-001.1"]}
  ]
}
EOF
  run splitter_validate_deps "${WORKSPACE_ROOT}/Input/prd.json"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# splitter_run (requires mocked claude_invoke)
# ---------------------------------------------------------------------------

@test "splitter_run returns 1 when prd.json is missing" {
  run splitter_run "${WORKSPACE_ROOT}"
  [ "$status" -ne 0 ]
}

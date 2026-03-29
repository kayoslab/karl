#!/usr/bin/env bats
# tests/splitter.bats - Tests for lib/splitter.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SPLITTER_SH="${KARL_DIR}/lib/splitter.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  STUB_DIR="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  # shellcheck source=../lib/subagent.sh
  source "${KARL_DIR}/lib/subagent.sh"
  # shellcheck source=../lib/splitter.sh
  source "${SPLITTER_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
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
# splitter_run (requires claude CLI stub)
# ---------------------------------------------------------------------------

@test "splitter_run returns 1 when prd.json is missing" {
  run splitter_run "${WORKSPACE_ROOT}"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# splitter_analyze_deps — dependency updates preserve all tickets
# ---------------------------------------------------------------------------

@test "splitter_analyze_deps preserves all tickets when adding dependencies" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false},
  {"id": "US-003", "priority": 3, "passes": false}
]
EOF

  # Mock subagent_invoke_json to return dependency updates for US-003 only
  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-003", "add_depends_on": ["US-001"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  # ALL three tickets must still exist
  local count
  count=$(jq 'length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 3 ]

  local ids
  ids=$(jq -r '.[].id' "${WORKSPACE_ROOT}/Input/prd.json" | sort | tr '\n' ',')
  [ "${ids}" = "US-001,US-002,US-003," ]
}

@test "splitter_analyze_deps preserves tickets with no matching update" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false}
]
EOF

  # Update only US-002 — US-001 must survive
  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-002", "add_depends_on": ["US-001"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  local count
  count=$(jq 'length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 2 ]

  # US-001 still exists and has no depends_on
  local us1_deps
  us1_deps=$(jq -r '.[] | select(.id == "US-001") | .depends_on // [] | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${us1_deps}" -eq 0 ]
}

@test "splitter_analyze_deps adds dependencies correctly" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false, "depends_on": []}
]
EOF

  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-002", "add_depends_on": ["US-001"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  local deps
  deps=$(jq -r '.[] | select(.id == "US-002") | .depends_on[0]' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${deps}" = "US-001" ]
}

@test "splitter_analyze_deps strips hallucinated non-existent IDs" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false}
]
EOF

  # Agent hallucinates a dependency on non-existent US-999
  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-002", "add_depends_on": ["US-999"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  # US-999 should be stripped
  local dep_count
  dep_count=$(jq '.[] | select(.id == "US-002") | .depends_on | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${dep_count}" -eq 0 ]
}

@test "splitter_analyze_deps handles empty dependency_updates" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false}
]
EOF

  subagent_invoke_json() {
    printf '{"dependency_updates": []}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  local count
  count=$(jq 'length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 2 ]
}

@test "splitter_analyze_deps preserves existing depends_on when adding new ones" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false},
  {"id": "US-003", "priority": 3, "passes": false, "depends_on": ["US-001"]}
]
EOF

  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-003", "add_depends_on": ["US-002"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  local deps
  deps=$(jq -r '.[] | select(.id == "US-003") | .depends_on | sort | join(",")' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${deps}" = "US-001,US-002" ]
}

@test "splitter_analyze_deps works with userStories format" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
{
  "userStories": [
    {"id": "US-001", "priority": 1, "passes": false},
    {"id": "US-002", "priority": 2, "passes": false}
  ]
}
EOF

  subagent_invoke_json() {
    printf '{"dependency_updates": [{"id": "US-002", "add_depends_on": ["US-001"]}]}'
  }

  splitter_analyze_deps "${WORKSPACE_ROOT}"

  local count
  count=$(jq '.userStories | length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 2 ]

  local deps
  deps=$(jq -r '.userStories[] | select(.id == "US-002") | .depends_on[0]' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${deps}" = "US-001" ]
}

@test "splitter_analyze_deps succeeds when agent fails (non-fatal)" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false}
]
EOF

  subagent_invoke_json() { return 1; }

  # Should still succeed (agent failure is non-fatal, validation still runs)
  run splitter_analyze_deps "${WORKSPACE_ROOT}"
  [ "$status" -eq 0 ]

  # Ticket must still exist
  local count
  count=$(jq 'length' "${WORKSPACE_ROOT}/Input/prd.json")
  [ "${count}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# splitter_apply_decisions — split must preserve non-split tickets
# ---------------------------------------------------------------------------

@test "splitter_apply_decisions preserves all non-split tickets" {
  make_prd "${WORKSPACE_ROOT}/Input/prd.json" <<'EOF'
[
  {"id": "US-001", "priority": 1, "passes": false},
  {"id": "US-002", "priority": 2, "passes": false},
  {"id": "US-003", "priority": 3, "passes": false}
]
EOF

  # Only split US-002, keep US-001 and US-003
  local decisions='{"split_decisions":[{"parent_id":"US-002","action":"split","reason":"test","sub_tickets":[{"id":"US-002.1","title":"Part A","priority":2,"passes":false,"status":"available","depends_on":[],"split_from":"US-002"}]},{"parent_id":"US-001","action":"keep","reason":"simple"},{"parent_id":"US-003","action":"keep","reason":"simple"}]}'

  splitter_apply_decisions "${WORKSPACE_ROOT}/Input/prd.json" "${decisions}"

  # US-001 and US-003 must survive, US-002 replaced by US-002.1
  local ids
  ids=$(jq -r '.[].id' "${WORKSPACE_ROOT}/Input/prd.json" | sort | tr '\n' ',')
  [[ "${ids}" == *"US-001"* ]]
  [[ "${ids}" == *"US-002.1"* ]]
  [[ "${ids}" == *"US-003"* ]]
  [[ "${ids}" != *"US-002,"* ]]
}

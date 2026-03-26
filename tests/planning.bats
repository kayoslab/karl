#!/usr/bin/env bats
# tests/planning.bats - Tests for lib/planning.sh (US-009)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
PLANNING_SH="${KARL_DIR}/lib/planning.sh"
AGENTS_SH="${KARL_DIR}/lib/agents.sh"
RATE_LIMIT_SH="${KARL_DIR}/lib/rate_limit.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  AGENTS_DIR="${WORKSPACE_ROOT}/Agents"
  STUB_DIR="$(mktemp -d)"
  mkdir -p "${AGENTS_DIR}"
  mkdir -p "${WORKSPACE_ROOT}/Output"
  export KARL_RATE_LIMIT_BACKOFF_BASE=0

  # shellcheck source=../lib/agents.sh
  source "${AGENTS_SH}"
  # shellcheck source=../lib/rate_limit.sh
  source "${RATE_LIMIT_SH}"
  # shellcheck source=../lib/planning.sh
  source "${PLANNING_SH}"

  # Minimal planner agent file (role must be 'planner')
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket, tech
outputs: plan, testing_recommendations, estimated_complexity, risks
constraints: Output must be valid JSON; All output fields are required
---

## Ticket

{{ticket}}

## Tech

{{tech}}
EOF

  # Minimal reviewer agent file (role must be 'reviewer')
  cat > "${AGENTS_DIR}/reviewer.md" <<'EOF'
---
role: reviewer
inputs: ticket, plan
outputs: approved, concerns, revised_plan
constraints: Output must be valid JSON; approved must be true or false
---

## Ticket

{{ticket}}

## Plan

{{plan}}
EOF

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  # Tests write to "${STUB_DIR}/.output" and "${STUB_DIR}/.exit" before calling run.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  # Default: valid approved plan JSON
  printf '%s' '{}' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

VALID_PLAN_JSON='{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
APPROVED_REVIEW_JSON='{"approved":true,"concerns":[],"revised_plan":null}'
REJECTED_REVIEW_JSON='{"approved":false,"concerns":["Missing error handling"],"revised_plan":null}'

# ---------------------------------------------------------------------------
# planning_run_agent — role name verification
# ---------------------------------------------------------------------------

@test "planning_run_agent succeeds when planner.md exists (uses role 'planner')" {
  printf '%s' "${VALID_PLAN_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"plan"'* ]]
}

@test "planning_run_agent fails when only planning.md exists instead of planner.md" {
  mv "${AGENTS_DIR}/planner.md" "${AGENTS_DIR}/planning.md"
  printf '%s' "${VALID_PLAN_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# planning_run_agent — response validation
# ---------------------------------------------------------------------------

@test "planning_run_agent returns plan JSON on success" {
  printf '%s' "${VALID_PLAN_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -eq 0 ]
  result=$(printf '%s' "${output}" | jq -r '.plan[0]')
  [ "${result}" = "Step 1" ]
}

@test "planning_run_agent fails when claude returns invalid JSON" {
  printf '%s' 'not-valid-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "planning_run_agent fails when plan field is missing from response" {
  printf '%s' '{"testing_recommendations":["t1"],"estimated_complexity":"low","risks":[]}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"plan"* ]]
}

@test "planning_run_agent fails when testing_recommendations field is missing from response" {
  printf '%s' '{"plan":["Step 1"],"estimated_complexity":"low","risks":[]}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"testing_recommendations"* ]]
}

@test "planning_run_agent fails when claude exits non-zero" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run planning_run_agent "${AGENTS_DIR}" '{"id":"US-009"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# planning_review_plan — role name verification
# ---------------------------------------------------------------------------

@test "planning_review_plan succeeds when reviewer.md exists (uses role 'reviewer')" {
  printf '%s' "${APPROVED_REVIEW_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_review_plan "${AGENTS_DIR}" '{"id":"US-009"}' "${VALID_PLAN_JSON}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"approved"'* ]]
}

@test "planning_review_plan fails when only reviewing.md exists instead of reviewer.md" {
  mv "${AGENTS_DIR}/reviewer.md" "${AGENTS_DIR}/reviewing.md"
  printf '%s' "${APPROVED_REVIEW_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_review_plan "${AGENTS_DIR}" '{"id":"US-009"}' "${VALID_PLAN_JSON}"
  [ "${status}" -ne 0 ]
}

@test "planning_review_plan returns review JSON on success" {
  printf '%s' "${APPROVED_REVIEW_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_review_plan "${AGENTS_DIR}" '{"id":"US-009"}' "${VALID_PLAN_JSON}"
  [ "${status}" -eq 0 ]
  approved=$(printf '%s' "${output}" | jq -r '.approved')
  [ "${approved}" = "true" ]
}

@test "planning_review_plan fails when claude returns invalid JSON" {
  printf '%s' 'not-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run planning_review_plan "${AGENTS_DIR}" '{"id":"US-009"}' "${VALID_PLAN_JSON}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# planning_persist
# ---------------------------------------------------------------------------

@test "planning_persist writes plan.json to Output/<story_id>/" {
  run planning_persist "${WORKSPACE_ROOT}" "US-009" "${VALID_PLAN_JSON}"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/US-009/plan.json" ]
}

@test "planning_persist creates Output/<story_id> directory if absent" {
  run planning_persist "${WORKSPACE_ROOT}" "US-099" "${VALID_PLAN_JSON}"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Output/US-099" ]
}

@test "planning_persist plan.json contains testing_recommendations field" {
  planning_persist "${WORKSPACE_ROOT}" "US-009" "${VALID_PLAN_JSON}"
  result=$(jq -r '.testing_recommendations[0]' "${WORKSPACE_ROOT}/Output/US-009/plan.json")
  [ "${result}" = "Test 1" ]
}

# ---------------------------------------------------------------------------
# planning_run_loop — happy path
# ---------------------------------------------------------------------------

@test "planning_run_loop returns 0 when plan is approved on first review" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
  }
  planning_commit() { return 0; }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"approved"* ]]
}

@test "planning_run_loop persists plan.json to Output/US-009/plan.json" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
  }
  planning_commit() { return 0; }

  planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  [ -f "${WORKSPACE_ROOT}/Output/US-009/plan.json" ]
}

@test "planning_run_loop persisted plan.json contains testing_recommendations" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
  }
  planning_commit() { return 0; }

  planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  result=$(jq -r '.testing_recommendations[0]' "${WORKSPACE_ROOT}/Output/US-009/plan.json")
  [ "${result}" = "Test 1" ]
}

# ---------------------------------------------------------------------------
# planning_run_loop — revision cycle
# ---------------------------------------------------------------------------

@test "planning_run_loop succeeds when second review approves after first rejects" {
  # Use a counter file: planning_review_plan runs in subshell (command substitution),
  # so variable increments don't survive back — file-based counter persists across subshells.
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    local count
    count=$(cat "${counter_file}")
    count=$((count + 1))
    printf '%d' "${count}" > "${counter_file}"
    if [[ "${count}" -eq 1 ]]; then
      printf '%s\n' '{"approved":false,"concerns":["Missing error handling"],"revised_plan":null}'
    else
      printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
    fi
  }
  planning_commit() { return 0; }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  rm -f "${counter_file}"
  [ "${status}" -eq 0 ]
}

@test "planning_run_loop prints revision message when review is not approved" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    local count
    count=$(cat "${counter_file}")
    count=$((count + 1))
    printf '%d' "${count}" > "${counter_file}"
    if [[ "${count}" -eq 1 ]]; then
      printf '%s\n' '{"approved":false,"concerns":["Missing error handling"],"revised_plan":null}'
    else
      printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
    fi
  }
  planning_commit() { return 0; }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  rm -f "${counter_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"revision"* ]]
}

# ---------------------------------------------------------------------------
# planning_run_loop — error paths
# ---------------------------------------------------------------------------

@test "planning_run_loop returns non-zero and prints ERROR when max retries exceeded" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":false,"concerns":["Still not good"],"revised_plan":null}'
  }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "2"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "planning_run_loop returns non-zero when planning agent fails" {
  planning_run_agent() {
    echo "ERROR: Planner agent failed" >&2
    return 1
  }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  [ "${status}" -ne 0 ]
}

@test "planning_run_loop returns non-zero when reviewer agent fails" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    echo "ERROR: Reviewer agent failed" >&2
    return 1
  }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  [ "${status}" -ne 0 ]
}

@test "planning_run_loop does not persist plan.json when all reviews reject" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":false,"concerns":["Needs work"],"revised_plan":null}'
  }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "2"
  [ "${status}" -ne 0 ]
  [ ! -f "${WORKSPACE_ROOT}/Output/US-009/plan.json" ]
}

# ---------------------------------------------------------------------------
# planning_persist_review
# ---------------------------------------------------------------------------

@test "planning_persist_review writes review.json to Output/<story_id>/" {
  run planning_persist_review "${WORKSPACE_ROOT}" "US-009" "${APPROVED_REVIEW_JSON}"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/US-009/review.json" ]
}

@test "planning_persist_review creates Output/<story_id> directory if absent" {
  run planning_persist_review "${WORKSPACE_ROOT}" "US-099" "${APPROVED_REVIEW_JSON}"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Output/US-099" ]
}

@test "planning_persist_review written file contains expected review content" {
  planning_persist_review "${WORKSPACE_ROOT}" "US-009" "${APPROVED_REVIEW_JSON}"
  approved=$(jq -r '.approved' "${WORKSPACE_ROOT}/Output/US-009/review.json")
  [ "${approved}" = "true" ]
}

@test "planning_persist_review does not overwrite unrelated ticket artifacts" {
  mkdir -p "${WORKSPACE_ROOT}/Output/US-001"
  printf '{"approved":false}' > "${WORKSPACE_ROOT}/Output/US-001/review.json"

  planning_persist_review "${WORKSPACE_ROOT}" "US-009" "${APPROVED_REVIEW_JSON}"

  us001_content=$(cat "${WORKSPACE_ROOT}/Output/US-001/review.json")
  [[ "${us001_content}" == *'"approved":false'* ]]
}

# ---------------------------------------------------------------------------
# planning_run_loop — review.json persistence
# ---------------------------------------------------------------------------

@test "planning_run_loop persists review.json to Output/US-009/review.json on approve" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
  }
  planning_commit() { return 0; }

  planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  [ -f "${WORKSPACE_ROOT}/Output/US-009/review.json" ]
}

@test "planning_run_loop review.json contains approved=true after approval" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":true,"concerns":[],"revised_plan":null}'
  }
  planning_commit() { return 0; }

  planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "3"
  approved=$(jq -r '.approved' "${WORKSPACE_ROOT}/Output/US-009/review.json")
  [ "${approved}" = "true" ]
}

@test "planning_run_loop does not persist review.json when all reviews reject" {
  planning_run_agent() {
    printf '%s\n' '{"plan":["Step 1"],"testing_recommendations":["Test 1"],"estimated_complexity":"low","risks":[]}'
  }
  planning_review_plan() {
    printf '%s\n' '{"approved":false,"concerns":["Needs work"],"revised_plan":null}'
  }

  run planning_run_loop "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-009"}' "" "2"
  [ "${status}" -ne 0 ]
  [ ! -f "${WORKSPACE_ROOT}/Output/US-009/review.json" ]
}

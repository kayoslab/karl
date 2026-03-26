#!/usr/bin/env bats
# tests/summarize.bats - Tests for lib/summarize.sh (US-018)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
SUMMARIZE_SH="${KARL_DIR}/lib/summarize.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  OUTPUT_DIR="${WORKSPACE_ROOT}/Output"
  mkdir -p "${OUTPUT_DIR}"
  # shellcheck source=../lib/summarize.sh
  source "${SUMMARIZE_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

PLAN_JSON='{"plan":["Step 1","Step 2"],"testing_recommendations":["Test auth","Test edge cases"],"estimated_complexity":"low","risks":["None"]}'
REVIEW_JSON='{"approved":true,"concerns":["Looks good","Minor nit"],"revised_plan":null}'
TESTS_JSON='{"passed":true,"failures":[],"summary":"All 10 tests pass","test_count":10}'
ARCHITECT_JSON='{"approved":true,"decision":"Use existing patterns","notes":"No structural changes","adr_required":false,"adr_entry":null}'
ARCHITECT_JSON_WITH_IMPL='{"approved":true,"decision":"Introduce new module","implementation_notes":"Add lib/foo.sh","adr_required":true,"adr_entry":"# ADR-001"}'
FAILING_TESTS_JSON='{"passed":false,"failures":["test_foo: assertion failed","test_bar: command not found"],"summary":"2 of 10 tests failed","test_count":10}'

# ---------------------------------------------------------------------------
# summarize_plan
# ---------------------------------------------------------------------------

@test "summarize_plan returns valid JSON" {
  run summarize_plan "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq empty
}

@test "summarize_plan includes summary_type=plan" {
  run summarize_plan "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "plan" ]
}

@test "summarize_plan includes source_file field" {
  run summarize_plan "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  source_file=$(printf '%s' "${output}" | jq -r '.source_file')
  [ "${source_file}" = "Output/US-018/plan.json" ]
}

@test "summarize_plan includes estimated_complexity field" {
  run summarize_plan "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"estimated_complexity"'* ]]
}

@test "summarize_plan includes step_count reflecting number of plan steps" {
  run summarize_plan "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  step_count=$(printf '%s' "${output}" | jq -r '.step_count')
  [ "${step_count}" -eq 2 ]
}

# ---------------------------------------------------------------------------
# summarize_review
# ---------------------------------------------------------------------------

@test "summarize_review returns valid JSON" {
  run summarize_review "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq empty
}

@test "summarize_review includes summary_type=review" {
  run summarize_review "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "review" ]
}

@test "summarize_review includes source_file field" {
  run summarize_review "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  source_file=$(printf '%s' "${output}" | jq -r '.source_file')
  [ "${source_file}" = "Output/US-018/review.json" ]
}

@test "summarize_review includes approved field" {
  run summarize_review "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  approved=$(printf '%s' "${output}" | jq -r '.approved')
  [ "${approved}" = "true" ]
}

@test "summarize_review includes feedback_count field" {
  run summarize_review "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  feedback_count=$(printf '%s' "${output}" | jq -r '.feedback_count')
  [ "${feedback_count}" -eq 2 ]
}

@test "summarize_review feedback_count is 0 for empty concerns" {
  review='{"approved":true,"concerns":[],"revised_plan":null}'
  run summarize_review "${review}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  feedback_count=$(printf '%s' "${output}" | jq -r '.feedback_count')
  [ "${feedback_count}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# summarize_tests
# ---------------------------------------------------------------------------

@test "summarize_tests returns valid JSON" {
  run summarize_tests "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq empty
}

@test "summarize_tests includes summary_type=tests" {
  run summarize_tests "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "tests" ]
}

@test "summarize_tests includes source_file field" {
  run summarize_tests "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  source_file=$(printf '%s' "${output}" | jq -r '.source_file')
  [ "${source_file}" = "Output/US-018/tests.json" ]
}

@test "summarize_tests includes passed field" {
  run summarize_tests "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  passed=$(printf '%s' "${output}" | jq -r '.passed')
  [ "${passed}" = "true" ]
}

@test "summarize_tests includes failure_count=0 when all tests pass" {
  run summarize_tests "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  failure_count=$(printf '%s' "${output}" | jq -r '.failure_count')
  [ "${failure_count}" -eq 0 ]
}

@test "summarize_tests includes failure_count when tests fail" {
  run summarize_tests "${FAILING_TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  failure_count=$(printf '%s' "${output}" | jq -r '.failure_count')
  [ "${failure_count}" -eq 2 ]
}

@test "summarize_tests passed=false when tests fail" {
  run summarize_tests "${FAILING_TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  passed=$(printf '%s' "${output}" | jq -r '.passed')
  [ "${passed}" = "false" ]
}

# ---------------------------------------------------------------------------
# summarize_architect
# ---------------------------------------------------------------------------

@test "summarize_architect returns valid JSON" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq empty
}

@test "summarize_architect includes summary_type=architect" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "architect" ]
}

@test "summarize_architect includes source_file field" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  source_file=$(printf '%s' "${output}" | jq -r '.source_file')
  [ "${source_file}" = "Output/US-018/architect.json" ]
}

@test "summarize_architect includes decision field" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  decision=$(printf '%s' "${output}" | jq -r '.decision')
  [ "${decision}" = "Use existing patterns" ]
}

@test "summarize_architect includes adr_required field" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  adr_required=$(printf '%s' "${output}" | jq -r '.adr_required')
  [ "${adr_required}" = "false" ]
}

@test "summarize_architect adr_required=true when architect says so" {
  run summarize_architect "${ARCHITECT_JSON_WITH_IMPL}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  adr_required=$(printf '%s' "${output}" | jq -r '.adr_required')
  [ "${adr_required}" = "true" ]
}

@test "summarize_architect extracts notes field" {
  run summarize_architect "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"notes"'* ]] || [[ "${output}" == *'"implementation_notes"'* ]]
}

@test "summarize_architect extracts implementation_notes when notes field absent" {
  run summarize_architect "${ARCHITECT_JSON_WITH_IMPL}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  # Either notes or implementation_notes key must be present in summary
  printf '%s' "${output}" | jq -e '(.notes // .implementation_notes) != null' > /dev/null
}

# ---------------------------------------------------------------------------
# summarize_artifact — dispatcher
# ---------------------------------------------------------------------------

@test "summarize_artifact dispatches plan to summarize_plan" {
  run summarize_artifact "plan" "${PLAN_JSON}" "Output/US-018/plan.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "plan" ]
}

@test "summarize_artifact dispatches review to summarize_review" {
  run summarize_artifact "review" "${REVIEW_JSON}" "Output/US-018/review.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "review" ]
}

@test "summarize_artifact dispatches tests to summarize_tests" {
  run summarize_artifact "tests" "${TESTS_JSON}" "Output/US-018/tests.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "tests" ]
}

@test "summarize_artifact dispatches architect to summarize_architect" {
  run summarize_artifact "architect" "${ARCHITECT_JSON}" "Output/US-018/architect.json"
  [ "${status}" -eq 0 ]
  summary_type=$(printf '%s' "${output}" | jq -r '.summary_type')
  [ "${summary_type}" = "architect" ]
}

@test "summarize_artifact returns non-zero for unknown type" {
  run summarize_artifact "unknown_type" '{}' "Output/US-018/unknown.json"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# summarize_ticket_artifacts — file I/O
# ---------------------------------------------------------------------------

@test "summarize_ticket_artifacts returns 0 when no summarizable artifacts exist" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
}

@test "summarize_ticket_artifacts writes plan_summary.json when plan.json exists" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${PLAN_JSON}" > "${OUTPUT_DIR}/US-018/plan.json"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_DIR}/US-018/plan_summary.json" ]
}

@test "summarize_ticket_artifacts plan_summary.json contains valid JSON" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${PLAN_JSON}" > "${OUTPUT_DIR}/US-018/plan.json"
  summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  jq empty "${OUTPUT_DIR}/US-018/plan_summary.json"
}

@test "summarize_ticket_artifacts writes review_summary.json when review.json exists" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${REVIEW_JSON}" > "${OUTPUT_DIR}/US-018/review.json"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_DIR}/US-018/review_summary.json" ]
}

@test "summarize_ticket_artifacts review_summary.json contains valid JSON with summary_type=review" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${REVIEW_JSON}" > "${OUTPUT_DIR}/US-018/review.json"
  summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  summary_type=$(jq -r '.summary_type' "${OUTPUT_DIR}/US-018/review_summary.json")
  [ "${summary_type}" = "review" ]
}

@test "summarize_ticket_artifacts writes architect_summary.json when architect.json exists" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${ARCHITECT_JSON}" > "${OUTPUT_DIR}/US-018/architect.json"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_DIR}/US-018/architect_summary.json" ]
}

@test "summarize_ticket_artifacts architect_summary.json contains valid JSON with summary_type=architect" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${ARCHITECT_JSON}" > "${OUTPUT_DIR}/US-018/architect.json"
  summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  summary_type=$(jq -r '.summary_type' "${OUTPUT_DIR}/US-018/architect_summary.json")
  [ "${summary_type}" = "architect" ]
}

@test "summarize_ticket_artifacts writes tests_summary.json when tests.json exists" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${TESTS_JSON}" > "${OUTPUT_DIR}/US-018/tests.json"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_DIR}/US-018/tests_summary.json" ]
}

@test "summarize_ticket_artifacts writes all four summaries when all artifacts present" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${PLAN_JSON}"      > "${OUTPUT_DIR}/US-018/plan.json"
  printf '%s\n' "${REVIEW_JSON}"    > "${OUTPUT_DIR}/US-018/review.json"
  printf '%s\n' "${ARCHITECT_JSON}" > "${OUTPUT_DIR}/US-018/architect.json"
  printf '%s\n' "${TESTS_JSON}"     > "${OUTPUT_DIR}/US-018/tests.json"
  run summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  [ "${status}" -eq 0 ]
  [ -f "${OUTPUT_DIR}/US-018/plan_summary.json" ]
  [ -f "${OUTPUT_DIR}/US-018/review_summary.json" ]
  [ -f "${OUTPUT_DIR}/US-018/architect_summary.json" ]
  [ -f "${OUTPUT_DIR}/US-018/tests_summary.json" ]
}

@test "summarize_ticket_artifacts does not affect other ticket directories" {
  mkdir -p "${OUTPUT_DIR}/US-001"
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${PLAN_JSON}" > "${OUTPUT_DIR}/US-001/plan.json"
  printf '%s\n' "${PLAN_JSON}" > "${OUTPUT_DIR}/US-018/plan.json"

  summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"

  # US-001 should not have a summary written
  [ ! -f "${OUTPUT_DIR}/US-001/plan_summary.json" ]
}

@test "summarize_ticket_artifacts summary retains source_file reference to original artifact" {
  mkdir -p "${OUTPUT_DIR}/US-018"
  printf '%s\n' "${PLAN_JSON}" > "${OUTPUT_DIR}/US-018/plan.json"
  summarize_ticket_artifacts "${WORKSPACE_ROOT}" "US-018"
  source_file=$(jq -r '.source_file' "${OUTPUT_DIR}/US-018/plan_summary.json")
  [[ "${source_file}" == *"plan.json"* ]]
}

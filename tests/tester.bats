#!/usr/bin/env bats
# tests/tester.bats - Tests for lib/tester.sh (US-011)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TESTER_SH="${KARL_DIR}/lib/tester.sh"
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
  # shellcheck source=../lib/tester.sh
  source "${TESTER_SH}"

  # Minimal tester agent file (role must be 'tester')
  cat > "${AGENTS_DIR}/tester.md" <<'EOF'
---
role: tester
inputs: ticket, plan, tech
outputs: tests_added, tests_modified, test_results, failures, failure_source
constraints: Output must be valid JSON; test_results must be pass or fail
---

## Ticket

{{ticket}}

## Plan

{{plan}}

## Tech

{{tech}}
EOF

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  # Default: valid passing response with no tests added
  printf '%s' '{"tests_added":[],"tests_modified":[],"test_results":"pass","failures":[],"failure_source":null}' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

VALID_TESTER_JSON='{"tests_added":["tests/foo.bats"],"tests_modified":[],"test_results":"pass","failures":[],"failure_source":null}'
PASS_NO_NEW_JSON='{"tests_added":[],"tests_modified":[],"test_results":"pass","failures":[],"failure_source":null}'
FAIL_JSON='{"tests_added":[],"tests_modified":[],"test_results":"fail","failures":["foo_test: expected 0 got 1"],"failure_source":"implementation"}'

# ---------------------------------------------------------------------------
# tester_run_agent — role name verification
# ---------------------------------------------------------------------------

@test "tester_run_agent succeeds when tester.md exists (uses role 'tester')" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"tests_added"'* ]]
}

@test "tester_run_agent fails when tester.md is absent" {
  rm "${AGENTS_DIR}/tester.md"
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# tester_run_agent — response validation
# ---------------------------------------------------------------------------

@test "tester_run_agent returns tester JSON on success" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
  result=$(printf '%s' "${output}" | jq -r '.tests_added[0]')
  [ "${result}" = "tests/foo.bats" ]
}

@test "tester_run_agent fails when claude returns invalid JSON" {
  printf '%s' 'not-valid-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "tester_run_agent fails when tests_added field is missing from response" {
  printf '%s' '{"tests_modified":[],"test_results":"pass","failures":[],"failure_source":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"tests_added"* ]]
}

@test "tester_run_agent fails when test_results field is missing from response" {
  printf '%s' '{"tests_added":[],"tests_modified":[],"failures":[],"failure_source":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"test_results"* ]]
}

@test "tester_run_agent fails when claude exits non-zero" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tester_run_agent "${AGENTS_DIR}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# tester_read_existing
# ---------------------------------------------------------------------------

@test "tester_read_existing returns empty string when tests.json does not exist" {
  run tester_read_existing "${WORKSPACE_ROOT}" "US-011"
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "tester_read_existing returns content of Output/<story_id>/tests.json" {
  mkdir -p "${WORKSPACE_ROOT}/Output/US-011"
  printf '%s' "${VALID_TESTER_JSON}" > "${WORKSPACE_ROOT}/Output/US-011/tests.json"
  run tester_read_existing "${WORKSPACE_ROOT}" "US-011"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"tests_added"'* ]]
}

@test "tester_read_existing returns valid JSON content" {
  mkdir -p "${WORKSPACE_ROOT}/Output/US-011"
  printf '%s' "${VALID_TESTER_JSON}" > "${WORKSPACE_ROOT}/Output/US-011/tests.json"
  tester_read_existing "${WORKSPACE_ROOT}" "US-011" | jq . > /dev/null
}

# ---------------------------------------------------------------------------
# tester_generate — happy path: tests added
# ---------------------------------------------------------------------------

@test "tester_generate returns 0 when agent succeeds" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

@test "tester_generate persists tests.json to Output/<story_id>/" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ -f "${WORKSPACE_ROOT}/Output/US-011/tests.json" ]
}

@test "tester_generate creates Output/<story_id> directory if absent" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-099"}' '{"plan":"step 1"}' ""
  [ -d "${WORKSPACE_ROOT}/Output/US-099" ]
}

@test "tester_generate persisted tests.json contains tests_added field" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  result=$(jq -r '.tests_added[0]' "${WORKSPACE_ROOT}/Output/US-011/tests.json")
  [ "${result}" = "tests/foo.bats" ]
}

@test "tester_generate persisted tests.json contains test_results field" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  result=$(jq -r '.test_results' "${WORKSPACE_ROOT}/Output/US-011/tests.json")
  [ "${result}" = "pass" ]
}

@test "tester_generate prints message including story id" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"US-011"* ]]
}

# ---------------------------------------------------------------------------
# tester_generate — happy path: no new tests
# ---------------------------------------------------------------------------

@test "tester_generate returns 0 when no tests are added or modified" {
  printf '%s' "${PASS_NO_NEW_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

@test "tester_generate still persists tests.json when no tests are added" {
  printf '%s' "${PASS_NO_NEW_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ -f "${WORKSPACE_ROOT}/Output/US-011/tests.json" ]
}

# ---------------------------------------------------------------------------
# tester_generate — failing tests
# ---------------------------------------------------------------------------

@test "tester_generate returns 0 even when test_results is fail (records the state)" {
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
  result=$(jq -r '.test_results' "${WORKSPACE_ROOT}/Output/US-011/tests.json")
  [ "${result}" = "fail" ]
}

# ---------------------------------------------------------------------------
# tester_generate — error conditions
# ---------------------------------------------------------------------------

@test "tester_generate returns non-zero when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

@test "tester_generate prints ERROR when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "tester_generate does not write tests.json when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ ! -f "${WORKSPACE_ROOT}/Output/US-011/tests.json" ]
}

@test "tester_generate returns non-zero when agent returns invalid JSON" {
  printf '%s' 'not-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# tester_generate — commit behaviour
# ---------------------------------------------------------------------------

@test "tester_generate commits tests.json when tests are added" {
  git -C "${WORKSPACE_ROOT}" init -q
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com"
  git -C "${WORKSPACE_ROOT}" config user.name "Test"

  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""

  result=$(git -C "${WORKSPACE_ROOT}" log --oneline)
  [[ "${result}" == *"US-011"* ]]
}

@test "tester_generate does not fail when git is not initialized" {
  printf '%s' "${VALID_TESTER_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tester_generate "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-011"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Real tester agent file contract validation
# ---------------------------------------------------------------------------

@test "real tester agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/tester.md"
  [ "${status}" -eq 0 ]
}

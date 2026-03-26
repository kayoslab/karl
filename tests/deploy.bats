#!/usr/bin/env bats
# tests/deploy.bats - Tests for lib/deploy.sh (US-015)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
DEPLOY_SH="${KARL_DIR}/lib/deploy.sh"
AGENTS_SH="${KARL_DIR}/lib/agents.sh"
RATE_LIMIT_SH="${KARL_DIR}/lib/rate_limit.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  AGENTS_DIR="${WORKSPACE_ROOT}/Agents"
  STUB_DIR="$(mktemp -d)"
  TICKET_ID="US-015"
  mkdir -p "${AGENTS_DIR}"
  mkdir -p "${WORKSPACE_ROOT}/Output/${TICKET_ID}"
  export KARL_RATE_LIMIT_BACKOFF_BASE=0

  # shellcheck source=../lib/agents.sh
  source "${AGENTS_SH}"
  # shellcheck source=../lib/rate_limit.sh
  source "${RATE_LIMIT_SH}"
  # shellcheck source=../lib/deploy.sh
  source "${DEPLOY_SH}"

  # Minimal deployment agent file
  cat > "${AGENTS_DIR}/deployment.md" <<'EOF'
---
role: deployment
inputs: ticket, plan, tech, tests
outputs: decision, gates_checked, failures, notes
constraints: Output must be valid JSON; decision must be pass or fail; gates_checked must include tests and typecheck
---

## Ticket

{{ticket}}

## Plan

{{plan}}

## Tech

{{tech}}

## Tests

{{tests}}
EOF

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  # Default: valid passing response
  printf '%s' '{"decision":"pass","gates_checked":["tests","typecheck"],"failures":[],"notes":"All gates passed"}' \
    > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

PASS_JSON='{"decision":"pass","gates_checked":["tests","typecheck"],"failures":[],"notes":"All gates passed"}'
FAIL_JSON='{"decision":"fail","gates_checked":["tests","typecheck"],"failures":["typecheck failed: 3 errors"],"notes":"Gate failure"}'

_init_repo() {
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" checkout -b "feature/${TICKET_ID}-impl" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# deploy_run_agent — basic invocation
# ---------------------------------------------------------------------------

@test "deploy_run_agent succeeds when deployment.md exists" {
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"decision"'* ]]
}

@test "deploy_run_agent fails when deployment.md is absent" {
  rm "${AGENTS_DIR}/deployment.md"
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -ne 0 ]
}

@test "deploy_run_agent returns JSON with decision field on success" {
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -eq 0 ]
  result=$(printf '%s' "${output}" | jq -r '.decision')
  [ "${result}" = "pass" ]
}

@test "deploy_run_agent returns JSON with gates_checked field on success" {
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -eq 0 ]
  result=$(printf '%s' "${output}" | jq -r '.gates_checked | length')
  [ "${result}" -gt 0 ]
}

@test "deploy_run_agent fails when claude returns invalid JSON" {
  printf '%s' 'not-valid-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "deploy_run_agent fails when decision field is missing from response" {
  printf '%s' '{"gates_checked":["tests","typecheck"],"failures":[],"notes":""}' \
    > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"decision"* ]]
}

@test "deploy_run_agent fails when gates_checked field is missing from response" {
  printf '%s' '{"decision":"pass","failures":[],"notes":""}' \
    > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"gates_checked"* ]]
}

@test "deploy_run_agent fails when claude exits non-zero" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# deploy_run_agent — tests context is passed to agent
# ---------------------------------------------------------------------------

@test "deploy_run_agent accepts tests_json argument without error" {
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_run_agent \
    "${AGENTS_DIR}" '{"id":"US-015"}' '{"plan":"step 1"}' "" \
    '{"tests_added":["tests/deploy.bats"],"test_results":"pass"}'
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# deploy_persist
# ---------------------------------------------------------------------------

@test "deploy_persist creates Output/<ticket_id>/deploy.json" {
  deploy_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" "${PASS_JSON}"
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json" ]
}

@test "deploy_persist writes valid JSON to deploy.json" {
  deploy_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" "${PASS_JSON}"
  jq . "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json" > /dev/null
}

@test "deploy_persist writes decision field to deploy.json" {
  deploy_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" "${PASS_JSON}"
  result=$(jq -r '.decision' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json")
  [ "${result}" = "pass" ]
}

@test "deploy_persist writes gates_checked field to deploy.json" {
  deploy_persist "${WORKSPACE_ROOT}" "${TICKET_ID}" "${PASS_JSON}"
  jq -e '.gates_checked' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json" > /dev/null
}

@test "deploy_persist creates Output/<ticket_id> directory if absent" {
  rm -rf "${WORKSPACE_ROOT}/Output/US-099"
  deploy_persist "${WORKSPACE_ROOT}" "US-099" "${PASS_JSON}"
  [ -f "${WORKSPACE_ROOT}/Output/US-099/deploy.json" ]
}

@test "deploy_persist requires workspace_root argument" {
  run deploy_persist
  [ "${status}" -ne 0 ]
}

@test "deploy_persist requires ticket_id argument" {
  run deploy_persist "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

@test "deploy_persist requires response_json argument" {
  run deploy_persist "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# deploy_gate — happy path (decision=pass)
# ---------------------------------------------------------------------------

@test "deploy_gate returns 0 when decision is pass" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

@test "deploy_gate creates deploy.json when decision is pass" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json" ]
}

@test "deploy_gate creates a git commit when decision is pass" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  log=$(git -C "${WORKSPACE_ROOT}" log --oneline)
  [[ "${log}" == *"${TICKET_ID}"* ]]
}

@test "deploy_gate commit message references deployment gate" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  log=$(git -C "${WORKSPACE_ROOT}" log --oneline)
  [[ "${log}" == *"deploy"* ]] || [[ "${log}" == *"gate"* ]]
}

@test "deploy_gate includes deploy.json in git commit when decision is pass" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  tracked=$(git -C "${WORKSPACE_ROOT}" show --name-only HEAD)
  [[ "${tracked}" == *"deploy.json"* ]]
}

@test "deploy_gate prints message including ticket id" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [[ "${output}" == *"US-015"* ]]
}

# ---------------------------------------------------------------------------
# deploy_gate — fail path (decision=fail)
# ---------------------------------------------------------------------------

@test "deploy_gate returns 1 when decision is fail" {
  _init_repo
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 1 ]
}

@test "deploy_gate logs failure reason when decision is fail" {
  _init_repo
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"typecheck failed"* ]]
}

@test "deploy_gate does not create a git commit when decision is fail" {
  _init_repo
  local commit_before
  commit_before=$(git -C "${WORKSPACE_ROOT}" rev-parse HEAD)
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' "" || true
  local commit_after
  commit_after=$(git -C "${WORKSPACE_ROOT}" rev-parse HEAD)
  [ "${commit_before}" = "${commit_after}" ]
}

@test "deploy_gate still persists deploy.json when decision is fail" {
  _init_repo
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' "" || true
  [ -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json" ]
}

@test "deploy_gate persisted deploy.json has decision=fail when gate fails" {
  _init_repo
  printf '%s' "${FAIL_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' "" || true
  result=$(jq -r '.decision' "${WORKSPACE_ROOT}/Output/${TICKET_ID}/deploy.json")
  [ "${result}" = "fail" ]
}

# ---------------------------------------------------------------------------
# deploy_gate — error conditions
# ---------------------------------------------------------------------------

@test "deploy_gate returns non-zero when agent returns invalid JSON" {
  _init_repo
  printf '%s' 'not-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

@test "deploy_gate returns non-zero when agent exits non-zero" {
  _init_repo
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

@test "deploy_gate returns non-zero when JSON is missing decision field" {
  _init_repo
  printf '%s' '{"gates_checked":["tests","typecheck"],"failures":[],"notes":""}' \
    > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -ne 0 ]
}

@test "deploy_gate requires agents_dir argument" {
  run deploy_gate
  [ "${status}" -ne 0 ]
}

@test "deploy_gate requires workspace_root argument" {
  run deploy_gate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
}

@test "deploy_gate requires ticket_json argument" {
  run deploy_gate "${AGENTS_DIR}" "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# deploy_gate — ADR context
# ---------------------------------------------------------------------------

@test "deploy_gate succeeds even when no ADR files exist" {
  _init_repo
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

@test "deploy_gate succeeds when ADR files exist in Output/ADR/" {
  _init_repo
  mkdir -p "${WORKSPACE_ROOT}/Output/ADR"
  echo "# ADR-001: Use bash" > "${WORKSPACE_ROOT}/Output/ADR/adr-001.md"
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# deploy_gate — tests.json context
# ---------------------------------------------------------------------------

@test "deploy_gate reads tests.json from Output/<ticket_id>/ when present" {
  _init_repo
  printf '%s' '{"tests_added":["tests/deploy.bats"],"test_results":"pass"}' \
    > "${WORKSPACE_ROOT}/Output/${TICKET_ID}/tests.json"
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

@test "deploy_gate succeeds when tests.json is absent from Output/<ticket_id>/" {
  _init_repo
  rm -f "${WORKSPACE_ROOT}/Output/${TICKET_ID}/tests.json"
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# deploy_gate — git not required for basic functionality
# ---------------------------------------------------------------------------

@test "deploy_gate does not fail if not a git repo (commit silently skipped)" {
  printf '%s' "${PASS_JSON}" > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run deploy_gate \
    "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-015"}' '{"plan":"step 1"}' ""
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Real deployment agent file contract validation
# ---------------------------------------------------------------------------

@test "real deployment agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/deployment.md"
  [ "${status}" -eq 0 ]
}

@test "real deployment agent has decision in outputs" {
  outputs=$(agents_get_contract_field "${KARL_DIR}/Agents/deployment.md" "outputs")
  [[ "${outputs}" == *"decision"* ]]
}

@test "real deployment agent has gates_checked in outputs" {
  outputs=$(agents_get_contract_field "${KARL_DIR}/Agents/deployment.md" "outputs")
  [[ "${outputs}" == *"gates_checked"* ]]
}

@test "real deployment agent constraints mention tests and typecheck" {
  constraints=$(agents_get_contract_field "${KARL_DIR}/Agents/deployment.md" "constraints")
  [[ "${constraints}" == *"tests"* ]] || [[ "${constraints}" == *"typecheck"* ]]
}

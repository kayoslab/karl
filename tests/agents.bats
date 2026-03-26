#!/usr/bin/env bats
# tests/agents.bats - Tests for lib/agents.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
AGENTS_SH="${KARL_DIR}/lib/agents.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  AGENTS_DIR="${WORKSPACE_ROOT}/Agents"
  mkdir -p "${AGENTS_DIR}"
  # shellcheck source=../lib/agents.sh
  source "${AGENTS_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

make_agent() {
  local role="${1}"
  local dir="${2:-${AGENTS_DIR}}"
  cat > "${dir}/${role}.md" <<EOF
---
role: ${role}
inputs: ticket, tech
outputs: result
constraints: Output must be valid JSON
---

# ${role} Agent

This is the ${role} agent prompt.

## Ticket

{{ticket}}

## Plan

{{plan}}

## ADR

{{adr}}

## Tech

{{tech}}

## Tests

{{tests}}
EOF
}

make_all_agents() {
  for role in planner reviewer architect tester developer deployment; do
    make_agent "${role}"
  done
}

# ---------------------------------------------------------------------------
# agents_validate
# ---------------------------------------------------------------------------

@test "agents_validate returns 0 when all required agents exist and are valid" {
  make_all_agents
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -eq 0 ]
}

@test "agents_validate fails when agents directory does not exist" {
  run agents_validate "${WORKSPACE_ROOT}/NoSuchDir"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "agents_validate fails when planner agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/planner.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"planner"* ]]
}

@test "agents_validate fails when reviewer agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/reviewer.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"reviewer"* ]]
}

@test "agents_validate fails when architect agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/architect.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"architect"* ]]
}

@test "agents_validate fails when tester agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/tester.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"tester"* ]]
}

@test "agents_validate fails when developer agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/developer.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"developer"* ]]
}

@test "agents_validate fails when deployment agent is missing" {
  make_all_agents
  rm "${AGENTS_DIR}/deployment.md"
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"deployment"* ]]
}

@test "agents_validate error lists all missing agents when directory is empty" {
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
  [[ "${output}" == *"planner"* ]]
  [[ "${output}" == *"tester"* ]]
  [[ "${output}" == *"developer"* ]]
}

@test "agents_validate fails when an agent file is missing contract fields" {
  make_all_agents
  # Overwrite planner.md without contract fields
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
---
# Planner Agent
Missing inputs, outputs, constraints fields.
EOF
  run agents_validate "${AGENTS_DIR}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# agents_load
# ---------------------------------------------------------------------------

@test "agents_load returns 0 and prints registry loaded message when all agents present" {
  make_all_agents
  run agents_load "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"[agents] Registry loaded from:"* ]]
  [[ "${output}" == *"Agents"* ]]
}

@test "agents_load fails when Agents directory is missing" {
  rmdir "${AGENTS_DIR}"
  run agents_load "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

@test "agents_load fails when agents directory is empty" {
  run agents_load "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# agents_get_contract_field
# ---------------------------------------------------------------------------

@test "agents_get_contract_field reads role from fenced frontmatter" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
# Body
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "role"
  [ "${status}" -eq 0 ]
  [ "${output}" = "planner" ]
}

@test "agents_get_contract_field reads inputs from fenced frontmatter" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket, tech
outputs: plan
constraints: Output must be valid JSON
---
# Body
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "inputs"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ticket, tech" ]
}

@test "agents_get_contract_field reads outputs from fenced frontmatter" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan, risks
constraints: Output must be valid JSON
---
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "outputs"
  [ "${status}" -eq 0 ]
  [ "${output}" = "plan, risks" ]
}

@test "agents_get_contract_field reads constraints from fenced frontmatter" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "constraints"
  [ "${status}" -eq 0 ]
  [ "${output}" = "Output must be valid JSON" ]
}

@test "agents_get_contract_field reads field from bare frontmatter" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON

# Body content starts here
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "role"
  [ "${status}" -eq 0 ]
  [ "${output}" = "planner" ]
}

@test "agents_get_contract_field returns 1 when field is absent" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
---
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "outputs"
  [ "${status}" -ne 0 ]
}

@test "agents_get_contract_field does not return prompt body content" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
# Body
role: body-value-should-not-be-returned
inputs: body-inputs
EOF
  run agents_get_contract_field "${AGENTS_DIR}/test.md" "role"
  [ "${status}" -eq 0 ]
  [ "${output}" = "planner" ]
}

# ---------------------------------------------------------------------------
# agents_validate_contract
# ---------------------------------------------------------------------------

@test "agents_validate_contract returns 0 when all required fields are present" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
# Body
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -eq 0 ]
}

@test "agents_validate_contract fails when role is missing" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"role"* ]]
}

@test "agents_validate_contract fails when inputs is missing" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
outputs: plan
constraints: Output must be valid JSON
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"inputs"* ]]
}

@test "agents_validate_contract fails when outputs is missing" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
constraints: Output must be valid JSON
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"outputs"* ]]
}

@test "agents_validate_contract fails when constraints is missing" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"constraints"* ]]
}

@test "agents_validate_contract error message includes filename" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/planner.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"planner.md"* ]]
}

@test "agents_validate_contract fails listing all missing fields" {
  cat > "${AGENTS_DIR}/test.md" <<'EOF'
---
role: planner
---
EOF
  run agents_validate_contract "${AGENTS_DIR}/test.md"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"inputs"* ]]
  [[ "${output}" == *"outputs"* ]]
  [[ "${output}" == *"constraints"* ]]
}

# ---------------------------------------------------------------------------
# agents_get_prompt
# ---------------------------------------------------------------------------

@test "agents_get_prompt returns body with fenced frontmatter stripped" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
# Planner Agent
This is the prompt body.
EOF
  run agents_get_prompt "${AGENTS_DIR}" "planner"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"# Planner Agent"* ]]
  [[ "${output}" == *"This is the prompt body."* ]]
  [[ "${output}" != *"role: planner"* ]]
  [[ "${output}" != *"---"* ]]
}

@test "agents_get_prompt fails when agent file does not exist" {
  run agents_get_prompt "${AGENTS_DIR}" "nonexistent"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "agents_get_prompt returns body for each of the six required roles" {
  make_all_agents
  for role in planner reviewer architect tester developer deployment; do
    run agents_get_prompt "${AGENTS_DIR}" "${role}"
    [ "${status}" -eq 0 ]
    [[ "${output}" == *"# ${role} Agent"* ]]
  done
}

# ---------------------------------------------------------------------------
# agents_compose_prompt
# ---------------------------------------------------------------------------

@test "agents_compose_prompt substitutes ticket into prompt" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
Ticket: {{ticket}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "planner" '{"ticket":"US-007: Load agents"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Ticket: US-007: Load agents"* ]]
}

@test "agents_compose_prompt substitutes plan into prompt" {
  cat > "${AGENTS_DIR}/reviewer.md" <<'EOF'
---
role: reviewer
inputs: plan
outputs: approved
constraints: Output must be valid JSON
---
Plan: {{plan}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "reviewer" '{"plan":"Step 1. Do this."}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Plan: Step 1. Do this."* ]]
}

@test "agents_compose_prompt substitutes adr into prompt" {
  cat > "${AGENTS_DIR}/architect.md" <<'EOF'
---
role: architect
inputs: adr
outputs: approved
constraints: Output must be valid JSON
---
ADR: {{adr}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "architect" '{"adr":"ADR-001: Use bash"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ADR: ADR-001: Use bash"* ]]
}

@test "agents_compose_prompt substitutes tech into prompt" {
  cat > "${AGENTS_DIR}/tester.md" <<'EOF'
---
role: tester
inputs: tech
outputs: test_results
constraints: Output must be valid JSON
---
Tech: {{tech}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "tester" '{"tech":"Bash, BATS"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Tech: Bash, BATS"* ]]
}

@test "agents_compose_prompt substitutes tests into prompt" {
  cat > "${AGENTS_DIR}/developer.md" <<'EOF'
---
role: developer
inputs: tests
outputs: files_changed
constraints: Output must be valid JSON
---
Tests: {{tests}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "developer" '{"tests":"tests/foo.bats"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Tests: tests/foo.bats"* ]]
}

@test "agents_compose_prompt leaves placeholders empty when context keys are absent" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
Ticket: {{ticket}}
Plan: {{plan}}
ADR: {{adr}}
Tech: {{tech}}
Tests: {{tests}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "planner" '{"ticket":"US-007"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Ticket: US-007"* ]]
  [[ "${output}" == *"Plan: "* ]]
  [[ "${output}" == *"ADR: "* ]]
  [[ "${output}" == *"Tech: "* ]]
  [[ "${output}" == *"Tests: "* ]]
}

@test "agents_compose_prompt handles empty context" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
Hello world
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "planner" '{}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Hello world"* ]]
}

@test "agents_compose_prompt handles multi-line ticket value" {
  cat > "${AGENTS_DIR}/planner.md" <<'EOF'
---
role: planner
inputs: ticket
outputs: plan
constraints: Output must be valid JSON
---
Ticket: {{ticket}}
EOF
  local ctx
  ctx=$(jq -n --arg t "Line one
Line two" '{"ticket":$t}')
  run agents_compose_prompt "${AGENTS_DIR}" "planner" "${ctx}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Line one"* ]]
  [[ "${output}" == *"Line two"* ]]
}

@test "agents_compose_prompt fails when agent file does not exist" {
  run agents_compose_prompt "${AGENTS_DIR}" "nonexistent" '{}'
  [ "${status}" -ne 0 ]
}

@test "agents_compose_prompt substitutes implementation into prompt" {
  cat > "${AGENTS_DIR}/developer.md" <<'EOF'
---
role: developer
inputs: implementation
outputs: files_changed
constraints: Output must be valid JSON
---
Implementation: {{implementation}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "developer" '{"implementation":"def foo(): pass"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Implementation: def foo(): pass"* ]]
}

@test "agents_compose_prompt substitutes failures into prompt" {
  cat > "${AGENTS_DIR}/tester.md" <<'EOF'
---
role: tester
inputs: failures
outputs: test_results
constraints: Output must be valid JSON
---
Failures: {{failures}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "tester" '{"failures":"Test X failed with assertion error"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Failures: Test X failed with assertion error"* ]]
}

@test "agents_compose_prompt substitutes mode into prompt" {
  cat > "${AGENTS_DIR}/tester.md" <<'EOF'
---
role: tester
inputs: mode
outputs: test_results
constraints: Output must be valid JSON
---
Mode: {{mode}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "tester" '{"mode":"verify"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Mode: verify"* ]]
}

@test "agents_compose_prompt leaves implementation, failures, mode empty when context keys are absent" {
  cat > "${AGENTS_DIR}/developer.md" <<'EOF'
---
role: developer
inputs: ticket
outputs: files_changed
constraints: Output must be valid JSON
---
Ticket: {{ticket}}
Implementation: {{implementation}}
Failures: {{failures}}
Mode: {{mode}}
EOF
  run agents_compose_prompt "${AGENTS_DIR}" "developer" '{"ticket":"US-013"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Ticket: US-013"* ]]
  [[ "${output}" == *"Implementation: "* ]]
  [[ "${output}" == *"Failures: "* ]]
  [[ "${output}" == *"Mode: "* ]]
}

# ---------------------------------------------------------------------------
# Real agent files (Agents/ in workspace root)
# ---------------------------------------------------------------------------

@test "real planner agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/planner.md"
  [ "${status}" -eq 0 ]
}

@test "real reviewer agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/reviewer.md"
  [ "${status}" -eq 0 ]
}

@test "real architect agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/architect.md"
  [ "${status}" -eq 0 ]
}

@test "real tester agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/tester.md"
  [ "${status}" -eq 0 ]
}

@test "real developer agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/developer.md"
  [ "${status}" -eq 0 ]
}

@test "real deployment agent passes contract validation" {
  run agents_validate_contract "${KARL_DIR}/Agents/deployment.md"
  [ "${status}" -eq 0 ]
}

@test "agents_validate passes for real Agents directory" {
  run agents_validate "${KARL_DIR}/Agents"
  [ "${status}" -eq 0 ]
}

@test "agents_validate_contract fails when constraints field removed from real planner agent copy" {
  local tmp_file
  tmp_file="${WORKSPACE_ROOT}/planner_no_constraints.md"
  grep -v '^constraints:' "${KARL_DIR}/Agents/planner.md" > "${tmp_file}"
  run agents_validate_contract "${tmp_file}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"constraints"* ]]
}

@test "real tester agent prompt body includes {{failures}} placeholder" {
  run grep -F '{{failures}}' "${KARL_DIR}/Agents/tester.md"
  [ "${status}" -eq 0 ]
}

@test "real tester agent prompt body includes {{mode}} placeholder" {
  run grep -F '{{mode}}' "${KARL_DIR}/Agents/tester.md"
  [ "${status}" -eq 0 ]
}

@test "real developer agent prompt body includes {{failures}} placeholder" {
  run grep -F '{{failures}}' "${KARL_DIR}/Agents/developer.md"
  [ "${status}" -eq 0 ]
}

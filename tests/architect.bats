#!/usr/bin/env bats
# tests/architect.bats - Tests for lib/architect.sh (US-010)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ARCHITECT_SH="${KARL_DIR}/lib/architect.sh"
AGENTS_SH="${KARL_DIR}/lib/agents.sh"
RATE_LIMIT_SH="${KARL_DIR}/lib/rate_limit.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  AGENTS_DIR="${WORKSPACE_ROOT}/Agents"
  STUB_DIR="$(mktemp -d)"
  mkdir -p "${AGENTS_DIR}"
  mkdir -p "${WORKSPACE_ROOT}/Output/ADR"
  export KARL_RATE_LIMIT_BACKOFF_BASE=0

  # shellcheck source=../lib/agents.sh
  source "${AGENTS_SH}"
  # shellcheck source=../lib/rate_limit.sh
  source "${RATE_LIMIT_SH}"
  # shellcheck source=../lib/architect.sh
  source "${ARCHITECT_SH}"

  # Minimal architect agent file
  cat > "${AGENTS_DIR}/architect.md" <<'EOF'
---
role: architect
inputs: ticket, plan, adr
outputs: adr_entry, approved
constraints: Output must be valid JSON; approved must be true or false
---

## Ticket

{{ticket}}

## Plan

{{plan}}

## Existing ADRs

{{adr}}
EOF

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  # Default: valid approved response with no ADR entry
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# architect_read_adrs
# ---------------------------------------------------------------------------

@test "architect_read_adrs returns empty string when Output/ADR does not exist" {
  rm -rf "${WORKSPACE_ROOT}/Output/ADR"
  run architect_read_adrs "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "architect_read_adrs returns empty string when Output/ADR is empty" {
  run architect_read_adrs "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "architect_read_adrs returns content of a single ADR file" {
  printf '%s' "# ADR-001: Use bash" > "${WORKSPACE_ROOT}/Output/ADR/US-001.md"
  run architect_read_adrs "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ADR-001: Use bash"* ]]
}

@test "architect_read_adrs concatenates multiple ADR files" {
  printf '%s' "# ADR-001" > "${WORKSPACE_ROOT}/Output/ADR/US-001.md"
  printf '%s' "# ADR-002" > "${WORKSPACE_ROOT}/Output/ADR/US-002.md"
  run architect_read_adrs "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ADR-001"* ]]
  [[ "${output}" == *"ADR-002"* ]]
}

@test "architect_read_adrs ignores non-.md files" {
  printf '%s' "secret" > "${WORKSPACE_ROOT}/Output/ADR/notes.txt"
  printf '%s' "# ADR-001" > "${WORKSPACE_ROOT}/Output/ADR/US-001.md"
  run architect_read_adrs "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ADR-001"* ]]
  [[ "${output}" != *"secret"* ]]
}

# ---------------------------------------------------------------------------
# architect_read_tech
# ---------------------------------------------------------------------------

@test "architect_read_tech returns empty string when tech.md does not exist" {
  run architect_read_tech "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "" ]
}

@test "architect_read_tech returns content of Output/tech.md" {
  printf '%s' "## Stack: Bash, BATS" > "${WORKSPACE_ROOT}/Output/tech.md"
  run architect_read_tech "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Stack: Bash, BATS"* ]]
}

# ---------------------------------------------------------------------------
# architect_run_agent
# ---------------------------------------------------------------------------

@test "architect_run_agent returns JSON on success" {
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run_agent "${AGENTS_DIR}" '{"id":"US-010"}' '{"plan":"do it"}' ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"approved"'* ]]
}

@test "architect_run_agent fails when claude returns invalid JSON" {
  printf '%s' 'not-valid-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run_agent "${AGENTS_DIR}" '{"id":"US-010"}' '{"plan":"do it"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "architect_run_agent fails when approved field is missing from response" {
  printf '%s' '{"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run_agent "${AGENTS_DIR}" '{"id":"US-010"}' '{"plan":"do it"}' ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"approved"* ]]
}

@test "architect_run_agent fails when claude exits non-zero" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run architect_run_agent "${AGENTS_DIR}" '{"id":"US-010"}' '{"plan":"do it"}' ""
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# architect_persist_adr
# ---------------------------------------------------------------------------

@test "architect_persist_adr creates Output/ADR directory if absent" {
  rm -rf "${WORKSPACE_ROOT}/Output/ADR"
  run architect_persist_adr "${WORKSPACE_ROOT}" "US-010" "# ADR content"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Output/ADR" ]
}

@test "architect_persist_adr writes Output/ADR/<story_id>.md" {
  run architect_persist_adr "${WORKSPACE_ROOT}" "US-010" "# ADR content"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/ADR/US-010.md" ]
}

@test "architect_persist_adr file contains the adr_entry content" {
  architect_persist_adr "${WORKSPACE_ROOT}" "US-010" "# ADR: Use BATS for testing"
  result=$(cat "${WORKSPACE_ROOT}/Output/ADR/US-010.md")
  [[ "${result}" == *"ADR: Use BATS for testing"* ]]
}

@test "architect_persist_adr does not fail when git is not initialized" {
  # git commit will fail (not a git repo) but architect_persist_adr uses || true
  run architect_persist_adr "${WORKSPACE_ROOT}" "US-010" "# ADR content"
  [ "${status}" -eq 0 ]
}

@test "architect_persist_adr commits ADR file when workspace is a git repo" {
  git -C "${WORKSPACE_ROOT}" init -q
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com"
  git -C "${WORKSPACE_ROOT}" config user.name "Test"

  architect_persist_adr "${WORKSPACE_ROOT}" "US-010" "# ADR: Use BATS"

  result=$(git -C "${WORKSPACE_ROOT}" log --oneline)
  [[ "${result}" == *"adr: [US-010]"* ]]
}

# ---------------------------------------------------------------------------
# architect_run — happy path: ADR required
# ---------------------------------------------------------------------------

@test "architect_run returns 0 when agent returns non-null adr_entry" {
  printf '%s' '{"approved":true,"adr_entry":"# ADR: New architecture"}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -eq 0 ]
}

@test "architect_run creates ADR file when agent returns non-null adr_entry" {
  printf '%s' '{"approved":true,"adr_entry":"# ADR: New architecture"}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ -f "${WORKSPACE_ROOT}/Output/ADR/US-010.md" ]
}

@test "architect_run prints ADR created message when adr_entry is present" {
  printf '%s' '{"approved":true,"adr_entry":"# ADR: New architecture"}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ADR created"* ]]
}

@test "architect_run writes Output/<story_id>/architect.json when ADR is created" {
  printf '%s' '{"approved":true,"adr_entry":"# ADR: New architecture"}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ -f "${WORKSPACE_ROOT}/Output/US-010/architect.json" ]
}

# ---------------------------------------------------------------------------
# architect_run — happy path: no ADR required
# ---------------------------------------------------------------------------

@test "architect_run returns 0 when agent returns null adr_entry" {
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -eq 0 ]
}

@test "architect_run does not create ADR file when adr_entry is null" {
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ ! -f "${WORKSPACE_ROOT}/Output/ADR/US-010.md" ]
}

@test "architect_run prints no ADR required message when adr_entry is null" {
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"No ADR required"* ]]
}

# ---------------------------------------------------------------------------
# architect_run — error conditions
# ---------------------------------------------------------------------------

@test "architect_run returns non-zero when architect agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -ne 0 ]
}

@test "architect_run prints ERROR when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "architect_run returns non-zero when agent returns invalid JSON" {
  printf '%s' 'not-json' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ "${status}" -ne 0 ]
}

@test "architect_run does not write architect.json when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ ! -f "${WORKSPACE_ROOT}/Output/US-010/architect.json" ]
}

# ---------------------------------------------------------------------------
# architect_run — traceability
# ---------------------------------------------------------------------------

@test "architect_run writes Output/<story_id>/architect.json" {
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  [ -f "${WORKSPACE_ROOT}/Output/US-010/architect.json" ]
}

@test "architect_run architect.json contains approved field" {
  printf '%s' '{"approved":true,"adr_entry":null}' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  result=$(jq -r '.approved' "${WORKSPACE_ROOT}/Output/US-010/architect.json")
  [ "${result}" = "true" ]
}

@test "architect_run architect.json is valid JSON" {
  PATH="${STUB_DIR}:${PATH}" architect_run "${AGENTS_DIR}" "${WORKSPACE_ROOT}" '{"id":"US-010"}' '{"plan":"do it"}'
  run jq . "${WORKSPACE_ROOT}/Output/US-010/architect.json"
  [ "${status}" -eq 0 ]
}

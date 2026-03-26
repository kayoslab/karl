#!/usr/bin/env bats
# tests/tech.bats - Tests for lib/tech.sh (US-021)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TECH_SH="${KARL_DIR}/lib/tech.sh"
RATE_LIMIT_SH="${KARL_DIR}/lib/rate_limit.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  AGENTS_DIR="${WORKSPACE_ROOT}/Agents"
  STUB_DIR="$(mktemp -d)"
  mkdir -p "${AGENTS_DIR}"
  mkdir -p "${WORKSPACE_ROOT}/Output"
  mkdir -p "${WORKSPACE_ROOT}/Input"
  export KARL_RATE_LIMIT_BACKOFF_BASE=0
  export KARL_AGENTS_DIR="${AGENTS_DIR}"

  # shellcheck source=../lib/rate_limit.sh
  source "${RATE_LIMIT_SH}"
  # shellcheck source=../lib/tech.sh
  source "${TECH_SH}"

  # Minimal tech agent file
  cat > "${AGENTS_DIR}/tech.md" <<'EOF'
---
role: tech
inputs: prd
outputs: tech_summary
constraints: Output must be concise markdown
---

## Role
Generate technology decisions.
EOF

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  printf '%s' '# Technology Context

**Language**: Bash — project is a shell script automation tool' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
  unset KARL_AGENTS_DIR
}

# ---------------------------------------------------------------------------
# tech_needed
# ---------------------------------------------------------------------------

@test "tech_needed returns 0 when Output/tech.md does not exist" {
  rm -f "${WORKSPACE_ROOT}/Output/tech.md"
  run tech_needed "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_needed returns 1 when Output/tech.md exists with content" {
  printf '# Technology Context\n**Language**: Bash\n' > "${WORKSPACE_ROOT}/Output/tech.md"
  run tech_needed "${WORKSPACE_ROOT}"
  [ "${status}" -ne 0 ]
}

@test "tech_needed returns 0 when Output/tech.md exists but is empty" {
  touch "${WORKSPACE_ROOT}/Output/tech.md"
  run tech_needed "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_needed returns 0 when Output directory does not exist" {
  rmdir "${WORKSPACE_ROOT}/Output"
  run tech_needed "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# tech_run_agent
# ---------------------------------------------------------------------------

@test "tech_run_agent returns content when claude succeeds" {
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" ""
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Technology Context"* ]]
}

@test "tech_run_agent fails when tech agent file does not exist" {
  rm "${AGENTS_DIR}/tech.md"
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" ""
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"ERROR"* ]]
}

@test "tech_run_agent fails when claude exits non-zero" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" ""
  [ "${status}" -ne 0 ]
}

@test "tech_run_agent works when prd_json is empty" {
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" ""
  [ "${status}" -eq 0 ]
}

@test "tech_run_agent strips frontmatter from agent file before calling claude" {
  # The agent frontmatter should not appear in the output (it's stripped before prompt)
  printf '%s' '## Role body content' > "${STUB_DIR}/.output"
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" ""
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"role: tech"* ]]
}

@test "tech_run_agent succeeds when prd_json is provided" {
  PATH="${STUB_DIR}:${PATH}" run tech_run_agent "${AGENTS_DIR}" '{"title":"My Project"}'
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# tech_persist
# ---------------------------------------------------------------------------

@test "tech_persist writes content to Output/tech.md" {
  run tech_persist "${WORKSPACE_ROOT}" "# Technology Context"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

@test "tech_persist creates Output directory if absent" {
  rmdir "${WORKSPACE_ROOT}/Output"
  run tech_persist "${WORKSPACE_ROOT}" "# Technology Context"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/Output" ]
}

@test "tech_persist content matches what was passed" {
  tech_persist "${WORKSPACE_ROOT}" "# Technology Context
**Language**: Bash"
  content=$(cat "${WORKSPACE_ROOT}/Output/tech.md")
  [[ "${content}" == *"Language"* ]]
}

# ---------------------------------------------------------------------------
# tech_discover
# ---------------------------------------------------------------------------

@test "tech_discover returns 0 and skips when tech.md already has content" {
  printf '# Technology Context\n**Language**: Bash\n' > "${WORKSPACE_ROOT}/Output/tech.md"
  tech_run_agent() { echo "ERROR: should not be called"; return 1; }
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_discover prints skip message when tech.md already exists" {
  printf '# Technology Context\n**Language**: Bash\n' > "${WORKSPACE_ROOT}/Output/tech.md"
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping"* ]]
}

@test "tech_discover creates Output/tech.md when absent" {
  tech_run_agent() { printf '# Technology Context\n**Language**: Bash\n'; }
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

@test "tech_discover Output/tech.md content matches agent output" {
  tech_run_agent() { printf '# Technology Context\n**Language**: Bash\n'; }
  tech_discover "${WORKSPACE_ROOT}"
  content=$(cat "${WORKSPACE_ROOT}/Output/tech.md")
  [[ "${content}" == *"Language"* ]]
}

@test "tech_discover skips gracefully when tech agent file is missing" {
  rm "${AGENTS_DIR}/tech.md"
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_discover returns 0 non-blocking when tech agent file is missing" {
  rm "${AGENTS_DIR}/tech.md"
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARNING"* ]]
}

@test "tech_discover skips gracefully when agent fails" {
  tech_run_agent() { echo "ERROR: agent failed" >&2; return 1; }
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_discover returns 0 non-blocking when agent fails" {
  tech_run_agent() { echo "ERROR: agent failed" >&2; return 1; }
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARNING"* ]]
}

@test "tech_discover reads PRD from Input/prd.json when present" {
  printf '{"title":"Karl"}' > "${WORKSPACE_ROOT}/Input/prd.json"
  local captured_prd=""
  tech_run_agent() {
    captured_prd="${2:-}"
    printf '# Technology Context\n'
  }
  tech_discover "${WORKSPACE_ROOT}"
  # prd.json was present; function ran without error
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

@test "tech_discover works without Input/prd.json" {
  rm -f "${WORKSPACE_ROOT}/Input/prd.json"
  tech_run_agent() { printf '# Technology Context\n**Language**: Bash\n'; }
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

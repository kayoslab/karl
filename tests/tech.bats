#!/usr/bin/env bats
# tests/tech.bats - Tests for lib/tech.sh

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
TECH_SH="${KARL_DIR}/lib/tech.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  STUB_DIR="$(mktemp -d)"
  mkdir -p "${WORKSPACE_ROOT}/Output"
  mkdir -p "${WORKSPACE_ROOT}/Input"

  # shellcheck source=../lib/tech.sh
  source "${TECH_SH}"

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
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "tech_discover prints skip message when tech.md already exists" {
  printf '# Technology Context\n**Language**: Bash\n' > "${WORKSPACE_ROOT}/Output/tech.md"
  run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"skipping"* ]]
}

@test "tech_discover creates Output/tech.md when claude succeeds" {
  PATH="${STUB_DIR}:${PATH}" run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [ -f "${WORKSPACE_ROOT}/Output/tech.md" ]
}

@test "tech_discover skips gracefully when claude agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"WARNING"* ]]
}

@test "tech_discover returns 0 non-blocking when agent fails" {
  printf '1' > "${STUB_DIR}/.exit"
  PATH="${STUB_DIR}:${PATH}" run tech_discover "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

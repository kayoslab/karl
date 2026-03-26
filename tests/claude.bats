#!/usr/bin/env bats
# tests/claude.bats - Tests for lib/claude.sh

CLAUDE_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/claude.sh"

setup() {
  STUB_DIR="$(mktemp -d)"
  # shellcheck source=../lib/claude.sh
  source "${CLAUDE_SH}"
}

teardown() {
  rm -rf "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# claude_is_installed
# ---------------------------------------------------------------------------

@test "claude_is_installed returns 0 when claude stub exists in PATH" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/claude"
  chmod +x "${STUB_DIR}/claude"
  PATH="${STUB_DIR}:${PATH}" run claude_is_installed
  [ "$status" -eq 0 ]
}

@test "claude_is_installed returns non-zero when claude is absent from PATH" {
  PATH="${STUB_DIR}" run claude_is_installed
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# claude_validate
# ---------------------------------------------------------------------------

@test "claude_validate returns 0 when claude binary is present" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "${STUB_DIR}/claude"
  chmod +x "${STUB_DIR}/claude"
  PATH="${STUB_DIR}:${PATH}" run claude_validate
  [ "$status" -eq 0 ]
}

@test "claude_validate returns 1 when claude binary is absent" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -eq 1 ]
}

@test "claude_validate stderr contains ERROR when claude is missing" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"ERROR"* ]]
}

@test "claude_validate stderr contains install instruction when claude is missing" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"Install"* ]]
}

@test "claude_validate stderr mentions PATH when claude is missing" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -eq 1 ]
  [[ "$output" == *"PATH"* ]]
}

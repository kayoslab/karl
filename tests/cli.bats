#!/usr/bin/env bats
# tests/cli.bats - Integration tests for Claude CLI validation at startup

KARL_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/karl.sh"
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
# Integration: claude_validate drives loop-does-not-begin behaviour
# ---------------------------------------------------------------------------

@test "claude_validate exits non-zero when claude binary is absent from PATH" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -ne 0 ]
}

@test "claude_validate prints actionable error message when claude is absent" {
  PATH="${STUB_DIR}" run claude_validate
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"Install"* ]]
}

# ---------------------------------------------------------------------------
# End-to-end: karl.sh exits before loop work when claude is absent
# Use a PATH with system utilities but no claude binary.
# ---------------------------------------------------------------------------

@test "karl.sh exits non-zero when claude binary is absent from PATH" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}"
  [ "$status" -ne 0 ]
}

@test "karl.sh prints actionable error when claude binary is absent" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
  [[ "$output" == *"Install"* ]]
}

# ---------------------------------------------------------------------------
# --max-retries argument parsing (US-012)
# ---------------------------------------------------------------------------

@test "karl.sh accepts --max-retries argument without unknown-argument error" {
  # Should fail due to missing claude, not due to argument parsing
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}" --max-retries 5
  [ "$status" -ne 0 ]
  [[ "$output" != *"Unknown argument"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "karl.sh exits non-zero when --max-retries is given without a value" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}" --max-retries
  [ "$status" -ne 0 ]
}

@test "karl.sh logs configured max-retries value in output" {
  # Provide a stub claude that exits immediately so we can observe log output
  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  # Provide a minimal workspace with a complete PRD so the loop reaches the log line
  TMPWS="$(mktemp -d)"
  mkdir -p "${TMPWS}/Input"
  printf '{"userStories":[{"id":"US-001","priority":1,"passes":true}]}' \
    > "${TMPWS}/Input/prd.json"
  touch "${TMPWS}/CLAUDE.md"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" commit --allow-empty -q -m "init"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --max-retries 7 --workspace "${TMPWS}" 2>&1 || true

  rm -rf "${TMPWS}"
  [[ "$output" == *"max-retries=7"* ]]
}

# ---------------------------------------------------------------------------
# --max-retries input validation (US-022)
# ---------------------------------------------------------------------------

@test "karl.sh exits non-zero when --max-retries is given a non-numeric value" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}" --max-retries abc
  [ "$status" -ne 0 ]
}

@test "karl.sh prints error message when --max-retries is non-numeric" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}" --max-retries abc
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# --dry-run mode (US-022 AC#3)
# ---------------------------------------------------------------------------

@test "karl.sh accepts --dry-run argument without unknown-argument error" {
  PATH="/usr/bin:/bin:${STUB_DIR}" run bash "${KARL_SH}" --dry-run
  [[ "$output" != *"Unknown argument"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "karl.sh --dry-run does not create a LOCK file" {
  TMPWS="$(mktemp -d)"
  mkdir -p "${TMPWS}/Input"
  printf '{"userStories":[{"id":"US-001","priority":1,"passes":false,"title":"First"}]}' \
    > "${TMPWS}/Input/prd.json"
  touch "${TMPWS}/CLAUDE.md"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" commit --allow-empty -q -m "init"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --dry-run --workspace "${TMPWS}" 2>&1 || true

  local lock_exists=0
  [ -f "${TMPWS}/LOCK" ] && lock_exists=1

  rm -rf "${TMPWS}"
  [ "${lock_exists}" -eq 0 ]
}

@test "karl.sh --dry-run shows the next ticket without starting work" {
  TMPWS="$(mktemp -d)"
  mkdir -p "${TMPWS}/Input"
  printf '{"userStories":[{"id":"US-001","priority":1,"passes":false,"title":"First story"}]}' \
    > "${TMPWS}/Input/prd.json"
  touch "${TMPWS}/CLAUDE.md"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" commit --allow-empty -q -m "init"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --dry-run --workspace "${TMPWS}" 2>&1 || true

  rm -rf "${TMPWS}"
  [[ "$output" == *"US-001"* ]]
}

# ---------------------------------------------------------------------------
# --clean flag (US-023)
# ---------------------------------------------------------------------------

@test "karl.sh accepts --clean argument without unknown-argument error" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" commit --allow-empty -q -m "init"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" 2>&1 || true

  rm -rf "${TMPWS}"
  [[ "$output" != *"Unknown argument"* ]]
  [[ "$output" != *"Unknown option"* ]]
}

@test "karl.sh --clean exits 0 on a clean git workspace" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" config user.email "test@test.com"
  git -C "${TMPWS}" config user.name "Test"
  git -C "${TMPWS}" commit --allow-empty -q -m "init"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" 2>&1

  rm -rf "${TMPWS}"
  [ "$status" -eq 0 ]
}

@test "karl.sh --clean checks out main branch" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" config user.email "test@test.com"
  git -C "${TMPWS}" config user.name "Test"
  git -C "${TMPWS}" commit --allow-empty -q -m "init"
  git -C "${TMPWS}" checkout -b feature/wip -q

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" > /dev/null 2>&1 || true

  local branch
  branch=$(git -C "${TMPWS}" rev-parse --abbrev-ref HEAD 2>/dev/null)
  rm -rf "${TMPWS}"
  [ "${branch}" = "main" ]
}

@test "karl.sh --clean removes LOCK file" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" config user.email "test@test.com"
  git -C "${TMPWS}" config user.name "Test"
  git -C "${TMPWS}" commit --allow-empty -q -m "init"
  touch "${TMPWS}/LOCK"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" > /dev/null 2>&1 || true

  local lock_exists=0
  [ -f "${TMPWS}/LOCK" ] && lock_exists=1
  rm -rf "${TMPWS}"
  [ "${lock_exists}" -eq 0 ]
}

@test "karl.sh --clean exits 1 when workspace is not a git repository" {
  TMPWS="$(mktemp -d)"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" 2>&1

  rm -rf "${TMPWS}"
  [ "$status" -ne 0 ]
}

@test "karl.sh --clean prints ERROR when workspace is not a git repository" {
  TMPWS="$(mktemp -d)"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" 2>&1

  rm -rf "${TMPWS}"
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR"* ]] || [[ "$output" == *"WARNING"* ]]
}

@test "karl.sh --clean --force exits 0 and discards uncommitted changes" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" config user.email "test@test.com"
  git -C "${TMPWS}" config user.name "Test"
  git -C "${TMPWS}" commit --allow-empty -q -m "init"
  # Create a tracked file and commit it, then modify it
  printf 'original\n' > "${TMPWS}/file.txt"
  git -C "${TMPWS}" add file.txt
  git -C "${TMPWS}" -c commit.gpgsign=false commit -q -m "add file"
  printf 'modified\n' > "${TMPWS}/file.txt"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --force --workspace "${TMPWS}" 2>&1

  local content
  content=$(cat "${TMPWS}/file.txt" 2>/dev/null || echo "")
  rm -rf "${TMPWS}"
  [ "$status" -eq 0 ]
  [ "${content}" = "original" ]
}

@test "karl.sh --clean warns about dirty tree without --force" {
  TMPWS="$(mktemp -d)"
  git -C "${TMPWS}" init -q
  git -C "${TMPWS}" config user.email "test@test.com"
  git -C "${TMPWS}" config user.name "Test"
  git -C "${TMPWS}" commit --allow-empty -q -m "init"
  printf 'original\n' > "${TMPWS}/file.txt"
  git -C "${TMPWS}" add file.txt
  git -C "${TMPWS}" -c commit.gpgsign=false commit -q -m "add file"
  printf 'modified\n' > "${TMPWS}/file.txt"

  cat > "${STUB_DIR}/claude" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "${STUB_DIR}/claude"

  PATH="${STUB_DIR}:/usr/bin:/bin" run bash "${KARL_SH}" \
    --clean --workspace "${TMPWS}" 2>&1

  rm -rf "${TMPWS}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"WARNING"* ]] || [[ "$output" == *"force"* ]]
}

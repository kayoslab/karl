#!/usr/bin/env bats
# tests/git.bats - Tests for lib/git.sh

GIT_SH="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)/lib/git.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  STUB_DIR="$(mktemp -d)"
  # shellcheck source=../lib/git.sh
  source "${GIT_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}" "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# Helper: initialize a real git repo in WORKSPACE_ROOT
# ---------------------------------------------------------------------------
_init_repo() {
  git -C "${WORKSPACE_ROOT}" init -b main > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.email "test@test.com" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" config user.name "Test" > /dev/null 2>&1
  git -C "${WORKSPACE_ROOT}" commit --allow-empty -m "initial" > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# git_repo_check
# ---------------------------------------------------------------------------

@test "git_repo_check returns 0 when directory is a git repository" {
  _init_repo
  run git_repo_check "${WORKSPACE_ROOT}"
  [ "${status}" -eq 0 ]
}

@test "git_repo_check returns 1 when directory is not a git repository" {
  run git_repo_check "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
}

@test "git_repo_check prints a warning when no repository exists" {
  run git_repo_check "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"WARNING"* ]]
}

@test "git_repo_check warning mentions git is required" {
  run git_repo_check "${WORKSPACE_ROOT}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"git"* ]]
}

@test "git_repo_check requires directory argument" {
  run git_repo_check
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# git_init_repo - auto_init=true (no prompt)
# ---------------------------------------------------------------------------

@test "git_init_repo with auto_init creates a git repository" {
  run git_init_repo "${WORKSPACE_ROOT}" "true"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/.git" ]
}

@test "git_init_repo with auto_init creates main branch" {
  git_init_repo "${WORKSPACE_ROOT}" "true"
  local branch
  branch=$(git -C "${WORKSPACE_ROOT}" rev-parse --abbrev-ref HEAD)
  [ "${branch}" = "main" ]
}

@test "git_init_repo with auto_init prints confirmation message" {
  run git_init_repo "${WORKSPACE_ROOT}" "true"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"initialized"* ]]
}

# ---------------------------------------------------------------------------
# git_init_repo - confirmation via stdin
# ---------------------------------------------------------------------------

@test "git_init_repo with 'y' confirmation initializes repository" {
  run git_init_repo "${WORKSPACE_ROOT}" <<< "y"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/.git" ]
}

@test "git_init_repo with 'Y' confirmation initializes repository" {
  run git_init_repo "${WORKSPACE_ROOT}" <<< "Y"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/.git" ]
}

@test "git_init_repo with 'n' confirmation returns 1" {
  run git_init_repo "${WORKSPACE_ROOT}" <<< "n"
  [ "${status}" -eq 1 ]
}

@test "git_init_repo decline prints ERROR message" {
  run git_init_repo "${WORKSPACE_ROOT}" <<< "n"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# git_init_repo - failure case (git init fails)
# ---------------------------------------------------------------------------

@test "git_init_repo prints ERROR and returns 1 when git init fails" {
  # Stub git to fail
  cat > "${STUB_DIR}/git" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "${STUB_DIR}/git"

  PATH="${STUB_DIR}:${PATH}" run git_init_repo "${WORKSPACE_ROOT}" "true"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"ERROR"* ]]
}

# ---------------------------------------------------------------------------
# git_ensure_repo
# ---------------------------------------------------------------------------

@test "git_ensure_repo returns 0 when repo already exists" {
  _init_repo
  run git_ensure_repo "${WORKSPACE_ROOT}" "true"
  [ "${status}" -eq 0 ]
}

@test "git_ensure_repo initializes repo when absent (auto_init)" {
  run git_ensure_repo "${WORKSPACE_ROOT}" "true"
  [ "${status}" -eq 0 ]
  [ -d "${WORKSPACE_ROOT}/.git" ]
}

#!/usr/bin/env bash
# workspace.sh - karl workspace bootstrap and validation

set -euo pipefail

# Required workspace directories
WORKSPACE_DIRS=(
  "Input"
  "Output"
  "Output/ADR"
)

# Required input files (must exist after bootstrap for run to proceed)
WORKSPACE_REQUIRED_INPUTS=(
  "Input/prd.json"
  "CLAUDE.md"
)

# Canonical output paths (created empty if missing)
WORKSPACE_OUTPUT_FILES=(
  "Output/progress.md"
  "Output/tech.md"
)

# bootstrap_workspace <workspace_root>
# Creates required directories and placeholder output files.
bootstrap_workspace() {
  local root="${1:?workspace root required}"

  for dir in "${WORKSPACE_DIRS[@]}"; do
    mkdir -p "${root}/${dir}"
  done

  for output_file in "${WORKSPACE_OUTPUT_FILES[@]}"; do
    local full_path="${root}/${output_file}"
    if [[ ! -f "${full_path}" ]]; then
      touch "${full_path}"
    fi
  done

  # Ensure LOCK is gitignored in the workspace (prevents branch-switch conflicts)
  local gitignore="${root}/.gitignore"
  if [[ -f "${gitignore}" ]]; then
    if ! grep -qx 'LOCK' "${gitignore}" 2>/dev/null; then
      printf '\nLOCK\n' >> "${gitignore}"
    fi
  else
    printf 'LOCK\n' > "${gitignore}"
  fi

  return 0
}

# validate_workspace <workspace_root>
# Returns 0 if workspace is valid, 1 with error messages if not.
validate_workspace() {
  local root="${1:?workspace root required}"
  local errors=0

  for dir in "${WORKSPACE_DIRS[@]}"; do
    if [[ ! -d "${root}/${dir}" ]]; then
      echo "ERROR: Required directory missing: ${root}/${dir}" >&2
      errors=$((errors + 1))
    fi
  done

  for input_file in "${WORKSPACE_REQUIRED_INPUTS[@]}"; do
    if [[ ! -f "${root}/${input_file}" ]]; then
      echo "ERROR: Required input file missing: ${root}/${input_file}" >&2
      errors=$((errors + 1))
    fi
  done

  if [[ "${errors}" -gt 0 ]]; then
    echo "ERROR: Workspace validation failed with ${errors} error(s). Aborting startup." >&2
    return 1
  fi

  return 0
}

# workspace_init <workspace_root>
# Bootstrap and then validate. Fails with clear error if required inputs are absent.
workspace_init() {
  local root="${1:?workspace root required}"

  bootstrap_workspace "${root}"
  validate_workspace "${root}"
}

#!/usr/bin/env bash
# lib/tech.sh - First-run tech discovery and tech.md generation

set -euo pipefail

# tech_needed <workspace_root>
# Returns 0 if tech discovery is needed (Output/tech.md absent or empty).
# Returns 1 if tech.md already exists and has content.
tech_needed() {
  local workspace_root="${1:?workspace_root required}"
  local tech_file="${workspace_root}/Output/tech.md"

  if [[ -f "${tech_file}" && -s "${tech_file}" ]]; then
    return 1
  fi
  return 0
}

# tech_persist <workspace_root> <content>
# Writes tech content to Output/tech.md.
tech_persist() {
  local workspace_root="${1:?workspace_root required}"
  local content="${2:?content required}"

  local output_dir="${workspace_root}/Output"
  mkdir -p "${output_dir}"
  printf '%s\n' "${content}" > "${output_dir}/tech.md"
}

# tech_discover <workspace_root>
# Runs tech discovery if Output/tech.md is absent or empty.
# Uses the tech subagent via Claude Code.
# Skips gracefully if agent fails.
# Always returns 0 (non-blocking).
tech_discover() {
  local workspace_root="${1:?workspace_root required}"

  if ! tech_needed "${workspace_root}"; then
    echo "[tech] tech.md already exists — skipping discovery"
    return 0
  fi

  local prd_json=""
  local prd_file="${workspace_root}/Input/prd.json"
  if [[ -f "${prd_file}" ]]; then
    prd_json=$(cat "${prd_file}")
  fi

  local content
  if ! content=$(cd "${workspace_root}" && claude --agent tech --print --output-format text -p "Generate the technology context markdown document for this project. Output ONLY the markdown starting with '# Technology Context'. No conversation. PRD: ${prd_json}"); then
    echo "[tech] WARNING: tech agent failed — skipping" >&2
    return 0
  fi

  tech_persist "${workspace_root}" "${content}"
  echo "[tech] tech.md created at ${workspace_root}/Output/tech.md"
  return 0
}

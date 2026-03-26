#!/usr/bin/env bash
# lib/tech.sh - First-run tech discovery and tech.md generation (US-021)

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

# tech_run_agent <agents_dir> <prd_json>
# Runs the tech agent to generate tech.md content.
# Prints tech.md content to stdout; returns non-zero on failure.
tech_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local prd_json="${2:-}"

  local tech_agent_file="${agents_dir}/tech.md"
  if [[ ! -f "${tech_agent_file}" ]]; then
    echo "ERROR: tech agent file not found at ${tech_agent_file}" >&2
    return 1
  fi

  # Read the tech agent prompt body (strip YAML frontmatter)
  local prompt
  prompt=$(awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm {print}' "${tech_agent_file}")

  # Append PRD context if provided
  if [[ -n "${prd_json}" ]]; then
    prompt="${prompt}

## PRD Context

${prd_json}"
  fi

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  printf '%s\n' "${response}"
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
# Uses KARL_AGENTS_DIR env var for agents directory (defaults to ${KARL_DIR}/Agents).
# Skips gracefully if tech agent is not found or agent fails.
# Always returns 0 (non-blocking).
tech_discover() {
  local workspace_root="${1:?workspace_root required}"
  local agents_dir="${KARL_AGENTS_DIR:-${KARL_DIR:-}/Agents}"

  if ! tech_needed "${workspace_root}"; then
    echo "[tech] tech.md already exists — skipping discovery"
    return 0
  fi

  if [[ ! -f "${agents_dir}/tech.md" ]]; then
    echo "[tech] WARNING: tech agent not found at ${agents_dir}/tech.md — skipping" >&2
    return 0
  fi

  local prd_json=""
  local prd_file="${workspace_root}/Input/prd.json"
  if [[ -f "${prd_file}" ]]; then
    prd_json=$(cat "${prd_file}")
  fi

  local content
  if ! content=$(cd "${workspace_root}" && tech_run_agent "${agents_dir}" "${prd_json}"); then
    echo "[tech] WARNING: tech agent failed — skipping" >&2
    return 0
  fi

  tech_persist "${workspace_root}" "${content}"
  echo "[tech] tech.md created at ${workspace_root}/Output/tech.md"
  return 0
}

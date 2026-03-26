#!/usr/bin/env bash
# lib/architect.sh - Architect agent: ADR validation and maintenance (US-010)

set -euo pipefail

# architect_read_adrs <workspace_root>
# Reads all ADR markdown files from Output/ADR/ and returns concatenated content.
# Returns empty string if no ADRs exist.
architect_read_adrs() {
  local workspace_root="${1:?workspace_root required}"
  local adr_dir="${workspace_root}/Output/ADR"

  if [[ ! -d "${adr_dir}" ]]; then
    printf ''
    return 0
  fi

  local content=""
  local first=1
  for f in "${adr_dir}"/*.md; do
    [[ -e "${f}" ]] || continue
    if [[ "${first}" -eq 0 ]]; then
      content="${content}"$'\n---\n'
    fi
    content="${content}$(cat "${f}")"
    first=0
  done

  printf '%s' "${content}"
}

# architect_read_tech <workspace_root>
# Reads Output/tech.md and returns its content.
# Returns empty string if file does not exist.
architect_read_tech() {
  local workspace_root="${1:?workspace_root required}"
  local tech_file="${workspace_root}/Output/tech.md"

  if [[ ! -f "${tech_file}" ]]; then
    printf ''
    return 0
  fi

  cat "${tech_file}"
}

# architect_run_agent <agents_dir> <ticket_json> <plan_json> <adr> [tech]
# Calls the architect agent to evaluate architectural impact.
# Prints agent response JSON to stdout; returns non-zero on failure.
architect_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local plan_json="${3:?plan_json required}"
  local adr="${4:-}"
  local tech="${5:-}"

  local context_json
  context_json=$(jq -n \
    --arg ticket "${ticket_json}" \
    --arg plan "${plan_json}" \
    --arg adr "${adr}" \
    --arg tech "${tech}" \
    '{"ticket":$ticket,"plan":$plan,"adr":$adr,"tech":$tech}')

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "architect" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Architect agent returned invalid JSON" >&2
    return 1
  fi

  if ! printf '%s' "${response}" | jq -e 'has("approved")' > /dev/null 2>&1; then
    echo "ERROR: Architect response missing required field: approved" >&2
    return 1
  fi

  printf '%s\n' "${response}"
}

# architect_persist_adr <workspace_root> <story_id> <adr_entry>
# Writes the ADR entry to Output/ADR/<story_id>.md and commits to git.
architect_persist_adr() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"
  local adr_entry="${3:?adr_entry required}"

  local adr_dir="${workspace_root}/Output/ADR"
  mkdir -p "${adr_dir}"

  local adr_file="${adr_dir}/${story_id}.md"
  printf '%s\n' "${adr_entry}" > "${adr_file}"

  local artifact_dir="${workspace_root}/Output/${story_id}"
  git -C "${workspace_root}" add "${adr_file}" 2>/dev/null || true
  git -C "${workspace_root}" add "${artifact_dir}/architect.json" 2>/dev/null || true
  git -C "${workspace_root}" commit -m "adr: [${story_id}] architecture decision" > /dev/null 2>&1 || true
}

# architect_run <agents_dir> <workspace_root> <ticket_json> <plan_json>
# Orchestrates the architect agent workflow:
#   - Reads existing ADRs and tech.md
#   - Calls architect agent
#   - Persists ADR if adr_entry is non-null
#   - Writes Output/<story_id>/architect.json for traceability
# Returns 0 on success, non-zero on failure.
architect_run() {
  local agents_dir="${1:?agents_dir required}"
  local workspace_root="${2:?workspace_root required}"
  local ticket_json="${3:?ticket_json required}"
  local plan_json="${4:?plan_json required}"

  local story_id
  story_id=$(printf '%s' "${ticket_json}" | jq -r '.id // "unknown"')

  local adr_content tech_content
  adr_content=$(architect_read_adrs "${workspace_root}")
  tech_content=$(architect_read_tech "${workspace_root}")

  local response
  if ! response=$(cd "${workspace_root}" && architect_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${adr_content}" "${tech_content}"); then
    echo "ERROR: Architect agent failed for ${story_id}" >&2
    return 1
  fi

  local output_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${output_dir}"
  printf '%s\n' "${response}" > "${output_dir}/architect.json"

  local adr_entry
  adr_entry=$(printf '%s' "${response}" | jq -r '.adr_entry // empty')

  if [[ -n "${adr_entry}" ]]; then
    architect_persist_adr "${workspace_root}" "${story_id}" "${adr_entry}"
    echo "[architect] ADR created for ${story_id}"
  else
    # No ADR needed — commit architect.json artifact only
    if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
      git -C "${workspace_root}" add "${output_dir}/architect.json" 2>/dev/null || true
      git -C "${workspace_root}" commit \
        -m "chore: [${story_id}] architect review — no ADR required" \
        > /dev/null 2>&1 || true
    fi
    echo "[architect] No ADR required for ${story_id}"
  fi

  return 0
}

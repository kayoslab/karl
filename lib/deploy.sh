#!/usr/bin/env bash
# lib/deploy.sh - Deployment gate: verify quality requirements before merge (US-015)

set -euo pipefail

# deploy_run_agent <agents_dir> <ticket_json> <plan_json> <tech> <tests_json>
# Calls the deployment agent to evaluate quality gates.
# Prints agent response JSON to stdout; returns non-zero on failure.
deploy_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local plan_json="${3:?plan_json required}"
  local tech="${4:-}"
  local tests_json="${5:-}"

  local context_json
  context_json=$(jq -n \
    --arg ticket "${ticket_json}" \
    --arg plan "${plan_json}" \
    --arg tech "${tech}" \
    --arg tests "${tests_json}" \
    '{"ticket":$ticket,"plan":$plan,"tech":$tech,"tests":$tests}')

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "deployment" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Deployment agent returned invalid JSON" >&2
    return 1
  fi

  for field in decision gates_checked; do
    if ! printf '%s' "${response}" | jq -e "has(\"${field}\")" > /dev/null 2>&1; then
      echo "ERROR: Deployment response missing required field: ${field}" >&2
      return 1
    fi
  done

  printf '%s\n' "${response}"
}

# deploy_persist <workspace_root> <ticket_id> <response_json>
# Writes the deployment agent response to Output/<ticket_id>/deploy.json.
# Returns 0 on success, non-zero on error.
deploy_persist() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local response_json="${3:?response_json required}"

  local output_dir="${workspace_root}/Output/${ticket_id}"
  mkdir -p "${output_dir}"
  printf '%s\n' "${response_json}" > "${output_dir}/deploy.json"
}

# deploy_gate <agents_dir> <workspace_root> <ticket_json> <plan_json> <tech>
# Orchestrates the full deployment gate workflow:
#   - Reads tests.json and ADR files for context
#   - Runs the deployment agent
#   - Persists deploy.json
#   - Creates a git commit on pass (silently skips if not a git repo)
#   - Returns 0 on pass, 1 on fail
deploy_gate() {
  local agents_dir="${1:?agents_dir required}"
  local workspace_root="${2:?workspace_root required}"
  local ticket_json="${3:?ticket_json required}"
  local plan_json="${4:?plan_json required}"
  local tech="${5:-}"

  local ticket_id
  ticket_id=$(printf '%s' "${ticket_json}" | jq -r '.id // "unknown"')

  # Read tests.json if present
  local tests_json=""
  local tests_file="${workspace_root}/Output/${ticket_id}/tests.json"
  if [[ -f "${tests_file}" ]]; then
    tests_json=$(cat "${tests_file}")
  fi

  # Read ADR files if present
  local adr_content=""
  local adr_dir="${workspace_root}/Output/ADR"
  if [[ -d "${adr_dir}" ]]; then
    local adr_files
    adr_files=$(find "${adr_dir}" -name "*.md" 2>/dev/null | sort)
    if [[ -n "${adr_files}" ]]; then
      while IFS= read -r adr_file; do
        adr_content+="$(cat "${adr_file}")"$'\n\n'
      done <<< "${adr_files}"
    fi
  fi

  local response
  if ! response=$(cd "${workspace_root}" && deploy_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${tech}" "${tests_json}"); then
    echo "ERROR: Deployment agent failed for ${ticket_id}" >&2
    return 1
  fi

  # Always persist the deploy.json artifact
  deploy_persist "${workspace_root}" "${ticket_id}" "${response}"

  local decision
  decision=$(printf '%s' "${response}" | jq -r '.decision')

  if [[ "${decision}" == "pass" ]]; then
    echo "[deploy] Gate passed for ${ticket_id}"

    # Create a git commit linking gate artifacts to history (silently skip if not a git repo)
    if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit \
        -m "chore: [${ticket_id}] deployment gate passed" \
        > /dev/null 2>&1 || true
    fi

    return 0
  else
    echo "[deploy] Gate FAILED for ${ticket_id}" >&2

    # Log each failure reason
    local failures_count
    failures_count=$(printf '%s' "${response}" | jq '.failures | length')
    if [[ "${failures_count}" -gt 0 ]]; then
      local i=0
      while [[ "${i}" -lt "${failures_count}" ]]; do
        local reason
        reason=$(printf '%s' "${response}" | jq -r ".failures[${i}]")
        echo "[deploy] Failure: ${reason}" >&2
        i=$((i + 1))
      done
    fi

    return 1
  fi
}

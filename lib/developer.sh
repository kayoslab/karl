#!/usr/bin/env bash
# lib/developer.sh - Developer agent: implements ticket against tests (US-036)

set -euo pipefail

# developer_run_agent <agents_dir> <ticket_json> <plan_json> <tech> <tests_json> <failures> <mode>
# Calls the developer agent to implement the ticket.
# Prints agent response JSON to stdout; returns non-zero on failure.
developer_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local plan_json="${3:?plan_json required}"
  local tech="${4:-}"
  local tests_json="${5:-}"
  local failures="${6:-}"
  local mode="${7:-implement}"

  local context_json
  context_json=$(jq -n \
    --arg ticket  "${ticket_json}" \
    --arg plan    "${plan_json}" \
    --arg tech    "${tech}" \
    --arg tests   "${tests_json}" \
    --arg failures "${failures}" \
    --arg mode    "${mode}" \
    '{"ticket":$ticket,"plan":$plan,"tech":$tech,"tests":$tests,"failures":$failures,"mode":$mode}')

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "developer" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Developer agent returned invalid JSON" >&2
    return 1
  fi

  for field in files_changed summary; do
    if ! printf '%s' "${response}" | jq -e "has(\"${field}\")" > /dev/null 2>&1; then
      echo "ERROR: Developer response missing required field: ${field}" >&2
      return 1
    fi
  done

  printf '%s\n' "${response}"
}

# developer_run <workspace_root> <ticket_id> <ticket_json> [failures] [mode]
# Orchestrates the developer agent workflow:
#   - Reads plan.json, tests.json, and tech.md from workspace
#   - Calls developer agent
#   - Persists Output/<ticket_id>/developer.json
# Returns 0 on success, non-zero on failure.
developer_run() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local ticket_json="${3:?ticket_json required}"
  local failures="${4:-}"
  local mode="${5:-implement}"

  local agents_dir="${KARL_DIR}/Agents"
  local output_dir="${workspace_root}/Output/${ticket_id}"

  local plan_json=""
  if [[ -f "${output_dir}/plan.json" ]]; then
    plan_json=$(cat "${output_dir}/plan.json")
  fi

  local tests_json=""
  if [[ -f "${output_dir}/tests.json" ]]; then
    tests_json=$(cat "${output_dir}/tests.json")
  fi

  local tech=""
  if [[ -f "${workspace_root}/Output/tech.md" ]]; then
    tech=$(cat "${workspace_root}/Output/tech.md")
  fi

  local response
  if ! response=$(cd "${workspace_root}" && developer_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${tech}" "${tests_json}" "${failures}" "${mode}"); then
    echo "ERROR: Developer agent failed for ${ticket_id}" >&2
    return 1
  fi

  mkdir -p "${output_dir}"
  printf '%s\n' "${response}" > "${output_dir}/developer.json"

  # Commit developer.json and any source files written by the agent
  if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
    git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
    git -C "${workspace_root}" commit \
      -m "feat: [${ticket_id}] developer agent implementation" \
      > /dev/null 2>&1 || true
  fi

  echo "[developer] Implementation complete for ${ticket_id}"
  return 0
}

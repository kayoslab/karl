#!/usr/bin/env bash
# lib/tester.sh - Test-first handoff: tester agent generates tests before development (US-011)

set -euo pipefail

# tester_run_agent <agents_dir> <ticket_json> <plan_json> <tech>
# Calls the tester agent to generate or update tests from the approved plan.
# Prints agent response JSON to stdout; returns non-zero on failure.
tester_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local plan_json="${3:?plan_json required}"
  local tech="${4:-}"

  local context_json
  context_json=$(jq -n \
    --arg ticket "${ticket_json}" \
    --arg plan "${plan_json}" \
    --arg tech "${tech}" \
    '{"ticket":$ticket,"plan":$plan,"tech":$tech}')

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "tester" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Tester agent returned invalid JSON" >&2
    return 1
  fi

  for field in tests_added test_results; do
    if ! printf '%s' "${response}" | jq -e "has(\"${field}\")" > /dev/null 2>&1; then
      echo "ERROR: Tester response missing required field: ${field}" >&2
      return 1
    fi
  done

  printf '%s\n' "${response}"
}

# tester_read_existing <workspace_root> <story_id>
# Reads Output/<story_id>/tests.json and prints its content.
# Returns empty string if the file does not exist.
tester_read_existing() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"

  local tests_file="${workspace_root}/Output/${story_id}/tests.json"

  if [[ ! -f "${tests_file}" ]]; then
    printf ''
    return 0
  fi

  cat "${tests_file}"
}

# tester_generate <agents_dir> <workspace_root> <ticket_json> <plan_json> <tech>
# Orchestrates the test generation workflow:
#   - Runs the tester agent to produce tests JSON
#   - Persists tests.json to Output/<story_id>/
#   - Commits tests.json to git history when tests are added or modified
# Returns 0 on success (including when test_results is "fail").
# Returns non-zero on agent failure or invalid JSON.
tester_generate() {
  local agents_dir="${1:?agents_dir required}"
  local workspace_root="${2:?workspace_root required}"
  local ticket_json="${3:?ticket_json required}"
  local plan_json="${4:?plan_json required}"
  local tech="${5:-}"

  local story_id
  story_id=$(printf '%s' "${ticket_json}" | jq -r '.id // "unknown"')

  local response
  if ! response=$(cd "${workspace_root}" && tester_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${tech}"); then
    echo "ERROR: Tester agent failed for ${story_id}" >&2
    return 1
  fi

  local output_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${output_dir}"
  printf '%s\n' "${response}" > "${output_dir}/tests.json"

  echo "[tester] Tests generated for ${story_id}"

  # Always commit tests.json and any test files written by the agent
  if git -C "${workspace_root}" rev-parse --git-dir > /dev/null 2>&1; then
    git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
    git -C "${workspace_root}" commit \
      -m "test: [${story_id}] tester agent — test generation" \
      > /dev/null 2>&1 || true
  fi

  return 0
}

# tester_run <workspace_root> <ticket_id> <ticket_json>
# Runs the tester agent in verification mode against current implementation.
# Returns 0 when test_results is "pass", 1 otherwise.
tester_run() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local ticket_json="${3:?ticket_json required}"

  local agents_dir="${KARL_DIR}/Agents"
  local output_dir="${workspace_root}/Output/${ticket_id}"

  local plan_json=""
  if [[ -f "${output_dir}/plan.json" ]]; then
    plan_json=$(cat "${output_dir}/plan.json")
  fi

  local tech=""
  if [[ -f "${workspace_root}/Output/tech.md" ]]; then
    tech=$(cat "${workspace_root}/Output/tech.md")
  fi

  local response
  if ! response=$(cd "${workspace_root}" && tester_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${tech}"); then
    echo "ERROR: Tester agent failed for ${ticket_id}" >&2
    return 1
  fi

  mkdir -p "${output_dir}"
  printf '%s\n' "${response}" > "${output_dir}/tests.json"

  local result
  result=$(printf '%s' "${response}" | jq -r '.test_results // "fail"')

  if [[ "${result}" == "pass" ]]; then
    echo "[tester] Tests passing for ${ticket_id}"
    return 0
  fi

  # Record failure source for rework loop branching
  local failure_source
  failure_source=$(printf '%s' "${response}" | jq -r '.failure_source // "implementation"')
  printf '%s' "${failure_source}" > "${output_dir}/last_failure_source"

  local failures
  failures=$(printf '%s' "${response}" | jq -r '.failures // [] | join("\n")')
  printf '%s' "${failures}" > "${output_dir}/last_failures"

  echo "[tester] Tests FAILING for ${ticket_id}"
  return 1
}

# tester_fix_run <workspace_root> <ticket_id> <ticket_json>
# Runs the tester agent in fix mode to correct a broken test.
# Returns 0 on success, non-zero on agent failure.
tester_fix_run() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local ticket_json="${3:?ticket_json required}"

  local agents_dir="${KARL_DIR}/Agents"
  local output_dir="${workspace_root}/Output/${ticket_id}"

  local plan_json=""
  if [[ -f "${output_dir}/plan.json" ]]; then
    plan_json=$(cat "${output_dir}/plan.json")
  fi

  local tech=""
  if [[ -f "${workspace_root}/Output/tech.md" ]]; then
    tech=$(cat "${workspace_root}/Output/tech.md")
  fi

  local response
  if ! response=$(cd "${workspace_root}" && tester_run_agent "${agents_dir}" "${ticket_json}" "${plan_json}" "${tech}"); then
    echo "[tester] Fix agent failed for ${ticket_id} — continuing" >&2
    return 1
  fi

  mkdir -p "${output_dir}"
  printf '%s\n' "${response}" > "${output_dir}/tests.json"

  echo "[tester] Test fix applied for ${ticket_id}"
  return 0
}

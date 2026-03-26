#!/usr/bin/env bash
# lib/planning.sh - Planning and review loop (US-009)

set -euo pipefail

# planning_run_agent <agents_dir> <ticket_json> <tech> [feedback]
# Creates an implementation plan using the planner agent.
# Prints plan JSON to stdout; returns non-zero on failure.
planning_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local tech="${3:-}"
  local feedback="${4:-}"

  local context_json
  context_json=$(jq -n --arg ticket "${ticket_json}" --arg tech "${tech}" \
    '{"ticket":$ticket,"tech":$tech}')
  if [[ -n "${feedback}" ]]; then
    context_json=$(printf '%s' "${context_json}" | jq --arg f "${feedback}" '. + {"feedback":$f}')
  fi

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "planner" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Planner agent returned invalid JSON" >&2
    return 1
  fi

  if ! printf '%s' "${response}" | jq -e 'has("plan")' > /dev/null 2>&1; then
    echo "ERROR: Planner response missing required field: plan" >&2
    return 1
  fi

  if ! printf '%s' "${response}" | jq -e 'has("testing_recommendations")' > /dev/null 2>&1; then
    echo "ERROR: Planner response missing required field: testing_recommendations" >&2
    return 1
  fi

  printf '%s\n' "${response}"
}

# planning_review_plan <agents_dir> <ticket_json> <plan_json>
# Reviews the implementation plan using the reviewer agent.
# Prints review JSON to stdout; returns non-zero on failure.
planning_review_plan() {
  local agents_dir="${1:?agents_dir required}"
  local ticket_json="${2:?ticket_json required}"
  local plan_json="${3:?plan_json required}"

  local context_json
  context_json=$(jq -n --arg ticket "${ticket_json}" --arg plan "${plan_json}" \
    '{"ticket":$ticket,"plan":$plan}')

  local prompt
  prompt=$(agents_compose_prompt "${agents_dir}" "reviewer" "${context_json}") || return 1

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Reviewer agent returned invalid JSON" >&2
    return 1
  fi

  printf '%s\n' "${response}"
}

# planning_persist <workspace_root> <story_id> <plan_json>
# Persists plan JSON to Output/<story_id>/plan.json.
planning_persist() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"
  local plan_json="${3:?plan_json required}"

  local output_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${output_dir}"
  printf '%s\n' "${plan_json}" > "${output_dir}/plan.json"
}

# planning_persist_review <workspace_root> <story_id> <review_json>
# Persists review JSON to Output/<story_id>/review.json.
planning_persist_review() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"
  local review_json="${3:?review_json required}"

  local output_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${output_dir}"
  printf '%s\n' "${review_json}" > "${output_dir}/review.json"
}

# planning_commit <workspace_root> <story_id>
# Commits the persisted plan artifact to git history.
planning_commit() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"

  local plan_file="${workspace_root}/Output/${story_id}/plan.json"
  git -C "${workspace_root}" add "${plan_file}" 2>/dev/null || true
  git -C "${workspace_root}" commit -m "plan: ${story_id} implementation plan" > /dev/null 2>&1 || true
}

# planning_run_loop <agents_dir> <workspace_root> <story_json> [tech] [max_retries]
# Orchestrates the planning and review loop for a story.
# Returns 0 with approved plan persisted to Output/<id>/plan.json.
# Returns 1 on agent failure or when max retries are exceeded.
planning_run_loop() {
  local agents_dir="${1:?agents_dir required}"
  local workspace_root="${2:?workspace_root required}"
  local story_json="${3:?story_json required}"
  local tech="${4:-}"
  local max_retries="${5:-3}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')

  local plan feedback=""
  local attempt=0

  while [[ "${attempt}" -lt "${max_retries}" ]]; do
    attempt=$((attempt + 1))

    if ! plan=$(cd "${workspace_root}" && planning_run_agent "${agents_dir}" "${story_json}" "${tech}" "${feedback}"); then
      echo "ERROR: Planner agent failed on attempt ${attempt}" >&2
      return 1
    fi

    local review
    if ! review=$(cd "${workspace_root}" && planning_review_plan "${agents_dir}" "${story_json}" "${plan}"); then
      echo "ERROR: Reviewer agent failed" >&2
      return 1
    fi

    local approved
    approved=$(printf '%s' "${review}" | jq -r '.approved // "false"')

    if [[ "${approved}" == "true" ]]; then
      planning_persist "${workspace_root}" "${story_id}" "${plan}"
      planning_persist_review "${workspace_root}" "${story_id}" "${review}"
      planning_commit "${workspace_root}" "${story_id}"
      echo "[planning] Plan approved and persisted for ${story_id}"
      return 0
    fi

    feedback=$(printf '%s' "${review}" | jq -r '[.concerns // [] | .[]] | join("; ")')
    echo "[planning] Plan requires revision (attempt ${attempt}/${max_retries}): ${feedback}"
  done

  echo "ERROR: Planning loop exceeded max retries (${max_retries}) for ${story_id}" >&2
  return 1
}

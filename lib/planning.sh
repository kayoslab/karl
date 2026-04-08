#!/usr/bin/env bash
# planning.sh - Planning and review orchestration via subagents

set -euo pipefail

# planning_run_loop <workspace_root> <story_json> <tech> [max_review_retries]
# Runs planner -> reviewer loop until approved or retries exhausted.
# Persists plan.json and review.json to Output/<story_id>/.
# Returns 0 on approval, 1 on failure.
planning_run_loop() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local tech="${3:-}"
  local max_retries="${4:-3}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${artifact_dir}"

  local feedback=""
  local attempt=0

  while [[ "${attempt}" -lt "${max_retries}" ]]; do
    attempt=$((attempt + 1))
    echo "[planning] Planning attempt ${attempt}/${max_retries} for ${story_id}..."

    local plan_prompt="Create an implementation plan for this ticket. Return ONLY a valid JSON object.
Ticket: ${story_json}
Technology Context: ${tech}"
    if [[ -n "${feedback}" ]]; then
      plan_prompt="${plan_prompt}

IMPORTANT — Your previous plan was REJECTED by the reviewer. You MUST address ALL of the following feedback in your revised plan. Do not repeat the same plan.

Reviewer feedback:
${feedback}"
    fi

    local plan_response
    if ! plan_response=$(cd "${workspace_root}" && subagent_invoke_json "planner" "${plan_prompt}" "${SCHEMA_PLANNER:-}"); then
      echo "ERROR: Planner agent failed for ${story_id}" >&2
      return 1
    fi
    mkdir -p "${artifact_dir}" 2>/dev/null || true
    printf '%s\n' "${plan_response}" > "${artifact_dir}/plan.json"

    local review_prompt="Review this implementation plan. Return ONLY a valid JSON object.
Ticket: ${story_json}
Plan: ${plan_response}"

    local review_response
    if ! review_response=$(cd "${workspace_root}" && subagent_invoke_json "reviewer" "${review_prompt}" "${SCHEMA_REVIEWER:-}"); then
      echo "ERROR: Reviewer agent failed for ${story_id}" >&2
      return 1
    fi
    mkdir -p "${artifact_dir}" 2>/dev/null || true
    printf '%s\n' "${review_response}" > "${artifact_dir}/review.json"

    local approved
    approved=$(printf '%s' "${review_response}" | jq -r '.approved // false')

    if [[ "${approved}" == "true" ]]; then
      # Merge reviewer corrections into the plan so downstream agents see them
      local corrections
      corrections=$(printf '%s' "${review_response}" | jq -r '
        def extract: if type == "array" then . else [.] end;
        [(.corrections // [])[], (.refinements // [])[], (.changes_required // [])[]]
        | if length > 0 then map(if type == "string" then . else tostring end) else empty end
        | join("; ")' 2>/dev/null) || corrections=""
      if [[ -n "${corrections}" ]]; then
        echo "[planning] Plan approved with corrections for ${story_id}"
        # Append corrections to plan.json so developer sees them
        local corrected_plan
        corrected_plan=$(printf '%s' "${plan_response}" | jq --arg c "${corrections}" '. + {reviewer_corrections: $c}' 2>/dev/null) || corrected_plan="${plan_response}"
        mkdir -p "${artifact_dir}" 2>/dev/null || true
        printf '%s\n' "${corrected_plan}" > "${artifact_dir}/plan.json"
      else
        echo "[planning] Plan approved for ${story_id}"
      fi
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit -m "plan: [${story_id}] implementation plan approved" > /dev/null 2>&1 || true
      return 0
    fi

    feedback=$(printf '%s' "${review_response}" | jq -r '
      (.concerns // []) | map(if type == "string" then . else tostring end) | join("; ")')

    if [[ -z "${feedback}" ]]; then
      # No recognized feedback fields — pass the entire review response
      feedback="${review_response}"
    fi

    echo "[planning] Plan rejected (attempt ${attempt}/${max_retries}): ${feedback}"
  done

  echo "ERROR: Planning failed after ${max_retries} attempts for ${story_id}" >&2
  return 1
}

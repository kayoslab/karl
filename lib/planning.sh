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
    [[ -n "${feedback}" ]] && plan_prompt="${plan_prompt}
Reviewer feedback from previous attempt: ${feedback}"

    local plan_response
    if ! plan_response=$(cd "${workspace_root}" && subagent_invoke_json "planner" "${plan_prompt}"); then
      echo "ERROR: Planner agent failed for ${story_id}" >&2
      return 1
    fi
    printf '%s\n' "${plan_response}" > "${artifact_dir}/plan.json"

    local review_prompt="Review this implementation plan. Return ONLY a valid JSON object.
Ticket: ${story_json}
Plan: ${plan_response}"

    local review_response
    if ! review_response=$(cd "${workspace_root}" && subagent_invoke_json "reviewer" "${review_prompt}"); then
      echo "ERROR: Reviewer agent failed for ${story_id}" >&2
      return 1
    fi
    printf '%s\n' "${review_response}" > "${artifact_dir}/review.json"

    # Check multiple approval field patterns: approved:true, verdict:"approve"/"approved"
    local approved
    approved=$(printf '%s' "${review_response}" | jq -r '
      if .approved == true then "true"
      elif (.verdict // "" | test("^approve"; "i")) then "true"
      else "false"
      end')

    if [[ "${approved}" == "true" ]]; then
      echo "[planning] Plan approved for ${story_id}"
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit -m "plan: [${story_id}] implementation plan approved" > /dev/null 2>&1 || true
      return 0
    fi

    # Extract feedback from any field that looks like reviewer concerns.
    # Handles: concerns, changes_required, notes, feedback, reason, comments
    # Each can be a string or an array of strings/objects.
    feedback=$(printf '%s' "${review_response}" | jq -r '
      def extract: if type == "array" then .[] else . end | if type == "string" then . else tostring end;
      [
        (.concerns       // null | if . then extract else empty end),
        (.changes_required // null | if . then extract else empty end),
        (.notes          // null | if . then extract else empty end),
        (.feedback       // null | if . then extract else empty end),
        (.reason         // null | if . then extract else empty end),
        (.comments       // null | if . then extract else empty end)
      ] | map(select(length > 0)) | join("; ")')

    if [[ -z "${feedback}" ]]; then
      # Last resort: dump the entire response minus the verdict/approved fields
      feedback=$(printf '%s' "${review_response}" | jq -r 'del(.approved, .verdict, .plan_hash) | tostring')
    fi

    echo "[planning] Plan rejected (attempt ${attempt}/${max_retries}): ${feedback}"
  done

  echo "ERROR: Planning failed after ${max_retries} attempts for ${story_id}" >&2
  return 1
}

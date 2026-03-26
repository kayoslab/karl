#!/usr/bin/env bash
# lib/summarize.sh - Artifact summarization policy (US-018)

set -euo pipefail

# summarize_plan <plan_json> <source_file>
# Produces a concise summary of a plan artifact.
# Prints summary JSON to stdout.
summarize_plan() {
  local plan_json="${1:?plan_json required}"
  local source_file="${2:?source_file required}"

  local step_count
  step_count=$(printf '%s' "${plan_json}" | jq '[.plan // [] | .[]] | length')

  local rec_count
  rec_count=$(printf '%s' "${plan_json}" | jq '[.testing_recommendations // [] | .[]] | length')

  local complexity
  complexity=$(printf '%s' "${plan_json}" | jq -r '.estimated_complexity // "unknown"')

  jq -n \
    --arg source_file "${source_file}" \
    --arg estimated_complexity "${complexity}" \
    --argjson step_count "${step_count}" \
    --argjson testing_recommendation_count "${rec_count}" \
    '{
      summary_type: "plan",
      source_file: $source_file,
      estimated_complexity: $estimated_complexity,
      step_count: $step_count,
      testing_recommendation_count: $testing_recommendation_count
    }'
}

# summarize_review <review_json> <source_file>
# Produces a concise summary of a review artifact.
# Prints summary JSON to stdout.
summarize_review() {
  local review_json="${1:?review_json required}"
  local source_file="${2:?source_file required}"

  local approved
  approved=$(printf '%s' "${review_json}" | jq -r '.approved // false')

  local feedback_count
  feedback_count=$(printf '%s' "${review_json}" | jq '[.concerns // [] | .[]] | length')

  jq -n \
    --arg source_file "${source_file}" \
    --argjson approved "${approved}" \
    --argjson feedback_count "${feedback_count}" \
    '{
      summary_type: "review",
      source_file: $source_file,
      approved: $approved,
      feedback_count: $feedback_count
    }'
}

# summarize_tests <tests_json> <source_file>
# Produces a concise summary of a test results artifact.
# Prints summary JSON to stdout.
summarize_tests() {
  local tests_json="${1:?tests_json required}"
  local source_file="${2:?source_file required}"

  local passed
  passed=$(printf '%s' "${tests_json}" | jq -r '.passed // false')

  local failure_count
  failure_count=$(printf '%s' "${tests_json}" | jq '[.failures // [] | .[]] | length')

  local test_count
  test_count=$(printf '%s' "${tests_json}" | jq '.test_count // 0')

  local summary
  summary=$(printf '%s' "${tests_json}" | jq -r '.summary // ""')

  jq -n \
    --arg source_file "${source_file}" \
    --argjson passed "${passed}" \
    --argjson failure_count "${failure_count}" \
    --argjson test_count "${test_count}" \
    --arg summary "${summary}" \
    '{
      summary_type: "tests",
      source_file: $source_file,
      passed: $passed,
      test_count: $test_count,
      failure_count: $failure_count,
      summary: $summary
    }'
}

# summarize_architect <architect_json> <source_file>
# Produces a concise summary of an architect artifact.
# Prints summary JSON to stdout.
summarize_architect() {
  local architect_json="${1:?architect_json required}"
  local source_file="${2:?source_file required}"

  local decision
  decision=$(printf '%s' "${architect_json}" | jq -r '.decision // ""')

  local adr_required
  adr_required=$(printf '%s' "${architect_json}" | jq '.adr_required // false')

  # Prefer implementation_notes over notes; fall back to empty string
  local notes
  notes=$(printf '%s' "${architect_json}" | jq -r '(.implementation_notes // .notes) // ""')

  # Determine which key name to use in the output
  local has_impl_notes
  has_impl_notes=$(printf '%s' "${architect_json}" | jq 'has("implementation_notes")')

  if [[ "${has_impl_notes}" == "true" ]]; then
    jq -n \
      --arg source_file "${source_file}" \
      --arg decision "${decision}" \
      --argjson adr_required "${adr_required}" \
      --arg implementation_notes "${notes}" \
      '{
        summary_type: "architect",
        source_file: $source_file,
        decision: $decision,
        adr_required: $adr_required,
        implementation_notes: $implementation_notes
      }'
  else
    jq -n \
      --arg source_file "${source_file}" \
      --arg decision "${decision}" \
      --argjson adr_required "${adr_required}" \
      --arg notes "${notes}" \
      '{
        summary_type: "architect",
        source_file: $source_file,
        decision: $decision,
        adr_required: $adr_required,
        notes: $notes
      }'
  fi
}

# summarize_artifact <type> <artifact_json> <source_file>
# Dispatches to the appropriate summarizer based on type.
# Prints summary JSON to stdout; returns non-zero for unknown types.
summarize_artifact() {
  local artifact_type="${1:?artifact_type required}"
  local artifact_json="${2:?artifact_json required}"
  local source_file="${3:?source_file required}"

  case "${artifact_type}" in
    plan)
      summarize_plan "${artifact_json}" "${source_file}"
      ;;
    review)
      summarize_review "${artifact_json}" "${source_file}"
      ;;
    tests)
      summarize_tests "${artifact_json}" "${source_file}"
      ;;
    architect)
      summarize_architect "${artifact_json}" "${source_file}"
      ;;
    *)
      echo "ERROR: Unknown artifact type: ${artifact_type}" >&2
      return 1
      ;;
  esac
}

# summarize_ticket_artifacts <workspace_root> <ticket_id>
# Summarizes all known durable artifacts for a ticket.
# Writes *_summary.json files alongside source artifacts.
# Returns 0 always (no summarizable artifacts is not an error).
summarize_ticket_artifacts() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"

  local artifact_dir="${workspace_root}/Output/${ticket_id}"
  local summarized=0

  # Ordered list: type -> source file -> summary file
  local -a types=( plan review architect tests )
  local -a sources=( plan.json review.json architect.json tests.json )
  local -a summaries=( plan_summary.json review_summary.json architect_summary.json tests_summary.json )

  local i
  for i in "${!types[@]}"; do
    local atype="${types[$i]}"
    local src="${artifact_dir}/${sources[$i]}"
    local dst="${artifact_dir}/${summaries[$i]}"
    local rel_path="Output/${ticket_id}/${sources[$i]}"

    if [[ -f "${src}" ]]; then
      local artifact_json
      artifact_json=$(cat "${src}")
      local summary
      summary=$(summarize_artifact "${atype}" "${artifact_json}" "${rel_path}") || continue
      printf '%s\n' "${summary}" > "${dst}"
      summarized=$((summarized + 1))
    fi
  done

  return 0
}

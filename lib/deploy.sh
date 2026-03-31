#!/usr/bin/env bash
# deploy.sh - Deployment gate via subagent

set -euo pipefail

# deploy_gate <workspace_root> <story_json> <plan_json> <tech>
# Returns 0 if deployment gate passes, 1 on failure.
deploy_gate() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local plan_json="${3:-}"
  local tech="${4:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${artifact_dir}"

  local tests=""
  [[ -f "${artifact_dir}/tests.json" ]] && tests=$(cat "${artifact_dir}/tests.json")

  local prompt_file
  prompt_file=$(mktemp)
  cat > "${prompt_file}" <<DEPLOYPROMPT
Verify all quality gates pass for this ticket. Run the actual test, build, and typecheck commands described in the Technology Context below.

IMPORTANT: Before running any commands, ensure project dependencies are installed. Check the Technology Context for the correct package manager and install command.

## Ticket
${story_json}

## Plan
${plan_json}

## Technology Context
${tech}

## Test Results from Rework Loop
${tests}

Return ONLY a valid JSON object: {"decision": "pass"|"fail", "gates_checked": ["tests", "typecheck"], "failures": [...], "notes": "..."}
DEPLOYPROMPT

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "deployment" "$(cat "${prompt_file}")"); then
    rm -f "${prompt_file}"
    echo "ERROR: Deployment gate agent failed for ${story_id}" >&2
    return 1
  fi
  rm -f "${prompt_file}"
  printf '%s\n' "${response}" > "${artifact_dir}/deploy.json"

  # Check multiple field names: decision, verdict, result, status
  local decision
  decision=$(printf '%s' "${response}" | jq -r '
    (.decision // .verdict // .result // .status // "fail")
    | if test("^pass"; "i") then "pass" else "fail" end')

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "deploy: [${story_id}] deployment gate — ${decision}" > /dev/null 2>&1 || true

  if [[ "${decision}" == "pass" ]]; then
    echo "[deploy] Deployment gate passed for ${story_id}"
    return 0
  fi

  local failures
  failures=$(printf '%s' "${response}" | jq -r '(.failures // []) | map(if type == "string" then . else tostring end) | join("; ")' 2>/dev/null) || failures="unknown"
  local notes
  notes=$(printf '%s' "${response}" | jq -r '.notes // ""' 2>/dev/null) || notes=""
  echo "ERROR: Deployment gate failed for ${story_id}: ${failures}" >&2
  [[ -n "${notes}" ]] && echo "[deploy] Notes: ${notes}" >&2
  return 1
}

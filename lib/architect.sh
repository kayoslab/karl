#!/usr/bin/env bash
# architect.sh - Architecture review via subagent

set -euo pipefail

# architect_run <workspace_root> <story_json> <plan_json>
architect_run() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local plan_json="${3:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${artifact_dir}"

  local adrs=""
  if [[ -d "${workspace_root}/Output/ADR" ]]; then
    adrs=$(cat "${workspace_root}"/Output/ADR/*.md 2>/dev/null || true)
  fi
  local tech=""
  [[ -f "${workspace_root}/Output/tech.md" ]] && tech=$(cat "${workspace_root}/Output/tech.md")

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "architect" \
    "Evaluate the architectural impact of this plan. Return ONLY a valid JSON object. Ticket: ${story_json} Plan: ${plan_json} Existing ADRs: ${adrs} Technology Context: ${tech}"); then
    echo "ERROR: Architect agent failed for ${story_id}" >&2
    return 1
  fi
  mkdir -p "${artifact_dir}" 2>/dev/null || true
  printf '%s\n' "${response}" > "${artifact_dir}/architect.json"

  local adr_entry
  adr_entry=$(printf '%s' "${response}" | jq -r '.adr_entry // .adr // .adr_content // .decision_record // empty')
  if [[ -n "${adr_entry}" && "${adr_entry}" != "null" ]]; then
    mkdir -p "${workspace_root}/Output/ADR"
    printf '%s\n' "${adr_entry}" > "${workspace_root}/Output/ADR/${story_id}.md"
  fi

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "arch: [${story_id}] architecture review" > /dev/null 2>&1 || true
  return 0
}

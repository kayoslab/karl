#!/usr/bin/env bash
# developer.sh - Developer agent via subagent

set -euo pipefail

# developer_run <workspace_root> <story_json> <mode>
# mode: "implement" for first pass, "fix" for rework
developer_run() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local mode="${3:-implement}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${artifact_dir}"

  local plan=""
  [[ -f "${artifact_dir}/plan.json" ]] && plan=$(cat "${artifact_dir}/plan.json")
  local tech=""
  [[ -f "${workspace_root}/Output/tech.md" ]] && tech=$(cat "${workspace_root}/Output/tech.md")
  local tests=""
  [[ -f "${artifact_dir}/tests.json" ]] && tests=$(cat "${artifact_dir}/tests.json")
  local failures=""
  [[ -f "${artifact_dir}/failures.txt" ]] && failures=$(cat "${artifact_dir}/failures.txt")

  # Build a clearly structured prompt so the developer can see failures
  local prompt_file
  prompt_file=$(mktemp)
  cat > "${prompt_file}" <<DEVPROMPT
Mode: ${mode}
${mode:+$(if [[ "${mode}" == "fix" ]]; then echo "IMPORTANT: The previous implementation failed tests. Fix the issues described in FAILURES below."; fi)}

## Ticket
${story_json}

## Plan
${plan}

## Technology Context
${tech}

## Tests (must pass)
${tests}

## Failures from previous attempt
${failures:-None}

After implementing, return ONLY a valid JSON object: {"files_changed": [...], "summary": "..."}
DEVPROMPT

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "developer" "$(cat "${prompt_file}")" "${SCHEMA_DEVELOPER:-}"); then
    rm -f "${prompt_file}"
    echo "ERROR: Developer agent failed for ${story_id}" >&2
    return 1
  fi
  rm -f "${prompt_file}"
  printf '%s\n' "${response}" > "${artifact_dir}/developer.json"

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "feat: [${story_id}] developer ${mode}" > /dev/null 2>&1 || true
  return 0
}

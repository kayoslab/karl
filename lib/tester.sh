#!/usr/bin/env bash
# tester.sh - Test generation and verification via subagent

set -euo pipefail

# tester_generate <workspace_root> <story_json> <plan_json> <tech>
tester_generate() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local plan_json="${3:-}"
  local tech="${4:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"
  mkdir -p "${artifact_dir}"

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "tester" \
    "Generate tests for this ticket. Mode: generate. Return ONLY a valid JSON object. Ticket: ${story_json} Plan: ${plan_json} Technology Context: ${tech}"); then
    echo "ERROR: Tester agent failed for ${story_id}" >&2
    return 1
  fi
  printf '%s\n' "${response}" > "${artifact_dir}/tests.json"

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "test: [${story_id}] test generation" > /dev/null 2>&1 || true
  return 0
}

# tester_verify <workspace_root> <story_json> <plan_json> <tech>
# Returns 0 if tests pass, 1 on failure. Writes failure info to artifact dir.
tester_verify() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local plan_json="${3:-}"
  local tech="${4:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"

  local tests=""
  [[ -f "${artifact_dir}/tests.json" ]] && tests=$(cat "${artifact_dir}/tests.json")
  local impl=""
  [[ -f "${artifact_dir}/developer.json" ]] && impl=$(cat "${artifact_dir}/developer.json")
  local failures=""
  [[ -f "${artifact_dir}/failures.txt" ]] && failures=$(cat "${artifact_dir}/failures.txt")

  local prompt_file
  prompt_file=$(mktemp)
  cat > "${prompt_file}" <<TESTPROMPT
Mode: verify — run the test suite and report results.

## Ticket
${story_json}

## Plan
${plan_json}

## Technology Context
${tech}

## Current Tests
${tests}

## Implementation Summary
${impl}

## Previous Failures
${failures:-None}

Run the tests. Return ONLY a valid JSON object: {"tests_added": [], "tests_modified": [], "test_results": "pass"|"fail", "failures": [...], "failure_source": "implementation"|"test"|null}
TESTPROMPT

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "tester" "$(cat "${prompt_file}")"); then
    rm -f "${prompt_file}"
    echo "ERROR: Tester verification failed for ${story_id}" >&2
    return 1
  fi
  rm -f "${prompt_file}"
  printf '%s\n' "${response}" > "${artifact_dir}/tests.json"

  # Check multiple field names for test results
  local test_results
  test_results=$(printf '%s' "${response}" | jq -r '
    (.test_results // .result // .status // .outcome // "fail")
    | if test("^pass"; "i") then "pass" else "fail" end')

  if [[ "${test_results}" == "pass" ]]; then
    return 0
  fi

  # Store failure info for rework loop — check multiple field names
  printf '%s' "${response}" | jq -r '
    .failure_source // .source // .blame // .failed_component // "implementation"' \
    > "${artifact_dir}/failure_source.txt"
  # Handle failures as array of strings or objects — check multiple field names
  printf '%s' "${response}" | jq -r '
    (.failures // .errors // .failed_tests // .issues // [])
    | if type == "array" then map(if type == "string" then . else tostring end) | join("\n")
      else tostring end' > "${artifact_dir}/failures.txt" 2>/dev/null || \
    printf '%s' "${response}" | jq -r '.failures // "unknown failure"' > "${artifact_dir}/failures.txt"

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "test: [${story_id}] test verification — failed" > /dev/null 2>&1 || true
  return 1
}

# tester_fix <workspace_root> <story_json> <plan_json> <tech>
tester_fix() {
  local workspace_root="${1:?workspace_root required}"
  local story_json="${2:?story_json required}"
  local plan_json="${3:-}"
  local tech="${4:-}"

  local story_id
  story_id=$(printf '%s' "${story_json}" | jq -r '.id // "unknown"')
  local artifact_dir="${workspace_root}/Output/${story_id}"

  local tests=""
  [[ -f "${artifact_dir}/tests.json" ]] && tests=$(cat "${artifact_dir}/tests.json")
  local failures=""
  [[ -f "${artifact_dir}/failures.txt" ]] && failures=$(cat "${artifact_dir}/failures.txt")

  local response
  if ! response=$(cd "${workspace_root}" && subagent_invoke_json "tester" \
    "Fix incorrect tests. Mode: fix. Return ONLY a valid JSON object. Ticket: ${story_json} Plan: ${plan_json} Technology Context: ${tech} Tests: ${tests} Failures: ${failures}"); then
    echo "ERROR: Tester fix failed for ${story_id}" >&2
    return 1
  fi
  printf '%s\n' "${response}" > "${artifact_dir}/tests.json"

  git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
  git -C "${workspace_root}" commit -m "test: [${story_id}] test self-correction" > /dev/null 2>&1 || true
  return 0
}

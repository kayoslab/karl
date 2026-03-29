#!/usr/bin/env bash
# rework.sh - Developer/tester rework loop

set -euo pipefail

# rework_loop <workspace_root> <story_id> <story_json> [max_retries]
# Alternates developer and tester until tests pass or limit reached.
# Returns 0 on success, 1 on failure.
rework_loop() {
  local workspace_root="${1:?workspace_root required}"
  local story_id="${2:?story_id required}"
  local story_json="${3:?story_json required}"
  local max_retries="${4:-10}"

  local artifact_dir="${workspace_root}/Output/${story_id}"
  local plan=""
  [[ -f "${artifact_dir}/plan.json" ]] && plan=$(cat "${artifact_dir}/plan.json")
  local tech=""
  [[ -f "${workspace_root}/Output/tech.md" ]] && tech=$(cat "${workspace_root}/Output/tech.md")

  local attempt=0
  local skip_developer="false"

  while [[ "${attempt}" -lt "${max_retries}" ]]; do
    attempt=$((attempt + 1))

    # Developer pass (skip if tester is self-correcting)
    if [[ "${skip_developer}" == "false" ]]; then
      local mode="implement"
      [[ "${attempt}" -gt 1 ]] && mode="fix"
      echo "[rework] Developer attempt ${attempt}/${max_retries} for ${story_id} (mode: ${mode})..."
      if ! developer_run "${workspace_root}" "${story_json}" "${mode}"; then
        echo "ERROR: Developer failed on attempt ${attempt}" >&2
        return 1
      fi
    fi
    skip_developer="false"

    # Tester verification
    echo "[rework] Tester verification for ${story_id}..."
    if tester_verify "${workspace_root}" "${story_json}" "${plan}" "${tech}"; then
      echo "[rework] All tests passing for ${story_id}"
      git -C "${workspace_root}" add -A > /dev/null 2>&1 || true
      git -C "${workspace_root}" commit -m "rework: [${story_id}] all tests passing" > /dev/null 2>&1 || true
      return 0
    fi

    # Check failure source
    local failure_source="implementation"
    [[ -f "${artifact_dir}/failure_source.txt" ]] && failure_source=$(cat "${artifact_dir}/failure_source.txt")

    if [[ "${failure_source}" == "test" ]]; then
      echo "[rework] Test failure is in test logic — tester self-correcting..."
      if tester_fix "${workspace_root}" "${story_json}" "${plan}" "${tech}"; then
        skip_developer="true"
      fi
    else
      echo "[rework] Test failure is in implementation — developer will retry..."
    fi
  done

  echo "ERROR: Rework loop exhausted (${max_retries} attempts) for ${story_id}" >&2
  mkdir -p "${artifact_dir}"
  printf '{"story_id":"%s","retries":%d,"reason":"rework limit exceeded"}\n' \
    "${story_id}" "${max_retries}" > "${artifact_dir}/retry_exceeded.json"
  return 1
}

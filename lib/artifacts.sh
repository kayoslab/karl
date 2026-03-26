#!/usr/bin/env bash
# lib/artifacts.sh - Structured artifact persistence and validation (US-017)

set -euo pipefail

# Registry of expected artifacts per ticket (plan, review, architect, tests, implementation, deployment)
KARL_EXPECTED_ARTIFACTS=(
  plan.json
  review.json
  architect.json
  tests.json
  developer.json
  deploy.json
  merge_check.json
)

# artifacts_dir <workspace_root> <ticket_id>
# Prints the artifact directory path for the given ticket.
artifacts_dir() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  printf '%s\n' "${workspace_root}/Output/${ticket_id}"
}

# artifacts_ensure_dir <workspace_root> <ticket_id>
# Creates the artifact directory for the given ticket if it does not exist.
artifacts_ensure_dir() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local dir
  dir=$(artifacts_dir "${workspace_root}" "${ticket_id}")
  mkdir -p "${dir}"
  echo "[artifacts] ensured artifact directory: ${dir}"
}

# artifacts_list <workspace_root> <ticket_id>
# Prints basenames of *.json artifact files for the given ticket; empty if none.
artifacts_list() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local dir="${workspace_root}/Output/${ticket_id}"
  if [[ ! -d "${dir}" ]]; then
    return 0
  fi
  local f
  for f in "${dir}"/*.json; do
    [[ -f "${f}" ]] && printf '%s\n' "$(basename "${f}")"
  done
  return 0
}

# artifacts_read <workspace_root> <ticket_id> <filename>
# Prints the contents of the named artifact; returns 1 if not found.
artifacts_read() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local filename="${3:?filename required}"
  local path="${workspace_root}/Output/${ticket_id}/${filename}"
  if [[ ! -f "${path}" ]]; then
    echo "ERROR: artifact not found: ${path}" >&2
    return 1
  fi
  cat "${path}"
}

# artifacts_validate_complete <workspace_root> <ticket_id>
# Returns 0 if all KARL_EXPECTED_ARTIFACTS are present; 1 otherwise.
# Prints missing artifact names on failure, success message on success.
artifacts_validate_complete() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local dir="${workspace_root}/Output/${ticket_id}"
  local missing=()
  local f
  for f in "${KARL_EXPECTED_ARTIFACTS[@]}"; do
    if [[ ! -f "${dir}/${f}" ]]; then
      missing+=("${f}")
    fi
  done
  if [[ "${#missing[@]}" -gt 0 ]]; then
    echo "Missing artifacts for ${ticket_id}: ${missing[*]}"
    return 1
  fi
  echo "All artifacts present for ${ticket_id}"
  return 0
}

# artifacts_summarize <workspace_root> <ticket_id>
# Prints a JSON summary: ticket_id, artifact_dir, complete, present[], missing[], adr_count.
artifacts_summarize() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local dir="${workspace_root}/Output/${ticket_id}"
  local adr_dir="${workspace_root}/Output/ADR"

  local present_json="[]"
  local missing_json="[]"
  local f
  for f in "${KARL_EXPECTED_ARTIFACTS[@]}"; do
    if [[ -f "${dir}/${f}" ]]; then
      present_json=$(printf '%s' "${present_json}" | jq --arg v "${f}" '. + [$v]')
    else
      missing_json=$(printf '%s' "${missing_json}" | jq --arg v "${f}" '. + [$v]')
    fi
  done

  local complete="false"
  if [[ "$(printf '%s' "${missing_json}" | jq 'length')" -eq 0 ]]; then
    complete="true"
  fi

  local adr_count=0
  if [[ -d "${adr_dir}" ]]; then
    adr_count=$(find "${adr_dir}" -maxdepth 1 -name "*.md" | wc -l | tr -d ' ')
  fi

  jq -n \
    --arg ticket_id "${ticket_id}" \
    --arg artifact_dir "${dir}" \
    --argjson complete "${complete}" \
    --argjson present "${present_json}" \
    --argjson missing "${missing_json}" \
    --argjson adr_count "${adr_count}" \
    '{ticket_id: $ticket_id, artifact_dir: $artifact_dir, complete: $complete, present: $present, missing: $missing, adr_count: $adr_count}'
}

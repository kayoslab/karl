#!/usr/bin/env bash
# subagent.sh - Thin wrapper for invoking Claude Code subagents
#
# When a JSON schema is provided, the call uses --json-schema + --output-format
# json and extracts the CLI's structured_output field. The CLI enforces the
# schema at the model level, so no post-hoc validation or normalization is
# needed. Non-schema calls return plain text (e.g. the tech agent's markdown).

set -euo pipefail

# Max retries and backoff for rate-limited requests
KARL_RATE_LIMIT_MAX_RETRIES="${KARL_RATE_LIMIT_MAX_RETRIES:-5}"
KARL_RATE_LIMIT_BACKOFF_BASE="${KARL_RATE_LIMIT_BACKOFF_BASE:-30}"

# _subagent_check_limit <text>
# Returns 0 if text contains a rate/usage limit indicator, 1 otherwise.
_subagent_check_limit() {
  local text="${1:-}"
  [[ -z "${text}" ]] && return 1

  local lower
  lower=$(printf '%s' "${text}" | tr '[:upper:]' '[:lower:]')

  if [[ "${lower}" == *"hit your limit"* ]] || \
     [[ "${lower}" == *"hit the limit"* ]] || \
     [[ "${lower}" == *"you've hit"*"limit"* ]] || \
     [[ "${lower}" == *"rate"*"limit"* ]] || \
     [[ "${lower}" == *"rate_limit"* ]] || \
     [[ "${lower}" == *"too many requests"* ]] || \
     [[ "${lower}" == *"429"* ]] || \
     [[ "${lower}" == *"overloaded"* ]] || \
     [[ "${lower}" == *"resource_exhausted"* ]] || \
     [[ "${lower}" == *"quota"*"exceeded"* ]] || \
     [[ "${lower}" == *"out of"*"usage"* ]]; then
    return 0
  fi

  return 1
}

# subagent_invoke <agent_name> <prompt_text> [json_schema]
# Invokes a Claude Code subagent in headless mode with tool access.
# Without a schema: returns plain text from the agent's `result` field.
# With a schema: forces --output-format json and extracts `structured_output`,
# which the CLI guarantees conforms to the schema.
# Returns 0 on success, 1 on failure, 2 on rate limit exhaustion.
subagent_invoke() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"
  local json_schema="${3:-}"

  local attempt=0
  local max_retries="${KARL_RATE_LIMIT_MAX_RETRIES}"
  local backoff_base="${KARL_RATE_LIMIT_BACKOFF_BASE}"

  local use_schema=false
  [[ -n "${json_schema}" ]] && use_schema=true

  while true; do
    local response="" stderr_file rc=0
    stderr_file=$(mktemp)

    if [[ "${use_schema}" == "true" ]]; then
      local raw_envelope=""
      if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
        raw_envelope=$(claude --agent "${agent_name}" --print --output-format json \
          --dangerously-skip-permissions \
          --json-schema "${json_schema}" \
          -p "${prompt_text}" 2> >(tee "${stderr_file}" >&2)) || rc=$?
      else
        raw_envelope=$(claude --agent "${agent_name}" --print --output-format json \
          --dangerously-skip-permissions \
          --json-schema "${json_schema}" \
          -p "${prompt_text}" 2>"${stderr_file}") || rc=$?
      fi
      if [[ "${rc}" -eq 0 ]] && [[ -n "${raw_envelope}" ]]; then
        response=$(printf '%s' "${raw_envelope}" | jq -rc '.structured_output // empty' 2>/dev/null) || response=""
      fi
    elif [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
      response=$(claude --agent "${agent_name}" --print --output-format text \
        --dangerously-skip-permissions \
        -p "${prompt_text}" 2> >(tee "${stderr_file}" >&2)) || rc=$?
    else
      response=$(claude --agent "${agent_name}" --print --output-format text \
        --dangerously-skip-permissions \
        -p "${prompt_text}" 2>"${stderr_file}") || rc=$?
    fi

    local stderr_output=""
    [[ -f "${stderr_file}" ]] && stderr_output=$(cat "${stderr_file}")
    rm -f "${stderr_file}"

    # Detect rate limits in both stdout and stderr
    local combined="${response}${stderr_output}"
    if _subagent_check_limit "${combined}"; then
      attempt=$((attempt + 1))
      if [[ "${attempt}" -ge "${max_retries}" ]]; then
        echo "ERROR: Rate limit persists after ${max_retries} retries for ${agent_name}" >&2
        return 2
      fi
      local wait_time=$((backoff_base * (2 ** (attempt - 1))))
      [[ "${wait_time}" -gt 300 ]] && wait_time=300
      echo "[rate_limit] ${agent_name} hit limit — waiting ${wait_time}s (attempt ${attempt}/${max_retries})" >&2
      sleep "${wait_time}"
      continue
    fi

    if [[ "${rc}" -eq 0 ]]; then
      # Empty response with rc=0 usually indicates a silent rate limit
      local trimmed
      trimmed=$(printf '%s' "${response}" | tr -d '[:space:]')
      if [[ -z "${trimmed}" ]]; then
        attempt=$((attempt + 1))
        if [[ "${attempt}" -ge "${max_retries}" ]]; then
          echo "ERROR: ${agent_name} returned empty response after ${max_retries} retries" >&2
          return 2
        fi
        local wait_time=$((backoff_base * (2 ** (attempt - 1))))
        [[ "${wait_time}" -gt 300 ]] && wait_time=300
        echo "[rate_limit] ${agent_name} returned empty response — waiting ${wait_time}s (attempt ${attempt}/${max_retries})" >&2
        sleep "${wait_time}"
        continue
      fi
      printf '%s' "${response}"
      return 0
    fi

    if [[ "${KARL_VERBOSE:-false}" == "true" ]] && [[ -n "${stderr_output}" ]]; then
      echo "ERROR: ${agent_name} failed: ${stderr_output}" >&2
    fi
    return 1
  done
}

# subagent_invoke_json <agent_name> <prompt_text> <json_schema>
# Invokes a subagent with a schema. The response is already valid JSON
# conforming to the schema (CLI-enforced). Prints it to stdout.
# Returns 1 on failure, 2 on rate limit exhaustion.
subagent_invoke_json() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"
  local json_schema="${3:?json_schema required — use subagent_invoke for free-form text}"

  subagent_invoke "${agent_name}" "${prompt_text}" "${json_schema}"
}

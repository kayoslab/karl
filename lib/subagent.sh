#!/usr/bin/env bash
# subagent.sh - Thin wrapper for invoking Claude Code subagents

set -euo pipefail

# Max retries and backoff for rate-limited requests
KARL_RATE_LIMIT_MAX_RETRIES="${KARL_RATE_LIMIT_MAX_RETRIES:-5}"
KARL_RATE_LIMIT_BACKOFF_BASE="${KARL_RATE_LIMIT_BACKOFF_BASE:-30}"

# _subagent_check_limit <text>
# Checks if text contains rate/usage limit indicators.
# Handles CLI messages like "You've hit your limit · resets 10am"
# and API errors like "rate_limit_error" or HTTP 429.
# Returns 0 if limit detected, 1 otherwise.
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

# _subagent_validate_schema <json> <schema>
# Validates that JSON has all required fields from the schema.
# Returns 0 if valid, 1 if missing required fields.
# Prints comma-separated list of missing fields to stdout on failure.
_subagent_validate_schema() {
  local json="${1}"
  local schema="${2}"

  local required_fields
  required_fields=$(printf '%s' "${schema}" | jq -r '.required // [] | .[]' 2>/dev/null) || return 0

  [[ -z "${required_fields}" ]] && return 0

  local missing=""
  local field
  while IFS= read -r field; do
    [[ -z "${field}" ]] && continue
    if ! printf '%s' "${json}" | jq -e --arg f "${field}" 'has($f)' > /dev/null 2>&1; then
      [[ -n "${missing}" ]] && missing="${missing}, "
      missing="${missing}${field}"
    fi
  done <<< "${required_fields}"

  if [[ -n "${missing}" ]]; then
    printf '%s' "${missing}"
    return 1
  fi
  return 0
}

# subagent_invoke <agent_name> <prompt_text> [json_schema]
# Invokes a Claude Code subagent in headless mode with tool access.
# Uses --dangerously-skip-permissions so agents can write files without prompting.
# When json_schema is provided, passes --json-schema to the CLI for structured output.
# Detects rate limit messages in both stdout and stderr, retries with backoff.
# Prints the agent's final text response to stdout.
# Returns 0 on success, 1 on failure, 2 on rate limit exhaustion.
subagent_invoke() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"
  local json_schema="${3:-}"

  local attempt=0
  local max_retries="${KARL_RATE_LIMIT_MAX_RETRIES}"
  local backoff_base="${KARL_RATE_LIMIT_BACKOFF_BASE}"

  # Build schema args
  local -a schema_args=()
  if [[ -n "${json_schema}" ]]; then
    schema_args=(--json-schema "${json_schema}")
  fi

  while true; do
    local response="" stderr_file rc=0
    stderr_file=$(mktemp)

    if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
      response=$(claude --agent "${agent_name}" --print --output-format text \
        --dangerously-skip-permissions \
        "${schema_args[@]+"${schema_args[@]}"}" \
        -p "${prompt_text}" 2> >(tee "${stderr_file}" >&2)) || rc=$?
    else
      response=$(claude --agent "${agent_name}" --print --output-format text \
        --dangerously-skip-permissions \
        "${schema_args[@]+"${schema_args[@]}"}" \
        -p "${prompt_text}" 2>"${stderr_file}") || rc=$?
    fi

    local stderr_output=""
    [[ -f "${stderr_file}" ]] && stderr_output=$(cat "${stderr_file}")
    rm -f "${stderr_file}"

    # Check for rate limit in both stdout (response) and stderr
    # The CLI outputs "You've hit your limit" on stdout with rc=0
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
      printf '%s' "${response}"
      return 0
    fi

    # Non-rate-limit failure — return immediately
    if [[ "${KARL_VERBOSE:-false}" == "true" ]] && [[ -n "${stderr_output}" ]]; then
      echo "ERROR: ${agent_name} failed: ${stderr_output}" >&2
    fi
    return 1
  done
}

# subagent_invoke_json <agent_name> <prompt_text> [json_schema]
# Invokes a subagent and extracts valid JSON from the response.
# When json_schema is provided, passes it to the CLI and validates the response.
# If required fields are missing, retries once with a correction prompt.
# Prints extracted JSON to stdout. Returns 1 if no valid JSON found.
# Returns 2 if rate-limited (propagated from subagent_invoke).
subagent_invoke_json() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"
  local json_schema="${3:-}"

  local raw rc=0
  raw=$(subagent_invoke "${agent_name}" "${prompt_text}" "${json_schema}") || rc=$?

  # Propagate rate limit (rc=2) distinctly from other failures
  [[ "${rc}" -ne 0 ]] && return "${rc}"

  # Extract JSON from the response
  local json
  json=$(_subagent_extract_json "${raw}") || {
    echo "ERROR: Could not extract valid JSON from ${agent_name} response" >&2
    if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
      echo "Raw response:" >&2
      printf '%s\n' "${raw}" >&2
    fi
    return 1
  }

  # If schema provided, validate required fields and retry on mismatch
  if [[ -n "${json_schema}" ]]; then
    local missing
    if missing=$(_subagent_validate_schema "${json}" "${json_schema}"); then
      # Valid — return as-is
      printf '%s' "${json}"
      return 0
    fi

    echo "[subagent] ${agent_name} response missing required fields: ${missing} — retrying with correction" >&2

    local correction_prompt="Your previous response was missing required fields: ${missing}.
Return ONLY a valid JSON object with these exact required fields: $(printf '%s' "${json_schema}" | jq -r '.required | join(", ")' 2>/dev/null).
Your previous response was: ${json}
Fix it and return the corrected JSON."

    local retry_raw retry_rc=0
    retry_raw=$(subagent_invoke "${agent_name}" "${correction_prompt}" "${json_schema}") || retry_rc=$?
    [[ "${retry_rc}" -ne 0 ]] && { printf '%s' "${json}"; return 0; }

    local retry_json
    retry_json=$(_subagent_extract_json "${retry_raw}") || { printf '%s' "${json}"; return 0; }

    # Use corrected response if it has the required fields, otherwise fall back to original
    if _subagent_validate_schema "${retry_json}" "${json_schema}" > /dev/null 2>&1; then
      printf '%s' "${retry_json}"
    else
      echo "[subagent] ${agent_name} correction still invalid — using original response" >&2
      printf '%s' "${json}"
    fi
    return 0
  fi

  printf '%s' "${json}"
  return 0
}

# _subagent_extract_json <raw_text>
# Extracts valid JSON from raw agent output.
# Tries: raw, code fences, last JSON block, first JSON block.
# Returns 0 with JSON on stdout, 1 if no valid JSON found.
_subagent_extract_json() {
  local raw="${1}"

  # Try raw response as-is (ideal case: agent returned pure JSON)
  if printf '%s' "${raw}" | jq . > /dev/null 2>&1; then
    printf '%s' "${raw}"
    return 0
  fi

  local extracted

  # Try to extract JSON from ```json ... ``` or ``` ... ``` fences
  extracted=$(printf '%s' "${raw}" | sed -n '/^```\(json\)\{0,1\}$/,/^```$/{ /^```/d; p; }')
  if [[ -n "${extracted}" ]] && printf '%s' "${extracted}" | jq . > /dev/null 2>&1; then
    printf '%s' "${extracted}"
    return 0
  fi

  # Try extracting the last JSON object (agents often write prose then JSON at the end)
  extracted=$(printf '%s' "${raw}" | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}' | sed -n '/^}/,/{/p' | awk '{lines[NR]=$0} END {for(i=NR;i>=1;i--) print lines[i]}')
  if [[ -n "${extracted}" ]] && printf '%s' "${extracted}" | jq . > /dev/null 2>&1; then
    printf '%s' "${extracted}"
    return 0
  fi

  # Try extracting first { ... } block
  extracted=$(printf '%s' "${raw}" | sed -n '/{/,/^}/p')
  if [[ -n "${extracted}" ]] && printf '%s' "${extracted}" | jq . > /dev/null 2>&1; then
    printf '%s' "${extracted}"
    return 0
  fi

  return 1
}

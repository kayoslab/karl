#!/usr/bin/env bash
# subagent.sh - Thin wrapper for invoking Claude Code subagents

set -euo pipefail

# Max retries and backoff for rate-limited requests
KARL_RATE_LIMIT_MAX_RETRIES="${KARL_RATE_LIMIT_MAX_RETRIES:-5}"
KARL_RATE_LIMIT_BACKOFF_BASE="${KARL_RATE_LIMIT_BACKOFF_BASE:-30}"

# _subagent_is_rate_limited <stderr_output> <exit_code>
# Returns 0 if the error looks like a rate limit, 1 otherwise.
_subagent_is_rate_limited() {
  local stderr_output="${1:-}"
  local exit_code="${2:-1}"

  # Non-zero exit with rate-limit indicators in stderr
  if [[ "${exit_code}" -ne 0 ]] && [[ -n "${stderr_output}" ]]; then
    local lower
    lower=$(printf '%s' "${stderr_output}" | tr '[:upper:]' '[:lower:]')
    if [[ "${lower}" == *"rate"*"limit"* ]] || \
       [[ "${lower}" == *"rate_limit"* ]] || \
       [[ "${lower}" == *"too many requests"* ]] || \
       [[ "${lower}" == *"429"* ]] || \
       [[ "${lower}" == *"overloaded"* ]] || \
       [[ "${lower}" == *"capacity"* ]]; then
      return 0
    fi
  fi

  return 1
}

# subagent_invoke <agent_name> <prompt_text>
# Invokes a Claude Code subagent in headless mode with tool access.
# Uses --dangerously-skip-permissions so agents can write files without prompting.
# Retries with exponential backoff on rate limit errors.
# Prints the agent's final text response to stdout.
# Returns 0 on success, 1 on failure, 2 on rate limit exhaustion.
subagent_invoke() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"

  local attempt=0
  local max_retries="${KARL_RATE_LIMIT_MAX_RETRIES}"
  local backoff_base="${KARL_RATE_LIMIT_BACKOFF_BASE}"

  while true; do
    local response="" stderr_file rc=0
    stderr_file=$(mktemp)

    if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
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

    if [[ "${rc}" -eq 0 ]]; then
      printf '%s' "${response}"
      return 0
    fi

    # Check if this is a rate limit error
    if _subagent_is_rate_limited "${stderr_output}" "${rc}"; then
      attempt=$((attempt + 1))
      if [[ "${attempt}" -ge "${max_retries}" ]]; then
        echo "ERROR: Rate limit persists after ${max_retries} retries for ${agent_name}" >&2
        return 2
      fi
      local wait_time=$((backoff_base * (2 ** (attempt - 1))))
      # Cap at 5 minutes
      [[ "${wait_time}" -gt 300 ]] && wait_time=300
      echo "[rate_limit] ${agent_name} rate-limited — waiting ${wait_time}s (attempt ${attempt}/${max_retries})" >&2
      sleep "${wait_time}"
      continue
    fi

    # Non-rate-limit failure — return immediately
    if [[ "${KARL_VERBOSE:-false}" == "true" ]] && [[ -n "${stderr_output}" ]]; then
      echo "ERROR: ${agent_name} failed: ${stderr_output}" >&2
    fi
    return 1
  done
}

# subagent_invoke_json <agent_name> <prompt_text>
# Invokes a subagent and extracts valid JSON from the response.
# Handles markdown code fences and prose-wrapped responses.
# Prints extracted JSON to stdout. Returns 1 if no valid JSON found.
# Returns 2 if rate-limited (propagated from subagent_invoke).
subagent_invoke_json() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"

  local raw rc=0
  raw=$(subagent_invoke "${agent_name}" "${prompt_text}") || rc=$?

  # Propagate rate limit (rc=2) distinctly from other failures
  [[ "${rc}" -ne 0 ]] && return "${rc}"

  local extracted

  # Try raw response as-is (ideal case: agent returned pure JSON)
  if printf '%s' "${raw}" | jq . > /dev/null 2>&1; then
    printf '%s' "${raw}"
    return 0
  fi

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

  echo "ERROR: Could not extract valid JSON from ${agent_name} response" >&2
  if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
    echo "Raw response:" >&2
    printf '%s\n' "${raw}" >&2
  fi
  return 1
}

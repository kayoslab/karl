#!/usr/bin/env bash
# subagent.sh - Thin wrapper for invoking Claude Code subagents

set -euo pipefail

# subagent_invoke <agent_name> <prompt_text>
# Invokes a Claude Code subagent in headless mode with tool access.
# Uses --dangerously-skip-permissions so agents can write files without prompting.
# Prints the agent's final text response to stdout.
# Returns 0 on success, 1 on failure.
subagent_invoke() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"

  local response
  if [[ "${KARL_VERBOSE:-false}" == "true" ]]; then
    response=$(claude --agent "${agent_name}" --print --output-format text \
      --dangerously-skip-permissions \
      -p "${prompt_text}") || return 1
  else
    response=$(claude --agent "${agent_name}" --print --output-format text \
      --dangerously-skip-permissions \
      -p "${prompt_text}" 2>/dev/null) || return 1
  fi

  printf '%s' "${response}"
}

# subagent_invoke_json <agent_name> <prompt_text>
# Invokes a subagent and extracts valid JSON from the response.
# Handles markdown code fences and prose-wrapped responses.
# Prints extracted JSON to stdout. Returns 1 if no valid JSON found.
subagent_invoke_json() {
  local agent_name="${1:?agent_name required}"
  local prompt_text="${2:?prompt_text required}"

  local raw
  raw=$(subagent_invoke "${agent_name}" "${prompt_text}") || return 1

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
  extracted=$(printf '%s' "${raw}" | tac | sed -n '/^}/,/{/p' | tac)
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

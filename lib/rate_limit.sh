#!/usr/bin/env bash
# lib/rate_limit.sh - Rate limit detection and retry logic (US-020)

: "${KARL_RATE_LIMIT_BACKOFF_BASE:=60}"
: "${KARL_RATE_LIMIT_MAX_RETRIES:=5}"

# rate_limit_detect <text>
# Returns 0 if text indicates a rate limit or quota error, 1 otherwise.
rate_limit_detect() {
  local text="${1:-}"
  printf '%s' "${text}" | grep -qiE 'rate.limit|quota exceeded|too many requests|usage limit|retry.after'
}

# rate_limit_parse_wait <text>
# Prints the number of seconds to wait extracted from text, or 0 if not found.
rate_limit_parse_wait() {
  local text="${1:-}"

  # Try seconds: "retry after N seconds" or "wait N seconds"
  local secs
  secs=$(printf '%s' "${text}" | grep -oiE '(retry after|wait) [0-9]+ seconds?' | grep -oE '[0-9]+' | head -1)
  if [[ -n "${secs}" ]]; then
    printf '%d' "${secs}"
    return 0
  fi

  # Try minutes: "retry after N minutes" or "wait N minutes"
  local mins
  mins=$(printf '%s' "${text}" | grep -oiE '(retry after|wait) [0-9]+ minutes?' | grep -oE '[0-9]+' | head -1)
  if [[ -n "${mins}" ]]; then
    local secs_total=$(( mins * 60 ))
    printf '%d' "${secs_total}"
    return 0
  fi

  printf '0'
}

# rate_limit_backoff <attempt>
# Sleeps for KARL_RATE_LIMIT_BACKOFF_BASE * attempt seconds, logs to stderr.
rate_limit_backoff() {
  local attempt="${1:?attempt required}"
  local base="${KARL_RATE_LIMIT_BACKOFF_BASE:-60}"
  local wait_secs=$(( base * attempt ))
  printf '[rate_limit] backoff: waiting %ds before retry (attempt %d)\n' "${wait_secs}" "${attempt}" >&2
  if [[ "${wait_secs}" -gt 0 ]]; then
    sleep "${wait_secs}"
  fi
}

# claude_invoke [args...]
# Wraps 'claude' with rate-limit detection and retry. Reads prompt from stdin.
# Rate-limit retries default to unlimited (0) — the loop waits for the quota to reset.
# Set KARL_RATE_LIMIT_MAX_RETRIES to a positive integer to cap retries.
claude_invoke() {
  local max_retries="${KARL_RATE_LIMIT_MAX_RETRIES:-0}"
  local stdin_data
  stdin_data=$(cat)

  local attempt=1
  while [[ "${max_retries}" -eq 0 ]] || [[ "${attempt}" -le "${max_retries}" ]]; do
    local output exit_code tmp_stderr
    tmp_stderr=$(mktemp)
    output=$(printf '%s\n' "${stdin_data}" | claude --dangerously-skip-permissions "$@" 2>"${tmp_stderr}")
    exit_code=$?
    local stderr_text
    stderr_text=$(cat "${tmp_stderr}")
    rm -f "${tmp_stderr}"

    if [[ "${exit_code}" -eq 0 ]]; then
      # Strip markdown code fences, then extract the outermost JSON object/array.
      # This handles claude responses that include prose before or after the JSON.
      output=$(printf '%s\n' "${output}" | sed '/^[[:space:]]*```/d')
      output=$(printf '%s' "${output}" | python3 -c "
import sys, json
text = sys.stdin.read()
# Try direct parse first
try:
    json.loads(text.strip())
    sys.stdout.write(text.strip())
    sys.exit(0)
except Exception:
    pass
# Extract from outermost { } or [ ]
for open_ch, close_ch in [('{', '}'), ('[', ']')]:
    s = text.find(open_ch)
    e = text.rfind(close_ch) + 1
    if s >= 0 and e > s:
        candidate = text[s:e]
        try:
            json.loads(candidate)
            sys.stdout.write(candidate)
            sys.exit(0)
        except Exception:
            pass
# Fall back to original stripped text
sys.stdout.write(text.strip())
" 2>/dev/null || printf '%s' "${output}")
      printf '%s\n' "${output}"
      return 0
    fi

    # Check both stdout and stderr for rate limit indicators
    local combined="${output} ${stderr_text}"
    if rate_limit_detect "${combined}"; then
      printf '[rate_limit] Rate limit detected (attempt %d) — waiting for reset\n' "${attempt}" >&2
      local wait_secs
      wait_secs=$(rate_limit_parse_wait "${combined}")
      if [[ "${wait_secs}" -gt 0 ]]; then
        printf '[rate_limit] Waiting %ds as requested by API\n' "${wait_secs}" >&2
        sleep "${wait_secs}"
      else
        rate_limit_backoff "${attempt}"
      fi
      attempt=$((attempt + 1))
    else
      # Non-rate-limit failure — return immediately
      printf '%s\n' "${output}"
      if [[ -n "${stderr_text}" ]]; then
        printf '%s\n' "${stderr_text}" >&2
      fi
      return "${exit_code}"
    fi
  done

  printf '[rate_limit] Max retries (%d) exceeded\n' "${max_retries}" >&2
  return 1
}

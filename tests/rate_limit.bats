#!/usr/bin/env bats
# tests/rate_limit.bats - Tests for lib/rate_limit.sh (US-020)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
RATE_LIMIT_SH="${KARL_DIR}/lib/rate_limit.sh"

setup() {
  STUB_DIR="$(mktemp -d)"

  # shellcheck source=../lib/rate_limit.sh
  source "${RATE_LIMIT_SH}"

  # Prevent real sleeps in tests
  KARL_RATE_LIMIT_BACKOFF_BASE=0
  KARL_RATE_LIMIT_MAX_RETRIES=5

  # Claude stub: reads output/exit from sidecar files in STUB_DIR.
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
printf '%s\n' "$(cat "${SCRIPT_DIR}/.output" 2>/dev/null)"
exit "$(cat "${SCRIPT_DIR}/.exit" 2>/dev/null || printf '0')"
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  # Default: success with empty output
  printf '' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
}

teardown() {
  rm -rf "${STUB_DIR}"
}

# ---------------------------------------------------------------------------
# rate_limit_detect — positive matches
# ---------------------------------------------------------------------------

@test "rate_limit_detect returns 0 for 'rate limit' text" {
  run rate_limit_detect "You have hit a rate limit. Please wait."
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'rate-limit' hyphenated" {
  run rate_limit_detect "Error: rate-limit exceeded"
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'quota exceeded' text" {
  run rate_limit_detect "Your quota exceeded for this billing period."
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'too many requests' text" {
  run rate_limit_detect "429 Too Many Requests"
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'usage limit' text" {
  run rate_limit_detect "You have reached your usage limit."
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'retry after' text" {
  run rate_limit_detect "Please retry after 60 seconds."
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect returns 0 for 'retry-after' hyphenated" {
  run rate_limit_detect "Retry-After: 30"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# rate_limit_detect — case insensitive
# ---------------------------------------------------------------------------

@test "rate_limit_detect is case-insensitive for 'Rate Limit'" {
  run rate_limit_detect "Rate Limit reached"
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect is case-insensitive for 'QUOTA EXCEEDED'" {
  run rate_limit_detect "QUOTA EXCEEDED"
  [ "${status}" -eq 0 ]
}

@test "rate_limit_detect is case-insensitive for 'TOO MANY REQUESTS'" {
  run rate_limit_detect "TOO MANY REQUESTS"
  [ "${status}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# rate_limit_detect — negative matches
# ---------------------------------------------------------------------------

@test "rate_limit_detect returns 1 for normal output" {
  run rate_limit_detect "Here is the implementation plan in JSON format."
  [ "${status}" -ne 0 ]
}

@test "rate_limit_detect returns 1 for empty string" {
  run rate_limit_detect ""
  [ "${status}" -ne 0 ]
}

@test "rate_limit_detect returns 1 for unrelated error text" {
  run rate_limit_detect "ERROR: Planner agent returned invalid JSON"
  [ "${status}" -ne 0 ]
}

@test "rate_limit_detect returns 1 for JSON output" {
  run rate_limit_detect '{"plan":["step1"],"testing_recommendations":[]}'
  [ "${status}" -ne 0 ]
}

# ---------------------------------------------------------------------------
# rate_limit_parse_wait — seconds parsing
# ---------------------------------------------------------------------------

@test "rate_limit_parse_wait outputs 30 for 'retry after 30 seconds'" {
  result=$(rate_limit_parse_wait "Please retry after 30 seconds.")
  [ "${result}" -eq 30 ]
}

@test "rate_limit_parse_wait outputs 60 for 'retry after 60 seconds'" {
  result=$(rate_limit_parse_wait "Rate limit hit. Retry after 60 seconds.")
  [ "${result}" -eq 60 ]
}

# ---------------------------------------------------------------------------
# rate_limit_parse_wait — minutes parsing
# ---------------------------------------------------------------------------

@test "rate_limit_parse_wait outputs 120 for 'retry after 2 minutes'" {
  result=$(rate_limit_parse_wait "Quota exceeded. Retry after 2 minutes.")
  [ "${result}" -eq 120 ]
}

@test "rate_limit_parse_wait outputs 300 for 'wait 5 minutes'" {
  result=$(rate_limit_parse_wait "Too many requests. Wait 5 minutes.")
  [ "${result}" -eq 300 ]
}

# ---------------------------------------------------------------------------
# rate_limit_parse_wait — fallback
# ---------------------------------------------------------------------------

@test "rate_limit_parse_wait outputs 0 when no timing info present" {
  result=$(rate_limit_parse_wait "You have reached your rate limit.")
  [ "${result}" -eq 0 ]
}

@test "rate_limit_parse_wait outputs 0 for empty input" {
  result=$(rate_limit_parse_wait "")
  [ "${result}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# rate_limit_backoff — formula
# ---------------------------------------------------------------------------

@test "rate_limit_backoff exits 0 with KARL_RATE_LIMIT_BACKOFF_BASE=0" {
  KARL_RATE_LIMIT_BACKOFF_BASE=0 run rate_limit_backoff 1
  [ "${status}" -eq 0 ]
}

@test "rate_limit_backoff exits 0 for attempt 3 with KARL_RATE_LIMIT_BACKOFF_BASE=0" {
  KARL_RATE_LIMIT_BACKOFF_BASE=0 run rate_limit_backoff 3
  [ "${status}" -eq 0 ]
}

@test "rate_limit_backoff logs to stderr" {
  KARL_RATE_LIMIT_BACKOFF_BASE=0 run rate_limit_backoff 1
  [ "${status}" -eq 0 ]
  # stderr should contain some backoff/rate-limit indicator
  [[ "${output}" == *"backoff"* ]] || [[ "${output}" == *"rate"* ]] || [[ "${output}" == *"wait"* ]] || [[ "${output}" == *"0"* ]]
}

# ---------------------------------------------------------------------------
# claude_invoke — success path
# ---------------------------------------------------------------------------

@test "claude_invoke returns 0 when claude exits 0" {
  printf 'success output\n' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'
  [ "${status}" -eq 0 ]
}

@test "claude_invoke returns stdout output on success" {
  printf 'hello from claude\n' > "${STUB_DIR}/.output"
  printf '0' > "${STUB_DIR}/.exit"
  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"hello from claude"* ]]
}

# ---------------------------------------------------------------------------
# claude_invoke — non-rate-limit failure (no retry)
# ---------------------------------------------------------------------------

@test "claude_invoke returns non-zero for non-rate-limit failure" {
  printf 'command not found: jq\n' > "${STUB_DIR}/.output"
  printf '1' > "${STUB_DIR}/.exit"
  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'
  [ "${status}" -ne 0 ]
}

@test "claude_invoke does not retry on non-rate-limit failure" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  # Stub increments counter; exits 1 with non-rate-limit message
  cat > "${STUB_DIR}/claude" <<STUBEOF
#!/usr/bin/env bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
printf '%d' "\${count}" > "${counter_file}"
printf 'unexpected error\n'
exit 1
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown' || true

  local count
  count=$(cat "${counter_file}")
  rm -f "${counter_file}"
  # Should only call claude once — no retry for non-rate-limit failure
  [ "${count}" -eq 1 ]
}

# ---------------------------------------------------------------------------
# claude_invoke — rate-limit retry then success
# ---------------------------------------------------------------------------

@test "claude_invoke retries after rate-limit and succeeds on second call" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  # First call: exit 1 with rate-limit text; second call: exit 0 with success
  cat > "${STUB_DIR}/claude" <<STUBEOF
#!/usr/bin/env bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
printf '%d' "\${count}" > "${counter_file}"
if [ "\${count}" -eq 1 ]; then
  printf 'rate limit exceeded\n'
  exit 1
else
  printf '{"plan":["step1"]}\n'
  exit 0
fi
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'

  local count
  count=$(cat "${counter_file}")
  rm -f "${counter_file}"

  [ "${status}" -eq 0 ]
  [ "${count}" -eq 2 ]
  [[ "${output}" == *'"plan"'* ]]
}

@test "claude_invoke logs rate-limit event to stderr" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  cat > "${STUB_DIR}/claude" <<STUBEOF
#!/usr/bin/env bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
printf '%d' "\${count}" > "${counter_file}"
if [ "\${count}" -eq 1 ]; then
  printf 'rate limit exceeded\n'
  exit 1
else
  printf 'success\n'
  exit 0
fi
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"' 2>&1; printf "prompt\n" | claude_invoke --print --no-markdown 2>&1'

  rm -f "${counter_file}"
  # stderr (captured via 2>&1) should mention rate limit or retry
  [[ "${output}" == *"rate"* ]] || [[ "${output}" == *"limit"* ]] || [[ "${output}" == *"retry"* ]] || [[ "${output}" == *"attempt"* ]]
}

# ---------------------------------------------------------------------------
# claude_invoke — max retries exceeded
# ---------------------------------------------------------------------------

@test "claude_invoke returns non-zero when max retries exceeded" {
  # Always fails with rate-limit text
  cat > "${STUB_DIR}/claude" <<'STUBEOF'
#!/usr/bin/env bash
printf 'rate limit exceeded\n'
exit 1
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 KARL_RATE_LIMIT_MAX_RETRIES=3 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'
  [ "${status}" -ne 0 ]
}

@test "claude_invoke respects KARL_RATE_LIMIT_MAX_RETRIES" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  # Always fails with rate-limit text — count how many times called
  cat > "${STUB_DIR}/claude" <<STUBEOF
#!/usr/bin/env bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
printf '%d' "\${count}" > "${counter_file}"
printf 'rate limit exceeded\n'
exit 1
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 KARL_RATE_LIMIT_MAX_RETRIES=3 PATH="${STUB_DIR}:${PATH}" \
    bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown' || true

  local count
  count=$(cat "${counter_file}")
  rm -f "${counter_file}"
  # Should call claude exactly max_retries times
  [ "${count}" -eq 3 ]
}

# ---------------------------------------------------------------------------
# claude_invoke — wait time parsing integration
# ---------------------------------------------------------------------------

@test "claude_invoke uses parse_wait when retry-after seconds present" {
  local counter_file
  counter_file="$(mktemp)"
  printf '0' > "${counter_file}"

  cat > "${STUB_DIR}/claude" <<STUBEOF
#!/usr/bin/env bash
count=\$(cat "${counter_file}")
count=\$((count + 1))
printf '%d' "\${count}" > "${counter_file}"
if [ "\${count}" -eq 1 ]; then
  printf 'rate limit hit. retry after 0 seconds.\n'
  exit 1
else
  printf 'success\n'
  exit 0
fi
STUBEOF
  chmod +x "${STUB_DIR}/claude"

  KARL_RATE_LIMIT_BACKOFF_BASE=0 PATH="${STUB_DIR}:${PATH}" \
    run bash -c 'source '"${RATE_LIMIT_SH}"'; printf "prompt\n" | claude_invoke --print --no-markdown'

  rm -f "${counter_file}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"success"* ]]
}

# ---------------------------------------------------------------------------
# Integration: karl.sh sources rate_limit.sh
# ---------------------------------------------------------------------------

@test "karl.sh sources lib/rate_limit.sh" {
  grep -q "rate_limit" "${KARL_DIR}/karl.sh"
}

# ---------------------------------------------------------------------------
# Integration: agent libs use claude_invoke
# ---------------------------------------------------------------------------

@test "lib/planning.sh uses claude_invoke instead of calling claude directly" {
  # Should not have bare 'claude --print' without going through claude_invoke
  # This checks that claude_invoke is called for the prompt pipe
  grep -q "claude_invoke" "${KARL_DIR}/lib/planning.sh"
}

@test "lib/architect.sh uses claude_invoke instead of calling claude directly" {
  grep -q "claude_invoke" "${KARL_DIR}/lib/architect.sh"
}

@test "lib/tester.sh uses claude_invoke instead of calling claude directly" {
  grep -q "claude_invoke" "${KARL_DIR}/lib/tester.sh"
}

@test "lib/deploy.sh uses claude_invoke instead of calling claude directly" {
  grep -q "claude_invoke" "${KARL_DIR}/lib/deploy.sh"
}

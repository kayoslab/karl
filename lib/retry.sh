#!/usr/bin/env bash
# retry.sh - Per-ticket retry counter management for karl

set -euo pipefail

# _retry_file <workspace_root> <ticket_id>
# Returns path to the retry counter file.
_retry_file() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  printf '%s/Output/%s/retry_count' "${workspace_root}" "${ticket_id}"
}

# retry_init <workspace_root> <ticket_id>
# Initialise the retry counter to 0 for a ticket.
retry_init() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  mkdir -p "${workspace_root}/Output/${ticket_id}"
  printf '0' > "$(_retry_file "${workspace_root}" "${ticket_id}")"
}

# retry_get_count <workspace_root> <ticket_id>
# Print the current retry count.
retry_get_count() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local f
  f="$(_retry_file "${workspace_root}" "${ticket_id}")"
  if [[ -f "${f}" ]]; then
    cat "${f}"
  else
    printf '0'
  fi
}

# retry_increment <workspace_root> <ticket_id>
# Increment the retry counter by 1.
retry_increment() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local count
  count=$(retry_get_count "${workspace_root}" "${ticket_id}")
  printf '%d' $(( count + 1 )) > "$(_retry_file "${workspace_root}" "${ticket_id}")"
}

# retry_check <workspace_root> <ticket_id> <max_retries>
# Returns 0 if count < max_retries (still within limit).
# Returns 1 if count >= max_retries (limit reached or exceeded).
retry_check() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local max_retries="${3:?max_retries required}"
  local count
  count=$(retry_get_count "${workspace_root}" "${ticket_id}")
  if [[ "${count}" -ge "${max_retries}" ]]; then
    return 1
  fi
  return 0
}

# retry_exceeded_persist <workspace_root> <ticket_id> <max_retries>
# Write Output/<ticket_id>/retry_exceeded.json with details about the failure.
retry_exceeded_persist() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local max_retries="${3:?max_retries required}"
  local count
  count=$(retry_get_count "${workspace_root}" "${ticket_id}")
  local outfile="${workspace_root}/Output/${ticket_id}/retry_exceeded.json"
  mkdir -p "${workspace_root}/Output/${ticket_id}"
  printf '{"ticket_id":"%s","max_retries":%d,"count":%d,"message":"Retry limit of %d reached for ticket %s. The developer/tester rework loop was stopped to prevent indefinite looping."}\n' \
    "${ticket_id}" "${max_retries}" "${count}" "${max_retries}" "${ticket_id}" \
    > "${outfile}"
}

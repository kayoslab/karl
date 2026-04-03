#!/usr/bin/env bash
# prd_claim.sh - Portable atomic ticket claiming via mkdir-based locks

set -euo pipefail

# _prd_lock_acquire <workspace_root>
# Spin on mkdir .prd.lockdir (POSIX-atomic) until acquired.
# Times out after ~30 seconds. Returns 0 on success, 1 on timeout.
_prd_lock_acquire() {
  local workspace_root="${1:?workspace_root required}"
  local lockdir="${workspace_root}/.prd.lockdir"
  local attempts=0
  local max_attempts=60

  while ! mkdir "${lockdir}" 2>/dev/null; do
    attempts=$((attempts + 1))
    if [[ "${attempts}" -ge "${max_attempts}" ]]; then
      echo "ERROR: Timed out waiting for PRD lock at ${lockdir}" >&2
      return 1
    fi
    sleep 0.5
  done

  return 0
}

# _prd_lock_release <workspace_root>
# Release the PRD lock by removing .prd.lockdir.
_prd_lock_release() {
  local workspace_root="${1:?workspace_root required}"
  local lockdir="${workspace_root}/.prd.lockdir"

  rmdir "${lockdir}" 2>/dev/null || true
}

# prd_claim_ticket <workspace_root> <ticket_id> <instance_id>
# Atomically set status="in_progress" for the given ticket.
# Returns 0 on success, 1 on failure.
prd_claim_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local instance_id="${3:?instance_id required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  # Check ticket is still available before claiming
  local current_status
  current_status=$(jq -r --arg id "${ticket_id}" \
    '(if type == "array" then . else .userStories end)
     | .[] | select(.id == $id)
     | if .status then .status
       elif .passes == true then "pass"
       else "available"
       end' \
    "${prd_file}" 2>/dev/null) || true

  if [[ "${current_status}" != "available" ]]; then
    _prd_lock_release "${workspace_root}"
    echo "ERROR: Ticket ${ticket_id} is not available (status: ${current_status})" >&2
    return 1
  fi

  local updated
  updated=$(jq --arg id "${ticket_id}" --arg inst "${instance_id}" \
    'if type == "array"
     then [.[] | if .id == $id then .status = "in_progress" | .claimed_by = $inst else . end]
     else .userStories = [.userStories[] | if .id == $id then .status = "in_progress" | .claimed_by = $inst else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Ticket ${ticket_id} claimed by instance ${instance_id}"
  return 0
}

# prd_release_ticket <workspace_root> <ticket_id>
# Set status="available" on failure (release the claim).
# Only releases if ticket is currently in_progress — never overwrites pass or fail.
# Returns 0 on success, 1 on failure.
prd_release_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  # Only release if currently in_progress — don't overwrite pass or fail
  local current_status
  current_status=$(jq -r --arg id "${ticket_id}" \
    '(if type == "array" then . else .userStories end)
     | .[] | select(.id == $id)
     | if .status then .status
       elif .passes == true then "pass"
       else "available"
       end' \
    "${prd_file}" 2>/dev/null) || true

  if [[ "${current_status}" != "in_progress" ]]; then
    _prd_lock_release "${workspace_root}"
    echo "[prd_claim] Ticket ${ticket_id} not released (status: ${current_status})"
    return 0
  fi

  local updated
  updated=$(jq --arg id "${ticket_id}" \
    'if type == "array"
     then [.[] | if .id == $id then .status = "available" | del(.claimed_by) else . end]
     else .userStories = [.userStories[] | if .id == $id then .status = "available" | del(.claimed_by) else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Ticket ${ticket_id} released"
  return 0
}

# prd_reset_in_progress <workspace_root>
# Reset all "in_progress" tickets back to "available".
# Called on startup to recover from a previous crash.
# Returns 0 on success, 1 on failure.
prd_reset_in_progress() {
  local workspace_root="${1:?workspace_root required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    return 0
  fi

  # Check if there are any in_progress tickets
  local count
  count=$(jq \
    '(if type == "array" then . else .userStories end)
     | [.[] | select(.status == "in_progress")] | length' \
    "${prd_file}" 2>/dev/null) || return 0

  if [[ "${count}" -eq 0 ]]; then
    return 0
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  local updated
  updated=$(jq \
    'if type == "array"
     then [.[] | if .status == "in_progress" then .status = "available" | del(.claimed_by) else . end]
     else .userStories = [.userStories[] | if .status == "in_progress" then .status = "available" | del(.claimed_by) else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Reset ${count} in-progress ticket(s) to available"
  return 0
}

# prd_reset_failed <workspace_root>
# Reset all "fail" tickets back to "available" so they can be retried.
# Called on startup to recover from previous run failures.
# Returns 0 on success, 1 on failure.
prd_reset_failed() {
  local workspace_root="${1:?workspace_root required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    return 0
  fi

  # Check if there are any failed tickets
  local count
  count=$(jq \
    '(if type == "array" then . else .userStories end)
     | [.[] | select(.status == "fail")] | length' \
    "${prd_file}" 2>/dev/null) || return 0

  if [[ "${count}" -eq 0 ]]; then
    return 0
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  local updated
  updated=$(jq \
    'if type == "array"
     then [.[] | if .status == "fail" then .status = "available" | del(.claimed_by) else . end]
     else .userStories = [.userStories[] | if .status == "fail" then .status = "available" | del(.claimed_by) else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Reset ${count} failed ticket(s) to available"
  return 0
}

# prd_fail_ticket <workspace_root> <ticket_id>
# Set status="fail" for the given ticket (permanent failure, not retryable).
# Returns 0 on success, 1 on failure.
prd_fail_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  local updated
  updated=$(jq --arg id "${ticket_id}" \
    'if type == "array"
     then [.[] | if .id == $id then .status = "fail" | del(.claimed_by) else . end]
     else .userStories = [.userStories[] | if .id == $id then .status = "fail" | del(.claimed_by) else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Ticket ${ticket_id} marked as failed"
  return 0
}

# prd_complete_ticket <workspace_root> <ticket_id>
# Set status="pass" and passes=true for the given ticket.
# Returns 0 on success, 1 on failure.
prd_complete_ticket() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"

  local prd_file="${workspace_root}/Input/prd.json"
  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  if ! _prd_lock_acquire "${workspace_root}"; then
    return 1
  fi

  local updated
  updated=$(jq --arg id "${ticket_id}" \
    'if type == "array"
     then [.[] | if .id == $id then .status = "pass" | .passes = true | del(.claimed_by) else . end]
     else .userStories = [.userStories[] | if .id == $id then .status = "pass" | .passes = true | del(.claimed_by) else . end]
     end' \
    "${prd_file}") || {
    _prd_lock_release "${workspace_root}"
    return 1
  }

  printf '%s\n' "${updated}" > "${prd_file}"
  _prd_lock_release "${workspace_root}"

  echo "[prd_claim] Ticket ${ticket_id} completed"
  return 0
}

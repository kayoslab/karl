#!/usr/bin/env bash
# lock.sh - Single-instance protection via LOCK file

set -euo pipefail

# lock_path <workspace_root>
# Prints the path to the LOCK file.
lock_path() {
  local root="${1:?workspace root required}"
  echo "${root}/LOCK"
}

# lock_exists <workspace_root>
# Returns 0 if LOCK file exists, 1 otherwise.
lock_exists() {
  local root="${1:?workspace root required}"
  [[ -f "$(lock_path "${root}")" ]]
}

# lock_acquire <workspace_root> [force]
# Creates the LOCK file with current PID.
# If LOCK already exists and force is not "true", prints ERROR and returns 1.
# If force is "true", removes existing LOCK, prints WARNING, then creates new one.
lock_acquire() {
  local root="${1:?workspace root required}"
  local force="${2:-false}"
  local lpath
  lpath="$(lock_path "${root}")"

  if [[ -f "${lpath}" ]]; then
    if [[ "${force}" == "true" ]]; then
      echo "WARNING: Forcing lock acquisition; removing existing LOCK at ${lpath}" >&2
      rm -f "${lpath}"
    else
      echo "ERROR: LOCK file exists at ${lpath}. Another instance may already be running." >&2
      echo "ERROR: Use --force-lock to override the stale lock." >&2
      return 1
    fi
  fi

  echo "$$" > "${lpath}"
  return 0
}

# lock_release <workspace_root>
# Removes the LOCK file. Idempotent — returns 0 even if already absent.
lock_release() {
  local root="${1:?workspace root required}"
  local lpath
  lpath="$(lock_path "${root}")"
  rm -f "${lpath}"
  return 0
}

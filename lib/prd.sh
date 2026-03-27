#!/usr/bin/env bash
# prd.sh - PRD parsing and ticket selection for karl

set -euo pipefail

# prd_validate <prd_file>
# Validates that the given file is valid JSON with a non-empty stories list.
# Accepts both formats:
#   - flat array:              [{...}, ...]
#   - object with userStories: {"userStories": [{...}, ...], ...}
# Returns 0 on success, 1 on failure with ERROR message to stderr.
prd_validate() {
  local prd_file="${1:?prd_file required}"

  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found: ${prd_file}" >&2
    return 1
  fi

  if ! jq empty "${prd_file}" 2>/dev/null; then
    echo "ERROR: prd.json is not valid JSON: ${prd_file}" >&2
    return 1
  fi

  local count
  count=$(jq 'if type == "array" then length else (.userStories // empty) | length end' \
    "${prd_file}" 2>/dev/null) || {
    echo "ERROR: prd.json missing userStories array: ${prd_file}" >&2
    return 1
  }

  if [[ -z "${count}" ]]; then
    echo "ERROR: prd.json missing userStories array: ${prd_file}" >&2
    return 1
  fi

  if [[ "${count}" -eq 0 ]]; then
    echo "ERROR: prd.json userStories array is empty: ${prd_file}" >&2
    return 1
  fi

  return 0
}

# prd_next_story <prd_file>
# Prints the unfinished story with the lowest numeric priority.
# A story is unfinished if: status is "available" (or absent with passes!=true),
# and it is not "in_progress" or "pass"/"fail".
# Stories with depends_on are skipped unless all dependencies have passed.
# Accepts both flat-array and { userStories: [...] } formats.
# Returns 0 and prints JSON object on success.
# Returns 2 if all stories pass (clean all-done exit).
# Returns 3 if no stories are available now but some are pending (in_progress/blocked).
# Returns 1 on validation error.
prd_next_story() {
  local prd_file="${1:?prd_file required}"

  prd_validate "${prd_file}" || return 1

  local story
  story=$(jq -c \
    '(if type == "array" then . else .userStories end) as $all
     | [ $all[]
         | . as $ticket
         # Derive effective status: explicit status field takes precedence,
         # then fall back to passes field for backward compat
         | (if .status then .status
            elif .passes == true then "pass"
            else "available"
            end) as $eff_status
         | select($eff_status == "available")
         # Filter out tickets whose dependencies have not all passed
         | select(
             (.depends_on // []) as $deps
             | if ($deps | length) == 0 then true
               else ($deps | all(. as $dep_id |
                 ($all[] | select(.id == $dep_id)
                  | (if .status then .status
                     elif .passes == true then "pass"
                     else "available"
                     end)) == "pass"))
               end
           )
       ]
     | sort_by(.priority)
     | first' \
    "${prd_file}" 2>/dev/null)

  if [[ -z "${story}" || "${story}" == "null" ]]; then
    # Check if all stories are terminal (pass or fail) vs some still in_progress/blocked
    local all_terminal
    all_terminal=$(jq \
      '(if type == "array" then . else .userStories end)
       | all(
           (if .status then .status
            elif .passes == true then "pass"
            else "available"
            end) as $s
           | ($s == "pass" or $s == "fail")
         )' \
      "${prd_file}" 2>/dev/null)
    if [[ "${all_terminal}" == "true" ]]; then
      return 2
    fi
    # Check if any tickets are in_progress — if so, worth waiting
    local in_progress_count
    in_progress_count=$(jq \
      '(if type == "array" then . else .userStories end)
       | [.[] | select(
           (if .status then .status
            elif .passes == true then "pass"
            else "available"
            end) == "in_progress"
         )] | length' \
      "${prd_file}" 2>/dev/null) || in_progress_count=0
    if [[ "${in_progress_count}" -eq 0 ]]; then
      # No tickets in_progress and none selectable — deadlocked (deps on failed tickets)
      return 2
    fi
    # Some tickets are in_progress — wait for them to complete
    return 3
  fi

  printf '%s\n' "${story}"
  return 0
}

# prd_select_next <workspace_root>
# Reads <workspace_root>/Input/prd.json and prints the next unfinished story.
# Returns 0 on success with JSON printed to stdout.
# Returns 2 with informational message when all stories are done.
# Returns 3 when no stories are available now but some are pending (in_progress/blocked).
# Returns 1 on validation error.
prd_select_next() {
  local workspace_root="${1:?workspace_root required}"
  local prd_file="${workspace_root}/Input/prd.json"

  local story rc=0
  story=$(prd_next_story "${prd_file}") || rc=$?
  if [[ "${rc}" -ne 0 ]]; then
    if [[ "${rc}" -eq 2 ]]; then
      echo "karl: all stories complete — nothing left to do"
      return 2
    fi
    if [[ "${rc}" -eq 3 ]]; then
      return 3
    fi
    return 1
  fi

  printf '%s\n' "${story}"
  return 0
}

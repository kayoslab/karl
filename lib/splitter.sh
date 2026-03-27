#!/usr/bin/env bash
# splitter.sh - Ticket splitting orchestration for karl

set -euo pipefail

# splitter_run_agent <agents_dir> <prd_json>
# Invoke the splitter agent via claude_invoke.
# Prints the agent response JSON to stdout.
splitter_run_agent() {
  local agents_dir="${1:?agents_dir required}"
  local prd_json="${2:?prd_json required}"

  local prompt
  prompt=$(agents_get_prompt "${agents_dir}" "splitter") || return 1

  # Manual substitution for {{prd}} since agents_compose_prompt doesn't handle it
  prompt=$(printf '%s\n' "${prompt}" | \
    KARL_PRD="${prd_json}" \
    awk '
      function str_replace(hay, needle, rep,    result, pos, len) {
        result = ""
        len = length(needle)
        while ((pos = index(hay, needle)) > 0) {
          result = result substr(hay, 1, pos - 1) rep
          hay = substr(hay, pos + len)
        }
        return result hay
      }
      {
        line = $0
        line = str_replace(line, "{{prd}}", ENVIRON["KARL_PRD"])
        print line
      }
    ')

  local response
  response=$(printf '%s\n' "${prompt}" | claude_invoke --print --output-format text) || return 1

  if ! printf '%s' "${response}" | jq . > /dev/null 2>&1; then
    echo "ERROR: Splitter agent returned invalid JSON" >&2
    return 1
  fi

  if ! printf '%s' "${response}" | jq -e 'has("split_decisions")' > /dev/null 2>&1; then
    echo "ERROR: Splitter response missing required field: split_decisions" >&2
    return 1
  fi

  printf '%s\n' "${response}"
}

# splitter_apply_decisions <prd_file> <decisions_json>
# Apply split decisions to the PRD file:
#   - For "split" actions: mark parent as pass, insert sub-tickets
#   - For "keep" actions: no change
# Returns 0 on success, 1 on error.
splitter_apply_decisions() {
  local prd_file="${1:?prd_file required}"
  local decisions_json="${2:?decisions_json required}"

  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  # Determine if input is flat array or object with userStories
  local is_array
  is_array=$(jq 'type == "array"' "${prd_file}")

  local updated
  if [[ "${is_array}" == "true" ]]; then
    updated=$(jq --argjson decisions "${decisions_json}" \
      '
      . as $stories
      | ($decisions.split_decisions // []) as $splits
      | [($splits[] | select(.action == "split") | .parent_id)] as $split_ids
      | [($splits[] | select(.action == "split") | .sub_tickets[])] as $new_tickets
      | ([$stories[] | select(.id as $id | $split_ids | index($id) | not)]
         + $new_tickets)
      | sort_by(.priority)
      ' "${prd_file}") || {
      echo "ERROR: Failed to apply split decisions" >&2
      return 1
    }
  else
    updated=$(jq --argjson decisions "${decisions_json}" \
      '. as $root
      | .userStories as $stories
      | ($decisions.split_decisions // []) as $splits
      | [($splits[] | select(.action == "split") | .parent_id)] as $split_ids
      | [($splits[] | select(.action == "split") | .sub_tickets[])] as $new_tickets
      | ([$stories[] | select(.id as $id | $split_ids | index($id) | not)]
         + $new_tickets)
      | sort_by(.priority) as $merged
      | $root | .userStories = $merged
      ' "${prd_file}") || {
      echo "ERROR: Failed to apply split decisions" >&2
      return 1
    }
  fi

  printf '%s\n' "${updated}" > "${prd_file}"
  return 0
}

# splitter_validate_deps <prd_file>
# Validate that all depends_on references in the PRD point to existing ticket IDs
# and the dependency graph has no cycles (is a DAG).
# Returns 0 on valid, 1 on error.
splitter_validate_deps() {
  local prd_file="${1:?prd_file required}"

  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  # Check for dangling depends_on references
  local dangling
  dangling=$(jq -r \
    '(if type == "array" then . else .userStories end) as $all
     | [$all[].id] as $ids
     | [$all[] | .depends_on // [] | .[] | select(. as $d | $ids | index($d) | not)]
     | unique | .[]' \
    "${prd_file}" 2>/dev/null) || true

  if [[ -n "${dangling}" ]]; then
    echo "ERROR: depends_on references non-existent ticket(s): ${dangling}" >&2
    return 1
  fi

  # Check for cycles via Kahn's algorithm (topological sort) in jq.
  # If not all nodes are processed, there is a cycle.
  local cycle_check
  cycle_check=$(jq -r \
    '(if type == "array" then . else .userStories end) as $all
     | ($all | length) as $total
     | ($all | map({key: .id, value: (.depends_on // [])}) | from_entries) as $deps
     # In-degree = number of dependencies each node has
     | (reduce $all[] as $t ({}; . + {($t.id): ($t.depends_on // [] | length)}))
     | {indeg: ., processed: 0, deps: $deps, ids: [$all[].id]}
     | until(
         ([.ids[] as $id | if .indeg[$id] == 0 then $id else empty end] | length) == 0;
         ([.ids[] as $id | if .indeg[$id] == 0 then $id else empty end]) as $ready
         | reduce $ready[] as $node (.;
             .processed += 1
             | .indeg[$node] = -1
             | reduce (.ids[] as $id
                 | if ((.deps[$id] // []) | index($node)) != null then $id else empty end
               ) as $child (.;
                 .indeg[$child] = (.indeg[$child] - 1)
               )
           )
       )
     | if .processed < $total then "cycle" else "ok" end' \
    "${prd_file}" 2>/dev/null) || cycle_check="error"

  if [[ "${cycle_check}" == "cycle" ]]; then
    echo "ERROR: Circular dependency detected in ticket dependency graph" >&2
    return 1
  fi

  if [[ "${cycle_check}" != "ok" ]]; then
    echo "ERROR: Failed to validate dependency graph" >&2
    return 1
  fi

  return 0
}

# splitter_run <workspace_root>
# Read prd.json, invoke splitter agent, apply decisions.
# Returns 0 on success, 1 on error.
splitter_run() {
  local workspace_root="${1:?workspace_root required}"
  local prd_file="${workspace_root}/Input/prd.json"

  if [[ ! -f "${prd_file}" ]]; then
    echo "ERROR: prd.json not found at ${prd_file}" >&2
    return 1
  fi

  local prd_content
  prd_content=$(cat "${prd_file}")

  echo "[splitter] Analyzing tickets for splitting..."
  local agents_dir="${KARL_DIR}/Agents"

  local response
  if ! response=$(cd "${workspace_root}" && splitter_run_agent "${agents_dir}" "${prd_content}"); then
    echo "ERROR: Splitter agent failed" >&2
    return 1
  fi

  # Check if there are any actual splits
  local split_count
  split_count=$(printf '%s' "${response}" | jq '[.split_decisions[] | select(.action == "split")] | length')

  if [[ "${split_count}" -eq 0 ]]; then
    echo "[splitter] No tickets need splitting"
    return 0
  fi

  echo "[splitter] Applying ${split_count} split decision(s)..."
  if ! splitter_apply_decisions "${prd_file}" "${response}"; then
    return 1
  fi

  # Validate dependency graph after applying splits
  echo "[splitter] Validating dependency graph..."
  if ! splitter_validate_deps "${prd_file}"; then
    echo "ERROR: Dependency validation failed after split — PRD may have dangling refs or cycles" >&2
    return 1
  fi

  echo "[splitter] Split complete"
  return 0
}

#!/usr/bin/env bash
# coordinator.sh - Overlap detection for multi-instance karl

set -euo pipefail

# coordinator_check <workspace_root> [base_dir]
# For each active worktree, run git diff --name-only main..HEAD and compute
# file intersections between worktrees.
# Prints an overlap report (JSON) to stdout.
# Returns 0 always (informational).
coordinator_check() {
  local workspace_root="${1:?workspace_root required}"
  local base_dir="${2:-}"

  if [[ -z "${base_dir}" ]]; then
    base_dir=$(worktree_base_dir "${workspace_root}")
  fi

  # Collect changed files per worktree
  local -a wt_names=()
  local -a wt_files=()

  while IFS= read -r wt_path; do
    if [[ -z "${wt_path}" ]]; then
      continue
    fi

    local wt_name
    wt_name=$(basename "${wt_path}")

    local files
    files=$(git -C "${wt_path}" diff --name-only main..HEAD 2>/dev/null | sort | tr '\n' '|') || continue

    wt_names+=("${wt_name}")
    wt_files+=("${files}")
  done < <(worktree_list "${workspace_root}")

  local num_wts=${#wt_names[@]}

  # Find overlapping files between pairs
  local overlaps="[]"
  local i j
  for ((i = 0; i < num_wts; i++)); do
    for ((j = i + 1; j < num_wts; j++)); do
      IFS='|' read -ra files_a <<< "${wt_files[$i]}"
      IFS='|' read -ra files_b <<< "${wt_files[$j]}"

      local overlap_list=""
      local fa fb
      for fa in "${files_a[@]}"; do
        [[ -z "${fa}" ]] && continue
        for fb in "${files_b[@]}"; do
          [[ -z "${fb}" ]] && continue
          if [[ "${fa}" == "${fb}" ]]; then
            if [[ -n "${overlap_list}" ]]; then
              overlap_list="${overlap_list},\"${fa}\""
            else
              overlap_list="\"${fa}\""
            fi
          fi
        done
      done

      if [[ -n "${overlap_list}" ]]; then
        local pair_json
        pair_json=$(jq -n \
          --arg w1 "${wt_names[$i]}" \
          --arg w2 "${wt_names[$j]}" \
          --argjson files "[${overlap_list}]" \
          '{"worker_a":$w1,"worker_b":$w2,"overlapping_files":$files}')
        overlaps=$(printf '%s' "${overlaps}" | jq --argjson pair "${pair_json}" '. + [$pair]')
      fi
    done
  done

  local report
  report=$(jq -n \
    --argjson overlaps "${overlaps}" \
    --argjson num_workers "${num_wts}" \
    '{"num_workers":$num_workers,"overlaps":$overlaps}')

  printf '%s\n' "${report}"
  return 0
}

# coordinator_run <workspace_root> [base_dir]
# Run coordinator check and invoke coordinator agent for non-trivial overlaps.
# Writes .karl-pause files to worktrees that should pause.
# Returns 0 always.
coordinator_run() {
  local workspace_root="${1:?workspace_root required}"
  local base_dir="${2:-}"

  local report
  report=$(coordinator_check "${workspace_root}" "${base_dir}")

  local overlap_count
  overlap_count=$(printf '%s' "${report}" | jq '.overlaps | length')

  if [[ "${overlap_count}" -eq 0 ]]; then
    return 0
  fi

  echo "[coordinator] Detected ${overlap_count} overlap(s) between workers"

  # For now, just log the overlaps. Agent invocation can be added later
  # when the coordinator agent is wired up with claude_invoke.
  printf '%s' "${report}" | jq -r '.overlaps[] | "  \(.worker_a) <-> \(.worker_b): \(.overlapping_files | join(", "))"'

  return 0
}

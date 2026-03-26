#!/usr/bin/env bash
# merge.sh - Safe merge policy checks for karl (US-014)

set -euo pipefail

# merge_check_clean_tree <workspace_root>
# Returns 0 if working tree has no staged or modified tracked files.
# Returns 1 if there are staged or unstaged modifications to tracked files.
# Untracked files are ignored.
merge_check_clean_tree() {
  local workspace_root="${1:?workspace_root required}"

  local unstaged_rc=0 staged_rc=0
  git -C "${workspace_root}" diff --quiet 2>/dev/null || unstaged_rc=$?
  git -C "${workspace_root}" diff --cached --quiet 2>/dev/null || staged_rc=$?

  if [[ "${unstaged_rc}" -ne 0 || "${staged_rc}" -ne 0 ]]; then
    echo "merge_check_clean_tree: working tree is dirty (staged or modified tracked files present)"
    return 1
  fi

  return 0
}

# merge_check_main_exists <workspace_root>
# Returns 0 if the 'main' branch exists in the local repo.
# Returns 1 if 'main' is absent.
merge_check_main_exists() {
  local workspace_root="${1:?workspace_root required}"

  if ! git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/main" 2>/dev/null; then
    echo "merge_check_main_exists: 'main' branch does not exist in this repository"
    return 1
  fi

  return 0
}

# merge_check_no_conflicts <workspace_root> <feature_branch> <base_branch>
# Returns 0 if feature_branch can merge cleanly onto base_branch (dry-run, no tree modification).
# Returns 1 if either branch does not exist or a precondition fails.
# Returns 2 if merge conflicts are detected.
merge_check_no_conflicts() {
  local workspace_root="${1:?workspace_root required}"
  local feature="${2:?feature_branch required}"
  local base="${3:?base_branch required}"

  if ! git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/${feature}" 2>/dev/null; then
    echo "merge_check_no_conflicts: feature branch '${feature}' does not exist"
    return 1
  fi

  if ! git -C "${workspace_root}" show-ref --verify --quiet "refs/heads/${base}" 2>/dev/null; then
    echo "merge_check_no_conflicts: base branch '${base}' does not exist"
    return 1
  fi

  local merge_base
  if ! merge_base=$(git -C "${workspace_root}" merge-base "${base}" "${feature}" 2>/dev/null); then
    echo "merge_check_no_conflicts: could not determine merge base for '${feature}' and '${base}'"
    return 1
  fi

  local merge_output
  merge_output=$(git -C "${workspace_root}" merge-tree "${merge_base}" "${base}" "${feature}" 2>/dev/null) || true

  if printf '%s' "${merge_output}" | grep -q '<<<<<<'; then
    echo "merge_check_no_conflicts: merge conflicts detected between '${feature}' and '${base}'"
    return 2
  fi

  return 0
}

# merge_safe_check <workspace_root> <ticket_id> <branch>
# Runs all merge safety checks and writes Output/<ticket_id>/merge_check.json.
# Returns 0 if all checks pass.
# Returns 1 if a precondition check fails (dirty tree, missing main).
# Returns 2 if merge conflicts are detected.
merge_safe_check() {
  local workspace_root="${1:?workspace_root required}"
  local ticket_id="${2:?ticket_id required}"
  local branch="${3:?branch required}"

  local artifact_dir="${workspace_root}/Output/${ticket_id}"
  mkdir -p "${artifact_dir}"

  local clean_tree_passed=true main_exists_passed=true no_conflicts_passed=true
  local final_rc=0

  if ! merge_check_clean_tree "${workspace_root}" > /dev/null 2>&1; then
    clean_tree_passed=false
    final_rc=1
  fi

  if ! merge_check_main_exists "${workspace_root}" > /dev/null 2>&1; then
    main_exists_passed=false
    final_rc=1
  fi

  local conflicts_rc=0
  merge_check_no_conflicts "${workspace_root}" "${branch}" "main" > /dev/null 2>&1 || conflicts_rc=$?
  if [[ "${conflicts_rc}" -eq 2 ]]; then
    no_conflicts_passed=false
    if [[ "${final_rc}" -eq 0 ]]; then
      final_rc=2
    fi
  elif [[ "${conflicts_rc}" -ne 0 ]]; then
    no_conflicts_passed=false
    if [[ "${final_rc}" -eq 0 ]]; then
      final_rc=1
    fi
  fi

  local all_passed="true"
  if [[ "${final_rc}" -ne 0 ]]; then
    all_passed="false"
  fi

  local json
  json=$(jq -n \
    --argjson clean_tree "${clean_tree_passed}" \
    --argjson main_exists "${main_exists_passed}" \
    --argjson no_conflicts "${no_conflicts_passed}" \
    --argjson all_passed "${all_passed}" \
    '{
      checks: {
        clean_tree: $clean_tree,
        main_exists: $main_exists,
        no_conflicts: $no_conflicts
      },
      all_passed: $all_passed
    }')

  printf '%s\n' "${json}" > "${artifact_dir}/merge_check.json"

  echo "merge_safe_check [${ticket_id}]: all_passed=${all_passed} (clean_tree=${clean_tree_passed}, main_exists=${main_exists_passed}, no_conflicts=${no_conflicts_passed})"

  return "${final_rc}"
}

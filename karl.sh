#!/usr/bin/env bash
# karl.sh - Autonomous multi-agent development loop entrypoint

set -euo pipefail

KARL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/claude.sh
source "${KARL_DIR}/lib/claude.sh"
# shellcheck source=lib/rate_limit.sh
source "${KARL_DIR}/lib/rate_limit.sh"
# shellcheck source=lib/agents.sh
source "${KARL_DIR}/lib/agents.sh"
# shellcheck source=lib/workspace.sh
source "${KARL_DIR}/lib/workspace.sh"
# shellcheck source=lib/lock.sh
source "${KARL_DIR}/lib/lock.sh"
# shellcheck source=lib/git.sh
source "${KARL_DIR}/lib/git.sh"
# shellcheck source=lib/branch.sh
source "${KARL_DIR}/lib/branch.sh"
# shellcheck source=lib/prd.sh
source "${KARL_DIR}/lib/prd.sh"
# shellcheck source=lib/retry.sh
source "${KARL_DIR}/lib/retry.sh"
# shellcheck source=lib/artifacts.sh
source "${KARL_DIR}/lib/artifacts.sh"
# shellcheck source=lib/summarize.sh
source "${KARL_DIR}/lib/summarize.sh"
# shellcheck source=lib/tech.sh
source "${KARL_DIR}/lib/tech.sh"
# shellcheck source=lib/planning.sh
source "${KARL_DIR}/lib/planning.sh"
# shellcheck source=lib/architect.sh
source "${KARL_DIR}/lib/architect.sh"
# shellcheck source=lib/tester.sh
source "${KARL_DIR}/lib/tester.sh"
# shellcheck source=lib/developer.sh
source "${KARL_DIR}/lib/developer.sh"
# shellcheck source=lib/rework.sh
source "${KARL_DIR}/lib/rework.sh"
# shellcheck source=lib/deploy.sh
source "${KARL_DIR}/lib/deploy.sh"
# shellcheck source=lib/commit.sh
source "${KARL_DIR}/lib/commit.sh"
# shellcheck source=lib/merge.sh
source "${KARL_DIR}/lib/merge.sh"
# shellcheck source=lib/loop.sh
source "${KARL_DIR}/lib/loop.sh"
# shellcheck source=lib/clean.sh
source "${KARL_DIR}/lib/clean.sh"
# shellcheck source=lib/prd_claim.sh
source "${KARL_DIR}/lib/prd_claim.sh"
# shellcheck source=lib/worktree.sh
source "${KARL_DIR}/lib/worktree.sh"
# shellcheck source=lib/splitter.sh
source "${KARL_DIR}/lib/splitter.sh"
# shellcheck source=lib/coordinator.sh
source "${KARL_DIR}/lib/coordinator.sh"
# shellcheck source=lib/merge_arbitrator.sh
source "${KARL_DIR}/lib/merge_arbitrator.sh"
# shellcheck source=lib/supervisor.sh
source "${KARL_DIR}/lib/supervisor.sh"

WORKSPACE_ROOT="${KARL_DIR}"
FORCE_LOCK="false"
AUTO_INIT_GIT="false"
MAX_RETRIES=10
DRY_RUN="false"
CLEAN="false"
FORCE="false"
SPLIT="false"
NUM_INSTANCES=1
WORKTREE_DIR=""

usage() {
  echo "Usage: $(basename "$0") [OPTIONS]" >&2
  echo "  --force-lock           Override a stale LOCK file from a previous run" >&2
  echo "  --auto-init-git        Initialize a git repository without prompting if none exists" >&2
  echo "  --max-retries <n>      Maximum rework cycles per ticket (default: 10)" >&2
  echo "  --workspace <path>     Use an alternate workspace root directory" >&2
  echo "  --dry-run              Validate setup and show next ticket without modifying code" >&2
  echo "  --clean                Reset repository to a clean baseline for recovery" >&2
  echo "  --force                With --clean: also discard uncommitted changes" >&2
  echo "  --split                Run splitter agent on prd.json before the loop" >&2
  echo "  --instances <n>        Run N parallel workers via git worktrees (default: 1)" >&2
  echo "  --worktree-dir <path>  Base directory for worktrees (default: ../.karl-worktrees)" >&2
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force-lock)
        FORCE_LOCK="true"
        shift
        ;;
      --auto-init-git)
        AUTO_INIT_GIT="true"
        shift
        ;;
      --max-retries)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --max-retries requires a value" >&2
          usage
          exit 1
        fi
        if ! [[ "${2}" =~ ^[0-9]+$ ]]; then
          echo "ERROR: --max-retries requires a numeric value, got: ${2}" >&2
          usage
          exit 1
        fi
        MAX_RETRIES="${2}"
        shift 2
        ;;
      --workspace)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --workspace requires a value" >&2
          usage
          exit 1
        fi
        WORKSPACE_ROOT="${2}"
        shift 2
        ;;
      --dry-run)
        DRY_RUN="true"
        shift
        ;;
      --clean)
        CLEAN="true"
        shift
        ;;
      --force)
        FORCE="true"
        shift
        ;;
      --split)
        SPLIT="true"
        shift
        ;;
      --instances)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --instances requires a value" >&2
          usage
          exit 1
        fi
        if ! [[ "${2}" =~ ^[0-9]+$ ]] || [[ "${2}" -lt 1 ]]; then
          echo "ERROR: --instances requires a positive integer, got: ${2}" >&2
          usage
          exit 1
        fi
        NUM_INSTANCES="${2}"
        shift 2
        ;;
      --worktree-dir)
        if [[ $# -lt 2 ]]; then
          echo "ERROR: --worktree-dir requires a value" >&2
          usage
          exit 1
        fi
        WORKTREE_DIR="${2}"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: Unknown argument: $1" >&2
        usage
        exit 1
        ;;
    esac
  done
}

main() {
  parse_args "$@"

  if [[ "${CLEAN}" == "true" ]]; then
    if ! git_repo_check "${WORKSPACE_ROOT}"; then
      echo "ERROR: ${WORKSPACE_ROOT} is not a git repository. Cannot clean." >&2
      exit 1
    fi
    clean_run "${WORKSPACE_ROOT}" "${FORCE}"
    exit 0
  fi

  if ! claude_validate; then
    exit 1
  fi

  workspace_init "${WORKSPACE_ROOT}"

  if ! git_ensure_repo "${WORKSPACE_ROOT}" "${AUTO_INIT_GIT}"; then
    exit 1
  fi

  # Ensure workspace baseline (Input/, CLAUDE.md, Output/) is committed to the
  # current branch so that switching to main never loses these files.
  if git -C "${WORKSPACE_ROOT}" rev-parse --git-dir > /dev/null 2>&1; then
    git -C "${WORKSPACE_ROOT}" add -A > /dev/null 2>&1 || true
    git -C "${WORKSPACE_ROOT}" diff --cached --quiet 2>/dev/null || \
      git -C "${WORKSPACE_ROOT}" commit \
        -m "chore: commit workspace baseline" \
        > /dev/null 2>&1 || true
  fi

  if [[ "${DRY_RUN}" == "true" ]]; then
    echo "[karl] dry-run mode: validating setup [max-retries=${MAX_RETRIES}]"
    local next_ticket rc=0
    next_ticket=$(prd_select_next "${WORKSPACE_ROOT}") || rc=$?
    if [[ "${rc}" -eq 2 ]]; then
      echo "[karl] dry-run: all stories complete — nothing left to do"
    elif [[ "${rc}" -ne 0 ]]; then
      echo "[karl] dry-run: ERROR reading PRD" >&2
      exit 1
    else
      local ticket_id
      ticket_id=$(printf '%s' "${next_ticket}" | jq -r '.id // empty')
      echo "[karl] dry-run: next ticket would be ${ticket_id}"
      printf '%s\n' "${next_ticket}"
    fi
    exit 0
  fi

  # Validate splitter agent if --split is requested
  if [[ "${SPLIT}" == "true" ]]; then
    local agents_dir="${KARL_DIR}/Agents"
    if ! agents_validate_extra "${agents_dir}" "${AGENTS_SPLITTER_ROLE}"; then
      echo "ERROR: Splitter agent validation failed" >&2
      exit 1
    fi
  fi

  # Validate multi-instance agents if --instances > 1
  if [[ "${NUM_INSTANCES}" -gt 1 ]]; then
    local agents_dir="${KARL_DIR}/Agents"
    if ! agents_validate_extra "${agents_dir}" "${AGENTS_MULTI_ROLES[@]}"; then
      echo "ERROR: Multi-instance agent validation failed" >&2
      exit 1
    fi
  fi

  # Run splitter before the main loop if requested
  if [[ "${SPLIT}" == "true" ]]; then
    echo "karl: running splitter agent..."
    if ! splitter_run "${WORKSPACE_ROOT}"; then
      echo "ERROR: Splitter failed" >&2
      exit 1
    fi
  fi

  if ! lock_acquire "${WORKSPACE_ROOT}" "${FORCE_LOCK}"; then
    exit 1
  fi

  trap 'lock_release "${WORKSPACE_ROOT}"' EXIT

  echo "karl: workspace ready, lock acquired (PID $$) [max-retries=${MAX_RETRIES}]"

  if [[ "${NUM_INSTANCES}" -gt 1 ]]; then
    echo "karl: multi-instance mode with ${NUM_INSTANCES} workers"
    supervisor_run "${WORKSPACE_ROOT}" "${NUM_INSTANCES}" "${MAX_RETRIES}" "${WORKTREE_DIR}"
  else
    loop_run "${WORKSPACE_ROOT}" "${MAX_RETRIES}"
  fi
}

main "$@"

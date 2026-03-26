# ADR-004: Safe-Merge Gate Contract

## Status
Accepted

## Context
The autonomous loop creates a feature branch per ticket, commits work, and then merges into main. Without a documented safety contract, autonomous merges risk leaving the repository in a broken state: dirty working trees, a missing or stale main branch, or unresolvable merge conflicts. ADR-002 specifies branch naming but does not address what conditions must hold before a merge is attempted.

## Decision
A mandatory safe-merge gate (`merge_safe_check`) must execute after `commit_create` and before `deploy_gate` in every loop iteration. The gate enforces three ordered checks:

1. **Clean-tree check** (`merge_check_clean_tree`): The working tree must have no uncommitted changes. Fails if `git status --porcelain` produces any output.
2. **Main-exists check** (`merge_check_main_exists`): The `main` branch must exist locally and its tip must match the latest local ref. Fails if `git rev-parse main` errors or if the ref is absent.
3. **Conflict-free check** (`merge_check_no_conflicts`): A dry-run merge of the feature branch onto main must produce no conflict markers. Implemented via `git merge-tree` (three-argument form) with grep for `<<<<<<<`.

All three checks must pass for `merge_safe_check` to return 0. Any failure causes `merge_safe_check` to return non-zero and emit a `[merge]`-prefixed error to stdout.

**Failure recovery**: When `merge_safe_check` fails, `loop_run_iteration` returns 1. `loop_run` resets git state (`git reset --hard` + `git checkout main`) and leaves the ticket's `passes` field as `false`, so the next loop iteration re-selects it and re-enters the developer workflow. No explicit rework callback is fired; the retry is implicit via ticket state.

**Artifact**: On each invocation, `merge_safe_check` writes `Output/ADR/merge_check.json` with the schema:
```json
{
  "ticket_id": "<string>",
  "feature_branch": "<string>",
  "checks": {
    "clean_tree": true,
    "main_exists": true,
    "no_conflicts": true
  },
  "all_passed": true
}
```
This artifact is overwritten on each invocation; only the result of the most recent check is retained.

**Logging**: Every check result and the final gate decision must be emitted with the `[merge]` prefix so progress.md and stdout logs are unambiguous.

## Consequences
- Autonomous merges cannot proceed past a dirty tree, a missing main, or a conflicting feature branch, preventing broken-state commits to main.
- Failure recovery is implicit (ticket stays `passes:false`) rather than explicit (no rework callback); this is intentional to keep the loop simple but means a persistent conflict will cause infinite retry until the developer manually resolves it.
- `git merge-tree` conflict detection depends on git version; on git < 2.38 the three-argument form may behave differently. This is a known risk accepted for now.
- `merge_check.json` is a single-slot artifact (overwritten each run); historical merge check results are not retained.
- All gate behaviour must be covered by `tests/merge.bats`; any change to check semantics requires updating this ADR and the tests.

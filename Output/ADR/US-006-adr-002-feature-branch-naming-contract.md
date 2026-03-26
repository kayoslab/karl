# ADR-002: Feature Branch Naming Contract

## Status
Accepted

## Context
The autonomous loop creates a git feature branch for each ticket it processes. Without a documented, deterministic naming contract, recovery flows cannot reliably locate an in-progress branch, agents cannot derive the branch name independently, and git history becomes ambiguous.

ADR-001 mentions branch name sanitization as a gotcha but does not specify the format or sanitization rules.

## Decision
All feature branches created by the loop must follow the format:

```
feature/<ticket-id>-<slug>
```

Where `<slug>` is derived from `<ticket-title>` by applying these transformations in order:

1. Convert to lowercase
2. Replace spaces and underscores with hyphens
3. Strip all characters that are not alphanumeric or hyphens
4. Collapse consecutive hyphens to a single hyphen
5. Trim leading and trailing hyphens

The function `branch_name <ticket_id> <ticket_title>` in `lib/branch.sh` is the single authoritative implementation. All callers must use this function — no inline branch name construction elsewhere.

`branch_ensure <branch_name> <workspace_root> <base_branch>` creates the branch from `<base_branch>` if absent, or reuses it silently if it already exists. A failure (e.g. invalid base branch, git error) returns non-zero and emits a clear error message; the loop stops the current iteration.

## Consequences
- Given the same ticket id and title, any agent or recovery script can reconstruct the branch name without querying git.
- Reusing an existing branch on re-entry avoids redundant branch creation and preserves partial work.
- The sanitization rules are tested in `tests/branch.bats`; any change to the rules requires updating this ADR and the tests.
- Non-gitflow branch formats (e.g. `bugfix/`, `hotfix/`) are out of scope for the loop's autonomous iterations.

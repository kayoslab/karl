# ADR-008: ADR Arbitrator — Synchronized Architectural Decisions Across Workers

## Status
Accepted

## Context
In multi-instance mode (ADR-007), each worker operates in an isolated git worktree branched from main at ticket claim time. The architect agent reads existing ADRs from `Output/ADR/*.md` in its working directory — but that is the worktree's copy, frozen at the branch point. ADRs created by other workers after that point are invisible.

This means two parallel architects can independently make contradictory or redundant architectural decisions because neither sees the other's output. The merge arbitrator (ADR-004) catches code conflicts at merge time, but architectural contradictions are semantic — they pass merge cleanly and only surface later as inconsistent design.

The existing locking primitives (`.prd.lockdir` for ticket claiming, `.merge.lockdir` for merges) do not cover this case. A new synchronization point is needed specifically for the architect phase.

## Decision
A new **ADR arbitrator** (`lib/adr_arbitrator.sh`) serializes architect invocations across all workers in multi-instance mode. It introduces three operations:

### 1. Lock: `.adr.lockdir`
A POSIX-atomic `mkdir`-based lock at `${main_repo_root}/.adr.lockdir`, following the same pattern as `.merge.lockdir` (ADR-004) and `.prd.lockdir` (ADR-007). Spin timeout: 60 seconds (120 attempts at 0.5s intervals).

This is the third independent lock in karl's concurrency model:

| Lock | Scope | Protects |
|------|-------|----------|
| `.prd.lockdir` | prd.json reads/writes | Ticket claiming and status updates |
| `.merge.lockdir` | git merge to main | Serialized merges from worktrees |
| `.adr.lockdir` | architect phase | ADR visibility and fast-track commits |

### 2. Sync from main: `adr_sync_from_main`
Before the architect runs, all ADRs on `main` are copied into the worktree using `git ls-tree` and `git show`. This reads from the object store — no checkout of main is required, and the worktree's own index is not disturbed beyond staging the synced files.

### 3. Fast-track to main: `adr_fast_track_to_main`
After the architect creates a new ADR, it is committed directly to `refs/heads/main` using git plumbing commands — without checking out main, which would be unsafe while worktrees are active:

```
git hash-object -w <adr_file>          # create blob
GIT_INDEX_FILE=<tmp> git read-tree main       # snapshot main tree
GIT_INDEX_FILE=<tmp> git update-index --add --cacheinfo 100644,<blob>,Output/ADR/<id>.md
GIT_INDEX_FILE=<tmp> git write-tree            # new tree with ADR added
git commit-tree <tree> -p <main-HEAD>          # new commit
git update-ref refs/heads/main <commit>        # advance main atomically
```

A per-process temporary index file (`.adr-index.$$`) is used to avoid conflicts. It is cleaned up unconditionally after the plumbing operations complete, including on failure.

### Orchestration flow
```
adr_arbitrator_run(main_repo, worktree, story_json, plan_json):
  1. Acquire .adr.lockdir
  2. adr_sync_from_main  — pull latest ADRs into worktree
  3. architect_run        — run architect agent (unchanged, operates on worktree)
  4. If new ADR created:
     adr_fast_track_to_main — commit ADR to main via plumbing
  5. Release .adr.lockdir (always, even on failure)
```

### Activation
- **Multi-instance mode**: `loop_run_ticket` receives `main_repo_root` (6th parameter, passed by `supervisor_worker_loop`). When `main_repo_root` differs from `workspace_root`, the ADR arbitrator wraps the architect call.
- **Single-instance mode**: `main_repo_root` is empty or equals `workspace_root`. The architect runs directly with no lock overhead. Behavior is identical to pre-ADR-008.

### Interaction with merge arbitrator
The ADR arbitrator and merge arbitrator hold independent locks. `adr_fast_track_to_main` uses `git update-ref` (atomic ref update) rather than `git merge`, so it does not conflict with the merge arbitrator's `git checkout main && git merge` flow. When the merge arbitrator later merges a feature branch, it reads the current `main` HEAD — which already includes any fast-tracked ADR commits.

## Consequences
- The architect phase becomes a serialization point in multi-instance mode. Only one worker's architect runs at a time. This is intentional — architectural decisions are inherently sequential. The bottleneck is minor because architect invocations are fast relative to development and testing phases.
- ADRs reach main before their parent ticket's code does. The `git log main -- Output/ADR/` will show fast-track commits interleaved with merge commits. This is a feature, not a bug �� it ensures visibility.
- The git plumbing approach bypasses hooks, signing, and other commit-time checks on main. This is acceptable because ADR files are plain markdown with no executable content.
- The temporary index file (`.adr-index.$$`) is an ephemeral artifact. If karl is killed between `read-tree` and cleanup, a stale file may remain. It is harmless (PID-suffixed, ignored by git) and will be overwritten on the next run.
- All ADR arbitrator behavior is covered by `tests/adr_arbitrator.bats`. Any change to the locking, sync, or fast-track mechanism requires updating this ADR and those tests.

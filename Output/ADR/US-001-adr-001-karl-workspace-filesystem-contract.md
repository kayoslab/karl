# ADR-001: karl Workspace Filesystem Contract

## Status
Accepted

## Context
karl is a bash-based autonomous agent loop. Every runtime artifact (agent prompts, inputs, outputs, architectural records) must live in a predictable, version-controllable location. Without a documented filesystem contract, future agents and contributors cannot reliably read or write state.

## Decision
karl's workspace is rooted at the repository root and organised as follows:

```
<root>/
  Agents/          # Agent prompt templates (*.md)
  Input/
    prd.json       # Canonical ticket backlog (required at runtime)
    CLAUDE.md      # Project instructions read by all agents (required at runtime)
  Output/
    ADR/           # Architectural Decision Records (one file per ADR)
    progress.md    # Append-only log of completed work
    tech.md        # Living technology context document
  lib/             # Bash source modules (workspace.sh, etc.)
  tests/           # bats-core test suites (*.bats)
  karl             # Main entrypoint script
  LOCK             # Single-instance protection file (runtime only)
```

Key rules:
1. `Agents/`, `Input/`, `Output/`, and `Output/ADR/` are created by `bootstrap_workspace` if absent.
2. `Input/prd.json` and `CLAUDE.md` are **required inputs** validated by `validate_workspace`; startup fails with a clear error if either is missing after bootstrap.
3. `Output/progress.md` and `Output/tech.md` are **canonical outputs** created as empty placeholders during bootstrap; they are append-safe and must never be truncated by agents.
4. `Output/ADR/` consolidates all durable runtime artifacts under `Output/` so a single directory captures the full state of a run.
5. `LOCK` lives at the repository root and is managed exclusively by the karl entrypoint for single-instance protection.

## Consequences
- All lib modules and agents can derive paths from a single `WORKSPACE_ROOT` variable rather than hard-coding them.
- Consumers of `lib/workspace.sh` receive consistent path constants (`WORKSPACE_DIRS`, `WORKSPACE_REQUIRED_INPUTS`, `WORKSPACE_OUTPUT_FILES`) without re-deriving them.
- Any change to this layout requires updating this ADR, `lib/workspace.sh`, and associated tests.

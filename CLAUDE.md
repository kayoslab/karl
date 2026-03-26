# karl Project Context

## Project Purpose

Build karl, a Ralph-style autonomous multi-agent development loop for Anthropic Claude CLI. Each ticket iteration uses fresh agents with clean context windows and persists only durable state to files. At runtime, karl maintains its workspace under ADR, Agents, Input, and Output folders, with ADR records stored in Output/ADR. karl reads Input/prd.json and CLAUDE.md, selects the highest-priority unfinished ticket, ensures a git repository exists, creates a deterministic gitflow feature branch, orchestrates planning, review, architecture, test, development, and deployment agents, enforces ADR and tech.md consistency, appends Output/progress.md after successful work, updates Input/prd.json, safely merges to main, and repeats until all tickets pass. The runtime includes single-instance protection via a LOCK file, concise artifact summarization, a configurable per-ticket iteration retry limit, and a clean command to reset the repository to a safe state. karl should be a very simple bash application maintaining the loops and agents.

## Tech Stack

- Language: Bash
- Testing: bats-core (BATS)
- Linting: shellcheck

## Coding Conventions

- Should be platform independent, run on macOS, Linux, etc.

## Testing Requirements

- Business logic should be tested
- Tests live in `tests/` with `.bats` extension
- Run tests with: `bats tests/`
- Typecheck: `shellcheck lib/*.sh`

## Quality Gates

Before merging:
1. `shellcheck lib/*.sh` — must pass with no errors
2. `bats tests/` — all tests must pass

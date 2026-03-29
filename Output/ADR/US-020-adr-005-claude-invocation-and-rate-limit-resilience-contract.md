# ADR-005: Claude Invocation and Rate-Limit Resilience Contract

## Status
Superseded by [migration-001-subagents-and-agent-teams](migration-001-subagents-and-agent-teams.md) (2026-03-27).
The `claude_invoke()` wrapper was replaced by direct `claude --agent` subagent invocations.

## Context
The autonomous loop calls the Claude CLI from multiple agent libs (planning, architect, tester, rework, deploy, tech). Without a centralised invocation wrapper, rate-limit responses from the Claude API would surface as unhandled errors, aborting the loop. A consistent retry strategy is required so the loop can run unattended for extended periods.

## Decision
All Claude CLI invocations within karl **must** go through `claude_invoke` in `lib/rate_limit.sh`. Direct calls to `claude` from agent libs are prohibited.

### `claude_invoke <prompt>`
- Calls `claude -p --dangerously-skip-permissions` with the provided prompt.
- On **non-zero exit + rate-limit content detected** by `rate_limit_detect`, waits using `rate_limit_parse_wait` (or falls back to `rate_limit_backoff`) and retries up to `KARL_RATE_LIMIT_MAX_RETRIES` times.
- On **non-zero exit without rate-limit content**, returns non-zero immediately — no retry.
- On success (exit 0), returns the captured stdout.
- All rate-limit events are logged to stderr with a `[rate_limit]` prefix; iteration state is never lost.

### Detection — `rate_limit_detect <text>`
Matches (case-insensitive): `rate.limit`, `quota exceeded`, `too many requests`, `usage limit`, `retry.after`.

### Wait — `rate_limit_parse_wait <text>`
Extracts seconds or minutes from the response text (e.g. `retry after 30 seconds`, `in 2 minutes`). Returns the parsed duration in seconds, or empty string if unparseable.

### Backoff — `rate_limit_backoff <attempt>`
Returns `KARL_RATE_LIMIT_BACKOFF_BASE * attempt`. Defaults to `KARL_RATE_LIMIT_BACKOFF_BASE=60`.

### Configuration
| Variable | Default | Purpose |
|---|---|---|
| `KARL_RATE_LIMIT_BACKOFF_BASE` | `60` | Base seconds for exponential-style backoff |
| `KARL_RATE_LIMIT_MAX_RETRIES` | `5` | Maximum retry attempts before aborting |

Both variables are exported by `lib/rate_limit.sh` and may be overridden by the caller or test environment.

## Consequences
- Any new agent lib that calls `claude` must use `claude_invoke`; direct `claude` calls are a contract violation.
- Tests must set `KARL_RATE_LIMIT_BACKOFF_BASE=0` to prevent real sleeps.
- Stubs for `claude` in tests must exit non-zero to trigger the retry path; emitting rate-limit text with exit 0 does not trigger a retry.
- `KARL_RATE_LIMIT_MAX_RETRIES` exhaustion causes `claude_invoke` to return non-zero, which propagates as a loop iteration failure (ticket stays `passes:false` per ADR-004 recovery semantics).
- All behaviour is covered by `tests/rate_limit.bats`; changes to detection patterns, backoff formula, or retry semantics require updating this ADR and the tests.

# ADR: Migration from Custom Bash Orchestration to Claude Code Subagents

**Date:** 2026-03-27
**Status:** Accepted
**Supersedes:** US-007 (Agent Registry Contract), US-020 (Claude Invocation and Rate-Limit Resilience Contract)

## Context

karl originally orchestrated AI agents through a custom bash layer: `lib/agents.sh` loaded markdown prompt files from `Agents/`, performed `{{placeholder}}` template substitution via AWK, and piped the composed prompt to `claude_invoke()` in `lib/rate_limit.sh`. Each pipeline stage had its own orchestration file that composed prompts, validated JSON output, and persisted artifacts.

Claude Code now provides native **custom subagents** — isolated agents with their own tools, model, and permissions, invocable via `claude --agent <name> --print -p "..."`.

## Decision

Replace the agent invocation layer with Claude Code native subagents:

1. **Custom subagents** replace the agent registry, template composition, and invocation wrapper. Each agent is defined as a `.claude/agents/<name>.md` file with standard Claude Code frontmatter (`name`, `description`, `tools`, `model`). Claude Code handles discovery, validation, and rate limiting natively.

2. **Bash retains pipeline orchestration.** Each stage file (`lib/planning.sh`, `lib/rework.sh`, etc.) calls `subagent_invoke_json` from `lib/subagent.sh` instead of the old `agents_compose_prompt` + `claude_invoke`. Bash controls the pipeline sequence, retry logic, and conditional branching (plan-review loop, rework loop).

3. **Tool restrictions** enforce per-agent security: reviewer and planner get read-only access, developer gets full filesystem access, tester gets read + write + bash for running tests. Agents run with `--dangerously-skip-permissions` for headless tool access.

4. **Multi-instance mode remains bash-based.** The supervisor spawns background worker processes, each running the full pipeline via subagent calls. A coordinator and team-lead subagent were designed to replace this with Claude Code agent teams, but the `Agent()` tool is not available in headless `--print` mode. These definitions remain in `.claude/agents/` for potential future interactive use.

### Why not coordinator/team-lead subagents?

The original plan was to have a coordinator subagent sequence the pipeline via `Agent(planner, reviewer, ...)` tool calls, and a team-lead subagent spawn coordinator teammates via agent teams. This failed because `claude --print -p` (headless mode) does not support the `Agent()` tool — subagents cannot spawn other subagents in this mode. Bash orchestration is the correct architecture for headless pipeline execution.

## Consequences

### Removed
- `Agents/` directory and `lib/agents.sh` (agent registry, template composition, frontmatter parsing)
- `lib/claude.sh` and `lib/rate_limit.sh` (Claude CLI validation, invocation wrapper, rate-limit retry)
- `lib/summarize.sh`, `lib/artifacts.sh` (artifact management)
- `lib/coordinator.sh` (overlap detection)

### Rewritten (subagent invocation instead of claude_invoke)
- `lib/planning.sh`, `lib/architect.sh`, `lib/tester.sh`, `lib/developer.sh`, `lib/deploy.sh`, `lib/rework.sh`

### Added
- `lib/subagent.sh` — `subagent_invoke` and `subagent_invoke_json` (JSON extraction from agent responses)
- `.claude/agents/*.md` — 10 Claude Code subagent definitions
- Startup dependency analysis (`splitter_analyze_deps`) — detects missing `depends_on` entries
- `--verbose` flag — shows full subagent output
- Signal propagation — Ctrl+C kills child claude processes

### Trade-offs
- **Pro:** Agent definitions are native Claude Code format. Discovery, validation, and tool restrictions handled by Claude Code.
- **Pro:** Per-agent tool restrictions enforced natively.
- **Pro:** Rate limiting handled by Claude Code internally.
- **Con:** Agents return free-form text that must be parsed for JSON. `subagent_invoke_json` handles markdown fences and prose-wrapped responses, but extraction can fail.
- **Con:** `--dangerously-skip-permissions` gives agents unrestricted filesystem access in headless mode.
- **Con:** Agent teams and coordinator subagent designs couldn't be used due to headless mode limitations.

### Superseded ADRs
- **US-007 (Agent Registry Contract)** — the custom agent registry and `agents_compose_prompt` no longer exist.
- **US-020 (Claude Invocation and Rate-Limit Resilience Contract)** — the `claude_invoke()` wrapper no longer exists.

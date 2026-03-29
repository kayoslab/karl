# Technology Context

- **Language & Runtime** — Bash (>=3.2), POSIX-compatible, macOS + Linux
- **AI Backend** — Claude CLI invoked via `.claude/agents/` subagent definitions
- **Key Dependencies** — `claude` CLI, `git`, `jq`, `bats-core`, `shellcheck`
- **Testing** — bats-core in `tests/*.bats`, mocked external commands, 330+ tests
- **Quality Gates** — `shellcheck lib/*.sh` + `bats tests/` enforced by deployment agent
- **Architecture** — `karl.sh` entrypoint, `lib/*.sh` bash orchestration, `.claude/agents/*.md` subagent definitions, durable state in `Output/` and `Input/prd.json`, fresh agent context per invocation
- **Agent Invocation** — `subagent_invoke_json` in `lib/subagent.sh` wraps `claude --agent <name> --print --dangerously-skip-permissions`
- **Constraints** — `jq` required at runtime, branch name sanitization, append-safe artifacts, no cross-ticket agent memory

The write was blocked pending your approval. Once you grant permission, `Output/tech.md` will be created with these sections:

- **Language & Runtime** — Bash, POSIX-compatible, macOS + Linux
- **Key Dependencies** — `claude` CLI, `git`, `jq`, `bats-core`, `shellcheck`
- **Testing Approach** — bats-core in `tests/*.bats`, mocked external commands
- **Build & Quality** — `shellcheck lib/*.sh` + `bats tests/` as quality gates
- **Architecture Notes** — entrypoint `karl`, `lib/*.sh` modules, `Agents/*.md` prompts, durable state in `Output/` and `Input/prd.json`, fresh agent per invocation
- **Gotchas & Constraints** — `jq` guard at startup, Claude CLI output parsing, branch name sanitization, append-safe artifacts, Homebrew out-of-scope for core

Please approve the write and it will be saved.

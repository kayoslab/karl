# ADR-003: Agent Registry Contract

## Status
Accepted

## Context
ADR-001 reserves the `Agents/` directory for agent prompt templates but does not specify the file format, required roles, validation rules, or how prompts are composed with runtime context. Without a documented contract, contributors cannot reliably author new agents, and the loader cannot enforce a stable interface.

## Decision
Each agent definition is a Markdown file in `Agents/` with a YAML-style frontmatter block at the top of the file containing exactly four fields:

```
role: <string>        # Canonical role identifier (case-insensitive match)
inputs: <csv>         # Comma-separated list of context keys the agent accepts
outputs: <csv>        # Comma-separated list of output keys the agent produces
constraints: <text>   # Free-text constraints applied to the agent's output
```

The six roles below are **required**. The loop will not start if any are absent:

| Role | File |
|---|---|
| architect | Agents/architect.md |
| planner | Agents/planner.md |
| reviewer | Agents/reviewer.md |
| tester | Agents/tester.md |
| developer | Agents/developer.md |
| deployment | Agents/deployment.md |

Additional optional agents (e.g. `tech`) may exist in `Agents/` and are loaded if present.

`agents_load [workspace]` reads every `*.md` file in `Agents/`, validates the four frontmatter fields via `agents_validate_contract`, and populates the in-memory registry. Missing required roles cause `agents_validate` to emit a named `ERROR` for each absent role and return non-zero, aborting startup.

Prompt composition is performed by `agents_compose_prompt <role> <ticket> <plan> <adr> <tech> <tests>`. The agent's Markdown body is used as a template; the following placeholders are substituted at compose time:

```
{{ticket}}   {{plan}}   {{adr}}   {{tech}}   {{tests}}
```

`agents_get_contract_field <file> <field>` extracts a single frontmatter field value using a line-anchored grep (`^field:`). Fields are matched in the raw file content; agent body text must not contain lines beginning with `role:`, `inputs:`, `outputs:`, or `constraints:` to avoid false matches.

## Consequences
- Any new agent added to `Agents/` must include all four frontmatter fields; `agents_validate_contract` will reject files missing any field.
- The six required roles are an explicit contract; removing or renaming a role file is a breaking change requiring an ADR amendment.
- `agents_get_contract_field` is intentionally simple (grep-based) and does not parse YAML; multi-line field values are not supported.
- All registry behaviour is covered by `tests/agents.bats`, including per-file real-agent contract validation tests.

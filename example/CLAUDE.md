# Example Project Context

## Project Purpose

This is an example workspace for karl. Replace this file with a description of your project.

A good CLAUDE.md explains:
- What the project does and why it exists
- The tech stack and key conventions
- Any constraints agents must respect (e.g. "do not modify generated files")
- Links to relevant documentation or ADRs

## Tech Stack

- Language: Bash
- Testing: bats-core (`bats tests/`)
- Linting: shellcheck

## Coding Conventions

- Scripts must be POSIX-compatible where possible
- All business logic must have a corresponding BATS test
- Tests live in `tests/` with `.bats` extension

## Testing Requirements

- Run tests with: `bats tests/`
- All tests must pass before a ticket is marked complete

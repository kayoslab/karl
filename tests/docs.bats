#!/usr/bin/env bats

# Tests for US-024: open-source onboarding documentation and example workspace

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

# ── README.md ──────────────────────────────────────────────────────────────────

@test "README.md exists" {
  [ -f "$REPO_ROOT/README.md" ]
}

@test "README.md is non-empty" {
  [ -s "$REPO_ROOT/README.md" ]
}

@test "README.md contains Installation section" {
  grep -qi "installation" "$REPO_ROOT/README.md"
}

@test "README.md contains Usage section" {
  grep -qi "usage" "$REPO_ROOT/README.md"
}

@test "README.md contains Architecture section" {
  grep -qi "architecture" "$REPO_ROOT/README.md"
}

@test "README.md contains Agents section" {
  grep -qi "agent" "$REPO_ROOT/README.md"
}

@test "README.md contains Configuration section" {
  grep -qi "configuration\|config" "$REPO_ROOT/README.md"
}

@test "README.md mentions Claude CLI prerequisite" {
  grep -qi "claude" "$REPO_ROOT/README.md"
}

@test "README.md mentions git prerequisite" {
  grep -qi "git" "$REPO_ROOT/README.md"
}

# ── Architecture diagram ───────────────────────────────────────────────────────

@test "docs/architecture.svg exists" {
  [ -f "$REPO_ROOT/docs/architecture.svg" ]
}

@test "docs/architecture.svg is non-empty" {
  [ -s "$REPO_ROOT/docs/architecture.svg" ]
}

@test "docs/architecture.svg contains valid SVG markup" {
  grep -q "<svg" "$REPO_ROOT/docs/architecture.svg"
}

# ── Claude Code subagent definitions (.claude/agents/) ───────────────────────

@test ".claude/agents/planner.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/planner.md" ]
}

@test ".claude/agents/reviewer.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/reviewer.md" ]
}

@test ".claude/agents/architect.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/architect.md" ]
}

@test ".claude/agents/tester.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/tester.md" ]
}

@test ".claude/agents/developer.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/developer.md" ]
}

@test ".claude/agents/deployment.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/deployment.md" ]
}

@test ".claude/agents/tech.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/tech.md" ]
}

@test ".claude/agents/coordinator.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/coordinator.md" ]
}

@test ".claude/agents/team-lead.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/team-lead.md" ]
}

@test ".claude/agents/splitter.md exists" {
  [ -f "$REPO_ROOT/.claude/agents/splitter.md" ]
}

# ── Example workspace – Input/prd.json ────────────────────────────────────────

@test "example/Input/prd.json exists" {
  [ -f "$REPO_ROOT/example/Input/prd.json" ]
}

@test "example/Input/prd.json is valid JSON" {
  python3 -c "import sys, json; json.load(sys.stdin)" < "$REPO_ROOT/example/Input/prd.json"
}

@test "example/Input/prd.json contains at least one ticket" {
  count=$(python3 -c "
import sys, json
data = json.load(sys.stdin)
stories = data if isinstance(data, list) else data.get('userStories', [])
print(len(stories))
" < "$REPO_ROOT/example/Input/prd.json")
  [ "$count" -ge 1 ]
}

@test "example/Input/prd.json ticket has required fields" {
  python3 -c "
import json
with open('$REPO_ROOT/example/Input/prd.json') as f:
    data = json.load(f)
stories = data if isinstance(data, list) else data.get('userStories', [])
ticket = stories[0]
required = ['id', 'title', 'description', 'acceptanceCriteria', 'priority', 'passes']
missing = [k for k in required if k not in ticket]
assert not missing, 'Missing fields: ' + str(missing)
"
}

# ── Example workspace – CLAUDE.md ─────────────────────────────────────────────

@test "example/CLAUDE.md exists" {
  [ -f "$REPO_ROOT/example/CLAUDE.md" ]
}

@test "example/CLAUDE.md is non-empty" {
  [ -s "$REPO_ROOT/example/CLAUDE.md" ]
}

# ── Example workspace – Output directory ──────────────────────────────────────

@test "example/Output directory exists" {
  [ -d "$REPO_ROOT/example/Output" ]
}

@test "example/Output/ADR directory exists" {
  [ -d "$REPO_ROOT/example/Output/ADR" ]
}

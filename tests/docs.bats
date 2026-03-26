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

# ── karl built-in agents (Agents/ in the karl root) ───────────────────────────

@test "Agents/planner.md exists" {
  [ -f "$REPO_ROOT/Agents/planner.md" ]
}

@test "Agents/reviewer.md exists" {
  [ -f "$REPO_ROOT/Agents/reviewer.md" ]
}

@test "Agents/architect.md exists" {
  [ -f "$REPO_ROOT/Agents/architect.md" ]
}

@test "Agents/tester.md exists" {
  [ -f "$REPO_ROOT/Agents/tester.md" ]
}

@test "Agents/developer.md exists" {
  [ -f "$REPO_ROOT/Agents/developer.md" ]
}

@test "Agents/deployment.md exists" {
  [ -f "$REPO_ROOT/Agents/deployment.md" ]
}

@test "Agents/tech.md exists" {
  [ -f "$REPO_ROOT/Agents/tech.md" ]
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

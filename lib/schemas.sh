#!/usr/bin/env bash
# schemas.sh - JSON Schema definitions for agent responses
#
# Each schema defines the required fields and types for a specific agent.
# Passed to the Claude CLI via --json-schema for model-level structured output
# enforcement. The CLI guarantees the response matches the schema, so no
# post-hoc validation or normalization is needed.

set -euo pipefail

# Reviewer: approves or rejects implementation plans
SCHEMA_REVIEWER='{"type":"object","properties":{"approved":{"type":"boolean"},"concerns":{"type":"array","items":{"type":"string"}}},"required":["approved","concerns"]}'

# Architect: evaluates architectural impact, optionally produces ADRs
SCHEMA_ARCHITECT='{"type":"object","properties":{"approved":{"type":"boolean"},"adr_entry":{"type":["string","null"]}},"required":["approved","adr_entry"]}'

# Deployment: quality gate pass/fail
SCHEMA_DEPLOYMENT='{"type":"object","properties":{"decision":{"type":"string","enum":["pass","fail"]},"gates_checked":{"type":"array","items":{"type":"string"}},"failures":{"type":"array","items":{"type":"string"}},"notes":{"type":"string"}},"required":["decision","gates_checked","failures"]}'

# Tester: test results with failure attribution
SCHEMA_TESTER='{"type":"object","properties":{"tests_added":{"type":"array","items":{"type":"string"}},"tests_modified":{"type":"array","items":{"type":"string"}},"test_results":{"type":"string","enum":["pass","fail"]},"failures":{"type":"array","items":{"type":"string"}},"failure_source":{"type":["string","null"]}},"required":["test_results","failures"]}'

# Merge resolver: conflict resolution outcome
SCHEMA_MERGE_RESOLVER='{"type":"object","properties":{"resolution":{"type":"string","enum":["resolved","unresolvable"]},"resolved_files":{"type":"array"},"summary":{"type":"string"}},"required":["resolution","summary"]}'

# Planner: concrete implementation plan for a ticket
SCHEMA_PLANNER='{"type":"object","properties":{"plan":{"type":"array","items":{"type":"string"}},"testing_recommendations":{"type":"array","items":{"type":"string"}},"estimated_complexity":{"type":"string","enum":["low","medium","high"]},"risks":{"type":"array","items":{"type":"string"}}},"required":["plan","testing_recommendations","estimated_complexity","risks"]}'

# Developer: files changed and summary after implementation
SCHEMA_DEVELOPER='{"type":"object","properties":{"files_changed":{"type":"array","items":{"type":"string"}},"summary":{"type":"string"}},"required":["files_changed","summary"]}'

# Splitter (split mode): split/keep decisions per ticket
SCHEMA_SPLITTER='{"type":"object","properties":{"split_decisions":{"type":"array","items":{"type":"object"}}},"required":["split_decisions"]}'

# Splitter (dependency analysis mode): missing dependency updates
SCHEMA_SPLITTER_DEPS='{"type":"object","properties":{"dependency_updates":{"type":"array","items":{"type":"object"}}},"required":["dependency_updates"]}'

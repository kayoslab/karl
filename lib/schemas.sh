#!/usr/bin/env bash
# schemas.sh - JSON Schema definitions for agent responses
#
# Each schema defines the required fields and types for a specific agent.
# Used by subagent_invoke_json with --json-schema for model-level enforcement
# and _subagent_validate_schema for response validation.

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

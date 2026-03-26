#!/usr/bin/env bats
# tests/artifacts.bats - Tests for lib/artifacts.sh (US-017)

KARL_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
ARTIFACTS_SH="${KARL_DIR}/lib/artifacts.sh"

setup() {
  WORKSPACE_ROOT="$(mktemp -d)"
  OUTPUT_DIR="${WORKSPACE_ROOT}/Output"
  ADR_DIR="${OUTPUT_DIR}/ADR"
  mkdir -p "${OUTPUT_DIR}" "${ADR_DIR}"
  # shellcheck source=../lib/artifacts.sh
  source "${ARTIFACTS_SH}"
}

teardown() {
  rm -rf "${WORKSPACE_ROOT}"
}

TICKET_ID="US-017"

# Complete artifact set including review.json
COMPLETE_ARTIFACTS=(plan.json review.json architect.json tests.json developer.json deploy.json merge_check.json)

# ---------------------------------------------------------------------------
# KARL_EXPECTED_ARTIFACTS registry
# ---------------------------------------------------------------------------

@test "KARL_EXPECTED_ARTIFACTS includes plan.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" plan.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes review.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" review.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes architect.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" architect.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes tests.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" tests.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes developer.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" developer.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes deploy.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" deploy.json "* ]]
}

@test "KARL_EXPECTED_ARTIFACTS includes merge_check.json" {
  [[ " ${KARL_EXPECTED_ARTIFACTS[*]} " == *" merge_check.json "* ]]
}

# ---------------------------------------------------------------------------
# artifacts_dir
# ---------------------------------------------------------------------------

@test "artifacts_dir returns correct path for ticket" {
  run artifacts_dir "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"Output/US-017"* ]]
}

@test "artifacts_dir includes workspace root in path" {
  run artifacts_dir "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${output}" = "${WORKSPACE_ROOT}/Output/US-017" ]
}

# ---------------------------------------------------------------------------
# artifacts_ensure_dir
# ---------------------------------------------------------------------------

@test "artifacts_ensure_dir creates artifact directory" {
  run artifacts_ensure_dir "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [ -d "${OUTPUT_DIR}/US-017" ]
}

@test "artifacts_ensure_dir is idempotent" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_ensure_dir "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [ -d "${OUTPUT_DIR}/US-017" ]
}

@test "artifacts_ensure_dir prints confirmation message" {
  run artifacts_ensure_dir "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"ensured"* ]]
}

# ---------------------------------------------------------------------------
# artifacts_list
# ---------------------------------------------------------------------------

@test "artifacts_list returns empty when no artifacts exist" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_list "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "artifacts_list returns empty when ticket directory does not exist" {
  run artifacts_list "${WORKSPACE_ROOT}" "US-NONEXISTENT"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "artifacts_list lists existing artifact files" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  printf '{}' > "${OUTPUT_DIR}/US-017/review.json"
  run artifacts_list "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"plan.json"* ]]
  [[ "${output}" == *"review.json"* ]]
}

@test "artifacts_list does not include non-json files" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '0\n' > "${OUTPUT_DIR}/US-017/retry_count"
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_list "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *"retry_count"* ]]
  [[ "${output}" == *"plan.json"* ]]
}

# ---------------------------------------------------------------------------
# artifacts_read
# ---------------------------------------------------------------------------

@test "artifacts_read returns content of existing artifact" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '%s\n' '{"plan": ["step 1"]}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_read "${WORKSPACE_ROOT}" "${TICKET_ID}" "plan.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"plan"'* ]]
}

@test "artifacts_read returns content of review.json artifact" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '%s\n' '{"approved":true,"concerns":[]}' > "${OUTPUT_DIR}/US-017/review.json"
  run artifacts_read "${WORKSPACE_ROOT}" "${TICKET_ID}" "review.json"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"approved"'* ]]
}

@test "artifacts_read returns 1 when artifact does not exist" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_read "${WORKSPACE_ROOT}" "${TICKET_ID}" "nonexistent.json"
  [ "${status}" -eq 1 ]
}

@test "artifacts_read prints error message when artifact is missing" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_read "${WORKSPACE_ROOT}" "${TICKET_ID}" "missing.json"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"not found"* ]]
}

# ---------------------------------------------------------------------------
# artifacts_validate_complete
# ---------------------------------------------------------------------------

@test "artifacts_validate_complete returns 0 when all expected artifacts exist" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  for f in "${COMPLETE_ARTIFACTS[@]}"; do
    printf '{}' > "${OUTPUT_DIR}/US-017/${f}"
  done
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
}

@test "artifacts_validate_complete returns 1 when review.json is absent" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  for f in "${COMPLETE_ARTIFACTS[@]}"; do
    printf '{}' > "${OUTPUT_DIR}/US-017/${f}"
  done
  rm "${OUTPUT_DIR}/US-017/review.json"
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 1 ]
}

@test "artifacts_validate_complete prints review.json in missing list when absent" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"review.json"* ]]
}

@test "artifacts_validate_complete returns 1 when artifacts are missing" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  # Only create plan.json; others missing
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 1 ]
}

@test "artifacts_validate_complete prints missing artifact names" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"architect.json"* ]] || [[ "${output}" == *"Missing"* ]]
}

@test "artifacts_validate_complete prints success message when complete" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  for f in "${COMPLETE_ARTIFACTS[@]}"; do
    printf '{}' > "${OUTPUT_DIR}/US-017/${f}"
  done
  run artifacts_validate_complete "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"present"* ]]
}

# ---------------------------------------------------------------------------
# artifacts_summarize
# ---------------------------------------------------------------------------

@test "artifacts_summarize returns valid JSON" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  printf '%s' "${output}" | jq empty
}

@test "artifacts_summarize includes ticket_id field" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"ticket_id"'* ]]
  [[ "${output}" == *'"US-017"'* ]]
}

@test "artifacts_summarize includes complete=false when artifacts are missing" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  complete=$(printf '%s' "${output}" | jq -r '.complete')
  [ "${complete}" = "false" ]
}

@test "artifacts_summarize includes complete=true when all artifacts exist" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  for f in "${COMPLETE_ARTIFACTS[@]}"; do
    printf '{}' > "${OUTPUT_DIR}/US-017/${f}"
  done
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  complete=$(printf '%s' "${output}" | jq -r '.complete')
  [ "${complete}" = "true" ]
}

@test "artifacts_summarize includes present and missing arrays" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{}' > "${OUTPUT_DIR}/US-017/plan.json"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"present"'* ]]
  [[ "${output}" == *'"missing"'* ]]
}

@test "artifacts_summarize lists review.json in missing when absent" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  # No artifacts created; review.json should be missing
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  missing=$(printf '%s' "${output}" | jq -r '.missing[]')
  [[ "${missing}" == *"review.json"* ]]
}

@test "artifacts_summarize lists review.json in present when it exists" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{}' > "${OUTPUT_DIR}/US-017/review.json"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  present=$(printf '%s' "${output}" | jq -r '.present[]')
  [[ "${present}" == *"review.json"* ]]
}

@test "artifacts_summarize counts ADRs in Output/ADR" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '# ADR\ncontent\n' > "${ADR_DIR}/US-001-test.md"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  adr_count=$(printf '%s' "${output}" | jq -r '.adr_count')
  [ "${adr_count}" -eq 1 ]
}

@test "artifacts_summarize shows adr_count=0 when no ADRs exist" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  adr_count=$(printf '%s' "${output}" | jq -r '.adr_count')
  [ "${adr_count}" -eq 0 ]
}

@test "artifacts_summarize includes artifact_dir field" {
  mkdir -p "${OUTPUT_DIR}/US-017"
  run artifacts_summarize "${WORKSPACE_ROOT}" "${TICKET_ID}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'"artifact_dir"'* ]]
}

@test "artifacts are append-safe and do not overwrite other ticket artifacts" {
  mkdir -p "${OUTPUT_DIR}/US-001"
  mkdir -p "${OUTPUT_DIR}/US-017"
  printf '{"ticket": "US-001"}' > "${OUTPUT_DIR}/US-001/plan.json"
  printf '{"ticket": "US-017"}' > "${OUTPUT_DIR}/US-017/plan.json"

  # Reading US-017 should not affect US-001
  artifacts_read "${WORKSPACE_ROOT}" "US-017" "plan.json" > /dev/null

  us001_content=$(cat "${OUTPUT_DIR}/US-001/plan.json")
  [[ "${us001_content}" == *'"US-001"'* ]]
}

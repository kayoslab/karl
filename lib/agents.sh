#!/usr/bin/env bash
# agents.sh - Agent registry loading and prompt composition for karl

set -euo pipefail

# Required agent roles
AGENTS_REQUIRED_ROLES=(planner reviewer architect tester developer deployment)
export AGENTS_REQUIRED_ROLES

# Multi-instance agent roles (validated only when --instances > 1)
AGENTS_MULTI_ROLES=(coordinator merge_arbitrator)
export AGENTS_MULTI_ROLES

# Splitter agent role (validated when --split is passed)
AGENTS_SPLITTER_ROLE="splitter"
export AGENTS_SPLITTER_ROLE

# agents_get_contract_field <agent_file> <field>
# Extracts a single frontmatter field value from an agent markdown file.
# Supports both --- fenced and bare (top-of-file) frontmatter.
# Returns 0 and prints the value if found, 1 if the field is missing or empty.
agents_get_contract_field() {
  local agent_file="${1:?agent_file required}"
  local field="${2:?field required}"

  # Try --- fenced frontmatter first (between first and second --- delimiters)
  local value
  value=$(awk -v field="${field}" '
    NR==1 && /^---$/ { in_fm=1; next }
    in_fm && /^---$/ { exit }
    in_fm {
      if ($0 ~ "^" field ":[[:space:]]*") {
        sub("^" field ":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "${agent_file}")

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  # Fall back to bare frontmatter: search only until first blank line or heading
  value=$(awk -v field="${field}" '
    NR==1 && /^---$/ { exit }
    /^#/ { exit }
    /^$/ && NR > 1 { exit }
    {
      if ($0 ~ "^" field ":[[:space:]]*") {
        sub("^" field ":[[:space:]]*", "")
        print
        exit
      }
    }
  ' "${agent_file}")

  if [[ -n "${value}" ]]; then
    printf '%s\n' "${value}"
    return 0
  fi

  return 1
}

# agents_validate_contract <agent_file>
# Validates that an agent markdown file has all required contract fields:
# role, inputs, outputs, constraints.
# Returns 0 if all fields are present, 1 if any are missing.
agents_validate_contract() {
  local agent_file="${1:?agent_file required}"
  local missing=()

  for field in role inputs outputs constraints; do
    if ! agents_get_contract_field "${agent_file}" "${field}" > /dev/null 2>&1; then
      missing+=("${field}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Agent file $(basename "${agent_file}") missing contract fields: ${missing[*]}" >&2
    return 1
  fi

  return 0
}

# agents_validate <agents_dir>
# Validates all required agent markdown files exist in agents_dir and pass contract validation.
# Returns 0 if all required agents are present and valid, 1 otherwise.
agents_validate() {
  local agents_dir="${1:?agents_dir required}"
  local missing=()

  if [[ ! -d "${agents_dir}" ]]; then
    echo "ERROR: Agents directory not found: ${agents_dir}" >&2
    return 1
  fi

  for role in "${AGENTS_REQUIRED_ROLES[@]}"; do
    if [[ ! -f "${agents_dir}/${role}.md" ]]; then
      missing+=("${role}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing required agent definitions: ${missing[*]}" >&2
    return 1
  fi

  local contract_errors=0
  for role in "${AGENTS_REQUIRED_ROLES[@]}"; do
    if ! agents_validate_contract "${agents_dir}/${role}.md"; then
      contract_errors=$((contract_errors + 1))
    fi
  done

  if [[ ${contract_errors} -gt 0 ]]; then
    return 1
  fi

  return 0
}

# agents_validate_extra <agents_dir> <roles...>
# Validates additional agent roles beyond the core required set.
# Returns 0 if all specified roles exist and pass contract validation, 1 otherwise.
agents_validate_extra() {
  local agents_dir="${1:?agents_dir required}"
  shift
  local roles=("$@")
  local missing=()

  for role in "${roles[@]}"; do
    if [[ ! -f "${agents_dir}/${role}.md" ]]; then
      missing+=("${role}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    echo "ERROR: Missing agent definitions: ${missing[*]}" >&2
    return 1
  fi

  local contract_errors=0
  for role in "${roles[@]}"; do
    if ! agents_validate_contract "${agents_dir}/${role}.md"; then
      contract_errors=$((contract_errors + 1))
    fi
  done

  if [[ ${contract_errors} -gt 0 ]]; then
    return 1
  fi

  return 0
}

# agents_load [karl_dir]
# Validates the agent registry in <karl_dir>/Agents.
# Defaults to KARL_DIR (the karl installation directory) when called with no argument.
# Returns 0 on success, 1 on error.
agents_load() {
  local karl_dir="${1:-${KARL_DIR}}"
  local agents_dir="${karl_dir}/Agents"

  if ! agents_validate "${agents_dir}"; then
    return 1
  fi

  echo "[agents] Registry loaded from: ${agents_dir}"
  return 0
}

# agents_get_prompt <agents_dir> <role>
# Prints the prompt body for the given role (frontmatter stripped).
# Returns 0 on success, 1 if the agent file is not found.
agents_get_prompt() {
  local agents_dir="${1:?agents_dir required}"
  local role="${2:?role required}"
  local agent_file="${agents_dir}/${role}.md"

  if [[ ! -f "${agent_file}" ]]; then
    echo "ERROR: Agent file not found for role: ${role}" >&2
    return 1
  fi

  # Strip YAML frontmatter: skip content between first and second '---' delimiters
  awk 'NR==1 && /^---$/ {fm=1; next} fm && /^---$/ {fm=0; next} !fm {print}' "${agent_file}"
  return 0
}

# agents_compose_prompt <agents_dir> <role> <context_json>
# Composes a full agent prompt by combining the agent template with context.
# context_json keys: ticket, plan, adr, tech, tests
# Returns 0 on success, 1 on error.
agents_compose_prompt() {
  local agents_dir="${1:?agents_dir required}"
  local role="${2:?role required}"
  local context_json="${3}"
  [[ -n "${context_json}" ]] || context_json='{}'

  local prompt
  prompt=$(agents_get_prompt "${agents_dir}" "${role}") || return 1

  local ticket plan adr tech tests implementation failures mode
  ticket=$(printf '%s' "${context_json}" | jq -r '.ticket // ""')
  plan=$(printf '%s' "${context_json}" | jq -r '.plan // ""')
  adr=$(printf '%s' "${context_json}" | jq -r '.adr // ""')
  tech=$(printf '%s' "${context_json}" | jq -r '.tech // ""')
  tests=$(printf '%s' "${context_json}" | jq -r '.tests // ""')
  implementation=$(printf '%s' "${context_json}" | jq -r '.implementation // ""')
  failures=$(printf '%s' "${context_json}" | jq -r '.failures // ""')
  mode=$(printf '%s' "${context_json}" | jq -r '.mode // ""')

  # Use ENVIRON + str_replace for safe substitution of multi-line values.
  # awk -v cannot accept newlines; gsub mangles & and \ in replacements.
  printf '%s\n' "${prompt}" | \
    KARL_TICKET="${ticket}" \
    KARL_PLAN="${plan}" \
    KARL_ADR="${adr}" \
    KARL_TECH="${tech}" \
    KARL_TESTS="${tests}" \
    KARL_IMPLEMENTATION="${implementation}" \
    KARL_FAILURES="${failures}" \
    KARL_MODE="${mode}" \
    awk '
      function str_replace(hay, needle, rep,    result, pos, len) {
        result = ""
        len = length(needle)
        while ((pos = index(hay, needle)) > 0) {
          result = result substr(hay, 1, pos - 1) rep
          hay = substr(hay, pos + len)
        }
        return result hay
      }
      {
        line = $0
        line = str_replace(line, "{{ticket}}",         ENVIRON["KARL_TICKET"])
        line = str_replace(line, "{{plan}}",            ENVIRON["KARL_PLAN"])
        line = str_replace(line, "{{adr}}",             ENVIRON["KARL_ADR"])
        line = str_replace(line, "{{tech}}",            ENVIRON["KARL_TECH"])
        line = str_replace(line, "{{tests}}",           ENVIRON["KARL_TESTS"])
        line = str_replace(line, "{{implementation}}", ENVIRON["KARL_IMPLEMENTATION"])
        line = str_replace(line, "{{failures}}",        ENVIRON["KARL_FAILURES"])
        line = str_replace(line, "{{mode}}",            ENVIRON["KARL_MODE"])
        print line
      }
    '
}

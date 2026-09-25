#!/usr/bin/env bash
# JSON emission helpers (CONTRACT.md "JSON output contract"). Sourced.

[[ -n "${_WIT_JSON_LOADED:-}" ]] && return 0
readonly _WIT_JSON_LOADED=1

readonly WIT_SCHEMA_VERSION="1.0"
export WIT_SCHEMA_VERSION

# wit_strip_cr — stdin filter removing carriage returns (Windows/Git Bash can
# contaminate captured command output; stdout must be CR-free).
wit_strip_cr() {
  tr -d '\r'
}

# wit_check_contract_version <provider> <manifest-path>: CONTRACT.md "Contract-version
# handshake". Returns 1 on a missing or major-skewed schema_version; callers map it to exit 3.
wit_check_contract_version() {
  local provider="$1" manifest="$2" declared core_major core_minor a_major a_minor
  declared="$(jq -r '.schema_version // empty' "$manifest" 2>/dev/null)"
  if [[ ! "$declared" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "work-item-tracker: adapter '%s' capabilities.json declares no valid schema_version (need MAJOR.MINOR; found: %s) — cannot handshake with core contract v%s\n" \
      "$provider" "${declared:-none}" "$WIT_SCHEMA_VERSION" >&2
    return 1
  fi
  # Base-10 forced: bare (( )) reads a leading zero ("08.0") as octal and errors, and
  # an errored condition is falsy, which would wave a skewed adapter through.
  core_major=$((10#${WIT_SCHEMA_VERSION%%.*}))
  core_minor=$((10#${WIT_SCHEMA_VERSION#*.}))
  a_major=$((10#${declared%%.*}))
  a_minor=$((10#${declared#*.}))
  if ((a_major != core_major)); then
    if ((a_major > core_major)); then
      printf "work-item-tracker: adapter '%s' speaks contract v%s but this core speaks v%s — update the work-items plugin\n" \
        "$provider" "$declared" "$WIT_SCHEMA_VERSION" >&2
    else
      printf "work-item-tracker: adapter '%s' speaks contract v%s but this core speaks v%s — update or regenerate the adapter\n" \
        "$provider" "$declared" "$WIT_SCHEMA_VERSION" >&2
    fi
    return 1
  fi
  if ((a_minor > core_minor)); then
    printf "work-item-tracker: adapter '%s' declares contract v%s, newer than core v%s — proceeding; unknown additive fields are ignored (update the work-items plugin to consume them)\n" \
      "$provider" "$declared" "$WIT_SCHEMA_VERSION" >&2
  fi
  return 0
}

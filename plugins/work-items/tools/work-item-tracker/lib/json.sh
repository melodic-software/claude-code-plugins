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

# wit_check_contract_version <provider> <manifest-path> — directional
# tolerant-reader handshake between the core's contract version
# (WIT_SCHEMA_VERSION) and the adapter manifest's declared schema_version
# (CONTRACT.md "Contract-version handshake"). Adapters resolve consumer-local
# first, so a consumer-owned, shadowing, or generated adapter can legitimately
# be built against a different contract revision than the engine dispatching to
# it — without this check the skew is silent. Semantics (standards-contract
# precedent — tolerate minor skew loudly where it matters, refuse major skew):
#   - missing/malformed schema_version → refuse (return 1): an unversioned
#     manifest cannot handshake; consumer/generated adapters must declare one.
#   - major mismatch (either direction) → refuse (return 1), stderr naming both
#     versions and the direction-appropriate fix.
#   - same major, adapter minor > core → proceed with a stderr notice: the
#     tolerant reader ignores additive fields it does not know.
#   - same major, adapter minor <= core → proceed silently: newer-core additive
#     fields are optional by definition, so an older adapter simply omits them.
# Callers map a refusal to exit 3 (config invalid — a first-run/setup signal).
wit_check_contract_version() {
  local provider="$1" manifest="$2" declared core_major core_minor a_major a_minor
  declared="$(jq -r '.schema_version // empty' "$manifest" 2>/dev/null)"
  if [[ ! "$declared" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "work-item-tracker: adapter '%s' capabilities.json declares no valid schema_version (need MAJOR.MINOR; found: %s) — cannot handshake with core contract v%s\n" \
      "$provider" "${declared:-none}" "$WIT_SCHEMA_VERSION" >&2
    return 1
  fi
  core_major="${WIT_SCHEMA_VERSION%%.*}"
  core_minor="${WIT_SCHEMA_VERSION#*.}"
  a_major="${declared%%.*}"
  a_minor="${declared#*.}"
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

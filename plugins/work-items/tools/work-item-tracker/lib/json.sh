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

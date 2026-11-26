#!/usr/bin/env bash

[[ -n "${_WIT_JSON_LOADED:-}" ]] && return 0
readonly _WIT_JSON_LOADED=1

readonly WIT_SCHEMA_VERSION="1.0"
export WIT_SCHEMA_VERSION

# shellcheck disable=SC2016,SC2034  # jq program text; read by the adapters that source this file
readonly WIT_JQ_DEF_UTC_TS='def wit_utc_ts:
  if type != "string" then null
  else (try (capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})$")
      | (.z | sub(":"; "")) as $z
      | ((.d + "Z") | fromdateiso8601)
        - (if $z == "Z" then 0
           else (if $z[0:1] == "-" then -1 else 1 end)
             * (($z[1:3] | tonumber) * 3600 + ($z[3:5] | tonumber) * 60) end)
      | todateiso8601) catch null) // null
  end;'

wit_strip_cr() {
  tr -d '\r'
}

wit_check_contract_version() {
  local provider="$1" manifest="$2" declared core_major core_minor a_major a_minor fix
  declared="$(jq -r '.schema_version // empty' "$manifest" 2>/dev/null)"
  if [[ ! "$declared" =~ ^[0-9]+\.[0-9]+$ ]]; then
    printf "work-item-tracker: adapter '%s' capabilities.json declares no valid schema_version (need MAJOR.MINOR; found: %s) — cannot handshake with core contract v%s\n" \
      "$provider" "${declared:-none}" "$WIT_SCHEMA_VERSION" >&2
    return 1
  fi
  core_major=$((10#${WIT_SCHEMA_VERSION%%.*}))
  core_minor=$((10#${WIT_SCHEMA_VERSION#*.}))
  a_major=$((10#${declared%%.*}))
  a_minor=$((10#${declared#*.}))
  if ((a_major != core_major)); then
    fix="update or regenerate the adapter"
    ((a_major > core_major)) && fix="update the work-items plugin"
    printf "work-item-tracker: adapter '%s' speaks contract v%s but this core speaks v%s — %s\n" \
      "$provider" "$declared" "$WIT_SCHEMA_VERSION" "$fix" >&2
    return 1
  fi
  if ((a_minor > core_minor)); then
    printf "work-item-tracker: adapter '%s' declares contract v%s, newer than core v%s — proceeding; unknown additive fields are ignored (update the work-items plugin to consume them)\n" \
      "$provider" "$declared" "$WIT_SCHEMA_VERSION" >&2
  fi
  return 0
}

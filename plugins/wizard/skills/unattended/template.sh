#!/usr/bin/env bash
# Unattended procedure library. The agent authors stages below the marker and
# never executes this script. The human launches it once, outside the agent.
#
# Result: $RESULT_DIR/<name>.json and <name>-latest.json. Secrets resolved at
# runtime are scrubbed from that JSON and from the transcript log.
#
# Source the library in tests with UNATTENDED_LIB_ONLY=1. A normal run calls
# stages, then writes the result.
set -euo pipefail

RESULT_DIR="${RESULT_DIR:-./unattended-result}"
RESULT_NAME="${RESULT_NAME:-result}"
FORCE="${FORCE:-0}"
TRANSCRIPT=""
OVERALL="ok"
declare -a STEP_IDS=() STEP_STATUS=() STEP_DETAIL=()
declare -a WARNINGS=() HELD=() SECRETS=()

env_value() {
  local name="$1" value=""
  if [[ -v $name ]]; then
    value="${!name}"
  fi
  printf '%s' "$value"
}

json_escape() {
  local s="$1"
  s=${s//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "$s"
}

scrub() {
  local s="$1" secret
  for secret in "${SECRETS[@]+"${SECRETS[@]}"}"; do
    [[ -n "$secret" ]] || continue
    s=${s//"$secret"/[redacted]}
  done
  printf '%s' "$s"
}

log_line() {
  local line
  line="$(scrub "$1")"
  [[ -n "$TRANSCRIPT" ]] || return 0
  printf '%s\n' "$line" >>"$TRANSCRIPT"
}

prior_status() {
  local id="$1" file="$RESULT_DIR/${RESULT_NAME}-latest.json" row
  [[ -f "$file" ]] || return 1
  # The library writes one step object with a space after each colon. Match
  # that object only, so a later failed step with the same id does not count.
  row="$(grep -F "\"id\": \"$(json_escape "$id")\"" "$file" 2>/dev/null || true)"
  [[ "$row" == *'"status": "ok"'* ]]
}

record_step() {
  local id="$1" status="$2" detail
  detail="$(scrub "$3")"
  STEP_IDS+=("$id")
  STEP_STATUS+=("$status")
  STEP_DETAIL+=("$detail")
  log_line "step $id $status $detail"
  if [[ "$status" == "failed" ]]; then
    OVERALL="failed"
  fi
}

run_step() {
  local id="$1"
  shift
  if [[ "$FORCE" != "1" ]] && prior_status "$id"; then
    record_step "$id" "skipped" "already ok"
    return 0
  fi
  if "$@"; then
    record_step "$id" "ok" "done"
    return 0
  fi
  record_step "$id" "failed" "command failed ($*)"
  return 1
}

preflight_bin() {
  local bin="$1" remedy="$2"
  if command -v "$bin" >/dev/null 2>&1; then
    record_step "preflight-$bin" "ok" "present"
    return 0
  fi
  record_step "preflight-$bin" "failed" "missing $bin; $remedy"
  return 1
}

require_root() {
  if [[ "$(id -u)" -eq 0 ]]; then
    record_step "privilege" "ok" "running as root"
    return 0
  fi
  record_step "privilege" "failed" "this script must run elevated (id -u is not 0)"
  return 1
}

require_user() {
  if [[ "$(id -u)" -ne 0 ]]; then
    record_step "privilege" "ok" "not root"
    return 0
  fi
  record_step "privilege" "failed" "this script must not run elevated"
  return 1
}

refuse_if_env() {
  local name="$1" banned="$2" current=""
  current="$(env_value "$name")"
  if [[ -n "$banned" && "$current" == "$banned" ]]; then
    record_step "not-inside" "failed" "refusing to run inside $name=$banned"
    return 1
  fi
  record_step "not-inside" "ok" "$name is not $banned"
  return 0
}

resolve_secret() {
  local name="$1" file="${2:-}" line key value
  value="$(env_value "$name")"
  if [[ -n "$value" ]]; then
    SECRETS+=("$value")
    printf '%s' "$value"
    return 0
  fi
  if [[ -n "$file" && -f "$file" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ "$line" == "$name="* ]] || continue
      value="${line#"$name="}"
      SECRETS+=("$value")
      printf '%s' "$value"
      return 0
    done <"$file"
  fi
  if [[ -r /dev/tty ]]; then
    printf 'Enter %s (hidden): ' "$name" >/dev/tty
    IFS= read -r -s value </dev/tty || value=""
    printf '\n' >/dev/tty
    SECRETS+=("$value")
    printf '%s' "$value"
    return 0
  fi
  record_step "secret-$name" "failed" "no env, file, or tty for $name"
  return 1
}

hold() {
  HELD+=("$1")
  log_line "hold $1"
}

release() {
  local name="$1" kept=() item
  for item in "${HELD[@]+"${HELD[@]}"}"; do
    [[ "$item" == "$name" ]] || kept+=("$item")
  done
  HELD=("${kept[@]+"${kept[@]}"}")
  log_line "release $name"
}

write_result() {
  local file latest id status detail warning held i
  mkdir -p "$RESULT_DIR"
  TRANSCRIPT="${TRANSCRIPT:-$RESULT_DIR/${RESULT_NAME}.log}"
  file="$RESULT_DIR/${RESULT_NAME}.json"
  latest="$RESULT_DIR/${RESULT_NAME}-latest.json"
  {
    printf '{\n'
    printf '  "schema": "wizard-unattended/1",\n'
    printf '  "status": "%s",\n' "$OVERALL"
    printf '  "transcript": "%s",\n' "$(json_escape "$TRANSCRIPT")"
    printf '  "steps": [\n'
    for i in "${!STEP_IDS[@]}"; do
      [[ "$i" -gt 0 ]] && printf ',\n'
      printf '    {"id": "%s", "status": "%s", "detail": "%s"}' \
        "$(json_escape "${STEP_IDS[$i]}")" \
        "$(json_escape "${STEP_STATUS[$i]}")" \
        "$(json_escape "${STEP_DETAIL[$i]}")"
    done
    printf '\n  ],\n'
    printf '  "warnings": [\n'
    for i in "${!WARNINGS[@]}"; do
      [[ "$i" -gt 0 ]] && printf ',\n'
      printf '    "%s"' "$(json_escape "$(scrub "${WARNINGS[$i]}")")"
    done
    printf '\n  ],\n'
    printf '  "held": [\n'
    for i in "${!HELD[@]}"; do
      [[ "$i" -gt 0 ]] && printf ',\n'
      printf '    "%s"' "$(json_escape "${HELD[$i]}")"
    done
    printf '\n  ]\n'
    printf '}\n'
  } >"$file"
  cp "$file" "$latest"
  # A failure that still holds a shared resource says so in the status. The
  # human does not paste the log back; the agent reads the JSON.
  if [[ "$OVERALL" == "failed" && ${#HELD[@]} -gt 0 ]]; then
    log_line "failed while holding: ${HELD[*]}"
  fi
}

if [[ "${UNATTENDED_LIB_ONLY:-}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

mkdir -p "$RESULT_DIR"
TRANSCRIPT="$RESULT_DIR/${RESULT_NAME}.log"
: >"$TRANSCRIPT"

# --- STAGES (replace this function; do not edit above) ---
stages() {
  require_user || return 1
  preflight_bin bash "install bash" || return 1
  run_step example true || return 1
}

stages
write_result
[[ "$OVERALL" == "ok" ]]

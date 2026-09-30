#!/usr/bin/env bash
# Fail when an ACTIVE skill-portability token duplicates or drifts from the
# org-agnosticism SSOT (docs/plugin-philosophy.md Design boundary; #4582).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

ORG_FILE="${PUBLISHER_TOKEN_ORG_FILE:-scripts/org-agnosticism-tokens.txt}"
PORT_FILE="${PUBLISHER_TOKEN_PORT_FILE:-scripts/skill-portability-tokens.txt}"

[[ -f "$ORG_FILE" && -f "$PORT_FILE" ]] || {
  printf 'ERROR: missing token file (%s or %s)\n' "$ORG_FILE" "$PORT_FILE" >&2
  exit 2
}

# Lines go through the portability gate's parser (read_list, `leading`
# comments), so both sides compare with surrounding whitespace trimmed.
# shellcheck source=lib/read-list.sh
source scripts/lib/read-list.sh || exit 2

org_lines=() pattern=() port_active=()
read_list::into org_lines "$ORG_FILE" --comments leading || exit 2
org_patterns=()
for line in "${org_lines[@]}"; do
  read_list::into_text pattern "${line#*[[:space:]]}" --comments leading || exit 2
  org_patterns+=("${pattern[@]}")
done

active_text=""
in_active=0
saw_active=0
while IFS= read -r line; do
  if [[ "$line" =~ ^#[[:space:]]*---[[:space:]]*ACTIVE ]]; then
    in_active=1
    saw_active=1
    continue
  fi
  if [[ "$line" =~ ^#[[:space:]]*---[[:space:]]*STAGED ]]; then
    in_active=0
    continue
  fi
  ((in_active == 1)) && active_text+="$line"$'\n'
done <"$PORT_FILE"
read_list::into_text port_active "$active_text" --comments leading || exit 2

# An input the gate cannot use must not read as a clean pass: nothing was compared.
((saw_active == 1)) || {
  printf 'ERROR: no "# --- ACTIVE" marker in %s\n' "$PORT_FILE" >&2
  exit 2
}
((${#port_active[@]} > 0)) || {
  printf 'ERROR: no active tokens under "# --- ACTIVE" in %s\n' "$PORT_FILE" >&2
  exit 2
}
((${#org_patterns[@]} > 0)) || {
  printf 'ERROR: no org patterns in %s\n' "$ORG_FILE" >&2
  exit 2
}

org_member() {
  local needle="$1" o
  for o in "${org_patterns[@]}"; do
    [[ "$needle" == "$o" ]] && return 0
  done
  return 1
}

publisher_like() {
  local p="$1"
  [[ "$p" == *'@melodic-software'* || "$p" == *'MELODIC_'* || "$p" == *'melodic-software'* ]]
}

failed=0
for p in "${port_active[@]}"; do
  if org_member "$p"; then
    continue
  fi
  if publisher_like "$p"; then
    printf 'FAIL: active portability token matches publisher class but is absent from %s: %s\n' "$ORG_FILE" "$p" >&2
    failed=1
  fi
done

if ((failed > 0)); then
  exit 1
fi
printf 'check-publisher-token-alignment: PASS (%d active portability tokens, %d org patterns)\n' \
  "${#port_active[@]}" "${#org_patterns[@]}"
exit 0

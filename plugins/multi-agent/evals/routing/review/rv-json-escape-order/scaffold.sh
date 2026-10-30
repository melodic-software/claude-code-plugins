#!/usr/bin/env bash
# Stages scripts/resolve-roles.sh after a proposed change and writes the change
# to change.diff. The change splits json_str into one step per escape and runs
# the quote escape before the backslash escape, so the backslash it adds before
# a quote in the target or a note is doubled and the JSON string ends early (the
# seeded defect). It also routes both note helpers through one shared note
# function, which changes no behavior (the decoy).
set -euo pipefail

base="$(mktemp -d)"
trap 'rm -rf "$base"' EXIT
mkdir -p "$base/scripts" scripts

cat >"$base/scripts/resolve-roles.sh" <<'SH'
#!/usr/bin/env bash
# Resolves each role's model and effort and prints one JSON object.
set -euo pipefail

ROLES=(orchestrator worker verifier retrieval)
NOTES=()
TARGET="${1:-all}"

note_layer_skip() {
  local label="$1" path="$2"
  NOTES+=("$label layer skipped: $path does not declare schema: 1")
}

note_unknown_role() {
  local label="$1" key="$2" role="$3"
  NOTES+=("$label: $key ignored: unknown role '$role' (valid: ${ROLES[*]})")
}

json_str() {
  local s="${1//\\/\\\\}"
  printf '"%s"' "${s//\"/\\\"}"
}

join() {
  local IFS=,
  printf '%s' "$*"
}

notes_json=()
for n in "${NOTES[@]+"${NOTES[@]}"}"; do
  notes_json+=("$(json_str "$n")")
  printf 'resolve-roles: %s\n' "$n" >&2
done

printf '{"target":%s,"notes":[%s]}\n' "$(json_str "$TARGET")" "$(join "${notes_json[@]+"${notes_json[@]}"}")"
SH

cat >scripts/resolve-roles.sh <<'SH'
#!/usr/bin/env bash
# Resolves each role's model and effort and prints one JSON object.
set -euo pipefail

ROLES=(orchestrator worker verifier retrieval)
NOTES=()
TARGET="${1:-all}"

note() {
  NOTES+=("$1")
}

note_layer_skip() {
  local label="$1" path="$2"
  note "$label layer skipped: $path does not declare schema: 1"
}

note_unknown_role() {
  local label="$1" key="$2" role="$3"
  note "$label: $key ignored: unknown role '$role' (valid: ${ROLES[*]})"
}

# Escapes one string for JSON, one character class per step.
json_str() {
  local s="$1"
  s="${s//\"/\\\"}"
  s="${s//\\/\\\\}"
  printf '"%s"' "$s"
}

join() {
  local IFS=,
  printf '%s' "$*"
}

notes_json=()
for n in "${NOTES[@]+"${NOTES[@]}"}"; do
  notes_json+=("$(json_str "$n")")
  printf 'resolve-roles: %s\n' "$n" >&2
done

printf '{"target":%s,"notes":[%s]}\n' "$(json_str "$TARGET")" "$(join "${notes_json[@]+"${notes_json[@]}"}")"
SH

diff -u --label a/scripts/resolve-roles.sh --label b/scripts/resolve-roles.sh \
  "$base/scripts/resolve-roles.sh" scripts/resolve-roles.sh >change.diff || test $? -eq 1

#!/usr/bin/env bash
# Stages two scripts that each own a NOTES array, so a rename scoped to one file
# has a same-named neighbor it must leave alone.
set -euo pipefail

mkdir -p scripts

cat >scripts/resolve-roles.sh <<'SH'
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

cat >scripts/route.sh <<'SH'
#!/usr/bin/env bash
# Prints the resolved route for one role and workload.
set -euo pipefail

NOTES=()
ROLE="${1:?usage: route.sh <role> [workload]}"
WORKLOAD="${2:-}"

if [[ -n "$WORKLOAD" && "$WORKLOAD" != mechanical ]]; then
  NOTES+=("workload $WORKLOAD is not declared; using the role default")
fi

printf 'route: %s %s\n' "$ROLE" "${WORKLOAD:-default}"
for n in "${NOTES[@]+"${NOTES[@]}"}"; do
  printf 'note: %s\n' "$n"
done
SH

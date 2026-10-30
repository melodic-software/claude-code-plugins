#!/usr/bin/env bash
# Stages scripts/route.sh and findings.md, four findings a reviewer raised
# against it. F2 and F4 are real defects: the unquoted right-hand side of `==`
# in is_member makes the needle a glob pattern, and the workload check tests
# membership in ROLES where it means WORKLOADS. F1 and F3 are false: set -e
# does not fire on a failed test inside an && list (and is_member always runs
# under `if !`), and the `+` expansion of NOTES yields every element.
set -euo pipefail

mkdir -p scripts

cat >scripts/route.sh <<'SH'
#!/usr/bin/env bash
# Prints the resolved route for one role and workload.
# Usage: route.sh <role> [workload]
set -euo pipefail

ROLES=(orchestrator worker verifier retrieval)
WORKLOADS=(code research mechanical)
NOTES=()

usage() {
  printf 'usage: route.sh <role> [workload]\n' >&2
  exit 2
}

# Succeeds when the first argument equals one of the rest.
is_member() {
  local needle="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == $needle ]] && return 0
  done
  return 1
}

ROLE="${1:-}"
WORKLOAD="${2:-}"
[[ -n "$ROLE" ]] || usage
if ! is_member "$ROLE" "${ROLES[@]}"; then
  printf 'route.sh: unknown role %s (valid: %s)\n' "$ROLE" "${ROLES[*]}" >&2
  exit 2
fi

if [[ -n "$WORKLOAD" ]] && ! is_member "$WORKLOAD" "${ROLES[@]}"; then
  NOTES+=("workload $WORKLOAD is not declared; using the role default")
  WORKLOAD=""
fi

printf 'route: %s %s\n' "$ROLE" "${WORKLOAD:-default}"
for n in "${NOTES[@]+"${NOTES[@]}"}"; do
  printf 'note: %s\n' "$n"
done
SH

cat >findings.md <<'MD'
# Review findings: scripts/route.sh

F1. `is_member` runs under `set -e`, so the first time `[[ "$item" == $needle ]]` is false the
whole script exits with status 1 before the loop reaches a later item. Only `orchestrator`, the
first entry in `ROLES`, can ever route.

F2. In `is_member`, the right-hand side of `==` is unquoted, so `[[ ]]` reads the needle as a glob
pattern. `route.sh '*'` or `route.sh 'w*'` passes the role check and prints a route for a role that
does not exist.

F3. `"${NOTES[@]+"${NOTES[@]}"}"` expands to a single word, so when more than one note is added the
loop prints only the first and drops the rest.

F4. The workload check passes `"${ROLES[@]}"` to `is_member` where it means `"${WORKLOADS[@]}"`, so
`route.sh worker code` reports `code` as not declared and prints the role default instead.
MD

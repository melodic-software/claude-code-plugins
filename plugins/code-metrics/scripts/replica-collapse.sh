# shellcheck shell=bash
# Sourced by the dispatcher and by every entry point that assembles a document
# of its own: apply the sanctioned-replication registries the resolved
# configuration names (`scope.registries`, or `duplication.registries` as the
# older name) to a `code-metrics/v1` document, so one collapse rule serves
# every audit and a report assembled outside the dispatcher (audit-coverage's
# join) is collapsed the same way.
#
#   cm_registry_paths <resolved.json>            print one resolved registry path per line;
#                                                return 2 with a message when one does not exist
#   cm_collapse_replicas <resolved.json> <in> <out>
#                                                write <in> to <out> with replicas collapsed and
#                                                the summary recomputed; a plain copy when no
#                                                registry is configured; return 2 on an error
#
# A registry path is taken as given, else under the repository root, because
# a team file names it root-relative and an audit may run from a subdirectory;
# one that exists nowhere is a configuration error, never an empty registry.
# The caller supplies `PY` (from python-resolve.sh).
# shellcheck disable=SC2154

CM_REPLICA_LIB_DIR="$(cd "${BASH_SOURCE[0]%/*}" && pwd)"

cm_registry_paths() {
  local config="$1" top registry list configured=()
  list="$(mktemp)"
  if ! "${PY[@]}" "$CM_REPLICA_LIB_DIR/resolve-config.py" --from-json "$config" --format registries >"$list"; then
    rm -f "$list"
    printf 'scope.registries could not be read from the resolved configuration (see the message above)\n' >&2
    return 2
  fi
  mapfile -t configured <"$list"
  rm -f "$list"
  top="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$top" ]] || top="$PWD"
  for registry in ${configured[@]+"${configured[@]}"}; do
    [[ -n "$registry" ]] || continue
    if [[ -f "$registry" ]]; then
      printf '%s\n' "$registry"
    elif [[ -f "$top/$registry" ]]; then
      printf '%s\n' "$top/$registry"
    else
      printf 'scope.registries: registry not found: %s\n' "$registry" >&2
      return 2
    fi
  done
}

cm_collapse_replicas() {
  local config="$1" input="$2" output="$3" paths args=() registry collapsed
  paths="$(cm_registry_paths "$config")" || return 2
  if [[ -z "$paths" ]]; then
    cp "$input" "$output"
    return 0
  fi
  args=(--prefix "$(git rev-parse --show-prefix 2>/dev/null || true)")
  while IFS= read -r registry; do
    [[ -n "$registry" ]] && args+=(--registry "$registry")
  done <<<"$paths"
  collapsed="$(mktemp)"
  if ! "${PY[@]}" "$CM_REPLICA_LIB_DIR/replica-collapse.py" "${args[@]}" <"$input" >"$collapsed"; then
    rm -f "$collapsed"
    return 2
  fi
  if ! "${PY[@]}" "$CM_REPLICA_LIB_DIR/report.py" resummarize <"$collapsed" >"$output"; then
    rm -f "$collapsed"
    return 2
  fi
  rm -f "$collapsed"
}

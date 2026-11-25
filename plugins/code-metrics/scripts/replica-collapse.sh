# shellcheck shell=bash
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
  local config="$1" input="$2" output="$3" paths args=() registry collapsed rc=0
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
  "${PY[@]}" "$CM_REPLICA_LIB_DIR/replica-collapse.py" "${args[@]}" <"$input" >"$collapsed" &&
    "${PY[@]}" "$CM_REPLICA_LIB_DIR/report.py" resummarize <"$collapsed" >"$output" || rc=2
  rm -f "$collapsed"
  return "$rc"
}

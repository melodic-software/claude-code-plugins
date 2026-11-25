#!/usr/bin/env bash
# GENERATED from lib/fleet-discovery.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.

FLEET_DEFAULT_SKIP_NAMES=(vendor node_modules .venv .pnpm-store .yarn .npm .cargo .rustup .gradle .m2
  .nuget __pycache__ .tox)

validate_skip_name() {
  local name="$1" origin="$2"
  [[ -n "$name" ]] || fail "invalid ${origin} value (expected a bare directory name): (empty)"
  case "$name" in
  */* | *\\*)
    fail "invalid ${origin} value (expected a bare directory name, no path separator): $name"
    ;;
  *) ;;
  esac
}

fleet_config_values() {
  ${FLEET_GIT_CMD:-git} config --file "$1" --null --get-all "$2" 2>/dev/null || true
}

resolve_input_path() {
  local value="$1" base="$2"
  if [[ "$value" =~ ^/ || "$value" =~ ^[A-Za-z]:[\\/] ]]; then
    printf '%s\n' "$value"
  else
    printf '%s/%s\n' "$base" "$value"
  fi
}

fleet_load_config_scope() {
  local file="$1" base="$2" value
  FLEET_CONFIG_ROOTS=()
  FLEET_CONFIG_REPOS=()
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && FLEET_CONFIG_ROOTS+=("$(resolve_input_path "$value" "$base")")
  done < <(fleet_config_values "$file" fleet.root)
  while IFS= read -r -d '' value; do
    [[ -n "$value" ]] && FLEET_CONFIG_REPOS+=("$(resolve_input_path "$value" "$base")")
  done < <(fleet_config_values "$file" fleet.repo)
}

fleet_load_config_skip() {
  local file="$1" value
  while IFS= read -r -d '' value; do
    validate_skip_name "$value" "fleet.skip"
    SKIP_NAMES+=("$value")
  done < <(fleet_config_values "$file" fleet.skip)
  while IFS= read -r -d '' value; do
    validate_skip_name "$value" "fleet.skipAppend"
    SKIP_APPEND_NAMES+=("$value")
  done < <(fleet_config_values "$file" fleet.skipAppend)
}

fleet_finalize_skip_names() {
  [[ ${#SKIP_NAMES[@]} -gt 0 ]] || SKIP_NAMES=("${FLEET_DEFAULT_SKIP_NAMES[@]}")
  [[ ${#SKIP_APPEND_NAMES[@]} -eq 0 ]] || SKIP_NAMES+=("${SKIP_APPEND_NAMES[@]}")
}

fleet_resolve_max_depth() {
  local value="$1" file="${2:-}"
  if [[ -z "$value" && -n "$file" ]]; then
    value="$(${FLEET_GIT_CMD:-git} config --file "$file" --get fleet.maxDepth 2>/dev/null || true)"
  fi
  value="${value:-5}"
  [[ "$value" =~ ^[0-9]+$ && "$value" -ge 1 && "$value" -le 12 ]] ||
    fail "max depth must be an integer from 1 through 12"
  FLEET_MAX_DEPTH="$value"
}

should_skip_dir_name() {
  local name="$1" skip
  case "$name" in
  . | .. | .git) return 0 ;;
  *) ;;
  esac
  for skip in "${SKIP_NAMES[@]}"; do
    [[ -n "$skip" && "$name" == "$skip" ]] && return 0
  done
  return 1
}

fleet_on_repo() { printf '%s\n' "$1"; }
fleet_on_symlink() { :; }
fleet_on_unreadable() { :; }

fleet_discover_root() {
  local dir="$1" depth="${2:-0}" child
  [[ -d "$dir" && ! -L "$dir" ]] || return 0
  if [[ ! -r "$dir" || ! -x "$dir" ]]; then
    if [[ -e "$dir/.git" ]]; then fleet_on_unreadable "$dir" 1; else fleet_on_unreadable "$dir" 0; fi
    return 0
  fi
  if [[ -d "$dir/.git" || -f "$dir/.git" ]]; then
    fleet_on_repo "$dir"
    return 0
  fi
  [[ "$depth" -lt "${FLEET_MAX_DEPTH:-5}" ]] || return 0
  for child in "$dir"/* "$dir"/.[!.]* "$dir"/..?*; do
    [[ -e "$child" || -L "$child" ]] || continue
    should_skip_dir_name "${child##*/}" && continue
    if [[ -L "$child" && -d "$child" ]]; then
      fleet_on_symlink "$child"
      continue
    fi
    [[ -d "$child" ]] || continue
    fleet_discover_root "$child" $((depth + 1))
  done
}

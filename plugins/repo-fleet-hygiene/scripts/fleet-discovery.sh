#!/usr/bin/env bash
# Shared discovery inputs for repo-fleet-hygiene: the default skip list, skip-name resolution,
# fleet config scope loading, and find-based root discovery. Sourced by audit and sync; the caller
# defines fail() and may set FLEET_GIT_CMD to a wrapper that runs git (default: git).
#
# Skip rules: an explicit --skip or fleet.skip entry REPLACES the default set, and --extend-skip or
# fleet.skipAppend entries ADD to whichever set is in effect. Callers collect entries into
# SKIP_NAMES and SKIP_APPEND_NAMES, then call fleet_finalize_skip_names.

# Package-manager cache trees never hold an operator's repository, and pnpm and uv lay junctions
# and bare .git markers inside them.
FLEET_DEFAULT_SKIP_NAMES=(vendor node_modules .venv .pnpm-store .yarn .npm .cargo .rustup .gradle .m2
  .nuget __pycache__ .tox)

# Bare directory-name validation for --skip / fleet.skip. Reject empty values and anything with a
# path separator so a mistaken path cannot silently widen or narrow discovery.
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

# fleet_config_values <config file> <key>: NUL-delimited values of a repeatable key.
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

# fleet_load_config_scope <config file> <base dir>: set FLEET_CONFIG_ROOTS and FLEET_CONFIG_REPOS
# from fleet.root and fleet.repo. Relative entries resolve against <base dir>, the config file's
# directory, never the caller's cwd.
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

# fleet_load_config_skip <config file>: append fleet.skip to SKIP_NAMES and fleet.skipAppend to
# SKIP_APPEND_NAMES.
fleet_load_config_skip() {
  local file="$1" value
  while IFS= read -r -d '' value; do
    # Empty fleet.skip values hard-fail (same contract as --skip ''), including a bare
    # `skip =` line that git-config returns as an empty string. Do not silently drop them:
    # an empty-only list would otherwise restore the defaults and quietly omit vendor/.
    validate_skip_name "$value" "fleet.skip"
    SKIP_NAMES+=("$value")
  done < <(fleet_config_values "$file" fleet.skip)
  while IFS= read -r -d '' value; do
    validate_skip_name "$value" "fleet.skipAppend"
    SKIP_APPEND_NAMES+=("$value")
  done < <(fleet_config_values "$file" fleet.skipAppend)
}

fleet_finalize_skip_names() {
  if [[ ${#SKIP_NAMES[@]} -eq 0 ]]; then
    SKIP_NAMES=("${FLEET_DEFAULT_SKIP_NAMES[@]}")
  fi
  [[ ${#SKIP_APPEND_NAMES[@]} -eq 0 ]] || SKIP_NAMES+=("${SKIP_APPEND_NAMES[@]}")
}

# fleet_discover_root <root>: print each Git checkout under <root>, pruning SKIP_NAMES and never
# descending into a .git directory.
fleet_discover_root() {
  local root="$1" name gitdir
  local prune=()
  [[ -d "$root" ]] || return 0
  for name in "${SKIP_NAMES[@]}"; do
    prune+=(${prune[@]+-o} -name "$name")
  done
  while IFS= read -r gitdir; do
    dirname "$gitdir"
  done < <(find "$root" -maxdepth "${FLEET_DISCOVERY_MAX_DEPTH:-5}" \( "${prune[@]}" \) -prune -o -name .git -print -prune 2>/dev/null)
}

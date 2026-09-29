#!/usr/bin/env bash
# Shared discovery for repo-fleet-hygiene: the default skip list, skip-name resolution, fleet config
# scope and depth loading, and the one repository walker. Sourced by audit and sync; the caller
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

# fleet_resolve_max_depth <explicit value> [<config file>]: set FLEET_MAX_DEPTH from the explicit
# value, else the config's fleet.maxDepth, else 5. Fails unless the result is an integer from 1
# through 12.
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
  # This arm is defense in depth, not a live guard: no input reaching the sole caller
  # (fleet_discover_root's child loop) can match it. `.` and `..` can never BE a child basename —
  # the loop's globs are "$dir"/* (no dotfiles), "$dir"/.[!.]* and "$dir"/..?*, none of which can
  # yield `.` or `..`. And for `.git`, the nested-repository early return fires first on the
  # identical path and predicate, so the loop never runs for a directory holding one. The arm is
  # kept so a future refactor of that early return cannot silently start walking `.git` internals.
  # Its contract is asserted directly in audit-fleet.test.sh, because no discovery-level test can
  # observe it (#2844).
  case "$name" in
  . | .. | .git) return 0 ;;
  *) ;;
  esac
  for skip in "${SKIP_NAMES[@]}"; do
    [[ -n "$skip" && "$name" == "$skip" ]] && return 0
  done
  return 1
}

# Discovery reports through three hooks. A caller that needs more than the checkout path redefines
# them after sourcing this file, and must then call fleet_discover_root in its own shell, not in a
# command substitution or a pipe, so the hooks' state survives.
#   fleet_on_repo <dir>: <dir> holds a .git marker. Default: print it.
#   fleet_on_symlink <path>: a symlinked directory that was not followed. Default: ignore.
#   fleet_on_unreadable <dir> <0|1>: <dir> cannot be entered; 1 when it shows a .git marker.
#     Default: ignore.
fleet_on_repo() { printf '%s\n' "$1"; }
fleet_on_symlink() { :; }
fleet_on_unreadable() { :; }

# fleet_discover_root <dir> [<depth>]: walk <dir> down to FLEET_MAX_DEPTH levels (default 5),
# pruning SKIP_NAMES. Hidden directories are walked and symlinked directories are not followed. A
# directory holding a .git marker is a repository and the walk stops there, so nothing nested
# inside a checkout is reported.
fleet_discover_root() {
  local dir="$1" depth="${2:-0}" child name
  [[ -d "$dir" && ! -L "$dir" ]] || return 0
  # Unreadable directories are ordinary under a volume-wide root (Windows $RECYCLE.BIN).
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
    # Unmatched globs leave literal patterns; skip those. Broken symlinks still match -L.
    [[ -e "$child" || -L "$child" ]] || continue
    name="${child##*/}"
    if should_skip_dir_name "$name"; then
      continue
    fi
    # Windows directory junctions satisfy both -d and -L under Git Bash, so they take this arm.
    if [[ -L "$child" && -d "$child" ]]; then
      fleet_on_symlink "$child"
      continue
    fi
    [[ -d "$child" ]] || continue
    fleet_discover_root "$child" $((depth + 1))
  done
}

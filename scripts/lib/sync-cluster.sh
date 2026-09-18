# shellcheck shell=bash
# shellcheck disable=SC2154  # every sync_cluster_* parameter is assigned by the caller after it sources this file; left undeclared here on purpose, so a caller that forgets one aborts under set -u instead of running with an empty value
# Shared engine for the scripts/sync-<cluster>.sh gates. Sourced, never executed.
#
# Every one of those gates answers the same three questions about one cluster of
# vendored copies -- rewrite the copies, fail on drift, fail when the canonical
# changed vs a base ref but a carrying plugin's manifest version did not -- and
# they differ only in the cluster's parameters and four wordings. Keeping one
# engine here means a fix to the walk (or to the "absent at the base ref is a new
# plugin" carve-out) lands in every gate at once instead of four times over.
#
# A caller sources this file, sets the parameters below, and ends with
# `sync_cluster::run "$@"`:
#
#   sync_cluster_script          the caller's own basename, quoted into messages
#   src                          canonical file, repo-relative
#   copies                       array of vendored copies, repo-relative
#   sync_cluster_manifest_strip  glob whose longest match is stripped off a copy
#                                path to reach its plugin root (e.g. '/hooks/*')
#   sync_cluster_noun            "Lib" or "Canonical" -- how the gate names the
#                                source in its --check-bump lines
#   sync_cluster_carrier         "carrying" or "consuming" -- how it names the
#                                plugins that vendor the copies
#   sync_cluster_sync_summary    1 to print a trailing per-run copy count in sync
#                                mode, 0 for the scripts that never printed one
#
# A gate whose --check-bump also gates surface no other cluster has
# (scripts/sync-standards-contract.sh gates the contract's own frontmatter semver
# and its CHANGELOG) keeps that one mode to itself, delegates the rest with
# `sync_cluster::run "$mode"`, and calls
# `sync_cluster::check_manifest_bumps_to <var> <base-ref>` for the
# carrying-plugin walk so the walk still lives in one place.
#
# `--print-manifest` is the published surface scripts/affected-tests.sh reads.
# It emits one `src<TAB><path>` line and zero or more `copy<TAB><path>` lines
# (already-expanded array values). The consumer invokes this flag; it does not
# scrape `src=` / `copies=(` out of the script text. Renaming the variables
# here does not change that output.
#
# The `${2:?usage: ...}` diagnostic for a missing <base-ref> stays in each caller:
# bash prefixes it with the path and line of the expansion, so hoisting it here
# would rewrite that message to name this file instead of the gate the user ran.

sync_cluster::sync() {
  local copy
  for copy in ${copies[@]+"${copies[@]}"}; do
    cp "$src" "$copy"
    echo "synced: $copy"
  done
  if ((sync_cluster_sync_summary)); then
    echo "synced ${#copies[@]} copies of $src."
  fi
}

sync_cluster::check() {
  local copy drifted=0
  for copy in ${copies[@]+"${copies[@]}"}; do
    if ! cmp -s "$src" "$copy"; then
      echo "DRIFT: $copy differs from $src" >&2
      drifted=1
    fi
  done
  if [[ "$drifted" -ne 0 ]]; then
    echo "Run scripts/$sync_cluster_script and commit the result." >&2
    exit 1
  fi
  echo "All ${#copies[@]} plugin copies match $src."
}

# sync_cluster::check_manifest_bumps_to <var> <base-ref>
#
# Walks the cluster's copies, reports on stderr every carrying plugin whose
# manifest version did not move vs <base-ref>, and writes 1 into <var> when any
# did not, 0 when all of them did. The answer goes into a caller variable rather
# than the return status because a status has to be read in a condition, and
# bash runs the whole body of a function called from a condition with errexit
# off. Locals carry an _sc_ prefix so the caller may name any of them as <var>.
sync_cluster::check_manifest_bumps_to() {
  local _sc_base="$2" _sc_copy _sc_manifest _sc_base_version _sc_head_version _sc_stale=0
  for _sc_copy in ${copies[@]+"${copies[@]}"}; do
    # shellcheck disable=SC2295  # the strip glob is a PATTERN, so it must stay unquoted
    _sc_manifest="${_sc_copy%%${sync_cluster_manifest_strip}}/.claude-plugin/plugin.json"
    # A plugin absent at the base ref is new in this change set; its initial
    # release already carries the new canonical content.
    _sc_base_version=$(git show "$_sc_base:$_sc_manifest" 2>/dev/null | jq -r '.version // empty' || true)
    if [[ -z "$_sc_base_version" ]]; then
      continue
    fi
    _sc_head_version=$(jq -r '.version // empty' "$_sc_manifest")
    if [[ "$_sc_head_version" == "$_sc_base_version" ]]; then
      echo "STALE VERSION: $src changed vs $_sc_base but $_sc_manifest is still $_sc_head_version" >&2
      _sc_stale=1
    fi
  done
  printf -v "$1" '%s' "$_sc_stale"
}

sync_cluster::check_bump() {
  local base="$1" stale=0
  if git diff --quiet "$base" -- "$src"; then
    echo "$sync_cluster_noun unchanged vs $base; no version bumps required."
    exit 0
  fi
  sync_cluster::check_manifest_bumps_to stale "$base"
  if [[ "$stale" -ne 0 ]]; then
    echo "Bump the version of every $sync_cluster_carrier plugin so consumers receive the lib change." >&2
    exit 1
  fi
  echo "$sync_cluster_noun changed vs $base and every $sync_cluster_carrier plugin bumped its version."
}

# sync_cluster::print_manifest
#
# Emits the cluster's src and copies as data. Tab-separated so a path cannot
# collide with the field name, and so affected-tests.sh can invoke this instead
# of parsing the caller's variable declarations.
sync_cluster::print_manifest() {
  local _sc_copy
  printf 'src\t%s\n' "$src"
  for _sc_copy in ${copies[@]+"${copies[@]}"}; do
    printf 'copy\t%s\n' "$_sc_copy"
  done
}

sync_cluster::run() {
  case "${1:-sync}" in
  sync)
    sync_cluster::sync
    ;;
  --check)
    sync_cluster::check
    ;;
  --check-bump)
    sync_cluster::check_bump "$2"
    ;;
  --print-manifest)
    sync_cluster::print_manifest
    ;;
  *)
    echo "usage: $sync_cluster_script [--check | --check-bump <base-ref> | --print-manifest]" >&2
    exit 2
    ;;
  esac
}

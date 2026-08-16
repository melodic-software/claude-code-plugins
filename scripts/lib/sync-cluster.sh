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
# `src` and `copies` keep those exact unprefixed names because they are a parsed
# contract, not a local style: scripts/affected-tests.sh reads `^src=` and
# `^copies=(` out of every scripts/sync-*.sh to derive which plugin copies a
# shared-lib change reaches. Rename them here and that derivation goes quietly
# empty (its own comment spells out the fail-open), so teach affected-tests.sh
# the new shape first if they ever have to move.
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

sync_cluster::check_bump() {
  local base="$1" copy manifest base_version head_version stale=0
  if git diff --quiet "$base" -- "$src"; then
    echo "$sync_cluster_noun unchanged vs $base; no version bumps required."
    exit 0
  fi
  for copy in ${copies[@]+"${copies[@]}"}; do
    # shellcheck disable=SC2295  # the strip glob is a PATTERN, so it must stay unquoted
    manifest="${copy%%${sync_cluster_manifest_strip}}/.claude-plugin/plugin.json"
    # A plugin absent at the base ref is new in this change set; its initial
    # release already carries the new lib.
    base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' || true)
    if [[ -z "$base_version" ]]; then
      continue
    fi
    head_version=$(jq -r '.version // empty' "$manifest")
    if [[ "$head_version" == "$base_version" ]]; then
      echo "STALE VERSION: $src changed vs $base but $manifest is still $head_version" >&2
      stale=1
    fi
  done
  if [[ "$stale" -ne 0 ]]; then
    echo "Bump the version of every $sync_cluster_carrier plugin so consumers receive the lib change." >&2
    exit 1
  fi
  echo "$sync_cluster_noun changed vs $base and every $sync_cluster_carrier plugin bumped its version."
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
  *)
    echo "usage: $sync_cluster_script [--check | --check-bump <base-ref>]" >&2
    exit 2
    ;;
  esac
}

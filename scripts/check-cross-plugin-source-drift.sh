#!/usr/bin/env bash
# Discover and check cross-plugin shared-source-file drift: files that live
# at the same path-within-plugin (e.g. hooks/hook-utils.sh) in 2+ plugins.
#
#   scripts/check-cross-plugin-source-drift.sh          discover: list every
#                                                        current cross-plugin
#                                                        file cluster and
#                                                        whether its copies
#                                                        are identical
#   scripts/check-cross-plugin-source-drift.sh --check  fail if a registered
#                                                        cluster has drifted,
#                                                        or an unregistered
#                                                        cluster is now fully
#                                                        identical
#
# This does not replace a cluster's own dedicated drift check --
# scripts/sync-hook-utils.sh stays authoritative for hooks/hook-utils.sh,
# scripts/validate-plugin-contracts.mjs for reference/artifact-protocol.md.
# This script's job is the one neither of those can do: notice when a NEW
# shared-copy pattern appears with no dedicated check yet, the same way the
# babysit-prs / source-control:pull-request policy split drifted apart
# silently until a manual audit caught it. Register a cluster in
# cross-plugin-source-registry.txt once it has a dedicated check (or is
# accepted as low-stakes coincidence); an unregistered identical cluster is
# a decision waiting to be made, not yet a violation of anything.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

registry="scripts/cross-plugin-source-registry.txt"

# Filenames that are *expected* to differ per plugin by design -- excluded
# from clustering entirely so they never produce noise.
skip_basenames=(SKILL.md plugin.json README.md CHANGELOG.md evals.json hooks.json .gitignore)

is_skipped() {
  local base="$1" skip
  for skip in "${skip_basenames[@]}"; do
    [[ "$base" == "$skip" ]] && return 0
  done
  return 1
}

# rel path within a plugin -> space-separated "plugin:fullpath" entries
declare -A cluster_entries
# rel path -> IDENTICAL | DIFFERS (only set for clusters with 2+ entries)
declare -A cluster_status

for plugin_dir in plugins/*/; do
  plugin="${plugin_dir%/}"
  plugin="${plugin##*/}"
  while IFS= read -r -d '' full; do
    base="${full##*/}"
    # shellcheck disable=SC2310  # is_skipped only compares strings; nothing inside it can fail
    if is_skipped "$base"; then
      continue
    fi
    rel="${full#"$plugin_dir"}"
    cluster_entries["$rel"]+="${plugin}:${full} "
  done < <(find "$plugin_dir" -type f -print0)
done

for rel in "${!cluster_entries[@]}"; do
  # shellcheck disable=SC2206
  entries=(${cluster_entries[$rel]})
  ((${#entries[@]} >= 2)) || continue

  first_hash=""
  identical=1
  for entry in "${entries[@]}"; do
    read -r h _ < <(sha256sum "${entry#*:}")
    if [[ -z "$first_hash" ]]; then
      first_hash="$h"
    elif [[ "$h" != "$first_hash" ]]; then
      identical=0
    fi
  done
  if ((identical)); then
    cluster_status["$rel"]="IDENTICAL"
  else
    cluster_status["$rel"]="DIFFERS"
  fi
done

declare -A registered
if [[ -f "$registry" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    registered["$line"]=1
  done <"$registry"
fi

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

if [[ "$mode" == "discover" ]]; then
  for rel in $(printf '%s\n' "${!cluster_status[@]}" | sort); do
    # shellcheck disable=SC2206
    entries=(${cluster_entries[$rel]})
    plugins_list=()
    for entry in "${entries[@]}"; do
      plugins_list+=("${entry%%:*}")
    done
    reg=""
    [[ -n "${registered[$rel]:-}" ]] && reg=" [registered]"
    printf '%-10s %s  (plugins: %s)%s\n' "${cluster_status[$rel]}" "$rel" "${plugins_list[*]}" "$reg"
  done
  exit 0
fi

# --check mode
errors=0

for rel in "${!cluster_status[@]}"; do
  if [[ "${cluster_status[$rel]}" == "IDENTICAL" && -z "${registered[$rel]:-}" ]]; then
    # shellcheck disable=SC2206
    entries=(${cluster_entries[$rel]})
    plugins_list=()
    for entry in "${entries[@]}"; do
      plugins_list+=("${entry%%:*}")
    done
    echo "UNREGISTERED: $rel is byte-identical across ${#entries[@]} plugins (${plugins_list[*]}) with no entry in $registry." >&2
    echo "  Either give it a dedicated drift check and register it, or add it to $registry as accepted." >&2
    errors=$((errors + 1))
  fi
done

for rel in "${!registered[@]}"; do
  status="${cluster_status[$rel]:-}"
  if [[ -z "$status" ]]; then
    echo "REGISTRY STALE: $rel is registered but no longer appears in 2+ plugins." >&2
    errors=$((errors + 1))
  elif [[ "$status" != "IDENTICAL" ]]; then
    echo "DRIFTED: $rel is registered as a shared-copy cluster but its copies no longer match." >&2
    errors=$((errors + 1))
  fi
done

if ((errors > 0)); then
  exit 1
fi
echo "No unregistered or drifted cross-plugin source clusters found."

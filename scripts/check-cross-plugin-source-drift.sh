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
# scripts/sync-shared-copies.sh stays authoritative for hooks/hook-utils.sh,
# scripts/validate-plugin-contracts.mjs for reference/artifact-protocol.md.
# This script's job is the one neither of those can do: notice when a NEW
# shared-copy pattern appears with no dedicated check yet. Register a cluster in
# cross-plugin-source-registry.txt once it has a dedicated check (or is
# accepted as low-stakes coincidence); an unregistered identical cluster is
# a decision waiting to be made, not yet a violation of anything.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${CHECK_DATA_ROOT:-$SCRIPT_DIR/..}" || exit 2
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

registry="scripts/cross-plugin-source-registry.txt"

# rel path within a plugin -> newline-delimited "plugin:fullpath" entries
declare -A cluster_entries=()
# rel path -> IDENTICAL | DIFFERS (only set for clusters with 2+ entries)
declare -A cluster_status=()

list_plugin_files() {
  if [[ -e .git ]] && command -v git >/dev/null 2>&1; then
    git -c core.quotepath=false ls-files --cached --others --exclude-standard -- plugins
  else
    find plugins -type f
  fi
}

while IFS=$'\t' read -r rel plugin full; do
  full="${full%$'\r'}"
  [[ -n "$rel" && -f "$full" && ! -L "$full" ]] || continue
  cluster_entries["$rel"]+="${plugin}:${full}"$'\n'
done < <(list_plugin_files | LC_ALL=C awk '
  BEGIN {
    skip["SKILL.md"] = 1; skip["plugin.json"] = 1; skip["README.md"] = 1
    skip["CHANGELOG.md"] = 1; skip["evals.json"] = 1; skip["hooks.json"] = 1
    skip[".gitignore"] = 1
  }
  {
    sub(/\r$/, "")
    if (substr($0, 1, 8) != "plugins/") next
    rest = substr($0, 9)
    slash = index(rest, "/")
    if (slash == 0) next
    plugin = substr(rest, 1, slash - 1)
    rel = substr(rest, slash + 1)
    if (rel == "") next
    # basename: after last /
    base = rel
    while ((p = index(base, "/")) > 0) base = substr(base, p + 1)
    if (base in skip) next
    cnt[rel]++
    if (cnt[rel] == 1) {
      first[rel] = rel "\t" plugin "\t" $0
    } else {
      if (cnt[rel] == 2) print first[rel]
      print rel "\t" plugin "\t" $0
    }
  }
')

# load_cluster <rel> -> populate the globals `entries` ("plugin:fullpath" pairs)
# and `plugins_list` (plugin names only). Globals rather than stdout: the callers
# need two arrays plus ${#entries[@]}, and a command substitution would both lose
# the arrays and put a function call where .shellcheckrc's SC2310 warns about
# set -e suppression.
load_cluster() {
  entries=()
  local rem="${cluster_entries[$1]}" line
  while [[ -n "$rem" ]]; do
    line="${rem%%$'\n'*}"
    [[ -n "$line" ]] && entries+=("$line")
    [[ "$line" != "$rem" ]] || break
    rem="${rem#*$'\n'}"
  done
  plugins_list=()
  local entry
  for entry in "${entries[@]}"; do
    plugins_list+=("${entry%%:*}")
  done
  if ((${#plugins_list[@]} > 1)); then
    local -a __pl_sorted=()
    local __p __i __j
    for __p in "${plugins_list[@]}"; do
      __i=${#__pl_sorted[@]}
      for ((__j = 0; __j < ${#__pl_sorted[@]}; __j++)); do
        if [[ "$__p" < "${__pl_sorted[__j]}" ]]; then
          __i=__j
          break
        fi
      done
      __pl_sorted=("${__pl_sorted[@]:0:__i}" "$__p" "${__pl_sorted[@]:__i}")
    done
    plugins_list=("${__pl_sorted[@]}")
  fi
}

declare -A file_hash
hash_paths=()
if ((${#cluster_entries[@]} > 0)); then
  for rel in "${!cluster_entries[@]}"; do
    load_cluster "$rel"
    ((${#entries[@]} >= 2)) || continue
    for entry in "${entries[@]}"; do
      hash_paths+=("${entry#*:}")
    done
  done
fi
if ((${#hash_paths[@]} > 0)); then
  hash_out="$(mktemp)" || exit 2
  trap 'rm -f "$hash_out"' EXIT
  if ! printf '%s\0' "${hash_paths[@]}" | xargs -0 sha256sum -z -- >"$hash_out"; then
    echo "check-cross-plugin-source-drift: sha256sum failed" >&2
    exit 2
  fi
  while IFS= read -r -d '' record; do
    file_hash["${record:66}"]="${record:0:64}"
  done <"$hash_out"
fi

if ((${#cluster_entries[@]} > 0)); then
  for rel in "${!cluster_entries[@]}"; do
    load_cluster "$rel"
    ((${#entries[@]} >= 2)) || continue

    first_hash=""
    identical=1
    for entry in "${entries[@]}"; do
      h="${file_hash[${entry#*:}]:-}"
      if [[ -z "$h" ]]; then
        echo "check-cross-plugin-source-drift: no hash for ${entry#*:}" >&2
        exit 2
      fi
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
fi

declare -A registered
registry_entries=()
if [[ -f "$registry" ]]; then
  # `inline`: entries are path-within-plugin strings, never regexes, so a `#`
  # anywhere on the line opens the rationale comment (scripts/lib/read-list.sh
  # owns the two comment families and why they must stay distinct).
  # shellcheck disable=SC2310  # the non-zero return IS the handled case; the library reports it
  read_list::into registry_entries "$registry" --comments inline || exit 2
  # A line containing ` -> ` is a cluster line (`<canonical> -> <member>...`,
  # a root-relative canonical copy and the plugin paths or globs that carry
  # it). It belongs to the duplication audit's reader
  # (plugins/code-metrics/skills/audit-duplication/scripts/registry-filter.py),
  # which excludes the whole class from its clone count; this check keys
  # clusters by path-within-plugin, so the line is dropped from the entry list
  # here and is neither registered nor reported stale.
  path_entries=()
  for line in ${registry_entries[@]+"${registry_entries[@]}"}; do
    [[ "$line" == *" -> "* ]] && continue
    path_entries+=("$line")
    registered["$line"]=1
  done
  registry_entries=(${path_entries[@]+"${path_entries[@]}"})
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
  # Feed `sort` from a loop, not an unquoted `$(...)` (word-splits and globs a
  # key containing a space) nor `printf '%s\n'` with NO arguments (prints one
  # blank line, which `mapfile -t` turns into an empty key on a tree with no
  # clusters). An empty array iterates zero times and feeds `sort` nothing.
  mapfile -t sorted_rels < <(
    for rel in "${!cluster_status[@]}"; do printf '%s\n' "$rel"; done | sort
  )
  for rel in "${sorted_rels[@]}"; do
    load_cluster "$rel"
    reg=""
    [[ -n "${registered[$rel]:-}" ]] && reg=" [registered]"
    printf '%-10s %s  (plugins: %s)%s\n' "${cluster_status[$rel]}" "$rel" "${plugins_list[*]}" "$reg"
  done
  exit 0
fi

errors=0

for rel in "${!cluster_status[@]}"; do
  if [[ "${cluster_status[$rel]}" == "IDENTICAL" && -z "${registered[$rel]:-}" ]]; then
    load_cluster "$rel"
    echo "UNREGISTERED: $rel is byte-identical across ${#entries[@]} plugins (${plugins_list[*]}) with no entry in $registry." >&2
    echo "  Either give it a dedicated drift check and register it, or add it to $registry as accepted." >&2
    errors=$((errors + 1))
  fi
done

for rel in ${registry_entries[@]+"${registry_entries[@]}"}; do
  status="${cluster_status[$rel]:-}"
  [[ -n "$status" ]] || continue
  read_list::mark_used "$rel"
  if [[ "$status" != "IDENTICAL" ]]; then
    echo "DRIFTED: $rel is registered as a shared-copy cluster but its copies no longer match." >&2
    errors=$((errors + 1))
  fi
done

stale_registry=()
read_list::stale_to stale_registry registry_entries
for rel in ${stale_registry[@]+"${stale_registry[@]}"}; do
  read_list::stale_line "$registry" "$rel" 'no longer appears in 2+ plugins.'
  errors=$((errors + 1))
done

if ((errors > 0)); then
  exit 1
fi
echo "No unregistered or drifted cross-plugin source clusters found."

#!/usr/bin/env bash
# Discover and check cross-plugin skill leaf-name collisions: a skill directory
# name (the leaf of `/<plugin>:<skill>`) carried by 2+ plugins.
#
#   scripts/check-skill-leaf-names.sh          discover: list every leaf name
#                                               owned by 2+ plugins, with its
#                                               owners and registration state
#   scripts/check-skill-leaf-names.sh --check  fail on an UNREGISTERED
#                                               collision, or a registry entry
#                                               that no longer collides
#
# Namespacing already guarantees every one of these is separately invocable --
# `/disk-hygiene:clean` and `/repo-hygiene:clean` can never resolve to each
# other, and the philosophy's Naming section is explicit that a built-in never
# forces a plugin skill's name. So a collision is not a correctness bug and this
# script is not a rename mandate.
#
# What it catches is the thing namespacing does NOT cover: the slash-command
# picker labels a row by the LEAF name and keeps `<plugin>:<skill>` as a hidden
# alias, so two colliding skills read identically in the listing and are told
# apart only by the `(<plugin-name>)` prefix the description carries. That cost
# is invisible from inside any one plugin -- nothing in a single skill's own
# review surfaces it -- and the grammar's own collision rule
# (docs/PLUGIN-PHILOSOPHY.md, Naming) governs siblings WITHIN one namespace, not
# across plugins.
#
# Registering a leaf name in skill-leaf-name-registry.txt records the grounds it
# was accepted on. An unregistered collision is a decision waiting to be made,
# not yet a violation of anything.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

registry="scripts/skill-leaf-name-registry.txt"

# leaf name -> space-separated owning plugin names
declare -A leaf_owners

for plugin_dir in plugins/*/; do
  plugin="${plugin_dir%/}"
  plugin="${plugin##*/}"
  skills_dir="${plugin_dir}skills"
  [[ -d "$skills_dir" ]] || continue
  for skill_dir in "$skills_dir"/*/; do
    [[ -f "${skill_dir}SKILL.md" ]] || continue
    leaf="${skill_dir%/}"
    leaf="${leaf##*/}"
    leaf_owners["$leaf"]+="${plugin} "
  done
done

# Collisions only: a leaf name owned by 2+ plugins.
declare -A collisions
for leaf in "${!leaf_owners[@]}"; do
  # shellcheck disable=SC2206  # plugin names are kebab-case; word-splitting is the intent
  owners=(${leaf_owners[$leaf]})
  ((${#owners[@]} >= 2)) || continue
  collisions["$leaf"]="${leaf_owners[$leaf]}"
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
  if ((${#collisions[@]} == 0)); then
    echo "No cross-plugin skill leaf-name collisions."
    exit 0
  fi
  for leaf in $(printf '%s\n' "${!collisions[@]}" | sort); do
    # shellcheck disable=SC2206
    owners=(${collisions[$leaf]})
    state="UNREGISTERED"
    [[ -n "${registered[$leaf]:-}" ]] && state="registered"
    printf '%-14s %-14s %d plugins: %s\n' \
      "$leaf" "$state" "${#owners[@]}" "$(printf '%s ' "${owners[@]}" | sed 's/ $//')"
  done
  exit 0
fi

failed=0

for leaf in $(printf '%s\n' "${!collisions[@]}" | sort); do
  [[ -n "${registered[$leaf]:-}" ]] && continue
  # shellcheck disable=SC2206
  owners=(${collisions[$leaf]})
  printf 'FAIL: skill leaf name %s is now carried by %d plugins (%s) and is not registered.\n' \
    "$leaf" "${#owners[@]}" "$(printf '%s ' "${owners[@]}" | sed 's/ $//')" >&2
  printf '      These are separately invocable, but the picker labels both rows %s.\n' "$leaf" >&2
  printf '      Rename one, or add %s to %s with the grounds it is accepted on.\n' "$leaf" "$registry" >&2
  failed=1
done

# Stale guard: a registry entry that no longer collides has outlived its reason
# and would otherwise silently pre-authorize a future collision on that name.
for leaf in $(printf '%s\n' "${!registered[@]}" | sort); do
  [[ -n "${collisions[$leaf]:-}" ]] && continue
  printf 'FAIL: %s lists %s, but it is no longer carried by 2+ plugins. Drop the entry.\n' \
    "$registry" "$leaf" >&2
  failed=1
done

if ((failed)); then
  exit 1
fi

printf 'All %d cross-plugin skill leaf-name collisions are registered.\n' "${#collisions[@]}"

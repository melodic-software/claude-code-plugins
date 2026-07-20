#!/usr/bin/env bash
# Discover and check cross-plugin skill leaf-name collisions: a skill directory
# name (the leaf of `/<plugin>:<skill>`) carried by 2+ plugins.
#
#   scripts/check-skill-leaf-names.sh          discover: list every leaf name
#                                               owned by 2+ plugins, with its
#                                               owners and registration state
#   scripts/check-skill-leaf-names.sh --check  fail on an UNREGISTERED
#                                               collision, on a registered one
#                                               whose OWNER SET changed, or on
#                                               an entry that no longer collides
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
# was accepted on, together with the owner set those grounds were argued over.
# A new plugin joining an already-registered collision has to be argued on its
# own merits, so the owner set is part of the entry rather than the bare name --
# otherwise the first registration would silently pre-authorize every later one.
# An unregistered collision is a decision waiting to be made, not yet a
# violation of anything.
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
#
# `collision_leaves` and `collision_count` shadow the associative array on
# purpose: under `set -u` an associative array that was declared but never
# assigned is UNBOUND, so `${#collisions[@]}` and `${!collisions[@]}` abort the
# script in the zero-collision case -- which is exactly the state the stale-entry
# guard is meant to shepherd the repo into.
declare -A collisions
collision_leaves=()
collision_count=0
for leaf in "${!leaf_owners[@]}"; do
  # shellcheck disable=SC2206  # plugin names are kebab-case; word-splitting is the intent
  owners=(${leaf_owners[$leaf]})
  ((${#owners[@]} >= 2)) || continue
  collisions["$leaf"]="${leaf_owners[$leaf]}"
  collision_leaves+=("$leaf")
  collision_count=$((collision_count + 1))
done

# leaf name -> accepted owner set: a sorted comma-separated plugin list, or `*`
# for a name whose owner set is open by contract (see the registry header).
declare -A registered
registered_leaves=()
if [[ -f "$registry" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    # `read`, not array splitting: the owner field may be a literal `*`, which
    # unquoted word splitting would pathname-expand against the cwd.
    read -r leaf_key owner_field _ <<<"$line"
    [[ -n "${registered[$leaf_key]+set}" ]] || registered_leaves+=("$leaf_key")
    registered["$leaf_key"]="${owner_field:-}"
  done <"$registry"
fi

# Sorted comma-separated owner set, so the comparison is order-independent.
owner_set() {
  printf '%s\n' "$@" | sort | paste -sd, -
}

mode="${1:-discover}"
case "$mode" in
discover | --check) ;;
*)
  echo "usage: $(basename "$0") [--check]" >&2
  exit 2
  ;;
esac

if [[ "$mode" == "discover" ]]; then
  if ((collision_count == 0)); then
    echo "No cross-plugin skill leaf-name collisions."
    exit 0
  fi
  for leaf in $(printf '%s\n' ${collision_leaves[@]+"${collision_leaves[@]}"} | sort); do
    # shellcheck disable=SC2206
    owners=(${collisions[$leaf]})
    # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
    actual="$(owner_set "${owners[@]}")"
    state="UNREGISTERED"
    if [[ -n "${registered[$leaf]+set}" ]]; then
      accepted="${registered[$leaf]}"
      state="OWNERS-CHANGED"
      if [[ "$accepted" == "*" ]]; then
        state="registered(*)"
      elif [[ -n "$accepted" ]]; then
        IFS=',' read -ra accepted_owners <<<"$accepted"
        # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
        accepted="$(owner_set "${accepted_owners[@]}")"
        [[ "$accepted" == "$actual" ]] && state="registered"
      fi
    fi
    printf '%-14s %-14s %d plugins: %s\n' \
      "$leaf" "$state" "${#owners[@]}" "$(printf '%s ' "${owners[@]}" | sed 's/ $//')"
  done
  exit 0
fi

failed=0

for leaf in $(printf '%s\n' ${collision_leaves[@]+"${collision_leaves[@]}"} | sort); do
  # shellcheck disable=SC2206
  owners=(${collisions[$leaf]})
  # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
  actual="$(owner_set "${owners[@]}")"

  if [[ -z "${registered[$leaf]+set}" ]]; then
    printf 'FAIL: skill leaf name %s is now carried by %d plugins (%s) and is not registered.\n' \
      "$leaf" "${#owners[@]}" "${actual//,/ }" >&2
    printf '      These are separately invocable, but the picker labels every row %s.\n' "$leaf" >&2
    printf '      Rename one, or add "%s %s" to %s with the grounds it is accepted on.\n' \
      "$leaf" "$actual" "$registry" >&2
    failed=1
    continue
  fi

  accepted="${registered[$leaf]}"
  # An open owner set is accepted by contract; only the name is registered.
  [[ "$accepted" == "*" ]] && continue

  # Normalize the registry side too, so the comparison is genuinely set-vs-set
  # and a hand-edited entry does not fail on ordering alone.
  if [[ -n "$accepted" ]]; then
    IFS=',' read -ra accepted_owners <<<"$accepted"
    # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
    accepted="$(owner_set "${accepted_owners[@]}")"
  fi

  if [[ -z "$accepted" ]]; then
    printf 'FAIL: %s registers %s without an owner set. Record it as "%s %s".\n' \
      "$registry" "$leaf" "$leaf" "$actual" >&2
    failed=1
  elif [[ "$accepted" != "$actual" ]]; then
    printf 'FAIL: skill leaf name %s is registered for %s but is now carried by %s.\n' \
      "$leaf" "${accepted//,/ }" "${actual//,/ }" >&2
    printf '      A new owner joins an accepted collision on its own grounds, not the old ones.\n' >&2
    printf '      Update the entry to "%s %s" and revisit the rationale above it.\n' "$leaf" "$actual" >&2
    failed=1
  fi
done

# Stale guard: a registry entry that no longer collides has outlived its reason
# and would otherwise silently pre-authorize a future collision on that name.
for leaf in $(printf '%s\n' ${registered_leaves[@]+"${registered_leaves[@]}"} | sort); do
  [[ -n "${collisions[$leaf]:-}" ]] && continue
  printf 'FAIL: %s lists %s, but it is no longer carried by 2+ plugins. Drop the entry.\n' \
    "$registry" "$leaf" >&2
  failed=1
done

if ((failed)); then
  exit 1
fi

printf 'All %d cross-plugin skill leaf-name collisions are registered.\n' "$collision_count"

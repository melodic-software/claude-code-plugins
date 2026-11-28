#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."
# shellcheck source=lib/read-list.sh
. "$SCRIPT_DIR/lib/read-list.sh" || exit 2

registry="scripts/skill-leaf-name-registry.txt"

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

collision_leaves=()
for leaf in "${!leaf_owners[@]}"; do
  # shellcheck disable=SC2206  # plugin names are kebab-case; word-splitting is the intent
  owners=(${leaf_owners[$leaf]})
  ((${#owners[@]} >= 2)) || continue
  collision_leaves+=("$leaf")
done

declare -A registered
registered_leaves=()
duplicate_leaves=()
if [[ -f "$registry" ]]; then
  registry_lines=()
  # shellcheck disable=SC2310  # the non-zero return IS the handled case; the library reports it
  read_list::into registry_lines "$registry" --comments inline || exit 2
  for line in ${registry_lines[@]+"${registry_lines[@]}"}; do
    read -r leaf_key owner_field _ <<<"$line"
    if [[ -n "${registered[$leaf_key]+set}" ]]; then
      duplicate_leaves+=("$leaf_key")
    else
      registered_leaves+=("$leaf_key")
    fi
    registered["$leaf_key"]="${owner_field:-}"
  done
fi

owner_set() {
  printf '%s\n' "$@" | sort | paste -sd, -
}

owner_set_field() {
  local -a parts=()
  IFS=',' read -ra parts <<<"$1"
  # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
  owner_set "${parts[@]}"
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
  if ((${#collision_leaves[@]} == 0)); then
    echo "No cross-plugin skill leaf-name collisions."
    exit 0
  fi
  for leaf in $(printf '%s\n' ${collision_leaves[@]+"${collision_leaves[@]}"} | sort); do
    # shellcheck disable=SC2206
    owners=(${leaf_owners[$leaf]})
    # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
    actual="$(owner_set "${owners[@]}")"
    state="UNREGISTERED"
    if [[ -n "${registered[$leaf]+set}" ]]; then
      accepted="${registered[$leaf]}"
      state="OWNERS-CHANGED"
      if [[ "$accepted" == "*" ]]; then
        state="registered(*)"
      elif [[ -n "$accepted" ]]; then
        # shellcheck disable=SC2310  # owner_set_field only sorts strings; nothing inside can fail
        accepted="$(owner_set_field "$accepted")"
        [[ "$accepted" == "$actual" ]] && state="registered"
      fi
    fi
    printf '%-14s %-14s %d plugins: %s\n' \
      "$leaf" "$state" "${#owners[@]}" "${owners[*]}"
  done
  exit 0
fi

failed=0

for leaf in ${duplicate_leaves[@]+"${duplicate_leaves[@]}"}; do
  printf 'FAIL: %s registers %s more than once. Merge the entries into one line.\n' \
    "$registry" "$leaf" >&2
  failed=1
done

prev=""
for leaf in ${registered_leaves[@]+"${registered_leaves[@]}"}; do
  if [[ -n "$prev" ]] && [[ "$(printf '%s\n%s\n' "$prev" "$leaf" | LC_ALL=C sort | head -n1)" != "$prev" ]]; then
    printf 'FAIL: %s lists %s after %s. Keep the entries sorted by leaf name.\n' \
      "$registry" "$leaf" "$prev" >&2
    failed=1
  fi
  prev="$leaf"
done

for leaf in $(printf '%s\n' ${collision_leaves[@]+"${collision_leaves[@]}"} | sort); do
  # shellcheck disable=SC2206
  owners=(${leaf_owners[$leaf]})
  # shellcheck disable=SC2310  # owner_set only sorts strings; nothing inside can fail
  actual="$(owner_set "${owners[@]}")"

  if [[ -z "${registered[$leaf]+set}" ]]; then
    printf 'FAIL: skill leaf name %s is now carried by %d plugins (%s) and is not registered.\n' \
      "$leaf" "${#owners[@]}" "${actual//,/ }" >&2
    printf '      These are separately invocable, but typing %s filters to all of them.\n' "$leaf" >&2
    printf '      Rename one, or add "%s %s" to %s with the grounds it is accepted on.\n' \
      "$leaf" "$actual" "$registry" >&2
    failed=1
    continue
  fi

  read_list::mark_used "$leaf"

  accepted="${registered[$leaf]}"
  [[ "$accepted" == "*" ]] && continue

  if [[ -n "$accepted" ]]; then
    # shellcheck disable=SC2310  # owner_set_field only sorts strings; nothing inside can fail
    accepted="$(owner_set_field "$accepted")"
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

# shellcheck disable=SC2310  # the non-zero return IS the stale verdict this reads
read_list::report_stale registered_leaves "$registry" \
  'is no longer carried by 2+ plugins. Drop the entry.' || failed=1

if ((failed)); then
  exit 1
fi

printf 'All %d cross-plugin skill leaf-name collisions are registered.\n' "${#collision_leaves[@]}"

#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)" || exit 2
cd "$SCRIPT_DIR/.." || exit 2
self="$(basename "$0")"

# shellcheck source=lib/changed-files.sh
. "$SCRIPT_DIR/lib/changed-files.sh" || exit 2
# shellcheck source=lib/gate-entry.sh
. "$SCRIPT_DIR/lib/gate-entry.sh" || exit 2
# shellcheck source=lib/changelog-fragments.sh
. "$SCRIPT_DIR/lib/changelog-fragments.sh" || exit 2

if ! jq --version >/dev/null 2>&1; then
  echo "$self: jq is required to read manifest versions; refusing to pass without it" >&2
  exit 2
fi

GE_FLAGS=("--check-bump:ref")
GE_BAD_REF_MSG="$self: cannot resolve base ref: ${2-}"
# shellcheck disable=SC2310  # the non-zero return IS the handled case
if ! gate_entry::classify "$@"; then
  echo "usage: $self --check-bump <base-ref>" >&2
  exit 2
fi
base="$GE_REF"
if ! mb="$(git merge-base "$base" HEAD)"; then
  echo "$self: 'git merge-base $base HEAD' failed (no common ancestor, or history not fetched deeply enough); refusing to pass without checking." >&2
  exit 2
fi

changed_paths=()
if ! changed_files::into changed_paths "$mb" --include-deleted --no-renames -- plugins/; then
  echo "$self: git diff failed against $base (or staging its output did); refusing to pass on a change set this gate could not read" >&2
  exit 2
fi

changed_plugins=()
declare -A seen_plugins=()
for path in ${changed_paths[@]+"${changed_paths[@]}"}; do
  case "$path" in
  plugins/*/vendor/*)
    name="${path#plugins/}"
    name="${name%%/*}"
    skill_rest="${path#"plugins/$name/skills/"}"
    if [[ "$path" != "plugins/$name/vendor/"* ]] &&
      { [[ "$skill_rest" == "$path" ]] || [[ "$skill_rest" != "${skill_rest%%/*}/vendor/"* ]]; }; then
      continue
    fi
    [[ -z "${seen_plugins[$name]:-}" ]] || continue
    seen_plugins["$name"]=1
    changed_plugins+=("$name")
    ;;
  *) ;;
  esac
done

if [[ ${#changed_plugins[@]} -eq 0 ]]; then
  echo "No plugin vendor/ tree changed vs $base; no version bumps required."
  gate_entry::finish 0
fi

base_manifest_file="$(mktemp)" || {
  echo "$self: mktemp failed; refusing to pass without a place to stage base manifests" >&2
  exit 2
}
trap 'rm -f "$base_manifest_file"' EXIT

stale=0
stale_fragment=0
dependabot=""
for plugin in "${changed_plugins[@]}"; do
  manifest="plugins/$plugin/.claude-plugin/plugin.json"
  if ! base_manifest_entry="$(git ls-tree --name-only "$mb" -- "$manifest")"; then
    echo "$self: git ls-tree failed reading $base; refusing to pass on a base this gate could not read" >&2
    exit 2
  fi
  [[ -n "$base_manifest_entry" ]] || continue
  if ! git show "$mb:$manifest" >"$base_manifest_file"; then
    echo "$self: git show failed reading $manifest at $base; refusing to pass on a manifest this gate could not read" >&2
    exit 2
  fi
  if ! base_version="$(jq -r '.version // empty' "$base_manifest_file")"; then
    echo "$self: $manifest at $base is not valid JSON; refusing to treat an unreadable base version as a bump exemption" >&2
    exit 2
  fi
  if [[ -z "$base_version" ]]; then
    echo "$self: $manifest at $base has no version; refusing to treat a version-less base manifest as a bump exemption" >&2
    exit 2
  fi
  head_version=$(jq -r '.version // empty' "$manifest" 2>/dev/null || true)
  rc=1
  if [[ -n "$head_version" ]]; then
    rc=0
    changelog_fragments::bump_delivered "$mb" "$plugin" "$base_version" "$head_version" || rc=$?
  fi
  # shellcheck disable=SC2310  # the non-zero return IS the answer; bump_delivered already read the list
  if ((rc == 1)) && [[ -n "$head_version" ]] && changelog_fragments::in_mode "$plugin"; then
    if [[ -z "$dependabot" ]]; then
      dependabot=no
      # shellcheck disable=SC2310  # the non-zero return IS the answer
      changelog_fragments::dependabot_only "$base" && dependabot=yes
    fi
    if [[ "$dependabot" == yes ]]; then
      echo "Dependabot-only change to a vendor/ tree of plugins/$plugin/: scripts/dependabot-fragments.sh writes its fragment after the merge."
      continue
    fi
    echo "STALE VERSION: a vendor/ tree of plugins/$plugin/ changed vs $base but $plugin, in fragment mode, has no fragment for it" >&2
    echo "  Run scripts/new-changelog-fragment.sh $plugin patch and describe the vendored change." >&2
    stale_fragment=1
  elif ((rc == 1)); then
    echo "STALE VERSION: a vendor/ tree of plugins/$plugin/ changed vs $base but $manifest is still ${head_version:-absent}" >&2
    stale=1
  elif ((rc != 0)); then
    exit 2
  fi
done

if [[ "$stale" -ne 0 ]]; then
  echo "Bump the version of every plugin whose vendor/ source changed — the version is the update cache key, so an unbumped plugin never delivers the change to consumers (ADR 0019, intra-plugin sharing)." >&2
fi
if [[ "$stale_fragment" -ne 0 ]]; then
  echo "Add a patch fragment for every plugin in fragment mode whose vendor/ source changed; the release pull request bumps its version, which delivers the change to consumers (ADR 0048)." >&2
fi
if [[ "$stale" -ne 0 || "$stale_fragment" -ne 0 ]]; then
  gate_entry::finish 1
fi

echo "Every plugin with a vendor/ change vs $base bumped its version."
gate_entry::finish 0

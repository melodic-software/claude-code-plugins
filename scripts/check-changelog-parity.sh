#!/usr/bin/env bash
# Keep each plugin's CHANGELOG.md honest against its manifest version.
#
#   scripts/check-changelog-parity.sh --check             fail if a versioned
#                                                         plugin has no sibling
#                                                         CHANGELOG.md
#   scripts/check-changelog-parity.sh --check-bump <ref>  fail if a plugin's
#                                                         manifest version
#                                                         changed vs <ref> but
#                                                         its CHANGELOG.md was
#                                                         not touched in the diff
#
# Two complementary gaps the same audit surfaced:
#   * --check is the static repo-wide invariant: a plugins/<name>/.claude-plugin/
#     plugin.json carrying a `version` must ship a plugins/<name>/CHANGELOG.md.
#     It catches a plugin that has bumped versions but never kept a changelog at
#     all (autonomy shipped 5 minor bumps with none).
#   * --check-bump is the go-forward PR discipline: a version change with no
#     CHANGELOG.md edit in the same diff means the release is undocumented. It
#     mirrors the sync-*.sh --check-bump bump gates and applies to EVERY plugin,
#     grandfathered or not — the moment a debt-listed plugin bumps again it must
#     start its changelog.
#
# Existing "versioned but changelog-less" debt is grandfathered by plugin NAME in
# scripts/changelog-parity-baseline.txt (same stale-guarded idiom as
# scripts/orphaned-fixtures-baseline.txt): --check exempts a listed plugin but
# fails on a STALE entry — one that now has a CHANGELOG.md (or no version) — so
# the exemption cannot outlive the debt. The baseline never relaxes --check-bump.
#
# Fail-closed: a versioned plugin with neither a CHANGELOG.md nor a baseline
# entry fails. CHANGELOG_PARITY_BASELINE overrides the baseline path (test
# injection).
set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

BASELINE="${CHANGELOG_PARITY_BASELINE:-scripts/changelog-parity-baseline.txt}"

mode="${1:-}"
case "$mode" in
--check | --check-bump) ;;
*)
  echo "usage: $(basename "$0") [--check | --check-bump <base-ref>]" >&2
  exit 2
  ;;
esac

# Grandfathered plugin names (static-check exemptions).
declare -A grandfathered
if [[ -f "$BASELINE" ]]; then
  while IFS= read -r line; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -z "$line" ]] && continue
    grandfathered["$line"]=1
  done <"$BASELINE"
fi

manifests=(plugins/*/.claude-plugin/plugin.json)
if [[ ! -e "${manifests[0]}" ]]; then
  echo "error: no plugin manifests found under plugins/*/.claude-plugin/" >&2
  exit 2
fi

version_of() { jq -r '.version // empty' "$1" 2>/dev/null; }

if [[ "$mode" == "--check" ]]; then
  declare -A saw_debt
  missing=0
  for manifest in "${manifests[@]}"; do
    plugin_dir="${manifest%/.claude-plugin/plugin.json}"
    name="${plugin_dir##*/}"
    [[ -n "$(version_of "$manifest")" ]] || continue
    if [[ -f "$plugin_dir/CHANGELOG.md" ]]; then
      if [[ -n "${grandfathered[$name]:-}" ]]; then
        echo "STALE BASELINE: '$name' in $BASELINE now has a CHANGELOG.md — remove it." >&2
        missing=$((missing + 1))
        # Mark handled so the second stale-scan loop does not re-report it.
        saw_debt["$name"]=1
      fi
      continue
    fi
    if [[ -n "${grandfathered[$name]:-}" ]]; then
      saw_debt["$name"]=1
      continue
    fi
    echo "MISSING CHANGELOG: $plugin_dir carries a versioned $manifest but no $plugin_dir/CHANGELOG.md." >&2
    echo "  Add $plugin_dir/CHANGELOG.md, or grandfather '$name' in $BASELINE with its owning issue." >&2
    missing=$((missing + 1))
  done
  # A baseline name that matches no versioned-and-changelog-less plugin is stale.
  for name in "${!grandfathered[@]}"; do
    if [[ -z "${saw_debt[$name]:-}" ]]; then
      echo "STALE BASELINE: '$name' in $BASELINE no longer names a versioned plugin missing a CHANGELOG.md — remove it." >&2
      missing=$((missing + 1))
    fi
  done
  if ((missing > 0)); then
    exit 1
  fi
  echo "Every versioned plugin has a CHANGELOG.md (or a stale-guarded baseline entry)."
  exit 0
fi

# --check-bump mode
if [[ -z "${2:-}" ]]; then
  echo "usage: $(basename "$0") --check-bump <base-ref>" >&2
  exit 2
fi
base="$2"
if ! git rev-parse --verify --quiet "${base}^{commit}" >/dev/null; then
  echo "check-changelog-parity: base ref '$base' is not a resolvable commit." >&2
  exit 2
fi

undocumented=0
for manifest in "${manifests[@]}"; do
  plugin_dir="${manifest%/.claude-plugin/plugin.json}"
  name="${plugin_dir##*/}"
  changelog="$plugin_dir/CHANGELOG.md"

  base_version="$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' 2>/dev/null || true)"
  # Absent at base => new plugin in this change set; the static --check owns
  # whether its initial CHANGELOG.md exists, not the bump gate.
  [[ -n "$base_version" ]] || continue
  head_version="$(version_of "$manifest")"
  [[ "$head_version" != "$base_version" ]] || continue

  if git diff --quiet "$base" -- "$changelog"; then
    echo "UNDOCUMENTED BUMP: $name went $base_version -> $head_version but $changelog was not updated in this diff." >&2
    undocumented=$((undocumented + 1))
  fi
done

if ((undocumented > 0)); then
  echo "Add a CHANGELOG.md entry for every plugin whose version changed." >&2
  exit 1
fi
echo "Every plugin whose version changed vs $base also updated its CHANGELOG.md."

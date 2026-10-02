#!/usr/bin/env bash
# Gate the standards contract's own version surface (ADR 0019).
#
#   scripts/check-standards-contract-bump.sh <base-ref>
#
# Fails when the contract or its schema changed vs <base-ref> but
#   (a) a carrying plugin's manifest version did not move: the plugin version
#       is the update cache key, or
#   (b) the standards-contract frontmatter semver did not move: setup's
#       migration detection reads it, so without a bump content drifts under a
#       frozen version forever, or
#   (c) the contract CHANGELOG has no "## <version>" entry for the frontmatter
#       version.
#
# The carrying plugins are the copies scripts/shared-copies.txt registers for the
# contract; scripts/sync-shared-copies.sh --check-bump gates their bump for a
# change to the contract text, and this gate adds the schema-only change, which
# changes no copy. Nothing here writes.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$script_dir/.."
# shellcheck source=lib/gate-entry.sh
. "$script_dir/lib/gate-entry.sh" || exit 2

src="docs/conventions/standards/README.md"
schema="docs/conventions/standards/standards.schema.json"
changelog="docs/conventions/standards/CHANGELOG.md"

base="${1:?usage: check-standards-contract-bump.sh <base-ref>}"
gate_entry::require_base "$base" "error: base ref $base does not resolve to a commit."

frontmatter_version() {
  awk '/^standards-contract:/ {print $2; exit}'
}

if git diff --quiet "$base" -- "$src" "$schema"; then
  echo "Contract unchanged vs $base; no version bumps required."
  exit 0
fi
stale=0

base_contract=""
if base_src=$(git show "$base:$src" 2>/dev/null); then
  base_contract=$(frontmatter_version <<<"$base_src")
fi
head_contract=$(frontmatter_version <"$src")
if [[ -n "$base_contract" && "$head_contract" == "$base_contract" ]]; then
  echo "STALE CONTRACT VERSION: $src changed vs $base but its standards-contract frontmatter is still $head_contract" >&2
  stale=1
fi

# A heading count could be satisfied by any unrelated '## ' section, so match the
# entry for the version the frontmatter now names.
head_contract_re=${head_contract//./\\.}
if ! grep -Eq "^## ${head_contract_re}( |$)" "$changelog" 2>/dev/null; then
  echo "STALE CHANGELOG: $src changed vs $base but $changelog has no '## $head_contract' entry" >&2
  stale=1
fi

manifest_dump="$(bash "$script_dir/sync-shared-copies.sh" --print-manifest)"
carriers=()
while IFS= read -r copy; do
  [[ -n "$copy" ]] && carriers+=("$copy")
done < <(awk -F'\t' -v s="$src" '$1 == "src" { on = ($2 == s) } on && $1 == "copy" { print $2 }' <<<"$manifest_dump")
if ((${#carriers[@]} == 0)); then
  echo "error: scripts/shared-copies.txt registers no copy of $src." >&2
  exit 2
fi
for copy in "${carriers[@]}"; do
  rest="${copy#plugins/}"
  manifest="plugins/${rest%%/*}/.claude-plugin/plugin.json"
  # A plugin absent at the base ref is new in this change set; its initial
  # release already carries the new contract.
  base_version=$(git show "$base:$manifest" 2>/dev/null | jq -r '.version // empty' || true)
  [[ -n "$base_version" ]] || continue
  head_version=$(jq -r '.version // empty' "$manifest")
  if [[ "$head_version" == "$base_version" ]]; then
    echo "STALE VERSION: $src changed vs $base but $manifest is still $head_version" >&2
    stale=1
  fi
done

if ((stale)); then
  echo "Bump the standards-contract frontmatter, add a changelog entry, and bump every carrying plugin." >&2
  echo "For a bump that only carries the sync, the CHANGELOG entry is: Shared \`$(basename "$src")\` synced (<link to the change>); no change to this plugin's reference." >&2
  exit 1
fi
echo "Contract changed vs $base with frontmatter, changelog, and every carrying plugin bumped."

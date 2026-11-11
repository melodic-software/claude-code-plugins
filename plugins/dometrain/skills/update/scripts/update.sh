#!/usr/bin/env bash
# dometrain update — drift check for Dometrain's upstream dometrain-grounding skill content.
#
# Modes:
#   --check (default)     report only — diff upstream against the vendored baseline
#   --apply               overwrite the vendor snapshot with current upstream
#                         (maintainer-only: run in a working clone, never the installed cache)
#
# No CLI to install/upgrade here (unlike context7's ctx7 package) — only vendored prose to diff.
#
# Exit codes (the shared drift-check contract):
#   0 — no drift, or --apply completed
#   1 — drift: upstream differs from the vendored baseline, or the baseline is missing
#   2 — unverifiable: curl or diff missing, fetch or write failure, or usage

set -uo pipefail

MODE="${1:---check}"
case "$MODE" in
--check | --apply) ;;
*)
  echo "✖ Unknown mode: $MODE (expected --check or --apply)" >&2
  exit 2
  ;;
esac

# All paths resolve relative to this script's own location, so the script works
# both in the installed plugin cache and in a working clone of the marketplace repo.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$SKILL_DIR/vendor"
GROUNDING_SKILL_MD="$SKILL_DIR/../grounding/SKILL.md"
BASELINE="$SNAPSHOT_DIR/SKILL.md"

UPSTREAM_URL="https://raw.githubusercontent.com/Dometrain/mcp/master/skills/dometrain-grounding/SKILL.md"

# Upstream lacks the vendored attribution comment; drop it and its next line so an identical
# copy reports no drift. {N;d} rather than GNU-only `,+1d` keeps this working on BSD sed.
strip_attribution() {
  sed '/<!-- Vendored from https:\/\/github.com\/Dometrain\/mcp/{N;d}' "$1"
}

# $1 names the action in the failure message: seed or refresh.
save_baseline() {
  if ! cp "$tmpfile" "$BASELINE"; then
    echo "  ✖ Failed to $1 baseline (check permissions/disk)" >&2
    exit 2
  fi
}

summary() {
  echo ""
  echo "=== Summary ==="
  printf '%s\n' "$@"
}

for cmd in curl diff; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✖ Required command not found: $cmd" >&2
    exit 2
  fi
done

mkdir -p "$SNAPSHOT_DIR"

echo "=== Upstream skill: dometrain-grounding ==="

tmpfile=$(mktemp)
baseline_lf=$(mktemp)
tmpfile_lf=$(mktemp)
trap 'rm -f "$tmpfile" "$baseline_lf" "$tmpfile_lf"' EXIT

curl_err=$(curl -fsSL "$UPSTREAM_URL" -o "$tmpfile" 2>&1 >/dev/null) || {
  echo "  ✖ Failed to fetch $UPSTREAM_URL" >&2
  [[ -n "$curl_err" ]] && echo "    $curl_err" >&2
  exit 2
}

if [[ ! -f "$BASELINE" ]]; then
  echo "  ↳ No baseline at $BASELINE"
  if [[ "$MODE" == "--apply" ]]; then
    save_baseline seed
    echo "  ✓ Baseline seeded ($(wc -c <"$BASELINE") bytes)"
    exit 0
  fi
  echo "  ↳ Drift: no baseline yet (plugin maintainers, in a working clone: run with --apply to seed it; see context/update.md)"
  exit 1
fi

# Normalize line endings before comparing — baseline may be CRLF on Windows checkouts,
# upstream is always LF. Without this, every Windows run reports false-positive drift.
strip_attribution "$BASELINE" | tr -d '\r' >"$baseline_lf"
tr -d '\r' <"$tmpfile" >"$tmpfile_lf"

if diff_output=$(diff -u "$baseline_lf" "$tmpfile_lf"); then
  echo "  ✓ Upstream unchanged since last baseline"
  summary "✓ No drift detected. dometrain grounding content is in sync with upstream."
  exit 0
fi

diff_lines=$(printf '%s\n' "$diff_output" | wc -l | tr -d ' ')
echo "  ↳ Drift detected ($diff_lines diff lines)"
echo ""
echo "  --- new upstream content (for manual review) ---"
printf '%s\n' "$diff_output" | head -60
if ((diff_lines > 60)); then
  echo "  ↳ (diff truncated to 60 of $diff_lines lines — run diff manually for full output)"
fi
echo ""

if [[ "$MODE" == "--apply" ]]; then
  save_baseline refresh
  echo "  ✓ Baseline refreshed to match current upstream"
  echo "  ↳ Re-add the attribution comment (see context/update.md) — --apply"
  echo "    overwrites with raw upstream content, which never carries it."
  TODAY=$(date -u +%Y-%m-%d)
  sed -i.bak -E "s/^( *synced: ).*/\1\"$TODAY\"/" "$GROUNDING_SKILL_MD" && rm -f "$GROUNDING_SKILL_MD.bak"
  echo "  ✓ Stamped synced: $TODAY in grounding/SKILL.md frontmatter"
  exit 0
fi

echo "  ↳ To integrate (plugin maintainers, in a working clone):"
echo "      1. Review the diff above and decide what to port into:"
echo "           $GROUNDING_SKILL_MD"
echo "      2. Preserve this plugin's customizations (see context/update.md)"
echo "      3. After integration, re-run this script with --apply"
summary "↳ Drift detected. See sections above." \
  "Next: review the diff, port relevant changes, then --apply."
exit 1

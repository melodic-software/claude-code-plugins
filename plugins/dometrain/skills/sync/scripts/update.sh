#!/usr/bin/env bash
# dometrain sync — drift check for Dometrain's upstream dometrain-grounding skill content.
#
# Modes:
#   (default)             report only — diff upstream against the vendored baseline
#   --refresh-baseline    overwrite the vendor snapshot with current upstream
#                         (maintainer-only: run in a working clone, never the installed cache)
#
# No CLI to install/upgrade here (unlike context7's ctx7 package) — only vendored prose to diff.
#
# Exit codes:
#   0 — verified: no drift detected (or drift reported in report mode)
#   1 — prerequisites missing (curl, diff not on PATH), or fetch/write failure (state unverifiable)
#   2 — drift detected (content differs, or baseline missing in report mode)

set -uo pipefail

MODE="${1:-report}"

# All paths resolve relative to this script's own location, so the script works
# both in the installed plugin cache and in a working clone of the marketplace repo.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$SKILL_DIR/vendor"
GROUNDING_SKILL_MD="$SKILL_DIR/../grounding/SKILL.md"
BASELINE="$SNAPSHOT_DIR/SKILL.md"

UPSTREAM_URL="https://raw.githubusercontent.com/Dometrain/mcp/master/skills/dometrain-grounding/SKILL.md"

# The vendored baseline carries an attribution HTML comment (plus its surrounding blank
# lines) after the frontmatter that upstream does not have — added deliberately (MIT
# attribution requirement) and placed there rather than before the frontmatter, because a
# leading comment breaks YAML-frontmatter recognition in markdownlint and would corrupt the
# verbatim snapshot on every format pass. Strip it before diffing so a copy that is otherwise
# byte-identical to upstream reports zero drift, not a permanent 2-line false positive.
strip_attribution() {
  sed '/<!-- Vendored from https:\/\/github.com\/Dometrain\/mcp/,+1d' "$1"
}

for cmd in curl diff; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✖ Required command not found: $cmd" >&2
    exit 1
  fi
done

mkdir -p "$SNAPSHOT_DIR"

echo "=== Upstream skill: dometrain-grounding ==="

tmpfile=$(mktemp)
baseline_lf=$(mktemp)
tmpfile_lf=$(mktemp)
trap 'rm -f "$tmpfile" "$baseline_lf" "$tmpfile_lf"' EXIT

if ! curl -fsSL "$UPSTREAM_URL" -o "$tmpfile" 2>/dev/null; then
  echo "  ✖ Failed to fetch $UPSTREAM_URL" >&2
  exit 1
fi

if [[ ! -f "$BASELINE" ]]; then
  echo "  ↳ No baseline at $BASELINE"
  if [[ "$MODE" == "--refresh-baseline" ]]; then
    if ! cp "$tmpfile" "$BASELINE"; then
      echo "  ✖ Failed to seed baseline (check permissions/disk)" >&2
      exit 1
    fi
    echo "  ✓ Baseline seeded ($(wc -c <"$BASELINE") bytes)"
    exit 0
  fi
  echo "  ↳ Run with --refresh-baseline to seed (until seeded, state is unverified)"
  exit 2
fi

# Normalize line endings before comparing — baseline may be CRLF on Windows checkouts,
# upstream is always LF. Without this, every Windows run reports false-positive drift.
strip_attribution "$BASELINE" | tr -d '\r' >"$baseline_lf"
tr -d '\r' <"$tmpfile" >"$tmpfile_lf"

if diff -q "$baseline_lf" "$tmpfile_lf" >/dev/null 2>&1; then
  echo "  ✓ Upstream unchanged since last baseline"
  echo ""
  echo "=== Summary ==="
  echo "✓ No drift detected. dometrain grounding content is in sync with upstream."
  exit 0
fi

diff_output=$(diff -u "$baseline_lf" "$tmpfile_lf")
diff_lines=$(printf '%s\n' "$diff_output" | wc -l | tr -d ' ')
echo "  ↳ Drift detected ($diff_lines diff lines)"
echo ""
echo "  --- new upstream content (for manual review) ---"
printf '%s\n' "$diff_output" | head -60
if ((diff_lines > 60)); then
  echo "  ↳ (diff truncated to 60 of $diff_lines lines — run diff manually for full output)"
fi
echo ""

if [[ "$MODE" == "--refresh-baseline" ]]; then
  if ! cp "$tmpfile" "$BASELINE"; then
    echo "  ✖ Failed to refresh baseline (check permissions/disk)" >&2
    exit 1
  fi
  echo "  ✓ Baseline refreshed to match current upstream"
  echo "  ↳ Re-add the attribution comment (see context/update.md) — --refresh-baseline"
  echo "    overwrites with raw upstream content, which never carries it."
  TODAY=$(date -u +%Y-%m-%d)
  sed -i.bak -E "s/^( *synced: ).*/\1\"$TODAY\"/" "$GROUNDING_SKILL_MD" && rm -f "$GROUNDING_SKILL_MD.bak"
  echo "  ✓ Stamped synced: $TODAY in grounding/SKILL.md frontmatter"
  exit 0
fi

echo "  ↳ To integrate (plugin maintainers, in a working clone):"
echo "      1. Review the diff above and decide what to port into:"
echo "           $SKILL_DIR/../grounding/SKILL.md"
echo "      2. Preserve this plugin's customizations (see context/update.md)"
echo "      3. After integration, re-run this script with --refresh-baseline"
echo ""
echo "=== Summary ==="
echo "↳ Drift detected. See sections above."
echo "Next: review the diff, port relevant changes, then --refresh-baseline."
exit 2

#!/usr/bin/env bash
# context7 update — drift check for ctx7 CLI version and upstream skill content.
#
# Modes:
#   (default)             report only — CLI version drift + upstream skill diff
#   --fix                 install/upgrade CLI to latest; still advisory on skill content
#   --refresh-baseline    overwrite upstream snapshot with current upstream and stamp synced
#                         and upstream-version (the master commit both files came from)
#                         (maintainer-only: run in a working clone, never the installed cache)
#
# Exit codes (the shared drift-check contract):
#   0 — no drift, or the requested fix/refresh completed with nothing left to report
#   1 — drift: the installed CLI is behind latest, or upstream skill content differs
#       from its baseline (a missing baseline counts as drift)
#   2 — unverifiable: a prerequisite (npm, curl, diff, git) missing, npm registry or
#       upstream unreachable, a requested fix/refresh failed, or usage
# Drift outranks unverifiable: a run that finds drift exits 1 even if another check
# could not run. A ctx7 CLI that is not installed is reported but is not drift.

# No -e: check_skill_drift captures non-zero return codes via $? as drift signals,
# not failures.
set -uo pipefail

MODE="${1:-report}"
case "$MODE" in
report | --fix | --refresh-baseline) ;;
*)
  echo "✖ Unknown mode: $MODE (expected report, --fix or --refresh-baseline)" >&2
  exit 2
  ;;
esac

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$SKILL_DIR/vendor"
SKILL_MD="$SKILL_DIR/SKILL.md"
BASELINE_FIND_DOCS="$SNAPSHOT_DIR/find-docs/SKILL.md"
BASELINE_CLI_SKILL="$SNAPSHOT_DIR/cli/SKILL.md"

UPSTREAM_REPO="https://github.com/upstash/context7"
UPSTREAM_RAW="https://raw.githubusercontent.com/upstash/context7"

# --- prerequisite checks ---
for cmd in npm curl diff git; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✖ Required command not found: $cmd" >&2
    exit 2
  fi
done

mkdir -p "$SNAPSHOT_DIR/find-docs" "$SNAPSHOT_DIR/cli"

# Verifies ctx7 is resolvable on PATH and prints a non-empty version.
# On success: prints version to stdout, returns 0.
# On failure: prints nothing to stdout, returns non-zero.
verify_ctx7_callable() {
  local version
  if ! command -v ctx7 >/dev/null 2>&1; then
    return 1
  fi
  version=$(ctx7 --version 2>/dev/null | tr -d '\r')
  if [[ -z "$version" ]]; then
    return 2
  fi
  printf '%s\n' "$version"
  return 0
}

install_and_verify() {
  echo "  ↳ Applying: npm install -g ctx7@latest"
  if ! npm install -g ctx7@latest; then
    echo "  ✖ npm install failed" >&2
    return 2
  fi
  local new_version
  if ! new_version=$(verify_ctx7_callable); then
    echo "  ✖ npm install reported success but ctx7 is not callable on PATH" >&2
    echo "  ↳ Check npm global bin: $(npm config get prefix 2>/dev/null)" >&2
    return 2
  fi
  echo "  ✓ CLI installed and verified: $new_version"
  return 0
}

# --- CLI version check ---
echo "=== Context7 CLI version ==="
INSTALLED=$(verify_ctx7_callable) || INSTALLED="not-installed"
LATEST=$(npm view ctx7 version 2>/dev/null | tr -d '\r')
echo "  installed: $INSTALLED"
echo "  latest:    ${LATEST:-unknown}"

if [[ "$INSTALLED" == "not-installed" ]]; then
  if [[ "$MODE" == "--fix" ]]; then
    install_and_verify || exit 2
  else
    echo "  ↳ ctx7 is not installed (not counted as drift). Run with --fix, or manually: npm install -g ctx7@latest"
  fi
elif [[ -z "$LATEST" ]]; then
  echo "  ✖ Cannot verify latest version (npm view ctx7 failed)" >&2
  echo "  ↳ CLI state is unverifiable until npm registry is reachable" >&2
  CLI_DRIFT=2
elif [[ "$INSTALLED" != "$LATEST" ]]; then
  echo "  ↳ CLI is behind latest."
  if [[ "$MODE" == "--fix" ]]; then
    install_and_verify || exit 2
  else
    echo "  ↳ Run with --fix to upgrade, or manually: npm install -g ctx7@latest"
    CLI_DRIFT=1
  fi
else
  echo "  ✓ CLI is current"
fi

echo ""

# --- upstream skill content check ---
# Resolve master once and fetch both files at that commit, so both baselines and the
# stamped upstream-version name the same revision.
UPSTREAM_SHA=$(git ls-remote "$UPSTREAM_REPO" refs/heads/master 2>/dev/null | cut -f1)

# Return codes:
#   0 — upstream unchanged (or baseline seeded/refreshed successfully in --refresh-baseline mode)
#   1 — drift detected (content differs, OR baseline missing in non-refresh mode)
#   2 — fetch failed or baseline write failed; state unverifiable
check_skill_drift() {
  local name="$1"
  local url="$2"
  local baseline="$3"
  local tmpfile baseline_lf tmpfile_lf
  tmpfile=$(mktemp)
  baseline_lf=$(mktemp)
  tmpfile_lf=$(mktemp)
  trap 'rm -f "$tmpfile" "$baseline_lf" "$tmpfile_lf"' RETURN

  if ! curl -fsSL "$url" -o "$tmpfile" 2>/dev/null; then
    echo "  ✖ Failed to fetch $url" >&2
    return 2
  fi

  echo "=== Upstream skill: $name ==="
  if [[ ! -f "$baseline" ]]; then
    echo "  ↳ No baseline at $baseline"
    if [[ "$MODE" == "--refresh-baseline" ]]; then
      if ! cp "$tmpfile" "$baseline"; then
        echo "  ✖ Failed to seed baseline (check permissions/disk)" >&2
        return 2
      fi
      echo "  ✓ Baseline seeded ($(wc -c <"$baseline") bytes)"
      return 0
    fi
    echo "  ↳ Drift: run with --refresh-baseline to seed the baseline"
    return 1
  fi

  # Baseline may be CRLF on a Windows checkout and upstream is always LF;
  # comparing unnormalized reports false drift on every Windows run.
  tr -d '\r' <"$baseline" >"$baseline_lf"
  tr -d '\r' <"$tmpfile" >"$tmpfile_lf"

  if diff -q "$baseline_lf" "$tmpfile_lf" >/dev/null 2>&1; then
    echo "  ✓ Upstream unchanged since last baseline"
    return 0
  fi

  local diff_output diff_lines
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
    if ! cp "$tmpfile" "$baseline"; then
      echo "  ✖ Failed to refresh baseline (check permissions/disk)" >&2
      return 2
    fi
    echo "  ✓ Baseline refreshed to match current upstream"
    return 0
  fi

  echo "  ↳ To integrate (plugin maintainers, in a working clone):"
  echo "      1. Review the diff above and decide what to port into:"
  echo "           $SKILL_DIR/SKILL.md"
  echo "           $SKILL_DIR/context/{cli,mcp,lookup,update}.md"
  echo "      2. Preserve the plugin's customizations (see context/update.md)"
  echo "      3. After integration, re-run this script with --refresh-baseline"
  return 1
}

if [[ "$UPSTREAM_SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "=== Upstream commit: $UPSTREAM_SHA ==="
  echo ""
  check_skill_drift "find-docs" "$UPSTREAM_RAW/$UPSTREAM_SHA/skills/find-docs/SKILL.md" "$BASELINE_FIND_DOCS"
  FIND_DOCS_RC=$?

  echo ""
  check_skill_drift "context7-cli" "$UPSTREAM_RAW/$UPSTREAM_SHA/skills/context7-cli/SKILL.md" "$BASELINE_CLI_SKILL"
  CLI_SKILL_RC=$?
else
  echo "✖ Cannot resolve upstash/context7 master (git ls-remote failed)" >&2
  FIND_DOCS_RC=2
  CLI_SKILL_RC=2
fi

if [[ "$MODE" == "--refresh-baseline" ]] && [[ $FIND_DOCS_RC == 0 ]] && [[ $CLI_SKILL_RC == 0 ]]; then
  TODAY=$(date -u +%Y-%m-%d)
  sed -i.bak -E -e "s/^( *synced: ).*/\1$TODAY/" \
    -e "s/^( *upstream-version: ).*/\1upstash\/context7@$UPSTREAM_SHA/" "$SKILL_MD" &&
    rm -f "$SKILL_MD.bak"
  echo "  ✓ Stamped synced: $TODAY and upstream-version: upstash/context7@$UPSTREAM_SHA in SKILL.md"
fi

echo ""
echo "=== Summary ==="
CLI_DRIFT="${CLI_DRIFT:-0}"
if [[ "$CLI_DRIFT" == 0 && $FIND_DOCS_RC == 0 && $CLI_SKILL_RC == 0 ]]; then
  echo "✓ No drift detected. Context7 is in sync with upstream."
  exit 0
fi
echo "↳ Drift or unverifiable state present. See sections above."
case "$CLI_DRIFT" in
1) echo "  - CLI version behind" ;;
2) echo "  - CLI state unverifiable (npm registry unreachable)" ;;
*) ;; # 0 = no CLI drift
esac
for entry in "find-docs:$FIND_DOCS_RC" "context7-cli:$CLI_SKILL_RC"; do
  case "${entry#*:}" in
  1) echo "  - ${entry%%:*} SKILL.md changed upstream (or baseline missing)" ;;
  2) echo "  - ${entry%%:*} upstream unreachable or baseline write failed (state unverifiable)" ;;
  *) ;; # 0 = unchanged
  esac
done
if [[ "$CLI_DRIFT" == 1 || $FIND_DOCS_RC == 1 || $CLI_SKILL_RC == 1 ]]; then
  if [[ "$MODE" == "report" ]]; then
    echo ""
    echo "Next: review diffs, port relevant changes, then --refresh-baseline."
  fi
  exit 1
fi
exit 2

#!/usr/bin/env bash
# context7 update — drift check for ctx7 CLI version and upstream skill content.
#
# Modes:
#   (default)             report only — CLI version drift + upstream skill diff
#   --fix                 install/upgrade CLI to latest; still advisory on skill content
#   --refresh-baseline    overwrite upstream snapshot with current upstream
#                         (maintainer-only: run in a working clone, never the installed cache)
#
# Exit codes:
#   0 — verified: no drift detected (or drift reported in report mode)
#   1 — prerequisites missing (npm, curl, diff not on PATH)
#   2 — state unverifiable OR requested fix/refresh failed
#       (npm registry unreachable, upstream fetch failed, post-install PATH issue,
#        baseline write failure; missing baseline in report mode surfaces as drift, exit 0)

# No -e: check_skill_drift captures non-zero return codes via $? as drift signals,
# not failures.
set -uo pipefail

MODE="${1:-report}"

# All paths resolve relative to this script's own location, so the script works
# both in the installed plugin cache and in a working clone of the marketplace repo.
SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_DIR="$SKILL_DIR/vendor"
SKILL_MD="$SKILL_DIR/SKILL.md"
BASELINE_FIND_DOCS="$SNAPSHOT_DIR/find-docs/SKILL.md"
BASELINE_CLI_SKILL="$SNAPSHOT_DIR/cli/SKILL.md"

UPSTREAM_FIND_DOCS="https://raw.githubusercontent.com/upstash/context7/refs/heads/master/skills/find-docs/SKILL.md"
UPSTREAM_CLI_SKILL="https://raw.githubusercontent.com/upstash/context7/refs/heads/master/skills/context7-cli/SKILL.md"

mkdir -p "$SNAPSHOT_DIR/find-docs" "$SNAPSHOT_DIR/cli"

# --- prerequisite checks ---
for cmd in npm curl diff; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "✖ Required command not found: $cmd" >&2
    exit 1
  fi
done

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
LATEST=$(npm view ctx7 version 2>/dev/null | tr -d '\r' || echo "")
echo "  installed: $INSTALLED"
echo "  latest:    ${LATEST:-unknown}"

if [[ "$INSTALLED" == "not-installed" ]]; then
  if [[ "$MODE" == "--fix" ]]; then
    install_and_verify || exit 2
  else
    echo "  ↳ ctx7 is not installed. Run with --fix, or manually: npm install -g ctx7@latest"
    CLI_DRIFT=1
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
# Return codes:
#   0 — upstream unchanged (or baseline seeded/refreshed successfully in --refresh-baseline mode)
#   1 — fetch failed or baseline write failed; state unverifiable
#   2 — drift detected (content differs, OR baseline missing in non-refresh mode)
check_skill_drift() {
  local name="$1"
  local url="$2"
  local baseline="$3"
  local tmpfile baseline_lf tmpfile_lf
  tmpfile=$(mktemp)
  baseline_lf=$(mktemp)
  tmpfile_lf=$(mktemp)
  # RETURN trap removes every temp file on all exit paths.
  trap 'rm -f "$tmpfile" "$baseline_lf" "$tmpfile_lf"' RETURN

  if ! curl -fsSL "$url" -o "$tmpfile" 2>/dev/null; then
    echo "  ✖ Failed to fetch $url" >&2
    return 1
  fi

  echo "=== Upstream skill: $name ==="
  if [[ ! -f "$baseline" ]]; then
    echo "  ↳ No baseline at $baseline"
    if [[ "$MODE" == "--refresh-baseline" ]]; then
      if ! cp "$tmpfile" "$baseline"; then
        echo "  ✖ Failed to seed baseline (check permissions/disk)" >&2
        return 1
      fi
      echo "  ✓ Baseline seeded ($(wc -c <"$baseline") bytes)"
      return 0
    fi
    echo "  ↳ Run with --refresh-baseline to seed (until seeded, state is unverified)"
    return 2
  fi

  # Normalize line endings before comparing — baseline may be CRLF on Windows
  # checkouts, upstream is always LF. Without this, every Windows run reports
  # false-positive drift.
  tr -d '\r' <"$baseline" >"$baseline_lf"
  tr -d '\r' <"$tmpfile" >"$tmpfile_lf"

  if diff -q "$baseline_lf" "$tmpfile_lf" >/dev/null 2>&1; then
    echo "  ✓ Upstream unchanged since last baseline"
    return 0
  fi

  local diff_lines
  diff_lines=$(diff "$baseline_lf" "$tmpfile_lf" | wc -l | tr -d ' ')
  echo "  ↳ Drift detected ($diff_lines lines changed)"
  echo ""
  echo "  --- new upstream content (for manual review) ---"
  diff -u "$baseline_lf" "$tmpfile_lf" | head -60
  echo ""

  if [[ "$MODE" == "--refresh-baseline" ]]; then
    if ! cp "$tmpfile" "$baseline"; then
      echo "  ✖ Failed to refresh baseline (check permissions/disk)" >&2
      return 1
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
  return 2
}

check_skill_drift "find-docs" "$UPSTREAM_FIND_DOCS" "$BASELINE_FIND_DOCS"
FIND_DOCS_RC=$?

echo ""
check_skill_drift "context7-cli" "$UPSTREAM_CLI_SKILL" "$BASELINE_CLI_SKILL"
CLI_SKILL_RC=$?

if [[ "$MODE" == "--refresh-baseline" ]] && [[ $FIND_DOCS_RC == 0 ]] && [[ $CLI_SKILL_RC == 0 ]]; then
  TODAY=$(date -u +%Y-%m-%d)
  sed -i.bak -E "s/^( *synced: ).*/\1$TODAY/" "$SKILL_MD" && rm -f "$SKILL_MD.bak"
  echo "  ✓ Stamped synced: $TODAY in SKILL.md frontmatter"
fi

echo ""
echo "=== Summary ==="
EXIT_CODE=0
if [[ "${CLI_DRIFT:-0}" == "0" ]] && [[ $FIND_DOCS_RC == 0 ]] && [[ $CLI_SKILL_RC == 0 ]]; then
  echo "✓ No drift detected. Context7 is in sync with upstream."
else
  echo "↳ Drift or unverifiable state present. See sections above."
  case "${CLI_DRIFT:-0}" in
  1) echo "  - CLI version behind" ;;
  2)
    echo "  - CLI state unverifiable (npm registry unreachable)"
    EXIT_CODE=2
    ;;
  *) ;; # 0 = no CLI drift; non-CLI drift handled below
  esac
  if [[ $FIND_DOCS_RC == 1 ]]; then
    echo "  - find-docs upstream fetch/write failed (state unverifiable)"
    EXIT_CODE=2
  elif [[ $FIND_DOCS_RC == 2 ]]; then
    echo "  - find-docs SKILL.md changed upstream (or baseline missing)"
  fi
  if [[ $CLI_SKILL_RC == 1 ]]; then
    echo "  - context7-cli upstream fetch/write failed (state unverifiable)"
    EXIT_CODE=2
  elif [[ $CLI_SKILL_RC == 2 ]]; then
    echo "  - context7-cli SKILL.md changed upstream (or baseline missing)"
  fi
  if [[ "$MODE" == "report" ]]; then
    echo ""
    echo "Next: review diffs, port relevant changes, then --refresh-baseline."
  fi
fi

exit $EXIT_CODE

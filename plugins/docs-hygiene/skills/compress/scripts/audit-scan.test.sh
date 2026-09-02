#!/usr/bin/env bash
# Contract smoke for audit-scan.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/audit-scan.sh"
FIX="$SCRIPT_DIR/../evals/fixtures"

PASS=0
FAIL=0
ok() { echo "ok: $*"; PASS=$((PASS + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL=$((FAIL + 1)); }

out="$(bash "$SCAN" "$FIX/terse-agent.md" 2>/dev/null)" || true
case "$out" in
*'| SKIP |'*) ok "terse-agent classifies SKIP" ;;
*) fail "terse-agent classifies SKIP (got: $out)" ;;
esac

out2="$(bash "$SCAN" "$FIX/audit-fixture-dir/verbose.md" 2>/dev/null)" || true
case "$out2" in
*'| COMPRESS |'*) ok "verbose fixture classifies COMPRESS" ;;
*) fail "verbose fixture classifies COMPRESS (got: $out2)" ;;
esac

out3="$(bash "$SCAN" "$FIX/audit-fixture-dir/lean.md" 2>/dev/null)" || true
case "$out3" in
*'| SKIP |'*) ok "lean fixture classifies SKIP" ;;
*) fail "lean fixture classifies SKIP (got: $out3)" ;;
esac

# Repo-relative .claude/rules path is signal 1 (no leading slash).
RULES_REL="$(mktemp -d)"
mkdir -p "$RULES_REL/.claude/rules"
printf '# rule\n\njust really basically actually simply perhaps somewhat very quite might note that keep in mind\n' >"$RULES_REL/.claude/rules/example.md"
# Enough flavor tokens that a missed signal-1 would fall through to COMPRESS
# rather than SKIP. Word-count floor is 50.
out4="$(bash "$SCAN" "$RULES_REL/.claude/rules/example.md" 2>/dev/null)" || true
case "$out4" in
*'author-time-disciplined path (signal 1)'*) ok "repo-relative .claude/rules classifies as signal 1" ;;
*) fail "repo-relative .claude/rules should be signal 1 (got: $out4)" ;;
esac
rm -rf "$RULES_REL"

# Two path-shaped tokens on one line count as two occurrences, not one line.
OCC="$(mktemp)"
# 50+ words so the density floor does not rewrite the count; two .md refs on
# one line; enough flavor tokens to escape the flavor-density SKIP.
{
  printf 'see docs/a.md and docs/b.md on one line. '
  printf 'just really basically actually simply perhaps somewhat very quite might '
  printf 'in order to due to the fact that make use of it is important to note that keep in mind '
  printf 'word word word word word word word word word word word word word word word '
  printf 'word word word word word word word word word word word word word word word\n'
} >"$OCC"
# Isolated occurrence counter: same regex the scanner uses.
occ_count=$(grep -Eo '(@|[a-z][a-z0-9._/-]+\.(md|cs|sh|json|yaml))' "$OCC" | wc -l | tr -d ' ')
line_count=$(grep -Ec '(@|[a-z][a-z0-9._/-]+\.(md|cs|sh|json|yaml))' "$OCC" | tr -d ' ')
if [[ "$occ_count" -gt "$line_count" ]]; then
  ok "path-hit regex counts occurrences ($occ_count) above line hits ($line_count)"
else
  fail "expected occurrence count > line count (occ=$occ_count line=$line_count)"
fi
rm -f "$OCC"

if [[ $FAIL -ne 0 ]]; then
  echo "$FAIL check(s) failed." >&2
  exit 1
fi
echo "OK: audit-scan.sh tests passed ($PASS checks)"

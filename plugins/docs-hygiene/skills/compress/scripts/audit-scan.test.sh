#!/usr/bin/env bash
# Contract smoke for audit-scan.sh.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCAN="$SCRIPT_DIR/audit-scan.sh"
FIX="$SCRIPT_DIR/../evals/fixtures"

PASS=0
FAIL=0
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}

# <path> <prefix text> <count of trailing 'word ' tokens>
write_padded_md() {
  local i=0
  {
    printf '%s' "$2"
    while [[ $i -lt $3 ]]; do
      printf 'word '
      i=$((i + 1))
    done
    printf '\n'
  } >"$1"
}

# <label> <expected substring> <scan argument>
assert_classify() {
  local out
  out="$(bash "$SCAN" "$3" 2>/dev/null)" || true
  case "$out" in
  *"$2"*) ok "$1" ;;
  *) fail "$1 (got: $out)" ;;
  esac
}

assert_classify "terse-agent classifies SKIP" '| SKIP |' "$FIX/terse-agent.md"
assert_classify "verbose fixture classifies COMPRESS" '| COMPRESS |' "$FIX/audit-fixture-dir/verbose.md"
assert_classify "lean fixture classifies SKIP" '| SKIP |' "$FIX/audit-fixture-dir/lean.md"

# Repo-relative .claude/rules path is signal 1 (no leading slash). mktemp -d
# is already absolute, so invoking the scanner with that path would match the
# old `*/.claude/rules/` glob and never exercise the repo-relative arm. Run
# from the temp dir with the relative argument the matcher is supposed to see.
RULES_REL="$(mktemp -d)"
mkdir -p "$RULES_REL/.claude/rules"
printf '# rule\n\njust really basically actually simply perhaps somewhat very quite might note that keep in mind\n' >"$RULES_REL/.claude/rules/example.md"
# Enough flavor tokens that a missed signal-1 would fall through to COMPRESS
# rather than SKIP. Word-count floor is 50.
out4="$(
  cd "$RULES_REL" || exit 1
  bash "$SCAN" .claude/rules/example.md 2>/dev/null
)" || true
case "$out4" in
*'author-time-disciplined path (signal 1)'*) ok "repo-relative .claude/rules classifies as signal 1" ;;
*) fail "repo-relative .claude/rules should be signal 1 (got: $out4)" ;;
esac
rm -rf "$RULES_REL"

# Five path refs on one line, ~500 words: line-count density is 1*1000/500 = 2
# (COMPRESS), occurrence density is 5*1000/500 = 10 > 8 (UNCERTAIN). Flavor
# tokens keep the file out of the flavor-density SKIP. The scanner itself must
# classify — a regex-only check never exercises path_dens.
OCC="$(mktemp -d)"
write_padded_md "$OCC/occ.md" \
  'see docs/a.md and docs/b.md and docs/c.md and docs/d.md and docs/e.md. just really basically ' 480
out_occ="$(bash "$SCAN" "$OCC/occ.md" 2>/dev/null)" || true
case "$out_occ" in
*'| UNCERTAIN |'*'cross-ref density'*) ok "one-line path refs classify UNCERTAIN by occurrence density" ;;
*) fail "one-line path refs should classify UNCERTAIN (got: $out_occ)" ;;
esac
rm -rf "$OCC"

# `@docs/a.md` is one occurrence. The old `(@|path.ext)` regex emitted `@` and
# `docs/a.md`, doubling density over the 8/kw threshold at ~200 words.
AT="$(mktemp -d)"
write_padded_md "$AT/at.md" 'see @docs/a.md on one line. just really ' 200
out_at="$(bash "$SCAN" "$AT/at.md" 2>/dev/null)" || true
case "$out_at" in
*'| COMPRESS |'*) ok "@-prefixed path ref counts as one occurrence (COMPRESS)" ;;
*) fail "@-prefixed path ref should classify COMPRESS, not double-count (got: $out_at)" ;;
esac
rm -rf "$AT"

if [[ $FAIL -ne 0 ]]; then
  echo "$FAIL check(s) failed." >&2
  exit 1
fi
echo "OK: audit-scan.sh tests passed ($PASS checks)"

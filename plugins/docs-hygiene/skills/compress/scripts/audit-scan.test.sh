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

# The COMPRESS reason follows compress_articles (SKILL.md "Articles"): the
# default, keep, promises no article cuts; cut names them.
out_keep="$(bash "$SCAN" "$FIX/audit-fixture-dir/verbose.md" 2>/dev/null)" || true
case "$out_keep" in
*'| COMPRESS |'*articles\ kept*) ok "the default reason keeps articles" ;;
*) fail "the default reason should say articles are kept (got: $out_keep)" ;;
esac
case "$out_keep" in
*hedging/articles*) fail "the default reason must not promise article cuts (got: $out_keep)" ;;
*) ok "the default reason promises no article cuts" ;;
esac
assert_classify_args() { # <label> <expected substring> <args...>
  local label="$1" want="$2" out
  shift 2
  out="$(bash "$SCAN" "$@" 2>/dev/null)" || true
  case "$out" in
  *"$want"*) ok "$label" ;;
  *) fail "$label (got: $out)" ;;
  esac
}
assert_classify_args "--articles cut names article cuts" 'filler/hedging/articles' --articles cut "$FIX/audit-fixture-dir/verbose.md"
bash "$SCAN" --articles drop "$FIX/audit-fixture-dir/verbose.md" >/dev/null 2>&1
if [[ $? -eq 2 ]]; then ok "--articles with another value exits 2"; else fail "--articles drop should exit 2"; fi

# Repo-relative .claude/rules path is signal 1 (no leading slash). mktemp -d
# is already absolute, so invoking the scanner with that path would match the
# old `*/.claude/rules/` glob and never exercise the repo-relative arm. Run
# from the temp dir with the relative argument the matcher is supposed to see.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
RULES_REL="$SCRATCH/rules"
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

# Five path refs on one line, ~500 words: line-count density is 1*1000/500 = 2
# (COMPRESS), occurrence density is 5*1000/500 = 10 > 8 (UNCERTAIN). Flavor
# tokens keep the file out of the flavor-density SKIP. The scanner itself must
# classify — a regex-only check never exercises path_dens.
OCC="$SCRATCH/occ"
mkdir -p "$OCC"
write_padded_md "$OCC/occ.md" \
  'see docs/a.md and docs/b.md and docs/c.md and docs/d.md and docs/e.md. just really basically ' 480
out_occ="$(bash "$SCAN" "$OCC/occ.md" 2>/dev/null)" || true
case "$out_occ" in
*'| UNCERTAIN |'*'cross-ref density'*) ok "one-line path refs classify UNCERTAIN by occurrence density" ;;
*) fail "one-line path refs should classify UNCERTAIN (got: $out_occ)" ;;
esac

# `@docs/a.md` is one occurrence. The old `(@|path.ext)` regex emitted `@` and
# `docs/a.md`, doubling density over the 8/kw threshold at ~200 words.
AT="$SCRATCH/at"
mkdir -p "$AT"
write_padded_md "$AT/at.md" 'see @docs/a.md on one line. just really ' 200
out_at="$(bash "$SCAN" "$AT/at.md" 2>/dev/null)" || true
case "$out_at" in
*'| COMPRESS |'*) ok "@-prefixed path ref counts as one occurrence (COMPRESS)" ;;
*) fail "@-prefixed path ref should classify COMPRESS, not double-count (got: $out_at)" ;;
esac

if [[ $FAIL -ne 0 ]]; then
  echo "$FAIL check(s) failed." >&2
  exit 1
fi
echo "OK: audit-scan.sh tests passed ($PASS checks)"

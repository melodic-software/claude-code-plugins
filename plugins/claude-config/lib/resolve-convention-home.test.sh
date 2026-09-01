#!/usr/bin/env bash
# Self-contained tests for lib/resolve-convention-home.sh (no external test lib — ships with the plugin).
#
# Per-plugin assertion helpers are deliberately duplicated, not shared:
# docs/conventions/shell-test-helpers/README.md.
#
# shellcheck disable=SC2016 # single-quoted backticks are the grammar under test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-convention-home.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  detail: %s\n' "$1" "$2" >&2
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 (got: $2)" ;;
  esac
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected exit $2, got $3"; fi
}

BEGIN='<!-- BEGIN GENERATED: convention-home -->'
END='<!-- END GENERATED: convention-home -->'

# mkrepo <name> — echo a fresh root with docs/conventions present
mkrepo() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d/docs/conventions"
  printf '%s' "$d"
}

# region <token-line...> — print a marked region whose body is the given lines
region() {
  printf '%s\n' "$BEGIN"
  printf '%s\n' "$@"
  printf '%s\n' "$END"
}

pointer() { printf 'Team conventions live in `%s` - read the topic doc there first.' "$1"; }

# run <root> — sets OUT, ERR, RC
run() {
  OUT="$(bash "$SCRIPT" --root "$1" 2>/dev/null)"
  RC=0
  ERR="$(bash "$SCRIPT" --root "$1" 2>&1 >/dev/null)" || RC=$?
}

# --- Case 1: AGENTS.md with a region resolves ---------------------------------
r="$(mkrepo agents-only)"
{ printf '# Repo\n\nIntro prose.\n\n'; region "$(pointer docs/conventions)"; printf '\nMore prose.\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 1: resolves with exit 0" 0 "$RC"
assert_eq "case 1: prints the repo-relative home" "docs/conventions" "$OUT"
assert_eq "case 1: stderr is silent on success" "" "$ERR"

# --- Case 2: CLAUDE.md alone (no AGENTS.md) resolves --------------------------
r="$(mkrepo claude-only)"
{ region "$(pointer docs/conventions)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 2: CLAUDE.md alone resolves" 0 "$RC"
assert_eq "case 2: prints the home" "docs/conventions" "$OUT"

# --- Case 3: a pure @AGENTS.md shim is never consulted ------------------------
# Even though the shim's body has a backticked path nowhere, the point is that a
# region inside a shim is impossible by definition; but a shim next to an
# AGENTS.md with no region must yield "ask", not a parse of the shim.
r="$(mkrepo shim)"
printf '\n  @AGENTS.md\r\n\n' >"$r/CLAUDE.md"
printf '# Repo\n\nNo region here.\n' >"$r/AGENTS.md"
run "$r"
assert_exit "case 3: shim skipped, no region anywhere -> exit 1" 1 "$RC"
assert_contains "case 3: says to ask" "$ERR" "ask the operator"
err_explain="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_contains "case 3: explain names the shim" "$err_explain" "pure @AGENTS.md shim"

# --- Case 4: shim with no AGENTS.md at all -> exit 1 --------------------------
r="$(mkrepo shim-orphan)"
printf '@AGENTS.md\n' >"$r/CLAUDE.md"
run "$r"
assert_exit "case 4: orphan shim -> exit 1" 1 "$RC"

# --- Case 5: both files carry a region: AGENTS.md wins, duplicate reported ---
r="$(mkrepo both)"
mkdir -p "$r/other/home"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
{ region "$(pointer other/home)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 5: duplicate is a warning, exit stays 0" 0 "$RC"
assert_eq "case 5: AGENTS.md supplies the value" "docs/conventions" "$OUT"
assert_contains "case 5: duplicate reported on stderr" "$ERR" "duplicate:"
assert_contains "case 5: remediation names the CLAUDE.md copy" "$ERR" "remove the CLAUDE.md copy"

# --- Case 6: two pointer lines in one region -> exit 3 ------------------------
r="$(mkrepo two-pointers)"
{ region "$(pointer docs/conventions)" "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 6: two pointers exit 3" 3 "$RC"
assert_contains "case 6: names the condition" "$ERR" "two pointer lines"
assert_eq "case 6: stdout empty" "" "$OUT"

# --- Case 7: target directory missing -> exit 3 --------------------------------
r="$(mkrepo missing-target)"
{ region "$(pointer docs/nowhere)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 7: missing target exits 3" 3 "$RC"
assert_contains "case 7: names the condition" "$ERR" "target directory missing"
assert_contains "case 7: names the path" "$ERR" "docs/nowhere"

# --- Case 8: invalid pointer paths each exit 3 --------------------------------
backslash=$(printf '%b' '\134')
tilde=$(printf '%b' '\176')
i=0
for bad in "/etc/conventions" "../escape" "${tilde}/conventions" "docs${backslash}conventions" "" "C:/conventions" "./docs/conventions" "docs/../conventions" 'docs/conv entions'; do
  i=$((i + 1))
  r="$(mkrepo "invalid-$i")"
  { region "$(pointer "$bad")"; } >"$r/AGENTS.md"
  run "$r"
  assert_exit "case 8.$i: invalid pointer [$bad] exits 3" 3 "$RC"
  assert_contains "case 8.$i: names invalid pointer path" "$ERR" "invalid pointer path"
done

# --- Case 9: a shell-shaped token is rejected and never executed --------------
r="$(mkrepo injection)"
marker="$TEST_TMPDIR/pwned"
{ region "$(pointer "\$(touch $marker)")"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 9: command-substitution token exits 3" 3 "$RC"
if [[ -e "$marker" ]]; then fail "case 9: token was executed" "marker file exists"; else pass "case 9: token was not executed"; fi

# --- Case 10: CRLF-authored AGENTS.md resolves cleanly ------------------------
r="$(mkrepo crlf)"
{ printf '# Repo\r\n\r\n'; region "$(pointer docs/conventions)" | sed 's/$/\r/'; printf 'tail\r\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 10: CRLF file resolves" 0 "$RC"
assert_eq "case 10: printed home carries no CR" "docs/conventions" "$OUT"

# --- Case 11: no root instruction file at all -> exit 1 -----------------------
r="$(mkrepo bare)"
run "$r"
assert_exit "case 11: no root file exits 1" 1 "$RC"

# --- Case 12: unterminated region -> exit 3 ------------------------------------
r="$(mkrepo unterminated)"
{ printf '%s\n' "$BEGIN"; pointer docs/conventions; printf '\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 12: unterminated region exits 3" 3 "$RC"
assert_contains "case 12: names the condition" "$ERR" "no END marker"

# --- Case 13: region present but no pointer line -> exit 1 --------------------
r="$(mkrepo empty-region)"
{ region "Conventions are documented somewhere."; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 13: empty region exits 1" 1 "$RC"
assert_contains "case 13: says the region has no pointer" "$ERR" "no pointer line"

# --- Case 14: first backticked token wins; prose lines in the region ignored --
r="$(mkrepo first-token)"
mkdir -p "$r/docs/second"
{ region "A prose line with no path." 'Home is `docs/conventions` and not `docs/second`.'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 14: one pointer line with two tokens is fine" 0 "$RC"
assert_eq "case 14: first token is the home" "docs/conventions" "$OUT"

# --- Case 15: a backticked path outside the region is not a pointer ----------
r="$(mkrepo outside)"
printf '# Repo\n\nSee `docs/conventions` for the rules.\n' >"$r/AGENTS.md"
run "$r"
assert_exit "case 15: outside-region path is ignored -> exit 1" 1 "$RC"

# --- Case 16: trailing slash is dropped on output -----------------------------
r="$(mkrepo trailing-slash)"
{ region "$(pointer docs/conventions/)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 16: trailing slash accepted" 0 "$RC"
assert_eq "case 16: normalized without trailing slash" "docs/conventions" "$OUT"

# --- Case 17: markers tolerate surrounding whitespace -------------------------
r="$(mkrepo marker-ws)"
{ printf '  %s  \n' "$BEGIN"; pointer docs/conventions; printf '\n'; printf '\t%s\n' "$END"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 17: indented markers still delimit the region" 0 "$RC"

# --- Case 18: --explain writes to stderr and leaves stdout clean --------------
r="$(mkrepo explain)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
out="$(bash "$SCRIPT" --root "$r" --explain 2>/dev/null)"
err="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_eq "case 18: stdout is exactly the home" "docs/conventions" "$out"
assert_contains "case 18: explain names the chosen file" "$err" "chosen:    AGENTS.md"
assert_contains "case 18: explain names the token" "$err" "token:"

# --- Case 19: a broken canonical file is not papered over by CLAUDE.md -------
r="$(mkrepo canonical-broken)"
{ region "$(pointer docs/conventions)" "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
{ region "$(pointer docs/conventions)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 19: AGENTS.md FAIL wins over a clean CLAUDE.md" 3 "$RC"

# --- Case 20: usage errors exit 2 ----------------------------------------------
rc=0
bash "$SCRIPT" --nope >/dev/null 2>&1 || rc=$?
assert_exit "case 20: unknown argument exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root "$TEST_TMPDIR/does-not-exist" >/dev/null 2>&1 || rc=$?
assert_exit "case 20: missing --root exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --root >/dev/null 2>&1 || rc=$?
assert_exit "case 20: --root with no value exits 2" 2 "$rc"
rc=0
bash "$SCRIPT" --help >/dev/null 2>&1 || rc=$?
assert_exit "case 20: --help exits 0" 0 "$rc"

# --- Case 21: an over-long line is truncated, not parsed past the cap --------
r="$(mkrepo long-line)"
long="$(printf 'x%.0s' $(seq 1 5000))"
{ region "$long "'`docs/conventions`'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 21: token past the cap is not seen -> region reads empty -> exit 1" 1 "$RC"

if [[ "$FAILED" -eq 0 ]]; then
  printf '\nAll %d checks passed.\n' "$CASE_NUM"
  exit 0
fi
printf '\n%d/%d checks failed.\n' "$FAILED" "$CASE_NUM" >&2
exit 1

#!/usr/bin/env bash
# shellcheck disable=SC2016 # single-quoted backticks are the grammar under test
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/resolve-convention-home.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# shellcheck source=test-helpers.sh
source "$SCRIPT_DIR/test-helpers.sh"

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "expected [$2], got [$3]"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "expected to contain: $3 (got: $2)" ;;
  esac
}

BEGIN='<!-- BEGIN GENERATED: convention-home -->'
END='<!-- END GENERATED: convention-home -->'

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.invalid GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.invalid

mkrepo() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d/docs/conventions"
  git init -q "$d" >/dev/null 2>&1
  printf '%s' "$d"
}

mkplain() {
  local d="$TEST_TMPDIR/$1"
  mkdir -p "$d/docs/conventions"
  printf '%s' "$d"
}

commit_all() {
  git -C "$1" add -A >/dev/null 2>&1
  git -C "$1" commit -q -m t >/dev/null 2>&1
  git -C "$1" rev-parse HEAD
}

region() {
  printf '%s\n' "$BEGIN"
  printf '%s\n' "$@"
  printf '%s\n' "$END"
}

pointer() { printf 'Team conventions live in `%s` - read the topic doc there first.' "$1"; }

run() {
  OUT="$(bash "$SCRIPT" --root "$1" 2>/dev/null)"
  RC=0
  ERR="$(bash "$SCRIPT" --root "$1" 2>&1 >/dev/null)" || RC=$?
}

r="$(mkrepo agents-only)"
{ printf '# Repo\n\nIntro prose.\n\n'; region "$(pointer docs/conventions)"; printf '\nMore prose.\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 1: resolves with exit 0" 0 "$RC"
assert_eq "case 1: prints the repo-relative home" "docs/conventions" "$OUT"
assert_eq "case 1: stderr is silent on success" "" "$ERR"

r="$(mkrepo claude-only)"
{ region "$(pointer docs/conventions)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 2: CLAUDE.md alone resolves" 0 "$RC"
assert_eq "case 2: prints the home" "docs/conventions" "$OUT"

r="$(mkrepo shim)"
printf '\n  @AGENTS.md\r\n\n' >"$r/CLAUDE.md"
printf '# Repo\n\nNo region here.\n' >"$r/AGENTS.md"
run "$r"
assert_exit "case 3: shim skipped, no region anywhere -> exit 1" 1 "$RC"
assert_contains "case 3: says to ask" "$ERR" "ask the operator"
err_explain="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_contains "case 3: explain names the shim" "$err_explain" "pure @AGENTS.md shim"

r="$(mkrepo shim-orphan)"
printf '@AGENTS.md\n' >"$r/CLAUDE.md"
run "$r"
assert_exit "case 4: orphan shim -> exit 1" 1 "$RC"

r="$(mkrepo both)"
mkdir -p "$r/other/home"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
{ region "$(pointer other/home)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 5: duplicate is a warning, exit stays 0" 0 "$RC"
assert_eq "case 5: AGENTS.md supplies the value" "docs/conventions" "$OUT"
assert_contains "case 5: duplicate reported on stderr" "$ERR" "duplicate:"
assert_contains "case 5: remediation names the CLAUDE.md copy" "$ERR" "remove the CLAUDE.md copy"

r="$(mkrepo two-pointers)"
{ region "$(pointer docs/conventions)" "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 6: two pointers exit 3" 3 "$RC"
assert_contains "case 6: names the condition" "$ERR" "two pointer lines"
assert_eq "case 6: stdout empty" "" "$OUT"

r="$(mkrepo missing-target)"
{ region "$(pointer docs/nowhere)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 7: missing target exits 3" 3 "$RC"
assert_contains "case 7: names the condition" "$ERR" "target directory missing"
assert_contains "case 7: names the path" "$ERR" "docs/nowhere"

backslash=$(printf '%b' '\134')
tilde=$(printf '%b' '\176')
i=0
for bad in "/etc/conventions" "../escape" "${tilde}/conventions" "docs${backslash}conventions" "" "C:/conventions" "./docs/conventions" "docs/../conventions" 'docs/conv entions' 'docs/a;b' 'docs/a*b' 'docs/a+b'; do
  i=$((i + 1))
  r="$(mkrepo "invalid-$i")"
  { region "$(pointer "$bad")"; } >"$r/AGENTS.md"
  run "$r"
  assert_exit "case 8.$i: invalid pointer [$bad] exits 3" 3 "$RC"
  assert_contains "case 8.$i: names invalid pointer path" "$ERR" "invalid pointer path"
done

r="$(mkrepo injection)"
marker="$TEST_TMPDIR/pwned"
{ region "$(pointer "\$(touch $marker)")"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 9: command-substitution token exits 3" 3 "$RC"
if [[ -e "$marker" ]]; then fail "case 9: token was executed" "marker file exists"; else pass "case 9: token was not executed"; fi

r="$(mkrepo crlf)"
{ printf '# Repo\r\n\r\n'; region "$(pointer docs/conventions)" | sed 's/$/\r/'; printf 'tail\r\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 10: CRLF file resolves" 0 "$RC"
assert_eq "case 10: printed home carries no CR" "docs/conventions" "$OUT"

r="$(mkrepo bare)"
run "$r"
assert_exit "case 11: no root file exits 1" 1 "$RC"

r="$(mkrepo unterminated)"
{ printf '%s\n' "$BEGIN"; pointer docs/conventions; printf '\n'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 12: unterminated region exits 3" 3 "$RC"
assert_contains "case 12: names the condition" "$ERR" "no END marker"

r="$(mkrepo empty-region)"
{ region "Conventions are documented somewhere."; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 13: empty region exits 1" 1 "$RC"
assert_contains "case 13: says the region has no pointer" "$ERR" "no pointer line"

r="$(mkrepo first-token)"
mkdir -p "$r/docs/second"
{ region "A prose line with no path." 'Home is `docs/conventions` and not `docs/second`.'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 14: one pointer line with two tokens is fine" 0 "$RC"
assert_eq "case 14: first token is the home" "docs/conventions" "$OUT"

r="$(mkrepo outside)"
printf '# Repo\n\nSee `docs/conventions` for the rules.\n' >"$r/AGENTS.md"
run "$r"
assert_exit "case 15: outside-region path is ignored -> exit 1" 1 "$RC"

r="$(mkrepo trailing-slash)"
{ region "$(pointer docs/conventions/)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 16: trailing slash accepted" 0 "$RC"
assert_eq "case 16: normalized without trailing slash" "docs/conventions" "$OUT"

r="$(mkrepo marker-ws)"
{ printf '  %s  \n' "$BEGIN"; pointer docs/conventions; printf '\n'; printf '\t%s\n' "$END"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 17: indented markers still delimit the region" 0 "$RC"

r="$(mkrepo explain)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
out="$(bash "$SCRIPT" --root "$r" --explain 2>/dev/null)"
err="$(bash "$SCRIPT" --root "$r" --explain 2>&1 >/dev/null)"
assert_eq "case 18: stdout is exactly the home" "docs/conventions" "$out"
assert_contains "case 18: explain names the chosen file" "$err" "chosen:    AGENTS.md"
assert_contains "case 18: explain names the token" "$err" "token:"

r="$(mkrepo canonical-broken)"
{ region "$(pointer docs/conventions)" "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
{ region "$(pointer docs/conventions)"; } >"$r/CLAUDE.md"
run "$r"
assert_exit "case 19: AGENTS.md FAIL wins over a clean CLAUDE.md" 3 "$RC"

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

r="$(mkrepo long-line)"
long="$(printf 'x%.0s' $(seq 1 5000))"
{ region "$long "'`docs/conventions`'; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 21: token past the cap is not seen -> region reads empty -> exit 1" 1 "$RC"

bom=$(printf '\357\273\277')
r="$(mkrepo bom-absent)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 22a: same fixture without BOM resolves" 0 "$RC"
assert_eq "case 22a: without BOM prints the home" "docs/conventions" "$OUT"

r="$(mkrepo bom-present)"
{
  printf '%s' "$bom"
  region "$(pointer docs/conventions)"
} >"$r/AGENTS.md"
run "$r"
assert_exit "case 22b: same fixture with BOM immediately before BEGIN resolves" 0 "$RC"
assert_eq "case 22b: with BOM prints the home" "docs/conventions" "$OUT"

r="$(mkrepo class-home)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
OUT="$(HOME="$r" bash "$SCRIPT" --root "$r" 2>/dev/null)"; RC=0
HOME="$r" bash "$SCRIPT" --root "$r" >/dev/null 2>&1 || RC=$?
assert_exit "case 23a: a root at \$HOME is not applicable" 5 "$RC"
assert_eq "case 23a: nothing on stdout" "" "$OUT"
ERR="$(HOME="$r" bash "$SCRIPT" --root "$r" 2>&1 >/dev/null)"
assert_contains "case 23a: says not applicable" "$ERR" "not applicable"

mkdir -p "$r/deep/er"
RC=0
HOME="$r/deep/er" bash "$SCRIPT" --root "$r" >/dev/null 2>&1 || RC=$?
assert_exit "case 23b: a root that is an ancestor of \$HOME is not applicable" 5 "$RC"

RC=0
HOME="$r/deep/er" bash "$SCRIPT" --root "$r/deep" >/dev/null 2>&1 || RC=$?
assert_exit "case 23c: a root below an ancestor of \$HOME is still an ancestor" 5 "$RC"

p="$(mkplain class-plain)"
{ region "$(pointer docs/conventions)"; } >"$p/AGENTS.md"
run "$p"
assert_exit "case 23d: a root outside any git work tree is not applicable" 5 "$RC"
assert_contains "case 23d: names the cause" "$ERR" "not inside a git work tree"

RC=0
HOME="$TEST_TMPDIR/elsewhere" bash "$SCRIPT" --root "$r" >/dev/null 2>&1 || RC=$?
assert_exit "case 23e: a git root that is neither \$HOME nor its ancestor resolves" 0 "$RC"

r="$(mkrepo symlink-claude)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
ln -s AGENTS.md "$r/CLAUDE.md"
run "$r"
assert_exit "case 24a: CLAUDE.md -> AGENTS.md resolves" 0 "$RC"
assert_eq "case 24a: prints the home" "docs/conventions" "$OUT"
case "$ERR" in
*duplicate:*) fail "case 24a: no duplicate line for a symlinked CLAUDE.md" "stderr: $ERR" ;;
*) pass "case 24a: no duplicate line for a symlinked CLAUDE.md" ;;
esac

r="$(mkrepo symlink-agents)"
{ region "$(pointer docs/conventions)"; } >"$r/CLAUDE.md"
ln -s CLAUDE.md "$r/AGENTS.md"
run "$r"
assert_exit "case 24b: AGENTS.md -> CLAUDE.md resolves" 0 "$RC"
case "$ERR" in
*duplicate:*) fail "case 24b: no duplicate line for a symlinked AGENTS.md" "stderr: $ERR" ;;
*) pass "case 24b: no duplicate line for a symlinked AGENTS.md" ;;
esac

r="$(mkrepo copy-claude)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
cp "$r/AGENTS.md" "$r/CLAUDE.md"
run "$r"
assert_contains "case 24c: a real copy is still a duplicate" "$ERR" "duplicate:"

r="$(mkrepo ref-sha)"
printf 'x\n' >"$r/docs/conventions/x.md"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
sha="$(commit_all "$r")"
git -C "$r" update-ref refs/remotes/origin/main "$sha"
{ region "Nothing is bound here."; } >"$r/AGENTS.md"
OUT="$(bash "$SCRIPT" --root "$r" --ref "$sha" 2>/dev/null)"; RC=0
bash "$SCRIPT" --root "$r" --ref "$sha" >/dev/null 2>&1 || RC=$?
assert_exit "case 25a: a 40-hex ref reads the committed file" 0 "$RC"
assert_eq "case 25a: prints the committed home" "docs/conventions" "$OUT"
OUT="$(bash "$SCRIPT" --root "$r" --ref origin/main 2>/dev/null)"; RC=0
bash "$SCRIPT" --root "$r" --ref origin/main >/dev/null 2>&1 || RC=$?
assert_exit "case 25b: origin/<name> reads the committed file" 0 "$RC"
assert_eq "case 25b: prints the committed home" "docs/conventions" "$OUT"
run "$r"
assert_exit "case 25c: without --ref the working tree is read" 1 "$RC"

for bad in "HEAD" "main" "origin/../x" "origin/-x" "--upload-pack=x" "${sha:0:39}" "${sha}0" "$(printf '%s' "$sha" | tr 'a-f' 'A-F')" ""; do
  RC=0
  bash "$SCRIPT" --root "$r" --ref "$bad" >/dev/null 2>&1 || RC=$?
  assert_exit "case 25d: ref shape [$bad] exits 2" 2 "$RC"
done
RC=0
bash "$SCRIPT" --root "$r" --ref "$(printf '0%.0s' $(seq 1 40))" >/dev/null 2>&1 || RC=$?
assert_exit "case 25e: a well-formed ref that is no commit exits 2" 2 "$RC"
RC=0
bash "$SCRIPT" --root "$r" --ref >/dev/null 2>&1 || RC=$?
assert_exit "case 25f: --ref with no value exits 2" 2 "$RC"

r="$(mkrepo ref-missing-home)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
sha="$(commit_all "$r")"
mkdir -p "$r/docs/conventions"
printf 'x\n' >"$r/docs/conventions/x.md"
RC=0
bash "$SCRIPT" --root "$r" --ref "$sha" >/dev/null 2>&1 || RC=$?
assert_exit "case 25g: a home directory absent at the ref exits 3" 3 "$RC"

r="$(mkrepo ref-subdir)"
mkdir -p "$r/sub/docs/conventions"
printf 'x\n' >"$r/sub/docs/conventions/x.md"
{ region "$(pointer docs/conventions)"; } >"$r/sub/AGENTS.md"
sha="$(commit_all "$r")"
OUT="$(bash "$SCRIPT" --root "$r/sub" --ref "$sha" 2>/dev/null)"; RC=0
bash "$SCRIPT" --root "$r/sub" --ref "$sha" >/dev/null 2>&1 || RC=$?
assert_exit "case 25h: --ref with a --root below the toplevel reads that directory's file" 0 "$RC"
assert_eq "case 25h: prints the home" "docs/conventions" "$OUT"

OUT="$({ region "$(pointer docs/conventions)"; } | bash "$SCRIPT" - 2>/dev/null)"; RC=0
{ region "$(pointer docs/conventions)"; } | bash "$SCRIPT" - >/dev/null 2>&1 || RC=$?
assert_exit "case 26a: stdin region resolves" 0 "$RC"
assert_eq "case 26a: prints the home" "docs/conventions" "$OUT"
RC=0
printf 'No region.\n' | bash "$SCRIPT" - >/dev/null 2>&1 || RC=$?
assert_exit "case 26b: stdin without a region exits 1" 1 "$RC"
RC=0
{ region "$(pointer docs/conventions)" "$(pointer docs/conventions)"; } | bash "$SCRIPT" - >/dev/null 2>&1 || RC=$?
assert_exit "case 26c: stdin with two pointers exits 3" 3 "$RC"
RC=0
{ region "$(pointer docs/conventions)"; } | bash "$SCRIPT" - --root "$TEST_TMPDIR" >/dev/null 2>&1 || RC=$?
assert_exit "case 26d: stdin with --root exits 2" 2 "$RC"

r="$(mkrepo declined)"
{ region "declined"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 27a: a declined region exits 4" 4 "$RC"
assert_eq "case 27a: stdout empty" "" "$OUT"
assert_contains "case 27a: says not to ask again" "$ERR" "do not ask again"

r="$(mkrepo declined-padded)"
{ region "  declined  "; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 27b: surrounding whitespace is ignored" 4 "$RC"

r="$(mkrepo declined-outside)"
printf 'declined\n' >"$r/AGENTS.md"
run "$r"
assert_exit "case 27c: a declined line outside the region is prose" 1 "$RC"

r="$(mkrepo declined-with-pointer)"
{ region "declined" "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 27d: declined beside a pointer is a FAIL" 3 "$RC"

r="$(mkrepo toplevel)"
mkdir -p "$r/packages/app"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
OUT="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$r/packages/app" bash "$SCRIPT" 2>/dev/null)"; RC=0
(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$r/packages/app" bash "$SCRIPT" >/dev/null 2>&1) || RC=$?
assert_exit "case 28a: CLAUDE_PROJECT_DIR in a subdirectory reads the toplevel's file" 0 "$RC"
assert_eq "case 28a: prints the toplevel's home" "docs/conventions" "$OUT"
{ region "Not bound."; } >"$r/packages/app/AGENTS.md"
OUT="$(cd "$TEST_TMPDIR" && CLAUDE_PROJECT_DIR="$r/packages/app" bash "$SCRIPT" 2>/dev/null)"
assert_eq "case 28b: the subdirectory's own AGENTS.md is not consulted" "docs/conventions" "$OUT"

for bad in .git .git/ .git/hooks .GIT sub/.git/info .git. .Git../hooks; do
  r="$(mkrepo "dot-git-$CASE_NUM")"
  mkdir -p "$r/sub/.git/info"
  { region "$(pointer "$bad")"; } >"$r/AGENTS.md"
  run "$r"
  assert_exit "case 29: pointer [$bad] exits 3" 3 "$RC"
  assert_contains "case 29: pointer [$bad] names the .git segment" "$ERR" ".git segment"
done
r="$(mkrepo dot-gitlike)"
mkdir -p "$r/.github"
{ region "$(pointer .github)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 29: a segment that only starts with .git resolves" 0 "$RC"

r="$(mkrepo symlinked-home)"
mkdir -p "$r/Real"
ln -s Real "$r/Alias"
{ region "$(pointer Alias)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 30a: a symlinked home exits 3" 3 "$RC"
assert_contains "case 30a: names the symlink" "$ERR" "through a symlink"
r="$(mkrepo symlinked-parent)"
mkdir -p "$r/real/conventions"
ln -s real "$r/link"
{ region "$(pointer link/conventions)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 30b: a home under a symlinked directory exits 3" 3 "$RC"
r="$(mkrepo symlinked-outside)"
ln -s "$TEST_TMPDIR" "$r/out"
{ region "$(pointer out)"; } >"$r/AGENTS.md"
run "$r"
assert_exit "case 30c: a symlink out of the repository exits 3" 3 "$RC"
r="$(mkrepo symlinked-root)"
{ region "$(pointer docs/conventions)"; } >"$r/AGENTS.md"
ln -s "$r" "$TEST_TMPDIR/root-link"
OUT="$(bash "$SCRIPT" --root "$TEST_TMPDIR/root-link" 2>/dev/null)"; RC=0
bash "$SCRIPT" --root "$TEST_TMPDIR/root-link" >/dev/null 2>&1 || RC=$?
assert_exit "case 30d: a symlinked --root with a real home resolves" 0 "$RC"
assert_eq "case 30d: prints the home" "docs/conventions" "$OUT"

report_and_exit

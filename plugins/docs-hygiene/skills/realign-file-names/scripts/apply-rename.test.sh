#!/usr/bin/env bash
# Self-contained tests for apply-rename.sh, driven against the committed fixture
# tree the audit sibling owns (fixtures/build-fixture.sh in audit-file-names).
#
# The audit stages run for real in `audit()` rather than being stubbed: the
# artifact is this script's only instruction set, so a suite that hand-wrote it
# would test a plan shape no audit produces.
#
# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# redirect `git init` / `git config` into the caller's repository.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SUT="$SCRIPT_DIR/apply-rename.sh"
AUDIT_DIR="$SCRIPT_DIR/../../audit-file-names/scripts"
INVENTORY="$AUDIT_DIR/inventory.sh"
SWEEP="$AUDIT_DIR/sweep.sh"
EMIT="$AUDIT_DIR/emit-findings.sh"
BUILD="$AUDIT_DIR/fixtures/build-fixture.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

FAILED=0
CASES=0

pass() {
  CASES=$((CASES + 1))
  printf 'PASS: %s\n' "$1"
}

fail() {
  CASES=$((CASES + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$2" "$3"; fi
}

assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}

assert_absent() {
  case "$2" in
  *"$3"*) fail "$1" "does NOT contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

# stage <root> : audit the tree and leave plan.md beside it. Prints the plan path.
stage() {
  w="$1/.audit"
  mkdir -p "$w"
  bash "$INVENTORY" --root "$1" >"$w/inv.tsv" 2>/dev/null
  awk -F'\t' '$1=="OFFENDER" {print $2 "\t" $3}' "$w/inv.tsv" >"$w/pairs.tsv"
  bash "$SWEEP" --root "$1" --pairs "$w/pairs.tsv" >"$w/sweep.tsv" 2>/dev/null
  bash "$EMIT" --root "$1" --inventory "$w/inv.tsv" --sweep "$w/sweep.tsv" \
    --out "$w/plan.md" >/dev/null 2>&1
  printf '%s' "$w/plan.md"
}

# Only the clean variant is used here: the collision variant makes the AUDIT
# refuse to emit a plan, so there is no artifact for this stage to act on.
new_fixture() {
  d="$TEST_TMPDIR/fx-$CASES-$RANDOM"
  bash "$BUILD" "$d" >/dev/null
  printf '%s' "$d"
}

# id_for <plan> <old-path> : the finding id whose record renames <old-path>
id_for() {
  awk -v old="\`$2\`" '$1=="###" && $3==old {print $2; exit}' "$1"
}

# BSD sed's `-i` takes a mandatory backup suffix, so every in-place edit in this
# suite goes through a temp file and is written back with `cat`.
inplace() {
  f="$1"
  shift
  sed "$@" "$f" >"$f.tmp.$$" || return 1
  cat "$f.tmp.$$" >"$f"
  rm -f "$f.tmp.$$"
}

accept() {
  inplace "$1" "/^### $2 /,/^### FN-/{s/^- \*\*Status:\*\* pending\$/- **Status:** accepted/}"
}

status_of() {
  awk -v id="$2" '
    $0 ~ "^### " id " " { inrec = 1; next }
    inrec && /^- \*\*Status:\*\* / { print $3; exit }
  ' "$1"
}

run() {
  bash "$SUT" "$@" 2>&1
}

# --- a single accepted rename, every current-tier form rewritten --------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Alpha-One.md)"
accept "$plan" "$id"
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "an accepted rename exits 0" "0" "$rc"
assert_contains "the run names the pair it applied" "$out" "APPLIED	$id	docs/Alpha-One.md	docs/alpha-one.md"
assert_eq "the record closes applied" "applied" "$(status_of "$plan" "$id")"
assert_eq "the old path leaves the index" "0" \
  "$(git -C "$root" ls-files -- docs/Alpha-One.md | wc -l | tr -d ' ')"
assert_eq "the new path enters the index" "1" \
  "$(git -C "$root" ls-files -- docs/alpha-one.md | wc -l | tr -d ' ')"

readme="$(cat "$root/README.md")"
assert_contains "a markdown link is repointed" "$readme" "[Alpha One](docs/alpha-one.md)"
assert_contains "a forge URL is repointed" "$readme" "blob/main/docs/alpha-one.md"
assert_contains "an unambiguous bare stem is rewritten" "$readme" "unambiguous and edited: alpha-one."
assert_absent "no current-tier site keeps the old basename" "$readme" "Alpha-One.md"

# --- the released tier is frozen ---------------------------------------------

assert_eq "a released file is byte-identical after an apply" "0" \
  "$(git -C "$root" diff --quiet -- CHANGELOG.md && echo 0 || echo 1)"
assert_contains "the released entry keeps the old name" \
  "$(cat "$root/CHANGELOG.md")" "[Alpha One](docs/Alpha-One.md)"

# --- the historical tier takes links and paths, never narrative ---------------

adr="$(cat "$root/docs/adr/0001-historical.md")"
assert_contains "a historical markdown link is repointed" "$adr" "[Alpha One](../alpha-one.md)"
assert_contains "historical narrative is left as written" "$adr" \
  "the team argued about BETA for two weeks"

# The other half of `links-and-paths`: a backtick path in the same historical
# file is repointed too. Applying BETA rather than Alpha-One, because that is
# the pair whose historical site is a backtick path.
root2="$(new_fixture)"
plan2="$(stage "$root2")"
idb="$(id_for "$plan2" docs/BETA.md)"
accept "$plan2" "$idb"
run --artifact "$plan2" --id "$idb" --root "$root2" >/dev/null
adr2="$(cat "$root2/docs/adr/0001-historical.md")"
# shellcheck disable=SC2016  # backticks are literal markdown in the fixture
assert_contains "a historical backtick path is repointed" "$adr2" '`docs/beta.md`'
assert_contains "and the narrative bare stem beside it is not" "$adr2" \
  "the team argued about BETA for two weeks"

# --- an unaccepted sibling is never touched ----------------------------------

assert_eq "a pending sibling stays pending" "pending" \
  "$(status_of "$plan" "$(id_for "$plan" docs/Gamma_Three.md)")"
assert_eq "an unaccepted offender keeps its path" "1" \
  "$(git -C "$root" ls-files -- docs/Gamma_Three.md | wc -l | tr -d ' ')"

# --- the generated record is regenerated, never text-edited ------------------

assert_contains "the run names the generated path it rebuilt" "$out" "REGENERATED	build/out.json"
gen="$(cat "$root/build/out.json")"
assert_contains "the regenerator rewrote the record from the tree" "$gen" '"generated_on": "regenerated"'
assert_contains "the rebuilt record carries the new path" "$gen" "docs/alpha-one.md"
assert_absent "the rebuilt record drops the old path" "$gen" "docs/Alpha-One.md"

# --- mode bits survive an edit ------------------------------------------------

root="$(new_fixture)"
chmod +x "$root/docs/tool.py"
git -C "$root" update-index --chmod=+x docs/tool.py
git -C "$root" commit -qm "tool.py is executable" -a >/dev/null 2>&1
plan="$(stage "$root")"
id="$(id_for "$plan" docs/BETA.md)"
accept "$plan" "$id"
out="$(run --artifact "$plan" --id "$id" --root "$root")"

assert_contains "the executable site was edited" "$(cat "$root/docs/tool.py")" 'DOC = "docs/beta.md"'
assert_eq "an edited executable keeps its mode bits" "yes" \
  "$([[ -x "$root/docs/tool.py" ]] && echo yes || echo no)"
assert_eq "the index keeps the executable bit too" "100755" \
  "$(git -C "$root" ls-files -s -- docs/tool.py | awk '{print $1}')"

# --- two mutually referencing offenders, applied one after the other ----------

root="$(new_fixture)"
plan="$(stage "$root")"
a="$(id_for "$plan" docs/Alpha-One.md)"
b="$(id_for "$plan" docs/BETA.md)"
accept "$plan" "$a"
accept "$plan" "$b"
first="$(run --artifact "$plan" --id "$a" --root "$root")"
second="$(run --artifact "$plan" --id "$b" --root "$root")"
rc=$?

assert_eq "the second of a mutually citing pair still applies" "0" "$rc"
assert_contains "the second rename lands" "$second" "APPLIED	$b	docs/BETA.md	docs/beta.md"
assert_eq "the second run reports no drift" "DRIFTED	0" \
  "$(printf '%s\n' "$second" | grep '^DRIFTED')"
assert_contains "the first file, moved and then edited, cites the second's new path" \
  "$(cat "$root/docs/alpha-one.md")" '[Beta](beta.md)'
assert_contains "the second file cites the first's new path" \
  "$(cat "$root/docs/beta.md")" '[Alpha One](alpha-one.md)'
assert_absent "the first run's output is not a no-op report" "$first" "EDITED	0"

# --- a drifted site is reported and skipped, never edited blind --------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
# The audit recorded a backtick path on README.md line 6; move it out from under
# the record without touching the line count.
# shellcheck disable=SC2016  # the backticks are literal markdown, not a subshell
inplace "$root/README.md" '6s|.*|- backtick path: `docs/somewhere-else.md`|'
out="$(run --artifact "$plan" --id "$id" --root "$root")"

assert_contains "a drifted site is counted" "$out" "DRIFTED	1"
assert_contains "the drifted site is named on stderr" "$out" \
  "site no longer carries the old name, skipped: README.md:6"
assert_contains "the drifted line is left exactly as found" \
  "$(sed -n '6p' "$root/README.md")" 'docs/somewhere-else.md'
assert_contains "the undrifted sites still applied" "$out" "APPLIED	$id"

# --- a bare stem is rewritten anchored, never inside a longer name -----------
#
# The sweep anchors its DETECTION so a hyphenated sibling is never matched
# inside a stem. An unanchored apply would throw that away and rewrite a
# reference to a file nobody renamed, which the run would report as an edit.

root="$(new_fixture)"
inplace "$root/README.md" \
  '14s|.*|A bare stem with a hyphen, unambiguous and edited: Alpha-One, beside Alpha-One-notes.md.|'
git -C "$root" commit -qm "a hyphenated sibling on the bare-stem line" -a >/dev/null
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Alpha-One.md)"
accept "$plan" "$id"
run --artifact "$plan" --id "$id" --root "$root" >/dev/null
line="$(sed -n '14p' "$root/README.md")"

assert_contains "the anchored bare stem is rewritten" "$line" "unambiguous and edited: alpha-one,"
assert_contains "a longer name carrying the stem is left alone" "$line" "Alpha-One-notes.md"

# --- the id is a finding id, never a pattern ---------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
before="$(git -C "$root" status --porcelain)"
out="$(run --artifact "$plan" --id 'FN-.*' --root "$root")"
rc=$?

assert_eq "an id carrying regex metacharacters is refused" "2" "$rc"
assert_contains "the refusal names the shape it wanted" "$out" "must be a finding id of the form"
assert_eq "and nothing was touched" "$before" "$(git -C "$root" status --porcelain)"

# --- a file that cites itself -------------------------------------------------
#
# Its own sites are planned against the old path, which the move retires. A run
# that read them and stopped there would exit 1 with the tree half-changed,
# contradicting what exit 1 promises.

root="$(new_fixture)"
# shellcheck disable=SC2016  # backticks are literal markdown in the seeded line
inplace "$root/docs/Gamma_Three.md" \
  '4s|.*|This record cites its own path, `docs/Gamma_Three.md`, from inside itself.|'
git -C "$root" commit -qm "a self-citing offender" -a >/dev/null
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "a self-citing offender applies in one run" "0" "$rc"
assert_eq "the record closes applied" "applied" "$(status_of "$plan" "$id")"
# shellcheck disable=SC2016  # backticks are literal markdown in the expectation
assert_contains "its own citation is repointed at the new path" \
  "$(cat "$root/docs/gamma-three.md")" '`docs/gamma-three.md`'

# --- a generated path is never text-edited, whatever the record says ----------
#
# Discriminating on purpose: the record is hand-edited to mark the generated
# site `edit`, the one input that would reach the guard. Without the guard the
# substitution would land and the regenerator would then rewrite over it, so a
# fixture whose generated site is already `regenerate` cannot tell the two
# apart.

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Alpha-One.md)"
accept "$plan" "$id"
# shellcheck disable=SC2016  # backticks are literal markdown in the plan row
inplace "$plan" 's#^\(| `build/out.json` .*\) regenerate |#\1 edit |#'
assert_contains "the record now marks the generated site as an edit" \
  "$(grep 'build/out.json' "$plan")" "| edit |"
run --artifact "$plan" --id "$id" --root "$root" >/dev/null
assert_eq "the generated file is byte-identical after the apply" "0" \
  "$(git -C "$root" diff --quiet -- build/out.json && echo 0 || echo 1)"
assert_contains "so its stale sample is still the old path, not a substitution" \
  "$(cat "$root/build/out.json")" "docs/Alpha-One.md"

# --- a missing old path is refused -------------------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
git -C "$root" rm -q docs/Gamma_Three.md
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "an untracked old path blocks the run" "1" "$rc"
assert_contains "the refusal names the remedy" "$out" "the fix is a re-audit, not a guess"
assert_eq "an accepted record whose file moved is recorded blocked" "blocked" \
  "$(status_of "$plan" "$id")"
assert_eq "and the sibling records are untouched" "pending" \
  "$(status_of "$plan" "$(id_for "$plan" docs/Alpha-One.md)")"

# A record nobody accepted is left alone: nothing was decided about it, so
# there is no decision to mark unachievable.
root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
git -C "$root" rm -q docs/Gamma_Three.md
run --artifact "$plan" --id "$id" --root "$root" >/dev/null
assert_eq "a pending record whose file moved stays pending" "pending" "$(status_of "$plan" "$id")"

# --- an unresolvable regenerator stops the run BEFORE anything moves ----------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Alpha-One.md)"
accept "$plan" "$id"
inplace "$root/.claude/docs-hygiene.json" 's|bash tools/gen.sh .|bash tools/does-not-exist.sh .|'
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "an unresolvable regenerator blocks the run" "1" "$rc"
assert_contains "the refusal names the command it could not resolve" "$out" "does-not-exist.sh"
assert_eq "nothing moved" "1" \
  "$(git -C "$root" ls-files -- docs/Alpha-One.md | wc -l | tr -d ' ')"
assert_eq "the record is untouched" "accepted" "$(status_of "$plan" "$id")"

# --- an interrupted apply resumes --------------------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
# The shape a run that died between `git mv` and its first edit leaves behind.
inplace "$plan" "/^### $id /,/^### FN-/{s/^- \*\*Status:\*\* accepted\$/- **Status:** applying/}"
git -C "$root" mv docs/Gamma_Three.md docs/gamma-three.md
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "a half-finished apply resumes rather than blocking" "0" "$rc"
assert_contains "the resume is announced" "$out" "resuming an interrupted apply of $id"
assert_eq "the resumed record closes applied" "applied" "$(status_of "$plan" "$id")"
assert_contains "the edits the dead run never made are made now" \
  "$(cat "$root/docs/README.md")" "[Gamma Three](gamma-three.md)"
assert_eq "a resumed run reports no drift" "DRIFTED	0" \
  "$(printf '%s\n' "$out" | grep '^DRIFTED')"

# --- a second run over an applied record is refused, not repeated ------------

before="$(git -C "$root" status --porcelain)"
plan_before="$(cat "$plan")"
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?
assert_eq "re-running an applied record exits 1" "1" "$rc"
assert_contains "the refusal says why" "$out" "is already applied"
assert_eq "the second run is a no-op on the tree" "$before" "$(git -C "$root" status --porcelain)"
assert_eq "and a no-op on the plan" "$plan_before" "$(cat "$plan")"

# --- --dry-run changes nothing -----------------------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Alpha-One.md)"
accept "$plan" "$id"
before="$(git -C "$root" status --porcelain)"
out="$(run --artifact "$plan" --id "$id" --root "$root" --dry-run)"
rc=$?

assert_eq "a dry run exits 0" "0" "$rc"
assert_contains "a dry run names the pair" "$out" "DRY-RUN	$id	docs/Alpha-One.md	docs/alpha-one.md"
assert_contains "a dry run lists the edits it would make" "$out" "WOULD-EDIT	README.md"
assert_contains "a dry run prints the per-tier form table" "$out" "WOULD-TIER	current	rewrites: "
assert_contains "and says what a frozen tier would only list" "$out" \
  "WOULD-TIER	released	rewrites: (none)	lists: md-link"
assert_contains "a dry run names the record it would rebuild" "$out" "WOULD-REGENERATE	build/out.json"
assert_eq "a dry run leaves the tree exactly as it was" "$before" "$(git -C "$root" status --porcelain)"
assert_eq "a dry run leaves the record alone" "accepted" "$(status_of "$plan" "$id")"

# --- --regenerate-only is the closing pass -----------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
for p in docs/Alpha-One.md docs/BETA.md docs/Gamma_Three.md; do
  i="$(id_for "$plan" "$p")"
  accept "$plan" "$i"
  run --artifact "$plan" --id "$i" --root "$root" >/dev/null
done
stale="$(cat "$root/build/out.json")"
out="$(run --regenerate-only --root "$root")"
rc=$?

assert_eq "--regenerate-only exits 0 with no artifact" "0" "$rc"
assert_contains "it names what it rebuilt" "$out" "REGENERATED	build/out.json"
assert_contains "the last rename of a run leaves the record stale" "$stale" "docs/Gamma_Three.md"
assert_absent "the closing pass clears it" "$(cat "$root/build/out.json")" "docs/Gamma_Three.md"
assert_contains "the closing pass records the final name" \
  "$(cat "$root/build/out.json")" "docs/gamma-three.md"

# --- a plan written on another branch is refused ------------------------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/BETA.md)"
accept "$plan" "$id"
git -C "$root" checkout -q -b some-other-branch
out="$(run --artifact "$plan" --id "$id" --root "$root")"
rc=$?

assert_eq "a plan from another branch blocks" "1" "$rc"
assert_contains "the refusal names both branches" "$out" "and this checkout is on 'some-other-branch'"

# --- an id the plan does not carry -------------------------------------------

git -C "$root" checkout -q -
out="$(run --artifact "$plan" --id FN-deadbeef --root "$root")"
rc=$?
assert_eq "an unknown id blocks" "1" "$rc"
assert_contains "the refusal names the id" "$out" "carries no finding 'FN-deadbeef'"

# --- a pending record is applied without a separate accept gate ---------------
#
# The gate is the SKILL's, per finding and per human. The script refuses only a
# status it cannot act on, so a plan record left pending still applies when the
# skill asks for it; what it must never do is act on one already applied.

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
out="$(run --artifact "$plan" --id "$id" --root "$root")"
assert_eq "a pending record applies when the caller asks" "applied" "$(status_of "$plan" "$id")"

# --- --root drives a checkout the script is not run from ----------------------

root="$(new_fixture)"
plan="$(stage "$root")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
other="$TEST_TMPDIR/elsewhere-$RANDOM"
mkdir -p "$other"
out="$(cd "$other" && bash "$SUT" --artifact "$plan" --id "$id" --root "$root" 2>&1)"
rc=$?

assert_eq "--root applies against a checkout the cwd is outside of" "0" "$rc"
assert_eq "the rename landed in the named root" "1" \
  "$(git -C "$root" ls-files -- docs/gamma-three.md | wc -l | tr -d ' ')"

# --- a real linked worktree ---------------------------------------------------
#
# A linked worktree's `.git` is a FILE pointing at the main repository's
# `worktrees/` directory, not a directory. Every git call here goes through
# `-C "$ROOT"`, so it resolves; an ordinary directory would not exercise that.

root="$(new_fixture)"
wt="$TEST_TMPDIR/wt-$RANDOM"
git -C "$root" worktree add -q -b side "$wt" >/dev/null 2>&1
plan="$(stage "$wt")"
id="$(id_for "$plan" docs/Gamma_Three.md)"
accept "$plan" "$id"
out="$(run --artifact "$plan" --id "$id" --root "$wt")"
rc=$?

assert_eq "the .git file of a linked worktree is not a directory" "yes" \
  "$([[ -f "$wt/.git" ]] && echo yes || echo no)"
assert_eq "a linked worktree applies" "0" "$rc"
assert_eq "the rename landed in the worktree" "1" \
  "$(git -C "$wt" ls-files -- docs/gamma-three.md | wc -l | tr -d ' ')"
assert_eq "and the main checkout is untouched" "1" \
  "$(git -C "$root" ls-files -- docs/Gamma_Three.md | wc -l | tr -d ' ')"
git -C "$root" worktree remove --force "$wt" >/dev/null 2>&1

# --- results ------------------------------------------------------------------

printf '\n%d case(s), %d failure(s)\n' "$CASES" "$FAILED"
[[ "$FAILED" -eq 0 ]] || exit 1

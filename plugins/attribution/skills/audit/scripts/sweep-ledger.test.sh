#!/usr/bin/env bash
# Self-contained tests for sweep-ledger.sh. Fixtures are built inline in a tmpdir.
# Per the shell-test-helpers convention, assertion helpers are local.
#
# Every case runs from inside a throwaway git repository, so the ledger lands in
# that repository's .work/ and never in this checkout's. The load-bearing cases are
# the ones a resumed sweep leans on: spend adding up across separate invocations,
# the ceiling stopping a sweep, a second checkout seeing a new sweep, and a cache
# hit coming back as a re-validation rather than as something reusable.
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEDGER_SH="$SCRIPT_DIR/sweep-ledger.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP: jq not installed (the ceiling is read from JSON config)" >&2
  exit 0
fi
if ! command -v git >/dev/null 2>&1; then
  echo "SKIP: git not installed (the ledger root is the checkout toplevel)" >&2
  exit 0
fi

export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/config"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR/.claude"

FAILED=0
CASE_NUM=0

pass() {
  CASE_NUM=$((CASE_NUM + 1))
  printf 'PASS: %s\n' "$1"
}
fail() {
  CASE_NUM=$((CASE_NUM + 1))
  FAILED=$((FAILED + 1))
  printf 'FAIL: %s\n  expected: %s\n  actual:   %s\n' "$1" "$2" "$3" >&2
}
assert_exit() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $3" "exit $2"; fi
}
assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "does not contain: $3" "$2" ;;
  *) pass "$1" ;;
  esac
}

# --- Fixtures --------------------------------------------------------------------

REPO="$TEST_TMPDIR/repo"
OTHER="$TEST_TMPDIR/other-checkout"
for d in "$REPO" "$OTHER"; do
  mkdir -p "$d"
  git -C "$d" init -q
  printf '%s\n' '.work/' >"$d/.git/info/exclude"
done
# The script names the ledger from git's own spelling of the toplevel, which is not
# the mktemp spelling on macOS (/private/var) or Git for Windows (C:/...).
REPO="$(git -C "$REPO" rev-parse --show-toplevel)"
OTHER="$(git -C "$OTHER" rev-parse --show-toplevel)"
LEDGER="$REPO/.work/t1/sweep-ledger.md"
OTHER_LEDGER_DIR="$OTHER/.work/t1"

# run <args...>: the script from inside the first checkout, stdout and stderr together.
run() { (cd "$REPO" && bash "$LEDGER_SH" "$@" 2>&1); }
run_other() { (cd "$OTHER" && bash "$LEDGER_SH" "$@" 2>&1); }

CLOSE_FIELDS=(--dispositions "convert-to-pointer x1, leave-with-reason x1"
  --pointer-liveness "live" --semantic-diff "no loss" --in-span "inside" --carve-out "unchanged")

URL="https://example.com/docs/page"
SHA_A="$(printf 'a%.0s' {1..64})"
SHA_B="$(printf 'b%.0s' {1..64})"

# --- Usage -----------------------------------------------------------------------

OUT="$(bash "$LEDGER_SH" --help 2>&1)"
assert_exit "--help exits 0" "$?" "0"
assert_contains "--help names the script" "$OUT" "sweep-ledger.sh"

OUT="$(run status)"
assert_exit "a missing --topic exits 2" "$?" "2"
assert_contains "a missing --topic says what it takes" "$OUT" "--topic is required"

OUT="$(run --topic ../escape init)"
assert_exit "a slug with a path separator exits 2" "$?" "2"
assert_eq "a refused slug writes nothing outside .work" "$([[ -e "$REPO/../escape" ]] && echo yes || echo no)" "no"

OUT="$(run --topic t1 frobnicate)"
assert_exit "an unknown subcommand exits 2" "$?" "2"

# --- No ledger: a new sweep ------------------------------------------------------

OUT="$(run --topic t1 status)"
assert_exit "status with no ledger exits 0" "$?" "0"
assert_eq "status with no ledger reports a new sweep" "$OUT" \
  "no ledger here: this is a new sweep (no closures, no spend, no cache)"
assert_eq "status with no ledger creates nothing" "$([[ -e "$REPO/.work" ]] && echo yes || echo no)" "no"

OUT="$(run --topic t1 spend 1)"
assert_exit "spend with no ledger is refused, exit 3" "$?" "3"
assert_contains "spend with no ledger says it is a new sweep" "$OUT" "this is a new sweep"

# --- init ------------------------------------------------------------------------

OUT="$(run --topic t1 init)"
assert_exit "init exits 0" "$?" "0"
assert_contains "init reports the ledger it created" "$OUT" "created: $LEDGER"
assert_eq "init creates the ledger under the checkout's .work" "$([[ -f "$LEDGER" ]] && echo yes || echo no)" "yes"
assert_contains "init records a sweep id" "$(cat "$LEDGER")" "- sweep: t1-20"
assert_contains "init records the checkout the sweep started in" "$(cat "$LEDGER")" "| checkout: $REPO | started: 20"
SWEEP_LINE="$(grep '^- sweep: ' "$LEDGER")"
SWEEP_ID_T1="${SWEEP_LINE#- sweep: }"
SWEEP_ID_T1="${SWEEP_ID_T1%% | *}"

run --topic t1 spend 5 >/dev/null
OUT="$(run --topic t1 init)"
assert_exit "a second init exits 0" "$?" "0"
assert_contains "a second init reports the ledger already exists" "$OUT" "ledger exists"
assert_contains "a second init names the sweep it resumes" "$OUT" "a resume of sweep t1-20"
assert_eq "a second init keeps the sweep line" "$(grep '^- sweep: ' "$LEDGER")" "$SWEEP_LINE"
assert_contains "status names the sweep" "$(run --topic t1 status)" "sweep: t1-20"
assert_contains "a second init leaves the recorded spend alone" "$(run --topic t1 status)" "spend: 5 of"

# --- close -----------------------------------------------------------------------

OUT="$(run --topic t1 close docs/a.md --dispositions "leave-with-reason x1" --pointer-liveness live)"
assert_exit "a close missing fields exits 2" "$?" "2"
assert_contains "a close missing fields names the semantic-diff field" "$OUT" "--semantic-diff"
assert_contains "a close missing fields names the in-span field" "$OUT" "--in-span"
assert_contains "a close missing fields names the carve-out field" "$OUT" "--carve-out"
assert_contains "a refused close records nothing" "$(run --topic t1 status)" "closed files: 0"

OUT="$(run --topic t1 close docs/a.md "${CLOSE_FIELDS[@]}" --carve-out "")"
assert_exit "an empty field value exits 2" "$?" "2"

OUT="$(run --topic t1 close /abs/a.md "${CLOSE_FIELDS[@]}")"
assert_exit "an absolute path is refused" "$?" "2"

OUT="$(run --topic t1 close docs/a.md --dispositions "one | two" --pointer-liveness live --semantic-diff ok --in-span ok --carve-out ok)"
assert_exit "a value holding a pipe is refused" "$?" "2"

OUT="$(run --topic t1 close docs/a.md "${CLOSE_FIELDS[@]}")"
assert_exit "a complete close exits 0" "$?" "0"
assert_contains "a complete close reports the count" "$OUT" "1 closed"
assert_contains "the closure carries the running spend, not the file's" "$(cat "$LEDGER")" "| spent: 5"
assert_contains "the closure carries the file" "$(cat "$LEDGER")" "- closed: docs/a.md | dispositions: convert-to-pointer x1, leave-with-reason x1"

OUT="$(run --topic t1 close docs/a.md "${CLOSE_FIELDS[@]}")"
assert_exit "closing a closed file exits 3" "$?" "3"
assert_contains "closing a closed file names it" "$OUT" "already closed: docs/a.md"

OUT="$(run --topic t1 close ./docs/a.md "${CLOSE_FIELDS[@]}")"
assert_exit "a ./ spelling of a closed file is still a duplicate" "$?" "3"
assert_contains "the duplicate is not recorded" "$(run --topic t1 status)" "closed files: 1"

run --topic t1 close docs/b.md "${CLOSE_FIELDS[@]}" >/dev/null
OUT="$(run --topic t1 status)"
assert_contains "a second file counts" "$OUT" "closed files: 2"
assert_contains "status lists the first closed file for a resume to skip" "$OUT" "  docs/a.md"
assert_contains "status lists the second closed file for a resume to skip" "$OUT" "  docs/b.md"

# --- spend: accumulation across invocations (the resume case) --------------------

OUT="$(run --topic t1 spend 7)"
assert_exit "spend exits 0" "$?" "0"
assert_contains "spend adds to the running total" "$OUT" "12 so far"

run --topic t1 init >/dev/null
OUT="$(run --topic t1 spend 010)"
assert_contains "a leading zero is decimal, not octal" "$OUT" "22 so far"
assert_contains "status reads the summed spend back" "$(run --topic t1 status)" "spend: 22 of 200"

OUT="$(run --topic t1 spend many)"
assert_exit "a non-numeric spend exits 2" "$?" "2"
OUT="$(run --topic t1 spend -3)"
assert_exit "a negative spend exits 2" "$?" "2"
assert_contains "refused spend leaves the total alone" "$(run --topic t1 status)" "spend: 22 of 200"

# --- ceiling -----------------------------------------------------------------------

OUT="$(run --topic t1 status)"
assert_exit "status under the default ceiling exits 0" "$?" "0"
assert_contains "the default ceiling is attributed to the defaults" "$OUT" "corpus_fetch_ceiling (bundled default)"

printf '%s\n' '{"budgets": {"corpus_fetch_ceiling": 30}}' >"$CLAUDE_PROJECT_DIR/.claude/attribution.json"
OUT="$(run --topic t1 status)"
assert_exit "status under a configured ceiling exits 0" "$?" "0"
assert_contains "the configured ceiling applies" "$OUT" "spend: 22 of 30"
assert_contains "the configured ceiling names its layer" "$OUT" "(from $CLAUDE_PROJECT_DIR/.claude/attribution.json)"

run --topic t1 spend 7 >/dev/null
OUT="$(run --topic t1 status)"
assert_exit "one under the ceiling still exits 0" "$?" "0"

run --topic t1 spend 1 >/dev/null
OUT="$(run --topic t1 status)"
assert_exit "spend at the ceiling exits 1" "$?" "1"
assert_contains "spend at the ceiling says to stop" "$OUT" "at or over corpus_fetch_ceiling"

run --topic t1 spend 4 >/dev/null
OUT="$(run --topic t1 status)"
assert_exit "spend over the ceiling exits 1" "$?" "1"
assert_contains "spend over the ceiling is reported as spent" "$OUT" "spend: 34 of 30"

# A team layer's ceiling is refined by the overlay: the later layer wins.
printf '%s\n' '{"budgets": {"corpus_fetch_ceiling": 500}}' >"$CLAUDE_PROJECT_DIR/.claude/attribution.local.json"
OUT="$(run --topic t1 status)"
assert_exit "a later layer raising the ceiling clears the stop" "$?" "0"
assert_contains "the later layer supplies the ceiling" "$OUT" "spend: 34 of 500"
rm -f "$CLAUDE_PROJECT_DIR/.claude/attribution.json" "$CLAUDE_PROJECT_DIR/.claude/attribution.local.json"

# --- cache -------------------------------------------------------------------------

OUT="$(run --topic t1 cache-check "$URL")"
assert_exit "cache-check on a miss exits 0" "$?" "0"
assert_contains "a miss says so and says to fetch" "$OUT" "not cached: $URL"

OUT="$(run --topic t1 cache-add "$URL" "$SHA_A")"
assert_exit "cache-add exits 0" "$?" "0"
assert_contains "cache-add reports the fetch time" "$OUT" "cached: $URL at 20"

OUT="$(run --topic t1 cache-check "$URL")"
assert_exit "cache-check on a hit exits 0" "$?" "0"
assert_contains "a hit must be re-validated" "$OUT" "re-validate: $URL"
assert_contains "a hit carries the recorded hash" "$OUT" "sha256 $SHA_A"
assert_contains "a hit carries the fetch time" "$OUT" "was fetched at 20"
assert_not_contains "a hit is never offered as reusable" "$OUT" "reusable"

run --topic t1 cache-add "$URL" "$SHA_B" >/dev/null
assert_contains "the newest entry for a URL wins" "$(run --topic t1 cache-check "$URL")" "sha256 $SHA_B"
assert_contains "a re-added URL is one cache entry" "$(run --topic t1 status)" "cache entries: 1"

OUT="$(run --topic t1 cache-add "$URL" "not-a-hash")"
assert_exit "a malformed hash exits 2" "$?" "2"
OUT="$(run --topic t1 cache-add "$URL" "${SHA_A^^}")"
assert_exit "an uppercase hash exits 2" "$?" "2"
OUT="$(run --topic t1 cache-add "ftp://example.com/x" "$SHA_A")"
assert_exit "a non-http URL exits 2" "$?" "2"
OUT="$(run --topic t1 cache-add "https://example.com/a b" "$SHA_A")"
assert_exit "a URL with whitespace exits 2" "$?" "2"

# --- checkout-local ----------------------------------------------------------------

OUT="$(run_other --topic t1 status)"
assert_exit "status in another checkout exits 0" "$?" "0"
assert_eq "another checkout sees a new sweep, not this one's ledger" "$OUT" \
  "no ledger here: this is a new sweep (no closures, no spend, no cache)"
OUT="$(run_other --topic t1 cache-check "$URL")"
assert_exit "another checkout has no cache to look in" "$?" "3"

# A ledger file copied into another checkout is refused, not resumed as the same
# sweep: it names the checkout it started in.
mkdir -p "$OTHER_LEDGER_DIR"
cp "$LEDGER" "$OTHER_LEDGER_DIR/sweep-ledger.md"
BEFORE="$(cat "$OTHER_LEDGER_DIR/sweep-ledger.md")"
OUT="$(run_other --topic t1 status)"
assert_exit "status on a copied ledger exits 3" "$?" "3"
assert_contains "a copied ledger is called a new sweep" "$OUT" "this is a new sweep"
assert_contains "a copied ledger names its sweep and the checkout it started in" "$OUT" "($SWEEP_ID_T1, started in $REPO)"
OUT="$(run_other --topic t1 spend 1)"
assert_exit "spend on a copied ledger exits 3" "$?" "3"
OUT="$(run_other --topic t1 close docs/c.md "${CLOSE_FIELDS[@]}")"
assert_exit "close on a copied ledger exits 3" "$?" "3"
OUT="$(run_other --topic t1 cache-check "$URL")"
assert_exit "cache-check on a copied ledger exits 3, the cache is not reused" "$?" "3"
OUT="$(run_other --topic t1 init)"
assert_exit "init on a copied ledger exits 3, it is not adopted as a resume" "$?" "3"
assert_eq "a refused copied ledger is left unchanged" "$(cat "$OTHER_LEDGER_DIR/sweep-ledger.md")" "$BEFORE"

# A ledger with no sweep line (one not started by init) records no checkout and is
# refused the same way.
mkdir -p "$REPO/.work/hand"
printf '%s\n' '# notes kept by hand' >"$REPO/.work/hand/sweep-ledger.md"
OUT="$(run --topic hand status)"
assert_exit "a ledger with no sweep line exits 3" "$?" "3"
assert_contains "a ledger with no sweep line says so" "$OUT" "no sweep line"

# Nothing but the ignored .work/ tree is written: no tracked or untracked file
# appears in the checkout.
assert_eq "the ledger is the only thing written, under the ignored .work/" \
  "$(git -C "$REPO" status --porcelain --ignored)" "!! .work/"

# --- --show-config -----------------------------------------------------------------

OUT="$(run --show-config)"
assert_exit "--show-config exits 0" "$?" "0"
assert_contains "--show-config names the ledger path" "$OUT" "$REPO/.work/<topic-slug>/sweep-ledger.md"
assert_contains "--show-config prints the effective ceiling" "$OUT" "corpus_fetch_ceiling=200 (bundled default)"

printf '%s\n' '{"budgets": {"corpus_fetch_ceiling": 90}}' >"$CLAUDE_PROJECT_DIR/.claude/attribution.json"
OUT="$(run --topic t1 --show-config)"
assert_contains "--show-config attributes a configured ceiling to its layer" "$OUT" \
  "corpus_fetch_ceiling=90 (from $CLAUDE_PROJECT_DIR/.claude/attribution.json)"
assert_contains "--show-config names the ledger for the topic" "$OUT" "$LEDGER"
rm -f "$CLAUDE_PROJECT_DIR/.claude/attribution.json"

# The script alone, with no lib.sh beside it: the --show-config probe reads
# "detector unavailable", never an empty configuration.
ALONE="$TEST_TMPDIR/alone"
mkdir -p "$ALONE"
cp "$LEDGER_SH" "$ALONE/sweep-ledger.sh"
OUT_NL="$(bash "$ALONE/sweep-ledger.sh" --show-config 2>/dev/null)"
assert_exit "--show-config without lib.sh exits 0" "$?" "0"
assert_eq "--show-config without lib.sh prints the unavailable marker" "$OUT_NL" "detector unavailable"
ERR_NL="$(bash "$ALONE/sweep-ledger.sh" --topic t1 status 2>&1 >/dev/null)"
assert_exit "a real run without lib.sh exits 2" "$?" "2"
assert_contains "a real run without lib.sh explains itself on stderr" "$ERR_NL" "cannot read"

printf '\nPassed: %s  Failed: %s\n' "$((CASE_NUM - FAILED))" "$FAILED"
[[ "$FAILED" -eq 0 ]]

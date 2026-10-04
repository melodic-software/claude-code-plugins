#!/usr/bin/env bash
# Tests for scripts/selection-audit.sh: the strace read parser, the trace audit
# end to end against a stub selector and a stub pr-require-checks.yml fallback (a suite that
# reads a file the selector does not map to it is a gap, and so is an unmapped
# read by a suite the fallback does not run; a mapped, a fallback-run, an
# unchecked and an untracked read are not), the replay verdicts including
# selector errors, and usage errors. The trace case needs strace, as
# the audit does, so it fails rather than skips where strace is missing.
set -uo pipefail
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AUDIT="$SELF_DIR/selection-audit.sh"
# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

git_repo() {
  git init -q "$1" &&
    git -C "$1" config user.email t@example.invalid &&
    git -C "$1" config user.name t &&
    git -C "$1" config commit.gpgsign false
}

# ci_fallback <repo> <suite>...: a pr-require-checks.yml whose UNMAPPED branch calls
# run-plugin-tests.sh, and a run-plugin-tests.sh whose --list is the suites given.
ci_fallback() {
  local repo="$1"
  shift
  mkdir -p "$repo/.github/workflows" "$repo/scripts"
  printf '%s\n' "          if grep -q '^UNMAPPED:' \"\$err\"; then" \
    '            scripts/run-plugin-tests.sh --jobs 3' \
    '            scripts/run-outside-node-suites.sh' \
    '          else' '            exit 1' '          fi' >"$repo/.github/workflows/pr-require-checks.yml"
  # shellcheck disable=SC2016 # the stub's $1 is its own argument, written literally
  printf '%s\n' '#!/usr/bin/env bash' '[[ "$1" == --list ]] || exit 2' "printf '%s\\n' $*" \
    >"$repo/scripts/run-plugin-tests.sh"
}

# --- reads: the parser -------------------------------------------------------
repo="$TMP_ROOT/repo"
mkdir -p "$repo" "$TMP_ROOT/repo2"
real="$(cd "$repo" && pwd -P)"
cat >"$TMP_ROOT/log" <<EOF
100 openat(AT_FDCWD<$real>, "a/b.sh", O_RDONLY) = 3<$real/a/b.sh>
100 openat(5<$real/plugins>, "x.md", O_RDONLY) = 4<$real/plugins/x.md>
100 openat(AT_FDCWD<$real>, "/usr/lib/libc.so.6", O_RDONLY) = 3</usr/lib/libc.so.6>
100 openat(AT_FDCWD<$real>, ".git/HEAD", O_RDONLY) = 3<$real/.git/HEAD>
101 openat(AT_FDCWD<$real>, "d.txt", O_RDONLY <unfinished ...>
101 <... openat resumed>) = 3<$real/c.txt>
102 openat(AT_FDCWD<$real>, "../repo2/f", O_RDONLY) = 3<$TMP_ROOT/repo2/f>
100 openat(AT_FDCWD<$real>, "a/b.sh", O_RDONLY) = 3<$real/a/b.sh>
EOF
got="$(bash "$AUDIT" reads "$TMP_ROOT/log" "$repo" 2>&1)"
want=$'a/b.sh\nc.txt\nplugins/x.md'
if [[ "$got" == "$want" ]]; then
  ok "reads: repo-relative opens, deduplicated; outside paths, .git and unfinished calls dropped"
else
  fail "reads: got [$got] want [$want]"
fi

# --- trace: end to end against a stub selector ---------------------------------
if ! strace -qq -o /dev/null -e trace=openat true >/dev/null 2>&1; then
  fail "strace is missing or cannot trace here; the trace audit cannot be exercised"
else
  t="$TMP_ROOT/trace-repo"
  git_repo "$t"
  mkdir -p "$t/suites" "$t/data"
  echo hidden >"$t/data/hidden.txt"
  echo named >"$t/data/named.txt"
  echo odd >"$t/data/unmapped.txt"
  echo broken >"$t/data/broken.txt"
  printf '%s\n' '#!/usr/bin/env bash' 'cat data/hidden.txt data/named.txt data/unmapped.txt data/untracked.txt data/broken.txt' >"$t/suites/reader.test.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'true' >"$t/suites/quiet.test.sh"
  # Reads the unmapped file too, but the fallback corpus does not run it.
  printf '%s\n' '#!/usr/bin/env bash' 'cat data/unmapped.txt' >"$t/suites/zz-outside.test.sh"
  # An eval fixture is data no lane runs, so the corpus leaves it untraced.
  mkdir -p "$t/plugins/x/evals/fixtures"
  printf '%s\n' '#!/usr/bin/env bash' 'cat data/hidden.txt' >"$t/plugins/x/evals/fixtures/fake.test.sh"
  ci_fallback "$t" suites/reader.test.sh suites/quiet.test.sh
  git -C "$t" add -A && git -C "$t" commit -qm base
  echo untracked >"$t/data/untracked.txt"
  cat >"$TMP_ROOT/stub-selector.sh" <<'EOF'
#!/usr/bin/env bash
# Stub of affected-tests.sh: one file after `--`, a fixed answer per file.
f="${!#}"
case "$f" in
data/named.txt) echo suites/reader.test.sh ;;
data/unmapped.txt) echo "UNMAPPED: 1 changed file(s) map to no test suite:" >&2 ;;
data/broken.txt) exit 3 ;;
*) echo "no-suite: $f (recorded in the stub)" >&2 ;;
esac
EOF
  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" GITHUB_STEP_SUMMARY="$TMP_ROOT/summary.md" \
    bash "$AUDIT" trace --jobs 2 --out "$TMP_ROOT/out") >"$TMP_ROOT/trace.log" 2>&1 || rc=$?
  gaps="$(cat "$TMP_ROOT/out/gaps.tsv" 2>/dev/null)"
  want=$'suites/reader.test.sh\tdata/hidden.txt\tno-suite: data/hidden.txt (recorded in the stub)\nsuites/zz-outside.test.sh\tdata/unmapped.txt\tunmapped: the fallback corpus does not run this suite'
  if [[ "$rc" -eq 1 ]]; then
    ok "trace: exits 1 on a gap"
  else
    fail "trace: exit $rc, want 1: $(cat "$TMP_ROOT/trace.log")"
  fi
  if [[ "$gaps" == "$want" ]]; then
    ok "trace: gaps are the unmapped-to-suite read and the unmapped read of a suite the fallback does not run (mapped, fallback-run, unchecked, untracked and self are not)"
  else
    fail "trace: gaps.tsv [$gaps] want [$want]"
  fi
  if grep -q '2 gap(s) in 2 suite(s)' "$TMP_ROOT/summary.md" 2>/dev/null; then
    ok "trace: the report reaches the step summary"
  else
    fail "trace: no gap count in the step summary"
  fi
  if grep -qxF $'data/broken.txt\tnot checked: selector exit 3' "$TMP_ROOT/out/verdicts.tsv" 2>/dev/null &&
    grep -q '; 1 not checked against the selector' "$TMP_ROOT/out/report.md"; then
    ok "trace: a selector error is a 'not checked' verdict with its reason, counted apart from gaps"
  else
    fail "trace: verdicts.tsv [$(cat "$TMP_ROOT/out/verdicts.tsv" 2>/dev/null)]"
  fi
  if [[ "$(cut -f1,2 "$TMP_ROOT/out/suites.tsv")" == $'suites/quiet.test.sh\t0\nsuites/reader.test.sh\t0\nsuites/zz-outside.test.sh\t0' ]]; then
    ok "trace: suites.tsv records every traced suite and its exit, and no eval fixture"
  else
    fail "trace: suites.tsv [$(cat "$TMP_ROOT/out/suites.tsv")]"
  fi

  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" \
    bash "$AUDIT" trace --shard 0/3 --out "$TMP_ROOT/out-shard") >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && "$(cut -f1 "$TMP_ROOT/out-shard/suites.tsv")" == suites/quiet.test.sh ]]; then
    ok "trace: --shard 0/3 keeps the first of three suites and finds no gap in it"
  else
    fail "trace: --shard 0/3 exit $rc, suites [$(cat "$TMP_ROOT/out-shard/suites.tsv" 2>/dev/null)]"
  fi

  rm "$t/.github/workflows/pr-require-checks.yml"
  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" \
    bash "$AUDIT" trace --out "$TMP_ROOT/out-noci") >/dev/null 2>&1 || rc=$?
  git -C "$t" checkout -q -- .github/workflows/pr-require-checks.yml
  if [[ "$rc" -eq 2 ]]; then
    ok "trace: exits 2 when pr-require-checks.yml's unmapped fallback cannot be read"
  else
    fail "trace: no pr-require-checks.yml fallback exit $rc, want 2"
  fi

  mv "$t/.github/workflows/pr-require-checks.yml" "$t/.github/workflows/ci.yml"
  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" \
    bash "$AUDIT" trace --shard 0/3 --out "$TMP_ROOT/out-oldci") >/dev/null 2>&1 || rc=$?
  mv "$t/.github/workflows/ci.yml" "$t/.github/workflows/pr-require-checks.yml"
  if [[ "$rc" -eq 0 && "$(cut -f1 "$TMP_ROOT/out-oldci/suites.tsv")" == suites/quiet.test.sh ]]; then
    ok "trace: a tree from before the rename reads the fallback from ci.yml"
  else
    fail "trace: ci.yml-named fallback exit $rc, want 0"
  fi
fi

# --- replay: verdict per commit ------------------------------------------------
r="$TMP_ROOT/replay-repo"
git_repo "$r"
mkdir -p "$r/scripts" "$r/suites"
cat >"$r/scripts/affected-tests.sh" <<'EOF'
#!/usr/bin/env bash
# Stub selector: `covered` selects the suite, `odd` is unmapped, anything else selects nothing.
for f in "$@"; do
  case "$f" in
  covered) echo suites/x.test.sh ;;
  odd) echo "UNMAPPED: 1 changed file(s) map to no test suite:" >&2 ;;
  boom) exit 5 ;;
  esac
done
exit 0
EOF
echo 'true' >"$r/suites/x.test.sh"
echo 'true' >"$r/suites/y.test.sh"
ci_fallback "$r" suites/x.test.sh
git -C "$r" add -A && git -C "$r" commit -qm base
good="$(git -C "$r" rev-parse HEAD)"
declare -A sha=()
for f in other covered odd boom; do
  echo "$f" >"$r/$f" && git -C "$r" add -A && git -C "$r" commit -qm "change $f"
  sha[$f]="$(git -C "$r" rev-parse HEAD)"
done

rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/x.test.sh --good "$good" --bad "${sha[other]}" --out "$TMP_ROOT/rp1" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"**Selection miss**"* && "$out" == *"| not selected | change other |"* ]]; then
  ok "replay: no commit selecting the suite is a selection miss, exit 1"
else
  fail "replay miss: exit $rc: $out"
fi

rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/x.test.sh --good "$good" --bad "${sha[odd]}" --out "$TMP_ROOT/rp2" 2>&1)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"Selected by 2 of 3 commit(s)"* && "$out" == *"| selected | change covered |"* &&
  "$out" == *"| selected (unmapped file: the full-corpus fallback runs it) | change odd |"* ]]; then
  ok "replay: a selecting commit and an unmapped fallback that runs the suite both count as selected, exit 0"
else
  fail "replay selected: exit $rc: $out"
fi

rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/y.test.sh --good "$good" --bad "${sha[odd]}" --out "$TMP_ROOT/rp3" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"**Selection miss**"* &&
  "$out" == *"| not selected (unmapped file: the full-corpus fallback does not run it) | change odd |"* ]]; then
  ok "replay: an unmapped fallback that does not run the suite is no selection, exit 1"
else
  fail "replay unmapped outside the fallback: exit $rc: $out"
fi

rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/y.test.sh --good "${sha[odd]}" --bad "${sha[boom]}" --out "$TMP_ROOT/rp4" 2>&1)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"**Inconclusive**: 1 of 1 commit(s)"* && "$out" != *"Selection miss"* &&
  "$out" == *"| error: selector exit 5 | change boom |"* ]]; then
  ok "replay: a selector error is neither a miss nor a selection; the range is inconclusive, exit 0"
else
  fail "replay error: exit $rc: $out"
fi
if [[ -z "$(git -C "$r" worktree list | sed 1d)" ]]; then
  ok "replay: removes its worktree"
else
  fail "replay left a worktree: $(git -C "$r" worktree list)"
fi

# A tree whose pr-require-checks.yml plans its lanes with scripts/plan-test-lanes.sh: the
# selector itself adds an unmapped file's language corpus (--unmapped-corpus,
# exit 4), so a suite in that corpus is selected and one outside it is not.
# shellcheck disable=SC2016 # workflow text, written literally
printf '%s\n' '          scripts/plan-test-lanes.sh --base "$DIFF_BASE"' >"$r/.github/workflows/pr-require-checks.yml"
cat >"$r/scripts/affected-tests.sh" <<'EOF'
#!/usr/bin/env bash
# Stub selector: `odd2` is unmapped, and --unmapped-corpus adds its corpus, suites/y.test.sh.
[[ "$1" == --unmapped-corpus ]] || exit 9
for f in "$@"; do
  case "$f" in
  odd2)
    echo "UNMAPPED: 1 changed file(s) map to no test suite:" >&2
    echo suites/y.test.sh
    exit 4
    ;;
  esac
done
exit 0
EOF
git -C "$r" add -A && git -C "$r" commit -qm "plan the lanes"
planned_base="$(git -C "$r" rev-parse HEAD)"
echo odd2 >"$r/odd2" && git -C "$r" add -A && git -C "$r" commit -qm "change odd2"
rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/y.test.sh --good "$planned_base" --bad HEAD --out "$TMP_ROOT/rp5" 2>&1)" || rc=$?
if [[ "$rc" -eq 0 && "$out" == *"| selected | change odd2 |"* ]]; then
  ok "replay: in a planned tree, the unmapped file's language corpus selects its suites"
else
  fail "replay planned corpus: exit $rc: $out"
fi
rc=0
out="$(cd "$r" && bash "$AUDIT" replay --suite suites/x.test.sh --good "$planned_base" --bad HEAD --out "$TMP_ROOT/rp6" 2>&1)" || rc=$?
if [[ "$rc" -eq 1 && "$out" == *"| not selected (unmapped file: its language corpus does not run it) | change odd2 |"* ]]; then
  ok "replay: in a planned tree, a suite outside the unmapped file's corpus is not selected"
else
  fail "replay planned outside the corpus: exit $rc: $out"
fi

# --- usage ---------------------------------------------------------------------
for args in "trace --shard 2/2" "bogus" "replay --suite x"; do
  rc=0
  # shellcheck disable=SC2086 # each case is a word list on purpose
  (cd "$r" && bash "$AUDIT" $args) >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 2 ]]; then
    ok "usage: '$args' exits 2"
  else
    fail "usage: '$args' exit $rc, want 2"
  fi
done

test_harness::report

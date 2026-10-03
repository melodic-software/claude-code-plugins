#!/usr/bin/env bash
# Tests for scripts/selection-audit.sh: the strace read parser, the trace audit
# end to end against a stub selector (a suite that reads a file the selector
# does not map to it is a gap; a mapped, an unmapped and an untracked read are
# not), the replay verdicts, and usage errors. The trace case needs strace, as
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
  printf '%s\n' '#!/usr/bin/env bash' 'cat data/hidden.txt data/named.txt data/unmapped.txt data/untracked.txt' >"$t/suites/reader.test.sh"
  printf '%s\n' '#!/usr/bin/env bash' 'true' >"$t/suites/quiet.test.sh"
  git -C "$t" add -A && git -C "$t" commit -qm base
  echo untracked >"$t/data/untracked.txt"
  cat >"$TMP_ROOT/stub-selector.sh" <<'EOF'
#!/usr/bin/env bash
# Stub of affected-tests.sh: one file after `--`, a fixed answer per file.
f="${!#}"
case "$f" in
data/named.txt) echo suites/reader.test.sh ;;
data/unmapped.txt) echo "UNMAPPED: 1 changed file(s) map to no test suite:" >&2 ;;
*) echo "no-suite: $f (recorded in the stub)" >&2 ;;
esac
EOF
  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" GITHUB_STEP_SUMMARY="$TMP_ROOT/summary.md" \
    bash "$AUDIT" trace --jobs 2 --out "$TMP_ROOT/out") >"$TMP_ROOT/trace.log" 2>&1 || rc=$?
  gaps="$(cat "$TMP_ROOT/out/gaps.tsv" 2>/dev/null)"
  want=$'suites/reader.test.sh\tdata/hidden.txt\tno-suite: data/hidden.txt (recorded in the stub)'
  if [[ "$rc" -eq 1 ]]; then
    ok "trace: exits 1 on a gap"
  else
    fail "trace: exit $rc, want 1: $(cat "$TMP_ROOT/trace.log")"
  fi
  if [[ "$gaps" == "$want" ]]; then
    ok "trace: only the read the selector does not map is a gap (mapped, unmapped, untracked and self are not)"
  else
    fail "trace: gaps.tsv [$gaps] want [$want]"
  fi
  if grep -q '1 gap(s) in 1 suite(s)' "$TMP_ROOT/summary.md" 2>/dev/null; then
    ok "trace: the report reaches the step summary"
  else
    fail "trace: no gap count in the step summary"
  fi
  if [[ "$(cut -f1,2 "$TMP_ROOT/out/suites.tsv")" == $'suites/quiet.test.sh\t0\nsuites/reader.test.sh\t0' ]]; then
    ok "trace: suites.tsv records every traced suite and its exit"
  else
    fail "trace: suites.tsv [$(cat "$TMP_ROOT/out/suites.tsv")]"
  fi

  rc=0
  (cd "$t" && SELECTION_AUDIT_SELECTOR="$TMP_ROOT/stub-selector.sh" \
    bash "$AUDIT" trace --shard 0/2 --out "$TMP_ROOT/out-shard") >/dev/null 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && "$(cut -f1 "$TMP_ROOT/out-shard/suites.tsv")" == suites/quiet.test.sh ]]; then
    ok "trace: --shard 0/2 keeps the first of two suites and finds no gap in it"
  else
    fail "trace: --shard 0/2 exit $rc, suites [$(cat "$TMP_ROOT/out-shard/suites.tsv" 2>/dev/null)]"
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
  esac
done
exit 0
EOF
echo 'true' >"$r/suites/x.test.sh"
git -C "$r" add -A && git -C "$r" commit -qm base
good="$(git -C "$r" rev-parse HEAD)"
declare -A sha=()
for f in other covered odd; do
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
  "$out" == *"| selected (unmapped file: full-corpus fallback) | change odd |"* ]]; then
  ok "replay: a selecting commit and an unmapped fallback both count as selected, exit 0"
else
  fail "replay selected: exit $rc: $out"
fi
if [[ -z "$(git -C "$r" worktree list | sed 1d)" ]]; then
  ok "replay: removes its worktree"
else
  fail "replay left a worktree: $(git -C "$r" worktree list)"
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

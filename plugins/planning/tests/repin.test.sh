#!/usr/bin/env bash
# repin.sh rewrites exactly one digest pin of a copy of the test file: one sha literal and
# one justification comment change, every other line stays byte-identical; an unknown or
# ambiguous label is refused and a matching digest is a no-op. It writes only when stdin and
# stdout are both terminals and the person answers y: any other run refuses and writes
# nothing. The copy is a stand-in test with the real call shape (label, then the sha256
# literal alone on the last line) that prints the same `want X, got Y` failure, so the real
# pins are never touched. `script` (util-linux) gives the attended cases a pty; hosts
# without it skip them.
#
# test-scope: plugins/planning/tests/repin.sh
set -uo pipefail
# The stand-in lives in a temporary git repository. Run from a git hook, inherited
# repository-local variables (GIT_INDEX_FILE among them) would point its git commands at the
# caller's repository instead. CALLER_INDEX keeps the caller's index path for the check below.
CALLER_INDEX="${GIT_INDEX_FILE:-}"
# shellcheck disable=SC2046 # one word per variable name is intended
unset $(git rev-parse --local-env-vars)

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPIN="$HERE/repin.sh"

PASS=0
FAIL=0
fail() {
  echo "FAIL: $*" >&2
  FAIL=$((FAIL + 1))
}
ok() {
  echo "ok: $*"
  PASS=$((PASS + 1))
}

WORK="$(mktemp -d "${TMPDIR:-/tmp}/repin-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}

CALLER_INDEX_SHA=""
[[ -f "$CALLER_INDEX" ]] && CALLER_INDEX_SHA="$(sha_of "$CALLER_INDEX")"

printf 'alpha\n' >"$WORK/alpha.txt"
printf 'beta\n' >"$WORK/beta.txt"
ALPHA="$(sha_of "$WORK/alpha.txt")"
BETA="$(sha_of "$WORK/beta.txt")"
STALE="$(printf '%064d' 7)"

# A stand-in for interview-defenses.test.sh: pin_file <label> <file> <sha256>.
# Both pins start out matching; each test makes one stale.
make_fixture() {
  local alpha_sha="$1" beta_sha="$2" dest="$3"
  cat >"$dest" <<EOF
#!/usr/bin/env bash
set -uo pipefail
FAILS=0
sha_of() { sha256sum <"\$1" | cut -d' ' -f1; }
pin_file() {
  local label="\$1" file="\$2" want="\$3" got
  got="\$(sha_of "\$file")"
  if [[ "\$got" == "\$want" ]]; then echo "ok: \$label"; else echo "FAIL: \$label — changed (want \$want, got \$got). Re-read." >&2; FAILS=1; fi
}
# Existing justification for the alpha pin.
pin_file "alpha file is unchanged (\\\`lock\\\` row)" \\
  "$WORK/alpha.txt" \\
  "$alpha_sha"
pin_file "beta file is unchanged" \\
  "$WORK/beta.txt" \\
  "$beta_sha"
exit \$FAILS
EOF
}

# Unattended: no terminal on stdin or stdout, as a lane runs it.
run_repin() { bash "$REPIN" "$@" </dev/null 2>&1; }

# The stand-in lives in tests/ of a git repo with one uncommitted edit, so the attended
# run's `git diff --stat` has a change to show and a pager to start if it is allowed one.
PLUGIN="$WORK/plugin"
mkdir -p "$PLUGIN/tests"
printf 'guarded\n' >"$PLUGIN/guarded.md"
if ! { git -C "$PLUGIN" init -q && git -C "$PLUGIN" add guarded.md &&
  git -C "$PLUGIN" -c user.name=t -c user.email=t@example.invalid commit -qm init; }; then
  echo "FAIL: cannot set up the git fixture" >&2
  exit 1
fi
printf 'weakened\n' >"$PLUGIN/guarded.md"

# --- an unattended run refuses and writes nothing ----------------------------------------
t="$PLUGIN/tests/stale.test.sh"
make_fixture "$STALE" "$BETA" "$t"
cp "$t" "$WORK/stale.before"
out="$(run_repin --test-file "$t" 'alpha file' 'An injected justification.')"
rc=$?
if [[ $rc -eq 5 ]]; then ok "no terminal: exit 5"; else fail "no terminal: expected exit 5, got $rc: $out"; fi
if [[ "$out" == *"terminal"* ]]; then ok "no terminal: says why"; else fail "no terminal: no reason given: $out"; fi
if cmp -s "$WORK/stale.before" "$t"; then ok "no terminal: pin unchanged"; else fail "file changed on an unattended run"; fi

# Attended: stdin and stdout on a pty, <answer> typed at the prompt. TTY_SUFFIX, already
# shell-quoted, is appended to the command line (a redirect). GIT_PAGER reads a line from
# the terminal, as less does on a key: if repin.sh let git start a pager, it would eat the
# answer.
HAVE_PTY=0
if command -v script >/dev/null 2>&1 && script -qec true /dev/null </dev/null >/dev/null 2>&1; then HAVE_PTY=1; fi
run_tty() {
  local answer="$1" cmd
  shift
  cmd="$(printf '%q ' bash "$REPIN" "$@")"
  printf '%s\n' "$answer" | GIT_PAGER='read -r _ </dev/tty; cat' SHELL="$(command -v bash)" timeout 30 script -qec "$cmd${TTY_SUFFIX:-}" /dev/null 2>&1
}

if [[ $HAVE_PTY -eq 1 ]]; then
  # --- attended and confirmed: one pin changes, every other line is byte-identical -------
  make_fixture "$STALE" "$BETA" "$t"
  out="$(run_tty y --test-file "$t" 'alpha file' 'Alpha text edited; the defense still holds.')"
  rc=$?
  if [[ $rc -eq 0 ]]; then ok "stale pin re-pinned: exit 0"; else fail "stale pin: expected exit 0, got $rc: $out"; fi
  if [[ "$out" == *PASS* ]]; then ok "prints PASS"; else fail "no PASS in output: $out"; fi
  if [[ "$out" == *"$STALE"* && "$out" == *"$ALPHA"* ]]; then ok "shows old and new digest before asking"; else fail "old/new digest not shown: $out"; fi
  if [[ "$out" == *"guarded.md"* ]]; then ok "shows the git diff stat before asking"; else fail "diff stat not shown: $out"; fi
  changes="$(diff "$WORK/stale.before" "$t" | grep -c '^[<>]')"
  if [[ "$changes" -eq 3 ]]; then ok "exactly three lines differ: old sha, new sha, justification"; else fail "expected 3 differing lines, got $changes"; fi
  if grep -qx "  \"$ALPHA\"" "$t"; then ok "alpha sha rewritten"; else fail "alpha sha not rewritten"; fi
  if grep -qx "  \"$BETA\"" "$t"; then ok "beta pin left as it was"; else fail "beta pin changed"; fi
  if grep -qx '# Alpha text edited; the defense still holds.' "$t"; then ok "justification inserted"; else fail "justification missing"; fi
  before_call="$(grep -n '^pin_file "alpha' "$t" | cut -d: -f1)"
  if [[ "$(sed -n "$((before_call - 1))p" "$t")" == '# Alpha text edited; the defense still holds.' ]]; then ok "justification sits beside the pin"; else fail "justification not above the pin call"; fi

  # --- a backslash in the justification is kept literally --------------------------------
  make_fixture "$STALE" "$BETA" "$t"
  run_tty y --test-file "$t" 'alpha file' 'Kept a\nliteral \\ backslash.' >/dev/null
  if grep -qxF '# Kept a\nliteral \\ backslash.' "$t"; then ok "backslashes in the justification stay literal"; else fail "justification was mangled"; fi

  # --- attended but declined (n, or Enter for the default) writes nothing ----------------
  for answer in n ''; do
    make_fixture "$STALE" "$BETA" "$t"
    out="$(run_tty "$answer" --test-file "$t" 'alpha file' 'unused')"
    rc=$?
    if [[ $rc -eq 6 ]]; then ok "answer '$answer': exit 6"; else fail "answer '$answer': expected exit 6, got $rc: $out"; fi
    if cmp -s "$WORK/stale.before" "$t"; then ok "answer '$answer': pin unchanged"; else fail "file changed after answer '$answer'"; fi
  done

  # --- a terminal on only one of stdin and stdout refuses --------------------------------
  for half in "stdout to a file:>$(printf '%q' "$WORK/redir.out")" "stdin from /dev/null:</dev/null"; do
    make_fixture "$STALE" "$BETA" "$t"
    out="$(TTY_SUFFIX=" ${half#*:}" run_tty y --test-file "$t" 'alpha file' 'unused')"
    rc=$?
    if [[ $rc -eq 5 ]]; then ok "${half%%:*}: exit 5"; else fail "${half%%:*}: expected exit 5, got $rc: $out"; fi
    if cmp -s "$WORK/stale.before" "$t"; then ok "${half%%:*}: pin unchanged"; else fail "file changed with ${half%%:*}"; fi
  done
else
  echo "skip - attended re-pin cases (no util-linux script)"
fi

# --- matching digest is a no-op ----------------------------------------------------------
make_fixture "$ALPHA" "$BETA" "$t"
cp "$t" "$WORK/ok.before"
out="$(run_repin --test-file "$t" 'alpha file' 'unused')"
rc=$?
if [[ $rc -eq 4 ]]; then ok "matching digest: exit 4"; else fail "matching digest: expected exit 4, got $rc: $out"; fi
if cmp -s "$WORK/ok.before" "$t"; then ok "matching digest changed nothing"; else fail "file changed on a no-op"; fi

# --- unknown and ambiguous labels are refused --------------------------------------------
make_fixture "$STALE" "$STALE" "$t"
cp "$t" "$WORK/refuse.before"
out="$(run_repin --test-file "$t" 'gamma' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "unknown label: exit 3"; else fail "unknown label: expected exit 3, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'is unchanged' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "ambiguous label: exit 3"; else fail "ambiguous label: expected exit 3, got $rc: $out"; fi
if cmp -s "$WORK/refuse.before" "$t"; then ok "refused labels changed nothing"; else fail "file changed on a refusal"; fi

# --- usage -------------------------------------------------------------------------------
out="$(run_repin --test-file "$t" 'alpha file')"
rc=$?
if [[ $rc -eq 2 ]]; then ok "missing justification: exit 2"; else fail "missing justification: expected exit 2, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'alpha file' $'two\nlines')"
rc=$?
if [[ $rc -eq 2 ]]; then ok "multi-line justification: exit 2"; else fail "multi-line justification: expected exit 2, got $rc: $out"; fi

# --- the caller's index is untouched -----------------------------------------------------
if [[ -n "$CALLER_INDEX_SHA" ]]; then
  if [[ "$(sha_of "$CALLER_INDEX")" == "$CALLER_INDEX_SHA" ]]; then ok "caller's GIT_INDEX_FILE untouched"; else fail "the fixture wrote to the caller's index $CALLER_INDEX"; fi
fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]

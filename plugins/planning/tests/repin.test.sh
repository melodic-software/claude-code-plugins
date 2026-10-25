#!/usr/bin/env bash
# repin.sh rewrites exactly one digest pin of a copy of the test file: one sha literal and
# one justification comment change, every other line stays byte-identical; an unknown or
# ambiguous label is refused and a matching digest is a no-op. It runs with no terminal, as a
# lane runs it. The copy is a stand-in test with the real call shape (label, then the sha256
# literal alone on the last line) that prints the same `want X, got Y` failure, so the real
# pins are never touched.
#
# test-scope: plugins/planning/tests/repin.sh
set -uo pipefail
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

# No terminal on stdin or stdout, as a lane runs it.
run_repin() { bash "$REPIN" "$@" </dev/null 2>&1; }

# --- a stale pin is re-pinned: one pin changes, every other line is byte-identical -------
t="$WORK/stale.test.sh"
make_fixture "$STALE" "$BETA" "$t"
cp "$t" "$WORK/stale.before"
out="$(run_repin --test-file "$t" 'alpha file' 'Alpha text edited; the defense still holds.')"
rc=$?
if [[ $rc -eq 0 ]]; then ok "stale pin re-pinned: exit 0"; else fail "stale pin: expected exit 0, got $rc: $out"; fi
if [[ "$out" == *PASS* ]]; then ok "prints PASS"; else fail "no PASS in output: $out"; fi
if [[ "$out" == *"alpha file is unchanged (\`lock\` row): $STALE -> $ALPHA"* ]]; then ok "prints label: old -> new for the commit"; else fail "label and old -> new not printed: $out"; fi
changes="$(diff "$WORK/stale.before" "$t" | grep -c '^[<>]')"
if [[ "$changes" -eq 3 ]]; then ok "exactly three lines differ: old sha, new sha, justification"; else fail "expected 3 differing lines, got $changes"; fi
if grep -qx "  \"$ALPHA\"" "$t"; then ok "alpha sha rewritten"; else fail "alpha sha not rewritten"; fi
if grep -qx "  \"$BETA\"" "$t"; then ok "beta pin left as it was"; else fail "beta pin changed"; fi
if grep -qx '# Alpha text edited; the defense still holds.' "$t"; then ok "justification inserted"; else fail "justification missing"; fi
before_call="$(grep -n '^pin_file "alpha' "$t" | cut -d: -f1)"
if [[ "$(sed -n "$((before_call - 1))p" "$t")" == '# Alpha text edited; the defense still holds.' ]]; then ok "justification sits beside the pin"; else fail "justification not above the pin call"; fi

# --- a backslash in the justification is kept literally ----------------------------------
make_fixture "$STALE" "$BETA" "$t"
run_repin --test-file "$t" 'alpha file' 'Kept a\nliteral \\ backslash.' >/dev/null
if grep -qxF '# Kept a\nliteral \\ backslash.' "$t"; then ok "backslashes in the justification stay literal"; else fail "justification was mangled"; fi

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

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]

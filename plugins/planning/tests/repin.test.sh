#!/usr/bin/env bash
# test-scope: plugins/planning/tests/repin.sh
# test-scope: plugins/planning/scripts/repin-digests.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPIN="$HERE/repin.sh"

# shellcheck source=../lib/test-ok-fail.sh
source "$HERE/../lib/test-ok-fail.sh"

WORK="$(mktemp -d "${TMPDIR:-/tmp}/repin-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}

printf 'alpha\n' >"$WORK/alpha.txt"
printf 'beta\n' >"$WORK/beta.txt"
printf 'delta\n' >"$WORK/delta.txt"
printf 'omega\n' >"$WORK/omega.txt"
ALPHA="$(sha_of "$WORK/alpha.txt")"
BETA="$(sha_of "$WORK/beta.txt")"
DELTA="$(sha_of "$WORK/delta.txt")"
OMEGA="$(sha_of "$WORK/omega.txt")"
STALE="$(printf '%064d' 7)"

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
pin_file "alpha file is unchanged (\\\`lock\\\` row, \\\\\\"quoted\\\\\\")" \\
  "$WORK/alpha.txt" \\
  "$alpha_sha"
pin_file "beta file is unchanged" \\
  "$WORK/beta.txt" \\
  "$beta_sha"
exit \$FAILS
EOF
}

make_quad_fixture() {
  local alpha_sha="$1" beta_sha="$2" delta_sha="$3" omega_sha="$4" dest="$5"
  make_fixture "$alpha_sha" "$beta_sha" "$dest.base"
  sed '$d' "$dest.base" >"$dest"
  rm -f "$dest.base"
  cat >>"$dest" <<EOF
pin_file "delta file is unchanged" \\
  "$WORK/delta.txt" \\
  "$delta_sha"
pin_file "omega file is unchanged" \\
  "$WORK/omega.txt" \\
  "$omega_sha"
exit \$FAILS
EOF
}

run_repin() { bash "$REPIN" "$@" </dev/null 2>&1; }

t="$WORK/stale.test.sh"
make_fixture "$STALE" "$BETA" "$t"
cp "$t" "$WORK/stale.before"
out="$(run_repin --test-file "$t" 'alpha file' 'Alpha text edited; the defense still holds.')"
rc=$?
if [[ $rc -eq 0 ]]; then ok "stale pin re-pinned: exit 0"; else fail "stale pin: expected exit 0, got $rc: $out"; fi
if [[ "$out" == *PASS* ]]; then ok "prints PASS"; else fail "no PASS in output: $out"; fi
if [[ "$out" == *"alpha file is unchanged (\`lock\` row, \"quoted\"): $STALE -> $ALPHA"* ]]; then ok "prints label: old -> new for the commit"; else fail "label and old -> new not printed: $out"; fi
changes="$(diff "$WORK/stale.before" "$t" | grep -c '^[<>]')"
if [[ "$changes" -eq 3 ]]; then ok "exactly three lines differ: old sha, new sha, justification"; else fail "expected 3 differing lines, got $changes"; fi
if grep -qx "  \"$ALPHA\"" "$t"; then ok "alpha sha rewritten"; else fail "alpha sha not rewritten"; fi
if grep -qx "  \"$BETA\"" "$t"; then ok "beta pin left as it was"; else fail "beta pin changed"; fi
if grep -qx '# Alpha text edited; the defense still holds.' "$t"; then ok "justification inserted"; else fail "justification missing"; fi
before_call="$(grep -n '^pin_file "alpha' "$t" | cut -d: -f1)"
if [[ "$(sed -n "$((before_call - 1))p" "$t")" == '# Alpha text edited; the defense still holds.' ]]; then ok "justification sits beside the pin"; else fail "justification not above the pin call"; fi

make_fixture "$STALE" "$BETA" "$t"
run_repin --test-file "$t" 'alpha file' 'Kept a\nliteral \\ backslash.' >/dev/null
if grep -qxF '# Kept a\nliteral \\ backslash.' "$t"; then ok "backslashes in the justification stay literal"; else fail "justification was mangled"; fi

make_fixture "$ALPHA" "$BETA" "$t"
cp "$t" "$WORK/ok.before"
out="$(run_repin --test-file "$t" 'alpha file' 'unused')"
rc=$?
if [[ $rc -eq 4 ]]; then ok "matching digest: exit 4"; else fail "matching digest: expected exit 4, got $rc: $out"; fi
if cmp -s "$WORK/ok.before" "$t"; then ok "matching digest changed nothing"; else fail "file changed on a no-op"; fi

make_fixture "$STALE" "$STALE" "$t"
cp "$t" "$WORK/refuse.before"
out="$(run_repin --test-file "$t" 'gamma' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "unknown label: exit 3"; else fail "unknown label: expected exit 3, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'is unchanged' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "ambiguous label: exit 3"; else fail "ambiguous label: expected exit 3, got $rc: $out"; fi
if cmp -s "$WORK/refuse.before" "$t"; then ok "refused labels changed nothing"; else fail "file changed on a refusal"; fi

out="$(run_repin --test-file "$t" 'alpha file')"
rc=$?
if [[ $rc -eq 2 ]]; then ok "missing justification: exit 2"; else fail "missing justification: expected exit 2, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'alpha file' $'two\nlines')"
rc=$?
if [[ $rc -eq 2 ]]; then ok "multi-line justification: exit 2"; else fail "multi-line justification: expected exit 2, got $rc: $out"; fi

t="$WORK/several.test.sh"
make_quad_fixture "$STALE" "$STALE" "$STALE" "$OMEGA" "$t"
cp "$t" "$WORK/several.before"
out="$(run_repin --test-file "$t" 'alpha file' 'beta file' 'delta file' 'Three texts edited; the defenses still hold.')"
rc=$?
if [[ $rc -eq 0 ]]; then ok "three labels re-pinned: exit 0"; else fail "three labels: expected exit 0, got $rc: $out"; fi
if [[ "$(printf '%s\n' "$out" | grep -c '^PASS$')" -eq 1 ]]; then ok "three labels: prints PASS once"; else fail "three labels: PASS not printed once: $out"; fi
if [[ "$out" == *"alpha file is unchanged (\`lock\` row, \"quoted\"): $STALE -> $ALPHA"* &&
  "$out" == *"beta file is unchanged: $STALE -> $BETA"* &&
  "$out" == *"delta file is unchanged: $STALE -> $DELTA"* ]]; then
  ok "three labels: prints one old -> new line per pin"
else
  fail "three labels: old -> new lines missing or wrong: $out"
fi
changes="$(diff "$WORK/several.before" "$t" | grep -c '^[<>]')"
if [[ "$changes" -eq 9 ]]; then ok "three labels: exactly nine lines differ"; else fail "three labels: expected 9 differing lines, got $changes"; fi
if grep -qx "  \"$ALPHA\"" "$t" && grep -qx "  \"$BETA\"" "$t" && grep -qx "  \"$DELTA\"" "$t"; then ok "three labels: each sha rewritten to its own digest"; else fail "three labels: a sha was not rewritten to its own digest"; fi
if grep -qx "  \"$OMEGA\"" "$t"; then ok "three labels: the unnamed pin left as it was"; else fail "three labels: the unnamed pin changed"; fi
if [[ "$(grep -cx '# Three texts edited; the defenses still hold.' "$t")" -eq 3 ]]; then ok "three labels: justification above each call"; else fail "three labels: justification not inserted once per pin"; fi
if bash "$t" >/dev/null 2>&1; then ok "three labels: the re-pinned file passes"; else fail "three labels: the re-pinned file still fails"; fi

make_quad_fixture "$STALE" "$STALE" "$STALE" "$OMEGA" "$t"
cp "$t" "$WORK/several-refuse.before"
out="$(run_repin --test-file "$t" 'alpha file' 'gamma' 'beta file' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "several labels, one unknown: exit 3"; else fail "several labels, one unknown: expected exit 3, got $rc: $out"; fi
if cmp -s "$WORK/several-refuse.before" "$t"; then ok "several labels, one unknown: file byte-identical"; else fail "file changed when one of several labels was unknown"; fi
out="$(run_repin --test-file "$t" 'alpha file' 'is unchanged' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "several labels, one ambiguous: exit 3"; else fail "several labels, one ambiguous: expected exit 3, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'alpha file' 'alpha' 'unused')"
rc=$?
if [[ $rc -eq 3 ]]; then ok "two labels naming one pin: exit 3"; else fail "two labels naming one pin: expected exit 3, got $rc: $out"; fi
out="$(run_repin --test-file "$t" 'alpha file' 'omega file' 'unused')"
rc=$?
if [[ $rc -eq 4 ]]; then ok "several labels, one already matching: exit 4"; else fail "several labels, one already matching: expected exit 4, got $rc: $out"; fi
if cmp -s "$WORK/several-refuse.before" "$t"; then ok "several-label refusals changed nothing"; else fail "file changed on a several-label refusal"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]

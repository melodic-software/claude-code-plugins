#!/usr/bin/env bash
# repin-digests.sh computes the digest pins of interview-defenses.test.sh from the files alone
# and runs nothing from the test file's checkout:
#   - on a copy of the plugin, every real pin already matches what it computes, so it agrees
#     with the test on all five pin kinds;
#   - after a guarded section and a fixture change in that copy, it re-pins both and the
#     copy's own test passes;
#   - a planted test file that writes a marker file when run is never run, an argument that
#     would run a command is refused, and so is a pin that reads a file outside the plugin.
#
# test-scope: plugins/planning/scripts/repin-digests.sh
# test-scope: plugins/planning/scripts/lib/pin-digests.sh
# test-scope: plugins/planning/tests/interview-defenses.test.sh
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN="$(cd "$HERE/.." && pwd)"
SUT="$HERE/repin-digests.sh"

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

WORK="$(mktemp -d "${TMPDIR:-/tmp}/repin-digests-test.XXXXXX")" || exit 1
trap 'rm -rf "$WORK"' EXIT

sha_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum <"$1" | cut -d' ' -f1; else shasum -a 256 <"$1" | cut -d' ' -f1; fi
}
STALE="$(printf '%064d' 7)"

# No terminal on stdin, as a lane runs it, from a checkout: here, the work directory.
run_sut() { (cd "$WORK" && bash "$SUT" "$@" </dev/null 2>&1); }

# --- a copy of the plugin: every real pin already matches --------------------------------
copy="$WORK/plugin"
mkdir -p "$copy/scripts" "$copy/tests"
cp -R "$PLUGIN/skills" "$copy/skills"
cp -R "$PLUGIN/scripts/lib" "$copy/scripts/lib"
cp "$PLUGIN/tests/interview-defenses.test.sh" "$copy/tests/"
real="$copy/tests/interview-defenses.test.sh"
cp "$real" "$WORK/real.before"

# Each pin's call line, backslashes and the trailing continuation dropped, names it alone.
pins=()
while IFS= read -r line; do
  pins+=("$line")
done < <(awk '/^pin_(section|frontmatter|case_digest|case_set|file) / {
  line = $0; gsub(/\\/, "", line); sub(/[[:space:]]*$/, "", line); print line
}' "$real")
for kind in pin_section pin_frontmatter pin_case_digest pin_case_set pin_file; do
  if grep -q "^$kind " < <(printf '%s\n' "${pins[@]}"); then ok "the real test has a $kind pin"; else fail "no $kind pin found in the real test"; fi
done
out="$(run_sut --test-file "$real" "${pins[@]}" 'unused')"
rc=$?
if [[ $rc -eq 4 ]]; then ok "every real pin: exit 4"; else fail "every real pin: expected exit 4, got $rc: $out"; fi
matched="$(printf '%s\n' "$out" | grep -c 'the digest already matches')"
if [[ "$matched" -eq "${#pins[@]}" ]]; then
  ok "all ${#pins[@]} real pins match the computed digests"
else
  fail "$matched of ${#pins[@]} real pins match the computed digests: $out"
fi
if cmp -s "$WORK/real.before" "$real"; then ok "every real pin: file unchanged"; else fail "the real test copy changed on a no-op"; fi

# --- a changed section and fixture in the copy: re-pinned, and the copy's test passes ------
skill="$copy/skills/interview/SKILL.md"
awk '{ print } $0 == "## Gates" { print "An added line inside the Gates section." }' "$skill" >"$WORK/skill.md" && cat "$WORK/skill.md" >"$skill"
fixture="$copy/skills/interview/evals/fixtures/lock-stop-on-gap/task-context.md"
printf 'An added fixture line.\n' >>"$fixture"
if bash "$real" >/dev/null 2>&1; then fail "the copy's test passes before the re-pin, so the change was not guarded"; else ok "the copy's test fails before the re-pin"; fi
out="$(run_sut --test-file "$real" 'SKILL.md Gates section' 'case A fixture: the task context' 'Test edit; the defenses still hold.')"
rc=$?
if [[ $rc -eq 0 ]]; then ok "section and fixture re-pinned: exit 0"; else fail "section and fixture: expected exit 0, got $rc: $out"; fi
if [[ "$out" == *"the task context still plants the open decision: "*" -> $(sha_of "$fixture")"* ]]; then
  ok "fixture: prints old -> new with the file's own digest"
else
  fail "fixture: old -> new line missing or wrong: $out"
fi
if bash "$real" >/dev/null 2>&1; then ok "the copy's test passes after the re-pin"; else fail "the copy's test still fails after the re-pin"; fi

# --- a planted test file is read, never run ------------------------------------------------
fake="$WORK/fake"
mkdir -p "$fake/tests" "$fake/data"
printf 'alpha\n' >"$fake/data/alpha.txt"
printf 'outside\n' >"$WORK/outside.txt"
ln -s "$WORK/outside.txt" "$fake/data/link.txt"
marker="$WORK/ran"
t="$fake/tests/fake.test.sh"
cat >"$t" <<EOF
#!/usr/bin/env bash
touch "$marker"
PLUGIN_DIR="\$(cd "\$(dirname "\${BASH_SOURCE[0]}")/.." && pwd)"
DATA="\$PLUGIN_DIR/data"
pin_file() { touch "$marker"; }
pin_file "alpha through a variable" \\
  "\${DATA}/alpha.txt" \\
  "$STALE"
pin_file "alpha behind a command substitution" \\
  "\$(touch "$marker")\$DATA/alpha.txt" \\
  "$STALE"
pin_file "alpha behind a backtick" \\
  "\`touch $marker\`\$DATA/alpha.txt" \\
  "$STALE"
pin_file "a file outside the plugin" \\
  "$WORK/outside.txt" \\
  "$STALE"
pin_file "outside through dot-dot" \\
  "\$PLUGIN_DIR/../outside.txt" \\
  "$STALE"
pin_file "outside through a link" \\
  "\$DATA/link.txt" \\
  "$STALE"
EOF
cp "$t" "$WORK/fake.before"
for label in 'behind a command substitution' 'behind a backtick' 'a file outside the plugin' 'outside through dot-dot' 'outside through a link'; do
  out="$(run_sut --test-file "$t" "$label" 'unused')"
  rc=$?
  if [[ $rc -eq 4 ]]; then ok "$label: refused with exit 4"; else fail "$label: expected exit 4, got $rc: $out"; fi
done
if cmp -s "$WORK/fake.before" "$t"; then ok "refused pins changed nothing"; else fail "the planted file changed on a refusal"; fi
# A test file whose plugin directory is above the checkout is refused before any pin is read.
cp "$t" "$WORK/top.test.sh"
out="$(run_sut --test-file "$WORK/top.test.sh" 'through a variable' 'unused')"
rc=$?
if [[ $rc -eq 2 ]]; then ok "a plugin directory above the checkout: exit 2"; else fail "a plugin directory above the checkout: expected exit 2, got $rc: $out"; fi
if cmp -s "$WORK/fake.before" "$WORK/top.test.sh"; then ok "a plugin directory above the checkout: file unchanged"; else fail "the top-level test file changed"; fi
out="$(run_sut --test-file "$t" 'through a variable' 'Data repin.')"
rc=$?
if [[ $rc -eq 0 ]]; then ok "a pin through a variable: exit 0"; else fail "a pin through a variable: expected exit 0, got $rc: $out"; fi
if grep -qx "  \"$(sha_of "$fake/data/alpha.txt")\"" "$t"; then ok "a pin through a variable: sha rewritten to the file's digest"; else fail "a pin through a variable: sha not rewritten"; fi
if [[ ! -e "$marker" ]]; then ok "the planted test file never ran"; else fail "the planted test file ran: $marker exists"; fi

echo
echo "passed: $PASS, failed: $FAIL"
[[ $FAIL -eq 0 ]]

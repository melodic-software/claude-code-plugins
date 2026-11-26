#!/usr/bin/env bash
# portability-scope: this suite IS check-shell-portability.sh's own fixture
# shellcheck disable=SC2016  # fixture bodies are literal shell content in single quotes; expansion is never wanted
set -uo pipefail

TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-shell-portability.sh"
SCAN_AWK="$SELF_DIR/lib/shell-portability-scan.awk"

REAL_TOKENS="$REPO_ROOT/scripts/shell-portability-tokens.txt"
. "$SELF_DIR/test-git-helpers.sh"

# shellcheck source=lib/test-harness.sh
. "$SELF_DIR/lib/test-harness.sh"
# shellcheck source=lib/fixture-tree.sh
. "$SELF_DIR/lib/fixture-tree.sh"

fx="" TREE=""

scan_paths() {
  local tokens="$1"
  shift
  SHELL_PORTABILITY_TOKENS="$tokens" bash "$SCRIPT" --paths "$@"
}

one_token_list() {
  local f
  f="$(mktemp "$TMP_ROOT/f.XXXXXX")"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

tmpsh() {
  local f
  f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

expect_all_detected() {
  while IFS= read -r case; do
    f="$(tmpsh "$case")"
    if out="$(scan_paths "$1" "$f" 2>&1)"; then
      fail "[$case] should fail, got success: $out"
    else
      ok "[$case] is detected"
    fi
    rm -f "$f"
  done
}

tok="$(one_token_list '\\b')"
f="$(tmpsh "grep -Eq '\\brequire\\b' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "literal \\\\b in a grep pattern should fail, got success: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "literal \\\\b in a grep pattern is detected (not silently inert)"
else
  fail "expected PORTABILITY with file:line, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'grep -Eq "(^|[^A-Za-z0-9_\$])require($|[^A-Za-z0-9_\$])" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "the bracket-expression word-boundary replacement does not fire"
else
  fail "the POSIX-portable replacement must not be flagged"
fi
rm -f "$f"

f="$(tmpsh "PAT=\"\\brequire\\b\"
grep -Eq \"\$PAT\" \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a \\\\b pattern assigned to a variable should fail, got success: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "a \\\\b pattern built in a variable and used later is detected"
else
  fail "expected PORTABILITY on the assignment line, got: $out"
fi
rm -f "$f"

f="$(tmpsh "printf '\\bspinner-frame\\n'")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "printf '\\b' must still fire -- the class is bare by design"
else
  ok "printf '\\b' fires (accepted over-flag, excusable per site)"
fi
rm -f "$f"

f="$(tmpsh "printf '\\bspinner-frame\\n'  # portability-ok: printf escape, not a regex")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "printf '\\b' with a portability-ok: annotation is excused"
else
  fail "an annotated printf '\\b' must be excused"
fi
rm -f "$f" "$tok"

for esc in '\\s' '\\S' '\\w' '\\W' '\\<' '\\>'; do
  tok="$(one_token_list "$esc")"
  f="$(tmpsh "sed -E 's/${esc}foo${esc}/bar/' \"\$file\"")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "literal $esc should fail, got success: $out"
  elif grep -q "PORTABILITY:" <<<"$out"; then
    ok "literal $esc is detected"
  else
    fail "expected PORTABILITY for $esc, got: $out"
  fi
  rm -f "$f" "$tok"
done

tok="$(one_token_list 'grep[^\n]*[[:space:]]-[A-Za-z]*P[A-Za-z]*([[:space:]|&;()<>'"'"'"`]|$)')"

f="$(tmpsh 'grep -P "\\d+" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "grep -P should fail, got success: $out"
else
  ok "grep -P is detected"
fi
rm -f "$f"

f="$(tmpsh 'grep -riP "\\d+" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "grep -riP (combined flags, P last) should fail"
else
  ok "grep -riP (combined flags, P last) is detected"
fi
rm -f "$f"

f="$(tmpsh 'grep -Pn "\\d+" "$file"')" # spellchecker:disable-line
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "grep -Pn (P not last in the cluster) should fail" # spellchecker:disable-line
else
  ok "grep -Pn (P not last in the cluster) is detected" # spellchecker:disable-line
fi
rm -f "$f"

f="$(tmpsh '# Cross-platform: uses grep -E (POSIX ERE) only -- no grep -P (macOS lacks it).')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a comment merely naming grep -P is not flagged (construct matching skips comments)"
else
  fail "a comment-only mention of grep -P must not fire"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'grep[^\n]*[[:space:]]-[A-Za-z]*P[A-Za-z]*([[:space:]|&;()<>'"'"'"`]|$)')"
expect_all_detected "$tok" <<'CASES'
x=$(grep -P)
grep -P|head -n1
grep -P; echo done
CASES
rm -f "$tok"

tok="$(one_token_list 'echo[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*([[:space:]|&;()<>'"'"'"`]|$)')"

f="$(tmpsh 'echo -e "line1\nline2"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "echo -e should fail, got success: $out"
else
  ok "echo -e is detected"
fi
rm -f "$f"

f="$(tmpsh "echo -ne 'a\\nb'")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "echo -ne (combined flags) should fail"
else
  ok "echo -ne (combined flags) is detected"
fi
rm -f "$f"

expect_all_detected "$tok" <<'CASES'
x=$(echo -e)
echo -e|cat
echo -e; echo done
CASES
rm -f "$tok"

tok="$(one_token_list 'sort[^\n]*[[:space:]]-[A-Za-z]*V[A-Za-z]*([[:space:]|&;()<>'"'"'"`]|$)')"

f="$(tmpsh 'sort -V "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort -V should fail, got success: $out"
else
  ok "sort -V is detected"
fi
rm -f "$f"

f="$(tmpsh 'sort -Vr "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "sort -Vr (V not last in the cluster) should fail"
else
  ok "sort -Vr (V not last in the cluster) is detected"
fi
rm -f "$f"

expect_all_detected "$tok" <<'CASES'
x=$(sort -V)
sort -V|head -n1
sort -V; echo done
CASES
rm -f "$tok"

tok="$(one_token_list '--version-sort')"
f="$(tmpsh 'sort --version-sort "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort --version-sort should fail, got success: $out"
else
  ok "sort --version-sort (long form) is detected"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'sort[^;&|\n]*[[:space:]]['"'"'"]?--sort['"'"'"]?(=|[[:space:]]+)['"'"'"]?version([[:space:]|&;()'"'"'"`]|[<>]([^(]|$)|$)')"

expect_all_detected "$tok" <<'CASES'
sort --sort=version "$file"
sort --sort version "$file"
sort --sort='version' "$file"
sort --sort="version" "$file"
sort --sort 'version' "$file"
sort --sort=version
x=$(sort --sort=version)
sort --sort=version|head -n1
sort --sort=version; echo done
sort --sort=version >"$out"
sort '--sort=version' "$file"
sort "--sort=version" "$file"
sort '--sort' version "$file"
sort "--sort" "version" "$file"
CASES

f="$(tmpsh 'git tag --sort=version:refname --list')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "git tag --sort=version:refname is not flagged (no sort command, no WORD boundary)"
else
  fail "git tag --sort=version:refname must not be flagged"
fi
rm -f "$f" "$tok"

f="$(tmpsh "$(printf '%s\n' \
  'echo -e"mail"' \
  'echo -e"mail\tX"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a non-cluster quoted splice after echo -e is not flagged (printed literally)"
else
  fail "echo -e non-cluster splices must not be flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'grep -P"x" file' \
  "grep -P'x' file" \
  'sort -V"r" file' \
  "echo -e\"n\" 'a\\tb'")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "letter splices keep the GNU flag live and should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "a quoted splice of option letters still reports the live GNU flag"
else
  fail "expected all 4 letter splices flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'grep -P"$re" file' \
  'sort -V"$v" file' \
  'grep -P"x y" file')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a non-letter quoted splice is not treated as a cluster"
else
  fail "variable and multi-word splices must not be flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'grep -e "$(printf pattern)" -P file' \
  'sort -k "$(printf 1)" -V file' \
  'sort -k "$(printf 1)" --sort=version file')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an option after a command substitution should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "the scan continues past a command substitution to a later GNU-only option"
else
  fail "expected all 3 post-substitution options flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "grep foo /dev/null; printf '%s\\\\n' -P|cat" \
  "sort /dev/null; printf '%s\\\\n' -V|cat")")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a later command's option-shaped argument is still not attributed backwards"
else
  fail "the separator scoping must still hold: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "grep -P'' pattern" \
  'sort -V"" file' \
  "echo -e'' value" \
  "grep -P''" \
  'sort -V""')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "empty quote pairs should still be detected, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 5 ]]; then
  ok "an empty quote pair after an option cluster is still detected"
else
  fail "expected all 5 empty-pair forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "grep -P'''' pattern" \
  'sort -V'"''"'"" file' \
  "echo -e\"\"'' value")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "repeated empty quote pairs should be detected, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "repeated empty quote pairs are detected, not just a single pair"
else
  fail "expected all 3 repeated-pair forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'grep -P"x"i pattern file' \
  "grep -P'x'i pattern file" \
  'sort -V"r"f file' \
  "echo -e\"n\"E 'a\\tb'")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a cluster letter after a quoted pair should be flagged, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "cluster letters and quoted chunks interleave in either order"
else
  fail "expected all 4 interleaved forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "echo -e\"n\"mail 'a\\tb'" \
  "echo -em 'a\\tb'" \
  "echo -me 'a\\tb'")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a non-[neE] letter in echo's cluster is printed literally and is not flagged"
else
  fail "echo clusters with a non-[neE] letter must not be flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "echo -ne 'a\\tb'" \
  "echo -eE 'a\\tb'" \
  "echo -e\"n\"E 'a\\tb'")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "genuine [neE] clusters should still be flagged, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "echo clusters built only from n/e/E are still flagged"
else
  fail "expected all 3 [neE] clusters flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "grep foo /dev/null; printf '%s\\n' -P|cat" \
  "sort /dev/null; printf '%s\\n' -V|cat" \
  "grep foo /dev/null && printf '%s\\n' -P" \
  "sort /dev/null && printf '%s\\n' --sort=version")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a later command's -P/-V/--sort argument is not attributed to grep/sort"
else
  fail "the option scan must stop at a command separator, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'echo -e<(printf x)' \
  'grep -P<(printf x) foo' \
  'sort -V<(printf x)' \
  'sort --sort=version<(printf x)' \
  'grep -P>(cat) foo')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a process substitution attached to an option cluster is not flagged"
else
  fail "attached process substitutions must not be flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'sort -V <file' \
  'sort -V >out' \
  'grep -P<file' \
  'echo -e>out' \
  'sort --sort=version<file')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "redirection-terminated GNU options should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 5 ]]; then
  ok "a redirection after an option cluster still terminates the word and is flagged"
else
  fail "expected all 5 redirection forms flagged, got: $out"
fi
rm -f "$f"

tok="$(one_token_list '(^|[^[:alnum:]_"'\'"'"'\\])(\$?['\''"]|\\)*s(\$?['\''"]|\\)*e(\$?['\''"]|\\)*d(\$?['\''"]|\\)*([[:space:]]([^;&|()`\n]|[<>]\([^)]*\))*)?[[:space:]]+(\$?['\''"]|\\)*-[bEnrsuz]*i([[:space:]|&;()<>]|$)')"

f="$(tmpsh "sed -i 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "unsuffixed sed -i should fail, got success: $out"
else
  ok "unsuffixed sed -i is detected"
fi
rm -f "$f"

f="$(tmpsh "sed -i.bak -E \"s/foo/bar/\" \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -i.bak (suffix directly attached) is not flagged"
else
  fail "sed -i.bak must not be flagged"
fi
rm -f "$f"

f="$(tmpsh "sed -i '' 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -i '' should fail -- it is GNU-incompatible despite looking BSD-safe, got success: $out"
else
  ok "sed -i '' (space-separated empty-suffix, single-quoted) is detected, not excused"
fi
rm -f "$f"

f="$(tmpsh 'sed -i "" -E "s/foo/bar/" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -i \"\" should fail -- it is GNU-incompatible despite looking BSD-safe, got success: $out"
else
  ok "sed -i \"\" (space-separated empty-suffix, double-quoted) is detected, not excused"
fi
rm -f "$f"

while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "[$case] should fail -- an unsuffixed in-place cluster, got success: $out"
  else
    ok "[$case] (unsuffixed in-place cluster without E) is detected"
  fi
  rm -f "$f"
done <<'CASES'
sed -ni '/keep/p' "$file"
sed -si 's/foo/bar/' "$file"
sed -ri 's/foo/bar/' "$file"
sed -zi 's/foo/bar/' "$file"
sed -bi 's/foo/bar/' "$file"
sed -ui 's/foo/bar/' "$file"
CASES

while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if scan_paths "$tok" "$f" >/dev/null 2>&1; then
    ok "[$case] is not flagged -- not a no-argument option cluster"
  else
    fail "[$case] must not be flagged -- the trailing i is not sed's in-place flag"
  fi
  rm -f "$f"
done <<'CASES'
sed -ei 's/foo/bar/' "$file"
sed -fi 's/foo/bar/' "$file"
sed -ni.bak '/keep/p' "$file"
CASES

while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if scan_paths "$tok" "$f" >/dev/null 2>&1; then
    ok "[$case] is not flagged -- the -i belongs to a later command"
  else
    fail "[$case] must not be flagged -- only the sed command's own options count"
  fi
  rm -f "$f"
done <<'CASES'
sed -n 'p' "$file"; grep -Ei pattern "$file"
sed -n 'p' "$file" && grep -i pattern "$file"
sed -n 'p' "$file" | grep -si pattern
CASES

f="$(tmpsh "foo=\$(sed -n 'p' \"\$a\") bar=\$(tool -i \"\$b\")")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a subshell close ends the gap -- tool's -i is not attributed to sed"
else
  fail "\$(sed ...) \$(tool -i ...) must not fire -- the -i belongs to tool"
fi
rm -f "$f"

while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "[$case] should fail -- a process substitution is one word, got success: $out"
  else
    ok "[$case] (process substitution before the cluster) is detected"
  fi
  rm -f "$f"
done <<'CASES'
sed -f <(gen_script) -i "$file"
sed -f <(gen_script) -Ei "$file"
CASES

f="$(tmpsh "sed 'a;b' -Ei \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed 'a;b' -Ei should fail -- the ';' is inside the script, got success: $out"
else
  ok "a ';' inside a quoted sed script does not end the command gap"
fi
rm -f "$f"

f="$(tmpsh "used=\"\$(grep -i pattern \"\$file\")\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "an identifier containing 'sed' (used=) does not arm the token on a bare -i"
else
  fail "used=\"\$(grep -i ...)\" must not fire -- 'sed' inside an identifier is not a sed command"
fi
rm -f "$f"

f="$(tmpsh "sed -Ei 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -Ei (unsuffixed) should fail, got success: $out"
else
  ok "sed -Ei (unsuffixed) is detected"
fi
rm -f "$f"

f="$(tmpsh "  sed -Ei 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "indented sed -Ei should fail, got success: $out"
else
  ok "indented sed -Ei is detected (command-token anchor allows a leading separator)"
fi
rm -f "$f"

f="$(tmpsh "sed -nEi 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -nEi (E/i not adjacent, extra letter in cluster) should fail, got success: $out"
else
  ok "sed -nEi (E/i not adjacent, extra letter in cluster) is detected"
fi
rm -f "$f"

f="$(tmpsh "sed -iE 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -iE (E is an attached backup suffix, not a flag) is not flagged"
else
  fail "sed -iE must not be flagged -- E is an attached nonempty suffix, which is dual-compatible"
fi
rm -f "$f"

f="$(tmpsh "sed -Ei.bak 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -Ei.bak (attached nonempty suffix) is not flagged"
else
  fail "sed -Ei.bak must not be flagged -- attached suffix is dual-compatible"
fi
rm -f "$f"

f="$(tmpsh "sed -Ei'' 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -Ei'' (attached empty suffix) is not flagged -- deferred ambiguous shape"
else
  fail "sed -Ei'' must not be flagged -- it is the same deferred ambiguous shape as -i''"
fi
rm -f "$f"

f="$(tmpsh "grep -Ei 'pattern' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "grep -Ei (no 'sed' on the line) does not fire the sed-scoped token"
else
  fail "grep -Ei must not fire a sed-scoped token -- it has no 'sed' mention on the line"
fi
rm -f "$f"

f="$(tmpsh "used=\"\$(grep -Ei 'pattern' \"\$file\")\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "an identifier containing 'sed' (used=) does not arm the sed-scoped token"
else
  fail "used=\"\$(grep -Ei ...)\" must not fire -- 'sed' inside an identifier is not a sed command"
fi
rm -f "$f"

expect_all_detected "$tok" <<'CASES'
x=$(sed -Ei)
sed -Ei|cat
sed -Ei; echo done
CASES
rm -f "$tok"

tok="$(one_token_list '(^|[^[:alnum:]_"'\'"'"'\\])(\$?['\''"]|\\)*s(\$?['\''"]|\\)*e(\$?['\''"]|\\)*d(\$?['\''"]|\\)*([[:space:]]([^;&|()`\n]|[<>]\([^)]*\))*)?[[:space:]]+(\$?['\''"]|\\)*--(\$?['\''"]|\\)*i(\$?['\''"]|\\)*n(\$?['\''"]|\\)*-(\$?['\''"]|\\)*p(\$?['\''"]|\\)*l(\$?['\''"]|\\)*a(\$?['\''"]|\\)*c(\$?['\''"]|\\)*e(\$?['\''"]|\\)*([[:space:]|&;()<>]|=|$)')"

f="$(tmpsh "sed --in-place 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed --in-place (bare) should fail, got success: $out"
else
  ok "sed --in-place (bare) is detected"
fi
rm -f "$f"

f="$(tmpsh "sed --in-place=.bak 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed --in-place=SUFFIX should fail, got success: $out"
else
  ok "sed --in-place=SUFFIX (long form has no portable BSD equivalent, suffixed or not) is detected"
fi
rm -f "$f"

f="$(tmpsh "case \"\$1\" in --in-place) in_place=1 ;; esac")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a script's own --in-place option arm is not flagged (no sed command on the line)"
else
  fail "--in-place must be scoped to a sed invocation -- an unrelated option arm must not fire"
fi
rm -f "$f"

expect_all_detected "$tok" <<'CASES'
x=$(sed --in-place)
sed --in-place|cat
sed --in-place; echo done
CASES

while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if scan_paths "$tok" "$f" >/dev/null 2>&1; then
    ok "[$case] is not flagged -- the --in-place belongs to a later command"
  else
    fail "[$case] must not be flagged -- only the sed command's own options count"
  fi
  rm -f "$f"
done <<'CASES'
sed -n 'p' "$file"; tool --in-place x
sed -n 'p' "$file" && tool --in-place x
sed -n 'p' "$file" | tool --in-place x
CASES

f="$(tmpsh "sed -f <(gen_script) --in-place \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -f <(gen) --in-place should fail -- a process substitution is one word, got success: $out"
else
  ok "a process substitution before --in-place does not end the command gap"
fi
rm -f "$f"
rm -f "$tok"

tok="$(one_token_list 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')"

f="$(tmpsh 'resolved=$(readlink -f -- "$1" 2>/dev/null)')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "bare readlink -f should fail, got success: $out"
else
  ok "bare readlink -f (no realpath attempt) is detected"
fi
rm -f "$f"

f="$(tmpsh 'resolved=$(realpath -- "$1" 2>/dev/null) || resolved=$(readlink -f -- "$1" 2>/dev/null)')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "readlink -f co-located with a realpath attempt is auto-guarded"
else
  fail "the realpath-first fallback ladder must not be flagged"
fi
rm -f "$f"

f="$(tmpsh 'realpath -- "$1" >/dev/null; readlink -f -- "$1"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "realpath;readlink with no || fallback relationship should fail, got success: $out"
else
  ok "realpath and readlink with no actual || fallback relationship is still flagged"
fi
rm -f "$f"

f="$(tmpsh 'realpath -- "$1" || echo "readlink -f is unavailable"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a printed-only readlink counterpart should fail, got success: $out"
else
  ok "a readlink counterpart that is only printed, not run, is still flagged"
fi
rm -f "$f" "$tok"

tok="$(one_token_list "$(printf '%s\n%s' '\\b' 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')")"
f="$(tmpsh 'echo "realpath is a coreutils tool"; grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an unrelated realpath mention should not excuse the \\b hit, got success: $out"
else
  ok "the realpath guard is scoped to the readlink pattern, not the whole line"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'date[[:space:]]+[^\n]*-d([[:space:]]|$)')"

f="$(tmpsh 'e=$(date -u -d "$s" +%s 2>/dev/null)')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "date -d should fail, got success: $out"
else
  ok "date -d is detected"
fi
rm -f "$f"

f="$(tmpsh 'e=$(date -u -d "@$e" +%s 2>/dev/null)')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "date -d with an @-epoch argument should fail, got success: $out"
else
  ok "date -d with an @-epoch argument is detected"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'date[[:space:]]+[^\n]*-d([[:space:]]|$)')"
f="$(tmpsh '# GNU date -d and BSD date -j -f are mutually exclusive dialects.')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a comment merely naming date -d is not flagged"
else
  fail "a comment-only mention of date -d must not fire"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'date[[:space:]]+[^\n]*-d([[:space:]]|$)')"
f="$(tmpsh 'elif [[ "$candidate" == "$base" && -d "$candidate" ]]; then')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "\"date\" as a substring of \"candidate\" does not spuriously match -d"
else
  fail "the candidate/-d false positive must not fire"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'stat[[:space:]]+[^\n]*-c')"

f="$(tmpsh 'size=$(stat -c%s "$f" 2>/dev/null)')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "bare stat -c should fail, got success: $out"
else
  ok "bare stat -c (no stat -f attempt) is detected"
fi
rm -f "$f"

f="$(tmpsh "dev_of() { stat -c '%d' \"\$1\" 2>/dev/null || stat -f '%d' \"\$1\" 2>/dev/null; }")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "stat -c co-located with a stat -f fallback is auto-guarded"
else
  fail "the stat -f fallback must not be flagged"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'stat[[:space:]]+[^\n]*-c')"
f="$(tmpsh "stat -f '%d' \"\$1\" >/dev/null; stat -c '%d' \"\$1\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "stat -f;stat -c with no || fallback relationship should fail, got success: $out"
else
  ok "stat -f and stat -c with no actual || fallback relationship is still flagged"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$f\" || echo 'stat -f is unavailable'")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a printed-only stat -f counterpart should fail, got success: $out"
else
  ok "a stat -f counterpart that is only printed, not run, is still flagged"
fi
rm -f "$f"

f="$(tmpsh 'size=$(stat -c "%s" "$1") || size=$(stat -f "%z" "$1")')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a name=\$(stat -f ...) fallback after || is still recognized as a guard"
else
  fail "the assignment-wrapped stat -f fallback ladder must not be flagged"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$f\"; true || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a stat -f reached across a ; should fail, got success: $out"
else
  ok "a stat -f fallback in a LATER command segment does not guard the GNU call"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$f\" & true || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a stat -f reached across a background & should fail, got success: $out"
else
  ok "a backgrounding & also breaks the stat fallback relationship"
fi
rm -f "$f"

f="$(tmpsh 'size=$(stat -c "%s" "$1" 2>&1) || size=$(stat -f "%z" "$1")')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a 2>&1 redirection inside the ladder does not break the guard"
else
  fail "2>&1 must not be mistaken for a control &: $(scan_paths "$tok" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh 'size=$(stat -c "%s" "$f") || size=$(stat 2>/dev/null -f "%z" "$f")')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a redirection before the BSD fallback option is still recognized as a guard"
else
  fail "a redirecting BSD fallback must not be flagged: $(scan_paths "$tok" "$f" 2>&1)"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')"
f="$(tmpsh 'realpath -- "$1"; true || readlink -f -- "$1"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a readlink reached across a ; should fail, got success: $out"
else
  ok "a realpath attempt in a LATER command segment does not guard readlink -f"
fi
rm -f "$f"

f="$(tmpsh 'realpath -- "$1" & true || readlink -f -- "$1"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a readlink reached across a background & should fail, got success: $out"
else
  ok "a backgrounding & also breaks the readlink fallback relationship"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'stat[[:space:]]+[^\n]*-c')"
f="$(tmpsh 'run "safe alias" "git -c alias.st=status st" 0')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "\"stat\" as a prefix of \"status\" does not spuriously match -c"
else
  fail "the status/-c false positive must not fire"
fi
rm -f "$f" "$tok"

tok="$(one_token_list "$(printf '%s\n%s' '\\b' 'stat[[:space:]]+[^\n]*-c')")"
f="$(tmpsh 'echo "stat -f is the BSD form"; grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an unrelated stat -f mention should not excuse the \\b hit, got success: $out"
else
  ok "the stat -f guard is scoped to the stat -c pattern, not the whole line"
fi
rm -f "$f" "$tok"

amptok="$(one_token_list '!subst-replacement-ampersand')"

amp_fires() {
  local label="$1" body="$2" f out
  f="$(tmpsh "$body")"
  if out="$(scan_paths "$amptok" "$f" 2>&1)"; then
    fail "$label should fire, got success: $out"
  elif grep -q "PORTABILITY: ${f}:1: !subst-replacement-ampersand" <<<"$out"; then
    ok "$label fires"
  else
    fail "$label: expected the & class at file:line, got: $out"
  fi
  rm -f "$f"
}
amp_clean() {
  local label="$1" body="$2" f out
  f="$(tmpsh "$body")"
  if out="$(scan_paths "$amptok" "$f" 2>&1)"; then
    ok "$label does not fire"
  else
    fail "$label must not fire: $out"
  fi
  rm -f "$f"
}

amp_fires 'the #2008 defect shape (quoted pattern, bare & replacement)' \
  'normalized="${normalized//"$soh"/&}"'
amp_fires 'the single-substitution ${var/pat/&} spelling' 'v="${v/X/&}"'
amp_fires 'a bare & in the middle of a replacement' 'v="${v//X/p&q}"'
amp_fires 'a doubled && replacement' 'v="${v//X/&&}"'
amp_fires 'a replacement containing its own slash' 'v="${v//X/b&/c}"'
amp_fires 'a bare & after an escaped one' 'v="${v//X/\&&}"'
amp_fires 'a bare & after a double-quoted one' 'v="${v//X/"&"&}"'
amp_fires 'a bare & after a nested expansion' 'v="${v//X/${r}&}"'
amp_fires 'a nested expansion in the pattern half' 'v="${v//${pat}/&}"'
amp_fires 'a double-quoted slash inside the pattern' 'v="${v//"a/b"/&}"'
amp_fires 'a backslash-escaped slash as the pattern' 'v="${v//\//&}"'
amp_fires 'an anchored ${var/#pat/&} substitution' 'v="${v/#X/&}"'
amp_fires 'an array element substitution' 'v="${arr[@]//X/&}"'
amp_fires 'a positional-parameter substitution' 'v="${1//X/&}"'
amp_fires 'an unquoted expansion context' 'v=${v//X/&}'

amp_clean 'a backslash-escaped \& replacement' 'n="${n//"$soh"/\&}"'
amp_clean 'a double-quoted "&" replacement' 'v="${v//X/"&"}"'
amp_clean 'a single-quoted &-replacement' "v=\"\${v//X/'&'}\""
amp_clean 'the ${var//pat} deletion form' 'v="${v//X}"'
amp_clean 'an empty replacement' 'v="${v//X/}"'
amp_clean 'a :- default-value word containing a slash and an &' 'v="${v:-a/b/&}"'
amp_clean 'a := assign-default word containing an &' 'v="${v:=a/b/&}"'
amp_clean 'a # prefix-strip pattern' 'v="${v#*/}"'
amp_clean 'a % suffix-strip pattern' 'v="${v%/*}"'
amp_clean 'a substring expansion' 'v="${v:0:1}"'
amp_clean 'a length expansion' 'v="${#v}"'
amp_clean 'an && control operator' 'a && b'
amp_clean 'a backgrounding &' 'cmd &'
amp_clean 'a 2>&1 file-descriptor duplication' 'printf x 2>&1'
amp_clean 'a quoted & in ordinary text' 'echo "a & b"'
amp_clean 'an & in the PATTERN half' 'v="${v//&/X}"'
amp_clean 'an && inside a nested substitution in the replacement' 'v="${v//X/$(a && b)}"'
amp_clean 'the construct inside single quotes (no expansion at all)' "printf '%s' '\${v//X/&}'"

amp_fires 'a substitution on the ${#} positional-argument count' 'v="${#//2/&}"'
amp_fires 'a single substitution on ${#}' 'v="${#/2/&}"'
amp_clean 'a plain ${#} count' 'v="${#}"'
amp_clean 'a ${##} length-of-$# expansion' 'v="${##}"'
amp_clean 'a ${#arr[@]} array length' 'v="${#arr[@]}"'

amp_clean 'an && inside a <( ) process substitution in the replacement' \
  'v="${v//X/<(cmd1 && cmd2)}"'
amp_clean 'an && inside a >( ) process substitution in the replacement' \
  'v="${v//X/>(cmd1 && cmd2)}"'
amp_clean 'a single & inside a process substitution in the replacement' \
  'v="${v//X/<(cmd1 & cmd2)}"'
amp_clean 'a process substitution in the PATTERN half' \
  'v="${v//<(cmd1 && cmd2)/y}"'
amp_fires 'a bare & after a process substitution in the replacement' \
  'v="${v//X/<(cmd1 && cmd2)&}"'
amp_fires 'a bare & replacement after a process substitution in the pattern' \
  'v="${v//<(cmd1 && cmd2)/&}"'

f="$(tmpsh 'v="${v//X/&}" # portability-ok: the sed-rule expansion is what this line wants')"
if scan_paths "$amptok" "$f" >/dev/null 2>&1; then
  ok "a same-line portability-ok excuses an & hit"
else
  fail "an annotated & hit must be excused: $(scan_paths "$amptok" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh '# portability-ok: bash >= 5.2 is guaranteed here
v="${v//X/&}"')"
if scan_paths "$amptok" "$f" >/dev/null 2>&1; then
  ok "a portability-ok comment block above excuses an & hit"
else
  fail "a block-annotated & hit must be excused: $(scan_paths "$amptok" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh '# portability-scope: this fixture IS a bash-5.2-construct corpus, on purpose
v="${v//X/&}"')"
if scan_paths "$amptok" "$f" >/dev/null 2>&1; then
  ok "a whole-file portability-scope excuses an & hit"
else
  fail "a file-scoped & hit must be excused: $(scan_paths "$amptok" "$f" 2>&1)"
fi
rm -f "$f"

amp_clean 'a comment-only line naming the construct' '# never write ${var//pat/&} here'

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'msg="opened here\nv=${v//X/&}"\n' >"$f"
if out="$(scan_paths "$amptok" "$f" 2>&1)"; then
  fail "an & hit on the second physical line should fire, got success: $out"
elif grep -q "PORTABILITY: ${f}:2: !subst-replacement-ampersand" <<<"$out"; then
  ok "an & hit inside a joined record is attributed to its own physical line"
else
  fail "expected the & hit at line 2 of the joined record, got: $out"
fi
rm -f "$f"

tok="$(one_token_list '\\b')"
f="$(tmpsh 'v="${v//X/&}"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "the & class is inert while its token line is absent"
else
  fail "the & class fired without its token line: $(scan_paths "$tok" "$f" 2>&1)"
fi
rm -f "$f" "$tok"

f="$(tmpsh 'v="${v//X/y}"')"
out="$(scan_paths "$amptok" "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 ]]; then
  ok "a directive-only token list is a loaded config, not an empty pattern set"
else
  fail "a directive-only token list failed closed: rc=$rc out=$out"
fi
rm -f "$f"

BADCLS="$(one_token_list '!no-such-class')"
f="$(tmpsh 'v="${v//X/&}"')"
out="$(scan_paths "$BADCLS" "$f" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"unknown script-implemented class"* ]]; then
  ok "an unknown script-implemented class fails closed"
else
  fail "an unknown !name did not fail closed: rc=$rc out=$out"
fi
rm -f "$f" "$BADCLS"

f="$(tmpsh 'v="${v//X/&}"')"
out="$(scan_paths "$amptok" "$f" 2>&1)"
if [[ "$out" == *"!subst-replacement-ampersand names the one class"* ]]; then
  ok "an & hit prints the bash-version remediation paragraph"
else
  fail "an & hit must carry its own remediation paragraph, got: $out"
fi
rm -f "$f"

tok="$(one_token_list 'grep[^\n]*[[:space:]]-[A-Za-z]*P([[:space:]]|$)')"
f="$(tmpsh 'grep -P foo "$file"')"
out="$(scan_paths "$tok" "$f" 2>&1)"
if [[ "$out" == *"PORTABILITY:"* && "$out" != *"!subst-replacement-ampersand names the one class"* ]]; then
  ok "an unrelated class failure does not print the bash-version paragraph"
else
  fail "the & remediation paragraph leaked onto an unrelated failure, got: $out"
fi
rm -f "$f" "$tok"

f="$(tmpsh 'normalized="${normalized//"$soh"/&}"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "the shipped token list must flag the & class, got success: $out"
elif grep -q "!subst-replacement-ampersand" <<<"$out"; then
  ok "the shipped token list has the & class active"
else
  fail "expected the & class from the shipped list, got: $out"
fi
rm -f "$f" "$amptok"

tok="$(one_token_list '\\b')"

f="$(tmpsh "grep -Eq '\\bfoo\\b' \"\$file\" # portability-ok: fixture asserts the GNU-only form on purpose")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "same-line portability-ok passes"
else
  fail "same-line portability-ok should pass"
fi
rm -f "$f"

f="$(tmpsh '# portability-ok: this fixture is intentionally GNU-only
grep -Eq "\\bfoo\\b" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "comment-block-above portability-ok passes"
else
  fail "comment-block-above portability-ok should pass"
fi
rm -f "$f"

f="$(tmpsh '# portability-ok: covers only the next line
grep -Eq "\\bfoo\\b" "$file"
plain_line=1
grep -Eq "\\bbar\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "annotation should not sanction a later hit, got success: $out"
elif grep -q ":4:" <<<"$out" && ! grep -q ":2:" <<<"$out"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f" "$tok"

tok="$(one_token_list '\\b')"
f="$(tmpsh '# portability-scope: this fixture IS a GNU-only-construct corpus, on purpose
grep -Eq "\\bfoo\\b" "$file"
grep -Eq "\\bbar\\b" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "whole-file portability-scope excuses every hit in the file"
else
  fail "whole-file portability-scope should pass"
fi
rm -f "$f" "$tok"

tok="$(one_token_list '\\b')"
f="$(tmpsh '# This script supports a whole-file portability-scope: <reason> declaration.
grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a doc-comment merely mentioning portability-scope: should not exempt the file, got success: $out"
elif grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "a doc-comment mentioning portability-scope: (not a genuine declaration) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f"

f="$(tmpsh 'msg="see portability-scope: docs for details"
grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a string literal mentioning portability-scope: should not exempt the file, got success: $out"
elif grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "a string literal mentioning portability-scope: (not a comment) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f" "$tok"

tok="$(one_token_list '\\b')"
f="$(tmpsh 'plain_line=1
  # portability-scope: indented declaration still counts
grep -Eq "\\bfoo\\b" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "an indented genuine portability-scope declaration anywhere in the file still exempts it"
else
  fail "an indented genuine portability-scope declaration should still exempt the file"
fi
rm -f "$f" "$tok"

tok="$(one_token_list '\\b')"
fixture_tree::build fx --sut "$SCRIPT"
printf 'grep -Eq "\\bfoo\\b" "$file"\n' >"$fx/FOO=bar.sh"
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="$tok" bash scripts/check-shell-portability.sh --paths "FOO=bar.sh" 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'PORTABILITY: FOO=bar\.sh:1:' <<<"$out"; then
  ok "a filename shaped like identifier=value is scanned, not silently dropped by awk"
else
  fail "an identifier=value-shaped filename must be scanned, not dropped (rc=$rc): $out"
fi
rm -rf "$fx" "$tok"

tok="$(one_token_list '\\b')"
fixture_tree::build fx --sut "$SCRIPT"
cp "$tok" "$fx/t=custom.txt"
cp "$tok" "$fx/plain-tokens.txt"
printf 'grep -Eq "\\bfoo\\b" "$file"\n' >"$fx/plain.sh"
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="t=custom.txt" bash scripts/check-shell-portability.sh --paths "plain.sh" 2>&1)"
rc=$?
if [[ "$rc" -eq 1 ]] && grep -q 'PORTABILITY: plain\.sh:1:' <<<"$out"; then
  ok "a token list shaped like identifier=value still loads its patterns"
else
  fail "an identifier=value-shaped token list must not silently disable the gate (rc=$rc): $out"
fi
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="plain-tokens.txt" bash scripts/check-shell-portability.sh --paths "plain.sh" 2>&1)"
if [[ "$?" -eq 1 ]] && grep -q 'PORTABILITY: plain\.sh:1:' <<<"$out"; then
  ok "the same fixture flags through an ordinary token path (guard is discriminating)"
else
  fail "control case did not flag; the token-list assertion above is not discriminating"
fi
rm -rf "$fx" "$tok"

BAD_TOKENS="$(mktemp "$TMP_ROOT/f.XXXXXX")"
printf '%s\n' '(unterminated' >"$BAD_TOKENS" # unmatched '(' -- invalid ERE, awk faults
f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="$BAD_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "malformed active token exits 2 (fail closed, no silent pass)"
else
  fail "malformed active token should exit 2, not silently treat the file as clean"
fi
rm -f "$f" "$BAD_TOKENS"

EMPTY_TOKENS="$(mktemp "$TMP_ROOT/f.XXXXXX")"
printf '# only comments\n#\n\n' >"$EMPTY_TOKENS"
f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="$EMPTY_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "a token list with no active patterns exits 2 (fail closed, gate never silently disabled)"
else
  fail "empty token list should exit 2, not silently treat every file as clean"
fi
rm -f "$f" "$EMPTY_TOKENS"

tok="$(one_token_list 'stat[[:space:]]+-c')"
f="$(tmpsh 'echo hello')"
scan_tmp="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
TMPDIR="$scan_tmp" SHELL_PORTABILITY_TOKENS="$tok" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
rc=$?
left="$(ls -A "$scan_tmp")"
if [[ "$rc" -eq 0 && -z "$left" ]]; then
  ok "a clean scan exits 0 and its EXIT trap removes the active-pattern temp file"
else
  fail "clean scan should exit 0 (got $rc) and leave TMPDIR empty (left: $left)"
fi
rm -rf "$scan_tmp" "$f" "$tok"

f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="/nonexistent/tokens.txt" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "missing token list exits 2 (fail closed)"
else
  fail "missing token list should exit 2"
fi
rm -f "$f"

(cd "$REPO_ROOT" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash "$SCRIPT" definitely-not-a-ref >/dev/null 2>&1)
if [[ "$?" -eq 2 ]]; then
  ok "invalid base ref exits 2 (fail closed)"
else
  fail "invalid base ref should exit 2"
fi

fixture_tree::build fx --sut "$SCRIPT"
mkdir -p "$fx/plugins/alpha/vendor" "$fx/plugins/alpha/skills/demo/evals" \
  "$fx/plugins/alpha/skills/demo/context"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/gate.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/vendor/upstream.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/notes.md"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/skills/demo/SKILL.md"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/skills/demo/context/run.md"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/skills/demo/evals/adversarial.md"
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  grep -q 'gate.sh' <<<"$out" &&
  grep -q 'SKILL\.md' <<<"$out" &&
  grep -q 'context/run\.md' <<<"$out" &&
  ! grep -qE 'vendor/|notes\.md|evals/' <<<"$out"; then
  ok "--all scans .sh and skill .md but excludes vendor/, evals/, and non-skill .md"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
if (cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all >/dev/null 2>&1); then
  ok "an empty tree passes"
else
  fail "an empty tree should pass"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
mkdir -p "$fx/plugins/alpha/skills/demo/context"
out="$(
  cd "$fx" &&
    git_init_test_repo "$fx" &&
    git -C "$fx" commit -q --allow-empty -m base &&
    base="$(git -C "$fx" rev-parse HEAD)" &&
    printf '%s\n' 'stat -c %Y "$f"' >'plugins/alpha/skills/demo/context/mtime.md' &&
    git -C "$fx" add -A >/dev/null 2>&1 &&
    git -C "$fx" commit -q -m add-skill-md &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list 'stat[[:space:]]+-c')" bash scripts/check-shell-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'mtime\.md' <<<"$out"; then
  ok "diff-mode gates a changed skill markdown file (#2704)"
else
  fail "diff-mode should flag changed skill .md (rc=$rc): $out"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
mkdir -p "$fx/plugins/alpha/skills/demo"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/skills/demo/SKILL.md"
printf '%s\n' 'plugins/alpha/skills/demo/SKILL.md' >"$fx/scripts/shell-portability-skill-md-baseline.txt"
out="$(
  cd "$fx" &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1
)"
rc=$?
if [[ "$rc" -eq 0 ]] && grep -q 'No unexcused' <<<"$out"; then
  ok "skill-md baseline grandfathers a known hit under --all"
else
  fail "baselined skill .md should pass --all (rc=$rc): $out"
fi
out="$(
  cd "$fx" &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --paths \
      plugins/alpha/skills/demo/SKILL.md 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'PORTABILITY:.*SKILL\.md' <<<"$out"; then
  ok "--paths ignores the skill-md baseline (audit mode)"
else
  fail "--paths should still flag a baselined file (rc=$rc): $out"
fi
printf '%s\n' 'echo clean' >"$fx/plugins/alpha/skills/demo/SKILL.md"
out="$(
  cd "$fx" &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'STALE BASELINE' <<<"$out"; then
  ok "a cleaned-up skill-md baseline entry fails as stale"
else
  fail "stale baseline entry should fail (rc=$rc): $out"
fi
rm -f "$fx/plugins/alpha/skills/demo/SKILL.md"
out="$(
  cd "$fx" &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q "names a missing file" <<<"$out"; then
  ok "a missing skill-md baseline entry fails as stale under --all"
else
  fail "missing baseline entry should fail under --all (rc=$rc): $out"
fi
mkdir -p "$fx/plugins/alpha/skills/demo"
printf '%s\n' 'word-boundary \\b token' >"$fx/plugins/alpha/skills/demo/SKILL.md"
mkdir -p "$fx/plugins/alpha/skills/demo/vendor"
mv "$fx/plugins/alpha/skills/demo/SKILL.md" "$fx/plugins/alpha/skills/demo/vendor/SKILL.md"
printf '%s\n' 'plugins/alpha/skills/demo/vendor/SKILL.md' >"$fx/scripts/shell-portability-skill-md-baseline.txt"
out="$(
  cd "$fx" &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] && grep -q 'outside the scannable skill-md set' <<<"$out"; then
  ok "a vendor/-moved skill-md baseline entry fails as outside-scannable"
else
  fail "outside-scannable baseline entry should fail (rc=$rc): $out"
fi
rm -rf "$fx"

fixture_tree::build fx --sut "$SCRIPT"
quoted_name="$(printf 'quoted-\303\251.sh')" # trailing U+00E9 byte -- non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git_init_test_repo "$fx" &&
    git -C "$fx" commit -q --allow-empty -m base &&
    base="$(git -C "$fx" rev-parse HEAD)" &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >'plain.sh' &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$quoted_name" &&
    git -C "$fx" add -A >/dev/null 2>&1 &&
    git -C "$fx" commit -q -m add-scripts &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  grep -q 'plain.sh:1:' <<<"$out" &&
  [[ "$(echo "$out" | grep -c 'PORTABILITY:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII changed files (rc=$rc): $out"
fi
rm -rf "$fx"

if out="$(scan_paths "$REAL_TOKENS" "$REPO_ROOT/plugins/markdown-format/git-hooks/markdown-gates.sh" 2>&1)"; then
  ok "the shipped token list does not flag markdown-gates.sh's reference implementation"
else
  fail "markdown-gates.sh must stay clean under the shipped token list, got: $out"
fi

f="$(tmpsh 'x=$(date -d "$s" +%s)')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "date -d should now be enforced by the shipped list, got success: $out"
else
  ok "date -d is enforced in the shipped list (#1510)"
fi
rm -f "$f"

f="$(tmpsh 'y=$(stat -c%s "$f")')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "stat -c should now be enforced by the shipped list, got success: $out"
else
  ok "stat -c is enforced in the shipped list (#1510)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'validate -d config' \
  'update -d /tmp' \
  'mystat -c foo')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a word merely ENDING in date/stat is not mistaken for the command"
else
  fail "validate/update/mystat must not be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh '/usr/bin/date -d @0')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a path-qualified date -d should still fail, got success: $out"
else
  ok "the leading boundary still admits a path-qualified /usr/bin/date -d"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date -d@0' \
  'date -d"$s" +%s' \
  'date --date=@0' \
  'date --date @0' \
  'stat --format=%s "$file"' \
  'stat --printf=%s "$file"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "attached and long date/stat spellings should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 6 ]]; then
  ok "attached -d, --date, --format and --printf spellings are all detected"
else
  fail "expected all 6 spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date -dtomorrow +%s' \
  'date -u -dyesterday' \
  'stat -Lc%s "$file"' \
  'stat -Lc '"'"'%s'"'"' "$file"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "worded -d arguments and clustered -c should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "a bare-word attached -d and a clustered -Lc are both detected"
else
  fail "expected all 4 forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date --debug +%s' \
  'stat --dereference "$file"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "date --debug and stat --dereference are not read as -d / -c"
else
  fail "long flags must not match the short-option branch: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date -ud tomorrow +%s' \
  'date -ud@0')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a clustered -d should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a clustered date -ud is detected at the argument-taking end"
else
  fail "expected both clustered forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat "$file-c"' \
  'stat foo-c')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a -c inside an operand is not mistaken for stat's format option"
else
  fail "operands containing -c must not be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh 'stat "$f" -c %s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a -c after an operand should still fail, got success: $out"
else
  ok "a -c that does begin an argument after an operand is still detected"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'sort --version-sort "$file"' \
  'sort --sort=version "$file"' \
  'sort --sort version "$file"' \
  'sort --sort='"'"'version'"'"' "$file"' \
  'x=$(sort --sort=version)' \
  'git tag --sort=version:refname --list')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "sort long forms should fail under the shipped list, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 5 ]] &&
  ! grep -q "PORTABILITY: ${f}:6:" <<<"$out"; then
  ok "the shipped list detects every sort long form and spares git tag --sort=<key>"
else
  fail "expected hits on lines 1-5 only, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'x=$(sort -V)' \
  'sort -V|head -n1' \
  'x=$(grep -P)' \
  'grep -P|head -n1' \
  'x=$(echo -e)' \
  'echo -e|cat')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "operator-terminated sort -V/grep -P/echo -e should fail under the shipped list, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 6 ]]; then
  ok "the shipped list detects every operator-terminated sort -V/grep -P/echo -e form"
else
  fail "expected all 6 operator-terminated forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 't=$(mktemp -p "$d")')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "shipped list should flag mktemp -p now that it is active: $out"
else
  ok "shipped list flags mktemp -p (active class, #1527)"
fi
rm -f "$f"

f="$(tmpsh 't=$(mktemp -dp "$d" tmp.XXXXXX)')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "shipped list should flag mktemp -dp combined cluster: $out"
else
  ok "shipped list flags mktemp -dp combined short-option cluster"
fi
rm -f "$f"

f="$(tmpsh 't=$(mktemp "$d/tmp.XXXXXX")')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "the portable mktemp \"\$DIR/template\" form (no -p) is not flagged"
else
  fail "the portable mktemp form should not be flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'mktemp -p/tmp name.XXXXXX' \
  'mktemp -prel/sub name.XXXXXX' \
  'mktemp --tmpdir=/tmp name.XXXXXX' \
  'mktemp --tmpdir name.XXXXXX')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "attached -p<DIR> and --tmpdir spellings should be flagged, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "the shipped list flags both attached -p<DIR> forms and both --tmpdir spellings"
else
  fail "expected all 4 parent-directory spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'tmp=$(mktemp); cp -p source "$tmp"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "cp -p after a portable mktemp on the same line is not flagged"
else
  fail "a later command's -p must not be attributed to mktemp, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'tmp=`mktemp` cp -p source target')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "cp -p after a backtick-substituted portable mktemp is not flagged"
else
  fail "a closing backtick must end the option scan, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'tmp=`mktemp -p "$d"`')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "mktemp -p inside a backtick substitution must still be flagged: $out"
else
  ok "mktemp -p inside a backtick substitution is still flagged"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'mktemp_wrapper -p /tmp' \
  'my_mktemp -p /tmp' \
  'mktempfoo -p /tmp' \
  'safe-mktemp -p /tmp' \
  'my.mktemp -p /tmp' \
  'safe+mktemp -p /tmp' \
  'safe@mktemp --tmpdir=/tmp' \
  'safe-mktemp --tmpdir=/tmp' \
  'xmktemp --tmpdir=/tmp')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "commands whose name merely contains mktemp are not flagged"
else
  fail "mktemp's tokens must not match a different command's name, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'mktemp -p /tmp' \
  'cd /tmp && mktemp -p sub' \
  't=$(mktemp --tmpdir=/tmp)' \
  '/usr/bin/mktemp -p /tmp' \
  '"/usr/bin/mktemp" -p /tmp' \
  "'mktemp' --tmpdir /tmp")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "the anchored tokens must still flag real mktemp calls, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 6 ]]; then
  ok "the anchored tokens flag mktemp at a line start, after &&, in \$(), by path and quoted"
else
  fail "expected all 6 anchored mktemp positions flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh '\mktemp -p /tmp')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "backslash-escaped mktemp must still be flagged: expected failure, got success"
else
  ok "backslash-escaped mktemp -p is flagged"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'x=$(sed -Ei)' \
  'sed -Ei|cat' \
  'sed -Ei; echo done' \
  'x=$(sed --in-place)' \
  'sed --in-place|cat' \
  'sed --in-place; echo done')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "operator-terminated sed -Ei/--in-place should fail under the shipped list, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 6 ]]; then
  ok "the shipped list detects every operator-terminated sed -Ei/--in-place form"
else
  fail "expected all 6 operator-terminated forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "sed -n 'p' \"\$file\"; grep -Ei pattern \"\$file\"" \
  "sed -n 'p' \"\$file\" && tool --in-place x")")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the shipped list scopes both sed gaps to the sed command's own segment"
else
  fail "a later command's -Ei/--in-place must not fire the shipped sed tokens: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'sed -f <(gen_script) -i "$file"' \
  'sed -f <(gen_script) -Ei "$file"' \
  'sed -f <(gen_script) --in-place "$file"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a process substitution must not hide a GNU-only sed call, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "the shipped list still detects sed calls whose flag follows a process substitution"
else
  fail "expected all 3 process-substitution forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat -- -c' \
  'date -- -d' \
  'stat "--" -c' \
  "stat '--' -c" \
  'stat \-\- -c' \
  "stat \$'--' -c" \
  'date -u -- -d tomorrow' \
  'mktemp -- -p /tmp')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a flag-shaped operand after -- (any quote spelling) is not reported"
else
  fail "an operand demoted by -- must not be reported, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'printf "%s\n" "$(stat -- -c)"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "a -- inside a quoted substitution demotes the nested option"
else
  fail "the nested marker must reach the nested invocation, got: $out"
fi
rm -f "$f"

for line in \
  'stat "a -- b" -c %s' \
  'stat "-- x" -c %s' \
  'stat $marker -c %s' \
  "stat \$'\\055\\055' -c %s" \
  'stat > -- -c "%s" "$f"' \
  'date 3>-- -d tomorrow' \
  'date --utc -d @0' \
  'stat "$(printf "%s" x --)" -c "%s" "$f"' \
  'grep "$(printf -- x)" -P file'; do
  f="$(tmpsh "$line")"
  if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
    fail "an ambiguous marker shape must keep reporting: $line"
  else
    ok "no suppression from an ambiguous marker shape: $line"
  fi
  rm -f "$f"
done

f="$(tmpsh "grep -- '\\bfoo' file")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a \\b pattern after -- should still fail, got success: $out"
else
  ok "a regex-escape operand is not demoted by --"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat -- -c; stat -c "%s" "$g"' \
  'date -- -d; date -d tomorrow')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a real call after a -- operand should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a GNU-only call after a -- operand is still reported on both classes"
else
  fail "expected both later invocations flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' -- \"\$g\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a real -c before -- should still fail, got success: $out"
else
  ok "a genuine option before -- is still detected"
fi
rm -f "$f"

for line in \
  'grep -P pattern -- -P' \
  'sort -V -- -V' \
  'stat -c "%s" -- -c' \
  'mktemp -p /tmp -- -p'; do
  f="$(tmpsh "$line")"
  if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
    fail "a real option before -- must fail despite a demoted twin after it: $line"
  else
    ok "a real option before -- is reported past its demoted twin: $line"
  fi
  rm -f "$f"
done

f="$(tmpsh "$(printf '%s\n' \
  'stat -c "%s" "$f" || command stat -f "%z" "$f"' \
  'stat -c "%s" "$f" || env stat -f "%z" "$f"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a BSD fallback wrapped in command/env is recognized as a real ladder"
else
  fail "command- and env-wrapped stat -f fallbacks must not be flagged"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$a\"; stat -c '%s' \"\$b\" || stat -f '%z' \"\$b\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an unguarded first call should fail, got success: $out"
else
  ok "a later guarded ladder no longer excuses an unguarded call before it"
fi
rm -f "$f"

f="$(tmpsh 'realpath "$1" 2>/dev/null || readlink -f "$1"')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the realpath || readlink -f ladder is still auto-guarded after segmentation"
else
  fail "the backward-looking readlink guard must survive segmentation"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "stat 'name;part' -c '%s'" \
  "date 'a;b' -d @0")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an option after a quoted separator should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a quoted shell separator in an operand no longer hides the option after it"
else
  fail "expected both quoted-separator forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  '"date" -d tomorrow' \
  '"date" --date=now' \
  "'stat' -c '%s' \"\$f\"" \
  '"/usr/bin/stat" -c "%s" "$f"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "quoted command words should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "a quoted or path-qualified date/stat command word is detected"
else
  fail "expected all 4 quoted command-word forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "grep -E '\\\\bword' file" \
  'sort -V list')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "quoted GNU regex escapes should still fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "GNU escape classes inside string literals still match after masking"
else
  fail "expected the quoted-escape and sort -V forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'printf -- "%s\n" "$(stat -c "%s" "$g")"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a nested stat -c under an outer -- should fail, got success: $out"
else
  ok "an outer -- does not hide a GNU-only call inside a substitution"
fi
rm -f "$f"

f="$(tmpsh 'x=$(stat -c "%s" "$g"; true) || stat -f "%z" "$g"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a substitution whose status comes from a later command should fail, got success: $out"
else
  ok "an inner command list no longer lets an outer || excuse the GNU call"
fi
rm -f "$f"

f="$(tmpsh 'x=$(stat -c "%s" "$g") || y=$(stat -f "%z" "$g")')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the substitution-wrapped stat ladder is still auto-guarded"
else
  fail "the command-substitution fallback ladder must not be flagged"
fi
rm -f "$f"

f="$(tmpsh 'size=`stat -c "%s" "$g"` || size=`stat -f "%z" "$g"`')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the backquoted stat ladder is auto-guarded too"
else
  fail "the backquote fallback ladder must not be flagged"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stamp=`date +%s` test -d "$dir"' \
  'meta=`stat "$file"` tool -c x')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a closing backquote bounds the command segment"
else
  fail "a later command option must not cross a closing backquote"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat -c "%s" "$g" &>/dev/null || stat -f "%z" "$g"' \
  'stat -c "%s" "$g" &>>log || stat -f "%z" "$g"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "bash &> and &>> are read as redirections, not as a background separator"
else
  fail "&> and &>> must not disconnect a genuine BSD fallback"
fi
rm -f "$f"

f="$(tmpsh 'stat -c "%s" "$g" & true || stat -f "%z" "$g"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a backgrounded GNU call should fail, got success: $out"
else
  ok "a lone control & still separates the GNU call from the later ||"
fi
rm -f "$f"

f="$(tmpsh 'stat -c "%s" "$g" || stat -f "%z" "$g"')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a real BSD -f counterpart is recognized as the fallback"
else
  fail "the plain stat -f ladder must not be flagged"
fi
rm -f "$f"

for line in \
  'stat -c "%s" "$g" || stat -- -f' \
  'stat -c "%s" "$g" || stat "--" -f' \
  'stat -c "%s" "$g" || y=$(stat -- -f)' \
  'stat -c "%s" "$g" || stat "$g" -f "%z"' \
  'stat -c "%s" "$g" || stat -tf "%z" "$g"' \
  'stat -c "%s" "$g" || stat -f' \
  'stat -c "%s" "$g" || stat -f # comment, not a format'; do
  f="$(tmpsh "$line")"
  if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
    fail "a fallback whose -f is not a parsed option must be rejected: $line"
  else
    ok "unprovable fallback rejected (trusted side): $line"
  fi
  rm -f "$f"
done

for line in \
  'stat -c "%s" "$g" || stat -Lf "%z" "$g"' \
  'stat -c "%s" "$g" || stat -f%z "$g"' \
  'stat -c "%s" "$g" || stat -t "%Y" -f "%z" "$g"' \
  'stat -c "%s" "$g" || stat -Ht "%Y" -f "%z" "$g"'; do
  f="$(tmpsh "$line")"
  if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
    ok "provable fallback still guarded: $line"
  else
    fail "a genuine BSD fallback spelling must stay guarded: $line"
  fi
  rm -f "$f"
done

f="$(tmpsh 'stat -c "%s" "$g" || stat -t -f "%z" "$g"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a -f consumed by a detached -t must be rejected, got success: $out"
else
  ok "a -f in a detached -t's argument slot is not a parsed option"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat "$(get_file)" -c %s' \
  'date "$(get_when)" -d tomorrow' \
  'stat "$(dirname "$(x)")" -c %s')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an option after a substitution operand should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "an option after a command-substitution operand is detected, nesting included"
else
  fail "expected all 3 substitution-operand forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat -c %s "$f" || x=$(stat -f %z "$f")' \
  'x=$(stat -c %s "$f") || x=$(stat -f %z "$f")')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a ladder whose BSD side sits inside a substitution stays guarded"
else
  fail "the guard must read the uncollapsed line: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat ${file:-name;part} -c %s' \
  'date ${when:-a;b} -d tomorrow')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a separator inside an expansion should not hide the option, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a separator inside a parameter expansion no longer ends the command"
else
  fail "expected both expansion forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat "${file}"; tool -c x' \
  'date "${when}"; test -d "$dir"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a separator after an expansion still bounds the command"
else
  fail "an expansion must not neutralize the operator after it: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh 'x="${y:-$(stat -c %s "$f")}"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a stat -c inside an expansion default should fail, got success: $out"
else
  ok "a substitution nested in a parameter expansion is still scanned"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date "-d" tomorrow +%s' \
  'date -"d" tomorrow +%s' \
  'stat "-c" %s "$f"' \
  'stat -"c" %s "$f"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "quoted option words should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 4 ]]; then
  ok "a quoted date/stat option word is detected"
else
  fail "expected all 4 quoted option-word forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'stat "-c" %s "$f" || stat -f %z "$f"' \
  'stat -"c" %s "$f" || stat -f %z "$f"' \
  'stat -c %s "$f" || stat "-f" %z "$f"' \
  'stat -c %s "$f" || stat -"f" %z "$f"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a quoted flag on either side of the ladder is still a real fallback"
else
  fail "a quoted-flag ladder must stay guarded: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "date \\" \
  '  -d tomorrow +%s' \
  "stat \\" \
  '  -c %s "$f"' \
  'grep -P pattern file')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a continued GNU-only invocation should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]] &&
  grep -q "PORTABILITY: ${f}:1:" <<<"$out" &&
  grep -q "PORTABILITY: ${f}:3:" <<<"$out" &&
  grep -q "PORTABILITY: ${f}:5:" <<<"$out"; then
  ok "a backslash-continued invocation is matched as one command at its first line"
else
  fail "expected hits at lines 1, 3 and 5, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "date \\" \
  "  -d @0 \\")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a trailing continued command should fail, got success: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "a continuation left open at end of file is still scanned"
else
  fail "expected the buffered command reported at line 1, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "# explains date -d below \\" \
  'date -d tomorrow +%s')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "the command under a backslash-ended comment should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 1 ]] &&
  grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "a trailing backslash in a comment does not continue into the next line"
else
  fail "expected exactly the line-2 call reported, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "printf '%s' a\\\\" \
  'date -d @0')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "the standalone date -d should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 1 ]] &&
  grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "an escaped backslash at end of line is not a line continuation"
else
  fail "expected exactly the line-2 call reported, got: $out"
fi
rm -f "$f"

# --- a `portability-ok:` marker anywhere in the joined command excuses it
f="$(tmpsh "$(printf '%s\n' \
  "date \\" \
  '  -d @0 # portability-ok: dual-dialect helper')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "an annotation on a continuation line excuses the whole logical command"
else
  fail "the marker must apply to the joined command: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "echo ok # portability-ok: unrelated \\" \
  'date -d tomorrow +%s')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "the command under a backslash-ended inline comment should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 1 ]] &&
  grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "a trailing backslash in an INLINE comment does not continue into the next line"
else
  fail "expected exactly the line-2 call reported, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'stat -c "%s" "$f" # || stat -f "%z" "$f"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a commented-out stat -f fallback should fail, got success: $out"
else
  ok "a commented-out || fallback does not guard the GNU-only call"
fi
rm -f "$f"

f="$(tmpsh 'echo ok # see date -d tomorrow')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  fail "an inline comment naming date -d must still report"
else
  ok "comment masking does not disable construct matching inside an inline comment"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  '! x=$(stat -c "%s" "$f") || stat -f "%z" "$f"' \
  '! x=`stat -c "%s" "$f"` || stat -f "%z" "$f"' \
  '! ( stat -c "%s" "$f" ) || stat -f "%z" "$f"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a negated probe inside a substitution should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "an outer negation survives a substitution or subshell boundary"
else
  fail "expected all three negated-probe spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'x=$(! stat -c "%s" "$f") || stat -f "%z" "$f"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a negation inside the substitution should fail, got success: $out"
else
  ok "a negation inside the substitution is still detected"
fi
rm -f "$f"

f="$(tmpsh '[[ ! -f "$x" ]] && stat -c "%s" "$f" || stat -f "%z" "$f"')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a ! inside a test does not read as pipeline negation"
else
  fail "the ladder must stay guarded: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date>/dev/null -d tomorrow' \
  'stat</dev/null -c %s "$f"' \
  'date>&2 -d tomorrow')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an attached redirection should not hide the option, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "a redirection attached to the command word no longer hides the option"
else
  fail "expected all three attached-redirection forms flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'git -c alias.x=status -c core.pager=cat log' \
  '[[ -d "$candidate" ]]' \
  'stat foo-c' \
  'stat "$file-c"' \
  'date "$x-d"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "widening the separator to a redirection keeps the operand negatives clean"
else
  fail "no operand/substring form may be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "stat -c '%s' \"\$f\" || (stat -f '%z' \"\$f\")" \
  "stat -c '%s' \"\$f\" || { stat -f '%z' \"\$f\"; }")")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a grouped BSD fallback after || is recognized as a real ladder"
else
  fail "grouped stat -f fallbacks must not be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "echo \"\$(stat -c '%s' \"\$f\")\" || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a substitution used as an argument should not guard, got success: $out"
else
  ok "a stat inside a substitution ARGUMENT does not reach the || that follows"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'x=$(stat -c "%s" "$f") || y=$(stat -f "%z" "$f")' \
  'x=$(stat -c "%s" "$1" 2>&1) || y=$(stat -f "%z" "$1")' \
  "size=\`stat -c '%s' \"\$f\"\` || size=\`stat -f '%z' \"\$f\"\`")")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "an assignment-wrapped ladder still propagates the status and stays guarded"
else
  fail "assignment-wrapped ladders must not be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$f\" || {stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a brace with no following blank is not a group, got success: $out"
else
  ok "a { with no following blank does not open a fallback group"
fi
rm -f "$f"

f="$(tmpsh '! 2>/dev/null stat -c "%s" "$f" || stat -f "%z" "$f"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a negation behind a prefix redirection should fail, got success: $out"
else
  ok "a prefix redirection does not hide the negation before the command name"
fi
rm -f "$f"
f="$(tmpsh "stat -c '%s' \"\$f\" || 2>/dev/null stat -f '%z' \"\$f\"")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a prefix redirection on the fallback keeps it a real ladder"
else
  fail "the redirected fallback must stay guarded: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh 'stat ${f:-"};part"} -c %s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a quoted brace inside an expansion should not hide the option, got success: $out"
else
  ok "a quoted } inside a parameter expansion does not close it early"
fi
rm -f "$f"
f="$(tmpsh 'x="${y:-$(stat -c %s "$f")}"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a substitution inside an expansion must still be scanned, got success: $out"
else
  ok "a \$( ) inside a parameter expansion still reopens real command text"
fi
rm -f "$f"

f="$(tmpsh "(stat -c '%s' \"\$f\")# || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a comment after ) should not leave the || structural, got success: $out"
else
  ok "a # straight after a closing paren opens a comment"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "stat -c '%s' \"\$f\" || { echo 'stat -f is unavailable'; }" \
  "stat -c '%s' \"\$f\" || ( true; stat -f '%z' \"\$f\" )")")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a group that does not run stat -f first should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a group opener does not excuse a fallback the group does not run first"
else
  fail "expected both non-ladder groups flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'stat ${x:-$((1 | 2))} -c %s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a nested arithmetic expansion should not hide the option, got success: $out"
else
  ok "a \$(( )) inside an expansion does not unbalance the frame stack"
fi
rm -f "$f"
f="$(tmpsh 'date -d "@$(( now + 1 ))" +%s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an arithmetic expansion in an operand must not hide the option, got success: $out"
else
  ok "an arithmetic expansion in an operand still leaves the option visible"
fi
rm -f "$f"
f="$(tmpsh 'stat "$(( ((1)) + 2 ))" -c %s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a nested paren group must not close the expansion early, got success: $out"
else
  ok "an inner ( ) group does not close an arithmetic expansion early"
fi
rm -f "$f"

f="$(tmpsh "x=\$(stat -c '%s' \"\$f\") y=\$(true) || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a later sibling substitution owns the status, so this is no ladder: $out"
else
  ok "a later substitution BESIDE the matched frame breaks the ladder"
fi
rm -f "$f"
f="$(tmpsh "x=\$(stat -c '%s' \"\$f\") y=1 || stat -f '%z' \"\$f\"")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a plain assignment beside the frame leaves the ladder intact"
else
  fail "a non-substitution assignment must not break the ladder: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"
f="$(tmpsh "x=\$(stat -c \"\$(fmt)\" \"\$f\") || stat -f '%z' \"\$f\"")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a frame nested inside the matched one does not take the status"
else
  fail "a nested frame must not read as a sibling: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh 'd"a"te -d tomorrow')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a quote-spliced date command word should fail, got success: $out"
else
  ok "a quote-spliced date command word is detected"
fi
rm -f "$f"
f="$(tmpsh 'st"a"t -c %s "$f"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a quote-spliced stat command word should fail, got success: $out"
else
  ok "a quote-spliced stat command word is detected"
fi
rm -f "$f"
f="$(tmpsh "$(printf '%s\n' \
  '"sed" -i '\''s/x/y/'\'' file' \
  's"e"d -ni p file')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "quoted or quote-spliced sed command words should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "a quoted or quote-spliced sed command word is detected"
else
  fail "expected both quoted sed command-word forms flagged, got: $out"
fi
rm -f "$f"
f="$(tmpsh '"sed" --in-place '\''s/x/y/'\'' file')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a quoted sed command word with --in-place should fail, got success: $out"
else
  ok "a quoted sed command word with --in-place is detected"
fi
rm -f "$f"
f="$(tmpsh "st\"a\"t -c '%s' \"\$f\" || st\"a\"t -f '%z' \"\$f\"")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a quote-spliced BSD fallback still reads as a real ladder"
else
  fail "the guard must see the spliced fallback: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"
f="$(tmpsh "$(printf '%s\n' \
  'printf "%s" "d" "a" "te -d x"' \
  'git -c alias.x=status -c core.x=1 diff' \
  '[[ -d "$candidate" ]] && echo yes')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "interleaved quote runs do not span separate words or longer names"
else
  fail "the spliced-name spelling over-reached: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"
f="$(tmpsh "$(printf '%s\n' \
  'x"sed" -i value' \
  'u"sed" --in-place x')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a quoted sed suffix inside a longer shell word is not flagged"
else
  fail "quoted sed suffix inside a longer word must not fire: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat %s\nbar%s -c %%s\n' "'foo" "'" >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a quoted newline should not hide the option, got success: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "a quoted word spanning physical lines still reaches its option"
else
  fail "expected the hit at line 1, got: $out"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'x=%sopen\nstat -c %%s "$f"\ndate -d @0 +%%s # portability-ok: fixture\nclose%s\n' "'" "'" >"$f"
out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
if grep -q "PORTABILITY: ${f}:2:" <<<"$out" &&
  ! grep -q "PORTABILITY: ${f}:3:" <<<"$out"; then
  ok "a joined record reports per physical line and scopes its annotation there"
else
  fail "expected line 2 flagged and line 3 excused, got: $out"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'cat >/dev/null <<%sEOF%s\n"CustomRule%sPath" = %s./x%s\nEOF\ngrep -q %sneedle%s "$f"\nprintf "%%s" "x -Path y"\n' \
  "'" "'" '`' "'" "'" "'" "'" >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a heredoc body does not leak an open frame into the lines after it"
else
  fail "heredoc body leaked quote state: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'cat >/tmp/gen.sh <<%sEOF%s\nstat -c %%s "$f"\nEOF\n' "'" "'" >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a heredoc body must still be scanned, got success: $out"
else
  ok "a heredoc body is still scanned for constructs"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'x=$(stat -c %%s "$f"\n# || stat -f %%z "$f"\n)\n' >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a commented-out fallback in a joined record should not guard: $out"
else
  ok "a # opening a joined physical line still starts a comment"
fi
rm -f "$f"
TOK="$(one_token_list 'grep[[:space:]]+-P')"
fixture_tree::build TREE --sut "$SCRIPT"
mkdir -p "$TREE/plugins/demo/hooks"
printf 'hooks/hook-utils.sh\n' >"$TREE/scripts/cross-plugin-source-registry.txt"
printf 'grep -P x\n' >"$TREE/plugins/demo/hooks/hook-utils.sh"
printf 'grep -P x\n' >"$TREE/plugins/demo/hooks/not-registered.sh"
out="$(SHELL_PORTABILITY_TOKENS="$TOK" bash "$TREE/scripts/check-shell-portability.sh" --all 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"not-registered.sh"* && "$out" != *"hook-utils.sh"* ]]; then
  ok "a registered sync copy (plugins/*/hooks/hook-utils.sh) is exempt while an unregistered sibling still flags"
else
  fail "registered-sync-copy exemption: rc=$rc out=$out"
fi
rm -rf "$TREE"
rm -f "$TOK"

TOK="$(one_token_list 'grep[[:space:]]+-P')"
fixture_tree::build TREE --sut "$SCRIPT"
mkdir -p "$TREE/plugins/demo/hooks"
printf 'hooks/*.sh\n' >"$TREE/scripts/cross-plugin-source-registry.txt"
printf 'grep -P x\n' >"$TREE/plugins/demo/hooks/hook-utils.sh"
out="$(SHELL_PORTABILITY_TOKENS="$TOK" bash "$TREE/scripts/check-shell-portability.sh" --all 2>&1)"
rc=$?
if [[ $rc -ne 0 && "$out" == *"hook-utils.sh"* ]]; then
  ok "a glob-shaped registry entry exempts nothing (literal comparison)"
else
  fail "glob registry entry silently exempted a scannable file: rc=$rc out=$out"
fi
rm -rf "$TREE"
rm -f "$TOK"

fixture_tree::build TREE --label shell-portability-tree
printf 'grep[[:space:]]+-P\n' >"$TREE/tokens=custom.txt"
f="$(tmpsh 'grep -P x')"
if (
  cd "$TREE" || exit 2
  SHELL_PORTABILITY_TOKENS='tokens=custom.txt' bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
); then
  fail "an identifier=value token path silently disabled every class"
else
  ok "an identifier=value token path is opened as a file, not read as an assignment"
fi
rm -rf "$TREE"
rm -f "$f"

TOK="$(mktemp "$TMP_ROOT/f.XXXXXX")"
printf '# only a comment, no active pattern\n' >"$TOK"
f="$(tmpsh 'grep -P x')"
out="$(scan_paths "$TOK" "$f" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"no active patterns"* ]]; then
  ok "an empty pattern set fails closed instead of reporting clean"
else
  fail "empty pattern set did not fail closed: rc=$rc out=$out"
fi
rm -f "$TOK" "$f"

out="$(awk -f "$SCAN_AWK" /dev/null 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"no active patterns"* ]]; then
  ok "the scanner program compiles and reaches END (awk -f, /dev/null)"
else
  fail "scanner program did not compile or did not reach END: rc=$rc out=$out"
fi

tok="$(one_token_list 'grep[[:space:]]+-P')"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'echo first\ngrep -P x\n' >"$f"
out="$(awk -f "$SCAN_AWK" "$tok" "$f" 2>&1)"
rc=$?
if [[ $rc -eq 0 && "$out" == '2: grep[[:space:]]+-P -> grep -P x' ]]; then
  ok "the scanner program runs on its two operands alone and prints LINE: token -> text"
else
  fail "direct two-operand run: rc=$rc out=$out"
fi
rm -f "$tok" "$f"

fixture_tree::build TREE --sut "$SCRIPT"
rm -f "$TREE/scripts/lib/shell-portability-scan.awk"
f="$(tmpsh 'grep -P x')"
out="$(bash "$TREE/scripts/check-shell-portability.sh" --paths "$f" 2>&1)"
rc=$?
if [[ $rc -eq 2 && "$out" == *"scanner program not found"* ]]; then
  ok "a missing scanner program fails the gate closed, naming the path"
else
  fail "missing scanner program did not fail closed: rc=$rc out=$out"
fi
rm -rf "$TREE"
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date&>/dev/null -d tomorrow' \
  'stat&>>log -c %s "$f"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "ampersand redirections after the command name should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "an ampersand redirection after the command name does not hide the option"
else
  fail "expected both ampersand spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'da\te -d tomorrow' \
  'date -\d tomorrow')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "backslash-quoted date words should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 2 ]]; then
  ok "backslash quoting is recognized in the command word and the option"
else
  fail "expected both backslash spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'date "--date" tomorrow' \
  'date --"date"=tomorrow' \
  'stat --"format"=%s "$f"')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "quote-spliced long options should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 3 ]]; then
  ok "a quote-spliced long option is detected on either side of the --"
else
  fail "expected all three long-option spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh 'x="$( (true); stat -c %s "$f"; true)" || stat -f %z "$f"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a trailing true owns the status, so this is no ladder: $out"
else
  ok "a raw subshell inside a substitution does not pop the enclosing frame"
fi
rm -f "$f"
f="$(tmpsh 'case "$x" in foo) stat -c %s "$f" ;; esac')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a case pattern terminator must not swallow the option, got success: $out"
else
  ok "a case pattern terminator still opens no frame"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'x=$(stat -c %%s "$f"\ntrue) || stat -f %%z "$f"\n' >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a later command on a newline owns the status, so this is no ladder: $out"
else
  ok "a structural newline inside a substitution breaks the ladder"
fi
rm -f "$f"

f="$(tmpsh "stat -c '%s' \"\$f\" || 2> /dev/null stat -f '%z' \"\$f\"")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a spaced redirection operand keeps the fallback a real ladder"
else
  fail "the spaced-redirection ladder must stay guarded: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'cat >/tmp/gen.sh <<%sEOF%s\n# portability-scope: generated fixture\nEOF\nstat -c %%s "$f"\n' \
  "'" "'" >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a heredoc-body scope line must not exempt the file, got success: $out"
else
  ok "a portability-scope line inside a heredoc body exempts nothing"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s "$f"\n# portability-scope: this file is a fixture corpus\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a genuine portability-scope declaration still exempts the whole file"
else
  fail "the file-scope declaration stopped working: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  "d\$'a'te -d tomorrow" \
  "date -\$'d' tomorrow" \
  "st\$'a't -c %s \"\$f\"" \
  "stat -\$'c' %s \"\$f\"" \
  'date $"--date"=tomorrow')")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "ANSI-C quote splices should fail, got success: $out"
elif [[ "$(echo "$out" | grep -c "PORTABILITY: ${f}:")" -eq 5 ]]; then
  ok "ANSI-C and locale quote splices are detected in the name and the option"
else
  fail "expected all five ANSI-C spellings flagged, got: $out"
fi
rm -f "$f"

f="$(tmpsh "$(printf '%s\n' \
  'validate -d $config' \
  'd$a$t$e -d tomorrow')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a bare \$ is not admitted as a quote-run character"
else
  fail "a bare \$ was treated as quote removal: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

for opener in "x='foo" 'y="foo' 'z=$(echo foo'; do
  case "$opener" in
  "x='foo") closer="bar'" ;;
  'y="foo') closer='bar"' ;;
  *) closer=')' ;;
  esac
  f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
  printf '%s\n' "$opener" '# portability-scope: bogus' "$closer" 'date -d tomorrow' >"$f"
  if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
    fail "a scope marker inside an open construct ($opener) must exempt nothing: $out"
  else
    ok "a scope marker inside an open construct ($opener) grants no file scope"
  fi
  rm -f "$f"
done

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf '%s\n' 'date -d tomorrow' '  # portability-scope: this file is a fixture corpus' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "an indented declaration after the hit still exempts the whole file"
else
  fail "the file-scope declaration stopped working: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s $(\\\n(1 | 2)) || stat -f %%z f\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a \$(( split by a line continuation is still one arithmetic expansion"
else
  fail "a continuation inside \$(( broke a real ladder: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s $((1 | 2)) || stat -f %%z f\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the same ladder without the continuation is clean too"
else
  fail "the uncontinued control ladder must stay clean: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'v=$(true  # note\nstat -c %%s "$f" || stat -f %%z "$f")\n' >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a ladder inside a comment's shadow should fire, got success: $out"
elif grep -q "PORTABILITY: ${f}:2:" <<<"$out"; then
  ok "an inline comment keeps masking across a join, so its || is not a guard"
else
  fail "expected the line-2 call reported, got: $out"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'v=$(true\nstat -c %%s "$f" || stat -f %%z "$f")\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the same joined ladder without the comment is a real ladder"
else
  fail "the uncommented control must stay clean: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

tok="$(one_token_list '!subst-replacement-ampersand')"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'a="${x//p/&} one\n${y//q/${z//r/&}} two"\n' >"$f"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an & in a joined record should fire, got success: $out"
elif grep -q "PORTABILITY: ${f}:1: !subst-replacement-ampersand" <<<"$out"; then
  ok "an expansion closed before the commit point is still reported, at line 1"
else
  fail "expected the earliest & frame reported at line 1, got: $out"
fi
rm -f "$f" "$tok"

f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s "$f" $(( (1 +\n2)) || stat -f %%z "$f"\n' >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a || inside an unterminated arithmetic expansion should not guard: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "an inner ( ) open across a join keeps the arithmetic expansion open"
else
  fail "expected the line-1 call reported, got: $out"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s "$f" $(( (1 + 2)) || stat -f %%z "$f"\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  fail "the unjoined control must report the same unguarded call"
else
  ok "the same arithmetic expansion on one line reports the same call"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s "$f" $(printf %%s $(( (1 +\n2)) ) || stat -f %%z "$f"\n' >"$f"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a nested arithmetic frame should keep its depth across the join: $out"
elif grep -q "PORTABILITY: ${f}:1:" <<<"$out"; then
  ok "arithmetic depth is held per frame, one frame deeper included"
else
  fail "expected the line-1 call reported, got: $out"
fi
rm -f "$f"
f="$(mktemp --suffix=.sh "$TMP_ROOT/f.XXXXXX")"
printf 'stat -c %%s "$f" $(printf %%s $(( (1 + 2)) ) || stat -f %%z "$f"\n' >"$f"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  fail "the unjoined nested control must report the same unguarded call"
else
  ok "the nested shape on one line reports the same call"
fi
rm -f "$f"

probe_dir="$(mktemp -d "$TMP_ROOT/d.XXXXXX")"
mkdir -p "$probe_dir/bin"
printf '#!/usr/bin/env bash\n[[ "${1:-}" == --version ]] && { echo "fake-a 1"; exit 0; }\nexit 0\n' >"$probe_dir/bin/fake-a"
printf '#!/usr/bin/env bash\n[[ "${1:-}" == --version ]] && { echo "fake-b 1"; exit 0; }\nexit 3\n' >"$probe_dir/bin/fake-b"
printf '#!/usr/bin/env bash\n[[ "${1:-}" == --version ]] && { echo "fake-a 1"; exit 0; }\nexit 0\n' >"$probe_dir/bin/fake-a-alias"
chmod +x "$probe_dir/bin/"*
printf 'awk "BEGIN { exit 0 }"\n' >"$probe_dir/calls-awk.test.sh"
printf 'exit 4\n' >"$probe_dir/always-fails.test.sh"
printf 'exit 0\n' >"$probe_dir/no-awk.test.sh"

probe() {
  PATH="$probe_dir/bin:$PATH" SHELL_PORTABILITY_AWKS="$1" bash "$SCRIPT" --awk-probe "${@:2}"
}

out="$(probe "fake-a fake-b" "$probe_dir/calls-awk.test.sh" 2>&1)"
rc=$?
if ((rc == 1)) && [[ "$out" == *"DIVERGENT: $probe_dir/calls-awk.test.sh: fake-a=0 fake-b=3"* ]]; then
  ok "--awk-probe reports a suite whose exit differs between two awks as DIVERGENT and exits 1"
else
  fail "--awk-probe should report DIVERGENT and exit 1, got rc=$rc: $out"
fi
out="$(probe "fake-a fake-b" "$probe_dir/no-awk.test.sh" 2>&1)"
rc=$?
if ((rc == 0)) && [[ "$out" == *"ok: $probe_dir/no-awk.test.sh: fake-a=0 fake-b=0"* ]]; then
  ok "--awk-probe passes a suite that agrees under every awk"
else
  fail "--awk-probe should pass an agreeing suite, got rc=$rc: $out"
fi
out="$(probe "fake-a fake-b" "$probe_dir/always-fails.test.sh" 2>&1)"
rc=$?
if ((rc == 0)) && [[ "$out" == *"FAILS UNDER EVERY AWK (not a divergence)"* ]]; then
  ok "--awk-probe names a suite failing under every awk without calling it a divergence"
else
  fail "--awk-probe should name a uniform failure and exit 0, got rc=$rc: $out"
fi
out="$(probe "fake-a fake-a-alias" "$probe_dir/calls-awk.test.sh" 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"needs two distinct awk implementations"* ]]; then
  ok "--awk-probe fails closed when two names share one version banner"
else
  fail "--awk-probe should exit 2 on one distinct implementation, got rc=$rc: $out"
fi
out="$(probe "fake-a fake-b" "$probe_dir/missing.test.sh" 2>&1)"
rc=$?
if ((rc == 2)) && [[ "$out" == *"no such suite"* ]]; then
  ok "--awk-probe fails closed on a missing suite"
else
  fail "--awk-probe should exit 2 on a missing suite, got rc=$rc: $out"
fi
if bash "$SCRIPT" --awk-probe >/dev/null 2>&1; then
  fail "--awk-probe with no suite should be a usage error"
else
  ok "--awk-probe with no suite is a usage error"
fi

cat >"$probe_dir/awk-v-regex.test.sh" <<'EOF'
prefix_re='\]\([^)]*$'
got="$(printf 'see [doc](a/b' | awk -v prefix_re="$prefix_re" '{ print ($0 ~ prefix_re) ? "open" : "closed" }')"
[[ "$got" == open ]]
EOF
cat >"$probe_dir/awk-environ-regex.test.sh" <<'EOF'
prefix_re='\]\([^)]*$'
got="$(printf 'see [doc](a/b' | PREFIX_RE="$prefix_re" awk '{ print ($0 ~ ENVIRON["PREFIX_RE"]) ? "open" : "closed" }')"
[[ "$got" == open ]]
EOF
if command -v gawk >/dev/null 2>&1 && command -v mawk >/dev/null 2>&1; then
  out="$(SHELL_PORTABILITY_AWKS="gawk mawk" bash "$SCRIPT" --awk-probe "$probe_dir/awk-v-regex.test.sh" 2>&1)"
  rc=$?
  if ((rc == 1)) && [[ "$out" == *"DIVERGENT: $probe_dir/awk-v-regex.test.sh: gawk=1 mawk=0"* ]] &&
    [[ "$out" == *'ENVIRON["NAME"]'* ]]; then
    ok "--awk-probe catches a regex handed through awk -v (gawk fails, mawk passes)"
  else
    fail "--awk-probe should catch the awk -v regex fixture, got rc=$rc: $out"
  fi
  out="$(SHELL_PORTABILITY_AWKS="gawk mawk" bash "$SCRIPT" --awk-probe "$probe_dir/awk-environ-regex.test.sh" 2>&1)"
  rc=$?
  if ((rc == 0)) && [[ "$out" == *"ok: $probe_dir/awk-environ-regex.test.sh: gawk=0 mawk=0"* ]]; then
    ok "--awk-probe passes the same regex read through ENVIRON[]"
  else
    fail "--awk-probe should pass the ENVIRON fixture, got rc=$rc: $out"
  fi
elif [[ -n "${CI:-}" ]]; then
  fail "the awk -v fixture pair needs gawk and mawk on PATH, and CI must carry both"
else
  printf 'NOT RUN: the awk -v fixture pair needs gawk and mawk on PATH\n'
fi
rm -rf "$probe_dir"

test_harness::report

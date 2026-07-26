#!/usr/bin/env bash
# portability-scope: this suite IS check-shell-portability.sh's own fixture
# corpus and necessarily contains, as literal test data, the GNU-only
# constructs the gate detects (\b, unsuffixed sed -i, grep -P, etc.) — the
# whole-file declaration this gate itself defines (see the script header's
# escape #3), exercised on itself the way check-skill-portability.sh's own
# STAGED-class self-reference exercises its sibling mechanism.
#
# Unit tests for check-shell-portability.sh. Synthetic cases run through
# --paths mode with a minimal, class-scoped token list
# (SHELL_PORTABILITY_TOKENS) built per test so a fixture is never coupled to
# the shipping list's other active classes; two cases run against the REAL
# shipped token list and the REAL corpus — the known-good markdown-format.sh
# reference implementation, and the shipping list's staged-class inertness —
# to prove the shipping config, not just the mechanism.
#
# Bespoke PASS/FAIL counters by design, not drift: this is repo tooling, not a
# plugin, so no plugin assertion library applies here — see
# docs/conventions/shell-test-helpers/README.md.
# shellcheck disable=SC2016  # fixture bodies are literal shell content in single quotes; expansion is never wanted
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SELF_DIR/.." && pwd)"
SCRIPT="$SELF_DIR/check-shell-portability.sh"
REAL_TOKENS="$REPO_ROOT/scripts/shell-portability-tokens.txt"

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

# scan_paths <tokens-file> <file>... — run the gate over explicit paths.
scan_paths() {
  local tokens="$1"
  shift
  SHELL_PORTABILITY_TOKENS="$tokens" bash "$SCRIPT" --paths "$@"
}

# one_token_list <ere-pattern> — a temp token file with exactly one active
# pattern, so a synthetic case is not coupled to any other class.
one_token_list() {
  local f
  f="$(mktemp)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

tmpsh() {
  local f
  f="$(mktemp --suffix=.sh)"
  printf '%s\n' "$1" >"$f"
  printf '%s' "$f"
}

# =============================================================================
# Regex-escape classes (\b \< \> \s \S \w \W) — the exact near-miss family.
# =============================================================================

# --- literal \b fires, and awk actually resolves it (the repo's own sibling
# token list documents that on gawk AND mawk/nawk, \b matches a literal
# backspace BYTE, not a boundary, when used as a boundary anchor — verify the
# LITERAL-TWO-CHARACTER-SEQUENCE form this gate uses is not silently inert
# under whichever awk resolves on the runner) -------------------------------
tok="$(one_token_list '\\b')"
f="$(tmpsh "grep -Eq '\\brequire\\b' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "literal \\\\b in a grep pattern should fail, got success: $out"
elif echo "$out" | grep -q "PORTABILITY: ${f}:1:"; then
  ok "literal \\\\b in a grep pattern is detected (not silently inert)"
else
  fail "expected PORTABILITY with file:line, got: $out"
fi
rm -f "$f"

# --- the POSIX-portable bracket-expression replacement does NOT fire -------
f="$(tmpsh 'grep -Eq "(^|[^A-Za-z0-9_\$])require($|[^A-Za-z0-9_\$])" "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "the bracket-expression word-boundary replacement does not fire"
else
  fail "the POSIX-portable replacement must not be flagged"
fi
rm -f "$f"

# --- a pattern BUILT on one line and CONSUMED on another still fires. This
# is the shape a grep/sed-same-line context requirement silently un-catches,
# and it is live in this repo (instruction-scan.sh's I6_ERE/RATIONALE_ERE),
# so the class deliberately stays bare — see the token file's note. ---------
f="$(tmpsh "PAT=\"\\brequire\\b\"
grep -Eq \"\$PAT\" \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a \\\\b pattern assigned to a variable should fail, got success: $out"
elif echo "$out" | grep -q "PORTABILITY: ${f}:1:"; then
  ok "a \\\\b pattern built in a variable and used later is detected"
else
  fail "expected PORTABILITY on the assignment line, got: $out"
fi
rm -f "$f"

# --- the mirror-image cost of staying bare: portable printf escape syntax
# carrying the same two characters DOES fire (over-flag, the documented
# direction), and `portability-ok:` is the recorded one-line escape for it --
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

# --- \s \w \S \W \< \> each fire individually -------------------------------
for esc in '\\s' '\\S' '\\w' '\\W' '\\<' '\\>'; do
  tok="$(one_token_list "$esc")"
  f="$(tmpsh "sed -E 's/${esc}foo${esc}/bar/' \"\$file\"")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "literal $esc should fail, got success: $out"
  elif echo "$out" | grep -q "PORTABILITY:"; then
    ok "literal $esc is detected"
  else
    fail "expected PORTABILITY for $esc, got: $out"
  fi
  rm -f "$f" "$tok"
done

# =============================================================================
# grep -P / --perl-regexp
# =============================================================================

tok="$(one_token_list 'grep[^\n]*[[:space:]]-[A-Za-z]*P[A-Za-z]*([[:space:]]|$)')"

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

# --- P need not be the LAST letter in the flag cluster --------------------
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

# =============================================================================
# echo -e / sort -V
# =============================================================================

tok="$(one_token_list 'echo[[:space:]]+-[a-zA-Z]*e[a-zA-Z]*([[:space:]]|$)')"

f="$(tmpsh 'echo -e "line1\nline2"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "echo -e should fail, got success: $out"
else
  ok "echo -e is detected"
fi
rm -f "$f"

# --- e need not be the only letter in the cluster ("echo -ne") -------------
f="$(tmpsh "echo -ne 'a\\nb'")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "echo -ne (combined flags) should fail"
else
  ok "echo -ne (combined flags) is detected"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'sort[^\n]*[[:space:]]-[A-Za-z]*V[A-Za-z]*([[:space:]]|$)')"

f="$(tmpsh 'sort -V "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort -V should fail, got success: $out"
else
  ok "sort -V is detected"
fi
rm -f "$f"

# --- V need not be the LAST letter in the flag cluster ("sort -Vr") --------
f="$(tmpsh 'sort -Vr "$file"')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  fail "sort -Vr (V not last in the cluster) should fail"
else
  ok "sort -Vr (V not last in the cluster) is detected"
fi
rm -f "$f" "$tok"

# --- sort -V's long-form spellings: --version-sort and --sort=version ------
tok="$(one_token_list '--version-sort')"
f="$(tmpsh 'sort --version-sort "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sort --version-sort should fail, got success: $out"
else
  ok "sort --version-sort (long form) is detected"
fi
rm -f "$f" "$tok"

tok="$(one_token_list 'sort[^\n]*[[:space:]]--sort(=|[[:space:]]+)['"'"'"]?version([[:space:]|&;()<>'"'"'"`]|$)')"

# --- every spelling of --sort's mandatory WORD: attached after `=` or handed
# over as the next argv element, bare or shell-quoted, and terminated by a
# control operator rather than whitespace ---------------------------------
while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "[$case] should fail, got success: $out"
  else
    ok "[$case] is detected"
  fi
  rm -f "$f"
done <<'CASES'
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
CASES

# --- ...but `--sort=<key>` belongs to portable commands too: Git's own
# version-aware tag ordering must not be reported as a GNU `sort` violation
f="$(tmpsh 'git tag --sort=version:refname --list')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "git tag --sort=version:refname is not flagged (no sort command, no WORD boundary)"
else
  fail "git tag --sort=version:refname must not be flagged"
fi
rm -f "$f" "$tok"

# =============================================================================
# sed -i without a backup-suffix argument
# =============================================================================

tok="$(one_token_list 'sed[^\n]*-i[[:space:]]+[^[:space:]]')"

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

# --- the space-separated empty-suffix idiom (-i '' / -i "") is NOT the
# portable form it looks like -- verified against a real GNU sed 4.9, that
# exact invocation exits 2 (the empty string is consumed as sed's SCRIPT
# argument, not as -i's suffix), so it must stay flagged, not be excused.
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
rm -f "$f" "$tok"

# =============================================================================
# sed -Ei (extended-regex + unsuffixed in-place combined into one flag
# cluster), and --in-place (GNU long form) — #1513
# =============================================================================

tok="$(one_token_list '(^|[^[:alnum:]_])sed([[:space:]][^\n]*)?[[:space:]]-[A-Za-z]*E[A-Za-z]*i([[:space:]|&;()<>]|$)')"

f="$(tmpsh "sed -Ei 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -Ei (unsuffixed) should fail, got success: $out"
else
  ok "sed -Ei (unsuffixed) is detected"
fi
rm -f "$f"

# --- an indented invocation still matches (the non-identifier branch of the
# command-token anchor, not the start-of-line branch) -----------------------
f="$(tmpsh "  sed -Ei 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "indented sed -Ei should fail, got success: $out"
else
  ok "indented sed -Ei is detected (command-token anchor allows a leading separator)"
fi
rm -f "$f"

# --- E/i need not be adjacent or the only letters in the cluster, but i must
# be the cluster's LAST letter (GNU syntax is -i[SUFFIX]) -------------------
f="$(tmpsh "sed -nEi 's/foo/bar/' \"\$file\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "sed -nEi (E/i not adjacent, extra letter in cluster) should fail, got success: $out"
else
  ok "sed -nEi (E/i not adjacent, extra letter in cluster) is detected"
fi
rm -f "$f"

# --- -iE is NOT the unsuffixed form: GNU's syntax is -i[SUFFIX], so the E is
# an attached backup suffix (verified against GNU sed 4.9: `sed -iE ... f`
# writes the backup `fE`), i.e. the dual-compatible shape -------------------
f="$(tmpsh "sed -iE 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -iE (E is an attached backup suffix, not a flag) is not flagged"
else
  fail "sed -iE must not be flagged -- E is an attached nonempty suffix, which is dual-compatible"
fi
rm -f "$f"

# --- an attached NONEMPTY suffix is dual-compatible, not flagged -----------
f="$(tmpsh "sed -Ei.bak 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -Ei.bak (attached nonempty suffix) is not flagged"
else
  fail "sed -Ei.bak must not be flagged -- attached suffix is dual-compatible"
fi
rm -f "$f"

# --- an attached EMPTY suffix is the same ambiguous shape as -i'' (deferred,
# see the token file) -- must not be flagged -------------------------------
f="$(tmpsh "sed -Ei'' 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "sed -Ei'' (attached empty suffix) is not flagged -- deferred ambiguous shape"
else
  fail "sed -Ei'' must not be flagged -- it is the same deferred ambiguous shape as -i''"
fi
rm -f "$f"

# --- plain -i (no E) does not double-fire this cluster token ---------------
f="$(tmpsh "sed -i 's/foo/bar/' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "plain sed -i (no E in the cluster) does not fire the -Ei token"
else
  fail "plain sed -i must not fire the E+i combined-cluster token"
fi
rm -f "$f"

# --- anchored to a sed mention on the line: bare -Ei from an unrelated tool
# name is not itself sufficient (grep also has -E and -i, commonly combined)
f="$(tmpsh "grep -Ei 'pattern' \"\$file\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "grep -Ei (no 'sed' on the line) does not fire the sed-scoped token"
else
  fail "grep -Ei must not fire a sed-scoped token -- it has no 'sed' mention on the line"
fi
rm -f "$f"

# --- the anchor is a sed COMMAND token, not any occurrence of the three
# characters: an identifier that merely contains 'sed' must not arm it ------
f="$(tmpsh "used=\"\$(grep -Ei 'pattern' \"\$file\")\"")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "an identifier containing 'sed' (used=) does not arm the sed-scoped token"
else
  fail "used=\"\$(grep -Ei ...)\" must not fire -- 'sed' inside an identifier is not a sed command"
fi
rm -f "$f"

# --- operator-terminated forms: no trailing whitespace before a control
# operator, redirection, or subshell close must still be detected (#1545 —
# the boundary originally accepted only whitespace or end of line, the same
# class of false negative #1537 fixed for sort -V/grep -P/echo -e). Quotes
# are NOT in this token's boundary (unlike the sibling tokens above) — see
# the "sed -Ei'' must not be flagged" test above for why. --------------------
while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "[$case] should fail, got success: $out"
  else
    ok "[$case] is detected"
  fi
  rm -f "$f"
done <<'CASES'
x=$(sed -Ei)
sed -Ei|cat
sed -Ei; echo done
CASES
rm -f "$tok"

tok="$(one_token_list '(^|[^[:alnum:]_])sed([[:space:]][^\n]*)?[[:space:]]--in-place([[:space:]|&;()<>]|=|$)')"

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

# --- an unrelated tool's own --in-place option (defined or forwarded by the
# script itself) is not a GNU sed invocation and must not be flagged --------
f="$(tmpsh "case \"\$1\" in --in-place) in_place=1 ;; esac")"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a script's own --in-place option arm is not flagged (no sed command on the line)"
else
  fail "--in-place must be scoped to a sed invocation -- an unrelated option arm must not fire"
fi
rm -f "$f"

# --- operator-terminated forms (#1545) --------------------------------------
while IFS= read -r case; do
  f="$(tmpsh "$case")"
  if out="$(scan_paths "$tok" "$f" 2>&1)"; then
    fail "[$case] should fail, got success: $out"
  else
    ok "[$case] is detected"
  fi
  rm -f "$f"
done <<'CASES'
x=$(sed --in-place)
sed --in-place|cat
sed --in-place; echo done
CASES
rm -f "$tok"

# =============================================================================
# readlink -f / --canonicalize, auto-guarded by a co-located realpath attempt
# =============================================================================

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

# --- mere co-location is not enough -- the guard requires an actual `||`
# fallback relationship. Two unconditional statements (semicolon-separated,
# no ||) both mentioning realpath/readlink on one line must still flag: the
# GNU-only readlink -f call runs unconditionally regardless of what realpath
# did, so there is no real fallback protecting it.
f="$(tmpsh 'realpath -- "$1" >/dev/null; readlink -f -- "$1"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "realpath;readlink with no || fallback relationship should fail, got success: $out"
else
  ok "realpath and readlink with no actual || fallback relationship is still flagged"
fi
rm -f "$f"

# --- nor is a `||` enough on its own: the counterpart must sit at COMMAND
# POSITION after it. A failure branch that merely PRINTS the portable form
# names it inside a diagnostic string, so no portable command ever runs and
# the GNU-only call must still flag (#1544).
f="$(tmpsh 'realpath -- "$1" || echo "readlink -f is unavailable"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a printed-only readlink counterpart should fail, got success: $out"
else
  ok "a readlink counterpart that is only printed, not run, is still flagged"
fi
rm -f "$f" "$tok"

# --- the realpath guard is scoped to the readlink pattern, not the whole line
# A line mentioning "realpath" for an unrelated reason must not blanket-excuse
# a DIFFERENT active token's hit on that same line.
tok="$(one_token_list "$(printf '%s\n%s' '\\b' 'readlink[[:space:]]+(-[A-Za-z]*f|--canonicalize)')")"
f="$(tmpsh 'echo "realpath is a coreutils tool"; grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an unrelated realpath mention should not excuse the \\b hit, got success: $out"
else
  ok "the realpath guard is scoped to the readlink pattern, not the whole line"
fi
rm -f "$f" "$tok"

# =============================================================================
# date -d (GNU date-string parsing) -- #1510
# =============================================================================

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

# --- a comment merely naming date -d is not flagged (construct matching skips comments)
tok="$(one_token_list 'date[[:space:]]+[^\n]*-d([[:space:]]|$)')"
f="$(tmpsh '# GNU date -d and BSD date -j -f are mutually exclusive dialects.')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a comment merely naming date -d is not flagged"
else
  fail "a comment-only mention of date -d must not fire"
fi
rm -f "$f" "$tok"

# --- "date" as a mere substring of an identifier (e.g. "candidate") followed
# later by an unrelated -d flag on the same line must not fire.
tok="$(one_token_list 'date[[:space:]]+[^\n]*-d([[:space:]]|$)')"
f="$(tmpsh 'elif [[ "$candidate" == "$base" && -d "$candidate" ]]; then')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "\"date\" as a substring of \"candidate\" does not spuriously match -d"
else
  fail "the candidate/-d false positive must not fire"
fi
rm -f "$f" "$tok"

# =============================================================================
# stat -c, auto-guarded by a co-located stat -f attempt -- #1510
# =============================================================================

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

# --- mere co-location is not enough -- the guard requires an actual `||`
# fallback relationship, mirroring the readlink/realpath guard's rigor.
tok="$(one_token_list 'stat[[:space:]]+[^\n]*-c')"
f="$(tmpsh "stat -f '%d' \"\$1\" >/dev/null; stat -c '%d' \"\$1\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "stat -f;stat -c with no || fallback relationship should fail, got success: $out"
else
  ok "stat -f and stat -c with no actual || fallback relationship is still flagged"
fi
rm -f "$f"

# --- and the `stat -f` counterpart must sit at COMMAND POSITION after the
# `||`, not merely somewhere to its right: a failure branch that only PRINTS
# the BSD form runs no portable command at all, so suppressing the hit would
# hide a real GNU-only call behind a fallback that does not exist (#1544).
f="$(tmpsh "stat -c '%s' \"\$f\" || echo 'stat -f is unavailable'")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a printed-only stat -f counterpart should fail, got success: $out"
else
  ok "a stat -f counterpart that is only printed, not run, is still flagged"
fi
rm -f "$f"

# --- ...while the assignment/command-substitution shape the corpus really
# uses for a fallback ladder stays guarded (lib/hook-utils.sh resolves through
# `name=$(cmd) || name=$(fallback)`, replicated in 15 hook-utils.sh copies).
f="$(tmpsh 'size=$(stat -c "%s" "$1") || size=$(stat -f "%z" "$1")')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a name=\$(stat -f ...) fallback after || is still recognized as a guard"
else
  fail "the assignment-wrapped stat -f fallback ladder must not be flagged"
fi
rm -f "$f"

# --- the guard must also stop at a command SEPARATOR. With another command
# between the GNU call and the ||, the || belongs to that later command, so the
# BSD form is not the GNU call's fallback and the unconditional GNU-only
# invocation must still flag (#1544).
f="$(tmpsh "stat -c '%s' \"\$f\"; true || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a stat -f reached across a ; should fail, got success: $out"
else
  ok "a stat -f fallback in a LATER command segment does not guard the GNU call"
fi
rm -f "$f"

# --- a CONTROL & is a separator too: it backgrounds the GNU call and hands the
# || to whatever follows, so in `... & true || stat -f ...` the || binds to
# `true` and the BSD form never runs (#1544).
f="$(tmpsh "stat -c '%s' \"\$f\" & true || stat -f '%z' \"\$f\"")"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a stat -f reached across a background & should fail, got success: $out"
else
  ok "a backgrounding & also breaks the stat fallback relationship"
fi
rm -f "$f"

# --- ...while `>&` and `&&` are NOT separators: a real ladder may redirect
# with 2>&1, and `a && b || c` does still fall back to c when a fails.
f="$(tmpsh 'size=$(stat -c "%s" "$1" 2>&1) || size=$(stat -f "%z" "$1")')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "a 2>&1 redirection inside the ladder does not break the guard"
else
  fail "2>&1 must not be mistaken for a control &: $(scan_paths "$tok" "$f" 2>&1)"
fi
rm -f "$f"

# --- a redirection may also sit between `stat` and its OWN option: it does not
# change the argv stat receives, so this is the same BSD fallback and must not
# be forced into a hand-written exemption (#1544).
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

# --- "stat" as a mere prefix of an identifier ("status") followed later by an
# unrelated -c flag on the same line must not fire (git's own -c name=value).
tok="$(one_token_list 'stat[[:space:]]+[^\n]*-c')"
f="$(tmpsh 'run "safe alias" "git -c alias.st=status st" 0')"
if scan_paths "$tok" "$f" >/dev/null 2>&1; then
  ok "\"stat\" as a prefix of \"status\" does not spuriously match -c"
else
  fail "the status/-c false positive must not fire"
fi
rm -f "$f" "$tok"

# --- the stat -f guard is scoped to the stat -c pattern, not the whole line
# A line mentioning "stat -f" for an unrelated reason must not blanket-excuse a
# DIFFERENT active token's hit on that same line.
tok="$(one_token_list "$(printf '%s\n%s' '\\b' 'stat[[:space:]]+[^\n]*-c')")"
f="$(tmpsh 'echo "stat -f is the BSD form"; grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "an unrelated stat -f mention should not excuse the \\b hit, got success: $out"
else
  ok "the stat -f guard is scoped to the stat -c pattern, not the whole line"
fi
rm -f "$f" "$tok"

# =============================================================================
# Opt-out annotation
# =============================================================================

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
elif echo "$out" | grep -q ":4:" && ! echo "$out" | grep -q ":2:"; then
  ok "annotation covers line 2 only and does not leak past intervening code"
else
  fail "expected line 4 flagged and line 2 clean, got: $out"
fi
rm -f "$f" "$tok"

# --- whole-file portability-scope declaration excuses every hit ------------
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

# --- a mere MENTION of the token (not a genuine comment-line declaration) --
# does NOT exempt the file -- #1513: a doc-block sentence explaining the
# mechanism, or a string literal containing the words, must not wrongly
# excuse a real hit.
tok="$(one_token_list '\\b')"
f="$(tmpsh '# This script supports a whole-file portability-scope: <reason> declaration.
grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a doc-comment merely mentioning portability-scope: should not exempt the file, got success: $out"
elif echo "$out" | grep -q "PORTABILITY: ${f}:2:"; then
  ok "a doc-comment mentioning portability-scope: (not a genuine declaration) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f"

f="$(tmpsh 'msg="see portability-scope: docs for details"
grep -Eq "\\bfoo\\b" "$file"')"
if out="$(scan_paths "$tok" "$f" 2>&1)"; then
  fail "a string literal mentioning portability-scope: should not exempt the file, got success: $out"
elif echo "$out" | grep -q "PORTABILITY: ${f}:2:"; then
  ok "a string literal mentioning portability-scope: (not a comment) does not exempt the file"
else
  fail "expected line 2 flagged (not exempted), got: $out"
fi
rm -f "$f" "$tok"

# --- a genuine declaration mid-file (not necessarily line 1) still works ---
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

# =============================================================================
# awk operand disambiguation: a scanned file whose name is shaped like an
# identifier=value assignment must not be silently dropped from the scan
# (#1513)
# =============================================================================

tok="$(one_token_list '\\b')"
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
printf 'grep -Eq "\\bfoo\\b" "$file"\n' >"$fx/FOO=bar.sh"
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="$tok" bash scripts/check-shell-portability.sh --paths "FOO=bar.sh" 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] && echo "$out" | grep -q 'PORTABILITY: FOO=bar\.sh:1:'; then
  ok "a filename shaped like identifier=value is scanned, not silently dropped by awk"
else
  fail "an identifier=value-shaped filename must be scanned, not dropped (rc=$rc): $out"
fi
rm -rf "$fx" "$tok"

# =============================================================================
# Fail-closed behavior
# =============================================================================

BAD_TOKENS="$(mktemp)"
printf '%s\n' '(unterminated' >"$BAD_TOKENS" # unmatched '(' -- invalid ERE, awk faults
f="$(tmpsh 'grep -Eq foo bar')"
SHELL_PORTABILITY_TOKENS="$BAD_TOKENS" bash "$SCRIPT" --paths "$f" >/dev/null 2>&1
if [[ "$?" -eq 2 ]]; then
  ok "malformed active token exits 2 (fail closed, no silent pass)"
else
  fail "malformed active token should exit 2, not silently treat the file as clean"
fi
rm -f "$f" "$BAD_TOKENS"

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

# =============================================================================
# Scope resolution: --all excludes vendor/, non-.sh files stay out of scope
# =============================================================================

fx="$(mktemp -d)"
mkdir -p "$fx/scripts" "$fx/plugins/alpha/vendor"
cp "$SCRIPT" "$fx/scripts/"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/gate.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/vendor/upstream.sh"
printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$fx/plugins/alpha/notes.md" # non-.sh stays out of scope
out="$(cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all 2>&1)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'gate.sh' &&
  ! echo "$out" | grep -qE 'vendor/|notes\.md'; then
  ok "--all scans gate.sh but excludes vendor/ and non-.sh files"
else
  fail "--all exclusion set wrong (rc=$rc): $out"
fi
rm -rf "$fx"

fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
if (cd "$fx" && SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh --all >/dev/null 2>&1); then
  ok "an empty tree passes"
else
  fail "an empty tree should pass"
fi
rm -rf "$fx"

# --- diff-mode reads a Git-quoted (non-ASCII) changed path -----------------
fx="$(mktemp -d)"
mkdir -p "$fx/scripts"
cp "$SCRIPT" "$fx/scripts/"
quoted_name="$(printf 'quoted-\303\251.sh')" # trailing U+00E9 byte -- non-ASCII, triggers Git quoting
out="$(
  cd "$fx" &&
    git init -q &&
    git config user.email test@example.com &&
    git config user.name test &&
    git commit -q --allow-empty -m base &&
    base="$(git rev-parse HEAD)" &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >'plain.sh' &&
    printf '%s\n' 'grep -Eq "\\bfoo\\b" "$file"' >"$quoted_name" &&
    git add -A >/dev/null 2>&1 &&
    git commit -q -m add-scripts &&
    SHELL_PORTABILITY_TOKENS="$(one_token_list '\\b')" bash scripts/check-shell-portability.sh "$base" 2>&1
)"
rc=$?
if [[ "$rc" -ne 0 ]] &&
  echo "$out" | grep -q 'plain.sh:1:' &&
  [[ "$(echo "$out" | grep -c 'PORTABILITY:')" -eq 2 ]]; then
  ok "diff-mode gates a Git-quoted (non-ASCII) changed path (not silently dropped)"
else
  fail "diff-mode should flag both the ASCII and non-ASCII changed files (rc=$rc): $out"
fi
rm -rf "$fx"

# =============================================================================
# The shipped token list against the REAL corpus
# =============================================================================

# --- the reference implementation this issue names as known-good is clean --
if out="$(scan_paths "$REAL_TOKENS" "$REPO_ROOT/plugins/markdown-format/hooks/markdown-format.sh" 2>&1)"; then
  ok "the shipped token list does not flag markdown-format.sh's reference implementation"
else
  fail "markdown-format.sh must stay clean under the shipped token list, got: $out"
fi

# --- date -d and stat -c are now ACTIVE in the shipped list (#1510) --------
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

# --- both tokens match a whole command WORD, not any word ending in it: the
# gap-scoping alone left "date"/"stat" unanchored on the left, so words merely
# ENDING in them took the flag of a genuinely different command (#1544). A
# path-qualified invocation is still the command itself and must stay flagged.
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

# --- -d takes a mandatory argument, so GNU accepts it ATTACHED, and --date is
# its documented long spelling (`date --help`: `-d, --date=STRING`). A
# whitespace-or-EOL-only tail matched neither (#1544). Likewise stat's
# --format/--printf are the long spellings of -c (`stat --help`:
# `-c  --format=FORMAT`), so the class was enforceable under one spelling only.
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

# --- an attached -d argument may be a bare WORD, and `c` may sit inside a
# short-option cluster (#1544). GNU documents a mandatory long-option argument
# as mandatory for the short option too, so `date -u -dtomorrow +%Y` succeeds,
# and `stat --help` documents `-L, --dereference` so `stat -Lc%s` succeeds.
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

# --- ...but a LONGER flag whose name merely contains the letter must not be
# read as that option. Both are real GNU flags that succeed in their own right.
f="$(tmpsh "$(printf '%s\n' \
  'date --debug +%s' \
  'stat --dereference "$file"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "date --debug and stat --dereference are not read as -d / -c"
else
  fail "long flags must not match the short-option branch: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

# --- `d` may sit at the argument-taking end of a CLUSTER: GNU lists `-u, --utc`
# beside `-d, --date=STRING`, and `date -ud tomorrow +%Y` succeeds (#1544).
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

# --- the matched hyphen must BEGIN an argument, so a `-c` living inside a
# filename passes no option and must not be reported (#1544).
f="$(tmpsh "$(printf '%s\n' \
  'stat "$file-c"' \
  'stat foo-c')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a -c inside an operand is not mistaken for stat's format option"
else
  fail "operands containing -c must not be flagged: $(scan_paths "$REAL_TOKENS" "$f" 2>&1)"
fi
rm -f "$f"

# --- ...while an option that genuinely follows an operand still is.
f="$(tmpsh 'stat "$f" -c %s')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a -c after an operand should still fail, got success: $out"
else
  ok "a -c that does begin an argument after an operand is still detected"
fi
rm -f "$f"

# --- sort's long-form spellings are active in the SHIPPED list (not just the
# isolated-token mechanism proven above): every flagged spelling on its own
# line, plus Git's portable `--sort=<key>` which must stay clean -----------
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
  ! echo "$out" | grep -q "PORTABILITY: ${f}:6:"; then
  ok "the shipped list detects every sort long form and spares git tag --sort=<key>"
else
  fail "expected hits on lines 1-5 only, got: $out"
fi
rm -f "$f"

# --- mktemp -p is now ACTIVE (#1527) ----------------------------------------
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

# --- attached-value and long-form parent-directory spellings (#1543). GNU
# getopt takes -p's DIR joined to the cluster, and documents --tmpdir[=DIR] as
# the equivalent; both are as BSD-incompatible as the whitespace-delimited form
# a cluster-plus-whitespace boundary alone matched. The attached DIR is an
# arbitrary string, so one whose first segment is alphabetic must flag exactly
# like `-p/tmp` — verified against GNU coreutils 8.32, where
# `mktemp -prel/sub name.XXXXXX` creates `rel/sub/name.XXXXXX`.
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

# --- ...and the option scan stops at a shell command separator (#1543): a
# physical line is not a command, so a later command's `-p` is not mktemp's.
f="$(tmpsh 'tmp=$(mktemp); cp -p source "$tmp"')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "cp -p after a portable mktemp on the same line is not flagged"
else
  fail "a later command's -p must not be attributed to mktemp, got: $out"
fi
rm -f "$f"

# --- ...including the legacy backtick spelling of that substitution (#1543).
# A closing backtick ends the substitution exactly as `)` ends `$(...)`, so in
# the VAR=value-prefixed command below the `-p` is cp's, not mktemp's.
f="$(tmpsh 'tmp=`mktemp` cp -p source target')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  ok "cp -p after a backtick-substituted portable mktemp is not flagged"
else
  fail "a closing backtick must end the option scan, got: $out"
fi
rm -f "$f"

# --- ...without over-stopping: a `-p` INSIDE the backtick substitution is
# mktemp's own and must keep flagging.
f="$(tmpsh 'tmp=`mktemp -p "$d"`')"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "mktemp -p inside a backtick substitution must still be flagged: $out"
else
  ok "mktemp -p inside a backtick substitution is still flagged"
fi
rm -f "$f"

# --- both mktemp tokens are anchored to the COMMAND TOKEN (#1543): `-p` and
# `--tmpdir` are GNU mktemp's flags, not a flag of every command whose name
# merely contains "mktemp". The boundary is a shell WORD POSITION rather than
# an enumeration of legal name characters -- `+` and `@` are as legal in a
# command name as `-` and `.`, so any such enumeration is unfinishable.
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

# --- ...and the real command still flags at every position the anchor admits:
# line start, after a separator, inside a substitution, reached by absolute
# path (`/` is a path separator, not part of a name), and with the command
# token itself quoted -- the shell strips those quotes and runs the same
# GNU-only mktemp.
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

# --- operator-terminated sed -Ei / --in-place forms are active in the
# SHIPPED list too (#1545): both tokens widened to the control-operator/
# redirection/subshell-close boundary (deliberately narrower than
# `--sort=WORD` (#1530) and `sort -V`/`grep -P`/`echo -e` (#1537), which also
# include quotes — see the token-file comment), proven here against the real
# token list rather than only the isolated-token mechanism above -----------
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

# =============================================================================
# Quote-aware command segmentation -- #1544 review round
#
# Each shape below was reproduced against the real gate before the segmenter
# replaced the `[^;&|()\n]*` gap. Two were false positives; three were the
# gate failing OPEN, the worse direction -- a GNU-only call reaching a BSD
# userland unreported.
# =============================================================================

# --- `--` ends option parsing, so a flag-shaped word after it is an operand.
f="$(tmpsh "$(printf '%s\n' \
  'stat -- -c' \
  'date -- -d' \
  'date -c -- -d' \
  'stat -- --format')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a flag-shaped operand after the -- end-of-options marker is not flagged"
else
  fail "-- must end option parsing for both date and stat"
fi
rm -f "$f"

# --- ... but a real option BEFORE the -- still is one.
f="$(tmpsh "stat -c '%s' -- \"\$f\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "a real -c before -- should still fail, got success: $out"
else
  ok "a genuine option before -- is still detected"
fi
rm -f "$f"

# --- an invocation wrapper still reaches the real BSD utility, so a ladder
# through one is a genuine fallback. `command` is POSIX-specified; `env` and a
# leading backslash reach the same utility.
f="$(tmpsh "$(printf '%s\n' \
  'stat -c "%s" "$f" || command stat -f "%z" "$f"' \
  'stat -c "%s" "$f" || env stat -f "%z" "$f"')")"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "a BSD fallback wrapped in command/env is recognized as a real ladder"
else
  fail "command- and env-wrapped stat -f fallbacks must not be flagged"
fi
rm -f "$f"

# --- the guard binds to the matched invocation, not to the line. The FIRST
# call here is unconditional and must flag even though a guarded ladder for a
# different operand follows it on the same line.
f="$(tmpsh "stat -c '%s' \"\$a\"; stat -c '%s' \"\$b\" || stat -f '%z' \"\$b\"")"
if out="$(scan_paths "$REAL_TOKENS" "$f" 2>&1)"; then
  fail "an unguarded first call should fail, got success: $out"
else
  ok "a later guarded ladder no longer excuses an unguarded call before it"
fi
rm -f "$f"

# --- the readlink/realpath ladder runs the other direction and must survive.
f="$(tmpsh 'realpath "$1" 2>/dev/null || readlink -f "$1"')"
if scan_paths "$REAL_TOKENS" "$f" >/dev/null 2>&1; then
  ok "the realpath || readlink -f ladder is still auto-guarded after segmentation"
else
  fail "the backward-looking readlink guard must survive segmentation"
fi
rm -f "$f"

# --- a separator inside quotes is a filename character, not a control
# operator, so the gap must not stop there and lose the option after it.
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

# --- a quoted command word is still that command. The mktemp tokens already
# admitted a closing quote; date and stat did not, so these were all missed.
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

# --- segmentation must not disturb the classes that legitimately live INSIDE
# string literals: matching runs on the original text, never on the mask.
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

echo
echo "PASS=$PASS FAIL=$FAIL"
[[ "$FAIL" -eq 0 ]]

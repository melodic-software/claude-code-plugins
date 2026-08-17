#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib; fixtures are built
# inline in a tmpdir, so the plugin ships no slop samples for the audit to trip
# over). Per the shell-test-helpers convention, assertion helpers are local.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

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
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "exit $2" "exit $3"; fi
}
assert_contains() {
  case "$2" in
  *"$3"*) pass "$1" ;;
  *) fail "$1" "contains: $3" "$2" ;;
  esac
}
assert_not_contains() {
  case "$2" in
  *"$3"*) fail "$1" "absent: $3" "present" ;;
  *) pass "$1" ;;
  esac
}

EM=$'\xe2\x80\x94'
CHECKMARK=$'\xe2\x9c\x85'
LQUO=$'\xe2\x80\x9c'
RQUO=$'\xe2\x80\x9d'

# --- Fixtures (built inline) ----------------------------------------------------

SLOP="$TEST_TMPDIR/slop.md"
cat >"$SLOP" <<EOF
# A pivotal document

This stands as a testament to the vibrant tapestry of the field ${EM} a
crucial, groundbreaking interplay that will delve into the intricacies.
Meticulously bolstered, showcasing renowned and enduring work.
EOF

CLEAN="$TEST_TMPDIR/clean.md"
cat >"$CLEAN" <<'EOF'
# Release notes

The parser now accepts empty input. Tests cover the failure paths one by one.
See the changelog for upgrade steps. Nothing else changed in this release.
EOF

ALLRULES="$TEST_TMPDIR/allrules.md"
cat >"$ALLRULES" <<EOF
# Every pattern rule

- ${CHECKMARK} an emoji bullet line
Some ${LQUO}curly quoted${RQUO} text here.
It is not just fast, but also correct in every case.
Despite its growth, the project faces significant challenges ahead.
As of my knowledge cutoff, this was true.
A leaked marker oaicite:12 sits here.
See https://example.com/?utm_source=chatgpt for details.
It serves as a hub. It stands as a marker. It functions as a portal.
The tool is fast, simple, and reliable. Cheap, quick, and easy too. It reads
clean, tight, and portable in every shell we tried this week.
EOF

MARKED="$TEST_TMPDIR/marked.md"
cat >"$MARKED" <<EOF
# Marker handling

An exempted line ${EM} with an em dash. <!-- ai-slop-ignore -->
EOF

FENCED="$TEST_TMPDIR/fenced.md"
cat >"$FENCED" <<EOF
# Code fences

\`\`\`text
An em dash inside a fence ${EM} stays exempt. So does ${CHECKMARK}.
\`\`\`

And one in inline code: \`a ${EM} b\` also stays exempt.
EOF

FILEMARK="$TEST_TMPDIR/filemark.md"
cat >"$FILEMARK" <<EOF
<!-- ai-slop-ignore-file: catalog-style file -->
Full of em dashes ${EM} and delve, tapestry, pivotal, crucial vocabulary.
EOF

DOCMARKS="$TEST_TMPDIR/docmarks.md"
cat >"$DOCMARKS" <<EOF
# Documents the markers without using them

Opt-outs: \`<!-- ai-slop-ignore -->\` per line, \`<!-- ai-slop-ignore-start -->\`
and \`<!-- ai-slop-ignore-end -->\` for blocks, \`<!-- ai-slop-ignore-file -->\`
for whole files. After the mentions, an em dash ${EM} must still be flagged.
EOF

MIDFILEMARK="$TEST_TMPDIR/midfilemark.md"
cat >"$MIDFILEMARK" <<EOF
# Content first

An em dash ${EM} before the marker.

<!-- ai-slop-ignore-file: declared late -->

Vocabulary after: delve, tapestry, pivotal.
EOF

MIDEMOJI="$TEST_TMPDIR/midemoji.md"
cat >"$MIDEMOJI" <<EOF
# Emoji in content position

The reaction was ${CHECKMARK} from the whole team.
EOF

# --- Seed-rule cases -------------------------------------------------------------

out="$(bash "$DETECT" "$SLOP" 2>&1)"
rc=$?
assert_exit "slop fixture: exit 0" 0 "$rc"
assert_contains "slop: em-dash fires" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "slop: em-dash condition is zero-tolerance" "$out" "fired=zero-tolerance"
assert_contains "slop: vocabulary fires" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"
assert_contains "slop: vocabulary condition carries threshold" "$out" "threshold 3.0"

out="$(bash "$DETECT" "$CLEAN" 2>&1)"
rc=$?
assert_exit "clean fixture: exit 0" 0 "$rc"
assert_not_contains "clean fixture: no findings from any rule" "$out" "Finding:"
assert_contains "clean fixture: summary reports zero" "$out" "Summary total: 0 findings"

# --- Full-roster pattern rules ---------------------------------------------------

out="$(bash "$DETECT" "$ALLRULES" 2>&1)"
assert_contains "roster: emoji-formatting fires on bullet line" "$out" "Finding: rule=ai-slop/audit/rule-emoji-formatting"
assert_contains "roster: curly-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-curly-artifacts"
assert_contains "roster: negative-parallelism fires" "$out" "Finding: rule=ai-slop/audit/rule-negative-parallelism"
assert_contains "roster: challenges-conclusion fires" "$out" "Finding: rule=ai-slop/audit/rule-challenges-conclusion"
assert_contains "roster: knowledge-cutoff fires" "$out" "Finding: rule=ai-slop/audit/rule-knowledge-cutoff-disclaimer"
assert_contains "roster: citation-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-llm-citation-artifacts"
assert_contains "roster: utm-params fires" "$out" "Finding: rule=ai-slop/audit/rule-utm-params"
assert_contains "roster: copulative-avoidance density fires" "$out" "Finding: rule=ai-slop/audit/rule-copulative-avoidance"
assert_contains "roster: rule-of-three density fires" "$out" "Finding: rule=ai-slop/audit/rule-rule-of-three"

out="$(bash "$DETECT" "$MIDEMOJI" 2>&1)"
assert_not_contains "emoji negative: content-position emoji does not fire the formatting rule" "$out" "Finding: rule=ai-slop/audit/rule-emoji-formatting"

# --- Exemptions ------------------------------------------------------------------

out="$(bash "$DETECT" "$MARKED" 2>&1)"
assert_not_contains "line marker: em dash on marked line not flagged" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "line marker: declined count nonzero" "$out" "declined=1"

out="$(bash "$DETECT" "$FENCED" 2>&1)"
assert_not_contains "fences: fenced and inline-code content not flagged" "$out" "Finding:"

out="$(bash "$DETECT" "$FILEMARK" 2>&1)"
assert_not_contains "file marker: whole file exempt" "$out" "Finding:"
assert_contains "file marker: counted as declined file" "$out" "(1 files declined)"

out="$(bash "$DETECT" "$DOCMARKS" 2>&1)"
assert_contains "marker mentions: backticked docs do not exempt the file" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "marker mentions: no decline from prose mentions" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 declined=0"

out="$(bash "$DETECT" "$MIDFILEMARK" 2>&1)"
assert_not_contains "mid-file file marker: whole file exempt, nothing scanned" "$out" "Finding:"
assert_contains "mid-file file marker: counted as declined file" "$out" "(1 files declined)"

# --- CLI contract ----------------------------------------------------------------

out="$(bash "$DETECT" --paths-file "$TEST_TMPDIR/nope" 2>&1)"
rc=$?
assert_exit "unreadable paths-file: exit 2" 2 "$rc"

out="$(bash "$DETECT" --bogus 2>&1)"
rc=$?
assert_exit "unknown option: exit 2" 2 "$rc"

pf="$TEST_TMPDIR/paths.txt"
printf '%s\n%s\n' "$SLOP" "$CLEAN" >"$pf"
out="$(bash "$DETECT" --paths-file "$pf" --offset 0 --limit 1 2>&1)"
assert_contains "chunking: limit 1 scans one file" "$out" "across 1 files scanned"

# --- Config cascade --------------------------------------------------------------

cfgdir="$TEST_TMPDIR/repo/.claude"
mkdir -p "$cfgdir"
cp "$SLOP" "$TEST_TMPDIR/repo/allowed.md"
cat >"$cfgdir/ai-slop.json" <<'EOF'
{
  "em_dash_allowed_paths": ["allowed.md"],
  "thresholds": { "ai_vocabulary": 999, "copulative_avoidance": 999, "rule_of_three": 999 },
  "disabled_rules": ["rule-significance-inflation"]
}
EOF
out="$(cd "$TEST_TMPDIR/repo" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" "$TEST_TMPDIR/repo/allowed.md" 2>&1)"
assert_not_contains "config: em_dash_allowed_paths exempts the document" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_not_contains "config: raised threshold silences vocabulary rule" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"
assert_not_contains "config: disabled rule emits no findings" "$out" "Finding: rule=ai-slop/audit/rule-significance-inflation"
assert_contains "config: disabled rule reported in summary" "$out" "rule=ai-slop/audit/rule-significance-inflation findings=0 declined=0 disabled=1"

out="$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" --show-config 2>&1)"
assert_contains "show-config: names the supplying layer" "$out" "$cfgdir/ai-slop.json"
assert_contains "show-config: effective threshold shown" "$out" "threshold_ai_vocabulary=999"
assert_contains "show-config: disabled rules shown" "$out" "disabled_rules=rule-significance-inflation"

# --- Portability -----------------------------------------------------------------

a="$(bash "$DETECT" "$ALLRULES" 2>&1)"
b="$(LC_ALL=C bash "$DETECT" "$ALLRULES" 2>&1)"
if [[ "$a" == "$b" ]]; then
  pass "portability: output identical under LC_ALL=C"
else
  fail "portability: output identical under LC_ALL=C" "identical" "differs"
fi

# --- Fences (CommonMark indentation + opener-char tracking) -----------------------

FENCY="$TEST_TMPDIR/fency.md"
cat >"$FENCY" <<EOF
# Fences

   \`\`\`text
   An em dash ${EM} inside an indented fence stays exempt.
   ~~~
   Still inside the backtick fence: delve, tapestry ${EM} exempt too.
   \`\`\`

An em dash ${EM} in prose after the fence closes must flag.
EOF

out="$(bash "$DETECT" "$FENCY" 2>&1)"
assert_contains "fences: prose after close still flags" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 "
assert_not_contains "fences: indented fence content exempt, tilde does not close backtick fence" "$out" "delve"

# --- Directory target expansion ---------------------------------------------------

DIRT="$TEST_TMPDIR/dirt"
mkdir -p "$DIRT/sub"
cat >"$DIRT/a.md" <<EOF
An em dash ${EM} here.
EOF
cat >"$DIRT/sub/b.md" <<EOF
Another em dash ${EM} here.
EOF

out="$(bash "$DETECT" "$DIRT" 2>&1)"
assert_contains "dir target: expands recursively to markdown" "$out" "2 files scanned"
assert_contains "dir target: findings from nested file" "$out" "sub/b.md"

# --- emit-findings.sh ------------------------------------------------------------

EMIT="$SCRIPT_DIR/emit-findings.sh"
EMITSRC="$TEST_TMPDIR/emitsrc.md"
cat >"$EMITSRC" <<EOF
# Mixed-tier sample

A pipe | and an em dash ${EM} on one line.

As of my knowledge cutoff, this was true.
EOF

DETOUT="$TEST_TMPDIR/detect-out.txt"
bash "$DETECT" "$EMITSRC" >"$DETOUT" 2>&1 || true
FOUT="$TEST_TMPDIR/findings/ai-slop.md"

out="$(bash "$EMIT" --from "$DETOUT" --out "$FOUT" --branch test-branch 2>&1)"
assert_contains "emit: reports destination" "$out" "wrote $FOUT"
fcontent="$(cat "$FOUT")"
assert_contains "emit: frontmatter type" "$fcontent" "type: review-findings"
assert_contains "emit: frontmatter branch" "$fcontent" "branch: test-branch"
if LC_ALL=C grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}-[0-9]{2}-[0-9]{2}Z$' "$FOUT"; then
  pass "emit: colon-free UTC date"
else
  fail "emit: colon-free UTC date" "colon-free timestamp" "$(grep '^date:' "$FOUT")"
fi
assert_contains "emit: finding cell leads with qualified rule id" "$fcontent" "ai-slop/audit/rule-em-dash"
# detect.sh sanitizes prose pipes to / at excerpt production; the cell must
# never carry a raw table-breaking pipe from prose.
assert_contains "emit: prose pipe arrives sanitized" "$fcontent" "pipe / and"

# The emitter's own escaping still guards pipes reaching it through other
# fields: feed a synthetic detect-output row carrying one.
SYNTH="$TEST_TMPDIR/synth-out.txt"
cat >"$SYNTH" <<'EOF'
Finding: rule=ai-slop/audit/rule-em-dash file=doc.md line=1 fired=zero|tolerance excerpt=text
Summary rule=ai-slop/audit/rule-em-dash findings=1 declined=0 disabled=0
EOF
bash "$EMIT" --from "$SYNTH" --out "$TEST_TMPDIR/findings/synth.md" --branch test-branch >/dev/null 2>&1
assert_contains "emit: pipe escaped in cell" "$(cat "$TEST_TMPDIR/findings/synth.md")" 'zero\|tolerance'

# An excerpt that itself contains file=/line= tokens (a doc describing this
# format) must not spoof the Location cell — first-occurrence parsing.
SPOOF="$TEST_TMPDIR/spoof.md"
cat >"$SPOOF" <<EOF
The docs file=README.md line=12 ${EM} see reference.
EOF
SPOOFOUT="$TEST_TMPDIR/spoof-out.txt"
bash "$DETECT" "$SPOOF" >"$SPOOFOUT" 2>&1 || true
bash "$EMIT" --from "$SPOOFOUT" --out "$TEST_TMPDIR/findings/spoof.md" --branch test-branch >/dev/null 2>&1
assert_contains "emit: excerpt field tokens cannot spoof Location" \
  "$(cat "$TEST_TMPDIR/findings/spoof.md")" "spoof.md:1 |"
first_row="$(LC_ALL=C grep -m1 '^| 1 |' "$FOUT")"
assert_contains "emit: IMPORTANT ranks first" "$first_row" "IMPORTANT"
assert_contains "emit: surfaces zero-result rules listed" "$fcontent" "rule-utm-params"

out="$(bash "$EMIT" --from "$DETOUT" --out "$FOUT" --branch test-branch 2>&1)"
assert_contains "emit: non-overwrite suffix on existing file" "$out" "ai-slop-2.md"

CLEANOUT="$TEST_TMPDIR/clean-out.txt"
bash "$DETECT" "$CLEAN" >"$CLEANOUT" 2>&1 || true
bash "$EMIT" --from "$CLEANOUT" --out "$TEST_TMPDIR/findings/none.md" --branch test-branch >/dev/null 2>&1
if [[ -f "$TEST_TMPDIR/findings/none.md" ]] && LC_ALL=C grep -q '^## Findings' "$TEST_TMPDIR/findings/none.md"; then
  pass "emit: zero findings still writes (coverage is the payload)"
else
  fail "emit: zero findings still writes (coverage is the payload)" "file with empty Findings" "missing"
fi

if bash "$EMIT" --from "$EMITSRC" --out "$TEST_TMPDIR/findings/garbage.md" --branch test-branch >/dev/null 2>&1; then
  fail "emit: refuses non-detector input" "exit 3" "exit 0"
else
  rc=$?
  if [[ "$rc" -eq 3 && ! -e "$TEST_TMPDIR/findings/garbage.md" ]]; then
    pass "emit: refuses non-detector input"
  else
    fail "emit: refuses non-detector input" "exit 3, no file" "exit $rc"
  fi
fi

# --- Result ---------------------------------------------------------------------

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed"
  exit 0
else
  echo "$FAILED of $CASE_NUM cases FAILED"
  exit 1
fi

#!/usr/bin/env bash
# Self-contained tests for detect.sh (no external test lib; THIS suite's
# fixtures are built inline in a tmpdir, so no unit-test slop corpus sits in
# the tree). The eval suite is the deliberate exception: evals/fixtures/ holds
# committed slop samples, because a prose scenario cannot be checked against
# the detector and drifted from it three times (#3041). This repo keeps its own
# audit off them with an excluded_paths glob in .claude/ai-slop.json, and they
# stay measurable through the same config isolation this suite uses — an empty
# HOME and CLAUDE_PROJECT_DIR give the shipped defaults back.
# Per the shell-test-helpers convention, assertion helpers are local.
set -uo pipefail

# Fixture git isolation: an inherited GIT_DIR/GIT_WORK_TREE/GIT_CONFIG would
# make the nested-repo fixture operate on the CALLER's repository.
unset GIT_DIR GIT_WORK_TREE GIT_CONFIG

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

# Fixture CONFIG isolation, the same idea as the git isolation above and found
# the same way: detect.sh resolves its config cascade from $HOME and from
# CLAUDE_PROJECT_DIR (falling back to the CWD's git toplevel), so running this
# suite inside a repo that ships `.claude/ai-slop.json` graded the fixtures
# against THAT repo's taste. Measured: this marketplace disabling rule-em-dash
# for its own house style turned nine unrelated cases red, each reporting
# `disabled=1` for a rule the case never mentions. Both layers are pointed at
# empty directories so a fixture asserts the SHIPPED defaults; the cascade cases
# below set CLAUDE_PROJECT_DIR per-invocation and still override this.
export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

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

REASONED="$TEST_TMPDIR/reasoned.md"
cat >"$REASONED" <<EOF
# Markers carrying a reason

A line marker ${EM} with a reason. <!-- ai-slop-ignore: quoting the tell itself -->

<!-- ai-slop-ignore-start: sample block, quoted verbatim -->
Inside the block ${EM} stays exempt.
<!-- ai-slop-ignore-end: end of sample -->

After the block, an em dash ${EM} must still be flagged.
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
for whole files. Each takes an optional reason: \`<!-- ai-slop-ignore: why -->\`.
After the mentions, an em dash ${EM} must still be flagged.
EOF

# A backticked mention of one marker form must not veto a real marker of another
# form on the same line. The guard mirrors the line-marker pattern exactly rather
# than matching any string starting with the marker prefix: when it matched the
# prefix, this line's genuine suppression was rejected and the operator's own
# marker was quoted back in the excerpt (reported by review, reproduced here).
MIXEDMARK="$TEST_TMPDIR/mixedmark.md"
cat >"$MIXEDMARK" <<EOF
# Mentions one form, uses another

Open a block with \`<!-- ai-slop-ignore-start -->\`, em dash ${EM} here. <!-- ai-slop-ignore -->
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

CURSOR="$TEST_TMPDIR/cursor.md"
cat >"$CURSOR" <<'EOF'
# Cursor-derived rules

Great question! I hope this helps, and let me know if you need more.
We did this in order to ship, due to the fact that the deadline slipped.
It could potentially fail here and might possibly regress there.
We leverage tools to facilitate work and utilize helpers for the rest.
EOF

CURSORNEG="$TEST_TMPDIR/cursorneg.md"
cat >"$CURSORNEG" <<'EOF'
# Benign neighbors of the Cursor-derived patterns

Feel free to customize the config for your repo. The run may fail on old
shells, and a question mark ends each prompt. Sort keys in ascending order to
keep diffs stable.
EOF

# Prefix-match false positives: ordinary prose whose words merely BEGIN with a
# listed phrase. Reported in review against rule-chatbot-artifacts and
# reproduced before fixing — an IMPORTANT-tier finding on prose containing no
# chat residue at all. The fix is the registry's whole-word flag; these cases
# are what keeps it.
WORDBOUND="$TEST_TMPDIR/wordbound.md"
cat >"$WORDBOUND" <<'EOF'
# Phrase prefixes inside ordinary words

These are great questions for the reviewer to work through.
The team found the smoking guns in yesterday's logs.
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

# --- Cursor-derived rules ----------------------------------------------------------

out="$(bash "$DETECT" "$CURSOR" 2>&1)"
assert_contains "cursor: chatbot-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-chatbot-artifacts"
assert_contains "cursor: filler-phrases fires" "$out" "Finding: rule=ai-slop/audit/rule-filler-phrases"
assert_contains "cursor: stacked-hedging fires" "$out" "Finding: rule=ai-slop/audit/rule-stacked-hedging"
assert_contains "cursor: plain-word vocab additions fire the density rule" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"

out="$(bash "$DETECT" "$CURSORNEG" 2>&1)"
assert_not_contains "cursor negative: benign near-miss phrasing stays quiet" "$out" "Finding:"

out="$(bash "$DETECT" "$WORDBOUND" 2>&1)"
assert_not_contains "word boundary: 'great questions' does not fire the chat-residue rule" "$out" "Finding:"
# The true positives must survive the boundary flag — a rule silenced into
# uselessness would also pass the assertion above.
WORDBOUNDPOS="$TEST_TMPDIR/wordboundpos.md"
cat >"$WORDBOUNDPOS" <<'EOF'
# The real thing

Great question! The retry budget is three attempts.
Found the smoking gun in the connection pool.
EOF
out="$(bash "$DETECT" "$WORDBOUNDPOS" 2>&1)"
assert_contains "word boundary: the exact phrases still fire" "$out" "rule=ai-slop/audit/rule-chatbot-artifacts findings=2"

CURSOROUT="$TEST_TMPDIR/cursor-out.txt"
bash "$DETECT" "$CURSOR" >"$CURSOROUT" 2>&1 || true
bash "$SCRIPT_DIR/emit-findings.sh" --from "$CURSOROUT" --out "$TEST_TMPDIR/findings/cursor.md" --branch test-branch >/dev/null 2>&1
cursor_row="$(LC_ALL=C grep -m1 'rule-chatbot-artifacts' "$TEST_TMPDIR/findings/cursor.md")"
assert_contains "cursor: chatbot-artifacts emits at IMPORTANT (crosswalk mirror)" "$cursor_row" "IMPORTANT"
filler_row="$(LC_ALL=C grep -m1 'rule-filler-phrases' "$TEST_TMPDIR/findings/cursor.md")"
assert_contains "cursor: filler-phrases emits at SUGGESTION (crosswalk mirror)" "$filler_row" "SUGGESTION"

# --- Exemptions ------------------------------------------------------------------

out="$(bash "$DETECT" "$MARKED" 2>&1)"
assert_not_contains "line marker: em dash on marked line not flagged" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "line marker: declined count nonzero" "$out" "declined=1"

out="$(bash "$DETECT" "$REASONED" 2>&1)"
assert_not_contains "reasoned line marker: marked line not flagged" "$out" "line=3"
assert_not_contains "reasoned block: block interior not flagged" "$out" "line=6"
assert_contains "reasoned block: -end with a reason still closes the block" "$out" "line=9"
assert_contains "reasoned markers: line and block interior both declined" "$out" "declined=2"

out="$(bash "$DETECT" "$FENCED" 2>&1)"
assert_not_contains "fences: fenced and inline-code content not flagged" "$out" "Finding:"

out="$(bash "$DETECT" "$FILEMARK" 2>&1)"
assert_not_contains "file marker: whole file exempt" "$out" "Finding:"
assert_contains "file marker: counted as declined file" "$out" "(1 files declined)"

out="$(bash "$DETECT" "$DOCMARKS" 2>&1)"
assert_contains "marker mentions: backticked docs do not exempt the file" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "marker mentions: no decline from prose mentions" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 declined=0"

out="$(bash "$DETECT" "$MIXEDMARK" 2>&1)"
assert_not_contains "mixed marker line: a mention of another form does not veto a real marker" "$out" "Finding:"
assert_contains "mixed marker line: the real line marker still declines" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1"

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

# The PRIMARY branch — a directory inside a git checkout expands via git
# ls-files (tracked files only) — needs its own coverage: the fixture above is
# outside any repo, so it exercises only the find fallback.
GITDIR="$TEST_TMPDIR/gitrepo"
mkdir -p "$GITDIR/docs"
git -C "$GITDIR" init -q
cat >"$GITDIR/docs/tracked.md" <<EOF
A tracked em dash ${EM} here.
EOF
cat >"$GITDIR/docs/untracked.md" <<EOF
An untracked em dash ${EM} here.
EOF
git -C "$GITDIR" add docs/tracked.md
out="$(bash "$DETECT" "$GITDIR/docs" 2>&1)"
assert_contains "dir target in git repo: tracked file scanned via ls-files" "$out" "tracked.md"
assert_contains "dir target in git repo: only the tracked file counts" "$out" "1 files scanned"

# Path agreement. One directory has several SPELLINGS on Git Bash: git answers
# the Windows form of the same checkout a shell reaches as "/tmp/...". An
# expansion that derives its prefix from one source and its filter from another
# drops every candidate wherever the two disagree, and the walk that backs it up
# returns untracked markdown in place of the tracked listing (issue 3266). The
# assertion is that the SPELLING of the target cannot change the answer. On a
# host where the two forms already agree these two cases restate the one above,
# which is the point: the invariant holds everywhere, and it is only observable
# here.
GITSPELL="$(git -C "$GITDIR/docs" rev-parse --show-toplevel)/docs"
PWDSPELL="$(cd "$GITDIR/docs" && pwd)"

# Each case asserts the emitted PATH, not just the count. A count alone does not
# pin this: an expansion that discards the caller's spelling and rebuilds every
# path from `git rev-parse --show-toplevel`, which is the anchor that must not
# be reintroduced, still scans exactly one file and would satisfy a count-only
# assertion while reproducing the defect.
out="$(bash "$DETECT" "$GITSPELL" 2>&1)"
assert_contains "dir target, git spelling: only the tracked file counts" "$out" "1 files scanned"
assert_contains "dir target, git spelling: emits the caller's spelling" "$out" "file=$GITSPELL/tracked.md"

out="$(bash "$DETECT" "$PWDSPELL" 2>&1)"
assert_contains "dir target, shell spelling: only the tracked file counts" "$out" "1 files scanned"
assert_contains "dir target, shell spelling: emits the caller's spelling" "$out" "file=$PWDSPELL/tracked.md"

# A trailing slash is the same directory and must expand identically; the
# expansion builds paths by concatenation, so an unnormalized target would emit
# a doubled separator. Two slashes are stripped as readily as one, so a doubled
# separator cannot reach the report and split one file across two target
# strings that `sort -u` is then unable to collapse.
out="$(bash "$DETECT" "$GITDIR/docs/" 2>&1)"
assert_contains "dir target with a trailing slash: only the tracked file counts" "$out" "1 files scanned"
assert_contains "dir target with a trailing slash: no doubled separator" "$out" "file=$GITDIR/docs/tracked.md"

out="$(bash "$DETECT" "$GITDIR/docs//" 2>&1)"
assert_contains "dir target with a doubled trailing slash: no doubled separator" "$out" "file=$GITDIR/docs/tracked.md"

# Subtree restriction. `ls-files` run with `-C <dir>` reports only that
# directory's own subtree, which is what lets the expansion drop the repo root
# from the derivation entirely. A listing anchored at the checkout root instead
# would sweep in this sibling.
mkdir -p "$GITDIR/sibling"
cat >"$GITDIR/sibling/outside.md" <<EOF
A sibling em dash ${EM} here.
EOF
git -C "$GITDIR" add sibling/outside.md
out="$(bash "$DETECT" "$GITDIR/docs" 2>&1)"
assert_contains "dir target: restricted to its own subtree" "$out" "1 files scanned"

# A non-ASCII filename. git C-quotes such a path unless told otherwise, and a
# quoted path fails the scan loop's -f test and is dropped with no finding and
# no declined row. The em dash in this name is the case that matters most here:
# the detector would otherwise never read the file it is named for.
mkdir -p "$GITDIR/unicode"
cat >"$GITDIR/unicode/caf${EM}e.md" <<EOF
An accented em dash ${EM} here.
EOF
git -C "$GITDIR" add "unicode/caf${EM}e.md"
out="$(bash "$DETECT" "$GITDIR/unicode" 2>&1)"
assert_contains "dir target: a non-ASCII filename is scanned, not silently dropped" "$out" "1 files scanned"

# The walk is reserved for a directory genuinely outside a checkout. A directory
# INSIDE one that holds only untracked markdown expands to nothing rather than
# falling through to a filesystem walk, which is what the documented
# tracked-files-only contract means.
mkdir -p "$GITDIR/untrackedonly"
cat >"$GITDIR/untrackedonly/loose.md" <<EOF
A loose em dash ${EM} here.
EOF
out="$(bash "$DETECT" "$GITDIR/untrackedonly" 2>&1)"
assert_contains "dir target in git repo, no tracked markdown: expands to nothing" "$out" "0 files scanned"

# --- Excerpt truncation at the byte boundary --------------------------------------

# 79 ASCII bytes then an em dash: a byte cut at 80 would keep only the first
# byte of the three-byte sequence, emitting invalid UTF-8 into the finding.
LONGLINE="$(printf 'x%.0s' $(seq 1 75)) em${EM}dash tail"
BOUNDARY="$TEST_TMPDIR/boundary.md"
printf '%s\n' "$LONGLINE" >"$BOUNDARY"
out="$(bash "$DETECT" "$BOUNDARY" 2>&1)"
if printf '%s' "$out" | LC_ALL=C grep -q $'\xe2\x80\x94'; then
  pass "excerpt truncation: em dash at boundary survives whole"
elif printf '%s' "$out" | LC_ALL=C grep -q $'\xe2'; then
  fail "excerpt truncation: no partial multi-byte sequence" "whole em dash or none" "lone lead byte present"
else
  pass "excerpt truncation: partial sequence dropped cleanly"
fi

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
# The `date:` frontmatter field is PARSED by the consumer: fix-pass-mode.md
# "Step 1" reads a value only if it is a full ISO-8601 date-time with an explicit
# UTC designator, so the time portion needs COLONS. This assertion previously
# pinned a hyphenated time (`T05-45-10Z`), which is ISO-8601 in neither the
# extended nor the basic profile — it encoded the emitter's bug as the contract.
# The colon-free rule belongs to the FILE NAME (Windows-safe), not to this field.
if LC_ALL=C grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$FOUT"; then
  pass "emit: ISO-8601 extended UTC date"
else
  fail "emit: ISO-8601 extended UTC date" "YYYY-MM-DDThh:mm:ssZ" "$(grep '^date:' "$FOUT")"
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

# A naive gsub double-escapes a pipe the SOURCE already escaped (`a \| b` ->
# `a \\| b`), which GFM reads as a literal backslash plus a LIVE delimiter.
# This repo writes literal `\|` in its own tables, so the case is real.
ALREADY="$TEST_TMPDIR/already-esc.txt"
cat >"$ALREADY" <<'EOF'
Finding: rule=ai-slop/audit/rule-em-dash file=doc.md line=1 fired=a\|b excerpt=text
Summary rule=ai-slop/audit/rule-em-dash findings=1 declined=0 disabled=0
EOF
ALREADY_OUT="$TEST_TMPDIR/findings/already-esc.md"
bash "$EMIT" --from "$ALREADY" --out "$ALREADY_OUT" --branch test-branch >/dev/null 2>&1
already_row="$(LC_ALL=C grep -m1 '^| 1 ' "$ALREADY_OUT")"
assert_not_contains "emit: an already-escaped pipe is not double-escaped" "$already_row" '\\\|'
assert_contains "emit: and survives as a single-escaped literal" "$already_row" 'a\|b'
already_delims="$(printf '%s' "$already_row" | sed 's/\\|//g' | awk -F'|' '{print NF - 1}')"
assert_contains "emit: so the row still parses as exactly 7 cells" "delims=$already_delims" "delims=8"

# Repo-root spelling mismatch: git's toplevel and the caller's pwd can name
# the same directory differently (Git Bash). This producer fails OPEN — a
# mismatch used to leave Location absolute. A symlink makes pwd and
# --show-toplevel disagree on Linux too.
SPELL_REAL="$TEST_TMPDIR/spell-real"
SPELL_LINK="$TEST_TMPDIR/spell-link"
mkdir -p "$SPELL_REAL"
(
  cd "$SPELL_REAL" || exit 1
  git init -q .
  git config user.email t@example.com
  git config user.name Test
)
ln -s "$SPELL_REAL" "$SPELL_LINK"
printf 'Finding: rule=ai-slop/audit/rule-em-dash file=%s/doc.md line=1 fired=zero excerpt=text\n' "$SPELL_LINK" >"$TEST_TMPDIR/spell.txt"
printf 'Summary rule=ai-slop/audit/rule-em-dash findings=1 declined=0 disabled=0\n' >>"$TEST_TMPDIR/spell.txt"
SPELL_OUT="$TEST_TMPDIR/findings/spell.md"
(cd "$SPELL_LINK" && bash "$EMIT" --from "$TEST_TMPDIR/spell.txt" --out "$SPELL_OUT" --branch test-branch) >/dev/null 2>&1
spell_body="$(cat "$SPELL_OUT")"
assert_contains "emit: a pwd-spelled absolute path is relativized" "$spell_body" "| doc.md:1 |"
assert_not_contains "emit: Location carries no absolute prefix" "$spell_body" "$SPELL_LINK/doc.md"
assert_not_contains "emit: Location carries no git-toplevel prefix either" "$spell_body" "$SPELL_REAL/doc.md"

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

# --- emit: branch names that are YAML indicators ---------------------------------
#
# git accepts branch names beginning with a YAML indicator: `git check-ref-format
# --branch` calls "@foo", "!foo", "#foo" and "&foo" all valid. Emitted as a bare
# plain scalar, "#foo" and "&foo" parse to null and "@foo"/"!foo"/"*foo" are
# parse errors. The consumer (review/fanout fix-pass-mode.md "Step 1") admits a
# findings file only when its `branch:` value equals the current branch EXACTLY,
# so a misparse silently drops every finding for that branch — no error, and
# nothing distinguishing it from "no findings".
#
# Both directions are asserted. Quoting is CONDITIONAL, so an ordinary branch
# name must stay a byte-identical plain scalar: a helper that quoted
# unconditionally would pass a quoted-only assertion while moving the wire
# format for every ordinary branch. `*foo` is not a legal git branch name, but
# --branch takes an arbitrary string, so the predicate is still asserted on it.
emit_branch_line() {
  # emit_branch_line <branch> -> the emitted `branch:` frontmatter line
  local b="$1" out="$TEST_TMPDIR/findings/ybranch.md"
  # Non-overwrite naming would divert a leftover sibling to ybranch-2.md.
  rm -f "$TEST_TMPDIR/findings/ybranch"*.md
  # Stdin closed: a missing-file grep that fell through to stdin would hang
  # the suite (the Windows Git Bash failure mode that blocked the first
  # widening of this loop). The emitter itself does not read stdin.
  bash "$EMIT" --from "$DETOUT" --out "$out" --branch "$b" </dev/null >/dev/null 2>&1 || true
  [[ -f "$out" ]] || {
    printf 'MISSING\n'
    return 0
  }
  LC_ALL=C grep -m1 '^branch:' "$out" </dev/null || true
}

# EVERY character in the predicate's indicator class is asserted, not a sample.
# A five-name sample stayed green after `|`, `>`, `%`, backtick, `"` and `'`
# were dropped from a sibling — the drift acceptance criterion 3 forbids.
# `-foo` is omitted: git rejects it, and --branch treats a leading `-` as a
# missing option value (exit 2), so no caller can reach the predicate with it.
for b in '?foo' ':foo' ',foo' '[foo' ']foo' '{foo' '}foo' '#foo' \
  '&foo' '*foo' '!foo' '|foo' '>foo' '%foo' '@foo' '`foo' "'foo"; do
  got="$(emit_branch_line "$b")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "emit: indicator branch '$b' is emitted as a quoted scalar"
  else
    fail "emit: indicator branch '$b' is emitted as a quoted scalar" "$want" "$got"
  fi
done

# The double-quote indicator, whose expected form carries an escape.
got="$(emit_branch_line '"foo')"
if [[ "$got" == 'branch: "\"foo"' ]]; then
  pass 'emit: indicator branch (leading double quote) is quoted and escaped'
else
  fail 'emit: indicator branch (leading double quote) is quoted and escaped' 'branch: "\"foo"' "$got"
fi

# Non-leading `: ` and ` #` also force quoting: both end a plain scalar early.
for b in 'has: colon' 'has #hash'; do
  got="$(emit_branch_line "$b")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "emit: branch '$b' is quoted (plain scalar would end early)"
  else
    fail "emit: branch '$b' is quoted (plain scalar would end early)" "$want" "$got"
  fi
done

for b in 'main' 'feat/3179-slug' 'release-1.2_x'; do
  got="$(emit_branch_line "$b")"
  want="branch: $b"
  if [[ "$got" == "$want" ]]; then
    pass "emit: ordinary branch '$b' stays an unquoted plain scalar"
  else
    fail "emit: ordinary branch '$b' stays an unquoted plain scalar" "$want" "$got"
  fi
done

# YAML implicit types: git accepts these as branch names, but a bare scalar
# becomes a boolean, null, or number and the consumer's exact-match drops
# every finding.
for b in true null 123 yes FALSE '~'; do
  got="$(emit_branch_line "$b")"
  want="branch: \"$b\""
  if [[ "$got" == "$want" ]]; then
    pass "emit: implicit-type branch '$b' is quoted"
  else
    fail "emit: implicit-type branch '$b' is quoted" "$want" "$got"
  fi
done

# The quoting must survive a branch name carrying the quote character itself —
# otherwise the emitted scalar is quoted but unparsable, trading a silent drop
# for a hard consumer failure. A BACKSLASH is deliberately not asserted: git
# rejects it in a branch name (`git check-ref-format --branch 'a\b'` fails), and
# awk consumes it as an escape at the -v assignment boundary before the helper
# ever runs, so an assertion here would pin an awk -v artifact on an input that
# cannot occur rather than this producer's quoting.
got="$(emit_branch_line '@with"quote')"
if [[ "$got" == 'branch: "@with\"quote"' ]]; then
  pass "emit: a quote character inside an indicator branch is escaped"
else
  fail "emit: a quote character inside an indicator branch is escaped" 'branch: "@with\"quote"' "$got"
fi

# --- Roster agreement: every rule's tier is asserted -----------------------------
#
# emit-findings.sh's rule_tier() declares itself a MIRROR of the severity
# crosswalk, and a mirror nothing compares drifts silently. Asserting two rules
# (as this suite did) left thirteen unguarded, so a rule added to detect.sh
# without a crosswalk row would emit SUGGESTION by fall-through and look
# deliberate. Two properties are checked here:
#   1. every slug detect.sh reports carries its expected tier through the emitter
#   2. the roster ITSELF has not changed — a new rule fails until it is tabled
# The expected set is written out rather than derived, so the test disagrees with
# the code instead of restating it.

EXPECTED_IMPORTANT="rule-knowledge-cutoff-disclaimer rule-llm-citation-artifacts rule-chatbot-artifacts"
EXPECTED_SUGGESTION="rule-em-dash rule-emoji-formatting rule-curly-artifacts rule-significance-inflation rule-negative-parallelism rule-challenges-conclusion rule-utm-params rule-filler-phrases rule-stacked-hedging rule-ai-vocabulary rule-copulative-avoidance rule-rule-of-three"

# The roster detect.sh actually ships, taken from its Summary rows on any run.
ROSTER="$(bash "$DETECT" "$CLEAN" 2>&1 | LC_ALL=C sed -n 's|^Summary rule=ai-slop/audit/\([a-z-]*\) .*|\1|p' | sort)"
EXPECTED_ROSTER="$(printf '%s %s' "$EXPECTED_IMPORTANT" "$EXPECTED_SUGGESTION" | tr ' ' '\n' | sort)"
if [[ "$ROSTER" == "$EXPECTED_ROSTER" ]]; then
  pass "roster agreement: detect.sh ships exactly the 15 tabled rules"
else
  fail "roster agreement: detect.sh ships exactly the 15 tabled rules" \
    "the tabled set" "$(diff <(echo "$EXPECTED_ROSTER") <(echo "$ROSTER") | tr '\n' ' ')"
fi

# Synthetic detector output naming every slug: a fixture that fired all 15
# organically would be a slop corpus this plugin then has to exempt from itself.
TIERSRC="$TEST_TMPDIR/tier-src.txt"
: >"$TIERSRC"
for slug in $EXPECTED_IMPORTANT $EXPECTED_SUGGESTION; do
  printf 'Finding: rule=ai-slop/audit/%s file=doc.md line=1 fired=synthetic excerpt=sample\n' "$slug" >>"$TIERSRC"
  printf 'Summary rule=ai-slop/audit/%s findings=1 declined=0 disabled=0\n' "$slug" >>"$TIERSRC"
done

TIEROUT="$TEST_TMPDIR/findings/tiers.md"
bash "$EMIT" --from "$TIERSRC" --out "$TIEROUT" --branch test-branch >/dev/null 2>&1
tier_content="$(cat "$TIEROUT")"

for slug in $EXPECTED_IMPORTANT; do
  row="$(LC_ALL=C grep -m1 "ai-slop/audit/$slug " "$TIEROUT")"
  case "$row" in
  *"| IMPORTANT |"*) pass "tier mirror: $slug is IMPORTANT" ;;
  *) fail "tier mirror: $slug is IMPORTANT" "IMPORTANT" "$row" ;;
  esac
done
for slug in $EXPECTED_SUGGESTION; do
  row="$(LC_ALL=C grep -m1 "ai-slop/audit/$slug " "$TIEROUT")"
  case "$row" in
  *"| SUGGESTION |"*) pass "tier mirror: $slug is SUGGESTION" ;;
  *) fail "tier mirror: $slug is SUGGESTION" "SUGGESTION" "$row" ;;
  esac
done

# F5 regression guard: both owner docs say this producer omits `tier:`.
assert_not_contains "frontmatter: no uncomputed tier: field" "$tier_content" "tier:"
assert_contains "action: filler-phrases carries its substitution, not the generic judgment string" \
  "$(LC_ALL=C grep -m1 'rule-filler-phrases' "$TIEROUT")" 'in order to'
assert_contains "action: stacked-hedging names the one-hedge repair" \
  "$(LC_ALL=C grep -m1 'rule-stacked-hedging' "$TIEROUT")" "states the real uncertainty"

# --- Result ---------------------------------------------------------------------

echo
if [[ "$FAILED" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed"
  exit 0
else
  echo "$FAILED of $CASE_NUM cases FAILED"
  exit 1
fi

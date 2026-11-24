#!/usr/bin/env bash
set -uo pipefail

unset GIT_DIR GIT_WORK_TREE GIT_CONFIG
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/dev/null}" GIT_CONFIG_NOSYSTEM=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DETECT="$SCRIPT_DIR/detect.sh"
TEST_TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export HOME="$TEST_TMPDIR/home"
export CLAUDE_PROJECT_DIR="$TEST_TMPDIR/noconfig"
mkdir -p "$HOME" "$CLAUDE_PROJECT_DIR"

make_repo() {
  git init -q "$1" >/dev/null 2>&1
}

# shellcheck source=lib/test-helpers.sh
source "$SCRIPT_DIR/lib/test-helpers.sh"
EXPECTED_CASES=283

assert_eq() {
  if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1" "$3" "$2"; fi
}

EM=$'\xe2\x80\x94'
CHECKMARK=$'\xe2\x9c\x85'
WARNSIGN=$'\xe2\x9a\xa0'
LQUO=$'\xe2\x80\x9c'
RQUO=$'\xe2\x80\x9d'

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

GENPROSE="$TEST_TMPDIR/general-prose.md"
cat >"$GENPROSE" <<'EOF'
# General-prose rules

Great question! I hope this helps, and let me know if you need more.
We did this in order to ship, due to the fact that the deadline slipped.
It could potentially fail here and might possibly regress there.
We leverage tools to facilitate work and utilize helpers for the rest.
EOF

GENPROSENEG="$TEST_TMPDIR/general-prose-neg.md"
cat >"$GENPROSENEG" <<'EOF'
# Benign neighbors of the general-prose patterns

Feel free to customize the config for your repo. The run may fail on old
shells, and a question mark ends each prompt. Sort keys in ascending order to
keep diffs stable.
EOF

WORDBOUND="$TEST_TMPDIR/wordbound.md"
cat >"$WORDBOUND" <<'EOF'
# Phrase prefixes inside ordinary words

These are great questions for the reviewer to work through.
The team found the smoking guns in yesterday's logs.
EOF

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

out="$(bash "$DETECT" "$ALLRULES" 2>&1)"
assert_contains "roster: emoji-formatting fires on bullet line" "$out" "Finding: rule=ai-slop/audit/rule-emoji-formatting"
assert_contains "roster: curly-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-curly-artifacts"
assert_contains "roster: negative-parallelism fires" "$out" "Finding: rule=ai-slop/audit/rule-negative-parallelism"
assert_contains "roster: challenges-conclusion fires" "$out" "Finding: rule=ai-slop/audit/rule-challenges-conclusion"
assert_contains "roster: knowledge-cutoff fires" "$out" "Finding: rule=ai-slop/audit/rule-knowledge-cutoff-disclaimer"
assert_contains "roster: citation-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-llm-citation-artifacts"
assert_contains "roster: utm-params fires" "$out" "Finding: rule=ai-slop/audit/rule-utm-params"
assert_contains "roster: copulative-avoidance density fires" "$out" "Finding: rule=ai-slop/audit/rule-copulative-avoidance"
assert_not_contains "roster: rule-of-three is rubric-demoted, no finding" "$out" "rule=ai-slop/audit/rule-rule-of-three"

out="$(bash "$DETECT" "$MIDEMOJI" 2>&1)"
assert_not_contains "emoji negative: content-position emoji does not fire the formatting rule" "$out" "Finding: rule=ai-slop/audit/rule-emoji-formatting"

BQEMOJI="$TEST_TMPDIR/bqemoji.md"
cat >"$BQEMOJI" <<EOF
# Blockquote emoji

> ${WARNSIGN} note
> ### ${WARNSIGN} note
  - ${WARNSIGN} note
EOF
out="$(bash "$DETECT" "$BQEMOJI" 2>&1)"
assert_contains "emoji: blockquote, blockquote-heading, and indented-bullet markers all fire" "$out" "rule=ai-slop/audit/rule-emoji-formatting findings=3"

BQNEG="$TEST_TMPDIR/bqneg.md"
cat >"$BQNEG" <<EOF
# Blockquote content

> The reaction was ${CHECKMARK} from the team.
EOF
out="$(bash "$DETECT" "$BQNEG" 2>&1)"
assert_not_contains "emoji negative: content-position emoji behind a blockquote does not fire" "$out" "Finding: rule=ai-slop/audit/rule-emoji-formatting"

BQCODE="$TEST_TMPDIR/bqcode.md"
cat >"$BQCODE" <<EOF
# Quoted code

>     ${WARNSIGN} literal code inside a quoted code block

> ${WARNSIGN} a real callout
EOF
out="$(bash "$DETECT" "$BQCODE" 2>&1)"
assert_contains "emoji: the real callout in a quote fires" "$out" "rule=ai-slop/audit/rule-emoji-formatting findings=1"
assert_not_contains "emoji negative: an indented code line inside a quote does not fire" "$out" "literal code"

out="$(bash "$DETECT" "$GENPROSE" 2>&1)"
assert_contains "general-prose: chatbot-artifacts fires" "$out" "Finding: rule=ai-slop/audit/rule-chatbot-artifacts"
assert_contains "general-prose: filler-phrases fires" "$out" "Finding: rule=ai-slop/audit/rule-filler-phrases"
assert_contains "general-prose: stacked-hedging fires" "$out" "Finding: rule=ai-slop/audit/rule-stacked-hedging"
assert_contains "general-prose: plain-word vocab additions fire the density rule" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"

out="$(bash "$DETECT" "$GENPROSENEG" 2>&1)"
assert_not_contains "general-prose negative: benign near-miss phrasing stays quiet" "$out" "Finding:"

out="$(bash "$DETECT" "$WORDBOUND" 2>&1)"
assert_not_contains "word boundary: 'great questions' does not fire the chat-residue rule" "$out" "Finding:"
WORDBOUNDPOS="$TEST_TMPDIR/wordboundpos.md"
cat >"$WORDBOUNDPOS" <<'EOF'
# The real thing

Great question! The retry budget is three attempts.
Found the smoking gun in the connection pool.
EOF
out="$(bash "$DETECT" "$WORDBOUNDPOS" 2>&1)"
assert_contains "word boundary: the exact phrases still fire" "$out" "rule=ai-slop/audit/rule-chatbot-artifacts findings=2"

GENPROSEOUT="$TEST_TMPDIR/general-prose-out.txt"
bash "$DETECT" "$GENPROSE" >"$GENPROSEOUT" 2>&1 || true
bash "$SCRIPT_DIR/emit-findings.sh" --from "$GENPROSEOUT" --out "$TEST_TMPDIR/findings/general-prose.md" --branch test-branch >/dev/null 2>&1
chatbot_row="$(LC_ALL=C grep -m1 'rule-chatbot-artifacts' "$TEST_TMPDIR/findings/general-prose.md")"
assert_contains "general-prose: chatbot-artifacts emits at IMPORTANT (crosswalk mirror)" "$chatbot_row" "IMPORTANT"
filler_row="$(LC_ALL=C grep -m1 'rule-filler-phrases' "$TEST_TMPDIR/findings/general-prose.md")"
assert_contains "general-prose: filler-phrases emits at SUGGESTION (crosswalk mirror)" "$filler_row" "SUGGESTION"

QUOTED="$TEST_TMPDIR/quoted.md"
cat >"$QUOTED" <<EOF
# Quoted material

> The source says we did this in order to ship on time ${EM} verbatim quote.

The guide bans "in order to" and recommends the shorter form.

Plain prose written in order to trip the wording rule.
EOF
out="$(bash "$DETECT" "$QUOTED" 2>&1)"
assert_contains "quote exemption: unquoted filler still fires" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1"
assert_contains "quote exemption: blockquote and quoted-span hits declined" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1 declined=2"
assert_contains "quote exemption: typography rule still fires inside the blockquote" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"

QUOTEDBLOCK="$TEST_TMPDIR/quotedblock.md"
cat >"$QUOTEDBLOCK" <<EOF
# Quoted block markers

> <!-- ai-slop-ignore-start: verbatim quote -->
> The source says ship ${EM} now.
> <!-- ai-slop-ignore-end: end of quote -->
EOF
out="$(bash "$DETECT" "$QUOTEDBLOCK" 2>&1)"
assert_contains "quote markers: a quoted start/end pair does not suppress the em dash" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 declined=0"

OUTSIDEBLOCK="$TEST_TMPDIR/outsideblock.md"
cat >"$OUTSIDEBLOCK" <<EOF
# Outside block markers

<!-- ai-slop-ignore-start: verbatim quote -->
> The source says ship ${EM} now.
<!-- ai-slop-ignore-end: end of quote -->
EOF
out="$(bash "$DETECT" "$OUTSIDEBLOCK" 2>&1)"
assert_contains "quote markers: a start/end pair outside the blockquote suppresses the em dash" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=1"

UNCLOSED="$TEST_TMPDIR/unclosed.md"
cat >"$UNCLOSED" <<EOF
# Unclosed block

<!-- ai-slop-ignore-start: verbatim quote -->
> The source says ship ${EM} now.
> <!-- ai-slop-ignore-end: end of quote -->

Later prose ${EM} after the quote.
EOF
out="$(bash "$DETECT" "$UNCLOSED" 2>&1)"
assert_contains "quote markers: a quoted end does not close, declining later prose" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=2 declined_marker=2"

CUTOFF="$TEST_TMPDIR/cutoff.md"
cat >"$CUTOFF" <<'EOF'
# Source-gap speculation

As of my last knowledge update, the API had no batch endpoint.
While specific details are scarce, the rollout continued.
This is not widely documented behavior.
The change appears in the provided sources only.
Based on available information, the flag defaults to off.
EOF
out="$(bash "$DETECT" "$CUTOFF" 2>&1)"
assert_contains "cutoff families: all five source-gap lines fire" "$out" "rule=ai-slop/audit/rule-knowledge-cutoff-disclaimer findings=5"

RAP="$TEST_TMPDIR/rap-repo"
mkdir -p "$RAP/docs/conventions"
make_repo "$RAP"
cat >"$RAP/docs/conventions/ai-slop.yaml" <<'EOF'
rule_allowed_paths:
  rule-filler-phrases: ["quirks/**"]
EOF
mkdir -p "$RAP/quirks"
printf '# Quirks\n\nWritten in order to stay exempt here.\n' >"$RAP/quirks/doc.md"
printf '# Plain\n\nWritten in order to fire here.\n' >"$RAP/plain.md"
out="$(CLAUDE_PROJECT_DIR="$RAP" bash "$DETECT" "$RAP/quirks/doc.md" "$RAP/plain.md" 2>&1)"
assert_contains "rule_allowed_paths: unlisted file still fires" "$out" "file=plain.md"
assert_not_contains "rule_allowed_paths: listed path declines the one rule" "$out" "file=quirks/doc.md"
assert_contains "rule_allowed_paths: decline counted for the exempted rule" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1 declined=1"

DECOY="$TEST_TMPDIR/rap-decoy"
mkdir -p "$DECOY/quirks/inner"
printf 'decoy\n' >"$DECOY/quirks/decoy.txt"
printf 'decoy\n' >"$DECOY/quirks/inner/decoy.txt"
mkdir -p "$RAP/quirks/nested"
printf '# Nested\n\nWritten in order to stay exempt here too.\n' >"$RAP/quirks/nested/deep.md"
out="$(cd "$DECOY" && CLAUDE_PROJECT_DIR="$RAP" bash "$DETECT" "$RAP/quirks/doc.md" "$RAP/quirks/nested/deep.md" "$RAP/plain.md" 2>&1)"
assert_not_contains "glob expansion: exemption survives a cwd where the glob expands" "$out" "file=quirks/doc.md"
assert_not_contains "glob expansion: ** crosses / for nested paths" "$out" "file=quirks/nested/deep.md"
assert_contains "glob expansion: unlisted file still fires from the decoy cwd" "$out" "file=plain.md"
assert_contains "glob expansion: both exempt files counted as declined" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1 declined=2"

WIDE="$TEST_TMPDIR/rap-wide"
mkdir -p "$WIDE/docs/conventions" "$WIDE/sub/deep"
make_repo "$WIDE"
cat >"$WIDE/docs/conventions/ai-slop.yaml" <<'EOF'
rule_allowed_paths:
  rule-filler-phrases: ["sub/*.md"]
EOF
printf '# Deep\n\nWritten in order to test star depth.\n' >"$WIDE/sub/deep/nested.md"
out="$(CLAUDE_PROJECT_DIR="$WIDE" bash "$DETECT" "$WIDE/sub/deep/nested.md" 2>&1)"
assert_contains "glob semantics: * crosses / (case fnmatch, no FNM_PATHNAME)" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=0 declined=1"

PHRASES_FIX="$TEST_TMPDIR/model-phrases.md"
cat >"$PHRASES_FIX" <<'EOF'
# Model phrases

Calibration is the part most people skip.
The honest take is that this works.
Small files parse faster, and that's the unlock.
We quoted "that's the unlock" on this line to document it.
EOF
out="$(bash "$DETECT" "$PHRASES_FIX" 2>&1)"
assert_contains "model phrases: anchored constructions fire per occurrence" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=3 declined=1"
assert_contains "model phrases: finding rows name the rule" "$out" "Finding: rule=ai-slop/audit/rule-model-era-phrases"

BAREFIX="$TEST_TMPDIR/bare-phrases.md"
cat >"$BAREFIX" <<'EOF'
# Bare forms

The unlock flow starts on the device screen.
An honest take from a human maintainer follows.
EOF
out="$(bash "$DETECT" "$BAREFIX" 2>&1)"
assert_contains "model phrases: bare bigrams do not fire (anchored roster only)" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=0 declined=0"

PREPO="$TEST_TMPDIR/phrase-repo"
mkdir -p "$PREPO/docs/conventions"
make_repo "$PREPO"
cat >"$PREPO/docs/conventions/ai-slop.yaml" <<'EOF'
phrase_add: ["chef.s kiss architecture"]
phrase_remove: ["(the|my) honest take"]
EOF
cat >"$PREPO/doc.md" <<'EOF'
# Doc

Calibration is the part most people skip.
The honest take is that this works.
This design is chef's kiss architecture, honestly.
The kiss of death for caches is a stale key.
EOF
out="$(CLAUDE_PROJECT_DIR="$PREPO" bash "$DETECT" "$PREPO/doc.md" 2>&1)"
assert_contains "phrase config: add fires whole, remove silences, no word-split" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=2 declined=0"

EMPTYREPO="$TEST_TMPDIR/phrase-empty"
mkdir -p "$EMPTYREPO/docs/conventions"
make_repo "$EMPTYREPO"
cat >"$EMPTYREPO/docs/conventions/ai-slop.yaml" <<'EOF'
phrase_remove: ["the part most people skip", "(the|my) honest take", "that.s the unlock"]
EOF
cp "$PHRASES_FIX" "$EMPTYREPO/doc.md"
out="$(CLAUDE_PROJECT_DIR="$EMPTYREPO" bash "$DETECT" "$EMPTYREPO/doc.md" 2>&1)"
assert_not_contains "phrase config: emptied roster emits no findings" "$out" "Finding: rule=ai-slop/audit/rule-model-era-phrases"
assert_contains "phrase config: emptied roster still reports its summary row" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=0 declined=0"

BADREPO="$TEST_TMPDIR/phrase-bad"
BADHOME="$TEST_TMPDIR/phrase-bad-home"
mkdir -p "$BADREPO" "$BADHOME/.claude"
make_repo "$BADREPO"
cat >"$BADHOME/.claude/ai-slop.json" <<'EOF'
{ "phrase_add": ["", "broken ("] }
EOF
cp "$PHRASES_FIX" "$BADREPO/doc.md"
out="$(HOME="$BADHOME" CLAUDE_PROJECT_DIR="$BADREPO" bash "$DETECT" "$BADREPO/doc.md" 2>&1)"
assert_contains "phrase hygiene: invalid fragment skipped with a note naming it" "$out" "phrase_add fragment is not a valid ERE, skipped: 'broken ('"
assert_contains "phrase hygiene: shipped roster keeps firing past the bad fragment" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=3 declined=1"
out="$(HOME="$BADHOME" CLAUDE_PROJECT_DIR="$BADREPO" bash "$DETECT" "$CLEAN" 2>&1)"
assert_not_contains "phrase hygiene: empty-string element does not flood clean prose" "$out" "Finding: rule=ai-slop/audit/rule-model-era-phrases"

CLRREPO="$TEST_TMPDIR/phrase-clear"
mkdir -p "$CLRREPO/docs/conventions"
make_repo "$CLRREPO"
cat >"$CLRREPO/docs/conventions/ai-slop.yaml" <<'EOF'
phrase_add: ["chef.s kiss architecture"]
EOF
cat >"$CLRREPO/docs/conventions/ai-slop.local.yaml" <<'EOF'
phrase_add: []
EOF
cat >"$CLRREPO/doc.md" <<'EOF'
# Doc

This design is chef's kiss architecture, honestly.
EOF
out="$(CLAUDE_PROJECT_DIR="$CLRREPO" bash "$DETECT" "$CLRREPO/doc.md" 2>&1)"
assert_contains "phrase config: explicit empty array clears the inherited add list" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=0 declined=0"

TRUNCPHRASE="$TEST_TMPDIR/phrase-trunc"
TRUNCPHOME="$TEST_TMPDIR/phrase-trunc-home"
mkdir -p "$TRUNCPHRASE" "$TRUNCPHOME/.claude"
make_repo "$TRUNCPHRASE"
printf '%s\n' '{ "phrase_add": ["chef.s kiss architecture"] }' '{bad' >"$TRUNCPHOME/.claude/ai-slop.json"
cp "$CLRREPO/doc.md" "$TRUNCPHRASE/doc.md"
out="$(HOME="$TRUNCPHOME" CLAUDE_PROJECT_DIR="$TRUNCPHRASE" bash "$DETECT" "$TRUNCPHRASE/doc.md" 2>&1)"
assert_contains "phrase config: partially parsed layer is refused, no phrase added" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=0 declined=0"

DISREPO="$TEST_TMPDIR/phrase-disabled"
mkdir -p "$DISREPO/docs/conventions"
make_repo "$DISREPO"
cat >"$DISREPO/docs/conventions/ai-slop.yaml" <<'EOF'
disabled_rules: ["rule-model-era-phrases"]
EOF
cp "$PHRASES_FIX" "$DISREPO/doc.md"
out="$(CLAUDE_PROJECT_DIR="$DISREPO" bash "$DETECT" "$DISREPO/doc.md" 2>&1)"
assert_not_contains "phrase config: disabled rule emits no findings" "$out" "Finding: rule=ai-slop/audit/rule-model-era-phrases"
assert_contains "phrase config: disabled rule reported in summary" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=1"

out="$(CLAUDE_PROJECT_DIR="$PREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "show-config: effective phrase roster shown" "$out" "model_phrases=(the part most people skip|that.s the unlock|chef.s kiss architecture)"

CATALOG_MD="$SCRIPT_DIR/../reference/catalog.md"
grade_violations="$(awk '/^## Model-era additions/{insec=1} insec && /^### rule-/{slug=$2} insec && /evidence: locally-observed/{lo[slug]=1} insec && /v1: script/{sc[slug]=1} END{for (s in lo) if (s in sc) print s}' "$CATALOG_MD")"
if [[ -z "$grade_violations" ]]; then
  pass "catalog gate: no locally-observed entry ships as a script rule"
else
  fail "catalog gate: no locally-observed entry ships as a script rule" "no slugs" "$grade_violations"
fi

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

LT="$TEST_TMPDIR/list-targets"
mkdir -p "$LT/sub" "$LT/vendor" "$LT/docs/conventions"
make_repo "$LT"
printf 'one\n' >"$LT/a.md"
printf 'two\n' >"$LT/sub/b.md"
printf 'three\n' >"$LT/vendor/c.md"
printf '%s\n' 'excluded_paths: ["vendor/**"]' >"$LT/docs/conventions/ai-slop.yaml"
git -C "$LT" add -A >/dev/null 2>&1
TAB=$'\t'
out="$(CLAUDE_PROJECT_DIR="$LT" bash "$DETECT" --list-targets --offset 0 --limit 1 "$LT" "$LT/missing.md" 2>/dev/null)"
rc=$?
assert_exit "list-targets: exit 0" 0 "$rc"
assert_contains "list-targets: key is the file= spelling, then the path" "$out" "a.md${TAB}$LT/a.md"
assert_contains "list-targets: a directory target expands" "$out" "sub/b.md${TAB}$LT/sub/b.md"
assert_not_contains "list-targets: excluded_paths drops the file" "$out" "vendor/c.md"
assert_not_contains "list-targets: a missing file is dropped" "$out" "missing.md"
assert_eq "list-targets: offset and limit are ignored, no Summary rows" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
out="$(bash "$DETECT" --list-targets --show-config 2>&1)"
assert_contains "list-targets: --show-config wins" "$out" "Config layers"
printf '%s\t%s\n' slop.md "$SLOP" >"$TEST_TMPDIR/listed.tsv"
out="$(bash "$DETECT" --paths-file "$TEST_TMPDIR/listed.tsv" 2>&1)"
assert_contains "list-targets: its output is a valid --paths-file" "$out" "across 1 files scanned"
TABF="$TEST_TMPDIR/tab${TAB}in${TAB}name.md"
if printf 'x\n' >"$TABF" 2>/dev/null && [[ -f "$TABF" ]]; then
  printf '%s\n' "$TABF" >"$TEST_TMPDIR/tabpath.txt"
  out="$(bash "$DETECT" --paths-file "$TEST_TMPDIR/tabpath.txt" 2>&1)"
  assert_contains "paths-file: a line with two tabs is the whole path" "$out" "across 1 files scanned"
else
  skip "paths-file: a line with two tabs is the whole path" "no tab in file names"
fi

EPREPO="$TEST_TMPDIR/empty-pf-repo"
mkdir -p "$EPREPO"
printf 'Tracked %s here.\n' "$EM" >"$EPREPO/tracked.md"
(
  cd "$EPREPO" || exit 1
  git init -q .
  git add tracked.md 2>/dev/null
)
printf '\n\n' >"$TEST_TMPDIR/empty-paths.txt"
out="$(CLAUDE_PROJECT_DIR="$EPREPO" bash "$DETECT" --paths-file "$TEST_TMPDIR/empty-paths.txt" 2>&1)"
assert_not_contains "empty paths-file: the repository listing is not scanned" "$out" "tracked.md"
assert_contains "empty paths-file: stderr says the list is empty" "$out" "lists no paths"
assert_contains "empty paths-file: zero-file Summary" "$out" "0 findings across 0 files scanned"

cfgdir="$TEST_TMPDIR/repo/docs/conventions"
mkdir -p "$cfgdir"
make_repo "$TEST_TMPDIR/repo"
cp "$SLOP" "$TEST_TMPDIR/repo/allowed.md"
cat >"$cfgdir/ai-slop.yaml" <<'EOF'
em_dash_allowed_paths: ["allowed.md"]
thresholds:
  ai_vocabulary: 999
  copulative_avoidance: 999
disabled_rules: ["rule-significance-inflation"]
EOF
out="$(cd "$TEST_TMPDIR/repo" && CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" "$TEST_TMPDIR/repo/allowed.md" 2>&1)"
assert_not_contains "config: em_dash_allowed_paths exempts the document" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_not_contains "config: raised threshold silences vocabulary rule" "$out" "Finding: rule=ai-slop/audit/rule-ai-vocabulary"
assert_not_contains "config: disabled rule emits no findings" "$out" "Finding: rule=ai-slop/audit/rule-significance-inflation"
assert_contains "config: disabled rule reported in summary" "$out" "rule=ai-slop/audit/rule-significance-inflation findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=1"

out="$(CLAUDE_PROJECT_DIR="$TEST_TMPDIR/repo" bash "$DETECT" --show-config 2>&1)"
assert_contains "show-config: names the supplying layer" "$out" "$cfgdir/ai-slop.yaml"
assert_contains "show-config: effective threshold shown" "$out" "threshold_ai_vocabulary=999"
assert_contains "show-config: disabled rules shown" "$out" "disabled_rules=rule-significance-inflation"

HOMEROOT="$TEST_TMPDIR/home-root"
mkdir -p "$HOMEROOT/.claude"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 777 } }' >"$HOMEROOT/.claude/ai-slop.json"
out="$(HOME="$HOMEROOT" CLAUDE_PROJECT_DIR="$HOMEROOT" bash "$DETECT" --show-config 2>&1)"
assert_eq "home root: the user-global file is listed once" "$(printf '%s\n' "$out" | grep -cxF "  $HOMEROOT/.claude/ai-slop.json")" "1"
assert_contains "home root: the user-global threshold applies" "$out" "threshold_ai_vocabulary=777"
make_repo "$HOMEROOT"
mkdir -p "$HOMEROOT/docs/conventions"
printf '%s\n' 'thresholds:' '  ai_vocabulary: 666' >"$HOMEROOT/docs/conventions/ai-slop.yaml"
out="$(HOME="$HOMEROOT" CLAUDE_PROJECT_DIR="$HOMEROOT" bash "$DETECT" --show-config 2>&1)"
assert_eq "a git repository at the home is still a home root" "$(printf '%s\n' "$out" | grep -cxF "  $HOMEROOT/.claude/ai-slop.json")" "1"
assert_not_contains "a home root: its YAML is not a team layer" "$out" "$HOMEROOT/docs/conventions/ai-slop.yaml"
NONREPO="$TEST_TMPDIR/non-repo-root"
mkdir -p "$NONREPO/docs/conventions"
printf '%s\n' 'thresholds:' '  ai_vocabulary: 555' >"$NONREPO/docs/conventions/ai-slop.yaml"
out="$(CLAUDE_PROJECT_DIR="$NONREPO" bash "$DETECT" --show-config 2>&1)"
assert_not_contains "a non-repo root: its YAML is not a team layer" "$out" "$NONREPO/docs/conventions/ai-slop.yaml"

DUALREPO="$TEST_TMPDIR/dual-read-repo"
DUALHOME="$TEST_TMPDIR/dual-read-home"
mkdir -p "$DUALREPO/docs/conventions" "$DUALHOME/.claude"
make_repo "$DUALREPO"
DUALTEAM="$DUALREPO/docs/conventions/ai-slop.yaml"
DUALLOCAL="$DUALREPO/docs/conventions/ai-slop.local.yaml"
DUALOLD="$DUALHOME/.claude/ai-slop.json"
printf '%s\n' 'thresholds:' '  ai_vocabulary: 5' '  copulative_avoidance: 6' >"$DUALTEAM"
printf '%s\n' 'thresholds:' '  ai_vocabulary: 11' >"$DUALLOCAL"
out="$(CLAUDE_PROJECT_DIR="$DUALREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "new layer only: the personal override supplies its value" "$out" "threshold_ai_vocabulary=11 (rule rule-ai-vocabulary) [layer: $DUALLOCAL]"
assert_not_contains "new layer only: no old-path warning" "$out" "old path"

rm "$DUALLOCAL"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 22 } }' >"$DUALOLD"
out="$(HOME="$DUALHOME" CLAUDE_PROJECT_DIR="$DUALREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "old file only: its value applies in the personal layer's place" "$out" "threshold_ai_vocabulary=22 (rule rule-ai-vocabulary) [layer: $DUALOLD]"
assert_contains "old file only: the team file still supplies the key the old file left" "$out" "threshold_copulative_avoidance=6 (rule rule-copulative-avoidance) [layer: $DUALTEAM]"
assert_contains "old file only: the warning names the old file, the new location and setup" "$out" "Warning: $DUALOLD is an old path, still read as the personal layer until it moves; /ai-slop:setup apply moves it to $DUALLOCAL and deletes it"
err="$(HOME="$DUALHOME" CLAUDE_PROJECT_DIR="$DUALREPO" bash "$DETECT" "$CLEAN" 2>&1 >/dev/null)"
assert_eq "old file only: a scan prints the warning once, on stderr" "$(printf '%s\n' "$err" | grep -c "is an old path")" "1"

printf '%s\n' 'thresholds:' '  ai_vocabulary: 11' >"$DUALLOCAL"
out="$(HOME="$DUALHOME" CLAUDE_PROJECT_DIR="$DUALREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "both present: the personal override wins" "$out" "threshold_ai_vocabulary=11 (rule rule-ai-vocabulary) [layer: $DUALLOCAL]"
assert_eq "both present: the old file is not a listed layer" "$(printf '%s\n' "$out" | grep -cxF "  $DUALOLD")" "0"
assert_contains "both present: the warning names both files and setup" "$out" "Warning: $DUALOLD is an old path and not read, since $DUALLOCAL supplies the personal layer; /ai-slop:setup apply moves its settings into $DUALLOCAL and deletes it"

INJREPO="$TEST_TMPDIR/threshold-inject"
INJHOME="$TEST_TMPDIR/threshold-inject-home"
mkdir -p "$INJREPO" "$INJHOME/.claude"
make_repo "$INJREPO"
cp "$SLOP" "$INJREPO/doc.md"
cat >"$INJHOME/.claude/ai-slop.json" <<EOF
{ "thresholds": { "ai_vocabulary": "99\\nSCANNED[\$(touch $INJREPO/PWNED)0]\\t5\\t5\\t0" } }
EOF
out="$(HOME="$INJHOME" CLAUDE_PROJECT_DIR="$INJREPO" bash "$DETECT" "$INJREPO/doc.md" 2>&1)"
assert_eq "threshold injection: a forged density row runs no command" "$([[ -e "$INJREPO/PWNED" ]] && echo ran || echo none)" "none"
assert_not_contains "threshold injection: a forged row reaches no path" "$out" "SCANNED["

# --- Config parsing against a CRLF-emitting jq (#3343) ---------------------------
make_crlf_jq() {
  mkdir -p "$1"
  cat >"$1/jq" <<EOF
#!/usr/bin/env bash
# pipefail so a jq failure stays a failure: awk's exit status would otherwise
# mask it, and the readers skip a refused layer only on jq's nonzero status.
set -o pipefail
# A wrapper jq, such as a mise shim that cannot run its own jq, falls back to the
# next jq on PATH, which is this shim: each level would start a bash and an awk
# without end. Refuse the second entry instead.
[[ -z "\${CRLF_JQ_SHIM:-}" ]] || { echo "crlf jq shim: re-entered through $2" >&2; exit 97; }
export CRLF_JQ_SHIM=1
"$2" "\$@" | awk '{ printf "%s\r\n", \$0 }'
EOF
  chmod +x "$1/jq"
}
CRLF_BIN="$TEST_TMPDIR/bin-crlf-jq"
make_crlf_jq "$CRLF_BIN" "$(command -v jq)"

LOOP_BIN="$TEST_TMPDIR/bin-loop-jq"
mkdir -p "$LOOP_BIN"
cat >"$LOOP_BIN/fallback-jq" <<'EOF'
#!/usr/bin/env bash
d=$((${FALLBACK_DEPTH:-0} + 1))
[[ "$d" -lt 4 ]] || exit 99
FALLBACK_DEPTH="$d" exec jq "$@"
EOF
chmod +x "$LOOP_BIN/fallback-jq"
make_crlf_jq "$LOOP_BIN" "$LOOP_BIN/fallback-jq"
PATH="$LOOP_BIN:$PATH" jq -n 1 >/dev/null 2>&1
rc=$?
assert_exit "crlf jq: a jq that resolves back to the shim is refused, not recursed into" 97 "$rc"

shim_out="$(PATH="$CRLF_BIN:$PATH" jq -rn '"x"' | od -c)"
assert_contains "crlf jq: the shim is on PATH and emits a carriage return" "$shim_out" '\r'

CRLFREPO="$TEST_TMPDIR/crlf-repo"
crlfdir="$TEST_TMPDIR/crlf-home/.claude"
mkdir -p "$crlfdir" "$CRLFREPO/quirks"
make_repo "$CRLFREPO"
cp "$SLOP" "$CRLFREPO/allowed.md"
cp "$SLOP" "$CRLFREPO/vendored.md"
cp "$RAP/quirks/doc.md" "$CRLFREPO/quirks/doc.md"
cp "$RAP/plain.md" "$CRLFREPO/plain.md"
cp "$PREPO/doc.md" "$CRLFREPO/phrases.md"
cat >"$crlfdir/ai-slop.json" <<'EOF'
{
  "excluded_paths": ["vendored.md"],
  "em_dash_allowed_paths": ["allowed.md"],
  "rule_allowed_paths": { "rule-filler-phrases": ["quirks/**"] },
  "phrase_add": ["chef.s kiss architecture"],
  "phrase_remove": ["(the|my) honest take"],
  "thresholds": { "ai_vocabulary": 999, "copulative_avoidance": 999 },
  "disabled_rules": ["rule-significance-inflation"]
}
EOF
crlf_detect() {
  (cd "$CRLFREPO" && HOME="$TEST_TMPDIR/crlf-home" PATH="$CRLF_BIN:$PATH" CLAUDE_PROJECT_DIR="$CRLFREPO" \
    bash "$DETECT" "$@" 2>&1)
}

out="$(crlf_detect "$CRLFREPO/vendored.md")"
assert_contains "crlf jq: excluded_paths still declines the file" "$out" "Declined: file=vendored.md cause=excluded-glob"

out="$(crlf_detect "$CRLFREPO/allowed.md")"
assert_not_contains "crlf jq: em_dash_allowed_paths still exempts the document" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"
assert_contains "crlf jq: the em-dash exemption is a decline, not a dropped file" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=0 declined_quote=0 declined_config=1 disabled=0"
assert_contains "crlf jq: disabled_rules still applies" "$out" "rule=ai-slop/audit/rule-significance-inflation findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=1"

out="$(crlf_detect "$CRLFREPO/quirks/doc.md" "$CRLFREPO/plain.md")"
assert_not_contains "crlf jq: rule_allowed_paths still declines the listed path" "$out" "file=quirks/doc.md"
assert_contains "crlf jq: rule_allowed_paths decline still counted" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1 declined=1"

out="$(crlf_detect "$CRLFREPO/phrases.md")"
assert_contains "crlf jq: phrase_add and phrase_remove still apply" "$out" "rule=ai-slop/audit/rule-model-era-phrases findings=2 declined=0"

out="$(crlf_detect --show-config)"
assert_contains "crlf jq: scalar threshold parses without the carriage return" "$out" "threshold_ai_vocabulary=999 (rule"

truncdir="$TEST_TMPDIR/trunc-home/.claude"
mkdir -p "$truncdir"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 999 } }' '{bad' >"$truncdir/ai-slop.json"

out="$(HOME="$TEST_TMPDIR/trunc-home" bash "$DETECT" --show-config 2>&1)"
assert_contains "malformed layer: the partially parsed threshold is refused" "$out" "threshold_ai_vocabulary=3.0 (rule"

out="$(HOME="$TEST_TMPDIR/trunc-home" PATH="$CRLF_BIN:$PATH" bash "$DETECT" --show-config 2>&1)"
assert_contains "malformed layer: refused under a CRLF-emitting jq too" "$out" "threshold_ai_vocabulary=3.0 (rule"

okdir="$TEST_TMPDIR/trunc-ok-home/.claude"
mkdir -p "$okdir"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 999 } }' >"$okdir/ai-slop.json"
out="$(HOME="$TEST_TMPDIR/trunc-ok-home" bash "$DETECT" --show-config 2>&1)"
assert_contains "malformed layer: the same value from a well-formed layer still applies" "$out" "threshold_ai_vocabulary=999 (rule"

OLDREPO="$TEST_TMPDIR/old-json-repo"
mkdir -p "$OLDREPO/.claude"
make_repo "$OLDREPO"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 999 } }' >"$OLDREPO/.claude/ai-slop.json"
printf '%s\n' '{ "thresholds": { "copulative_avoidance": 999 } }' >"$OLDREPO/.claude/ai-slop.local.json"
out="$(CLAUDE_PROJECT_DIR="$OLDREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "yaml: the old team file is not read when the YAML is absent" "$out" "threshold_ai_vocabulary=3.0 (rule rule-ai-vocabulary) [layer: default]"
assert_contains "yaml: a value no layer supplied reports the default layer" "$out" "threshold_copulative_avoidance=4.0 (rule rule-copulative-avoidance) [layer: default]"
assert_not_contains "yaml: neither old file is a listed layer" "$out" "$OLDREPO/.claude/"

YREPO="$TEST_TMPDIR/yaml-repo"
mkdir -p "$YREPO/.claude" "$YREPO/docs/conventions"
make_repo "$YREPO"
printf '%s\n' '{ "thresholds": { "ai_vocabulary": 999 }, "disabled_rules": ["rule-em-dash"], "excluded_paths": ["old/**"] }' >"$YREPO/.claude/ai-slop.json"
cat >"$YREPO/docs/conventions/ai-slop.yaml" <<'EOF'
# a comment with a "quote" and a # hash
thresholds:
  ai_vocabulary: 2.5   # trailing comment
disabled_rules:
  - "rule-emoji-formatting"
excluded_paths: ["vendor/**", "gen/*.md"]
em_dash_allowed_paths: []
rule_allowed_paths:
  rule-ai-vocabulary:
    - "docs/marketing/**"
  rule-em-dash: []
EOF
out="$(CLAUDE_PROJECT_DIR="$YREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "yaml: the YAML is a listed layer" "$out" "$YREPO/docs/conventions/ai-slop.yaml"
assert_not_contains "yaml: the old file is not read beside it" "$out" "$YREPO/.claude/ai-slop.json"
assert_contains "yaml: a scalar comes from the YAML" "$out" "threshold_ai_vocabulary=2.5 (rule rule-ai-vocabulary) [layer: $YREPO/docs/conventions/ai-slop.yaml]"
assert_contains "yaml: a list comes from the YAML and names its layer" "$out" "disabled_rules=rule-emoji-formatting [layer: $YREPO/docs/conventions/ai-slop.yaml]"
assert_contains "yaml: a flow-sequence list is read" "$out" "excluded_paths=vendor/** gen/*.md [layer: $YREPO/docs/conventions/ai-slop.yaml]"
assert_contains "yaml: a per-rule glob list names its layer" "$out" "rule_allowed_paths[rule-ai-vocabulary]=docs/marketing/** [layer: $YREPO/docs/conventions/ai-slop.yaml]"
assert_not_contains "yaml: an empty per-rule list leaves the rule unexempted" "$out" "rule_allowed_paths[rule-em-dash]"

printf '%s\n' 'thresholds:' '  copulative_avoidance: 7' 'disabled_rules: []' >"$YREPO/docs/conventions/ai-slop.local.yaml"
out="$(CLAUDE_PROJECT_DIR="$YREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "yaml: the personal override supplies its own scalar" "$out" "threshold_copulative_avoidance=7 (rule rule-copulative-avoidance) [layer: $YREPO/docs/conventions/ai-slop.local.yaml]"
assert_contains "yaml: the team YAML still supplies the key the personal override left" "$out" "threshold_ai_vocabulary=2.5 (rule rule-ai-vocabulary) [layer: $YREPO/docs/conventions/ai-slop.yaml]"
assert_contains "yaml: an explicit empty list in the personal override clears the team list" "$out" "disabled_rules= [layer: $YREPO/docs/conventions/ai-slop.local.yaml]"

printf '%s\n' 'phrase_remove:' '  - "(the|my) honest take"' >"$YREPO/docs/conventions/ai-slop.local.yaml"
out="$(CLAUDE_PROJECT_DIR="$YREPO" bash "$DETECT" --show-config 2>&1)"
assert_contains "yaml: phrase_remove alone names its layer" "$out" "model_phrases=(the part most people skip|that.s the unlock) [layer: add default, remove $YREPO/docs/conventions/ai-slop.local.yaml]"

BADY="$TEST_TMPDIR/yaml-bad-repo"
mkdir -p "$BADY/docs/conventions"
make_repo "$BADY"
printf '%s\n' 'thresholds: {ai_vocabulary: 999}' >"$BADY/docs/conventions/ai-slop.yaml"
out="$(CLAUDE_PROJECT_DIR="$BADY" bash "$DETECT" --show-config 2>&1)"
assert_contains "yaml: a layer outside the subset is refused" "$out" "threshold_ai_vocabulary=3.0 (rule rule-ai-vocabulary) [layer: default]"

cp "$SLOP" "$YREPO/doc.md"
printf '%s\n' 'excluded_paths:' '  - "doc.md"' >"$YREPO/docs/conventions/ai-slop.yaml"
rm -f "$YREPO/docs/conventions/ai-slop.local.yaml"
out="$(cd "$YREPO" && CLAUDE_PROJECT_DIR="$YREPO" bash "$DETECT" --list-targets "$YREPO/doc.md" 2>&1)"
assert_not_contains "yaml: excluded_paths from the YAML drops the target" "$out" "doc.md"

a="$(bash "$DETECT" "$ALLRULES" 2>&1)"
b="$(LC_ALL=C bash "$DETECT" "$ALLRULES" 2>&1)"
if [[ "$a" == "$b" ]]; then
  pass "portability: output identical under LC_ALL=C"
else
  fail "portability: output identical under LC_ALL=C" "identical" "differs"
fi

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

LISTFENCE="$TEST_TMPDIR/listfence.md"
cat >"$LISTFENCE" <<EOF
# Ordered list fence

1. \`\`\`text
   Inside a fence ${EM} cromulentia stays exempt.
   \`\`\`

An em dash ${EM} after the closer must flag.
EOF
out="$(bash "$DETECT" "$LISTFENCE" 2>&1)"
assert_contains "ordered-marker fence: prose after the closer still flags" "$out" "line=7"
assert_not_contains "ordered-marker fence: fenced content stays exempt" "$out" "cromulentia"

BULLETFENCE="$TEST_TMPDIR/bulletfence.md"
cat >"$BULLETFENCE" <<EOF
# Bullet list fence

- \`\`\`text
  Inside a bullet fence ${EM} zephyrantic stays exempt.
  \`\`\`

An em dash ${EM} after the bullet closer must flag.
EOF
out="$(bash "$DETECT" "$BULLETFENCE" 2>&1)"
assert_contains "bullet-marker fence: prose after the closer still flags" "$out" "line=7"
assert_not_contains "bullet-marker fence: fenced content stays exempt" "$out" "zephyrantic"

UNCLOSED="$TEST_TMPDIR/unclosed.md"
cat >"$UNCLOSED" <<EOF
# Unclosed fence

\`\`\`text
An em dash ${EM} inside a fence that never closes.
EOF
out="$(bash "$DETECT" "$UNCLOSED" 2>&1)"
rc=$?
assert_exit "unclosed fence: the run still exits 0" 0 "$rc"
assert_contains "unclosed fence: the warning names the opening line" "$out" "code fence opened at line 3"
assert_contains "unclosed fence: the warning names the file" "$out" "unclosed.md"

LONGNUM="$TEST_TMPDIR/longnum.md"
cat >"$LONGNUM" <<EOF
# Long number

1234567890. \`\`\`text

An em dash ${EM} after it must still flag.
EOF
out="$(bash "$DETECT" "$LONGNUM" 2>&1)"
assert_contains "ordered marker: a ten-digit number does not open a fence" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 "

DEDENT="$TEST_TMPDIR/dedent.md"
cat >"$DEDENT" <<EOF
- \`\`\`text
  inside the item ${EM} stays exempt
after the item ${EM} must flag
EOF
out="$(bash "$DETECT" "$DEDENT" 2>&1)"
assert_contains "list fence dedent: the dedented line is scanned" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 "
assert_contains "list fence dedent: it is the line below the item" "$out" "line=3"
assert_not_contains "list fence dedent: the item's own fenced content stays exempt" "$out" "inside the item"
assert_not_contains "list fence dedent: a container-ended fence is not reported unclosed" "$out" "is never closed"

DEDENTBLANK="$TEST_TMPDIR/dedentblank.md"
cat >"$DEDENTBLANK" <<EOF
1. \`\`\`text
   inside the item ${EM} stays exempt

after the blank line ${EM} must flag
EOF
out="$(bash "$DETECT" "$DEDENTBLANK" 2>&1)"
assert_contains "list fence dedent: a blank line keeps the fence open" "$out" "rule=ai-slop/audit/rule-em-dash findings=1 "
assert_contains "list fence dedent: the paragraph below the blank line is scanned" "$out" "line=4"
assert_not_contains "list fence dedent: content before the blank line stays exempt" "$out" "inside the item"

DEDENTFENCE="$TEST_TMPDIR/dedentfence.md"
cat >"$DEDENTFENCE" <<EOF
- \`\`\`text
  inside the item
\`\`\`
after the new opener ${EM} is code
EOF
out="$(bash "$DETECT" "$DEDENTFENCE" 2>&1)"
assert_contains "list fence dedent: a column-zero fence below the item opens a new block" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 "
assert_not_contains "list fence dedent: the line inside that new block stays exempt" "$out" "after the new opener"
assert_contains "list fence dedent: the new block running to EOF is reported unclosed" "$out" "code fence opened at line 3 is never closed"

GENERATED="$TEST_TMPDIR/generated.md"
cat >"$GENERATED" <<EOF
# Generated region

Mentioning \`<!-- BEGIN GENERATED: x -->\` in prose opens nothing ${EM} must flag.

<!-- BEGIN GENERATED: plugin options. Edit plugin.json, then run scripts/sync-plugin-options-docs.py -->
Inside the region ${EM} zephyrantic stays exempt.
<!-- END GENERATED: plugin options -->

After the region ${EM} must flag.
EOF
out="$(bash "$DETECT" "$GENERATED" 2>&1)"
assert_contains "generated region: prose outside it flags" "$out" "rule=ai-slop/audit/rule-em-dash findings=2 "
assert_contains "generated region: the line after END is scanned" "$out" "line=9"
assert_not_contains "generated region: its content stays exempt" "$out" "zephyrantic"

GENUNCLOSED="$TEST_TMPDIR/genunclosed.md"
cat >"$GENUNCLOSED" <<EOF
# Unclosed region

<!-- BEGIN GENERATED: x -->
An em dash ${EM} in a region that never closes.
EOF
out="$(bash "$DETECT" "$GENUNCLOSED" 2>&1)"
assert_contains "generated region: an unclosed one is reported" "$out" "generated region opened at line 3 is never closed"

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
cat >"$GITDIR/sibling.md" <<EOF
A sibling em dash ${EM} here.
EOF
git -C "$GITDIR" add sibling.md
out="$(bash "$DETECT" "$GITDIR/docs" 2>&1)"
assert_contains "dir target in git repo: tracked file scanned via ls-files" "$out" "file=$GITDIR/docs/tracked.md"
assert_contains "dir target in git repo: only the tracked file counts" "$out" "1 files scanned"
assert_not_contains "dir target in git repo: sibling outside the subtree is not scanned" "$out" "sibling.md"

GITSPELL="$(git -C "$GITDIR/docs" rev-parse --show-toplevel)/docs"
PWDSPELL="$(cd "$GITDIR/docs" && pwd)"

out="$(bash "$DETECT" "$GITSPELL" 2>&1)"
assert_contains "dir target, git spelling: the emitted path keeps that spelling" "$out" "file=$GITSPELL/tracked.md"
assert_contains "dir target, git spelling: only the tracked file counts" "$out" "1 files scanned"

out="$(bash "$DETECT" "$PWDSPELL" 2>&1)"
assert_contains "dir target, shell spelling: the emitted path keeps that spelling" "$out" "file=$PWDSPELL/tracked.md"
assert_contains "dir target, shell spelling: only the tracked file counts" "$out" "1 files scanned"

out="$(bash "$DETECT" "$GITDIR/docs/" 2>&1)"
assert_contains "dir target with a trailing slash: the emitted path is not doubled" "$out" "file=$GITDIR/docs/tracked.md"
assert_not_contains "dir target with a trailing slash: no doubled separator" "$out" "file=$GITDIR/docs//tracked.md"
assert_contains "dir target with a trailing slash: only the tracked file counts" "$out" "1 files scanned"

BAREREPO="$TEST_TMPDIR/barerepo"
mkdir -p "$BAREREPO/unicode"
git -C "$BAREREPO" init -q
printf 'A tracked em dash %s here.\n' "$EM" >"$BAREREPO/unicode/notes${EM}name.md"
printf 'A tracked em dash %s here too.\n' "$EM" >"$BAREREPO/ascii.md"
git -C "$BAREREPO" add "unicode/notes${EM}name.md" ascii.md

out="$(cd "$BAREREPO" && CLAUDE_PROJECT_DIR="$BAREREPO" bash "$DETECT" 2>&1)"
assert_contains "bare invocation: the non-ASCII tracked file is in the report" "$out" "file=unicode/notes${EM}name.md"
assert_contains "bare invocation: both tracked files count" "$out" "2 files scanned"

BADLS_BIN="$TEST_TMPDIR/bin-badls"
mkdir -p "$BADLS_BIN"
REAL_GIT="$(command -v git)"
cat >"$BADLS_BIN/git" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == "ls-files" ]]; then
    echo "fatal: stubbed ls-files failure" >&2
    exit 128
  fi
done
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$BADLS_BIN/git"
out="$(cd "$BAREREPO" && PATH="$BADLS_BIN:$PATH" CLAUDE_PROJECT_DIR="$BAREREPO" bash "$DETECT" 2>&1)"
assert_contains "bare invocation, listing fails: the summary reports 0 files scanned" "$out" "0 files scanned"

REAL_AWK="$(command -v awk)"
make_failing_awk() {
  mkdir -p "$1"
  cat >"$1/awk" <<EOF
#!/usr/bin/env bash
for a in "\$@"; do
  if [[ "\$a" == dir=* ]]; then
    n=\$(( \$(cat "$1/calls" 2>/dev/null || echo 0) + 1 ))
    echo "\$n" >"$1/calls"
    if [[ "\$n" -le $2 ]]; then
      echo "awk: fatal error: internal error" >&2
      exit $3
    fi
  fi
done
exec "$REAL_AWK" "\$@"
EOF
  chmod +x "$1/awk"
}
RETRY_DOC="$TEST_TMPDIR/retry.md"
printf 'One em dash %s in prose.\n' "$EM" >"$RETRY_DOC"

make_failing_awk "$TEST_TMPDIR/bin-awk-abort-once" 1 134
out="$(PATH="$TEST_TMPDIR/bin-awk-abort-once:$PATH" bash "$DETECT" "$RETRY_DOC" 2>&1)"
rc=$?
assert_exit "extraction aborts once: the retry completes the scan" 0 "$rc"
assert_contains "extraction aborts once: a retry notice reaches stderr" "$out" "prose extraction aborted (awk exit 134); retrying once"
assert_contains "extraction aborts once: the retried scan still reports the finding" "$out" "Finding: rule=ai-slop/audit/rule-em-dash"

make_failing_awk "$TEST_TMPDIR/bin-awk-abort-always" 99 134
out="$(PATH="$TEST_TMPDIR/bin-awk-abort-always:$PATH" bash "$DETECT" "$RETRY_DOC" 2>&1)"
rc=$?
assert_exit "extraction always aborts: the scan exits 2" 2 "$rc"
assert_contains "extraction always aborts: the failure message stands" "$out" "prose extraction failed; nothing was scanned"
assert_eq "extraction always aborts: it is retried once, not more" "$(cat "$TEST_TMPDIR/bin-awk-abort-always/calls")" "2"

make_failing_awk "$TEST_TMPDIR/bin-awk-error" 99 2
out="$(PATH="$TEST_TMPDIR/bin-awk-error:$PATH" bash "$DETECT" "$RETRY_DOC" 2>&1)"
rc=$?
assert_exit "extraction fails without an abort: the scan exits 2" 2 "$rc"
assert_eq "extraction fails without an abort: no retry runs" "$(cat "$TEST_TMPDIR/bin-awk-error/calls")" "1"

# --- Excerpt truncation at the byte boundary --------------------------------------
LONGLINE="$(printf 'x%.0s' $(seq 1 75)) em${EM}dash tail"
BOUNDARY="$TEST_TMPDIR/boundary.md"
printf '%s\n' "$LONGLINE" >"$BOUNDARY"
out="$(bash "$DETECT" "$BOUNDARY" 2>&1)"
if LC_ALL=C grep -q $'\xe2\x80\x94' <<<"$out"; then
  pass "excerpt truncation: em dash at boundary survives whole"
elif LC_ALL=C grep -q $'\xe2' <<<"$out"; then
  fail "excerpt truncation: no partial multi-byte sequence" "whole em dash or none" "lone lead byte present"
else
  pass "excerpt truncation: partial sequence dropped cleanly"
fi

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
if LC_ALL=C grep -qE '^date: [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' "$FOUT"; then
  pass "emit: ISO-8601 extended UTC date"
else
  fail "emit: ISO-8601 extended UTC date" "YYYY-MM-DDThh:mm:ssZ" "$(grep '^date:' "$FOUT")"
fi
assert_contains "emit: finding cell leads with qualified rule id" "$fcontent" "ai-slop/audit/rule-em-dash"
assert_contains "emit: prose pipe arrives sanitized" "$fcontent" "pipe / and"

SYNTH="$TEST_TMPDIR/synth-out.txt"
cat >"$SYNTH" <<'EOF'
Finding: rule=ai-slop/audit/rule-em-dash file=doc.md line=1 fired=zero|tolerance excerpt=text
Summary rule=ai-slop/audit/rule-em-dash findings=1 declined=0 disabled=0
EOF
bash "$EMIT" --from "$SYNTH" --out "$TEST_TMPDIR/findings/synth.md" --branch test-branch >/dev/null 2>&1
assert_contains "emit: pipe escaped in cell" "$(cat "$TEST_TMPDIR/findings/synth.md")" 'zero\|tolerance'

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

emit_branch_line() {
  local b="$1" out="$TEST_TMPDIR/findings/ybranch.md"
  rm -f "$TEST_TMPDIR/findings/ybranch"*.md
  bash "$EMIT" --from "$DETOUT" --out "$out" --branch "$b" </dev/null >/dev/null 2>&1 || true
  [[ -f "$out" ]] || {
    printf 'MISSING\n'
    return 0
  }
  LC_ALL=C grep -m1 '^branch:' "$out" </dev/null || true
}
assert_branch_line() {
  local got
  got="$(emit_branch_line "$1")"
  if [[ "$got" == "$2" ]]; then pass "$3"; else fail "$3" "$2" "$got"; fi
}

for b in '?foo' ':foo' ',foo' '[foo' ']foo' '{foo' '}foo' '#foo' \
  '&foo' '*foo' '!foo' '|foo' '>foo' '%foo' '@foo' '`foo' "'foo"; do
  assert_branch_line "$b" "branch: \"$b\"" \
    "emit: indicator branch '$b' is emitted as a quoted scalar"
done

assert_branch_line '"foo' 'branch: "\"foo"' \
  'emit: indicator branch (leading double quote) is quoted and escaped'

for b in 'has: colon' 'has #hash'; do
  assert_branch_line "$b" "branch: \"$b\"" \
    "emit: branch '$b' is quoted (plain scalar would end early)"
done

for b in 'main' 'feat/3179-slug' 'release-1.2_x'; do
  assert_branch_line "$b" "branch: $b" \
    "emit: ordinary branch '$b' stays an unquoted plain scalar"
done

for b in true null 123 yes FALSE '~'; do
  assert_branch_line "$b" "branch: \"$b\"" "emit: implicit-type branch '$b' is quoted"
done

assert_branch_line '@with"quote' 'branch: "@with\"quote"' \
  "emit: a quote character inside an indicator branch is escaped"

EXPECTED_IMPORTANT="rule-knowledge-cutoff-disclaimer rule-llm-citation-artifacts rule-chatbot-artifacts"
EXPECTED_SUGGESTION="rule-em-dash rule-emoji-formatting rule-curly-artifacts rule-significance-inflation rule-negative-parallelism rule-challenges-conclusion rule-utm-params rule-filler-phrases rule-stacked-hedging rule-model-era-phrases rule-ai-vocabulary rule-copulative-avoidance"

ROSTER="$(bash "$DETECT" "$CLEAN" 2>&1 | LC_ALL=C sed -n 's|^Summary rule=ai-slop/audit/\([a-z-]*\) .*|\1|p' | sort)"
EXPECTED_ROSTER="$(printf '%s %s' "$EXPECTED_IMPORTANT" "$EXPECTED_SUGGESTION" | tr ' ' '\n' | sort)"
if [[ "$ROSTER" == "$EXPECTED_ROSTER" ]]; then
  pass "roster agreement: detect.sh ships exactly the 15 tabled rules"
else
  fail "roster agreement: detect.sh ships exactly the 15 tabled rules" \
    "the tabled set" "$(diff <(echo "$EXPECTED_ROSTER") <(echo "$ROSTER") | tr '\n' ' ')"
fi

TIERSRC="$TEST_TMPDIR/tier-src.txt"
: >"$TIERSRC"
for slug in $EXPECTED_IMPORTANT $EXPECTED_SUGGESTION; do
  printf 'Finding: rule=ai-slop/audit/%s file=doc.md line=1 fired=synthetic excerpt=sample\n' "$slug" >>"$TIERSRC"
  printf 'Summary rule=ai-slop/audit/%s findings=1 declined=0 disabled=0\n' "$slug" >>"$TIERSRC"
done

TIEROUT="$TEST_TMPDIR/findings/tiers.md"
bash "$EMIT" --from "$TIERSRC" --out "$TIEROUT" --branch test-branch >/dev/null 2>&1
tier_content="$(cat "$TIEROUT")"

assert_tier() {
  local row
  row="$(LC_ALL=C grep -m1 "ai-slop/audit/$1 " "$TIEROUT")"
  case "$row" in
    *"| $2 |"*) pass "tier mirror: $1 is $2" ;;
    *) fail "tier mirror: $1 is $2" "$2" "$row" ;;
  esac
}
for slug in $EXPECTED_IMPORTANT; do assert_tier "$slug" IMPORTANT; done
for slug in $EXPECTED_SUGGESTION; do assert_tier "$slug" SUGGESTION; done

assert_not_contains "frontmatter: no uncomputed tier: field" "$tier_content" "tier:"
assert_contains "action: filler-phrases carries its substitution, not the generic judgment string" \
  "$(LC_ALL=C grep -m1 'rule-filler-phrases' "$TIEROUT")" 'in order to'
assert_contains "action: stacked-hedging names the one-hedge repair" \
  "$(LC_ALL=C grep -m1 'rule-stacked-hedging' "$TIEROUT")" "states the real uncertainty"

WRAPQ="$TEST_TMPDIR/wrapq.md"
cat >"$WRAPQ" <<'EOF'
# Wrapped quotes

The pattern fires on "challenges remained", "challenges
remainder", "challenges remaining", "challenges persisted"; it does not
fire on "challenges-adjacent".

Plain prose written in order to trip the wording rule.

- A bullet with an unmatched quote "here
- The next bullet is written in order to stay scanned

A 6" bolt is written in order to stay scanned, and so is
the line after the inch mark, written in order to stay scanned.
EOF
out="$(bash "$DETECT" "$WRAPQ" 2>&1)"
assert_contains "wrapped quote: documented phrases across a line break stay exempt" "$out" "rule=ai-slop/audit/rule-challenges-conclusion findings=0"
assert_contains "wrapped quote: exempt candidates counted under the quote cause" "$out" "rule=ai-slop/audit/rule-challenges-conclusion findings=0 declined=2 declined_marker=0 declined_quote=2 declined_config=0"
assert_contains "wrapped quote: an unmatched quote resets at the next list item; an inch mark opens nothing" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=4"

UNDERSCORE="$TEST_TMPDIR/underscore.md"
cat >"$UNDERSCORE" <<'EOF'
# Naming

Private fields take a leading underscore. The underscore is the convention;
one underscore per field, never two. A field with no underscore fails review,
and a field whose underscore is trailing fails too. Count the underscore once.
EOF
out="$(bash "$DETECT" "$UNDERSCORE" 2>&1)"
assert_contains "vocab: the noun underscore does not fire the density rule" "$out" "rule=ai-slop/audit/rule-ai-vocabulary findings=0"

SPLITMARK="$TEST_TMPDIR/splitmark.md"
cat >"$SPLITMARK" <<EOF
# Split

An em dash ${EM} with a marker. <!-- ai-slop-ignore: quoted example -->
EOF
out="$(bash "$DETECT" "$SPLITMARK" 2>&1)"
assert_contains "split declined: a line marker counts under marker" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=1 declined_quote=0 declined_config=0"
out="$(bash "$DETECT" "$QUOTED" 2>&1)"
assert_contains "split declined: quote-exempt hits count under quote" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=1 declined=2 declined_marker=0 declined_quote=2 declined_config=0"
out="$(CLAUDE_PROJECT_DIR="$RAP" bash "$DETECT" "$RAP/quirks/doc.md" 2>&1)"
assert_contains "split declined: a rule_allowed_paths exemption counts under config" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=0 declined=1 declined_marker=0 declined_quote=0 declined_config=1"

ATTRIB="$TEST_TMPDIR/attrib.md"
cat >"$ATTRIB" <<EOF
# Marker attribution

An em dash ${EM} on a marked line. <!-- ai-slop-ignore: attribution case -->
EOF
out="$(bash "$DETECT" "$ATTRIB" 2>&1)"
assert_contains "per-rule marker: the rule the exempted line matches is charged" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=1 declined_quote=0 declined_config=0"
assert_contains "per-rule marker: a rule the exempted line cannot match is charged nothing" "$out" "rule=ai-slop/audit/rule-utm-params findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0"

QUOTEDMARK="$TEST_TMPDIR/quotedmark.md"
cat >"$QUOTEDMARK" <<EOF
# Quoted marker

> A quote written in order to ship ${EM} here. <!-- ai-slop-ignore: quoted -->
EOF
out="$(bash "$DETECT" "$QUOTEDMARK" 2>&1)"
assert_contains "per-rule marker: a typography rule is charged the exempted blockquote line" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=1 declined_quote=0 declined_config=0"
assert_contains "per-rule marker: a wording rule is not charged quoted exempted material" "$out" "rule=ai-slop/audit/rule-filler-phrases findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0"

MARKREASON="$TEST_TMPDIR/markreason.md"
cat >"$MARKREASON" <<'EOF'
# Marker reason

Plain prose with no candidate in it. <!-- ai-slop-ignore: delve tapestry pivotal -->
EOF
out="$(bash "$DETECT" "$MARKREASON" 2>&1)"
assert_contains "per-rule marker: words inside the marker reason are not counted" "$out" "rule=ai-slop/audit/rule-ai-vocabulary findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0"

ALLBLOCK="$TEST_TMPDIR/allblock.md"
cat >"$ALLBLOCK" <<'EOF'
<!-- ai-slop-ignore-start: vocabulary sample -->
Delve tapestry pivotal crucial meticulous vibrant.
Intricate renowned enduring interplay groundbreaking.
<!-- ai-slop-ignore-end: end of sample -->
EOF
out="$(bash "$DETECT" "$ALLBLOCK" 2>&1)"
assert_contains "per-rule marker: a density rule counts exempted occurrences with no scannable words left" "$out" "rule=ai-slop/audit/rule-ai-vocabulary findings=0 declined=11 declined_marker=11 declined_quote=0 declined_config=0"
assert_contains "per-rule marker: a pattern rule the block cannot match stays at zero" "$out" "rule=ai-slop/audit/rule-utm-params findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0"

out="$(bash "$DETECT" "$FILEMARK" 2>&1)"
assert_contains "whole-file marker: a rule the prose matches is charged one file decline" "$out" "rule=ai-slop/audit/rule-em-dash findings=0 declined=1 declined_marker=1 declined_quote=0 declined_config=0"
assert_contains "whole-file marker: a rule the prose does not match is charged one file decline too" "$out" "rule=ai-slop/audit/rule-utm-params findings=0 declined=1 declined_marker=1 declined_quote=0 declined_config=0"

CHUNK_A="$TEST_TMPDIR/chunk-a.txt"
CHUNK_B="$TEST_TMPDIR/chunk-b.txt"
cat >"$CHUNK_A" <<'EOF'
Finding: rule=ai-slop/audit/rule-em-dash file=a.md line=3 fired=zero-tolerance excerpt=one
Summary rule=ai-slop/audit/rule-em-dash findings=1 declined=1 declined_marker=1 declined_quote=0 declined_config=0 disabled=0
Summary rule=ai-slop/audit/rule-filler-phrases findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=1
Summary rule=ai-slop/audit/rule-utm-params findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=0
Summary total: 1 findings across 3 files scanned (0 files declined)
EOF
cat >"$CHUNK_B" <<'EOF'
Declined: file=vendor/x.md cause=excluded-glob
Summary rule=ai-slop/audit/rule-em-dash findings=0 declined=2 declined_marker=0 declined_quote=2 declined_config=0 disabled=0
Summary rule=ai-slop/audit/rule-filler-phrases findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=1
Summary rule=ai-slop/audit/rule-utm-params findings=0 declined=0 declined_marker=0 declined_quote=0 declined_config=0 disabled=0
Summary total: 0 findings across 2 files scanned (1 files declined)
EOF
CHUNKOUT="$TEST_TMPDIR/findings/chunked.md"
bash "$EMIT" --from "$CHUNK_A" --from "$CHUNK_B" --out "$CHUNKOUT" --branch test-branch >/dev/null 2>&1
ccontent="$(cat "$CHUNKOUT")"
assert_contains "emit chunked: files scanned and chunk count are summed" "$ccontent" "Scanned: 5 files in 2 chunk(s); 1 whole file(s) declined."
assert_contains "emit chunked: declined counts sum across chunks with their split" "$ccontent" "Declined candidates: ai-slop/audit/rule-em-dash count=3 (marker=1, quote=2, config=0)"
assert_contains "emit chunked: a config-disabled rule is named" "$ccontent" "Disabled by config: [ai-slop/audit/rule-filler-phrases]"
assert_contains "emit chunked: a rule with zero findings in every chunk returns no result" "$ccontent" "Returned no result: [ai-slop/audit/rule-utm-params]"
assert_not_contains "emit chunked: a rule that fired in one chunk is not called no-result" "$ccontent" "Returned no result: [ai-slop/audit/rule-em-dash"
assert_contains "emit chunked: the declined-file row survives" "$ccontent" "Declined: file=vendor/x.md cause=excluded-glob"
assert_contains "emit chunked: the finding row from the first chunk is present" "$ccontent" "a.md:3"

echo
TOTAL=$((CASE_NUM + SKIPPED))
RC=0
if [[ "$TOTAL" -ne "$EXPECTED_CASES" ]]; then
  RC=1
  printf 'CASE COUNT MISMATCH: ran %d cases (%d pass/fail + %d host skip), expected %d.\n' \
    "$TOTAL" "$CASE_NUM" "$SKIPPED" "$EXPECTED_CASES" >&2
  printf 'Either a case did not run, so this tally cannot be trusted, or a case was added or removed and EXPECTED_CASES needs updating.\n' >&2
fi
if [[ "$FAILED" -ne 0 ]]; then
  RC=1
  echo "$FAILED of $CASE_NUM cases FAILED, $SKIPPED host skip(s)"
elif [[ "$RC" -eq 0 ]]; then
  echo "All $CASE_NUM cases passed, $SKIPPED host skip(s)"
fi
exit "$RC"

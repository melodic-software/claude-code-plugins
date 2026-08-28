#!/usr/bin/env bash
# PostToolUse hook: verify `/<plugin>:<skill>` references written to markdown
# resolve to a skill that exists in the working tree.
# Triggered on Write|Edit of *.md files.
#
# Catches subagent / training-recall hallucinations — a slash-command reference
# written AS a capability that does not exist, or one left behind by a rename.
# Sibling of cli-flag-verify and stale-path-verify: same defect class, third
# oracle.
#
# ENFORCEABILITY TIER: Detect-then-judge — ADVISORY PLUS A HUMAN VERDICT, never
# an auto-fix. Globbing a plugins tree is exact only inside a marketplace repo
# that owns the referenced plugin. In a consuming repo the reference may name a
# plugin from another marketplace, or one the operator has simply not installed,
# and this hook cannot distinguish that from a hallucination. Per the org
# convention on enforceability tiers, that means the finding is a prompt for a
# human decision, not a determination. The plugins-root gate below is what keeps
# the noise inside the one context where the oracle is meaningful.
#
# PLUGINS-ROOT GATE: the hook does nothing unless the file being written lives in
# a repo with a `plugins/` directory containing at least one `.claude-plugin/`
# manifest — i.e. a marketplace repo. Outside one there is no local authority to
# resolve a reference against, so the guard stays silent rather than guessing.
#
# PLUGIN-SCOPE GATE: within a marketplace repo, a reference is only adjudicated
# when its PLUGIN half resolves locally. `/some-other-marketplace:thing` is left
# alone; `/guardrails:nonexistent` is reported, because this repo owns
# `guardrails` and can therefore say the skill is not there.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext.
#
# Disable with the skill_reference_verify_enabled userConfig option set to false.

set -uo pipefail

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "SKILL_REFERENCE_VERIFY"

hook::ctx_reset

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PostToolUse" "guardrails-skill-reference-verify" "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
# A CHANGELOG is an append-only historical record: an entry saying a skill was
# renamed MUST keep naming the old command, so every rename permanently adds an
# unresolvable reference to one. Measured on this repo: 56 of 63 findings (89%)
# were CHANGELOG rename entries, all correct as written, and excluding them moves
# the guard from 3.4% of files firing at 6% precision to 0.5% firing at 57%.
#
# Deliberately narrow. `docs/topics/*/PLAN.md` completion records are arguably the
# same shape, but two of the four real findings on this corpus live there — a
# broader "historical by contract" rule would cost half the signal.
*/CHANGELOG.md | CHANGELOG.md) exit 0 ;;
*.md) ;;
*) exit 0 ;;
esac

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk.
#
# Every payload field this hook can need, in ONE jq process (hook::jq_fields),
# not three — a jq spawn is fork() emulation on Windows Git Bash. Both per-tool
# content fields and replace_all are fetched together because selecting between
# them would cost another process; jq reads the same envelope either way, and the
# tool-specific choice happens below in the shell. `replace_all` keeps its
# `// false | tostring` INSIDE the filter: hook::jq_fields wraps each filter in
# `// ""`, and jq's `//` treats the boolean false as empty, so a bare
# `.tool_input.replace_all` would come back "" instead of "false". That is kept
# for parity with the pre-conversion output, not because a branch depends on it
# — every consumer below tests `== "true"`, which "" and "false" fail alike.
# Failure semantics are unchanged: a missing jq or an unparsable payload yields
# rc 1 here, which exits 0 exactly as the unmatched-TOOL case did —
# hook::require_jq above has already made the degraded state visible once per
# session.
hook::jq_fields "$INPUT" '.tool_name' '.tool_input.new_string' \
  '.tool_input.content' '.tool_input.replace_all // false | tostring' \
  '[(.tool_response | objects | .structuredPatch)[]?.lines[]?
    | select(type == "string" and startswith("+")) | .[1:]] | join("\n")' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
# Edit's `replace_all` (documented at
# https://code.claude.com/docs/en/tools-reference — Edit requires `old_string` to
# occur exactly once, and `replace_all: true` is how Claude edits every occurrence
# instead). Reconstruction needs it: with `replace_all` the same `new_string`
# lands in several places on purpose, so several matches are the edit's own
# footprint rather than an ambiguity. Absent or false on every ordinary Edit.
#
# `replace_all` alone cannot say WHICH occurrences this call wrote, and that is
# the whole of the residual reported in #2129: after `ghost` replaces `setup`
# everywhere, the `ghost` inside a pre-existing `ghost-old` reads exactly like one
# the edit produced. Nothing in `tool_input` separates them — but the premise
# "nothing in the PAYLOAD does" is false. `tool_response` carries the Edit tool's
# structured output, whose `structuredPatch` marks the lines the call actually
# wrote with a leading `+`.
#
# Both halves of that were confirmed against pages fetched 2026-08-10, not recall:
# `PostToolUse` input "includes both `tool_input`, the arguments sent to the tool,
# and `tool_response`, the result it returned"
# (<https://code.claude.com/docs/en/hooks>, "PostToolUse input"), and that field is
# "the tool's structured `Output` object" (ibid., the PostToolBatch note
# contrasting the two shapes). `Output` for Edit is `FileEditOutput`, whose
# `structuredPatch` is `Array<{oldStart, oldLines, newStart, newLines, lines:
# string[]}>` (<https://code.claude.com/docs/en/agent-sdk/typescript>, "Edit").
#
# OBSERVED, not merely documented: an independent reviewer captured a live
# PostToolUse payload (a temp settings.json dumping stdin, driven by a headless
# claude 2.1.225 session) and `tool_response` arrived as an OBJECT carrying
# `filePath newString oldString originalFile replaceAll structuredPatch
# userModified`. An object, not the serialized string `PostToolBatch` passes — the
# distinction the hooks reference draws, and the one shape that would have broken
# the filter below. `structuredPatch` was complete rather than truncated at 42
# replacement sites in a 300-line file.
#
# The read is SHAPE-TOLERANT anyway (`objects` in the jq filter): a non-object
# `tool_response` yields an empty witness and leaves the filter inert, instead of
# erroring hook::jq_fields into its `|| exit 0` and silencing the whole guard —
# a risk the pre-gate code did not carry, because it never touched the field.
#
# Kept as the LINE TEXTS rather than line numbers on purpose. Numbers would be
# wrong the moment another PostToolUse hook reformats the file between the write
# and this read — the case the reconstruction fallback below already exists for —
# and mapping a character offset back to a line number costs a whole-prefix scan
# per occurrence, which is the quadratic term this hook spent a release removing.
# Matching the physical line by text is a hash lookup and survives renumbering.
# Its one imprecision is conservative: an untouched line whose text is identical
# to an edited one still passes, which keeps a finding rather than dropping one.
EDIT_WROTE_LINES=""
REPLACE_ALL=false
case "$TOOL" in
Edit)
  SCAN_CONTENT="${HOOK_JQ_FIELDS[1]}"
  REPLACE_ALL="${HOOK_JQ_FIELDS[3]}"
  case "$REPLACE_ALL" in
  true | false) ;;
  *)
    # Advisory guard: a malformed replace_all extraction must not wear the permissive
    # "false" branch. Well-formed payloads always stringify to true/false; anything
    # else is an unreadable field — skip verification rather than guess.
    exit 0
    ;;
  esac
  EDIT_WROTE_LINES="${HOOK_JQ_FIELDS[4]}"
  ;;
Write) SCAN_CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
PLUGINS_DIR="$REPO_ROOT/plugins"

# PLUGINS-ROOT GATE. Outside a marketplace repo there is no local authority.
[[ -d "$PLUGINS_DIR" ]] || exit 0
shopt -s nullglob
manifests=("$PLUGINS_DIR"/*/.claude-plugin/plugin.json)
shopt -u nullglob
((${#manifests[@]} > 0)) || exit 0

# A plugin's command namespace is its manifest `name`, which need not equal its
# directory name. Build the name → directory map from the manifests themselves so
# a renamed directory or a name override resolves correctly.
#
# The manifest also decides WHERE that plugin's skills live. Its `skills` key
# holds a path or an array of paths, each relative to the plugin root, and those
# ADD to the conventional `skills/` directory rather than replacing it — verified
# against the Plugins reference (<https://code.claude.com/docs/en/plugins-reference>,
# "Path behavior rules", fetched 2026-08-10). Collect them per plugin so a skill
# loaded from a declared location resolves like any other.
#
# One documented exception is NOT modelled: for a marketplace entry whose `source`
# resolves to the marketplace root, declared subdirectories REPLACE the default
# `skills/` scan. Modelling it would mean reading marketplace.json to learn how
# each entry resolves, and the cost of not modelling it is bounded — the default
# stays in the search set, so at worst a reference resolves that Claude Code would
# not offer and this advisory stays quiet. Staying quiet is the failure this guard
# is allowed to have; a false alarm is not.
declare -A PLUGIN_DIR=() PLUGIN_SKILL_PATHS=()
for m in "${manifests[@]}"; do
  pdir="${m%/.claude-plugin/plugin.json}"
  pname=$(jq -r '.name // empty' "$m" 2>/dev/null | tr -d '\r')
  [[ -n "$pname" ]] || pname="${pdir##*/}"
  PLUGIN_DIR["$pname"]="$pdir"
  PLUGIN_SKILL_PATHS["$pname"]=$(
    jq -r '.skills // empty | if type == "array" then .[] else . end' "$m" 2>/dev/null | tr -d '\r'
  )
done

# Extract a plugin skill's frontmatter `name`, or nothing when it declares none.
# Tolerates quoting and a trailing YAML comment (`name: renamed # public
# command`); comments are stripped first so the value pattern stays anchored to
# end-of-line.
skill_frontmatter_name() {
  sed -n '1,40p' "$1" 2>/dev/null |
    sed -E 's/[[:space:]]+#.*$//' |
    sed -nE 's/^name:[[:space:]]*"?'"'"'?([A-Za-z0-9_-]+)"?'"'"'?[[:space:]]*$/\1/p' |
    head -1
}

# The directories a plugin's skills are loaded from: the conventional `skills/`,
# plus every path its manifest declares, plus the plugin root when the manifest
# declares nothing and the root itself is the skill.
#
# All three shapes come from the Plugins reference
# (<https://code.claude.com/docs/en/plugins-reference>, fetched 2026-08-10):
# declared paths are relative to the plugin root and start with `./` (the `skills`
# key also accepts `.`, and both `.` and `./` denote the root); they ADD to the
# default `skills/` scan; and a plugin with a root SKILL.md, no `skills/`
# subdirectory and no `skills` key auto-loads as a single-skill plugin. That last
# condition is honoured as written rather than widened — a root SKILL.md sitting
# beside a populated `skills/` is not loaded, and accepting it would suppress the
# advisory for a command Claude Code does not actually offer.
#
# Call as: skill_roots <plugin-dir> <declared-paths> -> $roots
# shellcheck disable=SC2154  # roots is the caller's frame, per the call contract
skill_roots() {
  local pdir="$1" declared="$2" rel
  roots=("$pdir/skills")
  while IFS= read -r rel; do
    [[ -n "$rel" ]] || continue
    rel="${rel#./}"
    rel="${rel%/}"
    if [[ -z "$rel" || "$rel" == "." ]]; then roots+=("$pdir"); else roots+=("$pdir/$rel"); fi
  done <<<"$declared"
  [[ -z "$declared" && ! -d "$pdir/skills" && -f "$pdir/SKILL.md" ]] && roots+=("$pdir")
  return 0
}

# A plugin skill's command segment comes from its frontmatter `name` when set,
# and from the directory name ONLY when it does not.
#
# The directory name is not an alias. A `skills/legacy-dir/SKILL.md` declaring
# `name: renamed` answers to `/plugin:renamed` and NOT to `/plugin:legacy-dir` —
# treating the directory as a second valid spelling would suppress the advisory
# for exactly the stale pre-rename references this guard exists to catch.
#
# A directory alone is also not a skill: it must carry a SKILL.md, or a leftover
# empty `skills/<name>/` would suppress the advisory for a command that never
# existed.
#
# A root may BE a skill directory rather than a directory of them — a declared
# path can point straight at a directory holding SKILL.md — so each root is tried
# both ways.
skill_resolves() {
  local pdir="$1" skill="$2" declared="$3" root sd sdir fname
  local -a roots=()
  skill_roots "$pdir" "$declared"
  for root in "${roots[@]}"; do
    if [[ -f "$root/$skill/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/$skill/SKILL.md")
      # No declared name → the directory name IS the command segment.
      [[ -z "$fname" || "$fname" == "$skill" ]] && return 0
    fi
    if [[ -f "$root/SKILL.md" ]]; then
      fname=$(skill_frontmatter_name "$root/SKILL.md")
      sdir="${root%/}"
      if [[ -n "$fname" ]]; then
        [[ "$fname" == "$skill" ]] && return 0
      else
        [[ "${sdir##*/}" == "$skill" ]] && return 0
      fi
    fi
    for sd in "$root"/*/SKILL.md; do
      [[ -f "$sd" ]] || continue
      fname=$(skill_frontmatter_name "$sd")
      [[ -n "$fname" && "$fname" == "$skill" ]] && return 0
    done
  done
  return 1
}

# Candidate references: `/<plugin>:<skill>` inside inline-code spans only. Prose
# is not scanned — an unbackticked `/a:b` is as likely to be a URL fragment, a
# Windows drive path, or a time range as a command.
#
# The reference need not be the whole span: an invocation commonly carries
# arguments (`/plugin:skill --apply`, `/plugin:skill <target>`). Take the leading
# command token from each span rather than requiring the span to match exactly,
# or argument-bearing invocations — the common form in this repo — go unchecked.
emit_refs() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//' |
    sed -nE 's|^(/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*)([[:space:]].*)?$|\1|p'
}

# Reconstruction is bounded on four axes, because this hook has a 30s timeout
# (hooks.json) and a guard that loses its advisory to a timeout has stopped
# guarding. Two of the four are set from a measured cost curve rather than a
# round number, because the cost they bound is QUADRATIC and a linear estimate
# of it is wrong by orders of magnitude at the sizes that matter.
#
# One anchor_offsets scan, measured on the slowest host available (Windows/Git
# Bash, quiescent, best of three) IN THE C LOCALE: 0.07 s at 32 KiB, 0.24 s at
# 64 KiB, 0.53 s at 96 KiB, 1.07 s at 128 KiB, 2.18 s at 192 KiB, 3.94 s at
# 256 KiB. That is ~0.065 s x (KiB/32)^2 — bash's `%%` pattern strip walks the
# string it searches rather than indexing it, so the scan is quadratic in FILE
# size no matter how short the anchor is. Extrapolated: ~67 s at 1 MiB, ~18
# minutes at 4 MiB.
#
# The locale label is not a footnote: under a UTF-8 locale the same scans cost
# ~6.5x more. reconstruct_partial_edit pins LC_ALL=C for its own scanning, so C
# IS the locale these figures describe.
# Re-checked rather than re-measured, on a second host of the same shape
# (lightly loaded, not quiescent — ~18% CPU across 32 cores): 0.054 s at 32 KiB,
# 0.221 s at 64 KiB, 0.880 s at 128 KiB, 3.410 s at 256 KiB — the same curve
# within host-to-host spread.
#
# Those figures are the FLOOR, not the cost: they time an anchor that matches near
# the end, so one strip walks the file and the second is free. A no-match strip
# walks it twice (2.31 s at 200 KiB, measured the same way), and the whole-hunk
# probe pays a scan of its own before the fallback runs at all. Both bounds below
# are therefore calibrated end to end against the hook, not from that table.
#
#   * RECONSTRUCT_MAX_CHARS — above this, reconstruction does not run at all,
#     because scanning a larger file already spends the hook's budget. Complete
#     references in the hunk are still reported by the direct scan; only
#     partial-edit recovery is skipped, which is this guard's permitted failure
#     direction. 128 KiB is far above any real markdown file this guard reads
#     (CHANGELOGs, the one shape that grows without bound, are excluded upstream).
#   * RECONSTRUCT_FALLBACK_SCAN_BUDGET — the per-line fallback scans once per
#     anchor, so its cap must fall as the file grows, on the same curve: the
#     anchor cap is this budget divided by (KiB)^2. 60000 holds the whole
#     invocation near 7 s at every file size on that host — 58 anchors at 32 KiB,
#     14 at 64 KiB, 3 at 128 KiB. A flat anchor count cannot do this, and neither
#     can a total-characters budget, which assumes the linear cost this scan does
#     not have. The end-to-end scale case in the test suite is what holds these
#     two numbers honest; an earlier pair passed the same case at 21 s of a 30 s
#     budget, which is a bound in name only.
#
# The other two are ordinary counts: a hunk stops contributing once it has
# yielded this many code spans, far above any real edit given that only spans the
# anchor reaches are kept; and an anchor stops being counted one occurrence past
# the cap, which is all the uniqueness gate needs to know.
#
# Deferred alternative, with its trigger: replacing the bash search with a
# linear-time locate would retire the file cap instead of living under it. It is
# not done here because every portable option is a subprocess whose offsets are
# BYTES where these are characters, or a line-oriented tool that cannot match a
# multi-line hunk at all. Revisit if a real markdown file ever exceeds the cap.
RECONSTRUCT_MAX_CHARS=131072
RECONSTRUCT_MAX_SPANS=40
RECONSTRUCT_MAX_OCCURRENCES=40
RECONSTRUCT_FALLBACK_SCAN_BUDGET=60000

# Append to the caller's $ctx every inline-code span in <region> whose extent
# OVERLAPS [<hunk-start>, <hunk-end>), and count them in the caller's $nspan.
#
# Span boundaries are exactly the ones emit_refs' own `\`[^\`]+\`` finds, so what
# is kept here and what is parsed there cannot disagree: leftmost match, at least
# one character between the backticks (an adjacent pair opens nothing), and never
# across a newline, since grep matches within a line.
#
# Call as: collect_overlapping_spans <region> <hunk-start> <hunk-end>
# shellcheck disable=SC2154  # ctx and nspan are the caller's frame, per the docblock
collect_overlapping_spans() {
  local region="$1" hs="$2" he="$3"
  local i=0 a b rest pre after inner
  while :; do
    rest="${region:i}"
    pre="${rest%%\`*}"
    # No backtick left in the region — nothing further can open a span.
    [[ "$pre" == "$rest" ]] && return 0
    a=$((i + ${#pre}))
    after="${region:a+1}"
    inner="${after%%\`*}"
    # No closing backtick anywhere after this one: no span can open here or later.
    [[ "$inner" == "$after" ]] && return 0
    # An empty inner (an adjacent pair) or one spanning a newline is not a match
    # for grep either; it retries from the next character, so this walk does too.
    if [[ -z "$inner" || "$inner" == *$'\n'* ]]; then
      i=$((a + 1))
      continue
    fi
    b=$((a + 1 + ${#inner}))
    # The span occupies [a, b] inclusive of both backticks; the hunk [hs, he).
    if ((a < he && b >= hs)); then
      ctx+="\`$inner\`"$'\n'
      ((++nspan >= RECONSTRUCT_MAX_SPANS)) && return 0
    fi
    i=$((b + 1))
  done
}

# Locate every occurrence of <anchor> in the caller's $content, into the caller's
# $offs. Stops one past the occurrence cap: the uniqueness gate only needs to know
# whether there is more than one, and `replace_all` stops contributing context at
# the cap anyway.
#
# Occurrences, not matching lines. Counting lines is not enough: two occurrences
# on one physical line are a single line, and that is a real shape — inserting
# `legacy` into a line that already carries an untouched `` `/alpha:ghost-legacy` ``
# leaves the anchor twice on that line, and reporting the reference would be an
# advisory about text this call never wrote.
#
# ONE pattern operation per iteration. `${rest%%"$anchor"*}` both tests and locates:
# it returns $rest unchanged when there is no match, and a literal `==` on that
# result is a memcmp, not a second search. Asking `[[ $rest == *"$anchor"* ]]` first
# and then stripping searched the same text twice, which doubled the cost of the
# whole-hunk locate — where the anchor is the size of the edit and the search is the
# dominant term.
#
# Call as: anchor_offsets <anchor> -> $offs
# shellcheck disable=SC2154  # content and offs are the caller's frame, per the call contract
anchor_offsets() {
  local anchor="$1" alen=${#1}
  local rest="$content" base=0 pre
  offs=()
  while :; do
    pre="${rest%%"$anchor"*}"
    [[ "$pre" == "$rest" ]] && return 0
    offs+=($((base + ${#pre})))
    ((${#offs[@]} > RECONSTRUCT_MAX_OCCURRENCES)) && return 0
    base=$((base + ${#pre} + alen))
    rest="${content:base}"
  done
}

# Partial-replacement context reconstruction (Edit only). The same shape lives in
# stale-path-verify and cli-flag-verify, which still take the whole located line
# and filter it by word token; this one keeps only the part of the line the hunk
# reaches, so the three are not identical.
#
# An Edit may replace an arbitrary substring: swapping `setup` for `ghost` inside
# an existing `/alpha:setup` leaves `/alpha:ghost` on disk, but the hunk is the
# bare word `ghost` and carries no command for emit_refs to find, so a
# newly-broken reference would be silently missed.
#
# Recover bounded context POSITIONALLY. The edit is already applied by PostToolUse
# time, so every line of new_string is on disk verbatim and its own text locates
# the exact span of the file this call wrote. Diff-scope is then an overlap test
# rather than a word-token heuristic. Two gates:
#
#   1. LOCATE by the hunk's own text, never by its tokens, and only where that text
#      OCCURS exactly once in the file. A unique occurrence IS where the edit
#      landed. Anything repeated cannot say which copy that was, so it is dropped
#      rather than unioned. Exception: under `replace_all` every occurrence is a
#      place this call edited, so all are kept. The hunk is located WHOLE, falling
#      back to line by line only when the whole no longer matches.
#   2. KEEP only the inline-code spans whose extent OVERLAPS the located anchor.
#
# Gate 2 is what a word-token filter could never be: exact. Sharing a physical line
# with the hunk is not evidence the edit wrote a reference, so a span the anchor
# does not reach is dropped no matter how many words it happens to share with the
# hunk. And overlap has no minimum length to clear, so an Edit replacing two
# characters inside a command segment is scoped as precisely as one replacing
# twenty — where the token filter, needing a token long enough to filter on, simply
# produced none and gave up.
#
#   3. Under `replace_all` ONLY, keep an occurrence just when its physical line is
#      one `structuredPatch` reports the call as having WRITTEN. Gate 1's
#      uniqueness rule is what separates an edited occurrence from a coincidental
#      one everywhere else, and `replace_all` is exactly where that rule is
#      suspended — so it is the one branch that needs an external witness.
#
# Gate 3 may only ever REMOVE an occurrence when it can positively identify at
# least one the call wrote. Comparison is whitespace-normalized, and if the
# witness recognizes no occurrence at all it abstains and the unfiltered set
# stands. Both exist for the same reason: an earlier-ordered PostToolUse hook can
# reformat the file between the write and this read — the case the per-line
# fallback above was built for — and a witness compared to rewritten text would
# otherwise turn this gate from a filter into a silent mute, dropping a genuinely
# written reference. Normalization covers the whitespace reflow formatters
# actually do; the abstain covers everything else.
#
# What this does NOT claim, still. The witness is per LINE, so two references on
# one physical line stand or fall together, and an untouched line whose text
# duplicates an edited one verbatim is kept — nothing separates two identical
# lines. A multi-line `new_string` is not filtered at all: its anchor extent spans
# several lines and matches no single patch line. Where `structuredPatch` is absent
# (an older harness, or any payload without `tool_response`) the filter is inert by
# construction. Every one of those degrades to the pre-gate behaviour, which is
# over-reporting — the direction this guard already accepts — never under-reporting.
# Reconstruction remains a best effort under an advisory guard, not a proof that
# every reported line was written by this call; it simply no longer reports a line
# the payload itself says was untouched.
#
# Cost is ONE read of the file and, normally, ONE scan of it — no subprocess per
# hunk line and no rescan per hunk line either. The `grep` this replaced spawned two
# processes per line of the hunk; scanning in-memory removed the processes but left
# the per-line rescan, which is anchors TIMES file size and still spent the timeout
# on a thousand-line hunk. Locating the hunk whole is what removes the factor; the
# scanning budget bounds the fallback that cannot.
# The physical line an anchor occurrence sits in: back to the newline before it,
# forward to the newline after. A reference the edit landed inside is only whole
# when read from the line, not from the anchor alone — which is why the line is
# read at all, and why only the part of it the anchor reaches may be kept.
#
# Reads the caller's $content, $alen; sets the caller's $line, $hs, $he. Written
# as a function because Gate 3 needs the line one pass before the span walk does,
# and computing it twice from two copies of this arithmetic is how the two drift.
# Call as: anchor_line <offset> -> $line $hs $he
# shellcheck disable=SC2154  # content/alen/line/hs/he are the caller's frame, per the call contract
anchor_line() {
  local off="$1" head tail
  head="${content:0:off}"
  head="${head##*$'\n'}"
  hs=${#head}
  tail="${content:off+alen}"
  tail="${tail%%$'\n'*}"
  he=$((hs + alen))
  line="${content:off-hs:he+${#tail}}"
}

# Whitespace-normalized form of <text>, for comparing a line on disk against the
# line `structuredPatch` recorded at edit time. Tabs become spaces, runs collapse,
# ends are trimmed.
#
# Comparing raw text made Gate 3 undo the reformatting tolerance the fallback
# above exists to provide: a downstream PostToolUse hook that reflows whitespace
# leaves the anchor locatable (a literal substring search does not care what
# surrounds it) while changing the physical line, so a genuinely written reference
# was dropped. Whitespace is what formatters move; normalizing it keeps the
# witness usable without weakening what it discriminates, since a DIFFERENT
# reference's line differs by far more than spacing.
#
# No subshell: this runs once per occurrence, and `$(…)` here would fork per line.
# Call as: norm_ws <text> -> $NORM_WS
norm_ws() {
  local s="${1//$'\t'/ }"
  while [[ "$s" == *"  "* ]]; do s="${s//  / }"; done
  s="${s#"${s%%[![:space:]]*}"}"
  NORM_WS="${s%"${s##*[![:space:]]}"}"
}

reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  # Pin the locale this function's own scanning runs in, so its matcher semantics
  # and its cost are the consumer's ambient locale's business no longer. Every
  # search below is LITERAL, so a multibyte locale buys this function nothing and
  # charges it ~6.5x: one no-match scan, measured on a lightly-loaded Windows/Git
  # Bash host (bash 5.3, 32 logical cores at ~18%), costs 0.054 s at 32 KiB / 0.221 s
  # at 64 KiB / 0.880 s at 128 KiB under C, against 0.395 s / 1.447 s / 5.786 s
  # under en_US.UTF-8. That ratio is the reason for the pin; no wall-clock BOUND
  # is claimed from it, and the caps above are calibrated end to end against the
  # hook rather than off that table, so this is not a correction to them.
  #
  # `+x` is load-bearing, not decoration. The whole ~6.5x is bash's OWN `%%`
  # walk; the child processes are locale-insensitive here (`grep -oE` on the same
  # 64 KiB measured 0.139 s under BOTH locales), so exporting the pin would buy
  # nothing and cost real behavior: `[[:space:]]` is ASCII-only under C but admits
  # some non-ASCII spaces under a UTF-8 locale, so an exported pin would make
  # emit_refs below drop a reference whose argument separator is one of them, and
  # would make the blank-line filter keep an anchor line it used to discard.
  # Un-exported, children run in the caller's locale exactly as before, and nothing
  # they emit changes. Nothing needs them pinned either: no offset ever crosses a
  # process boundary — the fallback's grep yields anchor STRINGS and emit_refs
  # consumes a context STRING.
  #
  # WHICH separators those are is the host C library's table, not this hook's, and
  # it is not portable: glibc dropped U+00A0 and U+202F from `space` in 2.26, while
  # Cygwin/MSYS still classifies them; U+3000 and U+2028 are admitted by both.
  # Measured. The regression case DISCOVERS a separator this host actually
  # classifies differently rather than hardcoding one: a hardcoded byte (U+00A0,
  # say) passes on one platform and fails on another, asserting a libc's table
  # rather than this hook's behavior.
  #
  # Scope and lifetime were verified rather than assumed: assigning LC_ALL re-runs
  # setlocale even for a `local` (and even with `+x`), and bash restores the
  # previous value AND its export attribute on return, including when the consumer
  # exported LC_ALL itself.
  #
  # Safe because every offset this function computes is also consumed by it: the
  # unit is bytes here and characters outside, and the two never meet. Slices are
  # taken only at a literal match or at a newline, and no UTF-8 multibyte sequence
  # contains an ASCII byte, so a byte slice never splits a character.
  # RECONSTRUCT_MAX_CHARS is therefore read as bytes, the stricter of the two
  # readings, so it cannot raise the ceiling it exists to set, and the fallback's
  # KiB estimate stops understating a multibyte file and over-granting its anchor
  # cap. Both shifts are toward less work, never more.
  local +x LC_ALL=C
  local content
  content=$(<"$FILE") || return 0
  # Gate on the size BEFORE touching the string: every step past this point is a
  # whole-string operation, so a gate that runs after one of them has left that one
  # unbounded. Measuring the raw text rather than the normalized text also errs
  # toward not reconstructing, which is the safe direction here.
  ((${#content} <= RECONSTRUCT_MAX_CHARS)) || return 0
  # new_string arrived with CR stripped, so a CRLF file must be searched the same
  # way or no anchor would ever locate. Offsets are read back off this normalized
  # text only, never off the bytes on disk.
  content=${content//$'\r'/}

  local ctx="" nspan=0 anchor alen off hs he line cap kib located_whole=0
  local -a offs=() anchors=() keep=()

  # Gate 3's witness set: the physical lines `structuredPatch` reports this call as
  # having written, as a hash. Built only where it is consulted — under
  # `replace_all`, whose suspended uniqueness rule is the reason an external
  # witness is needed at all. Empty (no `tool_response`, or a patch with no added
  # lines) leaves the filter inert, which is the pre-existing behaviour.
  local -A wrote=()
  local filter_wrote=0 wl NORM_WS
  if [[ "$REPLACE_ALL" == "true" && -n "$EDIT_WROTE_LINES" ]]; then
    while IFS= read -r wl; do
      # Keys are whitespace-normalized, matching how the on-disk line is compared,
      # and carry a literal prefix so a patch line reading `@` or `*` cannot alias
      # bash's own array subscripts on lookup.
      norm_ws "$wl"
      wrote["L$NORM_WS"]=1
    done <<<"$EDIT_WROTE_LINES"
    ((${#wrote[@]})) && filter_wrote=1
  fi

  # The hunk is written to disk CONTIGUOUSLY, so locate it WHOLE first — one scan
  # for the entire edit instead of one per line. The loop below is then driven by a
  # single anchor, and the span set it produces is the same one the per-line walk
  # produced: an anchor's extent is the text the edit wrote on its own line, and the
  # whole hunk's extent is the union of exactly those. Multi-line is no obstacle —
  # the extent is bounded by offset, and a code span never crosses a newline.
  anchor_offsets "$SCAN_CONTENT"
  if ((${#offs[@]})) && { [[ "$REPLACE_ALL" == "true" ]] || ((${#offs[@]} == 1)); }; then
    anchors=("$SCAN_CONTENT")
    # $offs already holds this anchor's offsets; the loop must not pay for them twice.
    located_whole=1
  else
    # FALLBACK, for a hunk that is no longer on disk verbatim — another PostToolUse
    # hook may have reformatted the file between the write and this read — or one
    # whose whole text repeats. Individual lines can still locate, so walk them; the
    # budget is what keeps that walk from costing anchors TIMES file size.
    mapfile -t anchors < <(printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*$' 2>/dev/null)
    ((${#anchors[@]})) || return 0
    kib=$(((${#content} + 1023) / 1024))
    ((kib < 1)) && kib=1
    cap=$((RECONSTRUCT_FALLBACK_SCAN_BUDGET / (kib * kib)))
    ((cap < 1)) && cap=1
    ((${#anchors[@]} > cap)) && anchors=("${anchors[@]:0:cap}")
  fi

  # A repeated anchor line resolves identically every time, so scan each once.
  declare -A seen=()
  for anchor in "${anchors[@]}"; do
    alen=${#anchor}
    ((alen)) || continue
    [[ -n "${seen[$anchor]:-}" ]] && continue
    seen["$anchor"]=1
    if ((located_whole)); then located_whole=0; else anchor_offsets "$anchor"; fi
    ((${#offs[@]})) || continue
    # A non-unique anchor cannot say WHICH occurrence the edit landed on, so it is
    # dropped rather than unioned. Cost: a missed advisory when an edit lands in
    # text that repeats verbatim elsewhere in the file. For a detect-then-judge
    # guard that is the right side of the trade — it is degraded far worse by being
    # wrong when it speaks than by staying quiet.
    [[ "$REPLACE_ALL" == "true" ]] || ((${#offs[@]} == 1)) || continue

    # Gate 3, applied BEFORE the span walk so it can abstain as a whole.
    #
    # A MULTI-LINE anchor's extent is not a single physical line and can match no
    # patch line, so that shape is never filtered.
    keep=("${offs[@]}")
    if ((filter_wrote)) && [[ "$anchor" != *$'\n'* ]]; then
      keep=()
      for off in "${offs[@]}"; do
        anchor_line "$off"
        norm_ws "$line"
        [[ -n "${wrote[L$NORM_WS]:-}" ]] && keep+=("$off")
      done
      # ABSTAIN. If the witness recognized NOTHING, it is stale rather than
      # discriminating — a downstream PostToolUse hook rewrote the lines between
      # the write and this read, which is the very case the fallback above exists
      # for. Letting a stale witness exclude every occurrence would turn this gate
      # into a silent mute. Falling back to the unfiltered set is exactly the
      # behaviour that shipped before this gate, so the gate can only ever remove
      # occurrences when it can positively identify at least one the call wrote.
      ((${#keep[@]})) || keep=("${offs[@]}")
    fi

    for off in "${keep[@]}"; do
      anchor_line "$off"
      collect_overlapping_spans "$line" "$hs" "$he"
      ((nspan >= RECONSTRUCT_MAX_SPANS)) && break 2
    done
  done
  [[ -n "$ctx" ]] || return 0

  local saved="$SCAN_CONTENT"
  SCAN_CONTENT="$ctx"
  emit_refs
  SCAN_CONTENT="$saved"
}

declare -A CHECKED=()
UNRESOLVED=()
REFS=()
mapfile -t REFS < <(emit_refs)
# Reconstruction runs on EVERY Edit, not only when the hunk yielded nothing. One
# hunk can both carry a complete reference and change a substring inside another
# (`setup and placeholder` -> `ghost` plus a literal `/alpha:setup`), so gating on
# an empty REFS would miss the partial half. Duplicates are harmless — CHECKED
# dedupes below.
if [[ "$TOOL" == "Edit" ]]; then
  mapfile -t -O "${#REFS[@]}" REFS < <(reconstruct_partial_edit)
fi

for ref in "${REFS[@]}"; do
  [[ -n "$ref" ]] || continue
  [[ -n "${CHECKED[$ref]:-}" ]] && continue
  CHECKED["$ref"]=1
  plugin="${ref#/}"
  plugin="${plugin%%:*}"
  skill="${ref##*:}"
  # PLUGIN-SCOPE GATE: only adjudicate a plugin this repo owns.
  pdir="${PLUGIN_DIR[$plugin]:-}"
  [[ -n "$pdir" ]] || continue
  skill_resolves "$pdir" "$skill" "${PLUGIN_SKILL_PATHS[$plugin]:-}" && continue
  UNRESOLVED+=("$ref")
done

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel="$FILE" findings_json="[]"
  if command -v cygpath >/dev/null 2>&1; then
    local _file_lm _root_lm
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    [[ -n "$_file_lm" && -n "$_root_lm" ]] && file_rel="${_file_lm#"$_root_lm"/}"
  else
    file_rel="${FILE#"$REPO_ROOT"/}"
  fi
  # Redaction: a path that could not be made repo-relative degrades to its
  # basename — never an absolute path, which would embed the developer's
  # username.
  case "$file_rel" in
  /* | [A-Za-z]:*)
    file_rel="${file_rel##*/}"
    file_rel="${file_rel##*\\}"
    ;;
  *) ;;
  esac
  if ((${#UNRESOLVED[@]} > 0)); then
    findings_json=$(printf '%s\n' "${UNRESOLVED[@]}" | jq -Rn '[inputs]' 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  hook::emit_telemetry "skill-reference-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#UNRESOLVED[@]} > 0)); then
  hook::ctx_append "skill-reference-verify: ${#UNRESOLVED[@]} skill reference(s) do not resolve in $FILE"
  hook::ctx_append "This repo owns each plugin named below, so it can say the skill is not there:"
  # Name the directories the search ACTUALLY covered, from the same skill_roots
  # the resolution used. Naming only `skills/` understates the search for a plugin
  # whose manifest declares paths, and the advisory ends by telling the reader to
  # confirm against the tree — pointing them at the wrong part of it is the one
  # thing that instruction cannot survive. For the conventional layout this still
  # renders exactly `plugins/<plugin>/skills/`.
  declare -a roots=()
  for r in "${UNRESOLVED[@]}"; do
    plugin="${r#/}"
    plugin="${plugin%%:*}"
    skill_roots "${PLUGIN_DIR[$plugin]}" "${PLUGIN_SKILL_PATHS[$plugin]:-}"
    searched=""
    for root in "${roots[@]}"; do
      searched+="${searched:+, }plugins/${root#"$PLUGINS_DIR/"}/"
    done
    hook::ctx_append "  UNRESOLVED_SKILL: $r (no such skill under $searched)"
  done
  hook::ctx_append ""
  hook::ctx_append "Detect-then-judge: this is a prompt for your verdict, not a determination."
  hook::ctx_append "Confirm against the tree. A reference retained deliberately — documenting"
  hook::ctx_append "a rename, or a capability another marketplace ships — is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0

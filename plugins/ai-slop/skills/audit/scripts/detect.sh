#!/usr/bin/env bash
# AI-slop findings for /ai-slop:audit. Read-only.
#
# Rules: the catalog entries with v1=script (reference/catalog.md is the
# inventory; the severity crosswalk in the detector-findings convention holds
# the argued tier per rule). Two rule classes:
#   pattern  fires per prose line matching the rule's expression
#   density  fires per file when matches per 1000 words reach the threshold
#
# Output: Finding rows (rule/file/line/fired/excerpt), then Summary rows with
# per-rule finding and declined counts, the declined count split by cause
# (marker, quote, config), and the rule's disabled flag. All key=value,
# line-oriented. A chunked run (--offset/--limit) emits one Summary block per
# chunk; emit-findings.sh sums them. --list-targets prints the resolved target
# list instead of scanning: one `<key><TAB><path>` row per file, the key spelled
# as the file= field.
# Exit: always 0 on audit paths (a read-only audit must never fail the caller);
# 2 on unknown arguments or unreadable --paths-file, when no temporary
# directory can be made for the scan's per-file streams (removed on exit), or
# when prose extraction fails.
#
# Prose extraction: fenced code blocks, inline code spans, and ignore-marked
# lines and blocks are removed before any rule runs; exempted candidates are
# counted as declined per rule, never silently dropped.
#
# Unicode: matching uses LC_ALL=C byte sequences and POSIX ERE only, so
# behavior is identical across GNU and BSD grep and independent of the host
# locale. Em dash is \xE2\x80\x94; emoji classes are \xF0\x9F.. and
# \xE2[\x98-\x9E\xAC\xAD]..; curly quotes and invisible-space residue are
# \xE2\x80[\x98\x99\x9C\x9D\x8B] and \xC2\xA0.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/opt-value.sh
source "$SCRIPT_DIR/lib/opt-value.sh"
# shellcheck source=lib/cascade-read.sh
source "$SCRIPT_DIR/lib/cascade-read.sh"
# shellcheck source=lib/resolve-targets.sh
source "$SCRIPT_DIR/lib/resolve-targets.sh"

# All text processing runs in the C locale: the byte-sequence rules require it,
# and word counts diverge between UTF-8 and C locales (caught by the CI
# portability probe — a UTF-8 default runner counted 12 words where C counted
# 15 on the same line). Forcing it here makes output identical on every
# machine regardless of the caller's locale.
export LC_ALL=C

EM_DASH=$'\xe2\x80\x94'
EMOJI_ERE=$'(\xf0\x9f|\xe2[\x98-\x9e\xac\xad])'
CURLY_ERE=$'(\xe2\x80[\x98\x99\x9c\x9d\x8b]|\xc2\xa0)'

# Distinctive AI-vocabulary defaults (catalog rule-ai-vocabulary; config-tunable).
# The trailing four are measured admissions: the three plain-word additions
# (catalog calibration record, second pass) and pre-existing (fourth pass, from
# the model-era section), common enough alone that only the density gate makes
# them safe to ship. The bare singular "underscore" is not on the list: the
# source's entry targets the verb ("underscores the importance"), and in a
# programming-docs repository the singular is almost always the noun, the `_`
# character in a naming convention. "underscores" stays, as the verb's common
# form; rule-significance-inflation catches its stock objects separately.
DEFAULT_VOCAB="delve tapestry testament pivotal crucial underscores boasts intricate intricacies meticulous meticulously garner bolstered fostering showcasing vibrant nestled groundbreaking renowned interplay enduring utilize leverage facilitate pre-existing"

# Model-era phrase roster (catalog rule-model-era-phrases; config-tunable via
# phrase_add/phrase_remove). One ERE alternation fragment per element, apostrophes
# spelled `.` like the PATTERN_RULES phrase lists. Anchored forms only: the bare
# "honest take" and "the unlock" bigrams are recorded-only in the catalog
# (measured domain-literal false positives). A fragment may contain spaces, so
# these are read and joined as whole elements, never word-split.
MODEL_PHRASES=("the part most people skip" "(the|my) honest take" "that.s the unlock")

# --- Rule registry ---------------------------------------------------------------
# Pattern rules: slug|fired label|case-insensitive(0/1)|whole-word(0/1)|class|ERE
#
# whole-word adds grep's POSIX -w: the match must be bounded by non-word
# characters on both sides. Phrase rules need it — without it "great question"
# fires on "These are great questions for the reviewer", reporting an
# IMPORTANT-tier chat-residue finding on ordinary prose. GNU's \b would express this inline but is not
# POSIX, and this script's cross-grep parity claim rests on POSIX ERE only.
#
# It is OFF for rules whose match legitimately abuts a word character or is not
# word-shaped at all: the byte-class rules (em dash, emoji, curly quotes),
# the two EREs carrying `[^.]{0,80}` wildcards, the citation tokens (`[cite:`
# is followed by digits), and `utm_[a-z]+=` (followed by its value).
#
# class is `wording` or `typography` — the policy-level quotation exemption
# (catalog "Quotation exemption"; design borrowed from Wikipedia's MOS "principle
# of minimal change"). A wording rule judges prose the repo AUTHORS, so it never
# scans quoted material: blockquote lines and double-quoted spans are removed
# from its input and counted as declined. A typography rule targets artifacts
# that are defects wherever they appear (byte residue, tracking params, citation
# tokens), so it scans quoted material too.
#
# rule-emoji-formatting anchors on the prose stream's field-separator tab and
# then walks the markdown prefixes a formatting glyph can sit behind: up to
# three spaces of indentation, any depth of blockquote marker, and then one
# heading or bullet marker. A blockquote marker takes at most ONE following
# space, because that space is part of the marker and every space after it is
# the quote's own content: `>` and five spaces is an indented code block inside
# a quote, and a greedy `[ ]*` there would report a glyph in code as
# formatting. The blockquote branch is what catches a callout
# written as `> <glyph>` or `> ### <glyph>`; without it the same glyph fired at
# column zero and passed clean one character further in, which is how six
# callouts survived a whole fix pass. The glyph must still follow the last
# prefix DIRECTLY, so an emoji in content position stays clean: the catalog
# scopes this rule to emoji used as bullets, section markers, or visual
# separators, and an emoji inside a sentence is none of those.
PATTERN_RULES=(
  "rule-em-dash|zero-tolerance|0|0|typography|${EM_DASH}"
  "rule-emoji-formatting|formatting emoji|0|0|typography|$(printf '\t')[ ]?[ ]?[ ]?(>[ ]?)*(#+[[:space:]]+|[-*+][[:space:]]+)?${EMOJI_ERE}"
  "rule-curly-artifacts|unicode artifact|0|0|typography|${CURLY_ERE}"
  "rule-significance-inflation|phrase match|1|1|wording|(stands as a testament|testament to|pivotal (moment|role)|underscores (its|the) (importance|significance)|reflects broader|enduring legacy|marks a (significant )?shift|evolving landscape|indelible mark|deeply rooted|setting the stage for|rich tapestry|key turning point|(crucial|vital) role)"
  "rule-negative-parallelism|construction match|1|0|wording|(not (just|only|simply|merely) [^.]{0,80}but|isn.t [^.;]{0,60}[;,] it.s)"
  "rule-challenges-conclusion|formula match|1|0|wording|(despite [^.]{0,80}(challenge|hurdle)|challenges (remain|ahead|persist)|faces (several|numerous|significant|ongoing) challenges)"
  "rule-knowledge-cutoff-disclaimer|assistant-frame residue|1|1|wording|(knowledge cutoff|as of my last (knowledge )?(update|training)|up to my last training( update)?|i cannot browse|i do not have access to real|as an ai( language)? model|while specific details are (limited|scarce)|not widely (available|documented|disclosed)|(in|from) the (provided|available) (sources|search results)|based on (the )?available information)"
  "rule-llm-citation-artifacts|citation residue|0|0|typography|(oaicite|\[cite:|grok_card|attached_file|contentReference|filecite)"
  "rule-utm-params|tracking parameter|0|0|typography|utm_[a-z]+="
  "rule-chatbot-artifacts|chat-turn residue|1|1|wording|(i hope this helps|let me know if you|feel free to (ask|reach out)|i.d be happy to|happy to help|great question|you.re absolutely right|found the smoking gun)"
  "rule-filler-phrases|filler phrase|1|1|wording|(in order to|due to the fact that|it( is|.s) (important to note|worth noting)|it should be noted)"
  "rule-stacked-hedging|stacked hedge|1|1|wording|((could|may|might) potentially|(could|might) possibly)"
  "rule-model-era-phrases|phrase match|1|1|wording|__PHRASES__"
)
# Density rules: slug|threshold key|default threshold|ERE (vocab ERE is built at runtime).
# All density rules are wording-class: they judge authored prose, so they run on
# the quote-exempt stream and its word count.
# A density rule needs BOTH density >= threshold AND at least DENSITY_MIN_HITS
# matches: short files otherwise fire on a single normal-prose occurrence
# (measured on this repo: one triad in a 201-word doc hit 5.0/1000).
#
# rule-rule-of-three was demoted from this table to the judgment rubric
# (catalog reclass, 2026-08-25): a dogfood fix pass ended with 18/18 residual
# findings on load-bearing enumerations, no surveyed prose linter implements a
# tricolon rule, and the shipped ERE matched only single-word triads — biasing
# it toward exactly the terse operative enumerations the catalog's own boundary
# ("enumerating three actual things is not a tell") protects.
DENSITY_MIN_HITS=3
DENSITY_RULES=(
  "rule-ai-vocabulary|ai_vocabulary|3.0|__VOCAB__"
  "rule-copulative-avoidance|copulative_avoidance|4.0|(serves as|stands as|functions as|operates as|acts as a|represents a|marks a|boasts|features a|offers a|maintains a|refers to)"
)

PATHS_FILE=""
TARGETS=()
OFFSET=0
LIMIT=0
SHOW_CONFIG=0
LIST_TARGETS=0

usage() {
  cat <<'EOF'
detect.sh: emit AI-slop findings for /ai-slop:audit.

Usage:
  detect.sh [file.md ...]
  detect.sh --paths-file <file>
  detect.sh --offset N --limit N   # chunk the sorted target list
  detect.sh --list-targets [...]   # print <key><TAB><path> per file a scan would read, then exit
  detect.sh --show-config          # print effective config per layer, then exit
  detect.sh --help

With no paths, scans the repository's tracked markdown (git ls-files '*.md').
A --paths-file with no non-blank line scans nothing; it also reads --list-targets output.
--list-targets ignores --offset/--limit; --show-config wins over it.
Exit: 0 on audit, 2 on unknown arguments or unreadable --paths-file.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --paths-file)
    require_opt_value "detect.sh" "$@"
    PATHS_FILE="$2"
    shift 2
    ;;
  --offset)
    require_opt_value "detect.sh" "$@"
    OFFSET="$2"
    shift 2
    ;;
  --limit)
    require_opt_value "detect.sh" "$@"
    LIMIT="$2"
    shift 2
    ;;
  --show-config)
    SHOW_CONFIG=1
    shift
    ;;
  --list-targets)
    LIST_TARGETS=1
    shift
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  -*)
    echo "detect.sh: unknown option: $1" >&2
    exit 2
    ;;
  *)
    TARGETS+=("$1")
    shift
    ;;
  esac
done

# --- Config cascade (.claude/ai-slop.json; user-global -> team -> overlay) ------

REPO_ROOT="${CLAUDE_PROJECT_DIR:-}"
if [[ -z "$REPO_ROOT" ]]; then
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi

# Config-cascade step 2: a home or non-repo root has no team or overlay layer, and
# a team or overlay file that is the user-global file is not read a second time.
# shellcheck source=../../../lib/config-root.sh
source "$SCRIPT_DIR/../../../lib/config-root.sh"
USER_CFG="${HOME:-/nonexistent}/.claude/ai-slop.json"
CFG_LAYERS=()
[[ -f "$USER_CFG" ]] && CFG_LAYERS+=("$USER_CFG")
if [[ "$(config_root_classify "$REPO_ROOT")" == repo ]]; then
  for _cfg in "$REPO_ROOT/.claude/ai-slop.json" "$REPO_ROOT/.claude/ai-slop.local.json"; do
    [[ -f "$_cfg" ]] && ! config_root_paths_same "$_cfg" "$USER_CFG" && CFG_LAYERS+=("$_cfg")
  done
fi

HAVE_JQ=1
command -v jq >/dev/null 2>&1 || HAVE_JQ=0

VOCAB="$DEFAULT_VOCAB"
PHRASE_ADD=()
PHRASE_REMOVE=()
PHRASE_ADD_LAYER=""
EXCLUDED_GLOBS=()
EM_DASH_ALLOWED_GLOBS=()
DISABLED_RULES=""
# Per-rule path exemptions: rule_allowed_paths maps a rule slug to globs whose
# files decline that rule (the generalization of em_dash_allowed_paths, which
# stays supported as an alias feeding rule-em-dash's entry). This is the
# proportionate closure for a density rule: a line marker cannot quiet a
# per-file density verdict, a file marker silences every rule, and this key
# silences exactly one rule on exactly the named paths.
declare -A RULE_ALLOWED_GLOBS

# threshold_for <threshold key> <default>: .thresholds.<key> from config, else default.
threshold_for() {
  local key="$1" default="$2" v
  cascade::scalar v ".thresholds.${key}" ${CFG_LAYERS[@]+"${CFG_LAYERS[@]}"}
  printf '%s' "${v:-$default}"
}

if [[ "$HAVE_JQ" -eq 1 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  cascade::list EXCLUDED_GLOBS excluded_paths "${CFG_LAYERS[@]}"
  cascade::list EM_DASH_ALLOWED_GLOBS em_dash_allowed_paths "${CFG_LAYERS[@]}"
  _disabled=()
  cascade::list _disabled disabled_rules "${CFG_LAYERS[@]}"
  DISABLED_RULES="${_disabled[*]-}"
  cascade::slug_map RULE_ALLOWED_GLOBS rule_allowed_paths "${CFG_LAYERS[@]}"
  _add=()
  _remove=()
  cascade::list _add vocab_add "${CFG_LAYERS[@]}"
  cascade::list _remove vocab_remove "${CFG_LAYERS[@]}"
  add="${_add[*]-}"
  remove="${_remove[*]-}"
  [[ -n "${add// /}" ]] && VOCAB="$VOCAB $add"
  if [[ -n "${remove// /}" ]]; then
    filtered=""
    for w in $VOCAB; do
      case " $remove " in
      *" $w "*) ;;
      *) filtered="$filtered $w" ;;
      esac
    done
    VOCAB="${filtered# }"
  fi
  cascade::list PHRASE_ADD phrase_add "${CFG_LAYERS[@]}"
  PHRASE_ADD_LAYER="$cascade_list_layer"
  cascade::list PHRASE_REMOVE phrase_remove "${CFG_LAYERS[@]}"
elif [[ "$HAVE_JQ" -eq 0 && "${#CFG_LAYERS[@]}" -gt 0 ]]; then
  echo "Note: jq not found; config layers present but unread, using defaults" >&2
fi

VOCAB_ERE="($(printf '%s' "$VOCAB" | tr ' ' '|'))"

# Effective phrase roster: shipped minus phrase_remove, plus phrase_add, then
# hygiene. Both hygiene checks close measured failure modes, not hypothetical
# ones: an empty/whitespace fragment joins as an empty alternation branch that
# matches EVERY line (flood), and a fragment grep -E rejects (exit 2, e.g. an
# unbalanced paren) errors every grep for the rule into findings=0 — a Summary
# row indistinguishable from a clean corpus. Invalid fragments are skipped with
# a note; the rule keeps running on the fragments that survive.
phrase_fragment_ok() {
  LC_ALL=C grep -E -- "($1)" /dev/null >/dev/null 2>&1
  [[ $? -ne 2 ]]
}
EFFECTIVE_PHRASES=()
for frag in "${MODEL_PHRASES[@]}"; do
  removed=0
  for r in ${PHRASE_REMOVE[@]+"${PHRASE_REMOVE[@]}"}; do
    [[ "$frag" == "$r" ]] && removed=1 && break
  done
  [[ "$removed" -eq 1 ]] && continue
  EFFECTIVE_PHRASES+=("$frag")
done
for frag in ${PHRASE_ADD[@]+"${PHRASE_ADD[@]}"}; do
  [[ -z "${frag//[[:space:]]/}" ]] && continue
  if ! phrase_fragment_ok "$frag"; then
    echo "Note: phrase_add fragment is not a valid ERE, skipped: '$frag' (${PHRASE_ADD_LAYER})" >&2
    continue
  fi
  EFFECTIVE_PHRASES+=("$frag")
done
PHRASES_ERE=""
if [[ "${#EFFECTIVE_PHRASES[@]}" -gt 0 ]]; then
  PHRASES_ERE="($(
    IFS='|'
    printf '%s' "${EFFECTIVE_PHRASES[*]}"
  ))"
fi

# em_dash_allowed_paths is the legacy alias: append it to rule-em-dash's entry
# so both spellings work and neither silently shadows the other.
if [[ "${#EM_DASH_ALLOWED_GLOBS[@]}" -gt 0 ]]; then
  RULE_ALLOWED_GLOBS["rule-em-dash"]="${RULE_ALLOWED_GLOBS["rule-em-dash"]:-} ${EM_DASH_ALLOWED_GLOBS[*]}"
fi

# rule_allowed <slug> <file>: the file declines this one rule via config.
rule_allowed() {
  local slug="$1" file="$2" globs
  globs="${RULE_ALLOWED_GLOBS[$slug]:-}"
  [[ -z "${globs// /}" ]] && return 1
  # read -r -a word-splits WITHOUT pathname expansion. An unquoted $globs here
  # was glob-expanded against the caller's cwd first, so a configured glob
  # reached matches_glob as whatever files it happened to match locally —
  # exemptions silently failed whenever the cwd made the expansion diverge
  # from the literal glob (worst from the repo root, where globs expand).
  local -a glob_arr=()
  read -r -a glob_arr <<<"$globs"
  [[ "${#glob_arr[@]}" -eq 0 ]] && return 1
  matches_glob "$file" "${glob_arr[@]}"
}

rule_disabled() {
  case " $DISABLED_RULES " in
  *" $1 "*) return 0 ;;
  *) return 1 ;;
  esac
}

if [[ "$SHOW_CONFIG" -eq 1 ]]; then
  echo "Config layers (later refines earlier):"
  if [[ "${#CFG_LAYERS[@]}" -eq 0 ]]; then
    echo "  (none; bundled defaults)"
  else
    for layer in "${CFG_LAYERS[@]}"; do echo "  $layer"; done
  fi
  for entry in "${DENSITY_RULES[@]}"; do
    IFS='|' read -r slug key default _ <<<"$entry"
    echo "Effective: threshold_${key}=$(threshold_for "$key" "$default") (rule $slug)"
  done
  echo "Effective: vocab=$VOCAB"
  echo "Effective: model_phrases=${PHRASES_ERE:-"(empty roster; rule inert)"}"
  echo "Effective: excluded_paths=${EXCLUDED_GLOBS[*]:-}"
  echo "Effective: em_dash_allowed_paths=${EM_DASH_ALLOWED_GLOBS[*]:-}"
  for slug in "${!RULE_ALLOWED_GLOBS[@]}"; do
    echo "Effective: rule_allowed_paths[$slug]=${RULE_ALLOWED_GLOBS[$slug]# }"
  done
  echo "Effective: disabled_rules=${DISABLED_RULES:-}"
  exit 0
fi

# --- Target list -----------------------------------------------------------------

resolve_targets TARGETS "$REPO_ROOT" "$PATHS_FILE" "$OFFSET" "$LIMIT" "$LIST_TARGETS" ${TARGETS[@]+"${TARGETS[@]}"} || exit $?

matches_glob() {
  # matches_glob <path> <glob>...: any glob matches the path (or its repo-relative form).
  local path="$1" rel="${1#"$REPO_ROOT"/}" g
  shift
  for g in "$@"; do
    # shellcheck disable=SC2254
    case "$path" in $g) return 0 ;; *) ;; esac
    # shellcheck disable=SC2254
    case "$rel" in $g) return 0 ;; *) ;; esac
  done
  return 1
}

# Excluded paths, the filter the scan loop applies before reading a file.
if [[ "$LIST_TARGETS" -eq 1 ]]; then
  for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
    [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}" && continue
    printf '%s\t%s\n' "${file#"$REPO_ROOT"/}" "$file"
  done
  exit 0
fi

# --- Prose extraction ------------------------------------------------------------
# Emits "lineno<TAB>text" for prose lines; strips fenced code blocks, inline code
# spans, and honors the ignore markers. A marker-exempt (DECLINE) line keeps the
# same "lineno<TAB>text" shape in its own stream, so a caller can ask which rule
# the exempted line would have matched instead of charging every rule for it.
#
# A fence opener may follow a list marker (`- ` or `1. ` plus one to four
# spaces), because CommonMark puts a fence inside a list item; its closer is
# then measured against that item's content column rather than column zero. A
# fence still open at end of file is reported on stderr: that is the correct
# parse, but it reads the rest of the file as code, and scanning nothing is a
# failure that must not be silent.
#
# Markers must be WELL-FORMED comment markers, not prose mentions (the
# audit-noise precedent): the file/start/end forms must stand alone on their
# line, and the trailing line form must not be backtick-quoted. Without this, a
# document that DOCUMENTS the markers exempts itself — found by dogfooding when
# the plugin's own README declined and was silently half-scanned.
#
# Every form takes the same optional `: reason`, because the fix flow tells the
# operator to suppress with one (audit SKILL.md, step 3) and the catalog names
# the marker as the remedy for a recorded false-positive class. When only the
# file form parsed a reason, the two forms an operator reaches for first failed
# differently and silently: a line marker carrying a reason did not match, so
# the finding stayed AND the reason text landed in its own excerpt; a `-start`
# carrying one never opened the block, so the whole block was scanned. The `-end`
# form takes one for the same reason in the dangerous direction — an unmatched
# `-end` leaves `ignored` set and silently swallows the rest of the file.
#
# The backtick guard mirrors the line-marker pattern exactly rather than matching
# any string starting with the marker prefix. A prefix match would let a
# backticked mention of `-start`, `-end`, or `-file` veto a genuine line marker
# sharing that line, rejecting the suppression and quoting the operator's own
# marker back inside the excerpt — the same failure this parser exists to avoid,
# in a new shape. Covered by the mixed-marker case in detect.test.sh.
#
# Batched: one awk process reads every scanned file in turn (a list of
# "k<TAB>path" rows, k the file's index in the target list) and writes each
# file's streams under $SCAN_DIR, one file per stream per target. Each rule then
# runs one grep over a whole stream directory instead of one grep per file, so
# the process count no longer grows with the number of files. Every stream file
# holds exactly the bytes a per-file `printf '%s\n' "$stream"` would have fed
# grep, so the rules see the same input; a stream with no rows holds one empty
# line, as that printf did for an empty variable.
#   P/k    prose rows
#   W/k    P/k with quoted material removed (see the quotation exemption below)
#   TP/k   the text column of P/k (what `cut -f2-` gave), for word and density counts
#   TW/k   the text column of W/k
#   DP/k, DW/k, TDW/k  the same three for marker-exempt rows, written only when
#          the file has some
# stdout carries one status row per file: "k<TAB>marker" when a file-level marker
# declines it, else "k<TAB>scan<TAB>1" or "k<TAB>scan<TAB>0" for whether it has
# marker-exempt rows.
#
# Quotation exemption (strip_row): blockquote lines are dropped and double-quoted
# spans cut, for the prose rows and the marker-exempt rows separately. A quoted
# span may WRAP: markdown prose soft-wraps at a column, so the closing quote of a
# span often sits on the next line. The stripper carries an open-span state
# across rows: a row with an unmatched opening quote is cut from that quote to
# its end and the next row is cut from its start through the closing quote.
# Without the carry, the quote pairing on the continuation line is off by one and
# the exemption inverts, keeping the quoted text and stripping the prose between
# quotes. The state resets per file, at a paragraph boundary (a blank line), and
# at the start of a new block element (heading, list item, table row), so a stray
# unmatched quote can blank out at most the rest of its own paragraph.
#
# Fences per CommonMark: openers may be indented up to three spaces past their
# container (counted by hand, because mawk has no {n,m} intervals), and a fence
# closes only on its OWN character, so ~~~ inside a backtick fence stays content.
# No apostrophes anywhere in this program: it is single-quoted.
# shellcheck disable=SC2016 # awk program text, not shell expansions
EXTRACT_AWK='
  function fence_char(s) {
    if (substr(s, 1, 3) == "```") return "`"
    if (substr(s, 1, 3) == "~~~") return "~"
    return ""
  }
  # An ordered marker carries at most nine digits (CommonMark "Lists"), so a
  # longer run is a number in prose, not a list. Without the cap a line such
  # as `1234567890. ` followed by a fence opened one, and every following
  # line was read as code until a bare closer or end of file.
  function marker_len(s,   n) {
    if (s ~ /^[-*+]/) return 1
    n = 0
    while (n < 9 && substr(s, n + 1, 1) ~ /^[0-9]$/) n++
    if (n > 0 && (substr(s, n + 1, 1) == "." || substr(s, n + 1, 1) == ")")) return n + 1
    return 0
  }
  # Inline code spans go, and so does a line ignore marker: the marker and its
  # reason are control syntax the author did not write as prose, so a rule
  # must not be charged a decline for a word that appears only there.
  function stripped(s,   t) {
    t = s
    gsub(/`[^`]*`/, "", t)
    gsub(/<!-- ai-slop-ignore(-file|-start|-end)?(:[^>]*)? -->/, "", t)
    return t
  }
  # One output row. NUL bytes are dropped from it, as capturing the per-file
  # extraction into a shell variable dropped them; left in, they would make
  # grep read the stream file as binary and report no matching lines.
  function out_row(n, text,   s) {
    s = sprintf("%d\t%s", n, text)
    if (gsub(/\000/, "", s) > 0) had_nul = 1
    return s
  }
  # One source line ($0, line number ln). Returns 1 at a file-level marker,
  # which declines the whole file wherever it sits, even inside a fence.
  function line_step(   ind, rest, fc, fi, ml, sp) {
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-file(:[^>]*)? -->[[:space:]]*$/) {
      stopped = 1
      return 1
    }
    ind = 0
    while (substr($0, ind + 1, 1) == " ") ind++
    rest = substr($0, ind + 1)
    # A fence opened inside a list item ends with its CONTAINER, not only at a
    # closer. A non-blank line indented less than the content column of that
    # item ends the item, and lazy continuation reaches a paragraph but never
    # a fenced block, so such a line belongs to the document. Clear the fence
    # and fall through, so the line is judged on its own: it may be prose, and
    # it may itself be an opener. A blank line does NOT end an item, which is
    # why this tests rest. A document-level fence keeps fence_ind 0, so the
    # comparison is never true for one and no top-level case moves.
    if (fence != "" && fence_ind > 0 && rest != "" && ind < fence_ind) fence = ""
    fc = fence_char(rest)
    fi = 0
    if (fc == "" && ind <= 3) {
      ml = marker_len(rest)
      if (ml > 0) {
        sp = 0
        while (substr(rest, ml + sp + 1, 1) == " ") sp++
        if (sp >= 1 && sp <= 4) {
          fc = fence_char(substr(rest, ml + sp + 1))
          if (fc != "") fi = ind + ml + sp
        }
      }
    }
    if (fence == "") {
      if (fc != "" && ind <= 3) { fence = fc; fence_ind = fi; fence_line = ln; return 0 }
    } else {
      if (fence_char(rest) == fence && ind <= fence_ind + 3) fence = ""
      return 0
    }
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-start(:[^>]*)? -->[[:space:]]*$/) { ignored = 1; return 0 }
    if ($0 ~ /^[[:space:]]*<!-- ai-slop-ignore-end(:[^>]*)? -->[[:space:]]*$/) { ignored = 0; return 0 }
    if (ignored) { D[++nd] = out_row(ln, stripped($0)); return 0 }
    if ($0 ~ /<!-- ai-slop-ignore(:[^>]*)? -->/ && $0 !~ /`<!-- ai-slop-ignore(:[^>]*)? -->/) {
      D[++nd] = out_row(ln, stripped($0))
      return 0
    }
    P[++np] = out_row(ln, stripped($0))
    return 0
  }
  # Quotation exemption for one row of stream st; returns 1 and sets SQ when
  # the row survives.
  function strip_row(st, row,   tab, lineno, text, q, before, after) {
    tab = index(row, "\t")
    if (tab == 0) return 0
    lineno = substr(row, 1, tab - 1)
    text = substr(row, tab + 1)
    if (text ~ /^[ ]?[ ]?[ ]?>/) return 0
    if (text ~ /^[[:space:]]*$/ || text ~ /^[[:space:]]*(#|[-*+] |[0-9]+\. |\|)/) OPEN[st] = 0
    if (OPEN[st]) {
      q = index(text, "\"")
      if (q == 0) { SQ = lineno "\t"; return 1 }
      text = substr(text, q + 1)
      OPEN[st] = 0
    }
    gsub(/"[^"]*"/, "", text)
    q = index(text, "\"")
    if (q > 0) {
      # A lone quote opens a span only when it sits where an opening quote
      # sits: after the line start, whitespace, or an opening bracket, and
      # directly before a non-space character. An inch or second mark
      # (6", 30") or a stray closing quote fails that test, so it is
      # dropped and the prose on both sides stays scanned instead of
      # blanking the rest of the paragraph.
      before = (q > 1) ? substr(text, q - 1, 1) : " "
      after = substr(text, q + 1, 1)
      if (before ~ /[[:space:](\[{]/ && after ~ /[^[:space:]]/) {
        text = substr(text, 1, q - 1)
        OPEN[st] = 1
      } else {
        text = substr(text, 1, q - 1) substr(text, q + 1)
      }
    }
    SQ = lineno "\t" text
    return 1
  }
  function text_col(row,   tab) {
    tab = index(row, "\t")
    return tab ? substr(row, tab + 1) : row
  }
  # put(stream, k, rows, n, text_only): write one stream file.
  function put(stream, k, rows, n, text_only,   path, i) {
    path = dir "/" stream "/" k
    if (n == 0) print "" > path
    for (i = 1; i <= n; i++) print (text_only ? text_col(rows[i]) : rows[i]) > path
    close(path)
  }
  # quoted_free(src, n, st, dst): strip src[1..n] into dst; returns the row count.
  function quoted_free(src, n, st, dst,   i, m) {
    m = 0
    OPEN[st] = 0
    for (i = 1; i <= n; i++) if (strip_row(st, src[i])) dst[++m] = SQ
    return m
  }
  function scan_file(k, f,   r, nw, ndw) {
    fence = ""; fence_ind = 0; fence_line = 0; ignored = 0; stopped = 0
    ln = 0; np = 0; nd = 0; had_nul = 0
    split("", P); split("", D); split("", W); split("", DW)
    while ((r = (getline < f)) > 0) {
      ln++
      if (line_step()) break
    }
    if (r < 0) printf "detect.sh: %s: cannot be read; scanned as empty\n", f > "/dev/stderr"
    close(f)
    if (fence != "" && !stopped) {
      printf "detect.sh: %s: code fence opened at line %d is never closed; the rest of the file was read as code\n", f, fence_line > "/dev/stderr"
    }
    if (stopped) { print k "\tmarker"; return }
    if (had_nul) printf "detect.sh: %s: NUL bytes dropped from the scanned text\n", f > "/dev/stderr"
    nw = quoted_free(P, np, "p", W)
    put("P", k, P, np, 0); put("TP", k, P, np, 1)
    put("W", k, W, nw, 0); put("TW", k, W, nw, 1)
    if (nd > 0) {
      ndw = quoted_free(D, nd, "d", DW)
      put("DP", k, D, nd, 0)
      put("DW", k, DW, ndw, 0); put("TDW", k, DW, ndw, 1)
    }
    print k "\tscan\t" (nd > 0 ? 1 : 0)
  }
  {
    tab = index($0, "\t")
    scan_file(substr($0, 1, tab - 1), substr($0, tab + 1))
  }
'

# Finding rows from `grep -r` over a stream directory ("<stream>/k:lineno<TAB>text")
# become "k<TAB>lineno<TAB>excerpt". The lineno/text split reproduces
# `IFS=$'\t' read -r lineno text` (runs of tabs separate, edge tabs trimmed),
# and a row with no line number is dropped.
#
# The excerpt is truncated to at most 80 BYTES without splitting a multi-byte
# UTF-8 sequence: under the forced C locale substr counts bytes, so an em dash /
# curly quote / emoji straddling the boundary (exactly this tool's own targets)
# would be cut mid-character and emit invalid UTF-8 into the finding. It scans
# back over at most three trailing continuation bytes; if their lead byte
# declares more bytes than survived the cut, the whole partial sequence drops.
# A `|` in the excerpt becomes `/`.
# shellcheck disable=SC2016 # awk program text, not shell expansions
FINDING_AWK='
  BEGIN { for (j = 0; j < 256; j++) ORD[sprintf("%c", j)] = j }
  function excerpt(s,   n, i, b, need) {
    s = substr(s, 1, 80)
    n = length(s)
    for (i = 0; i < 4 && n - i >= 1; i++) {
      b = ORD[substr(s, n - i, 1)]
      if (b < 128) break
      if (b >= 192) {
        need = (b >= 240) ? 4 : (b >= 224) ? 3 : 2
        if (i + 1 < need) s = substr(s, 1, n - i - 1)
        break
      }
    }
    gsub(/\|/, "/", s)
    return s
  }
  {
    c = index($0, ":")
    path = substr($0, 1, c - 1)
    k = substr(path, index(path, "/") + 1)
    row = substr($0, c + 1)
    sub(/^\t+/, "", row)
    t = index(row, "\t")
    if (t == 0) { lineno = row; text = "" }
    else {
      lineno = substr(row, 1, t - 1)
      text = substr(row, t + 1)
      sub(/^\t+/, "", text)
      sub(/\t+$/, "", text)
    }
    if (lineno == "") next
    print k "\t" lineno "\t" excerpt(text)
  }
'

# --- Scan ------------------------------------------------------------------------

ALL_RULES=()
for entry in "${PATTERN_RULES[@]}" "${DENSITY_RULES[@]}"; do ALL_RULES+=("${entry%%|*}"); done

# Declined counts are kept per rule AND per cause, because one total tells a
# reader nothing about what was exempted: `marker` is the in-file ignore
# markers, counting the exempted lines, or occurrences, THAT RULE would have matched,
# plus one whole-file charge to every rule when a file-level marker declines
# the file; `quote` is the quotation exemption (blockquote lines and
# double-quoted spans a wording rule would have matched); and `config` is an
# excluded_paths glob or a rule_allowed_paths entry. Fenced code is not a
# decline at all: it is never prose, so nothing is counted for it.
declare -A FINDINGS DECLINED DECL_MARKER DECL_QUOTE DECL_CONFIG
for slug in "${ALL_RULES[@]}"; do
  FINDINGS[$slug]=0
  DECLINED[$slug]=0
  DECL_MARKER[$slug]=0
  DECL_QUOTE[$slug]=0
  DECL_CONFIG[$slug]=0
done

# decline_rule <slug> <n> <cause>: cause is marker | quote | config.
decline_rule() {
  local slug="$1" n="$2" cause="$3"
  DECLINED[$slug]=$((DECLINED[$slug] + n))
  case "$cause" in
  marker) DECL_MARKER[$slug]=$((DECL_MARKER[$slug] + n)) ;;
  quote) DECL_QUOTE[$slug]=$((DECL_QUOTE[$slug] + n)) ;;
  config) DECL_CONFIG[$slug]=$((DECL_CONFIG[$slug] + n)) ;;
  *)
    echo "detect.sh: internal error: unknown decline cause '$cause'" >&2
    exit 2
    ;;
  esac
}

# decline_all_rules <n> <cause>
decline_all_rules() {
  local n="$1" cause="$2" slug
  for slug in "${ALL_RULES[@]}"; do
    decline_rule "$slug" "$n" "$cause"
  done
}

TOTAL_FILES=0
DECLINED_FILES=0

# Stdout is assembled per target index and printed in target order at the end,
# because each rule now runs across every file at once: OUT[k] collects file
# k's rows in the order the per-file scan emitted them (pattern rules in table
# order, then density rules, each in line order).
declare -A OUT=()
emit_finding() {
  # emit_finding <k> <slug> <lineno> <fired> <excerpt>
  local row
  printf -v row 'Finding: rule=ai-slop/audit/%s file=%s line=%s fired=%s excerpt=%s\n' \
    "$2" "${REL_OF[$1]}" "$3" "$4" "$5"
  OUT[$1]+="$row"
  FINDINGS[$2]=$((FINDINGS[$2] + 1))
}

SCAN_DIR="$(mktemp -d "${TMPDIR:-/tmp}/ai-slop-detect.XXXXXX")" || {
  echo "detect.sh: cannot create a temporary directory; nothing was scanned" >&2
  exit 2
}
trap 'rm -rf "$SCAN_DIR"' EXIT
mkdir -p "$SCAN_DIR/P" "$SCAN_DIR/W" "$SCAN_DIR/TP" "$SCAN_DIR/TW" \
  "$SCAN_DIR/DP" "$SCAN_DIR/DW" "$SCAN_DIR/TDW" || exit 2

# scan_grep <stream> <grep args...>: one grep over every file of one stream.
scan_grep() {
  local stream="$1"
  shift
  (cd "$SCAN_DIR" && LC_ALL=C grep -r "$@" "$stream")
}

# file_counts c|o: reads `grep -r` output and prints "k<TAB>n" for each file with
# n > 0. Mode c reads `-c` rows ("<stream>/k:n"); mode o counts one row per
# `-o` match, as `| wc -l` did.
file_counts() {
  awk -v mode="$1" '
    {
      c = index($0, ":")
      path = substr($0, 1, c - 1)
      k = substr(path, index(path, "/") + 1)
      if (mode == "c") { if (substr($0, c + 1) + 0 > 0) print k "\t" substr($0, c + 1) }
      else if (!(k in n)) { n[k] = 1; order[++m] = k } else n[k]++
    }
    END { if (mode == "o") for (i = 1; i <= m; i++) print order[i] "\t" n[order[i]] }
  '
}

FILE_OF=()
REL_OF=()
STATE_OF=()
SCANNED=()
declare -A HAS_DECL=()
k=0
for file in ${TARGETS[@]+"${TARGETS[@]}"}; do
  k=$((k + 1))
  FILE_OF[k]="$file"
  REL_OF[k]="${file#"$REPO_ROOT"/}"
  if [[ "${#EXCLUDED_GLOBS[@]}" -gt 0 ]] && matches_glob "$file" "${EXCLUDED_GLOBS[@]}"; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1 config
    STATE_OF[k]=excluded
    continue
  fi
  TOTAL_FILES=$((TOTAL_FILES + 1))
  printf '%s\t%s\n' "$k" "$file"
done >"$SCAN_DIR/list"
N_TARGETS=$k

# Every file now rides on this one awk run, so its failure is not a per-file
# blank: an extraction that did not complete would report a clean tree. It stops
# the scan instead, and a run that returned fewer status rows than files fails
# the same way.
if ! LC_ALL=C awk -v dir="$SCAN_DIR" "$EXTRACT_AWK" "$SCAN_DIR/list" >"$SCAN_DIR/status"; then
  echo "detect.sh: prose extraction failed; nothing was scanned" >&2
  exit 2
fi
if [[ "$(wc -l <"$SCAN_DIR/status" | tr -d ' ')" -ne "$TOTAL_FILES" ]]; then
  echo "detect.sh: prose extraction returned fewer files than it was given; nothing was scanned" >&2
  exit 2
fi

# A file-level marker declines the WHOLE file wherever it sits: extraction stops
# at the marker and the file contributes no stream.
while IFS=$'\t' read -r k state has_decl; do
  STATE_OF[k]="$state"
  if [[ "$state" == marker ]]; then
    DECLINED_FILES=$((DECLINED_FILES + 1))
    decline_all_rules 1 marker
    continue
  fi
  SCANNED+=("$k")
  [[ "$has_decl" == 1 ]] && HAS_DECL[$k]=1
done <"$SCAN_DIR/status"

# Rule exemptions per file for one rule: ALLOWED[k] is set, and the config
# decline charged, for each scanned file a rule_allowed_paths glob exempts.
declare -A ALLOWED=()
mark_allowed() {
  local slug="$1" charge="$2" kk
  ALLOWED=()
  [[ -z "${RULE_ALLOWED_GLOBS[$slug]:-}" ]] && return 0
  for kk in ${SCANNED[@]+"${SCANNED[@]}"}; do
    if rule_allowed "$slug" "${FILE_OF[kk]}"; then
      ALLOWED[$kk]=1
      [[ "$charge" == 1 ]] && decline_rule "$slug" 1 config
    fi
  done
}

# Marker-exempt rows are kept in a stream shaped exactly like the prose stream
# (`lineno<TAB>text`), so each rule can be asked what IT would have matched
# instead of every rule being charged the raw exempted-line count. The shape
# matters beyond tidiness: rule-emoji-formatting anchors its expression on that
# field separator, so a bare-text stream could never match it.
#
# Quotation exemption: wording rules never scan quoted material. Blockquote
# lines are dropped and double-quoted spans stripped; every quote-exempt
# candidate a wording rule WOULD have matched is counted as declined for that
# rule below, never silently dropped. Typography rules keep the full stream.
#
# The same split applies to the marker accounting: a wording rule is charged
# against the quote-free marker stream (DW), a typography rule against the full
# one (DP). A marker-exempt line a wording rule would only have matched inside
# quoted material is charged to no rule at all. It was exempt twice over, and the
# marker count is the count of lines the rule would actually have raised a
# finding on.
declare -A FULL_HITS=() KEPT_HITS=()
for entry in "${PATTERN_RULES[@]}"; do
  IFS='|' read -r slug label ci word class ere <<<"$entry"
  # Runtime-built roster, like __VOCAB__ in the density loop. The empty-roster
  # guard runs before decline accounting: with every phrase removed there is
  # nothing to exempt, and "()" would match every line.
  if [[ "$ere" == "__PHRASES__" ]]; then
    [[ -z "$PHRASES_ERE" ]] && continue
    ere="$PHRASES_ERE"
  fi
  rule_disabled "$slug" && continue
  [[ "${#SCANNED[@]}" -eq 0 ]] && continue
  mark_allowed "$slug" 1
  flags=(-E)
  [[ "$ci" == "1" ]] && flags+=(-i)
  [[ "$word" == "1" ]] && flags+=(-w)
  stream=P
  declined_stream=DP
  if [[ "$class" == "wording" ]]; then
    stream=W
    declined_stream=DW
    FULL_HITS=()
    KEPT_HITS=()
    while IFS=$'\t' read -r kk n; do FULL_HITS[$kk]="$n"; done < <(scan_grep P -c "${flags[@]}" -- "$ere" | file_counts c)
    while IFS=$'\t' read -r kk n; do KEPT_HITS[$kk]="$n"; done < <(scan_grep W -c "${flags[@]}" -- "$ere" | file_counts c)
    for kk in "${!FULL_HITS[@]}"; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      [[ "${FULL_HITS[$kk]}" -gt "${KEPT_HITS[$kk]:-0}" ]] &&
        decline_rule "$slug" $((FULL_HITS[$kk] - ${KEPT_HITS[$kk]:-0})) quote
    done
  fi
  if [[ "${#HAS_DECL[@]}" -gt 0 ]]; then
    while IFS=$'\t' read -r kk n; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      decline_rule "$slug" "$n" marker
    done < <(scan_grep "$declined_stream" -c "${flags[@]}" -- "$ere" | file_counts c)
  fi
  # One finding per matching prose line.
  while IFS= read -r row; do
    kk="${row%%$'\t'*}"
    row="${row#*$'\t'}"
    [[ -n "${ALLOWED[$kk]:-}" ]] && continue
    emit_finding "$kk" "$slug" "${row%%$'\t'*}" "$label" "${row#*$'\t'}"
  done < <(scan_grep "$stream" "${flags[@]}" -- "$ere" | LC_ALL=C awk "$FINDING_AWK")
done

# Density rules: one finding per file when density reaches the threshold. All
# density rules are wording-class, so both the hit count and the word count come
# from the quote-exempt stream; quote-exempt hits are declined. The threshold is
# read once per rule: it does not depend on the file.
#
# Marker declines for the density rules are counted OUTSIDE the word-count
# guard. A file whose every prose line sits inside an ignore block has no
# scannable words left, so the guarded pass never reaches it, and a rule would
# report zero declines for material the markers demonstrably suppressed.
declare -A WORDS=()
if [[ "${#SCANNED[@]}" -gt 0 ]]; then
  while IFS=$'\t' read -r kk n; do WORDS[$kk]="$n"; done < <(
    cd "$SCAN_DIR" && find TW -type f -exec wc -w {} + |
      awk '$2 ~ /^TW\// { print substr($2, 4) "\t" $1 }'
  )
fi
for entry in "${DENSITY_RULES[@]}"; do
  IFS='|' read -r slug key default ere <<<"$entry"
  rule_disabled "$slug" && continue
  [[ "${#SCANNED[@]}" -eq 0 ]] && continue
  [[ "$ere" == "__VOCAB__" ]] && ere="$VOCAB_ERE"
  mark_allowed "$slug" 0
  if [[ "${#HAS_DECL[@]}" -gt 0 ]]; then
    while IFS=$'\t' read -r kk n; do
      [[ -n "${ALLOWED[$kk]:-}" ]] && continue
      decline_rule "$slug" "$n" marker
    done < <(scan_grep TDW -E -o -i -w -- "$ere" | file_counts o)
  fi
  threshold="$(threshold_for "$key" "$default")"
  FULL_HITS=()
  KEPT_HITS=()
  while IFS=$'\t' read -r kk n; do KEPT_HITS[$kk]="$n"; done < <(scan_grep TW -E -o -i -w -- "$ere" | file_counts o)
  while IFS=$'\t' read -r kk n; do FULL_HITS[$kk]="$n"; done < <(scan_grep TP -E -o -i -w -- "$ere" | file_counts o)
  candidates=""
  for kk in "${SCANNED[@]}"; do
    words="${WORDS[$kk]:-0}"
    [[ "$words" -gt 0 ]] || continue
    if [[ -n "${ALLOWED[$kk]:-}" ]]; then
      decline_rule "$slug" 1 config
      continue
    fi
    hits="${KEPT_HITS[$kk]:-0}"
    full_hits="${FULL_HITS[$kk]:-0}"
    [[ "$full_hits" -gt "$hits" ]] && decline_rule "$slug" $((full_hits - hits)) quote
    [[ "$hits" -lt "$DENSITY_MIN_HITS" ]] && continue
    candidates+="$kk"$'\t'"$hits"$'\t'"$words"$'\n'
  done
  [[ -z "$candidates" ]] && continue
  # Density and the threshold test as the per-file awk calls computed them: the
  # density string is split back into a field so the comparison sees two
  # numeric strings, exactly as it did with two -v values. The threshold is
  # config text, so it reaches awk only as -v, never as a row field.
  while IFS=$'\t' read -r kk hits words density over; do
    [[ "$kk" =~ ^[0-9]+$ && "$over" == 1 ]] || continue
    first_line="$(LC_ALL=C grep -E -i -m1 -- "$ere" "$SCAN_DIR/W/$kk")"
    first_line="${first_line%%$'\t'*}"
    emit_finding "$kk" "$slug" "${first_line:-1}" \
      "density $density/1000 words, threshold $threshold ($hits hits in $words words)" \
      "density rule"
  done < <(printf '%s' "$candidates" | awk -F '\t' -v t="$threshold" '{
    split(sprintf("%.1f", ($2 * 1000) / $3), d, "\n")
    print $1 "\t" $2 "\t" $3 "\t" d[1] "\t" ((d[1] >= t) ? 1 : 0)
  }')
done

for ((k = 1; k <= N_TARGETS; k++)); do
  case "${STATE_OF[k]:-}" in
  excluded) echo "Declined: file=${REL_OF[k]} cause=excluded-glob" ;;
  marker) echo "Declined: file=${REL_OF[k]} cause=file-marker" ;;
  *) printf '%s' "${OUT[$k]:-}" ;;
  esac
done

TOTAL_FINDINGS=0
for slug in "${ALL_RULES[@]}"; do
  disabled=0
  rule_disabled "$slug" && disabled=1
  echo "Summary rule=ai-slop/audit/$slug findings=${FINDINGS[$slug]} declined=${DECLINED[$slug]} declined_marker=${DECL_MARKER[$slug]} declined_quote=${DECL_QUOTE[$slug]} declined_config=${DECL_CONFIG[$slug]} disabled=$disabled"
  TOTAL_FINDINGS=$((TOTAL_FINDINGS + FINDINGS[$slug]))
done
echo "Summary total: $TOTAL_FINDINGS findings across $TOTAL_FILES files scanned ($DECLINED_FILES files declined)"
exit 0

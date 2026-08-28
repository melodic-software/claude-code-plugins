#!/usr/bin/env bash
# Compose a conforming findings file from the audit's report sidecar.
#
#   emit-findings.sh --report <sidecar.json> --out <path> [--branch <b>]
#
# The FINDINGS HOME is never resolved here. The caller — the audit skill's
# context/persist-findings.md — resolves it through the topic-docs rung order
# and runs the detector-findings fetch-and-refuse gate, then hands the resolved
# path in as --out. That split follows the ai-slop precedent exactly, and it is
# required rather than stylistic: rung resolution reads prose (a CLAUDE.md
# declaration, a configured memory_dir) and is therefore model work under Brief
# constraint C1. A bash implementation would either violate C1 or silently
# collapse to the documented default, which is the one case that fails without
# reporting anything. What is left here is reasoning-free composition: cell
# escaping, rule-id-first Finding cells, and tier lookup.
#
# The RELAY BOUNDARY is enforced here, not upstream. Only fingerprint-confirmed
# copies and the two deterministic stamp rules may reach a findings file;
# judgment verdicts (source-fetched-similar, llm-suspected, not-found) stay in
# the human report. They are counted in `## Surfaces` rather than dropped, and
# their tier names are deliberately NOT printed — the findings file is the
# apply relay's input, and a tier name in it invites a consumer to act on a
# verdict this producer withheld on purpose.
#
# The per-rule Tier/Action cells MIRROR the severity crosswalk in
# docs/specs/provenance-type-inventory.md, which lands in
# docs/conventions/detector-findings/README.md at registration (Phase 7). That
# table is the source of truth — a tier change lands there first and is copied
# here, never the reverse.
#
# No `tier:` frontmatter is emitted: nothing here computes a run-size value,
# and the shape contract makes it required of review:fanout's own writer only.
#
# Exit: 0 on success (with findings or none — coverage is the payload), 2 on
# usage error, 3 when the report is not usable audit output (it does not parse, it
# has no findings key, its findings key is not a list, or a `not-found` finding
# names no searched surfaces; refusing beats composing from garbage, and each
# refusal names its own cause), 4 when jq is absent, 5 when the destination could
# not be written. A single malformed RECORD is none of these: it lands in
# `## Unparsed` rather than costing the well-formed findings beside it.
set -uo pipefail

REPORT=""
OUT=""
BRANCH=""

usage() {
  cat <<'EOF'
emit-findings.sh — compose a findings file from the audit's report sidecar.

Usage:
  emit-findings.sh --report <sidecar.json> --out <path> [--branch <b>]

--report  the audit's JSON report sidecar: {findings: [...], counts: {...}}
--out     the CONVENTION-RESOLVED destination; if it exists, a -2/-3 suffix is
          appended (non-overwrite naming)
--branch  defaults to the current git branch
EOF
}

require_opt_value() {
  local opt="$1"
  if [[ $# -lt 2 || -z "${2:-}" || "$2" == -* ]]; then
    echo "emit-findings.sh: $opt requires a value" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
  --report)
    require_opt_value "$@"
    REPORT="$2"
    shift 2
    ;;
  --out)
    require_opt_value "$@"
    OUT="$2"
    shift 2
    ;;
  --branch)
    require_opt_value "$@"
    BRANCH="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "emit-findings.sh: unknown argument: $1" >&2
    usage >&2
    exit 2
    ;;
  esac
done

[[ -n "$REPORT" && -n "$OUT" ]] || {
  echo "emit-findings.sh: --report and --out are both required" >&2
  usage >&2
  exit 2
}
[[ -f "$REPORT" ]] || {
  echo "emit-findings.sh: --report file not found: $REPORT" >&2
  exit 2
}
command -v jq >/dev/null 2>&1 || {
  echo "emit-findings.sh: jq is required to read the report sidecar" >&2
  exit 4
}

# Parse first, and say so. `has("findings")` fails on unparsable input too, so every
# truncated or non-JSON sidecar used to be refused for having no findings key — a
# cause the input does not have, and one that sends a reader looking for a key in a
# file that has no keys at all.
if ! jq -e 'type == "object"' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT is not a JSON object; not audit output" >&2
  exit 3
fi

if ! jq -e 'has("findings")' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has no findings key; not audit output" >&2
  exit 3
fi

# `findings` present but not a list. Checked HERE and named for what it is, because
# the next gate iterates it: a `"findings": "none"` sidecar failed there instead and
# was refused under the not-found message, reporting a cause the input does not have.
if ! jq -e '(.findings | type) == "array"' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has a findings key that is not a list; not audit output" >&2
  exit 3
fi

# --- The declared-tier reader ------------------------------------------------------
#
# ONE reader, THREE callers: the searched-surfaces gate immediately below, the
# relay-boundary withhold predicate, and the fingerprint-confirmed eligibility test
# beside it. A second, laxer notion of "the tier" is how the gate came to miss
# `{"Tier": "not-found"}` and `{"tier": ["not-found"]}` — shapes the boundary itself
# recognizes — so such a sidecar skipped the refusal and was quietly counted as
# withheld instead. It is also how `{"Tier": "fingerprint-confirmed"}` came to be
# read as a declaration when withholding and as no declaration at all when relaying:
# the record was dropped, and the count called it a copy declaring no
# fingerprint-confirmed tier, which its own reader disagrees with. Every caller
# asking the same question of the same reader is what removes the room for both.
#
# WHERE the tier is read is an EXPLICIT KEY ALLOWLIST: the top-level `tier`, and the
# whole of a top-level `verdict`. Both are the record DECLARING its tier, and nothing
# else is. Keys are matched case-folded so casing is not a way around the boundary,
# but only at those two positions, so `{"xref": {"TIER": "prior: not-found"}}` stays
# the cross-reference it reads as.
#
# A `verdict` is taken WHOLE rather than as `verdict.tier`, because a key named
# `verdict` is already the declaration: `{"verdict": "not-found"}`,
# `{"verdict": ["not-found"]}` and `{"verdict": {"result": {"tier": "llm-suspected"}}}`
# each say the same thing `{"verdict": {"tier": "not-found"}}` does, and reading only
# the `tier` child let all three past — into a relay row on a stamp rule, or verbatim
# into `## Unparsed` with no rule id.
#
# The narrowness is the point. Reading `tier` at any depth cannot tell the declared
# tier of a record from an unrelated nested one, and this sidecar is model-authored
# against no schema, with `tier` already overloaded (verdict tier, and crosswalk
# severity). So a fingerprint-confirmed copy carrying
# `"review": {"tier": "one agent argued llm-suspected and was vetoed"}` was withheld:
# it reached neither the relay nor `## Unparsed`. A leak is visible in the output; a
# drop is not, and every sloppiness about WHERE the tier lives is a drop.
#
# WHICH VALUES NAME A TIER: the WRAPPER is read generously, the NAME exactly. Every
# string anywhere inside the declared value is a candidate, trimmed and case-folded,
# and it names a tier only when it EQUALS one. That keeps `"  not-found  "`,
# `["not-found"]`, `{"name": "llm-suspected"}` and `"LLM-Suspected"` the verdicts
# they say they are, while a future `not-found-v2` is an unknown tier rather than the
# verdict it happens to start with. Substring matching erased such a record entirely,
# printing no `## Unparsed` entry for it; an unknown tier now takes the ordinary path
# for its rule id — the appendix when nothing maps it, the not-relay-eligible count
# when a rule does map it and the declaration does not authorize the relay.
#
# Free text in a tier field names no tier under that rule, which is the same answer
# this producer already gives a verdict name spelled in a `note`. It has to be: a
# `verdict.tier` reading "the llm-suspected nomination was overruled" is a review
# note, and withholding the fingerprint-confirmed copy carrying it is the drop above
# wearing an allowlisted key.
#
# Scoped to THESE FOUR NAMES on purpose — the three withheld verdicts, and the one
# tier a copy finding may be relayed on. A tier naming none of them is a tier this
# producer neither withheld nor can relay.
# shellcheck disable=SC2016  # `$name` is a jq parameter, not a shell expansion.
TIER_DEFS='
def tier_slot:
  if type == "object" then
    to_entries[] | select(.key | ascii_downcase == "tier") | .value
  else empty end;
def verdict_slot:
  if type == "object" then
    to_entries[] | select(.key | ascii_downcase == "verdict") | .value
  else empty end;
# The top-level `tier` IS the declaration whenever it DECLARES one. A `verdict`
# is the judges output, and the tier is set by fixed rule from the evidence rather
# than from a judge — different fields by design — so a record declaring
# `fingerprint-confirmed` and carrying `"verdict": {"prior": "llm-suspected"}` has
# declared a confirmed copy, and reading the verdict beside it is the over-capture
# drop one container in.
#
# A record whose `tier` NAMES NO TIER falls back to its `verdict`, which is then the
# only tier it has: the `tier` child when it has one, and otherwise the whole value,
# because `{"verdict": "not-found"}`, `{"verdict": ["not-found"]}` and
# `{"verdict": {"result": {"tier": "llm-suspected"}}}` each say what
# `{"verdict": {"tier": "not-found"}}` says. Reading only the `tier` child let all
# three past the boundary — onto a relay row on a stamp rule, and verbatim into
# `## Unparsed` with no rule id.
#
# NARROWING TURNS ON A TIER NAMED, NEVER ON A `tier` KEY PRESENT — at BOTH steps, and
# by the same rule, because the two steps are the same question asked twice. Keying
# either off the key lets one unusable value disarm the whole boundary:
# `{"tier": null, "verdict": "not-found"}` never consulted the verdict, and
# `{"verdict": {"tier": "pending", "result": "not-found"}}` never looked past the
# `tier` child. Each printed its verdict name and payload verbatim into `## Unparsed`
# and skipped the searched-surfaces gate on the way.
#
# A tier that RENDERS as a verdict name IS a verdict name, so the two invisibilities
# are handled differently and each by the property that DEFINES it.
#
# Characters that render as nothing are stripped EVERYWHERE, by
# `Default_Ignorable_Code_Point` — the Unicode property for exactly that — plus the
# rest of `Cf`. Anything narrower is a list of the ones someone thought of: an
# enumeration of two zero-width characters left six others through; trimming the class
# at the ends only left an interior `"not-‍found"`; and stripping `Cf` alone left the
# variation selectors and the combining grapheme joiner, which are `Mn`. Each spelling
# read as `not-found` to whoever opens the findings file while comparing unequal.
#
# Combining marks at large are NOT stripped, because they render: `not-fóund` is a
# different name, and this reader should say so rather than guess at a verdict.
#
# Separators do render too, so they are trimmed at the ends only: `"not found"` is a
# different string, not this verdict.
# Hyphen-like code points are folded to ASCII by the DASH class, because every one of
# these four names is hyphenated and `"not‐found"` spelled with U+2010 renders exactly
# like the verdict it is. Homoglyphs beyond the dash class are a STATED LIMIT, not a
# closed one: such a tier is an unknown tier, and the record takes the `## Unparsed`
# path, which review:fanout surfaces for manual handling and never auto-classifies.
def norm:
  ascii_downcase
  | gsub("[\\p{Default_Ignorable_Code_Point}\\p{Cf}]"; "")
  | gsub("[\\p{Pd}\\x{2212}]"; "-")
  | sub("^[[:space:][:cntrl:]\\p{Z}]+"; "")
  | sub("[[:space:][:cntrl:]\\p{Z}]+$"; "");
# KEYS are candidates as well as values: `{"tier": {"not-found": true}}` says what
# `{"tier": "not-found"}` says, and reading values alone printed it verbatim into
# `## Unparsed`. "Every string anywhere inside" has to mean every string.
def names_in:
  [ .[] | .. | (strings, (objects | keys[])) | norm ];
# `source-not-identified` is the spelling SKILL.md publishes for the neutral outcome
# this file elsewhere calls `not-found`. Both are recognized, because the sidecar is
# written against that description and a name this reader does not know is a verdict
# that walks into the relay. Recognizing one name too many can only withhold a
# record; recognizing one too few relays a judgment verdict.
def is_verdict_name:
  . == "source-fetched-similar" or . == "llm-suspected"
  or . == "not-found" or . == "source-not-identified";
def is_neutral_name:
  . == "not-found" or . == "source-not-identified";
def is_tier_name:
  is_verdict_name or . == "fingerprint-confirmed";
# Prefer the narrower reading of a container ONLY when it names a tier; otherwise the
# whole container is the declaration. This is the single rule both steps apply.
def narrow($inner; $whole):
  if ($inner | names_in | any(is_tier_name)) then $inner else $whole end;
def verdict_declared:
  verdict_slot | . as $v | narrow([ tier_slot ]; [ $v ]);
def declared_tiers:
  . as $rec | narrow([ tier_slot ]; [ $rec | verdict_declared ] | add // []);
def declared_names:
  declared_tiers | names_in;
def declares($name):
  declared_names | index($name) != null;
def withheld_verdict:
  declared_names | any(is_verdict_name);
def declares_not_found:
  declared_names | any(is_neutral_name);
def declares_confirmed:
  declares("fingerprint-confirmed");
# A stamp rule fires on a date arithmetic that owes the tier nothing, so it relays
# whatever the record does or does not declare — with ONE exception. When the record
# declares a tier in its OWN `tier` field and that field names no tier this reader
# knows, the declaration is uninterpretable, and relaying on it hands the apply relay
# a record whose own verdict this producer cannot read. `"tier": "nоt-found"` with a
# Cyrillic o is the case that matters: a homoglyph past the dash class, which the
# stated limit says takes the ordinary path rather than the relay.
#
# Scoped to the `tier` field, NOT to the verdict fallback. A stamp finding carrying
# `"verdict": {"reviewed_by": "alice"}` has declared no tier and must still relay;
# withholding it would be this fix committing the over-capture the whole boundary
# exists to avoid.
def own_tier_unreadable:
  ([ tier_slot ] | names_in) as $own
  | ($own | length) > 0 and ($own | any(is_tier_name) | not);
# `searched` is read wherever the outcome may be DECLARED, through the same slots the
# tier is read through and with the key case-folded the same way: the record top level,
# and anywhere inside the `tier` or `verdict` value. A gate reading one position, or
# one casing, while the boundary reads three refuses a sidecar for naming its surfaces
# where it declared the outcome — the one direction this gate has no excuse for failing
# in, and it costs every well-formed finding in the sidecar beside it.
def searched_here:
  if type == "object" then
    to_entries[] | select(.key | ascii_downcase == "searched") | .value
  else empty end;
def searched_slots:
  [ searched_here,
    (tier_slot | .. | objects | searched_here),
    (verdict_slot | .. | objects | searched_here),
    null ]
  | map(if type == "array" then length else 0 end);
# For a record with no declared tier to respect, because it is not an object at
# all. Such a record is bound for `## Unparsed` verbatim, so a verdict name
# ANYWHERE inside it would print into the file the boundary keeps it out of —
# `[{"tier": "not-found", "excerpt": "..."}]` is a verdict in the wrong wrapper,
# not a future record. Naming a verdict exactly is the test, so a note that merely
# mentions one still takes the appendix path the contract gives it.
def stray_verdict:
  [ .. | (strings, (objects | keys[])) | norm ] | any(is_verdict_name);
'

# The searched-surfaces schema check, on the same input-refusal exit code as the
# guard above and for the same reason: refusing beats composing from a sidecar
# whose neutral outcome asserts nothing. A `not-found` outcome is only meaningful
# when it names the surfaces it checked, and that listing was prose-only until
# this check.
#
# It reads the tier through the SHARED reader above, not an exact top-level string
# compare. A gate stricter than the boundary would refuse valid input; a gate laxer
# than it — which an exact compare is — lets a `{"Tier": "not-found"}` sidecar past
# the refusal and then withholds it silently, which is the failure this gate exists
# to prevent.
#
# It validates the SIDECAR, not an emitted row, and it has to. The relay boundary
# below withholds every `not-found` finding from the findings file, so there is no
# row to check and no field to check it in — `searched` is read here and goes no
# further. Non-empty is all this can assert: nothing here knows which surfaces the
# run actually checked, so a complete listing and a truncated one look identical.
#
# `searched` is read at BOTH positions the outcome may be declared at, for the same
# reason the tier is: a sidecar keeping the outcome and its surfaces together in the
# `verdict` object names its surfaces, and refusing it whole would be this gate
# failing in the one direction it has no excuse for — rejecting input that satisfies
# the very requirement it enforces.
if ! jq -e "$TIER_DEFS"'
  [ (.findings // [])[]
    | select(declares_not_found)
    | select((searched_slots | max) == 0)
  ] | length == 0
' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has a not-found finding whose searched surfaces are not a non-empty array" >&2
  exit 3
fi

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

CORPUS_FILES="$(jq -r '.counts.files // ""' "$REPORT" 2>/dev/null)"

# ISO-8601 EXTENDED, colons in the time portion. The consumer reads this field
# only when it is a full date-time with an explicit UTC designator; the
# colon-free rule the convention states elsewhere binds the FILE NAME, not this.
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Non-overwrite naming: never clobber an unconsumed findings file.
if [[ -e "$OUT" ]]; then
  n=2
  while [[ -e "${OUT%.md}-$n.md" ]]; do n=$((n + 1)); done
  OUT="${OUT%.md}-$n.md"
fi
# Both writing steps are checked explicitly. `set -e` is deliberately off here,
# so an uncreatable directory or an unwritable path would otherwise let the run
# fall through to the success message: the audit reports its findings relayed
# while the consumer never scans a file that does not exist. That is the worst
# failure a persistence step can have, because nothing downstream contradicts it.
if ! mkdir -p "$(dirname "$OUT")" 2>/dev/null; then
  echo "emit-findings.sh: cannot create the destination directory for $OUT" >&2
  exit 5
fi

# Repo root for relativizing Location. One directory has several spellings on
# Git Bash, and matching the wrong one leaves every Location absolute — still a
# well-formed cell, so nothing downstream reports the miss. This producer fails
# OPEN: a path matching no spelling is left as-is.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT_ALT=""
if [[ -n "$REPO_ROOT" ]]; then
  REPO_ROOT_ALT="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || REPO_ROOT_ALT=""
  [[ "$REPO_ROOT_ALT" == "$REPO_ROOT" ]] && REPO_ROOT_ALT=""
fi

# --- Record stream ---------------------------------------------------------------
#
# jq classifies and composes the per-rule detail text; awk below owns escaping
# and table assembly. Fields are joined on tabs rather than @tsv because @tsv
# escapes backslashes, and an excerpt legitimately carries `\|` — the very
# sequence the idempotent escaper downstream has to see intact.

RECORDS="$(jq -r "$TIER_DEFS"'
def clean: (if . == null then "" else tostring end) | gsub("[\t\n\r]"; " ");

# WITHHOLDING IS DECIDED BY THE DECLARED TIER, AHEAD OF ANY RULE LOOKUP, through
# the shared reader defined above the searched-surfaces gate. A judgment verdict
# carrying no rule id used to match no branch below and fall through to "U", which
# prints the record verbatim into `## Unparsed` — tier name and payload landing in
# the one file the boundary keeps them out of. Deciding on the tier first closes
# that route and every variant of it: a verdict paired with a valid rule id, and a
# verdict declared inside a `verdict` object, are withheld too.
#
# Four kinds, because `## Surfaces` states what each count IS and a count that
# lumps them together says something false about the records in it:
#   R  relay-eligible, a table row
#   W  a declared judgment verdict, withheld and counted as such
#   X  a mapped rule whose declaration does not authorize the relay — a copy naming
#      no fingerprint-confirmed, a stamp whose own tier names no tier this reader
#      knows: not relay-eligible, but not a judgment finding on the human report
#   U  unmappable for any other reason, printed verbatim into `## Unparsed`
#
# EVERY FIELD READ BELOW IS TYPE-GUARDED, and a record that is not an object at all
# is routed to "U" before anything reads a key of it. jq aborts the whole program on
# a type error, so one malformed record — an array where an object belongs, a `span`
# that is a string, a `rule` that is a list — used to end the run at exit 3 and take
# every well-formed finding in the sidecar with it, under a message blaming the JSON.
# Refusing a sidecar is for what the input-refusal gates above examine deliberately;
# a single bad record is what `## Unparsed` is for.
def opt($k): if type == "object" then .[$k] else null end;

[ (.findings // [])[]
  | if type != "object" then
      (if stray_verdict then "W" else "U" end) as $kind
      | { kind: $kind, rorder: 3, rule: "", slug: "", file: "", lnum: 0,
          detail: "", raw: (if $kind == "U" then (. | tojson) else "" end) }
    else
  (if (.rule | type) == "string" then .rule else "" end) as $rule
  | ($rule | split("/") | last) as $slug
  | (if (.line | type) == "number" then .line
     elif (.span | opt("start_line") | type) == "number" then .span.start_line
     else 0 end) as $lnum
  | (
      if withheld_verdict then "W"
      elif $slug == "rule-verbatim-copy" then
        (if declares_confirmed then "R" else "X" end)
      elif $slug == "rule-stamp-expired" or $slug == "rule-trigger-less-stamp" then
        (if own_tier_unreadable then "X" else "R" end)
      else "U"
      end) as $kind
  | {
      kind: $kind,
      rorder: (
        if $slug == "rule-verbatim-copy" then 0
        elif $slug == "rule-stamp-expired" then 1
        elif $slug == "rule-trigger-less-stamp" then 2
        else 3 end),
      rule: $rule,
      slug: $slug,
      file: (.file // ""),
      lnum: $lnum,
      detail: (
        if $slug == "rule-verbatim-copy" then
          "matched span of \(.fingerprint | opt("longest_span_words") // "?") words, containment \(.fingerprint | opt("containment") // "?"), against \(.source | opt("url") // "an unnamed source")"
          + (if (.source | opt("identity") | opt("checked")) == true then " (identity checked)" else "" end)
          + (if (.excerpt // "") != "" then "; excerpt: \(.excerpt)" else "" end)
        elif $slug == "rule-stamp-expired" then
          "stamp \(.stamp_date // "?") exceeds the \(.window_days // "?")-day window by \(.days_over // "?") days"
        elif $slug == "rule-trigger-less-stamp" then
          "stamp \(.stamp_date // "?") on a surface stating no recheck trigger"
        else "" end),
      # Defence in depth for the boundary above: only the ONE kind that prints a
      # raw record carries one into the composition stage, so no later edit to the
      # awk half can print a withheld payload by accident.
      raw: (if $kind == "U" then (. | tojson) else "" end)
    }
    end
]
| sort_by(.kind, .rorder, .file, .lnum)
| .[]
| [ .kind, .slug, .rule, .file, (.lnum | tostring), .detail, .raw ]
| map(clean) | join("\t")
' "$REPORT" 2>/dev/null)" || {
  echo "emit-findings.sh: could not read $REPORT as JSON" >&2
  exit 3
}

# --- Composition -----------------------------------------------------------------

LC_ALL=C awk -F'\t' \
  -v branch="$BRANCH" -v date_utc="$DATE_UTC" -v corpus_files="$CORPUS_FILES" \
  -v repo_root="$REPO_ROOT" -v repo_root_alt="$REPO_ROOT_ALT" '
# Quote a frontmatter value only when the plain form would misparse. git
# accepts branch names starting with a YAML indicator ("#foo" reads as a
# comment) and names YAML implicitly types ("no" -> false, "123" -> a number).
# The consumer admits a findings file on an EXACT branch match, so a misparse
# silently drops every finding for that branch. The predicate is deliberately
# identical to the sibling producers: several producers answering one
# frontmatter contract must agree, or a consumer sees several shapes.
function yaml_implicit_typed(s,   l) {
  l = tolower(s)
  if (l ~ /^(true|false|yes|no|on|off|null|~)$/) return 1
  if (s ~ /^[+-]?[0-9]+$/) return 1
  if (s ~ /^[+-]?[0-9]*\.[0-9]+([eE][+-]?[0-9]+)?$/) return 1
  if (s ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/) return 1
  return 0
}
function yaml_scalar(s) {
  if (s ~ /^[-?:,\[\]{}#&*!|>%@`"\047]/ || s ~ /: / || s ~ / #/ || s ~ /^$/ ||
      s ~ /[ \t]$/ || yaml_implicit_typed(s)) {
    gsub(/\\/, "\\\\", s)
    gsub(/"/, "\\\"", s)
    return "\"" s "\""
  }
  return s
}

# Tier/Action mirror of the severity crosswalk (see header comment). All three
# rules argue to IMPORTANT and none is auto-applicable: each repair is a
# judgment the relay surfaces rather than applies.
function rule_tier(slug) { return "IMPORTANT" }
function rule_action(slug) {
  if (slug == "rule-verbatim-copy")
    return "Not auto-applicable — remediate with `/provenance:audit fix`; disposition choice, the semantic-diff guard and pointer liveness are producer-owned"
  if (slug == "rule-stamp-expired")
    return "Not auto-applicable — re-derive the record against its live basis and restamp, or replace the restatement with a pointer"
  if (slug == "rule-trigger-less-stamp")
    return "Not auto-applicable — state the observable event that obliges re-derivation (upstream-drift required part 4)"
  return "Review by hand"
}

# Cell-escaping rule: a literal | becomes \| inside Finding/Action cells.
#
# IDEMPOTENT. A naive gsub double-escapes a pipe the SOURCE already escaped:
# `a \| b` becomes `a \\| b`, which GFM reads as a literal backslash followed
# by a LIVE delimiter — the cell splits and the fix action misreads the row.
# Escape by the parity of the complete backslash run before each pipe: an odd
# count already escapes the delimiter; an even count (zero included) does not.
function esc(s,   out, i, n, c, bs) {
  out = ""; n = length(s); i = 1
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\\") {
      bs = 0
      while (i <= n && substr(s, i, 1) == "\\") { bs++; i++ }
      if (i <= n && substr(s, i, 1) == "|") {
        if (bs % 2 == 0) bs++
        while (bs--) out = out "\\"
        out = out "|"
        i++
      } else {
        while (bs--) out = out "\\"
      }
    } else if (c == "|") {
      out = out "\\|"; i++
    } else {
      out = out c; i++
    }
  }
  return out
}

# Fail OPEN: a path matching no spelling is returned unchanged.
function relativize(p) {
  if (repo_root != "" && index(p, repo_root "/") == 1)
    return substr(p, length(repo_root) + 2)
  if (repo_root_alt != "" && index(p, repo_root_alt "/") == 1)
    return substr(p, length(repo_root_alt) + 2)
  return p
}

BEGIN { n_relay = 0; n_withheld = 0; n_ineligible = 0; n_unparsed = 0 }

NF >= 6 {
  kind = $1; slug = $2; rule = $3; file = $4; lnum = $5; detail = $6; raw = $7
  if (kind == "R") {
    n_relay++
    r_slug[n_relay] = slug
    r_loc[n_relay] = relativize(file) (lnum + 0 > 0 ? ":" lnum : "")
    r_find[n_relay] = rule ": " detail
  } else if (kind == "W") {
    n_withheld++
  } else if (kind == "X") {
    n_ineligible++
  } else {
    n_unparsed++
    u_raw[n_unparsed] = raw
  }
}

END {
  printf("---\n")
  printf("type: review-findings\n")
  printf("date: %s\n", date_utc)
  printf("branch: %s\n", yaml_scalar(branch))
  printf("---\n\n")

  printf("## Findings\n\n")
  printf("| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |\n")
  printf("|------|------|------------|----------|------------|---------|--------|\n")
  for (i = 1; i <= n_relay; i++) {
    # Confidence is `high` for every row here: each is a deterministic rule
    # that fired. Confidence is confidence-of-realness, never confidence in the
    # fix — the fix judgment is said in Tier and in the Action wording.
    # Location is escaped like every other cell that carries input. A path is not
    # trusted to be pipe-free — `a|b.md` split the row, and every cell after it
    # shifted one column left, so the consumer read the Finding as a Surface.
    printf("| %d | %s | high | %s | provenance:audit | %s | %s |\n",
      i, rule_tier(r_slug[i]), esc(r_loc[i]), esc(r_find[i]), esc(rule_action(r_slug[i])))
  }
  printf("\n")

  if (n_unparsed > 0) {
    printf("## Unparsed\n\n")
    printf("Findings the projection could not map to a relay rule, kept verbatim:\n\n")
    for (i = 1; i <= n_unparsed; i++) printf("- `%s`\n", u_raw[i])
    printf("\n")
  }

  printf("## Surfaces\n\n")
  printf("Ran: provenance:audit")
  if (corpus_files != "") printf(" over %s corpus files", corpus_files)
  printf(". Relay-eligible findings: %d.", n_relay)
  # Each count says what its records ARE. Calling every withheld record a judgment
  # finding was false of the copy findings in the second count, and false in the
  # direction that matters: it asserted they were on the human report, which sends
  # a reader looking for them where they are not.
  if (n_withheld > 0)
    printf(" Withheld from the relay: %d judgment findings, which stay on the human report by contract.", n_withheld)
  if (n_ineligible > 0)
    printf(" Not relay-eligible: %d findings declaring a tier this producer cannot relay on.", n_ineligible)
  if (n_unparsed > 0)
    printf(" Unmapped: %d, listed above.", n_unparsed)
  printf("\n")
}
' <<<"$RECORDS" >"$OUT" || {
  echo "emit-findings.sh: failed to write $OUT" >&2
  exit 5
}

if [[ ! -s "$OUT" ]]; then
  echo "emit-findings.sh: wrote nothing to $OUT" >&2
  exit 5
fi

echo "emit-findings.sh: wrote $OUT" >&2

#!/usr/bin/env bash
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"

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

while [[ $# -gt 0 ]]; do
  case "$1" in
  --report)
    require_opt_value "emit-findings.sh" "$@"
    REPORT="$2"
    shift 2
    ;;
  --out)
    require_opt_value "emit-findings.sh" "$@"
    OUT="$2"
    shift 2
    ;;
  --branch)
    require_opt_value "emit-findings.sh" "$@"
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

if ! jq -e 'type == "object"' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT is not a JSON object; not audit output" >&2
  exit 3
fi

if ! jq -e 'has("findings")' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has no findings key; not audit output" >&2
  exit 3
fi

if ! jq -e '(.findings | type) == "array"' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has a findings key that is not a list; not audit output" >&2
  exit 3
fi

# shellcheck disable=SC2016  # `$name` is a jq parameter, not a shell expansion.
TIER_DEFS='
def key_slot($k):
  if type == "object" then
    to_entries[] | select(.key | ascii_downcase == $k) | .value
  else empty end;
def tier_slot: key_slot("tier");
def verdict_slot: key_slot("verdict");
# The top-level `tier` IS the declaration whenever it DECLARES one. A `verdict`
# is the judges output, and the tier is set by fixed rule from the evidence rather
# than from a judge — different fields by design — so a record declaring
# `fingerprint-confirmed` and carrying `"verdict": {"prior": "llm-suspected"}` has
# declared a confirmed copy.
#
# A record whose `tier` NAMES NO TIER falls back to its `verdict`, which is then the
# only tier it has: the `tier` child when it has one, and otherwise the whole value.
#
# NARROWING TURNS ON A TIER NAMED, NEVER ON A `tier` KEY PRESENT — at BOTH steps, and
# by the same rule, because the two steps are the same question asked twice.
#
# Characters that render as nothing are stripped EVERYWHERE, by
# `Default_Ignorable_Code_Point` — the Unicode property for exactly that — plus the
# rest of `Cf`.
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
# `{"tier": "not-found"}` says.
def names_in:
  [ .[] | .. | (strings, (objects | keys[])) | norm ];
# `source-not-identified` is the older spelling of `not-found` that
# SKILL.md once published, and it stays recognized here: a
# sidecar is model-authored against whatever description was in context, and a name
# this reader does not know is a verdict that walks into the relay. Recognizing one
# name too many can only withhold a record; recognizing one too few relays a judgment
# verdict. Do not narrow this to one name.
def is_verdict_name:
  . == "vendored-snapshot" or . == "source-fetched-similar" or . == "llm-suspected"
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
def withheld_verdict:
  declared_names | any(is_verdict_name);
def declares_not_found:
  declared_names | any(is_neutral_name);
def declares_confirmed:
  declared_names | index("fingerprint-confirmed") != null;
# A stamp rule fires on a date arithmetic that owes the tier nothing, so it relays
# whatever the record does or does not declare — with TWO exceptions, and the one
# below is the second of them to be evaluated.
#
# FIRST, in the classification chain: `withheld_verdict` is tested before any rule id
# is looked at, so a stamp record that declares a judgment verdict is withheld there
# and never reaches this predicate.
#
# SECOND, here. When the record declares a tier in its OWN `tier` field and that field
# names no tier this reader knows, the declaration is uninterpretable, and relaying on
# it hands the apply relay a record whose own verdict this producer cannot read.
#
# This second exception is scoped to the `tier` field, NOT to the verdict fallback. A
# stamp finding carrying `"verdict": {"reviewed_by": "alice"}` names no verdict and
# declares no tier, so it passes both exceptions and must still relay.
def own_tier_unreadable:
  ([ tier_slot ] | names_in) as $own
  | ($own | length) > 0 and ($own | any(is_tier_name) | not);
# `searched` is read wherever the outcome may be DECLARED, through the same slots the
# tier is read through and with the key case-folded the same way: the record top level,
# and anywhere inside the `tier` or `verdict` value.
def searched_here: key_slot("searched");
def searched_slots:
  [ searched_here,
    (tier_slot | .. | objects | searched_here),
    (verdict_slot | .. | objects | searched_here),
    null ]
  | map(if type == "array" then length else 0 end);
# For a record with no declared tier to respect, because it is not an object at
# all. Such a record is bound for `## Unparsed` verbatim, so a verdict name
# ANYWHERE inside it would print into the file the boundary keeps it out of —
# `[{"tier": "not-found", "excerpt": "..."}]` is a verdict in the wrong wrapper.
def stray_verdict:
  [ . ] | names_in | any(is_verdict_name);
'

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

DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ -e "$OUT" ]]; then
  n=2
  while [[ -e "${OUT%.md}-$n.md" ]]; do n=$((n + 1)); done
  OUT="${OUT%.md}-$n.md"
fi
if ! mkdir -p "$(dirname "$OUT")" 2>/dev/null; then
  echo "emit-findings.sh: cannot create the destination directory for $OUT" >&2
  exit 5
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT_ALT=""
if [[ -n "$REPO_ROOT" ]]; then
  REPO_ROOT_ALT="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || REPO_ROOT_ALT=""
  [[ "$REPO_ROOT_ALT" == "$REPO_ROOT" ]] && REPO_ROOT_ALT=""
fi

RECORDS="$(jq -r "$TIER_DEFS"'
def clean: (if . == null then "" else tostring end) | gsub("[\t\n\r]"; " ");

# WITHHOLDING IS DECIDED BY THE DECLARED TIER, AHEAD OF ANY RULE LOOKUP, through
# the shared reader defined above the searched-surfaces gate.
#
# ONE CLASS IS DECIDED BEFORE THAT, and by no tier: a restated-fact record, by its
# rule slug or its class. Only the fully qualified rule id can relay; a record carrying
# the slug under another prefix is W, as the copy and stamp rows match by slug.
#
# Four kinds, because `## Surfaces` states what each count IS and a count that
# lumps them together says something false about the records in it:
#   R  relay-eligible, a table row
#   W  a declared judgment verdict, or a restated-fact finding lacking the declared
#      outcome, withheld and counted as such
#   X  a mapped rule whose declaration does not authorize the relay — a copy naming
#      no fingerprint-confirmed, a stamp whose own tier names no tier this reader
#      knows: not relay-eligible, but not a judgment finding on the human report
#   U  unmappable for any other reason, printed verbatim into `## Unparsed`
#
# EVERY FIELD READ BELOW IS TYPE-GUARDED, and a record that is not an object at all
# is routed to "U" (or "W") before anything reads a key of it.
def opt($k): if type == "object" then .[$k] else null end;

# The declared outcome is read strictly, the opposite of the tier reader: a
# generous read here is a relay nobody authorized. Exact top-level keys
# `class`, `rubric` and `review`, a real boolean `unanimous`, and each verdict
# a string equal to its documented name after `norm`.
def says($want): type == "string" and norm == $want;
def restated_class: opt("class") | says("restated-fact");
def outcome_declared:
  restated_class
  and ((opt("rubric") | opt("unanimous")) == true)
  and (opt("rubric") | opt("verdict") | says("stands"))
  and (opt("review") | opt("verdict") | says("survives"));

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
  | ($rule == "attribution/audit/rule-restated-upstream-fact") as $restated_rule
  | (
      if $slug == "rule-restated-upstream-fact" or restated_class then
        (if $restated_rule and outcome_declared then "R" else "W" end)
      elif withheld_verdict then "W"
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
        elif $slug == "rule-restated-upstream-fact" then
          # Only what the row needs, each read type-guarded so a stray object in
          # `samples`, `url` or `excerpt` cannot carry a tier name in as a value.
          "restates a fact an external source owns with no conforming pointer or record; unanimous panel of \(.rubric | opt("samples") | if type == "number" then tostring else "?" end) samples, refutation survived"
          + (.source | opt("url") | if type == "string" then "; source \(.)" else "" end)
          + (.excerpt | if type == "string" and . != "" then "; excerpt: \(.)" else "" end)
        else "" end),
      # Only U carries its raw record to the awk stage, so awk cannot print a
      # withheld payload.
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

# Tier/Action mirror of the severity crosswalk. All four
# rules argue to IMPORTANT and none is auto-applicable: each repair is a
# judgment the relay surfaces rather than applies.
function rule_tier(slug) { return "IMPORTANT" }
# Confidence is confidence-of-realness, `high` or omitted. The three deterministic
# rules fired on a computation; the restated-fact row was selected by a panel, so
# its cell is empty rather than `high`.
function rule_confidence(slug) {
  return slug == "rule-restated-upstream-fact" ? "" : "high"
}
function rule_action(slug) {
  if (slug == "rule-verbatim-copy")
    return "Not auto-applicable: remediate with `/attribution:audit fix`; disposition choice, the semantic-diff guard and pointer liveness are producer-owned"
  if (slug == "rule-stamp-expired")
    return "Not auto-applicable: re-derive the record against its live basis and restamp, or replace the restatement with a pointer"
  if (slug == "rule-trigger-less-stamp")
    return "Not auto-applicable: state the observable event that obliges re-derivation (upstream-drift required part 4)"
  if (slug == "rule-restated-upstream-fact")
    return "Not auto-applicable: report-only, no fix pass reaches it; replace the restatement with a pointer at the point of use, or with a stamped record (the decision in its own words, a pointer, an as-of date, an observable recheck trigger) when the surface must work offline"
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
    # Location is escaped like every input cell: a path may contain a pipe.
    printf("| %d | %s | %s | %s | attribution:audit | %s | %s |\n",
      i, rule_tier(r_slug[i]), rule_confidence(r_slug[i]), esc(r_loc[i]), esc(r_find[i]),
      esc(rule_action(r_slug[i])))
  }
  printf("\n")

  if (n_unparsed > 0) {
    printf("## Unparsed\n\n")
    printf("Findings the projection could not map to a relay rule, kept verbatim:\n\n")
    for (i = 1; i <= n_unparsed; i++) printf("- `%s`\n", u_raw[i])
    printf("\n")
  }

  printf("## Surfaces\n\n")
  printf("Ran: attribution:audit")
  if (corpus_files != "") printf(" over %s corpus files", corpus_files)
  printf(". Relay-eligible findings: %d.", n_relay)
  # Each count says what its records are, so a reader looks in the right place.
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

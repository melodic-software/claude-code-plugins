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
# usage error, 3 when the report carries no findings key at all (not audit
# output; refusing beats composing from garbage), 4 when jq is absent, 5 when
# the destination could not be written.
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

if ! jq -e 'has("findings")' "$REPORT" >/dev/null 2>&1; then
  echo "emit-findings.sh: $REPORT has no findings key; not audit output" >&2
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

RECORDS="$(jq -r '
def clean: (if . == null then "" else tostring end) | gsub("[\t\n\r]"; " ");

[ (.findings // [])[]
  | (.rule // "") as $rule
  | ($rule | split("/") | last) as $slug
  | ((.line // .span.start_line) // 0) as $lnum
  | {
      kind: (
        if $slug == "rule-verbatim-copy" then
          (if (.tier // "") == "fingerprint-confirmed" then "R" else "W" end)
        elif $slug == "rule-stamp-expired" or $slug == "rule-trigger-less-stamp" then "R"
        else "U"
        end),
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
          "matched span of \(.fingerprint.longest_span_words // "?") words, containment \(.fingerprint.containment // "?"), against \(.source.url // "an unnamed source")"
          + (if .source.identity.checked == true then " (identity checked)" else "" end)
          + (if (.excerpt // "") != "" then "; excerpt: \(.excerpt)" else "" end)
        elif $slug == "rule-stamp-expired" then
          "stamp \(.stamp_date // "?") exceeds the \(.window_days // "?")-day window by \(.days_over // "?") days"
        elif $slug == "rule-trigger-less-stamp" then
          "stamp \(.stamp_date // "?") on a surface stating no recheck trigger"
        else "" end),
      raw: (. | tojson)
    }
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

BEGIN { n_relay = 0; n_withheld = 0; n_unparsed = 0 }

NF >= 6 {
  kind = $1; slug = $2; rule = $3; file = $4; lnum = $5; detail = $6; raw = $7
  if (kind == "R") {
    n_relay++
    r_slug[n_relay] = slug
    r_loc[n_relay] = relativize(file) (lnum + 0 > 0 ? ":" lnum : "")
    r_find[n_relay] = rule ": " detail
  } else if (kind == "W") {
    n_withheld++
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
    printf("| %d | %s | high | %s | provenance:audit | %s | %s |\n",
      i, rule_tier(r_slug[i]), r_loc[i], esc(r_find[i]), esc(rule_action(r_slug[i])))
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
  if (n_withheld > 0)
    printf(" Withheld from the relay: %d judgment findings, which stay on the human report by contract.", n_withheld)
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

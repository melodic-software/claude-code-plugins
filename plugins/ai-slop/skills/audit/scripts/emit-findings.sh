#!/usr/bin/env bash
# Compose a conforming review-findings file from detect.sh output.
#
#   emit-findings.sh --from <detect-output> --out <path> [--branch <b>] [--tier <t>]
#
# The FINDINGS HOME is never resolved here: the caller (the audit skill)
# resolves it through the detector-findings convention's rung order and its
# fetch-and-refuse gate, then hands the resolved path in as --out. This script
# owns only the deterministic composition — at repo scale a findings file runs
# to thousands of rows, which is script work, not prose work.
#
# The per-rule Tier/Action cells MIRROR the severity crosswalk in
# docs/conventions/detector-findings/README.md ("The severity crosswalk");
# that table is the source of truth — a tier change lands there first and is
# copied here, never the reverse.
#
# Exit: 0 on success, 2 on usage error, 3 when --from carries no detect.sh
# Summary rows at all (not detector output; refusing beats composing from
# garbage). Zero findings with Summary rows present still WRITES the file —
# per the persist contract, coverage is the payload.
set -euo pipefail

FROM=""
OUT=""
BRANCH=""
TIER="medium"

usage() {
  cat <<'EOF'
emit-findings.sh — compose a review-findings file from detect.sh output.

Usage:
  emit-findings.sh --from <detect-output> --out <path> [--branch <b>] [--tier <small|medium|large>]

--out is the CONVENTION-RESOLVED destination; if it exists, a -2/-3 suffix is
appended (non-overwrite naming). --branch defaults to the current git branch.
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
  --from)
    require_opt_value "$@"
    FROM="$2"
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
  --tier)
    require_opt_value "$@"
    TIER="$2"
    shift 2
    ;;
  --help | -h)
    usage
    exit 0
    ;;
  *)
    echo "emit-findings.sh: unknown argument: $1" >&2
    exit 2
    ;;
  esac
done

[[ -n "$FROM" && -n "$OUT" ]] || {
  usage >&2
  exit 2
}
[[ -f "$FROM" ]] || {
  echo "emit-findings.sh: --from file not found: $FROM" >&2
  exit 2
}
case "$TIER" in small | medium | large) ;; *)
  echo "emit-findings.sh: --tier must be small|medium|large" >&2
  exit 2
  ;;
esac

if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

if ! LC_ALL=C grep -q '^Summary rule=' "$FROM"; then
  echo "emit-findings.sh: $FROM has no detect.sh Summary rows; not detector output" >&2
  exit 3
fi

# Non-overwrite naming: never clobber an unconsumed findings file.
if [[ -e "$OUT" ]]; then
  n=2
  while [[ -e "${OUT%.md}-$n.md" ]]; do n=$((n + 1)); done
  OUT="${OUT%.md}-$n.md"
fi
mkdir -p "$(dirname "$OUT")"

DATE_UTC="$(date -u +%Y-%m-%dT%H-%M-%SZ)"

LC_ALL=C awk -v branch="$BRANCH" -v tier="$TIER" -v date_utc="$DATE_UTC" '
  # Tier/Action mirror of the severity crosswalk (see header comment).
  function rule_tier(slug) {
    if (slug == "rule-knowledge-cutoff-disclaimer" || slug == "rule-llm-citation-artifacts")
      return "IMPORTANT"
    return "SUGGESTION"
  }
  function rule_action(slug) {
    if (slug == "rule-utm-params")
      return "Strip the utm_* parameters from the URL (auto-applicable: resolution unchanged)"
    if (slug == "rule-knowledge-cutoff-disclaimer")
      return "Delete the assistant-frame sentence; check surrounding prose did not depend on it"
    if (slug == "rule-llm-citation-artifacts")
      return "Remove the generation artifact; decide whether the claim needs a real citation"
    return "Guarded rewrite via /ai-slop:audit fix (judgment; see crosswalk row)"
  }
  # Cell-escaping rule: literal | becomes \| inside Finding/Action cells.
  function esc(s) { gsub(/\|/, "\\|", s); return s }

  /^Finding: / {
    # Split the excerpt off FIRST, on the first " excerpt=" occurrence, then
    # parse the remaining header left-to-right with index() (first match).
    # Greedy .* extraction would anchor on the LAST "file="/"line=" in the
    # line, so an excerpt containing those tokens (docs describing this very
    # format) would silently corrupt the Location cell.
    line = $0
    sub(/^Finding: rule=ai-slop\/audit\//, "", line)
    ix = index(line, " excerpt=")
    if (ix == 0) next
    excerpt = substr(line, ix + 9)
    head = substr(line, 1, ix - 1)
    ix = index(head, " fired=")
    fired = substr(head, ix + 7)
    head = substr(head, 1, ix - 1)
    ix = index(head, " line=")
    lno = substr(head, ix + 6)
    head = substr(head, 1, ix - 1)
    ix = index(head, " file=")
    file = substr(head, ix + 6)
    slug = substr(head, 1, ix - 1)
    t = rule_tier(slug)
    row = "| " t " | high | " file ":" lno " | ai-slop:audit | " \
      esc("ai-slop/audit/" slug " " fired " -- " excerpt) " | " esc(rule_action(slug)) " |"
    if (t == "IMPORTANT") imp[++ni] = row
    else sug[++ns] = row
    next
  }
  /^Declined: / { declined_files[++ndecl] = $0; next }
  /^Summary rule=/ {
    line = $0
    sub(/^Summary rule=/, "", line)
    rid = line; sub(/ .*/, "", rid)
    f = line; sub(/.*findings=/, "", f); sub(/ .*/, "", f)
    d = line; sub(/.*declined=/, "", d); sub(/ .*/, "", d)
    if (f == 0) norows[++nz] = rid
    if (d > 0) decl[rid] = d
    next
  }
  END {
    printf "---\ntype: review-findings\ndate: %s\nbranch: %s\ntier: %s\n---\n\n", date_utc, branch, tier
    print "## Findings"
    print ""
    print "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
    print "|------|------|------------|----------|------------|---------|--------|"
    rank = 0
    for (i = 1; i <= ni; i++) printf "| %d %s\n", ++rank, imp[i]
    for (i = 1; i <= ns; i++) printf "| %d %s\n", ++rank, sug[i]
    print ""
    print "## Surfaces"
    print ""
    ran = "Ran: [ai-slop:audit (detect.sh)]."
    zero = ""
    for (i = 1; i <= nz; i++) zero = zero (zero == "" ? "" : ", ") norows[i]
    if (zero != "") ran = ran " Returned no result: [" zero "]."
    print ran
    for (rid in decl) printf "Declined candidates: %s count=%s\n", rid, decl[rid]
    for (i = 1; i <= ndecl; i++) print declined_files[i]
  }
' "$FROM" >"$OUT"

echo "emit-findings.sh: wrote $OUT"

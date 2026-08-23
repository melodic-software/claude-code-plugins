#!/usr/bin/env bash
# Compose a conforming review-findings file from detect.sh output.
#
#   emit-findings.sh --from <detect-output> --out <path> [--branch <b>]
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

# No `tier:` frontmatter is emitted. Both owner docs (context/persist-findings.md
# and the detector-findings adopter row) say this producer omits it, and nothing
# here computes a value: the retired --tier flag defaulted to a hardcoded
# "medium" that described no property of the run.
FROM=""
OUT=""
BRANCH=""

usage() {
  cat <<'EOF'
emit-findings.sh — compose a review-findings file from detect.sh output.

Usage:
  emit-findings.sh --from <detect-output> --out <path> [--branch <b>]

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

# ISO-8601 EXTENDED, colons in the time portion. The consumer parses this field:
# fix-pass-mode.md "Step 1" reads a value only if it is "a full ISO-8601
# date-time carrying an explicit UTC designator (Z) or a numeric offset", and
# calls anything else UNREADABLE. The colon-free rule this convention states
# elsewhere binds the FILE NAME (Windows-safe), never this frontmatter field.
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Repo root, for relativizing Location when detect.sh handed us an absolute
# path. One directory has several SPELLINGS on Git Bash, and matching the
# wrong one leaves every Location absolute — an absolute path is still a
# well-formed cell, so the fail-open producer never reports it. Measured:
# `git rev-parse --show-toplevel` answers `C:/Users/u/AppData/Local/Temp/t/repo`
# while the caller reached the same directory as `/tmp/t/repo`.
#
# The PRIMARY anchor is derived from the caller's own `pwd` by removing the
# sub-path git reports for it. The git-reported forms stay as fallbacks.
# (This producer FAILs OPEN: a path that matches no spelling is left as-is.
# The claude-config sibling fails closed on the same mismatch.)
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT_ALT=""
REPO_ROOT_PWD=""
if [[ -n "$REPO_ROOT" ]]; then
  REPO_ROOT_ALT="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || REPO_ROOT_ALT=""
  [[ "$REPO_ROOT_ALT" == "$REPO_ROOT" ]] && REPO_ROOT_ALT=""
  git_prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"
  git_prefix="${git_prefix%/}"
  cwd_now="$(pwd)"
  if [[ -z "$git_prefix" ]]; then
    REPO_ROOT_PWD="$cwd_now"
  elif [[ "$cwd_now" == */"$git_prefix" ]]; then
    REPO_ROOT_PWD="${cwd_now%/"$git_prefix"}"
  fi
  [[ "$REPO_ROOT_PWD" == "$REPO_ROOT" || "$REPO_ROOT_PWD" == "$REPO_ROOT_ALT" ]] && REPO_ROOT_PWD=""
fi

LC_ALL=C awk -v branch="$BRANCH" -v date_utc="$DATE_UTC" \
  -v repo_root="$REPO_ROOT" -v repo_root_alt="$REPO_ROOT_ALT" -v repo_root_pwd="$REPO_ROOT_PWD" '
  # Tier/Action mirror of the severity crosswalk (see header comment).
  function rule_tier(slug) {
    if (slug == "rule-knowledge-cutoff-disclaimer" || slug == "rule-llm-citation-artifacts" ||
        slug == "rule-chatbot-artifacts")
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
    if (slug == "rule-chatbot-artifacts")
      return "Delete the chat-turn sentence; keep any real content it carried in document register"
    if (slug == "rule-filler-phrases")
      return "Substitute per rewrite-guide.md: \"in order to\" -> \"to\", \"due to the fact that\" -> \"because\"; delete the note-phrases outright"
    if (slug == "rule-stacked-hedging")
      return "Keep the one hedge that states the real uncertainty; drop the other"
    return "Guarded rewrite via /ai-slop:audit fix (judgment; see crosswalk row)"
  }
  # Cell-escaping rule: literal | becomes \| inside Finding/Action cells.
  #
  # IDEMPOTENT. A naive gsub double-escapes a pipe the SOURCE already escaped:
  # `a \| b` becomes `a \\| b`, which GFM reads as a literal backslash followed
  # by a LIVE delimiter — the cell splits and the fix action misreads the row.
  # This repo writes literal `\|` in its own tables, so the case is real rather
  # than theoretical. Already-escaped pipes are parked on a sentinel first, then
  # restored single-escaped. (Defect identified in #3180; fan-out from #3202.)
  function esc(s) {
    gsub(/\\\|/, "\001", s)
    gsub(/\|/, "\\|", s)
    gsub(/\001/, "\\|", s)
    return s
  }

  # Prefer the caller pwd spelling, then git toplevel, then cd-then-pwd.
  # Fail OPEN: a path matching no spelling is returned unchanged (absolute
  # Location stays well-formed). That was this producer pre-fix mode.
  function relativize(p) {
    if (repo_root_pwd != "" && index(p, repo_root_pwd "/") == 1)
      return substr(p, length(repo_root_pwd) + 2)
    if (repo_root != "" && index(p, repo_root "/") == 1)
      return substr(p, length(repo_root) + 2)
    if (repo_root_alt != "" && index(p, repo_root_alt "/") == 1)
      return substr(p, length(repo_root_alt) + 2)
    return p
  }

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
    file = relativize(substr(head, ix + 6))
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
    printf "---\ntype: review-findings\ndate: %s\nbranch: %s\n---\n\n", date_utc, branch
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

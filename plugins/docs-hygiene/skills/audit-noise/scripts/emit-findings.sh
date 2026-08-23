#!/usr/bin/env bash
# Compose a conforming review-findings file from detect.sh output.
#
#   emit-findings.sh --from <detect-output> --out <path> [--branch <b>]
#
# The FINDINGS HOME is never resolved here: the caller (the audit-noise skill)
# resolves it through the detector-findings convention's rung order and its
# fetch-and-refuse gate, then hands the resolved path in as --out. This script
# owns only the deterministic composition.
#
# The per-rule Tier/Action cells MIRROR the severity crosswalk in
# docs/conventions/detector-findings/README.md ("The severity crosswalk");
# that table is the source of truth — a tier change lands there first and is
# copied here, never the reverse.
#
# ONE of this detector's six shapes has a crosswalk row
# (rule-negation-without-positive). The other five are counted as declined with
# reason=no-severity-crosswalk-row rather than emitted: "no crosswalk row, no
# relay" made visible in `## Surfaces` instead of enforced by silence.
#
# Exit: 0 on success, 2 on usage error, 3 when --from carries no detect.sh
# Summary total row (not detector output; refusing beats composing from
# garbage). Zero findings with a Summary row present still WRITES the file —
# per the persist contract, coverage is the payload.
set -euo pipefail

# No `tier:` frontmatter is emitted: it is required of review:fanout's own
# writer, and nothing here computes a value that would describe this run.
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

# `branch:` is what proves a findings file is this branch's — never the
# directory it sits in. fix-pass-mode.md "Step 1" admits a candidate only when
# its branch: equals the current branch EXACTLY, so with no resolvable branch
# there is nothing correct to write and refusing beats emitting a file the
# relay can never match (the normal state on a detached-HEAD CI checkout).
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

if ! LC_ALL=C grep -q '^Summary total: files=' "$FROM"; then
  echo "emit-findings.sh: $FROM has no detect.sh Summary total row; not detector output" >&2
  exit 3
fi

# Non-overwrite naming: never clobber an unconsumed findings file.
if [[ -e "$OUT" ]]; then
  n=2
  while [[ -e "${OUT%.md}-$n.md" ]]; do n=$((n + 1)); done
  OUT="${OUT%.md}-$n.md"
fi
mkdir -p "$(dirname "$OUT")"

# Repo root, for relativizing Location. The fix action fences each remediation
# to its finding's Location, and an absolute path is not portable to the
# checkout that applies the fix.
#
# One directory has several SPELLINGS on Git Bash, and matching the wrong one
# leaves every Location absolute while nothing reports it — an absolute path is
# still a well-formed cell, so the relativization fails silently. Measured on
# one fixture: `git rev-parse --show-toplevel` answers
# `C:/Users/u/AppData/Local/Temp/t/repo`, `cd`-then-`pwd` answers
# `/c/Users/u/AppData/Local/Temp/t/repo`, and the caller reached it as
# `/tmp/t/repo` through a separate MSYS mount. All three name one directory.
#
# The PRIMARY anchor is therefore derived from the caller's own `pwd` — the
# same spelling detect.sh absolutized its targets with, because both come from
# `pwd` in the same shell — by removing the sub-path git reports for it. The
# git-reported forms stay as fallbacks for a caller that resolved paths some
# other way.
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

# ISO-8601 EXTENDED, colons in the time portion. The consumer parses this field:
# fix-pass-mode.md "Step 1" reads a value only if it is "a full ISO-8601
# date-time carrying an explicit UTC designator (Z) or a numeric offset", and
# calls anything else UNREADABLE. The colon-free rule this convention states
# elsewhere binds the FILE NAME (Windows-safe), never this frontmatter field.
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

LC_ALL=C awk -v branch="$BRANCH" -v date_utc="$DATE_UTC" -v repo_root="$REPO_ROOT" \
  -v repo_root_alt="$REPO_ROOT_ALT" -v repo_root_pwd="$REPO_ROOT_PWD" '
  # Cell-escaping rule: literal | becomes \| inside Finding/Action cells, and
  # this detector reads DOCUMENTS — markdown tables in the audited corpus put
  # pipes into excerpts as a matter of course.
  function esc(s) { gsub(/\|/, "\\|", s); return s }

  # The condition that fired, in the run own values: which cue selected the
  # line. Peeled the same way the detector peels it, so the reported cue is the
  # one the rule actually matched rather than a restatement of the rule.
  function fired_cue(x,   t) {
    t = x
    sub(/^[ \t]+/, "", t)
    sub(/^(>|[-*+]|[0-9]+[.)])[ \t]+/, "", t)
    sub(/^\*\*/, "", t)
    sub(/^\*/, "", t)
    if (t ~ /^Do not[ \t]/) return "Do not"
    if (t ~ /^Do NOT[ \t]/) return "Do NOT"
    if (t ~ /^Don.t[ \t]/) return "Don\47t"
    if (t ~ /^Never[ \t]/) return "Never"
    if (t ~ /^Avoid[ \t]/) return "Avoid"
    return "unknown"
  }

  function relativize(p) {
    if (repo_root_pwd != "" && index(p, repo_root_pwd "/") == 1)
      return substr(p, length(repo_root_pwd) + 2)
    if (repo_root != "" && index(p, repo_root "/") == 1)
      return substr(p, length(repo_root) + 2)
    if (repo_root_alt != "" && index(p, repo_root_alt "/") == 1)
      return substr(p, length(repo_root_alt) + 2)
    return p
  }

  function flush_record(   loc, cue, row) {
    if (r_shape == "") return
    seen[r_shape]++
    if (r_shape != "negation-without-positive") {
      # No crosswalk row, no relay. Counted, never silently dropped.
      declined[r_shape]++
      reset_record()
      return
    }
    loc = relativize(r_file) ":" r_line
    cue = fired_cue(r_excerpt)
    row = "| SUGGESTION | high | " loc " | docs-hygiene:audit-noise | " \
      esc("docs-hygiene/audit-noise/rule-negation-without-positive cue=\"" cue \
          "\", positive-clauses=0 -- " r_excerpt) \
      " | " esc("Rewrite to the positive target the prohibition implies. Keep the negation only where the positive form loses the constraint, and then pair the two in one sentence.") " |"
    rows[++nrows] = row
    reset_record()
  }

  function reset_record() { r_file = ""; r_shape = ""; r_line = ""; r_excerpt = "" }

  /^File: /           { flush_record(); r_file = substr($0, 7); next }
  /^Finding shape: /  { r_shape = substr($0, 16); next }
  /^Finding line: /   { r_line = substr($0, 15); next }
  /^Finding excerpt: /{ r_excerpt = substr($0, 18); next }
  /^---$/             { flush_record(); next }

  END {
    flush_record()
    printf "---\ntype: review-findings\ndate: %s\nbranch: %s\n---\n\n", date_utc, branch
    print "## Findings"
    print ""
    print "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
    print "|------|------|------------|----------|------------|---------|--------|"
    for (i = 1; i <= nrows; i++) printf "| %d %s\n", i, rows[i]
    print ""
    print "## Surfaces"
    print ""
    ran = "Ran: [docs-hygiene:audit-noise (detect.sh)]."
    if (nrows == 0)
      ran = ran " Returned no result: [docs-hygiene/audit-noise/rule-negation-without-positive]."
    print ran
    # Deterministic order: the five shapes that carry no crosswalk row, in the
    # order the skill tables them.
    split("citation ghost-ref preamble enum-list scope-meta", order, " ")
    for (i = 1; i <= 5; i++)
      if (declined[order[i]] > 0)
        printf "Declined candidates: docs-hygiene/audit-noise/rule-%s count=%s reason=no-severity-crosswalk-row\n", \
          order[i], declined[order[i]]
  }
' "$FROM" >"$OUT"

echo "emit-findings.sh: wrote $OUT"

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
# ONLY the `negation` shape is emitted. The five older shapes (citation,
# ghost-ref, preamble, enum-list, scope-meta) carry no severity-crosswalk row,
# and the detector-findings contract admits no row whose tier cannot be looked
# up from one — those stay in the human report. Their rows are counted as
# declined, never silently dropped.
#
# The per-rule Tier/Action cells MIRROR the severity crosswalk in
# docs/conventions/detector-findings/README.md ("The severity crosswalk"); that
# table is the source of truth — a tier change lands there first and is copied
# here, never the reverse.
#
# BODY-SCOPE FENCE, RE-VERIFIED HERE. detect.sh already skips YAML frontmatter,
# but this script recomputes the fence rather than trusting its input, and
# additionally drops any body row whose line quotes a `'trigger phrase'` that
# also appears in the file's own `description:` or `when_to_use:`. The reason is
# plugins/skill-quality/scripts/check-skill.sh:414: it hard-FAILs a dropped
# trigger phrase versus the base ref, so a remediation that edits a description
# or a quoted trigger phrase is an auto-invocation regression. A fence that
# lives only in the caller is one caller away from being bypassed; findings that
# reach an APPLY relay carry it in the writer.
#
# Exit: 0 on success, 2 on usage error, 3 when --from carries no detect.sh
# blocks at all (not scanner output; refusing beats composing from garbage).
# Zero EMITTABLE findings with blocks present still WRITES the file — coverage
# is the payload.
set -euo pipefail

FROM=""
OUT=""
BRANCH=""
CARVEOUT=""

usage() {
  cat <<'EOF'
emit-findings.sh — compose a review-findings file from detect.sh output.

Usage:
  emit-findings.sh --from <detect-output> --out <path> [--branch <b>]
                   [--declined-carveout <n>]

--from is detect.sh output (File:/Finding tier:/Finding shape:/Finding line:/
Finding excerpt: blocks). --out is the CONVENTION-RESOLVED destination; if it
exists, a -2/-3 suffix is appended (non-overwrite naming). --branch defaults to
the current git branch. --declined-carveout records how many negation
candidates the judgment lane dropped on a sanctioned dismissal ground before
this script ran, so that exclusion is counted in ## Surfaces instead of going
unrecorded.

Only `negation` rows are emitted (the one shape carrying a severity-crosswalk
row); all other shapes are counted as declined and left to the human report.
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
  --declined-carveout)
    require_opt_value "$@"
    CARVEOUT="$2"
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

# `branch:` is load-bearing for the consumer: fix-pass-mode.md "Step 1" admits a
# candidate only on an EXACT branch match, so with no branch resolvable there is
# no file the relay could ever match. Refuse rather than write one. This is the
# normal state on a detached-HEAD CI checkout of a PR merge ref.
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

if [[ -n "$CARVEOUT" && ! "$CARVEOUT" =~ ^[0-9]+$ ]]; then
  echo "emit-findings.sh: --declined-carveout takes a non-negative integer" >&2
  exit 2
fi

# A detect.sh block always opens with a `File: ` line. Anything without one is
# not scanner output.
if ! LC_ALL=C grep -qE '^File: .' "$FROM"; then
  echo "emit-findings.sh: $FROM has no detect.sh blocks; not scanner output" >&2
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
# fix-pass-mode.md "Step 1" reads a value only if it is a full ISO-8601 date-time
# carrying an explicit UTC designator (Z) or numeric offset. The colon-free rule
# the convention states elsewhere binds the FILE NAME, never this field.
DATE_UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Repo root, for relativizing Location. The fix action fences each remediation
# to its finding's Location, and an absolute path is not portable to the
# checkout that applies the fix.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"

LC_ALL=C awk \
  -v branch="$BRANCH" -v date_utc="$DATE_UTC" -v repo_root="$REPO_ROOT" -v carveout="$CARVEOUT" '
  # Tier mirror of the severity crosswalk (see header comment). IMPORTANT on
  # severity.md stated-rule limb: docs-hygiene:write-for-agents "Prompt the
  # positive" is the stated rule the text violates.
  function rule_tier() { return "IMPORTANT" }
  function rule_action() {
    return "Rewrite to the positive target the prohibition implies (\"Do not use markdown\" -> \"Compose your response as smoothly flowing prose paragraphs\"). Keep a negation only where the positive form genuinely loses the constraint, and then pair it with the positive in the same sentence. The constraint must survive the edit; only its framing changes."
  }
  # Cell-escaping rule: literal | becomes \| inside Finding/Action cells.
  function esc(s) { gsub(/\|/, "\\|", s); return s }

  # Emit a YAML scalar, quoting ONLY when the plain form would misparse. Git
  # accepts branch names beginning with a YAML indicator: "#foo" reads as a
  # comment (branch becomes empty), and "@foo" / "!foo" / "&foo" / "*foo" and
  # friends are indicators too. The consumer admits a candidate only on an EXACT
  # branch match, so a misparse silently drops every finding for that branch.
  # A plain scalar YAML implicitly TYPES is also unsafe: git accepts branch
  # names like `true`, `null`, `no`, `123` and `2026-08-23`, and a consumer
  # reading those back gets a boolean, a null, a number or a date rather than
  # the exact branch string the relay matches on. Quote them too.
  function yaml_implicit_typed(s,   l) {
    l = tolower(s)
    if (l ~ /^(true|false|yes|no|on|off|null|~)$/) return 1
    if (s ~ /^[+-]?[0-9]+$/) return 1
    if (s ~ /^[+-]?[0-9]*\.[0-9]+([eE][+-]?[0-9]+)?$/) return 1
    if (s ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}/) return 1
    if (s ~ /^0[xXoObB][0-9a-fA-F_]+$/) return 1
    return 0
  }
  function yaml_scalar(s) {
    if (s ~ /^[-?:,\[\]{}#&*!|>%@`"\x27]/ || s ~ /: / || s ~ / #/ || s ~ /^$/ || s ~ /[ \t]$/ || yaml_implicit_typed(s)) {
      gsub(/\\/, "\\\\", s)
      gsub(/"/, "\\\"", s)
      return "\"" s "\""
    }
    return s
  }
  function trim(s) { gsub(/^[ \t]+|[ \t]+$/, "", s); return s }

  # Frontmatter close line for <file>, or 0 when there is none. Recomputed here
  # rather than trusted from the caller (header comment: BODY-SCOPE FENCE).
  # An unclosed leading `---` fences the whole file, the fail-safe direction.
  # Delimiter test deliberately IDENTICAL to this repo authoritative extractor
  # skill_frontmatter::extract (plugins/skill-quality/scripts/skill-frontmatter.sh),
  # which is what check-skill.sh -- the hard-FAIL gate this fence exists to
  # satisfy -- parses frontmatter with. Exact equality against "---" would be
  # STRICTER than that parser, and the mismatch direction is the dangerous one:
  # a delimiter carrying trailing whitespace or a CR is real frontmatter to the
  # gate but invisible here, so the block would be treated as body and the
  # description and when_to_use lines would become emittable.
  function is_fence(s) { return s ~ /^---[[:space:]]*$/ }

  function fm_end(file,   line, n, fmclose, result) {
    if (file in fmcache) return fmcache[file]
    n = 0; fmclose = -1
    while ((getline line < file) > 0) {
      n++
      if (n == 1) { if (!is_fence(line)) { fmclose = 0; break } ; continue }
      if (is_fence(line)) { fmclose = n; break }
    }
    while ((getline line < file) > 0) n++
    result = (fmclose == -1) ? n : fmclose
    close(file)
    fmcache[file] = result
    return result
  }

  # The `description:` / `when_to_use:` text of <file>, for the quoted-trigger fence.
  function descr(file,   line, n, d) {
    if (file in dcache) return dcache[file]
    d = ""; n = 0
    while ((getline line < file) > 0) {
      n++
      sub(/\r$/, "", line)
      if (n == 1 && !is_fence(line)) break
      if (n > 1 && is_fence(line)) break
      if (line ~ /^description:/) d = d " " line
      if (line ~ /^when_to_use:/) d = d " " line
    }
    close(file)
    dcache[file] = d
    return d
  }

  function source_line(file, lno,   line, n) {
    n = 0
    while ((getline line < file) > 0) {
      n++
      if (n == lno) { sub(/\r$/, "", line); close(file); return line }
    }
    close(file)
    return ""
  }

  # A body line that quotes a trigger phrase also present in the description or
  # when_to_use is fenced: its remediation could not be applied without risking
  # the dropped-trigger-phrase regression.
  function quotes_trigger(file, text,   d, n, parts, i, q) {
    d = descr(file)
    if (d == "") return 0
    # Single quote by code point: a literal one cannot be written inside this
    # single-quoted awk program, and \x escapes are not portable across awks.
    n = split(text, parts, sprintf("%c", 39))
    # parts[2], parts[4], ... are the single-quoted spans.
    for (i = 2; i <= n; i += 2) {
      q = trim(parts[i])
      if (length(q) >= 4 && index(d, q) > 0) return 1
    }
    return 0
  }

  # --- block intake ----------------------------------------------------------
  /^File: /          { cur_file = substr($0, 7); next }
  /^Finding shape: /  { cur_shape = substr($0, 16); next }
  /^Finding line: /   { cur_line = substr($0, 15); next }
  /^Finding excerpt: /{ cur_excerpt = substr($0, 18); next }
  /^Finding marker: / { cur_marker = substr($0, 17); next }
  /^Finding tier: /   { next }
  /^Summary /         { next }

  /^---$/ {
    if (cur_file == "" || cur_shape == "") { reset(); next }
    nblocks++

    if (cur_shape != "negation") { declined_nocrosswalk[cur_shape]++; reset(); next }

    if (cur_line + 0 <= fm_end(cur_file)) { declined_frontmatter[cur_shape]++; reset(); next }

    text = source_line(cur_file, cur_line + 0)
    if (text == "") { declined_unreadable[cur_shape]++; reset(); next }

    if (quotes_trigger(cur_file, text)) { declined_trigger[cur_shape]++; reset(); next }

    # OUT-OF-REPO FENCE. Location is contractually repo-relative because the fix
    # action fences each remediation to it. A path outside the working tree
    # would have the fix pass either edit a file outside it or consume the
    # finding without applying it.
    #
    # The prefix test is LEXICAL, so a `..` segment defeats it: `/repo/../x.md`
    # starts with `/repo/` while resolving outside the repository, and the row
    # would enter the relay carrying a traversing Location. Any path holding a
    # `..` segment is therefore declined outright — fail closed, since this
    # fence exists to be defensive about its own input. Residual, recorded
    # rather than implied: a symlink INSIDE the repo pointing outside it still
    # resolves past this test, which needs a canonicalizing syscall awk has no
    # portable access to.
    abs = cur_file
    if (substr(abs, 1, 1) != "/") abs = repo_root "/" cur_file
    if (abs ~ /(^|\/)\.\.(\/|$)/) { declined_outofrepo[cur_shape]++; reset(); next }
    if (repo_root == "" || index(abs, repo_root "/") != 1) { declined_outofrepo[cur_shape]++; reset(); next }
    loc = substr(abs, length(repo_root) + 2)

    rows[++nemit] = "| " rule_tier() " | high | " loc ":" cur_line " | docs-hygiene:audit-noise | " \
      esc("docs-hygiene/audit-noise/rule-negation-without-positive prohibition=\"" fired_marker(cur_marker, text) "\" with no positive alternative in the sentence -- " trim(cur_excerpt)) \
      " | " esc(rule_action()) " |"
    seen++
    reset()
    next
  }

  function reset() { cur_file = ""; cur_shape = ""; cur_line = ""; cur_excerpt = ""; cur_marker = "" }

  # Which prohibition fired, in the run own values (never the rule restated).
  # PREFER the marker the scanner supplied: it comes from the sentence that
  # actually triggered, so a line whose FIRST sentence is carved out
  # ("Never commit a secret. Do not use markdown.") reports the second
  # sentence marker rather than pointing review at the guardrail. The
  # whole-line scan below is only the fallback for detector output predating
  # the `Finding marker:` field, and carries that first-match imprecision.
  function fired_marker(supplied, text,   i, pats, n, lower) {
    if (supplied != "") return supplied
    lower = tolower(text)
    n = split("never|do not|must not|should not|avoid", pats, "|")
    for (i = 1; i <= n; i++) if (index(lower, pats[i]) > 0) return pats[i]
    if (index(lower, "don") > 0) return "dont"
    return "(prohibition)"
  }

  END {
    printf "---\ntype: review-findings\ndate: %s\nbranch: %s\n---\n\n", date_utc, yaml_scalar(branch)
    print "## Findings"
    print ""
    print "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
    print "|------|------|------------|----------|------------|---------|--------|"
    for (i = 1; i <= nemit; i++) printf "| %d %s\n", i, rows[i]
    print ""
    print "## Surfaces"
    print ""
    ran = "Ran: [docs-hygiene:audit-noise (detect.sh)]."
    if (seen == 0) ran = ran " Returned no result: [docs-hygiene/audit-noise/rule-negation-without-positive]."
    print ran
    printf "Detect blocks read: %d. Emitted: %d.\n", nblocks, nemit
    for (k in declined_nocrosswalk)
      printf "Declined candidates: %s count=%d reason=no-severity-crosswalk-row (human report only)\n", k, declined_nocrosswalk[k]
    for (k in declined_frontmatter)
      printf "Declined candidates: %s count=%d reason=frontmatter (body-scope fence)\n", k, declined_frontmatter[k]
    for (k in declined_trigger)
      printf "Declined candidates: %s count=%d reason=quoted-trigger-phrase (body-scope fence)\n", k, declined_trigger[k]
    for (k in declined_outofrepo)
      printf "Declined candidates: %s count=%d reason=outside-repo-root (Location must be repo-relative; human report only)\n", k, declined_outofrepo[k]
    for (k in declined_unreadable)
      printf "Declined candidates: %s count=%d reason=source-line-unreadable\n", k, declined_unreadable[k]
    # The judgment lane drops candidates on a sanctioned dismissal ground (a
    # document ABOUT the pattern, a shape-definition example matching its own
    # pattern) before this script sees them, so it reports their count here
    # rather than letting the exclusion go unrecorded — a decline this contract
    # promises is never silent.
    if (carveout != "")
      printf "Declined candidates: negation count=%s reason=judgment-lane-dismissal (SKILL.md \"Dismissal grounds\")\n", carveout
  }
' "$FROM" >"$OUT"

echo "emit-findings.sh: wrote $OUT"

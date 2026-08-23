#!/usr/bin/env bash
# Compose a conforming review-findings file from instruction-scan.sh output.
#
#   emit-findings.sh --from <scan-output> --out <path> [--branch <b>]
#
# The FINDINGS HOME is never resolved here: the caller (the audit-instructions
# skill) resolves it through the detector-findings convention's rung order and
# its fetch-and-refuse gate, then hands the resolved path in as --out. This
# script owns only the deterministic composition.
#
# ONLY the I28 and I29 families are emitted. Every other check id
# instruction-scan.sh marks (I6, I8-a/b/c, I10, I23, I25, I27) has no
# severity-crosswalk row, and the detector-findings contract admits no row
# whose tier cannot be looked up from one — those stay in the human report.
# Rows for them are counted as declined, never silently dropped. I29 rows
# come from restatement-scan.py and are concatenated onto the same --from
# stream.
#
# The per-rule Tier/Action cells MIRROR the severity crosswalk in
# docs/conventions/detector-findings/README.md ("The severity crosswalk"); that
# table is the source of truth — a tier change lands there first and is copied
# here, never the reverse.
#
# BODY-SCOPE FENCE, RE-VERIFIED HERE. instruction-scan.sh --body-only already
# drops frontmatter hits, but this script recomputes the fence rather than
# trusting its input, and additionally drops any body row whose line quotes a
# `'trigger phrase'` that also appears in the file's own `description:`. The
# reason is check-skill.sh check 3: it hard-FAILs a dropped trigger phrase versus
# the base ref, so a remediation that edits a description or a quoted trigger
# phrase is an auto-invocation regression. A fence that lives only in the caller
# is one caller away from being bypassed; findings that reach an APPLY relay
# carry it in the writer.
#
# Exit: 0 on success, 2 on usage error, 3 when --from carries no scan rows at all
# (not scanner output; refusing beats composing from garbage). Zero EMITTABLE
# findings with scan rows present still WRITES the file — coverage is the payload.
set -euo pipefail

FROM=""
OUT=""
BRANCH=""
CARVEOUT=""

usage() {
  cat <<'EOF'
emit-findings.sh — compose a review-findings file from instruction-scan.sh output.

Usage:
  emit-findings.sh --from <scan-output> --out <path> [--branch <b>]
                   [--declined-carveout <n>]

--from is instruction-scan.sh output (`file:line:check-id` rows); run it with
--body-only. --out is the CONVENTION-RESOLVED destination; if it exists, a
-2/-3 suffix is appended (non-overwrite naming). --branch defaults to the
current git branch. --declined-carveout records how many I28/I29 candidates the
model lane dropped for a criteria carve-out before this script ran, so that
exclusion is counted in ## Surfaces instead of going unrecorded.

Only I28-a / I28-b / I29-a / I29-b rows are emitted (the families carrying
severity-crosswalk rows); all other check ids are counted as declined and left
to the human report.
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
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

# A scan row is `<path>:<line>:<check-id>`. Anything with no such row is not
# scanner output.
if ! LC_ALL=C grep -qE '^.+:[0-9]+:I[0-9]+(-[a-c])?$' "$FROM"; then
  echo "emit-findings.sh: $FROM has no instruction-scan.sh rows; not scanner output" >&2
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

# Repo root, for relativizing Location. The fix action fences each remediation to
# its finding's Location, and an absolute path is not portable to the checkout
# that applies the fix.
#
# One directory has several SPELLINGS on Git Bash, and matching the wrong one
# silently declines a real in-repo finding — this producer FAILS CLOSED, so a
# path it cannot prove is under the root never reaches the relay. Measured:
# `git rev-parse --show-toplevel` answers Git Bash's Windows spelling of the same temp repo
# while the caller reached the same directory as `/tmp/t/repo`.
#
# The PRIMARY anchor is derived from the caller's own `pwd` by removing the
# sub-path git reports for it. The git-reported forms stay as fallbacks.
# (The ai-slop sibling fails OPEN on the same mismatch — Location stays
# absolute and nothing reports it.)
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

if [[ -n "$CARVEOUT" && ! "$CARVEOUT" =~ ^[0-9]+$ ]]; then
  echo "emit-findings.sh: --declined-carveout takes a non-negative integer" >&2
  exit 2
fi

LC_ALL=C awk \
  -v branch="$BRANCH" -v date_utc="$DATE_UTC" -v repo_root="$REPO_ROOT" \
  -v repo_root_alt="$REPO_ROOT_ALT" -v repo_root_pwd="$REPO_ROOT_PWD" -v carveout="$CARVEOUT" '
  function rule_id(id) {
    if (id == "I28-a") return "claude-config/audit-instructions/rule-coercive-emphasis"
    if (id == "I28-b") return "claude-config/audit-instructions/rule-blanket-tool-default"
    if (id == "I29-a") return "claude-config/audit-instructions/rule-description-restatement"
    if (id == "I29-b") return "claude-config/audit-instructions/rule-sibling-restatement"
    return ""
  }
  # Tier mirror of the severity crosswalk (see header comment). I28 and I29
  # are IMPORTANT on the degradation-with-a-named-trigger limb.
  function rule_tier(id) { return "IMPORTANT" }
  function rule_action(id) {
    if (id == "I28-a")
      return "Downgrade the emphasis, never the directive: restate as normal conditional phrasing (\"Use this tool when ...\"). The directive must survive the edit verbatim, apart from capitalization forced by dropping a leading wrapper; only its volume changes."
    if (id == "I28-b")
      return "Replace the blanket default with the targeted condition it stood in for (\"Use [tool] when it would ...\"). The condition is the payload; do not delete the instruction."
    return "Cut the body restatement. Do not edit the description, when_to_use, or any quoted trigger phrase — the always-in-context field stays; only the body copy that restates it is removed."
  }
  # Cell-escaping rule: literal | becomes \| inside Finding/Action cells.
  #
  # IDEMPOTENT. A naive gsub double-escapes a pipe the SOURCE already escaped:
  # `a \| b` becomes `a \\| b`, which GFM reads as a literal backslash followed
  # by a LIVE delimiter — the cell splits and the fix action misreads the row.
  # This repo writes literal `\|` in its own tables, so the case is real rather
  # than theoretical. Escape by the parity of the complete backslash run before
  # each pipe: an odd count already escapes the delimiter; an even count
  # (including zero, and `\\|`) leaves it live in GFM and needs one more `\`.
  function esc(s,    out, i, n, c, bs) {
    out = ""
    n = length(s)
    i = 1
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
        out = out "\\|"
        i++
      } else {
        out = out c
        i++
      }
    }
    return out
  }

  # Prefer the caller pwd spelling, then git toplevel, then cd-then-pwd.
  # Empty return means the path is not under any known spelling of the root
  # (fail closed — this producer pre-fix mode on a spelling mismatch).
  function relativize_in_repo(p) {
    if (repo_root_pwd != "" && index(p, repo_root_pwd "/") == 1)
      return substr(p, length(repo_root_pwd) + 2)
    if (repo_root != "" && index(p, repo_root "/") == 1)
      return substr(p, length(repo_root) + 2)
    if (repo_root_alt != "" && index(p, repo_root_alt "/") == 1)
      return substr(p, length(repo_root_alt) + 2)
    return ""
  }

  # Emit a YAML scalar, quoting ONLY when the plain form would misparse. Git
  # accepts branch names beginning with a YAML indicator: "#foo" reads as a
  # comment (branch becomes empty), and "@foo" / "!foo" / "&foo" / "*foo" and
  # friends are indicators too. The consumer admits a candidate only on an EXACT
  # branch match, so a misparse silently drops every finding for that branch.
  # Quoting is deliberately conditional rather than unconditional: an ordinary
  # branch name keeps a byte-identical plain scalar, so this cannot perturb the
  # common path or diverge from the sibling ai-slop producer on it.
  function yaml_scalar(s) {
    if (s ~ /^[-?:,\[\]{}#&*!|>%@`"\x27]/ || s ~ /: / || s ~ / #/ || s ~ /^$/ || s ~ /[ \t]$/) {
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
  # Delimiter test, deliberately IDENTICAL to this repo authoritative extractor
  # skill_frontmatter::extract (plugins/skill-quality/scripts/skill-frontmatter.sh),
  # which is what check-skill.sh -- the hard-FAIL gate this whole fence exists to
  # satisfy -- parses frontmatter with. Exact equality against "---" is STRICTER
  # than that parser, and the direction of the mismatch is the dangerous one: a
  # delimiter carrying trailing whitespace or a CR is real frontmatter to the
  # gate but invisible here, so the block would be treated as body and the
  # description and when_to_use lines would become emittable. Three
  # implementations of "is this the fence" must agree or the fence is only as
  # strong as the loosest reader. [[:space:]] covers the CR case too.
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

  # The `description:` value of <file>, for the quoted-trigger-phrase fence.
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

  # Read line <lno> of <file>.
  function source_line(file, lno,   line, n) {
    n = 0
    while ((getline line < file) > 0) {
      n++
      if (n == lno) { sub(/\r$/, "", line); close(file); return line }
    }
    close(file)
    return ""
  }

  # Which marker fired, in the run own values (never the rule definition restated).
  function fired_marker(id, text,   i, m, pats_a, pats_b, n) {
    if (id == "I28-a") {
      n = split("CRITICAL:|IMPORTANT:|You MUST|you MUST|MANDATORY|ALWAYS use|NEVER skip", pats_a, "|")
      for (i = 1; i <= n; i++) if (index(text, pats_a[i]) > 0) return "marker=\"" pats_a[i] "\""
      return "marker=(forced-compliance emphasis)"
    }
    if (id == "I28-b") {
      n = split("default to using|default to running|default to calling|if in doubt, use|if in doubt use|always use|use even when", pats_b, "|")
      for (i = 1; i <= n; i++) if (index(tolower(text), pats_b[i]) > 0) return "phrase=\"" pats_b[i] "\""
      return "phrase=(blanket tool default)"
    }
    if (id == "I29-a") return "shape=\"description-restatement\""
    return "shape=\"sibling-section-restatement\""
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

  # --- row intake ------------------------------------------------------------
  /^.+:[0-9]+:I[0-9]+(-[a-c])?$/ {
    nrows++
    # Split from the RIGHT: a path may contain colons, the last two fields never do.
    id = $0; sub(/^.*:/, "", id)
    rest = $0; sub(/:[^:]*$/, "", rest)
    lno = rest; sub(/^.*:/, "", lno)
    file = rest; sub(/:[^:]*$/, "", file)

    rid = rule_id(id)
    if (rid == "") { declined_nocrosswalk[id]++; next }

    if (lno + 0 <= fm_end(file)) { declined_frontmatter[id]++; next }

    text = source_line(file, lno + 0)
    if (text == "") { declined_unreadable[id]++; next }

    if (quotes_trigger(file, text)) { declined_trigger[id]++; next }

    # OUT-OF-REPO FENCE. The Phase A inventory spans user-level surfaces under
    # CLAUDE_CONFIG_DIR (default ~/.claude) as well as repo-owned ones, but
    # Location is contractually repo-relative because the fix action fences each
    # remediation to it. A user-level hit would otherwise enter the relay
    # carrying an absolute path, where the fix pass either edits a file outside
    # the working tree or consumes the finding without applying it. Neither is
    # acceptable, so such rows are declined here and stay in the human report.
    loc = relativize_in_repo(file)
    if (loc == "") { declined_outofrepo[id]++; next }

    excerpt = trim(text)
    if (length(excerpt) > 160) excerpt = substr(excerpt, 1, 157) "..."

    rows[++nemit] = "| " rule_tier(id) " | high | " loc ":" lno " | claude-config:audit-instructions | " \
      esc(rid " " fired_marker(id, text) " -- " excerpt) " | " esc(rule_action(id)) " |"
    seen[id]++
    next
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
    ran = "Ran: [claude-config:audit-instructions (instruction-scan.sh --body-only)]."
    zero = ""
    if (!("I28-a" in seen)) zero = "claude-config/audit-instructions/rule-coercive-emphasis"
    if (!("I28-b" in seen))
      zero = zero (zero == "" ? "" : ", ") "claude-config/audit-instructions/rule-blanket-tool-default"
    if (!("I29-a" in seen))
      zero = zero (zero == "" ? "" : ", ") "claude-config/audit-instructions/rule-description-restatement"
    if (!("I29-b" in seen))
      zero = zero (zero == "" ? "" : ", ") "claude-config/audit-instructions/rule-sibling-restatement"
    if (zero != "") ran = ran " Returned no result: [" zero "]."
    print ran
    printf "Scan rows read: %d. Emitted: %d.\n", nrows, nemit
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
    # The model lane drops carve-out candidates (destructive/security gate,
    # stated hard precondition, document about the pattern) before this script
    # sees them, so it reports their count here rather than letting the
    # exclusion go unrecorded — a decline this file promises is never silent.
    if (carveout != "")
      printf "Declined candidates: I28 count=%s reason=criteria-carve-out (model lane; see reference/criteria.md I28)\n", carveout
  }
' "$FROM" >"$OUT"

echo "emit-findings.sh: wrote $OUT"

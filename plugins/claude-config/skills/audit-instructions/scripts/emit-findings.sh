#!/usr/bin/env bash
# Compose a conforming review-findings file from instruction-scan.sh output and
# from model-lane findings.
#
#   emit-findings.sh [--from <scan-output>] [--from-lane <lane-rows>] --out <path>
#                    [--branch <b>]
#
# The FINDINGS HOME is never resolved here: the caller (the audit-instructions
# skill) resolves it from the memory root per the detector-findings convention
# and its fetch-and-refuse gate, then hands the resolved path in as --out. This
# script owns only the deterministic composition.
#
# TWO INTAKE PATHS, each admitting only the rules that carry a severity-crosswalk
# row and are selected on that path:
#   --from       scanner-fed: I28-a/b (instruction-scan.sh) and I29-a/b
#                (restatement-scan.py, concatenated onto the same stream).
#                Confidence `high`: a deterministic detector fired.
#   --from-lane  lane-fed: I30, I31, I32, I33, which no scanner seeds; the rows
#                are the Phase C-surviving lane findings, in the same
#                `file:line:check-id` shape. Confidence is omitted: a judgment
#                selected the row, and the contract has no grade below `high`
#                for a producer that performs no reviewer verification.
#                I31 and I33 are admitted for a file inside a skill directory
#                (skills/<name>/...) or in a context/, reference/, or references/
#                directory; I33 excludes SKILL.md. I32 is CRITICAL on a path
#                under plugins/ and IMPORTANT anywhere else.
# A row on the wrong path is declined with the path it belongs to. Every other
# check id (I6, I8-a/b/c/f, I10, I23, I25, I27, ...) has no crosswalk row, and
# the detector-findings contract admits no row whose tier cannot be looked up
# from one — those stay in the human report. Rows for them are counted as
# declined, never silently dropped. A line that is not a row at all (suffix
# outside [a-f], prose, blank) is counted as reason=unparsable-row, never
# omitted from both the rows-read count and every Declined line.
#
# Every emitted row carries its audit-pass finding identity in the Finding cell
# (`finding_id=<16 hex>`), derived by finding-ids.sh beside this script; a row
# it cannot identify is declined reason=identity-unresolved rather than emitted
# without one.
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
# Exit: 0 on success, 2 on usage error, 3 when neither input carries a single
# row (not scanner or lane output; refusing beats composing from garbage). Zero
# EMITTABLE findings with rows present still WRITES the file — coverage is the
# payload.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FROM=""
FROM_LANE=""
OUT=""
BRANCH=""
CARVEOUT=""
RESIDENCY=""

usage() {
  cat <<'EOF'
emit-findings.sh — compose a review-findings file from instruction-scan.sh
output and model-lane findings.

Usage:
  emit-findings.sh [--from <scan-output>] [--from-lane <lane-rows>] --out <path>
                   [--branch <b>] [--declined-carveout <n>]
                   [--declined-residency <n>]

At least one of --from and --from-lane is required. --from is
instruction-scan.sh output (`file:line:check-id` rows); run it with
--body-only. --from-lane is the lane findings for I30, I31, I32, and I33 that
survived Phase C, one `file:line:check-id` row each, the line being the
flagged sentence's first line. I31 and I33 rows must sit in a skill directory or
a context/, reference/, or references/ directory (I33 not in SKILL.md). --out is the CONVENTION-RESOLVED destination; if it exists, a
-2/-3 suffix is appended (non-overwrite naming). --branch defaults to the
current git branch. --declined-carveout records how many I28/I29 candidates the
model lane dropped for a criteria carve-out before this script ran, so that
exclusion is counted in ## Surfaces instead of going unrecorded.
--declined-residency records how many I28/I29 candidates the report holds as
RESIDENCY-UNRESOLVED (their surface's residency was never established), which
propose no applicable edit and so are held out of --from the same way.

Only I28-a / I28-b / I29-a / I29-b rows (from --from) and I30 / I31 / I32 /
I33 rows (from --from-lane) are emitted, the families carrying
severity-crosswalk rows; all other check ids are counted as declined and left
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
  --from-lane)
    require_opt_value "$@"
    FROM_LANE="$2"
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
  --declined-residency)
    require_opt_value "$@"
    RESIDENCY="$2"
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

[[ (-n "$FROM" || -n "$FROM_LANE") && -n "$OUT" ]] || {
  usage >&2
  exit 2
}
if [[ -n "$FROM" && ! -f "$FROM" ]]; then
  echo "emit-findings.sh: --from file not found: $FROM" >&2
  exit 2
fi
if [[ -n "$FROM_LANE" && ! -f "$FROM_LANE" ]]; then
  echo "emit-findings.sh: --from-lane file not found: $FROM_LANE" >&2
  exit 2
fi
# awk tells the two streams apart by FILENAME, so one file cannot be both.
if [[ -n "$FROM" && "$FROM" == "$FROM_LANE" ]]; then
  echo "emit-findings.sh: --from and --from-lane name the same file; the paths admit different rules" >&2
  exit 2
fi
if [[ -z "$BRANCH" ]]; then
  BRANCH="$(git branch --show-current 2>/dev/null || true)"
  [[ -n "$BRANCH" ]] || {
    echo "emit-findings.sh: no --branch and no current git branch" >&2
    exit 2
  }
fi

# A row is `<path>:<line>:<check-id>`. Input with no such row is neither scanner
# nor lane output. Strip a trailing CR first so an all-CRLF file with a matching
# row is recognized rather than refused — the same strip the awk intake applies
# before its pattern match.
ROW_ERE='^.+:[0-9]+:I[0-9]+(-[a-f])?$'
INPUTS=()
[[ -n "$FROM" ]] && INPUTS+=("$FROM")
[[ -n "$FROM_LANE" ]] && INPUTS+=("$FROM_LANE")
if ! LC_ALL=C sed $'s/\r$//' "${INPUTS[@]}" | LC_ALL=C grep -E "$ROW_ERE" >/dev/null; then
  echo "emit-findings.sh: ${INPUTS[*]} carries no instruction-scan.sh or lane rows" >&2
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
#
# A scan row may also carry a path that is not absolute at all:
# instruction-scan.sh echoes the caller's own argument, and naming a repo-owned
# file relatively is the ordinary invocation. Such a path is resolved against
# CALLER_PWD, the same directory the awk body reads the file from.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
REPO_ROOT_ALT=""
REPO_ROOT_PWD=""
CALLER_PWD="$(pwd)"
if [[ -n "$REPO_ROOT" ]]; then
  REPO_ROOT_ALT="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || REPO_ROOT_ALT=""
  [[ "$REPO_ROOT_ALT" == "$REPO_ROOT" ]] && REPO_ROOT_ALT=""
  git_prefix="$(git rev-parse --show-prefix 2>/dev/null || true)"
  git_prefix="${git_prefix%/}"
  if [[ -z "$git_prefix" ]]; then
    REPO_ROOT_PWD="$CALLER_PWD"
  elif [[ "$CALLER_PWD" == */"$git_prefix" ]]; then
    REPO_ROOT_PWD="${CALLER_PWD%/"$git_prefix"}"
  fi
  [[ "$REPO_ROOT_PWD" == "$REPO_ROOT" || "$REPO_ROOT_PWD" == "$REPO_ROOT_ALT" ]] && REPO_ROOT_PWD=""
fi

if [[ -n "$CARVEOUT" && ! "$CARVEOUT" =~ ^[0-9]+$ ]]; then
  echo "emit-findings.sh: --declined-carveout takes a non-negative integer" >&2
  exit 2
fi
if [[ -n "$RESIDENCY" && ! "$RESIDENCY" =~ ^[0-9]+$ ]]; then
  echo "emit-findings.sh: --declined-residency takes a non-negative integer" >&2
  exit 2
fi

# I29 rows come from restatement-scan.py, a NATIVE Windows interpreter. MSYS
# converts its argv on the way in and the scanner echoes what it received:
# backslash separators, and 8.3 SHORT components (`<drive>:\Users\<SHORT~1>\...`) for
# every directory that has one. None of the three anchors above is spelled that
# way, so such a row was declined as outside the root -- fail closed, and on a
# host whose checkout sits under a short-named path that silently dropped every
# restatement finding into the human-report-only column.
#
# `cygpath -l -m` answers the long, forward-slash spelling of such a path, which
# is the toplevel form the anchors are written in. The expansion cannot be done
# from the anchor side instead: `cygpath -m -s` also shortens components MSYS
# left long, so the two spellings do not meet in the middle. The path travels to
# cygpath through a file this script owns rather than through a command line, so
# no scanner-supplied text is ever interpolated into a shell word.
#
# Where cygpath is absent -- Linux CI, where neither shape occurs -- awk falls
# back to separator normalization alone and the anchors work as they always did.
CYGPATH_BIN="$(command -v cygpath 2>/dev/null || true)"
CYGPATH_IO=""
if [[ -n "$CYGPATH_BIN" ]]; then
  CYGPATH_IO="$(mktemp 2>/dev/null || true)"
  [[ -n "$CYGPATH_IO" ]] || CYGPATH_BIN=""
fi

# Identity for every row an intake path could admit, keyed by the row verbatim.
# Only the admitted families are identified: a scan over a large corpus carries
# thousands of rows for families that never reach this file.
IDMAP="$(mktemp)"
trap 'rm -f "$IDMAP" ${CYGPATH_IO:+"$CYGPATH_IO"}' EXIT
LC_ALL=C sed $'s/\r$//' "${INPUTS[@]}" |
  LC_ALL=C grep -E ':I(28-[ab]|29-[ab]|3[0-3])$' |
  bash "$SCRIPT_DIR/finding-ids.sh" >"$IDMAP" 2>/dev/null || true

LC_ALL=C awk \
  -v branch="$BRANCH" -v date_utc="$DATE_UTC" -v repo_root="$REPO_ROOT" \
  -v repo_root_alt="$REPO_ROOT_ALT" -v repo_root_pwd="$REPO_ROOT_PWD" \
  -v caller_pwd="$CALLER_PWD" -v carveout="$CARVEOUT" -v residency="$RESIDENCY" \
  -v cygpath_bin="$CYGPATH_BIN" -v cygpath_io="$CYGPATH_IO" \
  -v idmap="$IDMAP" -v lane_file="$FROM_LANE" -v have_scan="${FROM:+1}" '
  BEGIN {
    while ((getline line < idmap) > 0) {
      if (substr(line, 1, 1) == "#") continue
      split(line, idf, "\t")
      fid[idf[1]] = idf[2]
    }
    close(idmap)
  }
  function rule_id(id) {
    if (id == "I28-a") return "claude-config/audit-instructions/rule-coercive-emphasis"
    if (id == "I28-b") return "claude-config/audit-instructions/rule-blanket-tool-default"
    if (id == "I29-a") return "claude-config/audit-instructions/rule-description-restatement"
    if (id == "I29-b") return "claude-config/audit-instructions/rule-sibling-restatement"
    if (id == "I30") return "claude-config/audit-instructions/rule-trigger-less-stamp"
    if (id == "I31") return "claude-config/audit-instructions/rule-migration-relative-phrasing"
    if (id == "I32") return "claude-config/audit-instructions/rule-route-to-absent-skill"
    if (id == "I33") return "claude-config/audit-instructions/rule-spoke-self-description"
    return ""
  }
  function lane_rule(id) { return (id == "I30" || id == "I31" || id == "I32" || id == "I33") }
  # Tier mirror of the severity crosswalk (see header comment). I32 is
  # CRITICAL on the marketplace arm (a path under plugins/, catalog severity
  # error) and IMPORTANT on the user and project arm (catalog severity warning).
  # I33 is SUGGESTION, and every other emitted rule is IMPORTANT.
  function rule_tier(id, loc) {
    if (id == "I32") return (loc ~ /^plugins\//) ? "CRITICAL" : "IMPORTANT"
    if (id == "I33") return "SUGGESTION"
    return "IMPORTANT"
  }
  function tier_rank(t) { return (t == "CRITICAL") ? 0 : (t == "IMPORTANT") ? 1 : 2 }
  # Where history cut from a spoke belongs: the owning plugin CHANGELOG, or the
  # repository one for a surface outside plugins/.
  function changelog_of(loc,   c) {
    if (loc ~ /^plugins\/[^\/]+\//) {
      c = loc
      sub(/^plugins\//, "", c)
      sub(/\/.*$/, "", c)
      return "plugins/" c "/CHANGELOG.md"
    }
    return "CHANGELOG.md"
  }
  # The skill hub a spoke belongs to: the SKILL.md of the nearest ancestor
  # directory that holds one. The I33 remediation can land there, so its Action
  # names it. A file no skill owns (one a memory surface points at) has no hub.
  function hub_of(file, loc,   base, h, probe, probe_line) {
    base = (length(file) >= length(loc) && substr(file, length(file) - length(loc) + 1) == loc) \
      ? substr(file, 1, length(file) - length(loc)) : (repo_root_pwd != "" ? repo_root_pwd : repo_root) "/"
    h = loc
    while (sub(/\/?[^\/]+$/, "", h) && h != "") {
      probe = base h "/SKILL.md"
      if ((getline probe_line < probe) >= 0) { close(probe); return h "/SKILL.md" }
    }
    return ""
  }
  function rule_action(id, loc, file,   hub) {
    if (id == "I28-a")
      return "Downgrade the emphasis, never the directive: restate as normal conditional phrasing (\"Use this tool when ...\"). The directive must survive the edit verbatim, apart from capitalization forced by dropping a leading wrapper; only its volume changes."
    if (id == "I28-b")
      return "Replace the blanket default with the targeted condition it stood in for (\"Use [tool] when it would ...\"). The condition is the payload; do not delete the instruction."
    if (id == "I30")
      return "Add the recheck trigger as an observable event (a release note naming the flag, a fetch no longer carrying the quoted span, a version floor moving), or point the stamp at the dated owner record that carries one. Keep the claim, its basis, and its date; the stamp stays."
    if (id == "I31")
      return "Restate the sentence as the current rule and its reason in the present tense; the rule itself survives, and only its framing against a prior version changes. Remediation target for any history worth keeping: " changelog_of(loc) " or an ADR, never this spoke."
    if (id == "I32")
      return "Name the skill that exists, or describe the capability by class per the seam-phrasing convention. Keep the routing sentence; the route is repointed, never left to nowhere."
    if (id == "I33") {
      hub = hub_of(file, loc)
      return "Delete the opener that describes the role or loading of this spoke; the content below it stays. Remediation target when the index row of the hub does not already carry the loading condition: " (hub == "" ? "the surface that points at this file" : hub) ", where that condition is added."
    }
    return "Cut the body restatement. Do not edit the description, when_to_use, or any quoted trigger phrase — the always-in-context field stays; only the body copy that restates it is removed."
  }
  # The surfaces a lane rule is defined over. I31 and I33 apply to any file
  # inside a skill directory (skills/<name>/...) and to any file in a context/,
  # reference/, or references/ directory, which is where a file a memory surface
  # points at lives. I33 excludes a SKILL.md, the hub whose index carries the
  # loading condition. A row elsewhere is outside the scope of the remedy and is
  # declined, never emitted.
  function in_rule_surfaces(id, loc) {
    if (id != "I31" && id != "I33") return 1
    if (id == "I33" && loc ~ /(^|\/)SKILL\.md$/) return 0
    return (loc ~ /(^|\/)skills\/[^\/]+\/.+/ || loc ~ /(^|\/)(context|reference|references)\/[^\/]+$/)
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

  # is_absolute(p): true for every absolute spelling that can reach an anchor.
  # A POSIX `/`-rooted path, a UNC or root-relative backslash path, and a
  # drive-letter path — the last being exactly what `git rev-parse
  # --show-toplevel` answers under Git Bash, so it is the form the anchors
  # themselves are written in. Testing only the leading `/` would read
  # `D:/repo/doc.md` as relative and join it to the calling directory,
  # declining a row that relativizes correctly today. The `\`-rooted and
  # drive-letter half is is_win_absolute; only the POSIX root is added here.
  function is_absolute(p) {
    if (substr(p, 1, 1) == "/") return 1
    return is_win_absolute(p)
  }

  # Prefer the caller pwd spelling, then git toplevel, then cd-then-pwd.
  # Empty return means the path is not under any known spelling of the root
  # (fail closed).
  #
  # A path that is NOT absolute is resolved against the calling directory,
  # because that is the directory this script already read the file from:
  # fm_end(), source_line(), and quotes_trigger() each getline the path as
  # written, so by the time control reaches here the excerpt in hand came out of
  # caller_pwd/p. Anchoring the Location anywhere else would have the row name a
  # different file than the one it quotes — a silent corruption in place of a
  # silent drop. (The docs-hygiene sibling joins to the repo root instead, and is
  # right to: its detector emits paths already relative to that root, where
  # instruction-scan.sh echoes the argument it was handed, verbatim.)
  #
  # The anchor tests are LEXICAL, so a `..` segment defeats them:
  # `<root>/../outside.md` starts with `<root>/` while resolving outside the
  # repository, and would enter the relay carrying a traversing Location for the
  # fix pass to resolve outside the working tree. Any path holding a `..`
  # segment is refused outright — fail closed, the direction this fence exists
  # to hold. Residual, recorded rather than implied: a symlink inside the
  # repository pointing outside it still resolves past this test, which needs a
  # canonicalizing syscall awk has no portable access to.
  #
  # `is_absolute` already treats `\` as a separator (Git Bash / Windows). A
  # slash-only `..` test would admit `..\outside.md`: joined as
  # `<pwd>/..\outside.md`, the `..` is followed by `\` rather than `/` or
  # end-of-string, the prefix check still succeeds, and Location becomes a
  # traversing spelling. Separate regexes, not a bracket class holding both
  # delimiters: the runner awk is mawk.
  function has_dotdot_segment(p) {
    if (p ~ /(^|\/)\.\.(\/|$)/) return 1
    if (p ~ /(^|\\)\.\.(\\|$)/) return 1
    if (p ~ /\/\.\.\\/) return 1
    if (p ~ /\\\.\.\//) return 1
    return 0
  }

  # is_win_absolute(p): the drive-letter and UNC subset of is_absolute -- the
  # only shapes whose separators are backslashes and whose components can be 8.3
  # short names. A POSIX path is deliberately excluded: on Linux a backslash is
  # an ordinary filename byte, and rewriting it there would corrupt a Location
  # rather than repair one.
  #
  # Written with substr rather than a bracket expression holding `/` and `\`:
  # the runner awk is mawk (see the 0.39.3 changelog entry), and an unescaped
  # delimiter inside a bracketed regex literal is where the dialects part.
  function is_win_absolute(p,   c1) {
    c1 = substr(p, 1, 1)
    if (c1 == "\\") return 1
    if (c1 !~ /^[A-Za-z]$/) return 0
    if (substr(p, 2, 1) != ":") return 0
    return (substr(p, 3, 1) == "/" || substr(p, 3, 1) == "\\")
  }

  # Re-spell a Windows path in the long, forward-slash form the anchors use.
  # Cached per distinct input: a row set names few files and each miss costs a
  # process. Falls back to separator normalization when cygpath is unavailable
  # or answers nothing, which leaves an already-long path correct and a short
  # one exactly as declinable as it is today.
  function win_long(p,   out, cmd) {
    if (p in wincache) return wincache[p]
    out = ""
    if (cygpath_bin != "" && cygpath_io != "") {
      printf "%s\n", p > cygpath_io
      close(cygpath_io)
      cmd = cygpath_bin " -l -m -f " "\047" cygpath_io "\047" " 2>/dev/null"
      if ((cmd | getline out) <= 0) out = ""
      close(cmd)
    }
    if (out == "") { out = p; gsub(/\\/, "/", out) }
    wincache[p] = out
    return out
  }

  function relativize_in_repo(p) {
    if (is_win_absolute(p)) p = win_long(p)
    if (!is_absolute(p)) {
      sub(/^\.\//, "", p)
      sub(/^\.\\/, "", p)
      p = caller_pwd "/" p
    }
    gsub(/\/\.\//, "/", p)
    if (has_dotdot_segment(p)) return ""
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

  # One Declined line per check id in <counts>, carrying <reason> verbatim.
  function report_declined(counts, reason,   k) {
    for (k in counts)
      printf "Declined candidates: %s count=%d reason=%s\n", k, counts[k], reason
  }

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
    # fmclose == -1 only when the loop ran to EOF, so n is already the line
    # count there: an unclosed leading `---` fences the whole file.
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
  function fired_marker(id, text,   i, pats_a, pats_b, n, t) {
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
    if (id == "I30") return "shape=\"stamp-without-recheck-trigger\""
    if (id == "I31") return "shape=\"migration-relative-phrasing\""
    if (id == "I32") {
      # With more than one candidate the writer cannot tell which one is absent.
      t = text
      if (gsub(/\/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*/, "", t) + gsub(/`[a-z][a-z0-9-]*:[a-z][a-z0-9-]*`/, "", t) > 1)
        return "shape=\"route-to-absent-skill\""
      if (match(text,/\/[a-z][a-z0-9-]*:[a-z][a-z0-9-]*/))
        return "target=\"" substr(text, RSTART, RLENGTH) "\""
      if (match(text, /`[a-z][a-z0-9-]*:[a-z][a-z0-9-]*`/))
        return "target=\"" substr(text, RSTART + 1, RLENGTH - 2) "\""
      return "shape=\"route-to-absent-skill\""
    }
    if (id == "I33") return "shape=\"spoke-self-description\""
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
  # Count first, classify second. A line that misses the scan-row pattern still
  # increments nrows and lands in reason=unparsable-row; it is never omitted
  # from both Scan rows read and every Declined line. Trailing CR is stripped
  # here the same way descr() and source_line() already strip it, so a mixed
  # CRLF file does not silently drop the CR-terminated rows.
  {
    sub(/\r$/, "")
    is_lane = (lane_file != "" && FILENAME == lane_file)
    if (is_lane) nlane++; else nrows++
  }
  /^.+:[0-9]+:I[0-9]+(-[a-f])?$/ {
    # Split from the RIGHT: a path may contain colons, the last two fields never do.
    id = $0; sub(/^.*:/, "", id)
    rest = $0; sub(/:[^:]*$/, "", rest)
    lno = rest; sub(/^.*:/, "", lno)
    file = rest; sub(/:[^:]*$/, "", file)

    rid = rule_id(id)
    if (rid == "") { declined_nocrosswalk[id]++; next }
    if (is_lane && !lane_rule(id)) { declined_scanner_fed[id]++; next }
    if (!is_lane && lane_rule(id)) { declined_lane_fed[id]++; next }

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

    if (!in_rule_surfaces(id, loc)) { declined_scope[id]++; next }

    if (!($0 in fid)) { declined_identity[id]++; next }

    # Identical sentences under one heading path share an anchor, hence an id:
    # the finding is reported once and the collision is named with its count.
    f = fid[$0]
    if (f in nfid) { if (nfid[f]++ == 1) collided[++ncoll] = f; next }
    nfid[f] = 1

    excerpt = trim(text)
    if (length(excerpt) > 160) excerpt = substr(excerpt, 1, 157) "..."

    # Rank order is tier, then Confidence (high above omitted), then input order.
    tier = rule_tier(id, loc)
    k = tier_rank(tier) * 2 + (is_lane ? 1 : 0)
    bucket[k, ++nb[k]] = "| " tier " | " (is_lane ? "" : "high") " | " esc(loc) ":" lno \
      " | claude-config:audit-instructions | " \
      esc(rid " " fired_marker(id, text) " finding_id=" fid[$0] " -- " excerpt) " | " \
      esc(rule_action(id, loc, file)) " |"
    nemit++
    if (is_lane) nemit_lane++
    seen[id]++
    next
  }
  {
    id = $0
    sub(/^.*:/, "", id)
    if (id == "" || id !~ /^I[0-9]+(-[A-Za-z0-9]+)?$/) id = "(unparsable)"
    declined_unparsable[id]++
  }

  END {
    printf "---\ntype: review-findings\ndate: %s\nbranch: %s\n---\n\n", date_utc, yaml_scalar(branch)
    print "## Findings"
    print ""
    print "| Rank | Tier | Confidence | Location | Surface(s) | Finding | Action |"
    print "|------|------|------------|----------|------------|---------|--------|"
    rank = 0
    for (k = 0; k <= 5; k++)
      for (i = 1; i <= nb[k]; i++) printf "| %d %s\n", ++rank, bucket[k, i]
    print ""
    print "## Surfaces"
    print ""
    how = ""
    if (have_scan != "") how = "instruction-scan.sh --body-only"
    if (lane_file != "") how = how (how == "" ? "" : "; ") "model lanes: I30, I31, I32, I33"
    ran = "Ran: [claude-config:audit-instructions (" how ")]."
    zero = ""
    ranids = ""
    if (have_scan != "") ranids = "I28-a I28-b I29-a I29-b"
    if (lane_file != "") ranids = ranids (ranids == "" ? "" : " ") "I30 I31 I32 I33"
    nz = split(ranids, zids, " ")
    for (i = 1; i <= nz; i++)
      if (!(zids[i] in seen))
        zero = zero (zero == "" ? "" : ", ") rule_id(zids[i])
    if (zero != "") ran = ran " Returned no result: [" zero "]."
    print ran
    printf "Scan rows read: %d. Emitted: %d.\n", nrows, nemit
    if (lane_file != "")
      printf "Lane rows read: %d. Emitted from lanes: %d.\n", nlane, nemit_lane
    for (i = 1; i <= ncoll; i++)
      printf "Identity collisions: finding_id=%s count=%d (reported once; no suppression carries forward)\n", collided[i], nfid[collided[i]]
    report_declined(declined_nocrosswalk, "no-severity-crosswalk-row (human report only)")
    report_declined(declined_scanner_fed, "scanner-fed-rule (admitted only through --from)")
    report_declined(declined_lane_fed, "lane-fed-rule (admitted only through --from-lane)")
    report_declined(declined_scope, "outside-rule-surfaces (I31 and I33 apply to files in a skill directory and in context/, reference/, or references/ directories; I33 excludes SKILL.md)")
    report_declined(declined_identity, "identity-unresolved (finding-ids.sh refused the row)")
    report_declined(declined_frontmatter, "frontmatter (body-scope fence)")
    report_declined(declined_trigger, "quoted-trigger-phrase (body-scope fence)")
    report_declined(declined_outofrepo, "outside-repo-root (Location must be repo-relative; human report only)")
    report_declined(declined_unreadable, "source-line-unreadable")
    report_declined(declined_unparsable, "unparsable-row")
    # The model lane drops carve-out candidates (destructive/security gate,
    # stated hard precondition, document about the pattern) before this script
    # sees them, so it reports their count here rather than letting the
    # exclusion go unrecorded — a decline this file promises is never silent.
    if (carveout != "")
      printf "Declined candidates: I28 count=%s reason=criteria-carve-out (model lane; see reference/criteria.md I28)\n", carveout
    if (residency != "")
      printf "Declined candidates: count=%s reason=residency-unresolved (RESIDENCY-UNRESOLVED in the human report; no applicable edit)\n", residency
  }
' "${INPUTS[@]}" >"$OUT"

echo "emit-findings.sh: wrote $OUT"

#!/usr/bin/env bash
# PostToolUse hook: verify that a repo-relative path cited in newly-written
# markdown is not one this repository has since removed.
# Triggered on Write|Edit of *.md files.
#
# ORACLE: disappearance, not absence. A finding requires the repository to prove
# it once owned the path — the exact repo-relative path must appear in the set
# of paths deleted across HEAD's history AND be gone from the working tree now.
# Absence on its own is evidence of nothing: `docs/`, `scripts/`, `lib/`,
# `.claude/` are conventional names shared by every repo that uses them, so a
# path's SHAPE can never establish that it was a claim about THIS tree. Only
# history can.
#
# ENFORCEABILITY TIER: Detect-then-judge — ADVISORY PLUS A HUMAN VERDICT, never
# an auto-fix. The oracle is mechanical, but the conclusion is not: a doc may
# cite a removed path deliberately, as a deletion or completion record, and such
# a citation is correct exactly as written. Per the org convention on
# enforceability tiers that makes the finding a prompt for a decision, not a
# determination.
#
# WHAT THIS STRUCTURALLY CANNOT CATCH: a hallucinated path. An invented path was
# never in this repository, so it never enters the deleted-path set and this
# guard stays silent by construction. That class needs a signal this oracle does
# not have — something separating "asserted about THIS tree" from "documented
# about a consumer's tree", such as an explicit marker convention for
# consumer-tree examples. Absent that signal it stays out of scope, because a
# hallucinated path and a correctly-documented consumer path are the same
# observation: absent locally, conventionally shaped.
#
# SCOPE: inline code spans only. Markdown link destinations are out — on-disk
# link integrity belongs to the repo's offline link checker, and under this
# oracle no link-kind candidate contributes a finding anyway.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext.
#
# Disable with the stale_path_verify_enabled userConfig option set to false.

set -uo pipefail

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "STALE_PATH_VERIFY"

hook::ctx_reset

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PostToolUse" "guardrails-stale-path-verify" "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
# A CHANGELOG is an append-only historical record, and this oracle selects
# precisely for removed paths — precisely what such a record documents. Mirrors
# skill-reference-verify's exclusion for the same reason.
*/CHANGELOG.md | CHANGELOG.md) exit 0 ;;
*.md) ;;
# Code files are out of scope: a path literal in a script resolves against the
# runtime CWD, not the repo root, so a repo-root existence test is the wrong
# oracle there.
*) exit 0 ;;
esac

# Diff-scope: verify only the content THIS tool call wrote, never re-read the
# whole file from disk. An Edit's pre-existing lines outside the changed hunk are
# not this call's claims.
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')
# replace_all feeds reconstruction's uniqueness gate below. Per the tools
# reference an Edit's `old_string` "must appear exactly once", and
# `replace_all: true` is how every occurrence is replaced instead — so under
# replace_all the same new_string landing in several places is the edit's own
# footprint rather than an ambiguity.
# https://code.claude.com/docs/en/tools-reference
REPLACE_ALL=false
case "$TOOL" in
Edit)
  SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r')
  REPLACE_ALL=$(printf '%s' "$INPUT" | jq -r '(.tool_input.replace_all // false) | tostring' 2>/dev/null | tr -d '\r')
  ;;
Write) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | tr -d '\r') ;;
*) exit 0 ;;
esac
[[ -n "$SCAN_CONTENT" ]] || exit 0

REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
[[ -d "$REPO_ROOT" ]] || exit 0

# Inline-code spans, backticks stripped. Prose is deliberately NOT scanned: an
# unquoted `a/b` in a sentence is as likely to be a ratio, a date, or an
# either/or as a path.
emit_tokens() {
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//'
}

# Reduce a raw token to a repo-relative path candidate, or nothing.
# Prints the candidate on success; prints nothing when the token is not one.
normalize_candidate() {
  local t="$1"

  # A code span can hold a whole command; take only single-token spans. NOT
  # because a path cannot contain whitespace — git permits spaces in pathnames —
  # but because a whitespace-bearing span is far likelier to be a command than a
  # path, and reading one as a path adjudicates its arguments: the suite pins
  # `cp docs/gone.md docs/real.md` staying quiet even though it names a genuinely
  # deleted path. The cost is that a spaced deleted path is never adjudicated;
  # admitting one needs a discriminator against command spans, tracked in #1452.
  [[ "$t" =~ [[:space:]] ]] && return 0

  # Strip a trailing line/range citation suffix — this repo cites
  # `docs/MIGRATION-PLAYBOOK.md:576-580` and `SKILL.md:24` pervasively.
  t="${t%%:[0-9]*}"

  # Strip a trailing markdown-anchor fragment.
  t="${t%%#*}"

  # Strip surrounding and trailing prose punctuation.
  t="${t#[\'\"\(]}"
  t="${t%[\'\"\),;.]}"

  # Leading ./ is the same path.
  t="${t#./}"

  # Must look like a path at all.
  [[ "$t" == */* ]] || return 0

  # Reject anything that is not a literal repo-relative path.
  case "$t" in
  # URLs, protocol-relative, mail, and anchors.
  *://* | //* | mailto:* | \#*) return 0 ;;
  # Absolute POSIX and Windows paths — hardcoded-path-check owns those.
  /* | [A-Za-z]:[/\\]*) return 0 ;;
  # Home-relative.
  '~'*) return 0 ;;
  # A repo-root-relative citation has nothing to ascend from.
  ../* | */../*) return 0 ;;
  # Glob, brace, or placeholder metacharacters — a pattern, not an assertion.
  *'*'* | *'?'* | *'['* | *']'* | *'{'* | *'}'* | *'<'* | *'>'* | *'$'* | *'('* | *')'* | *'|'* | *'!'*) return 0 ;;
  # Ellipsis stand-ins.
  *...*) return 0 ;;
  # Vendor and build trees are not tracked; their absence proves nothing.
  node_modules/* | */node_modules/* | .git/* | */.git/*) return 0 ;;
  *) ;;
  esac

  # A bare directory reference with no extension and no trailing slash is
  # ambiguous with a namespace, a module path, or a URL path fragment.
  #
  # A TRAILING SLASH clears that ambiguity but buys no finding: git records file
  # deletions, never directory ones, so no DELETED key can ever carry a slash and
  # the exact provenance lookup below can never match `docs/old/`. An absent
  # directory citation therefore only ever reaches ABSENT — enough to trip the
  # shallow-clone and failed-walk notices, never enough to emit a STALE_PATH.
  # Directory citations are OUT OF SCOPE for adjudication; making them work means
  # deriving deleted ancestors from the file entries, tracked in #1452.
  local last="${t##*/}"
  if [[ "$t" != */ && "$last" != *.* ]]; then
    return 0
  fi

  printf '%s' "$t"
}

# Partial-replacement context reconstruction (Edit only), mirroring
# skill-reference-verify's reconstruct_partial_edit.
#
# An Edit may replace an arbitrary substring: swapping `gone` for `real` inside an
# existing `docs/gone.md` span leaves `docs/real.md` on disk, but the hunk is the
# bare word `real` with no backtick pair around it, so emit_tokens finds no span
# and a newly-stale citation would be silently missed. Write needs none of this —
# its content is the whole file, already fully scanned.
#
# Recover bounded context: the edit is already applied by PostToolUse time, so pull
# from disk only the lines the hunk's OWN TEXT appears in, scan those, and keep only
# candidates containing one of the hunk's word tokens.
#
# The anchor match is a SUBSTRING match, so line-anchoring ALONE does not bound
# what is recovered: when the hunk is a single bare fragment the anchor IS that
# fragment and the line filter degenerates to the token filter. What bounds it is
# the occurrence-uniqueness gate below — the same gate the sibling guard this
# function mirrors already carries.
reconstruct_partial_edit() {
  [[ "$TOOL" == "Edit" && -f "$FILE" ]] || return 0
  # The token filter reads the hunk with any COMPLETE code span removed first. A
  # complete span is already handled by the direct scan, and leaving it in would
  # contribute its own path segments as tokens — `docs` then passes every citation
  # under that directory. What remains is the genuinely bare edited text.
  local residue
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  residue=$(printf '%s' "$SCAN_CONTENT" | sed -E 's/`[^`]*`//g')
  # Minimum token length. A substring match on a very short token matches almost
  # any path segment, so below 4 characters the token carries no filtering power.
  # Path separators are deliberately NOT in the token charset: a prose fragment
  # like `and/or` would then match far more candidates than a bare word does.
  local -a toks=()
  mapfile -t toks < <(printf '%s' "$residue" | grep -oE '[A-Za-z0-9][A-Za-z0-9._-]{3,}' 2>/dev/null | sort -u)
  ((${#toks[@]})) || return 0
  # Lines are located by the hunk's own lines, never by its tokens. Every line of
  # new_string is on disk verbatim, so it matches the line the edit landed in; a
  # token, being shorter, also matches lines the edit never touched — a bare `docs`
  # in unrelated prose pulls in every citation under docs/.
  local -a anchors=()
  mapfile -t anchors < <(printf '%s' "$SCAN_CONTENT" | grep -vE '^[[:space:]]*$' 2>/dev/null)
  ((${#anchors[@]})) || return 0
  # An anchor is used ONLY when it OCCURS exactly once in the file — occurrences,
  # not matching lines. Counting lines is not enough: two occurrences on one
  # physical line are one grep hit, and that is a real shape — editing `docs` into
  # a line that already carries an untouched `` `docs/gone.md` `` leaves the anchor
  # twice on that line, and adjudicating that citation would be an advisory about
  # text this call never wrote. Occurrence uniqueness subsumes line uniqueness (one
  # occurrence can only be on one line), so it is the only gate.
  #
  # This is what makes the recovered set diff-scoped rather than merely narrower.
  # The edited line provably contains the anchor, so a single occurrence pins the
  # edit to that line; a non-unique anchor cannot say WHICH occurrence the edit
  # landed on, and is dropped rather than unioned. Cost: a missed advisory when an
  # edit lands in text repeating verbatim elsewhere in the file. For a
  # detect-then-judge guard that is the right side of the trade — it is degraded
  # far worse by being wrong when it speaks than by staying quiet.
  local anchor occ ctx=""
  local -a hits=()
  for anchor in "${anchors[@]}"; do
    mapfile -t hits < <(grep -F -- "$anchor" "$FILE" 2>/dev/null)
    ((${#hits[@]})) || continue
    # replace_all is the one case where repetition is expected rather than
    # ambiguous: every occurrence is a place THIS call edited, so all of them are
    # in scope and uniqueness must not be required. Accepted narrowing — a line
    # that independently contained new_string and was never touched is kept too,
    # since nothing in the payload distinguishes it from an edited one.
    if [[ "$REPLACE_ALL" == "true" ]]; then
      for occ in "${hits[@]}"; do ctx+="$occ"$'\n'; done
      continue
    fi
    # Count anchor STARTS, including overlapping ones. `grep -o` emits only
    # non-overlapping matches, so a self-overlapping anchor undercounts: with
    # anchor `docs/docs` against `docs/docs/docs`, starts exist at offsets 0 and
    # 5, but the two spans overlap and `grep -o` reports 1 — the anchor passes a
    # uniqueness gate it should fail, and reconstruction then scans a line it
    # cannot attribute, recreating the false STALE_PATH this gate exists to
    # prevent. `index()` walks every start position, overlapping or not.
    # The anchor crosses into awk via the environment, not `-v`: `-v` processes
    # escape sequences in the value, so an anchor containing a backslash would
    # be silently transformed before the comparison.
    occ=$(HOOK_ANCHOR="$anchor" awk '
      BEGIN { a = ENVIRON["HOOK_ANCHOR"]; n = 0 }
      { p = 1; while ((i = index(substr($0, p), a)) > 0) { n++; p = p + i } }
      END { print n }
    ' "$FILE" 2>/dev/null)
    ((occ == 1)) || continue
    ctx+="${hits[0]}"$'\n'
  done
  [[ -n "$ctx" ]] || return 0
  local saved="$SCAN_CONTENT"
  SCAN_CONTENT=$(printf '%s' "$ctx" | grep -vE '^[[:space:]]*$' | head -40)
  local raw cand seg
  while IFS= read -r raw; do
    [[ -n "$raw" ]] || continue
    cand=$(normalize_candidate "$raw")
    [[ -n "$cand" ]] || continue
    # SUBSTRING match against the CANDIDATE, not the raw span: an Edit can replace
    # part of a segment (`gone` -> `real` turns `docs/gone.md` into `docs/real.md`),
    # so the hunk token is a substring of the path rather than the whole of it, and
    # the anchor must appear in the thing actually reported.
    for seg in "${toks[@]}"; do
      if [[ "$cand" == *"$seg"* ]]; then
        printf '%s\n' "$cand"
        break
      fi
    done
  done < <(emit_tokens)
  SCAN_CONTENT="$saved"
}

declare -A DELETED=()
DELETED_BUILT=0
SHALLOW=0
WALK_FAILED=0

# The deleted-path set, built at most once and only after some candidate has
# already failed the working-tree existence test — the overwhelmingly common
# quiet path never pays for the history walk.
build_deleted_set() {
  ((DELETED_BUILT)) && return 0
  DELETED_BUILT=1

  # An unborn HEAD has no history to walk.
  git -C "$REPO_ROOT" rev-parse --verify -q HEAD >/dev/null 2>&1 || return 0

  # Over truncated history the set is empty and the guard would do nothing while
  # appearing healthy, so the degradation is announced rather than absorbed.
  if [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null | tr -d '\r')" == "true" ]]; then
    SHALLOW=1
    return 0
  fi

  # --no-renames is MANDATORY. Under git's default rename detection a moved file
  # is recorded as R and --name-only prints the NEW path, so the stale path never
  # enters the set and the guard silently drops to zero findings. HEAD, not
  # --all: a path that only ever existed on an abandoned branch is not a stale
  # mainline citation.
  #
  # The walk is captured and its status checked BEFORE anything is populated. A
  # non-shallow clone can still fail mid-walk — a partial/lazy clone offline, a
  # damaged object store — emitting some deleted paths and then exiting nonzero.
  # Read through a pipe or process substitution that status is invisible, and a
  # truncated set is indistinguishable from a complete one: the guard would look
  # healthy while adjudicating against a fraction of history. Same failure mode
  # as a shallow clone, so it takes the same announced degradation.
  local walk walk_status=0
  walk=$(git -C "$REPO_ROOT" log HEAD --no-renames --diff-filter=D --name-only --pretty=format: 2>/dev/null) ||
    walk_status=$?
  if ((walk_status != 0)); then
    WALK_FAILED=1
    return 0
  fi

  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    DELETED["$p"]=1
  done < <(printf '%s\n' "$walk" | tr -d '\r')
}

# "Did you mean" enrichment, only once a finding exists. A basename match is far
# too weak to trigger on — `README.md` and `SKILL.md` match hundreds of paths —
# but once history has established the path was removed, a UNIQUE surviving
# basename is very likely where it went.
moved_hint() {
  local base="${1##*/}" matches=()
  mapfile -t matches < <(git -C "$REPO_ROOT" ls-files 2>/dev/null | tr -d '\r' |
    awk -F/ -v b="$base" '$NF == b')
  ((${#matches[@]} == 1)) && printf '%s' "${matches[0]}"
}

declare -A CHECKED=()
MISSING=()
ABSENT=0
ls_tag=""

RAW_TOKENS=()
mapfile -t RAW_TOKENS < <(emit_tokens)
# Reconstruction runs on EVERY Edit, not only when the hunk yielded nothing. One
# hunk can both carry a complete code span and change a substring inside another,
# so gating on an empty scan would miss the partial half. Duplicates are harmless
# — CHECKED dedupes below.
if [[ "$TOOL" == "Edit" ]]; then
  mapfile -t -O "${#RAW_TOKENS[@]}" RAW_TOKENS < <(reconstruct_partial_edit)
fi

for raw in "${RAW_TOKENS[@]}"; do
  [[ -n "$raw" ]] || continue
  cand=$(normalize_candidate "$raw")
  [[ -n "$cand" ]] || continue

  [[ -n "${CHECKED[$cand]:-}" ]] && continue
  CHECKED["$cand"]=1

  # Present, not merely reachable: -L keeps a dangling symlink — the link itself is
  # there, only its target is not — from reading as a removal.
  [[ -e "$REPO_ROOT/${cand%/}" || -L "$REPO_ROOT/${cand%/}" ]] && continue
  ABSENT=1

  # PROVENANCE GATE: adjudicate only a path this repository demonstrably once
  # had. Anything else is somebody else's tree, an example, or a plan.
  build_deleted_set
  [[ -n "${DELETED[$cand]:-}" ]] || continue

  # Deleted once, tracked again now. Under a sparse checkout such a path is absent
  # from the working tree BY DESIGN, so the filesystem alone cannot separate it from
  # a real removal and the index has to be consulted. Placed after the provenance
  # gate, not before it: only a path already headed for a finding pays for the call,
  # which keeps the quiet path free of any per-candidate git invocation.
  #
  # The test is the SKIP-WORKTREE BIT, not mere presence in the index. An index
  # entry exists in two different situations and `--error-unmatch` cannot tell them
  # apart — it reports the entry either way:
  #
  #   sparse checkout      `ls-files -v` tags the entry `S` — or lowercase `s`
  #                        when the assume-unchanged bit is ALSO set, since `-v`
  #                        marks assume-unchanged by lowercasing the letter;
  #                        either case carries the skip-worktree bit, so the
  #                        path is absent BY DESIGN.
  #   unstaged deletion    tag stays `H` and `git status` shows ` D`; the path is
  #                        genuinely gone from the working tree, which is exactly
  #                        the disappearance this guard adjudicates.
  #
  # Exempting on presence alone therefore suppressed the finding for a real removal
  # a user had not committed yet. Only the skip-worktree letter, in either case,
  # earns the exemption.
  ls_tag=$(git -C "$REPO_ROOT" ls-files -v -- ":(literal)${cand%/}" 2>/dev/null | tr -d '\r' | cut -c1)
  [[ "$ls_tag" == [Ss] ]] && continue

  MISSING+=("$cand")
done

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local file_rel="$FILE" findings_json="[]"
  if command -v cygpath >/dev/null 2>&1; then
    local _file_lm _root_lm
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    [[ -n "$_file_lm" && -n "$_root_lm" ]] && file_rel="${_file_lm#"$_root_lm"/}"
  else
    file_rel="${FILE#"$REPO_ROOT"/}"
  fi
  # Redaction: a path that could not be made repo-relative degrades to its
  # basename — never an absolute path, which would embed the developer's
  # username.
  case "$file_rel" in
  /* | [A-Za-z]:*)
    file_rel="${file_rel##*/}"
    file_rel="${file_rel##*\\}"
    ;;
  *) ;;
  esac
  if ((${#MISSING[@]} > 0)); then
    local m raw_list=""
    for m in "${MISSING[@]}"; do raw_list+="$m"$'\n'; done
    findings_json=$(printf '%s' "$raw_list" | jq -R . | jq -s . 2>/dev/null) || findings_json="[]"
  fi
  local data
  data=$(jq -n --arg file "$file_rel" --argjson findings "$findings_json" \
    '{tool:"",file:$file,findings:$findings}' 2>/dev/null) ||
    data='{"tool":"","file":"","findings":[]}'
  # $1 is the envelope status, defaulting to a completed check. The degradation
  # branches pass `skipped`: they run when the deleted-path oracle was unavailable,
  # and reporting `ok` there would make a sink read an un-run check as a healthy
  # one — the truncated-history failure looking exactly like a clean scan is the
  # thing this guard already refuses to do on the user-visible path.
  hook::emit_telemetry "stale-path-verify" "PostToolUse" "${1:-ok}" "$start" "$data" "$REPO_ROOT"
}

if ((SHALLOW)) && ((ABSENT)); then
  if hook::notice_once "guardrails-stale-path-verify-shallow" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "stale-path-verify: this clone is shallow, so the deleted-path history it reads is truncated and the guard cannot adjudicate. Run \`git fetch --unshallow\` to restore it."
  fi
  emit_tel skipped
  exit 0
fi

if ((WALK_FAILED)) && ((ABSENT)); then
  if hook::notice_once "guardrails-stale-path-verify-walk-failed" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "stale-path-verify: the deleted-path history walk exited nonzero, so the set it reads is incomplete and the guard cannot adjudicate. Run \`git log --diff-filter=D --name-only\` to see why — a partial clone missing objects offline and a damaged object store are the usual causes."
  fi
  emit_tel skipped
  exit 0
fi

if ((${#MISSING[@]} > 0)); then
  hook::ctx_append "stale-path-verify: ${#MISSING[@]} cited path(s) were removed from this repo and no longer exist in $FILE"
  for m in "${MISSING[@]}"; do
    hint=$(moved_hint "$m")
    if [[ -n "$hint" ]]; then
      hook::ctx_append "  STALE_PATH: $m (one tracked file now carries that name: $hint)"
    else
      hook::ctx_append "  STALE_PATH: $m"
    fi
  done
  hook::ctx_append ""
  hook::ctx_append "Detect-then-judge: this is a prompt for your verdict, not a determination."
  hook::ctx_append "Confirm against the tree. A path cited deliberately as a"
  hook::ctx_append "deletion or completion record — documenting that the file was retired —"
  hook::ctx_append "is correct as written."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0

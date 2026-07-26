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
case "$TOOL" in
Edit) SCAN_CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r') ;;
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

  # A code span can hold a whole command; take only single-token spans. A path
  # candidate never contains whitespace.
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
  local last="${t##*/}"
  if [[ "$t" != */ && "$last" != *.* ]]; then
    return 0
  fi

  printf '%s' "$t"
}

declare -A DELETED=()
DELETED_BUILT=0
SHALLOW=0

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
  local p
  while IFS= read -r p; do
    [[ -n "$p" ]] || continue
    DELETED["$p"]=1
  done < <(git -C "$REPO_ROOT" log HEAD --no-renames --diff-filter=D --name-only --pretty=format: 2>/dev/null | tr -d '\r')
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

while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  cand=$(normalize_candidate "$raw")
  [[ -n "$cand" ]] || continue

  [[ -n "${CHECKED[$cand]:-}" ]] && continue
  CHECKED["$cand"]=1

  [[ -e "$REPO_ROOT/${cand%/}" ]] && continue
  ABSENT=1

  # PROVENANCE GATE: adjudicate only a path this repository demonstrably once
  # had. Anything else is somebody else's tree, an example, or a plan.
  build_deleted_set
  [[ -n "${DELETED[$cand]:-}" ]] || continue

  MISSING+=("$cand")
done < <(emit_tokens)

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
  hook::emit_telemetry "stale-path-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((SHALLOW)) && ((ABSENT)); then
  if hook::notice_once "guardrails-stale-path-verify-shallow" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "stale-path-verify: this clone is shallow, so the deleted-path history it reads is truncated and the guard cannot adjudicate. Run \`git fetch --unshallow\` to restore it."
  fi
  emit_tel
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

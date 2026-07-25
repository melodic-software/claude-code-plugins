#!/usr/bin/env bash
# PostToolUse hook: verify repo-relative paths asserted in newly-written markdown
# actually exist in the working tree.
# Triggered on Write|Edit of *.md files.
#
# Catches subagent / training-recall hallucinations — a path written AS a
# citation that does not exist. Sibling of cli-flag-verify: same class of defect
# (a confident specific that was never checked), different oracle.
#
# ENFORCEABILITY TIER: Deterministic. The oracle is a filesystem test — the path
# either resolves under the repo root or it does not. No judgment step.
#
# NON-BLOCKING (advisory): exits 0 with hookSpecificOutput additionalContext
# on unresolvable paths.
#
# FIRST-SEGMENT GATE is what keeps this quiet. A candidate is only checked when
# its leading segment is a real directory in the repo. `docs/nope.md` is checked
# because `docs/` exists; `some-other-repo/src/main.rs` is not, because
# `some-other-repo/` does not — it is an example, another project, or a package
# path, none of which this repo can adjudicate.
#
# ACCEPTED RESIDUAL: a doc that cites a file the same change set has not written
# yet fires. PostToolUse runs after the write, so a doc-before-code ordering
# within one session produces a finding for a path that becomes real minutes
# later. Advisory-only is the mitigation; a blocking version of this guard would
# be wrong for that reason alone.
#
# Disable with the asserted_path_verify_enabled userConfig option set to false.

set -uo pipefail

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "ASSERTED_PATH_VERIFY"

hook::ctx_reset

INPUT=$(hook::buffer_stdin) || exit 0

hook::require_jq "PostToolUse" "guardrails-asserted-path-verify" "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.md) ;;
# Code files are out of scope: a path literal in a script resolves against the
# runtime CWD, not the repo root, so a repo-root existence test is the wrong
# oracle there and would fire on every correct relative path.
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

# Emit raw path-shaped tokens (one per line) from inline-code spans and markdown
# link/image targets. Prose is deliberately NOT scanned: an unquoted `a/b` in a
# sentence is as likely to be a ratio, a date, or an either/or as a path, and a
# path asserted as a citation is written in code or as a link by convention.
emit_tokens() {
  # Inline-code spans, backticks stripped.
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null | sed -E 's/^`+//; s/`+$//'
  # Markdown link and image targets: the parenthesized destination only.
  printf '%s' "$SCAN_CONTENT" | grep -oE '\]\([^)[:space:]]+\)' 2>/dev/null | sed -E 's/^\]\(//; s/\)$//'
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

  # Strip a trailing markdown-anchor fragment; lychee already resolves those.
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
  # Escapes the tree; not resolvable against the repo root.
  ../* | */../*) return 0 ;;
  # Glob, brace, or placeholder metacharacters — a pattern, not an assertion.
  *'*'* | *'?'* | *'['* | *']'* | *'{'* | *'}'* | *'<'* | *'>'* | *'$'* | *'('* | *')'* | *'|'* | *'!'*) return 0 ;;
  # Ellipsis stand-ins.
  *...*) return 0 ;;
  # Vendor and build trees are not tracked; their absence proves nothing.
  node_modules/* | */node_modules/* | .git/* | */.git/*) return 0 ;;
  esac

  # A bare directory reference with no extension and no trailing slash is
  # ambiguous with a namespace, a module path, or a URL path fragment. Require
  # either a file extension in the last segment or an explicit trailing slash.
  local last="${t##*/}"
  if [[ "$t" != */ && "$last" != *.* ]]; then
    return 0
  fi

  printf '%s' "$t"
}

# FIRST-SEGMENT GATE. Only adjudicate a candidate whose leading segment is a
# real directory here — that is what distinguishes "this repo's path, written
# wrong" from "a path belonging to something else".
first_segment_is_local() {
  local seg="${1%%/*}"
  [[ -n "$seg" ]] || return 1
  [[ -d "$REPO_ROOT/$seg" ]]
}

declare -A CHECKED=()
MISSING=()

while IFS= read -r raw; do
  [[ -n "$raw" ]] || continue
  cand=$(normalize_candidate "$raw")
  [[ -n "$cand" ]] || continue
  [[ -n "${CHECKED[$cand]:-}" ]] && continue
  CHECKED["$cand"]=1
  first_segment_is_local "$cand" || continue
  target="${cand%/}"
  [[ -e "$REPO_ROOT/$target" ]] && continue
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
  hook::emit_telemetry "asserted-path-verify" "PostToolUse" "ok" "$start" "$data" "$REPO_ROOT"
}

if ((${#MISSING[@]} > 0)); then
  hook::ctx_append "asserted-path-verify: ${#MISSING[@]} asserted path(s) do not exist in $FILE"
  hook::ctx_append "Each leading directory IS in this repo, so these read as this repo's paths written wrong:"
  for m in "${MISSING[@]}"; do
    hook::ctx_append "  MISSING_PATH: $m"
  done
  hook::ctx_append ""
  hook::ctx_append "Confirm each against the working tree. If a path is intentionally"
  hook::ctx_append "forward-looking (a file this change set has not written yet), it is"
  hook::ctx_append "correct and this finding is expected — PostToolUse cannot tell the"
  hook::ctx_append "difference."
  hook::ctx_flush PostToolUse
fi

emit_tel
exit 0

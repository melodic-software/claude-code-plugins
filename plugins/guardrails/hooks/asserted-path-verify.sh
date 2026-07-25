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

# Emit `<kind>|<raw-token>` lines from inline-code spans and markdown link/image
# destinations. Prose is deliberately NOT scanned: an unquoted `a/b` in a
# sentence is as likely to be a ratio, a date, or an either/or as a path, and a
# path asserted as a citation is written in code or as a link by convention.
#
# The kind is carried because the two resolve against different bases (see
# bases_for below). `|` is a safe separator: normalize_candidate rejects any
# candidate containing one.
emit_tokens() {
  # Inline-code spans, backticks stripped.
  # shellcheck disable=SC2016  # backticks are literal ERE data, not expansions
  printf '%s' "$SCAN_CONTENT" | grep -oE '`[^`]+`' 2>/dev/null |
    sed -E 's/^`+//; s/`+$//; s/^/code|/'
  # Markdown link and image destinations. A destination may carry an optional
  # title (`[x](dest "Title")`) and may be angle-bracketed (`[x](<dest>)`), so
  # take the whole parenthesized run and keep only the leading destination token.
  printf '%s' "$SCAN_CONTENT" | grep -oE '\]\([^)]*\)' 2>/dev/null |
    sed -E 's/^\]\(//; s/\)$//; s/^[[:space:]]+//; s/[[:space:]].*$//; s/^<//; s/>$//; s/^/link|/'
}

# Percent-decode a markdown destination — `docs/my%20file.md` names the file
# `docs/my file.md`. Decodes only when every `%` in the string begins a valid
# two-hex-digit escape; anything else is returned untouched, so a literal `%` in
# a filename is not mangled. Callers MUST re-apply the traversal guard after
# decoding: `%2e%2e%2f` decodes to `../`.
maybe_percent_decode() {
  local s="$1"
  [[ "$s" == *%* ]] || {
    printf '%s' "$s"
    return 0
  }
  [[ "$s" =~ ^([^%]|%[0-9A-Fa-f]{2})*$ ]] || {
    printf '%s' "$s"
    return 0
  }
  printf '%b' "${s//%/\\x}"
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
  # A `../` candidate is NOT rejected here. A markdown link destination is
  # document-relative, so `../gone.md` from `docs/sub/note.md` is a legitimate
  # in-repo reference. The caller canonicalizes link destinations against the
  # document directory and drops only those that resolve outside the repo; a
  # code-span candidate carrying `../` is dropped there instead, since a
  # repo-root-relative citation has nothing to ascend from.
  # Glob, brace, or placeholder metacharacters — a pattern, not an assertion.
  *'*'* | *'?'* | *'['* | *']'* | *'{'* | *'}'* | *'<'* | *'>'* | *'$'* | *'('* | *')'* | *'|'* | *'!'*) return 0 ;;
  # Ellipsis stand-ins.
  *...*) return 0 ;;
  # Vendor and build trees are not tracked; their absence proves nothing.
  node_modules/* | */node_modules/* | .git/* | */.git/*) return 0 ;;
  # Anything else is a candidate; the extension and first-segment gates below
  # decide whether it is adjudicated.
  *) ;;
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

# A code-span citation is repo-root-relative — that is this repo's convention for
# citing a file in prose. A markdown link destination is document-relative per
# CommonMark, but this repo also writes repo-root paths inside link syntax, so a
# link is accepted when EITHER base resolves. An advisory guard errs quiet.
DOC_DIR="$(dirname "$FILE")"

# Collapse `.` and `..` segments lexically, preserving absoluteness. Purely
# textual on purpose: the target need not exist — that is what is being tested —
# so `realpath`/`readlink -f` would fail on exactly the inputs that matter.
# Returns 1 when the path ascends past its own root, which is how "escapes the
# tree" is detected.
lexical_normalize() {
  local p="$1" seg out=() lead=""
  [[ "$p" == /* ]] && lead=/
  local IFS=/
  for seg in $p; do
    case "$seg" in
    '' | .) ;;
    ..)
      ((${#out[@]})) || return 1
      unset 'out[-1]'
      ;;
    *) out+=("$seg") ;;
    esac
  done
  printf '%s%s' "$lead" "${out[*]}"
}

# The document's directory as a repo-relative prefix (`docs/sub`), asked of git
# rather than computed by string surgery.
#
# Deriving it as `${DOC_DIR#$REPO_ROOT}` does not work: on Windows `git rev-parse
# --show-toplevel` returns a drive path (`C:/Users/KyleSexton/…`) while `dirname
# "$FILE"` returns the MSYS form (`/tmp/…`), so the prefix silently never matches.
# cygpath does not rescue it either — the MSYS `/tmp` mount resolves through an 8.3
# short name (`KYLESE~1`), so the two sides still differ. `--show-prefix` sidesteps
# the whole problem by answering in one universe. Empty outside a work tree, which
# is correct: hook::repo_root then falls back to this same directory.
DOC_REL="$(git -C "$DOC_DIR" rev-parse --show-prefix 2>/dev/null | tr -d '\r')"
DOC_REL="${DOC_REL%/}"

# Resolve a document-relative destination to a repo-relative path, or return 1
# when it escapes the repo. Since the input is already repo-relative, ascending
# past its root IS leaving the repo — so lexical_normalize's own failure is the
# containment test, with no absolute paths involved.
resolve_within_repo() {
  lexical_normalize "${DOC_REL:+$DOC_REL/}$1"
}

declare -A CHECKED=()
MISSING=()

while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  kind="${line%%|*}"
  raw="${line#*|}"
  cand=$(normalize_candidate "$raw")
  [[ -n "$cand" ]] || continue

  if [[ "$kind" == "link" ]]; then
    cand=$(maybe_percent_decode "$cand")
    # Absolute forms are re-checked post-decode; `../` is handled by
    # canonicalization below, not by rejection.
    case "$cand" in
    /* | [A-Za-z]:[/\\]*) continue ;;
    *) ;;
    esac
    # Resolve document-relative the way a renderer would, then require the result
    # to stay inside the repo. A `../` that lands in-repo is a legitimate
    # reference; one that ascends past the root is not ours to adjudicate.
    if [[ "$cand" == *../* || "$cand" == ../* ]]; then
      cand=$(resolve_within_repo "$cand") || continue
      [[ -n "$cand" ]] || continue
      # Now repo-root-relative, so the doc-dir base no longer applies.
      kind=link_rooted
    fi
  else
    # A repo-root-relative citation has nothing to ascend from.
    case "$cand" in
    ../* | */../*) continue ;;
    *) ;;
    esac
  fi

  [[ -n "${CHECKED[$kind|$cand]:-}" ]] && continue
  CHECKED["$kind|$cand"]=1

  if [[ "$kind" == "link" ]]; then
    bases=("$DOC_DIR" "$REPO_ROOT")
  else
    bases=("$REPO_ROOT")
  fi

  # FIRST-SEGMENT GATE. Only adjudicate a candidate whose leading segment is a
  # real directory under some base — that is what distinguishes "this repo's
  # path, written wrong" from "a path belonging to something else". A candidate
  # gated out on every base is never reported.
  target="${cand%/}"
  first_seg="${cand%%/*}"
  gated=0
  resolved=0
  for base in "${bases[@]}"; do
    [[ -n "$first_seg" && -d "$base/$first_seg" ]] || continue
    gated=1
    if [[ -e "$base/$target" ]]; then
      resolved=1
      break
    fi
  done
  ((gated)) || continue
  ((resolved)) && continue
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

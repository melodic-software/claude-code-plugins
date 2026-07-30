#!/usr/bin/env bash
# PreToolUse hook: block an MCP-created PR whose BODY would fail the consuming
# repository's own `pr-issue-linkage` CI gate.
#
# WHY IT EXISTS — cloud/remote sessions have no `gh` CLI and create PRs through
# the GitHub MCP server (`mcp__github__create_pull_request` /
# `mcp__github__update_pull_request`), a surface the sibling
# pr-body-linkage-gate.sh Bash hook never sees. This hook is that sibling's
# MCP-surface counterpart: same validator semantics, same scope guards, on the
# payload shape the MCP tools deliver. Where the Bash sibling must tokenize a
# command line to even find the body, here the body arrives as a plain JSON
# field — so the extraction caveats (heredocs, dynamic values, directory
# changes) don't exist on this surface, and the fail-open set is much smaller.
#
# WHAT IT ENFORCES — the two halves the reusable
# melodic-software/ci-workflows pr-issue-linkage validator requires: after
# stripping HTML comments (terminated spans, then an unterminated `<!--`
# swallowing the rest), the body must carry
#   (a) a native closing keyword (`Closes/Fixes/Resolves #N`, including
#       `owner/repo#N`) OR the literal `No linked issue` / `No related issue:`;
#   (b) a `## Related` section that is present AND non-empty, where a DEEPER
#       heading (`### ...`) is that section's content, not its terminator.
#
# SCOPE GUARDS —
#   - enforcement is keyed to the repository's OWN policy: the gate runs only
#     when the repo root carries `.github/workflows/pr-issue-linkage.yml`
#     (or `.yaml`), so a consumer without the check is never gated;
#   - a call targeting a DIFFERENT repository (tool_input owner/repo not
#     matching the repo's origin remote) is out of scope and allowed —
#     this repo's policy is not another repo's;
#   - `update_pull_request` with no `body` field changes nothing the CI gate
#     re-validates, and is allowed.
#
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE BAD BODY — unreadable
# stdin, missing jq, or an undeterminable target repo allow (policy gate, not a
# security guard). A present-but-failing body blocks. A `create_pull_request`
# with NO body field is a determinable bad body (GitHub opens the PR with an
# empty body, which the CI gate rejects) and blocks.
#
# LOCALE — matching runs under LC_ALL=C and the JavaScript-`\s`-only Unicode
# whitespace characters are normalized to plain spaces first, so the verdict
# does not depend on the ambient locale. See the sibling's LOCALE note for the
# full rationale.
#
# Kill switch: pr_linkage_mcp_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming the missing half(s) plus the line to add.

set -uo pipefail

# Pinned for the whole process: see LOCALE above. Set before anything reads a
# character class, including the shared lib.
export LC_ALL=C

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "PR_LINKAGE_MCP_GATE"

start=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require_jq "PreToolUse" "source-control-pr-linkage-mcp-gate" "$INPUT"
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
mcp__github__create_pull_request | mcp__github__update_pull_request) ;;
*) exit 0 ;;
esac

HOOK_CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty' 2>/dev/null | tr -d '\r')
REPO_ROOT=$(hook::repo_root "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}")

# The consuming repo's own gate definition is the authority; no gate, no
# enforcement.
GATE_FILE=""
for candidate in "$REPO_ROOT/.github/workflows/pr-issue-linkage.yml" \
  "$REPO_ROOT/.github/workflows/pr-issue-linkage.yaml"; do
  [[ -f "$candidate" ]] && {
    GATE_FILE="$candidate"
    break
  }
done
[[ -n "$GATE_FILE" ]] || exit 0

# Out-of-scope guard: only judge PRs aimed at THIS repository. The origin URL's
# separators are normalized so https, ssh (`git@host:owner/repo`), and proxied
# forms all end in `/owner/repo`; comparison is case-insensitive because GitHub
# routing is.
T_OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // empty' 2>/dev/null)
T_REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // empty' 2>/dev/null)
ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
if [[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]]; then
  norm="${ORIGIN%/}"
  norm="${norm%.git}"
  norm="${norm//:/\/}"
  [[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0
fi

# An update that carries no body leaves the body CI already validated
# untouched.
if [[ "$TOOL" == "mcp__github__update_pull_request" ]]; then
  printf '%s' "$INPUT" | jq -e '.tool_input | has("body")' >/dev/null 2>&1 || exit 0
fi

BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.body // ""' 2>/dev/null)

emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg outcome "$1" --arg tool "$TOOL" \
    '{outcome:$outcome,tool:$tool}' 2>/dev/null) || data='{"outcome":"","tool":""}'
  hook::emit_telemetry "pr-linkage-mcp-gate" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- Body validation (mirrors the ci-workflows validator; see the sibling
# pr-body-linkage-gate.sh for the fully annotated original of each function) --

UNICODE_SPACES=(
  $'\xc2\xa0' $'\xe1\x9a\x80'
  $'\xe2\x80\x80' $'\xe2\x80\x81' $'\xe2\x80\x82' $'\xe2\x80\x83'
  $'\xe2\x80\x84' $'\xe2\x80\x85' $'\xe2\x80\x86' $'\xe2\x80\x87'
  $'\xe2\x80\x88' $'\xe2\x80\x89' $'\xe2\x80\x8a'
  $'\xe2\x80\xa8' $'\xe2\x80\xa9' $'\xe2\x80\xaf'
  $'\xe2\x81\x9f' $'\xe3\x80\x80' $'\xef\xbb\xbf'
)

strip_html_comments() {
  local body="$1" line rest kept out="" in_comment=0 sp
  for sp in "${UNICODE_SPACES[@]}"; do body="${body//"$sp"/ }"; done
  while IFS= read -r line || [[ -n "$line" ]]; do
    rest="${line%$'\r'}"
    kept=""
    while [[ -n "$rest" ]]; do
      if ((in_comment)); then
        if [[ "$rest" == *"-->"* ]]; then
          rest="${rest#*-->}"
          in_comment=0
        else
          rest=""
        fi
      else
        if [[ "$rest" == *"<!--"* ]]; then
          kept+="${rest%%<!--*}"
          rest="${rest#*<!--}"
          in_comment=1
        else
          kept+="$rest"
          rest=""
        fi
      fi
    done
    out+="$kept"$'\n'
  done <<<"$body"
  printf '%s' "$out"
}

trim() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

KEYWORD_ERE='[^a-z0-9_](close[sd]?|fix(es|ed)?|resolve[sd]?)[[:space:]]*:?[[:space:]]*([a-z0-9_.-]+/[a-z0-9_.-]+)?#[0-9]+[^a-z0-9_]'
NO_ISSUE_ERE='[^a-z0-9_]no (linked|related) issue[^a-z0-9_]'

has_linkage() {
  local probe
  probe=$'\n'"${1,,}"$'\n'
  [[ "$probe" =~ $KEYWORD_ERE || "$probe" =~ $NO_ISSUE_ERE ]]
}

related_section() {
  local body="$1" line t start=0 lvl i=0 out=""
  local -a lines=()
  while IFS= read -r line || [[ -n "$line" ]]; do lines+=("$line"); done <<<"$body"
  for ((i = 0; i < ${#lines[@]}; i++)); do
    t="${lines[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    [[ "${t,,}" =~ ^##[[:space:]]+related$ ]] && {
      start=$((i + 1))
      break
    }
  done
  ((start)) || return 1
  for ((i = start; i < ${#lines[@]}; i++)); do
    t="${lines[i]}"
    t="${t#"${t%%[![:space:]]*}"}"
    t="${t%"${t##*[![:space:]]}"}"
    if [[ "$t" =~ ^#+[[:space:]]+[^[:space:]] ]]; then
      lvl=0
      while [[ "${t:lvl:1}" == "#" ]]; do ((lvl++)); done
      ((lvl <= 2)) && break
    fi
    out+="${lines[i]}"$'\n'
  done
  trim "$out"
}

problems=()
stripped=$(strip_html_comments "$BODY")
# shellcheck disable=SC2310  # the two exits ARE the verdict: absent vs present
if related=$(related_section "$stripped"); then
  [[ -n "$related" ]] || problems+=('The "## Related" section is empty.')
else
  problems+=('Missing a "## Related" section.')
fi
has_linkage "$stripped" ||
  problems+=('Missing a native closing keyword (Closes/Fixes/Resolves #N) and no "No linked issue" marker.')

if ((${#problems[@]} == 0)); then
  emit_tel "ok"
  exit 0
fi

emit_tel "blocked"
echo "BLOCKED: PR body fails this repo's required pr-issue-linkage check." >&2
for p in "${problems[@]}"; do echo "  - $p" >&2; done
echo "Gate: ${GATE_FILE#"$REPO_ROOT/"} (required check 'pr-issue-linkage / pr-issue-linkage')." >&2
echo "Add to the body:" >&2
echo "  Closes #<issue>      (or the literal line: No linked issue)" >&2
echo "  ## Related" >&2
echo "  - <links, or N/A>" >&2
exit 2

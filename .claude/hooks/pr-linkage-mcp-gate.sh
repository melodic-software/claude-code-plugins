#!/usr/bin/env bash
# PreToolUse gate: block an MCP-created PR whose BODY would fail this
# repository's required `pr-issue-linkage` CI check.
#
# WHY IT EXISTS — cloud/remote sessions have no `gh` CLI and create PRs through
# the GitHub MCP server (`mcp__github__create_pull_request` /
# `mcp__github__update_pull_request`), a surface the source-control plugin's
# `pr-body-linkage-gate.sh` Bash hook never sees. Because this hook and the
# settings entry that wires it are checked into the repository, it loads in any
# session that opens this repo — cloud containers included — with no plugin
# install step. It is the MCP-surface sibling of the plugin hook and mirrors
# the same validator semantics.
#
# WHAT IT ENFORCES — the two halves the
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
#     when the project root carries `.github/workflows/pr-issue-linkage.yml`
#     (or `.yaml`), so a copy of this hook in a repo without the check never
#     blocks anything;
#   - a call targeting a DIFFERENT repository (tool_input owner/repo not
#     matching the project's origin remote) is out of scope and allowed —
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
# does not depend on the ambient locale. Mirrors the plugin hook's LOCALE note.
#
# BLOCKING: exits 2 naming the missing half(s) plus the line to add.

set -uo pipefail
export LC_ALL=C

INPUT=$(cat) || exit 0
[[ -n "$INPUT" ]] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
case "$TOOL" in
mcp__github__create_pull_request | mcp__github__update_pull_request) ;;
*) exit 0 ;;
esac

ROOT="${CLAUDE_PROJECT_DIR:-.}"

# The consuming repo's own gate definition is the authority; no gate, no
# enforcement.
GATE_FILE=""
for candidate in "$ROOT/.github/workflows/pr-issue-linkage.yml" \
  "$ROOT/.github/workflows/pr-issue-linkage.yaml"; do
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
ORIGIN=$(git -C "$ROOT" remote get-url origin 2>/dev/null || true)
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

# --- Body validation (mirrors the ci-workflows validator; see the plugin
# hook plugins/source-control/hooks/pr-body-linkage-gate.sh for the fully
# annotated original of each function) ---------------------------------------

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

((${#problems[@]})) || exit 0

echo "BLOCKED: PR body fails this repo's required pr-issue-linkage check." >&2
for p in "${problems[@]}"; do echo "  - $p" >&2; done
echo "Gate: ${GATE_FILE#"$ROOT/"} (required check 'pr-issue-linkage / pr-issue-linkage')." >&2
echo "Add to the body:" >&2
echo "  Closes #<issue>      (or the literal line: No linked issue)" >&2
echo "  ## Related" >&2
echo "  - <related PR / ADR / decision this PR does not close, or N/A>" >&2
exit 2

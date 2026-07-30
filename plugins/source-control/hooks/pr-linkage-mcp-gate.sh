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
# routing is. When the match cannot be ESTABLISHED — no origin remote, or a
# payload missing owner/repo — the target is undeterminable and the call is
# allowed: imposing this checkout's policy on a repository it was never proven
# to be is the worse failure (see FAIL-OPEN above).
T_OWNER=$(printf '%s' "$INPUT" | jq -r '.tool_input.owner // empty' 2>/dev/null)
T_REPO=$(printf '%s' "$INPUT" | jq -r '.tool_input.repo // empty' 2>/dev/null)
ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null || true)
[[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]] || exit 0
norm="${ORIGIN%/}"
norm="${norm%.git}"
norm="${norm//:/\/}"
[[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0

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

# --- Body validation ----------------------------------------------------------
# The validator core is shared with the Bash-surface sibling
# pr-body-linkage-gate.sh; the annotated functions live in
# pr-linkage-validator.sh, sourced so a drift fix against the upstream
# ci-workflows validator lands on every surface at once.
# shellcheck source=pr-linkage-validator.sh
source "$(dirname "${BASH_SOURCE[0]}")/pr-linkage-validator.sh"

# shellcheck disable=SC2310  # the return status IS the verdict
if linkage::problems "$BODY"; then
  emit_tel "ok"
  exit 0
fi

echo "BLOCKED: PR body fails this repo's required pr-issue-linkage check." >&2
for p in "${LINKAGE_PROBLEMS[@]}"; do echo "  - $p" >&2; done
echo "Gate: ${GATE_FILE#"$REPO_ROOT/"} (required check 'pr-issue-linkage / pr-issue-linkage')." >&2
echo "Add to the body:" >&2
echo "  Closes #<issue>      (or the literal line: No linked issue)" >&2
echo "  ## Related" >&2
echo "  - <links, or N/A>" >&2
emit_tel "blocked"
exit 2

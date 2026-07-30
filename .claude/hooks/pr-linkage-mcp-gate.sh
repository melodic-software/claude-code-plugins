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
# NO KILL SWITCH, by design — this hook IS this repository's tracked policy,
# so "disable it" is an edit to .claude/settings.json that goes through a PR,
# exactly like changing the CI gate itself. The plugin sibling carries the
# per-user userConfig switch; a repo-level policy file deliberately does not.
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

# `.` is a last-resort fallback for running outside a Claude session (tests
# set CLAUDE_PROJECT_DIR); if it points somewhere without the gate workflow,
# the gate-file check below simply fails to find it and the hook allows.
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
# Undeterminable target (no origin remote, or payload missing owner/repo):
# allow — imposing this checkout's policy on a repository it was never proven
# to be is the worse failure (see FAIL-OPEN above).
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

# --- Body validation ----------------------------------------------------------
# The validator core is the source-control plugin's pr-linkage-validator.sh,
# resolved relative to THIS FILE — the hook is checked into the marketplace
# repo whose checkout always carries the plugin source, so no plugin install
# is needed and a drift fix lands on every surface at once. Resolution is
# deliberately not via CLAUDE_PROJECT_DIR: the hook judges payloads against
# whatever repo it ships in, wherever that checkout lives. If the lib moves,
# fail OPEN with a loud note (policy gate, not a security guard) — CI still
# holds the contract, and the test suite fails on the silent-skip.
VALIDATOR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../../plugins/source-control/hooks/pr-linkage-validator.sh"
# shellcheck source=../../plugins/source-control/hooks/pr-linkage-validator.sh
if ! source "$VALIDATOR" 2>/dev/null; then
  echo "pr-linkage-mcp-gate: shared validator not found at $VALIDATOR — gate skipped." >&2
  exit 0
fi

# shellcheck disable=SC2310  # the return status IS the verdict
linkage::problems "$BODY" && exit 0

echo "BLOCKED: PR body fails this repo's required pr-issue-linkage check." >&2
for p in "${LINKAGE_PROBLEMS[@]}"; do echo "  - $p" >&2; done
echo "Gate: ${GATE_FILE#"$ROOT/"} (required check 'pr-issue-linkage / pr-issue-linkage')." >&2
echo "Add to the body:" >&2
echo "  Closes #<issue>      (or the literal line: No linked issue)" >&2
echo "  ## Related" >&2
echo "  - <related PR / ADR / decision this PR does not close, or N/A>" >&2
exit 2

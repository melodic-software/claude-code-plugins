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
# WHAT IT ENFORCES — the five requirements the reusable
# melodic-software/ci-workflows pr-issue-linkage validator requires: after
# stripping HTML comments (terminated spans, then an unterminated `<!--`
# swallowing the rest), the body must carry
#   (a) a native closing keyword (`Closes/Fixes/Resolves #N`, including
#       `owner/repo#N`) OR the literal `No linked issue` / `No related issue:`;
#   (b) four present AND non-empty contract sections — `## Summary`, `## Fix`,
#       `## Verification`, `## Related` — where a DEEPER heading (`### ...`)
#       is that section's content, not its terminator.
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
# BLOCKING: exits 2 naming every missing or empty requirement plus the lines to add.

set -uo pipefail

# Pinned for the whole process: see LOCALE above. Set before anything reads a
# character class, including the shared lib.
export LC_ALL=C

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics
# and fails a guard that sources anything ahead of it.
[[ "${CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
start=${EPOCHREALTIME:-}

INPUT=$(hook::buffer_stdin) || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require_jq "PreToolUse" "source-control-pr-linkage-mcp-gate" "$INPUT"

# Every payload field this gate reads, in ONE jq process (#3509). The per-field
# form this replaced ran `printf '%s' "$INPUT" | jq -r … 2>/dev/null` five times
# plus a sixth `jq -e` for the has("body") probe — measured with
# `strace -f -e trace=clone,clone3,fork,vfork,execve`, 3-4 forks and 1-2 execs
# EACH, all six asking about the same buffered string. One hook::jq_fields call
# answers all of them for 3 forks and 1 exec.
#
# Reading every field up front means owner/repo/body are extracted before the
# tool-name and scope guards would have short-circuited. Nothing observable
# reorders: the reads have no side effects, they come out of one process either
# way, and each guard below still exits exactly where it did.
#
# `has("body")` rides along as the string "true"/"false" — the probe's own jq -e
# is what the boolean replaces, and a missing `.tool_input` makes the whole
# filter null, which hook::jq_fields renders "" (neither "true" nor the empty
# check below passes, so an absent tool_input still ALLOWS as before).
#
# BODY IS DELIBERATELY NOT TAKEN FROM THIS BATCH. hook::jq_fields CR-strips
# every value it returns, and the validator only strips a CR at end of line; a
# body carrying a MID-LINE CR would therefore be judged against different text
# than before, and stripping is the permissive direction — `## Sum<CR>mary`
# becomes a section that was previously missing, turning a BLOCK into an ALLOW.
# The batch reports whether the raw body holds a CR at all and the next block
# re-reads it losslessly only in that case, which no real payload hits.
hook::jq_fields "$INPUT" \
  '.tool_name' '.cwd' '.tool_input.owner' '.tool_input.repo' \
  '(.tool_input | has("body"))' '((.tool_input.body // "") | contains("\r"))' \
  '(.tool_input.body // "")' || exit 0
TOOL="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
T_OWNER="${HOOK_JQ_FIELDS[2]}"
T_REPO="${HOOK_JQ_FIELDS[3]}"
HAS_BODY="${HOOK_JQ_FIELDS[4]}"
BODY_HAS_CR="${HOOK_JQ_FIELDS[5]}"
BODY="${HOOK_JQ_FIELDS[6]}"

case "$TOOL" in
mcp__github__create_pull_request | mcp__github__update_pull_request) ;;
*) exit 0 ;;
esac

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
# The redirect sits on the enclosing GROUP, not inside the substitution: bash
# elides the extra fork and execs in the substitution's own subshell only when
# the command carries no redirection of its own, so `$(git … 2>/dev/null)` cost
# two forks for one program where this costs one (#3509). The group holds
# exactly one command, so nothing beyond that git call is silenced; `|| ORIGIN=""`
# reproduces what the old `|| true` produced, an empty ORIGIN on failure.
{ ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin) || ORIGIN=""; } 2>/dev/null
[[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]] || exit 0
norm="${ORIGIN%/}"
norm="${norm%.git}"
norm="${norm//:/\/}"
[[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0

# An update that carries no body leaves the body CI already validated
# untouched.
if [[ "$TOOL" == "mcp__github__update_pull_request" ]]; then
  [[ "$HAS_BODY" == "true" ]] || exit 0
fi

# The batched BODY is already correct for every payload the batch reported no
# CR in — the strip had nothing to remove, so the value is byte-identical to
# what the dedicated `jq -r` returned. Only a body that DOES carry a CR is
# re-read losslessly, at the cost of the one jq process this whole batch exists
# to avoid; see the note on the hook::jq_fields call above for why that
# direction is the unsafe one to guess at.
if [[ "$BODY_HAS_CR" == "true" ]]; then
  BODY=$(printf '%s' "$INPUT" | jq -r '.tool_input.body // ""' 2>/dev/null)
fi

# emit_tel <outcome> [status] — status defaults to the outcome; pass an
# explicit documented status (ok|error|skipped|blocked) when the domain
# outcome is not itself a documented envelope status (an unknown status is
# mapped to error by the reference sink; the domain detail rides data.outcome).
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  # hook::json_str_object_to, not `jq -n --arg`: the library builder is
  # documented byte-identical to that jq form for an all-string object, and
  # costs neither the fork nor the exec (#3509). Both fields are strings.
  local data
  hook::json_str_object_to data outcome "$1" tool "$TOOL"
  hook::emit_telemetry "pr-linkage-mcp-gate" "PreToolUse" "${2:-$1}" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# Defer-guard: when the consuming repo tracks its OWN equivalent gate in
# .claude/settings.json (a PreToolUse hook whose command names
# pr-linkage-mcp-gate — the marketplace repo does exactly this so its policy
# survives sessions with no plugin install), both copies would fire and exit 2
# on every MCP PR call, and the repo-local copy is deliberately
# kill-switch-free. The plugin side is the right place to yield: the repo's
# settings.json states the wiring authoritatively, whereas the repo-local
# script has no sound signal for "plugin enabled" (plugin SOURCE present never
# implies plugin ACTIVE). A repo could suppress this gate with a no-op script
# of the same name — acceptable: this is a policy gate, not a security guard,
# and the required CI check remains the authority.
if [[ -f "$REPO_ROOT/.claude/settings.json" ]] &&
  jq -e '[.hooks.PreToolUse[]?.hooks[]? | (.command // empty), (.args[]? | strings)]
    | any(contains("pr-linkage-mcp-gate"))' \
    "$REPO_ROOT/.claude/settings.json" >/dev/null 2>&1; then
  emit_tel "deferred" "skipped"
  exit 0
fi

# --- Body validation ----------------------------------------------------------
# The validator core is shared with the Bash-surface sibling
# pr-body-linkage-gate.sh; the annotated functions live in
# pr-linkage-validator.sh, sourced so a drift fix against the upstream
# ci-workflows validator lands on every surface at once.
# shellcheck source=pr-linkage-validator.sh
source "$HOOK_DIR/pr-linkage-validator.sh"
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
echo "  ## Summary" >&2
echo "  <what and why>" >&2
echo "  ## Fix" >&2
echo "  <concrete change>" >&2
echo "  ## Verification" >&2
echo "  <evidence the change works>" >&2
echo "  ## Related" >&2
echo "  - <links, or N/A>" >&2
emit_tel "blocked"
exit 2

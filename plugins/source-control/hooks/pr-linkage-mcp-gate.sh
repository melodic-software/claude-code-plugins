#!/usr/bin/env bash
# PreToolUse hook: block an MCP-created or MCP-updated PR whose BODY carries a
# negated closing reference.
#
# WHY IT EXISTS — cloud/remote sessions create PRs through the GitHub MCP
# server (`mcp__github__create_pull_request` /
# `mcp__github__update_pull_request`, or the `mcp__plugin_<plugin>_github__`
# form of a plugin-bundled server), because `gh pr create` there is absent or
# refused by the cloud GitHub proxy (docs/cloud-sessions.md, "GitHub MCP tools
# vs the gh CLI"). That is a surface the sibling
# pr-body-linkage-gate.sh Bash hook never sees. This hook is that sibling's
# MCP-surface counterpart: same validator semantics, same scope guards, on the
# payload shape the MCP tools deliver. Where the Bash sibling must tokenize a
# command line to even find the body, here the body arrives as a plain JSON
# field — so the extraction caveats (heredocs, dynamic values, directory
# changes) don't exist on this surface, and the fail-open set is much smaller.
#
# WHAT IT ENFORCES — no negated closing reference (`does not close #N`)
# anywhere in the body, which GitHub's negation-blind parser would still close
# on merge, judged as the consuming repository's
# `.github/actions/pr-require-checks/check-contract` composite step
# (melodic-software/ci-workflows) judges it, after stripping HTML comments and
# masking Markdown code. The rest of that contract (a closing line
# and non-empty `## Summary`, `## Fix`, `## Verification` and `## Related`
# sections) is advisory in CI, so a body missing any of it is allowed.
#
# SCOPE GUARDS —
#   - enforcement is keyed to the repository's OWN policy: the gate runs only
#     when one of the repo's `.github/workflows/*.yml` / `*.yaml` files `uses:`
#     the contract composite step `pr-require-checks/check-contract` (the
#     SHA-pinned `melodic-software/ci-workflows/.github/actions/<path>@<sha>`
#     form or ci-workflows' own local `./.github/actions/<path>`), so a consumer
#     without the step is never gated. This is deliberately NOT the
#     `pr_body_required_sections` seam (docs/contracts/pr-body-convention/),
#     whose portable default excludes `Related` on purpose;
#   - a call targeting a DIFFERENT repository (tool_input owner/repo not
#     matching the repo's origin remote) is out of scope and allowed —
#     this repo's policy is not another repo's;
#   - `update_pull_request` with no `body` field changes nothing the CI gate
#     re-validates, and is allowed.
#
# FAIL-OPEN ON EXTRACTION, FAIL-CLOSED ON A DETERMINABLE BAD BODY — unreadable
# stdin, missing jq, or an undeterminable target repo allow (policy gate, not a
# security guard). A body carrying a negated closer blocks. A
# `create_pull_request` with NO body field is judged as an empty body, which
# carries none, and allows.
#
# LOCALE — matching runs under LC_ALL=C and the JavaScript-`\s`-only Unicode
# whitespace characters are normalized to plain spaces first, so the verdict
# does not depend on the ambient locale. See the sibling's LOCALE note for the
# full rationale.
#
# Kill switch: pr_linkage_mcp_gate_enabled userConfig option.
#
# BLOCKING: exits 2 naming each negated closer plus the `Refs: #N` line to use.

set -uo pipefail

# Pinned for the whole process: see LOCALE above. Set before anything reads a
# character class, including the shared lib.
export LC_ALL=C

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh. scripts/check-killswitch-hoist.sh pins this line to
# hook::is_enabled's semantics.
[[ "${CLAUDE_PLUGIN_OPTION_PR_LINKAGE_MCP_GATE_ENABLED:-true}" == "true" ]] || exit 0
# Parameter expansion, not `dirname`: a command substitution forks, which is a
# process on Windows Git Bash. A bare filename strips to itself, so it means `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
start=${EPOCHREALTIME:-}

hook::buffer_stdin_to INPUT || exit 0
[[ -n "$INPUT" ]] || exit 0

hook::require jq "PreToolUse" "source-control" "$INPUT"

# Every payload field this gate reads, in ONE jq process, fenced by
# pr-linkage-spawn-budget.test.sh. `has("body")` comes back "true"/"false", or
# "" when `.tool_input` is missing, which allows.
#
# The batch CR-strips every value, and a CR alone between a negation and its
# closing keyword is a word break: stripping it glues the two into one word that
# is no closer, turning a BLOCK into an ALLOW. So the batch also reports whether
# the raw body holds a CR, and a block below re-reads such a body losslessly.
# `tostring` keeps that probe total over every JSON type, since one erroring
# filter fails the whole batch.
#
# A batch that still fails (a `tool_input` or payload root that is not an
# object) falls back to one jq read per field rather than allowing, so a batch
# failure cannot turn a BLOCK into an ALLOW.
read_fields_singly() {
  local f v
  HOOK_JQ_FIELDS=()
  for f in '.tool_name // empty' '.cwd // empty' \
    '.tool_input.owner // empty' '.tool_input.repo // empty' \
    '.tool_input | has("body")' \
    '(.tool_input.body // "") | tostring | contains("\r")' \
    '.tool_input.body // ""'; do
    v=$(printf '%s' "$INPUT" | jq -r "$f" 2>/dev/null)
    HOOK_JQ_FIELDS+=("$v")
  done
  # Of these fields, only `.cwd` is CR-stripped on this path.
  HOOK_JQ_FIELDS[1]="${HOOK_JQ_FIELDS[1]//$'\r'/}"
}
hook::jq_fields "$INPUT" \
  '.tool_name' '.cwd' '.tool_input.owner' '.tool_input.repo' \
  '(.tool_input | has("body"))' \
  '((.tool_input.body // "") | tostring | contains("\r"))' \
  '(.tool_input.body // "")' || read_fields_singly
TOOL="${HOOK_JQ_FIELDS[0]}"
HOOK_CWD="${HOOK_JQ_FIELDS[1]}"
T_OWNER="${HOOK_JQ_FIELDS[2]}"
T_REPO="${HOOK_JQ_FIELDS[3]}"
HAS_BODY="${HOOK_JQ_FIELDS[4]}"
BODY_HAS_CR="${HOOK_JQ_FIELDS[5]}"
BODY="${HOOK_JQ_FIELDS[6]}"

# chomp <var> — strip trailing newlines from the named variable, in-shell, as
# `$(jq -r …)` would have: hook::jq_fields keeps them, and an
# `"owner": "acme-corp\n"` would otherwise slip past the exact-match guards. The
# batch's CR strip lets a CR-carrying tool, owner or repo match, which the
# per-field fallback does not: the stricter direction, so the body is judged.
chomp() {
  local __v="${!1}"
  while [[ "$__v" == *$'\n' ]]; do __v="${__v%$'\n'}"; done
  printf -v "$1" '%s' "$__v"
}
for v in TOOL HOOK_CWD T_OWNER T_REPO BODY; do chomp "$v"; done

# A GitHub server bundled by a plugin names its tools
# mcp__plugin_<plugin>_github__<tool> rather than mcp__github__<tool>; the
# hooks.json matcher admits both shapes, so this list must too, or the hook
# would fire only to skip the call.
IS_UPDATE=0
case "$TOOL" in
mcp__github__create_pull_request | mcp__plugin_*_github__create_pull_request) ;;
mcp__github__update_pull_request | mcp__plugin_*_github__update_pull_request) IS_UPDATE=1 ;;
*) exit 0 ;;
esac

REPO_ROOT=""
hook::repo_root_to REPO_ROOT "${HOOK_CWD:-${CLAUDE_PROJECT_DIR:-.}}" || :

# The consuming repo's own workflows are the authority: the gate runs only
# where one of them wires in the contract composite step. No step, no
# enforcement.
GATE_FILE=""
# Both `uses:` forms the fleet writes: the SHA-pinned cross-repo reference
# (`melodic-software/ci-workflows/.github/actions/<path>@<sha>`) and
# ci-workflows' own local dogfood (`./.github/actions/<path>`), where <path> is
# `pr-require-checks/check-contract`. The trailing class keeps a longer sibling
# directory (`check-contract-foo`) out.
gate_re='\.github/actions/pr-require-checks/check-contract([@[:space:]]|$)'
for candidate in "$REPO_ROOT"/.github/workflows/*.yml "$REPO_ROOT"/.github/workflows/*.yaml; do
  # An unmatched glob stays literal; skipped here rather than leaking
  # `shopt -s nullglob` out of the hook.
  [[ -f "$candidate" ]] || continue
  # Fork-free read, not `grep` (pr-linkage-spawn-budget.test.sh). `read -d ''`
  # returns 1 at EOF, yet `wf` holds the bytes. Cleared first so an unreadable
  # file does not keep the previous candidate's bytes.
  wf=""
  IFS= read -r -d '' wf <"$candidate"
  [[ "$wf" =~ $gate_re ]] || continue
  GATE_FILE="$candidate"
  break
done
[[ -n "$GATE_FILE" ]] || exit 0

# Out-of-scope guard: only judge PRs aimed at THIS repository. The origin URL's
# separators are normalized so https, ssh (`git@host:owner/repo`), and proxied
# forms all end in `/owner/repo`; comparison is case-insensitive because GitHub
# routing is. When the match cannot be ESTABLISHED — no origin remote, or a
# payload missing owner/repo — the target is undeterminable and the call is
# allowed: imposing this checkout's policy on a repository it was never proven
# to be is the worse failure (see FAIL-OPEN above).
# The redirect sits on the group, not inside the substitution: bash execs git in
# the substitution's subshell only when git carries no redirection of its own.
{ ORIGIN=$(git -C "$REPO_ROOT" remote get-url origin) || ORIGIN=""; } 2>/dev/null
[[ -n "$ORIGIN" && -n "$T_OWNER" && -n "$T_REPO" ]] || exit 0
norm="${ORIGIN%/}"
norm="${norm%.git}"
norm="${norm//:/\/}"
[[ "${norm,,}" == *"/${T_OWNER,,}/${T_REPO,,}" ]] || exit 0

# An update that carries no body leaves the body CI already validated
# untouched.
((IS_UPDATE)) && [[ "$HAS_BODY" != "true" ]] && exit 0

# Only a body carrying a CR differs from its batched value; re-read it losslessly
# (see the note on the hook::jq_fields call above).
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
  # Byte-identical to `jq -n --arg` for an all-string object, with no spawn.
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
if linkage::blocking_problems "$BODY"; then
  emit_tel "ok"
  exit 0
fi

linkage::block_message "${GATE_FILE#"$REPO_ROOT/"}"
emit_tel "blocked"
exit 2

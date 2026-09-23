#!/usr/bin/env bash
# PreToolUse hook: detect secret/credential patterns before file writes.
# Triggered on Write|Edit|NotebookEdit of any file.
#
# BLOCKING: exits 2 when high-confidence secret patterns (API keys, tokens,
# private keys) are detected in new content. Stderr feedback tells Claude what
# was found and how to fix it.
#
# Pattern selection: only HIGH-confidence patterns with distinctive prefixes
# and fixed lengths. Generic patterns (password=, api_key=, secret=) are
# excluded — too many false positives for a real-time blocking hook. Sourced
# from gitleaks, TruffleHog, and secrets-patterns-db.
#
# Cross-platform: uses grep -E (POSIX ERE) only — no grep -P (macOS lacks it).
#
# Consumer seams: scoped to $CLAUDE_PROJECT_DIR (files outside it are another
# repo's concern) only when that root is a git work tree that is not home or an
# ancestor of home; any other root scans every write, as if unset. A generic
# allowlist exempts dependency caches, .env examples, test fixtures, and
# machine-local CC state. Disable entirely with the
# secret_pattern_detection_enabled userConfig option set to false.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics
# and fails a guard that sources anything ahead of it.
[[ "${CLAUDE_PLUGIN_OPTION_SECRET_PATTERN_DETECTION_ENABLED:-true}" == "true" ]] || exit 0

# The hook's own directory is derived with parameter expansion rather than
# `dirname`. GNU Bash forks a subshell for every command substitution even when
# the body is a builtin (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). On Windows Git Bash that
# fork is a process, and this line runs on every fire — including inside the
# dispatcher, where the include guard makes `source` cheap but `$(dirname …)`
# still execs. `${BASH_SOURCE[0]%/*}` equals `dirname` for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture (#3528): fail-open with a dual-channel "guard did not
# run" notice; 0 (allow) and 2 (block) pass through. Fail-open is the status
# quo on abort for this guard too; it is now announced on both channels so a
# write that went unscanned for secrets is never a silent one. A maintainer
# who wants an unscanned write denied instead flips this one word to closed.
guard::abort_boundary secret-pattern-detection PreToolUse open 0 2
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

# Bundled pattern lib — resolved under the plugin root (CC sets
# CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract tests working
# when it is unset). Shared with lib/git-hooks/pre-commit-content-invariants.sh
# so Write|Edit and the write-path-independent pre-commit layer cannot drift.
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
# shellcheck source=../lib/secret-detection/secret-patterns.sh
source "$PLUGIN_ROOT/lib/secret-detection/secret-patterns.sh"

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; buffer
# once, parse each field from it. rc 1 (empty stdin) skips like the empty-field
# guards below; rc 2 (text that is not JSON) FAILS CLOSED — the guard cannot
# evaluate the tool call, and a silent skip would pass exactly the traffic this
# guard exists to stop; rc 3 (a JSON payload cut short by the pipe, a transport
# fault) is a loud skip the dispatcher takes once. buffer_stdin already
# printed the reason to stderr. Buffering does not require jq (hook::buffer_stdin's
# own JSON-completeness check is jq-optional), so it runs before the jq gate
# below — hook::require_jq needs the buffered input for its once-per-session
# notice scoping.
hook::buffer_stdin_to INPUT || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-secret-pattern-detection" "$INPUT"

# Every payload field this hook can need, in ONE jq process (hook::jq_fields),
# not three — a jq spawn is fork() emulation on Windows Git Bash and this guard
# runs on every Write/Edit/NotebookEdit. All three per-tool content fields are
# fetched together because selecting between them would cost a second process;
# jq reads the same envelope either way, and the tool-specific choice happens
# below in the shell. Failure semantics are unchanged: a missing jq or an
# unparsable payload yields rc 1 here, which exits 0 exactly as the empty-TOOL
# case did — hook::require_jq above has already made the degraded state visible
# once per session.
hook::jq_fields "$INPUT" \
  '.tool_name' '.tool_input.file_path' \
  '.tool_input.content' '.tool_input.new_string' '.tool_input.new_source' \
  '.tool_input.path' || exit 0

# A NUL byte in ANY scanned content field is fail-CLOSED (#2136): stripping joins
# text across the byte, so a clean scan would not reflect the bytes carried. One
# refusal, reached from the envelope below and from each file of the MCP lane, so
# the two cannot drift to different wording or a different posture.
secret_nul_refusal() {
  echo "BLOCKED: the payload carries a NUL byte in scanned content." >&2
  echo "The helper strips NUL bytes before matching, so a clean scan would not reflect the bytes the payload carried." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
}

if ((HOOK_JQ_FIELDS_NUL)); then
  secret_nul_refusal
fi

TOOL="${HOOK_JQ_FIELDS[0]}"

# 0 when <slash-normalized path> is allowlisted. A function rather than the
# inline case it replaced because the MCP lane asks the same question of a
# repo-relative path: one list, two callers, no chance of the remote write path
# drifting to a different set of holes than the local one.
secret_path_allowlisted() {
  case "$1" in
  *.claude/hooks/*) return 0 ;;
  *settings.local.json) return 0 ;;
  *CLAUDE.local.md) return 0 ;;
  # Dependency caches — anchored to a path-segment boundary (leading `/` or start
  # of path) so a directory that merely CONTAINS the name (evil_node_modules/,
  # .venv-backup/) is NOT exempted from the scan.
  */.venv/* | .venv/*) return 0 ;;
  */node_modules/* | node_modules/*) return 0 ;;
  *.env.example | *.env.sample | *.env.template) return 0 ;;
  *tests/fixtures/* | *tests/testdata/* | *Tests/fixtures/* | *Tests/testdata/*) return 0 ;;
  *.claude/skills/*/context/*) return 0 ;;
  *.claude/skills/*/completed/*) return 0 ;;
  *) return 1 ;; # proceed to content check
  esac
}

# Scan <content> for secret patterns. The report lands in the caller's $scan_out
# (empty means clean) and each pattern label is APPENDED to the caller's $labels,
# so the MCP lane accumulates labels across the files of one tool call. Callers
# read $scan_out rather than a status, the same write-into-a-variable shape the
# library's own `_to` helpers use.
#
# secrets::scan_text's exit status is lost inside `$()` because the trailing
# `printf x` sentinel is what `$()` reports; the sentinel is also what keeps a
# trailing newline `$()` would otherwise strip, the same pattern as
# hardcoded-path-check.
#
# Call as: secret_scan <content> -> $scan_out $labels
# shellcheck disable=SC2154  # scan_out and labels are the caller's frame, per the call contract
secret_scan() {
  local line
  scan_out=$(
    secrets::scan_text "$1"
    printf x
  )
  scan_out=${scan_out%x}
  [[ -n "$scan_out" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -n "$line" ]] || continue
    labels+=("${line%% (line *}")
  done < <(printf '%s' "$scan_out")
}

# Scan every file a GitHub MCP write carries, and block the whole tool call if
# any of them holds a secret. Exits 2 on a violation; returns for a clean call.
#
# WHAT THIS LANE DELIBERATELY DOES NOT REUSE, and why:
#
#   The project-scope guard. It exists because a LOCAL Write can target another
#   checkout on this machine, which is that repo's policy to enforce. An MCP
#   write names `owner/repo` and a repo-relative path; there is no local file,
#   and CLAUDE_PROJECT_DIR says nothing about the destination. Applying the
#   local test would skip every MCP write (a relative path is never under the
#   project root), which is a silent hole, not a scope.
#
#   hook::normalize_path_to. It folds Windows drive letters and case for comparison
#   against local paths. A GitHub path is already `/`-separated, case-sensitive,
#   and never carries a drive letter.
#
# The ALLOWLIST is reused unchanged: `.env.example`, a test fixture tree or a
# vendored node_modules is the same false positive whichever route writes it.
mcp_lane() {
  local count=1 i path content violations="" first_offender="" scan_out
  local -a labels=()
  # Captured before any further hook::jq_fields call: that helper overwrites
  # HOOK_JQ_FIELDS in place, and the single-file shape's values are already in
  # the array this function was reached through.
  local single_path="${HOOK_JQ_FIELDS[5]}" single_content="${HOOK_JQ_FIELDS[2]}"

  if [[ "$TOOL" == "mcp__github__push_files" ]]; then
    hook::jq_fields "$INPUT" '.tool_input.files | length' || return 0
    count="${HOOK_JQ_FIELDS[0]}"
    # A payload whose files array is absent or unreadable carries nothing this
    # guard can scan; `null` and a non-numeric answer both land here.
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
  fi

  for ((i = 0; i < count; i++)); do
    if [[ "$TOOL" == "mcp__github__push_files" ]]; then
      # One jq process per file, on a lane that fires only on a GitHub MCP write
      # — never on the Write/Edit path this guard runs on for every keystroke of
      # authored content. Reusing hook::jq_fields rather than hand-rolling an
      # extraction keeps this lane's NUL handling the same as the envelope's.
      hook::jq_fields "$INPUT" ".tool_input.files[$i].path" ".tool_input.files[$i].content" || continue
      path="${HOOK_JQ_FIELDS[0]}"
      content="${HOOK_JQ_FIELDS[1]}"
    else
      path="$single_path"
      content="$single_content"
    fi

    # Same fail-closed posture as the envelope: a NUL in scanned content means a
    # clean scan would not reflect the bytes carried.
    if ((HOOK_JQ_FIELDS_NUL)); then
      secret_nul_refusal
    fi

    [[ -n "$path" && -n "$content" ]] || continue
    secret_path_allowlisted "${path//\\//}" && continue

    secret_scan "$content"
    [[ -n "$scan_out" ]] || continue

    [[ -n "$first_offender" ]] || first_offender="$path"
    violations+="$path:"$'\n'"$scan_out"$'\n'
  done

  [[ -n "$violations" ]] || return 0

  {
    printf 'Secret/credential pattern(s) detected in content bound for GitHub:\n\n'
    printf '%s\n' "$violations"
    printf 'This write goes straight to a repository — there is no local file to\n'
    printf 'fix afterwards, and no pre-commit hook on this path. Remove the secret\n'
    printf 'and reissue. If this is a test fixture or example, add its path to the\n'
    printf 'allowlist in secret-pattern-detection.sh.\n'
  } >&2

  if [[ -n "$start" ]] && hook::telemetry_enabled; then
    local labels_json data
    labels_json=$(printf '%s\n' "${labels[@]}" | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
    # `file` carries the repo-relative path the MCP call named. It is authored
    # content, not a local filesystem path, so it embeds no username and needs
    # none of hook::repo_relative_path_to's redaction.
    data=$(jq -n --arg file "$first_offender" --argjson violations "$labels_json" \
      '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
      data='{"tool":"","file":"","violations":[]}'
    hook::emit_telemetry "secret-pattern-detection" "PreToolUse" "blocked" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
  fi
  exit 2
}

case "$TOOL" in
Write | Edit | NotebookEdit) IS_MCP=0 ;;
# --- The GitHub MCP write lane (#3719) --------------------------------------
# A Write|Edit matcher does not see a write issued through an MCP tool, so a
# secret this session authored could reach a repository by a route this guard
# never inspected. These two tools carry file CONTENT and are inspected below.
#
# mcp__github__delete_file is deliberately absent: its schema carries owner,
# repo, path, message and branch, and NO content. There is nothing for a content
# guard to scan, and a delete cannot introduce a secret. Naming it here would
# claim coverage that consists of skipping every call.
mcp__github__push_files | mcp__github__create_or_update_file) IS_MCP=1 ;;
*) exit 0 ;;
esac

# The MCP lane resolves its own paths and content per file and never touches the
# local filesystem, so it runs before the local-write handling below and exits
# on its own. See mcp_lane for what it deliberately does not reuse.
if ((IS_MCP)); then
  mcp_lane
  exit 0
fi

FILE="${HOOK_JQ_FIELDS[1]}"
[[ -n "$FILE" ]] || exit 0

NORM_FILE=""
hook::normalize_path_to NORM_FILE "$FILE"

# Case-preserved, slash-normalized path for the allowlist globs below. On
# Windows hook::normalize_path_to lower-cases the remainder so the membership
# comparison is effectively case-insensitive; reusing that folded value for the
# case-sensitive allowlist would silently break the upper-case patterns
# (CLAUDE.local.md). The allowlist globs are suffix/substring matches, so a
# plain backslash→slash fixup is enough — the drive letter never participates.
ALLOW_FILE="${FILE//\\//}"

# --- Scope guard: police only files inside THIS project ---
# A PreToolUse Write|Edit hook fires on every file write regardless of which
# repo the target lives in. A file outside the project root is not ours to scan:
# that repo owns its own secret policy. Fail CLOSED: when the root cannot be
# resolved (CLAUDE_PROJECT_DIR unset), fall through and scan rather than skip.
#
# A SET root is honored only when it names a project; otherwise it is cleared
# and treated as unset, which only scans more. Claude Code sets the variable to
# the session's start directory, which may be home or any folder. Cleared:
#   - a relative root, or one spelled with `//`, `/./`, `/../`, a trailing `/.`
#     or `/..`, or `~` (an 8.3 name such as PROGRA~1): such a root cannot be
#     compared with the file path as a string.
#   - a root that is not a git work tree: its .git holds HEAD, or is a file
#     whose first line is `gitdir:` (a linked worktree or submodule).
#   - a root when neither HOME nor USERPROFILE is set: home is unknown.
#   - home, or an ancestor of home, as a string or as the same directory under
#     another path (a link, a case or drive spelling): it contains every other
#     checkout on the machine. The ancestors walked are those of home as
#     spelled, not of a symlinked home's resolved target.
# Every test is a builtin, so the check stays fork-free.
spd_scope_root="${CLAUDE_PROJECT_DIR:-}"
spd_scope_root="${spd_scope_root//\\//}"
PROJECT_DIR=""
if [[ -n "$spd_scope_root" ]]; then
  spd_keep=1
  case "$spd_scope_root" in
  *//* | */./* | */../* | */. | */.. | *~*) spd_keep=0 ;;
  /* | [A-Za-z]:/*) ;;
  *) spd_keep=0 ;;
  esac
  spd_scope_root="${spd_scope_root%/}"
  if ((spd_keep)); then
    spd_keep=0
    if [[ -e "$spd_scope_root/.git/HEAD" ]]; then
      spd_keep=1
    elif [[ -f "$spd_scope_root/.git" ]]; then
      spd_gitline=""
      { IFS= read -r spd_gitline <"$spd_scope_root/.git"; } 2>/dev/null || :
      [[ "$spd_gitline" == gitdir:* ]] && spd_keep=1
    fi
  fi
  hook::normalize_path_to PROJECT_DIR "$spd_scope_root"
  spd_home=""
  hook::normalize_path_to spd_home "${HOME:-${USERPROFILE:-}}"
  [[ -z "$spd_home" || "$spd_home/" == "$PROJECT_DIR"/* ]] && spd_keep=0
  # Each home candidate and each of its parents, compared as a directory. The
  # walk drops one path component per step, so it ends within the path's depth.
  spd_prev=""
  for spd_h in "${HOME:-}" "${USERPROFILE:-}"; do
    ((spd_keep)) || break
    [[ -n "$spd_h" && "$spd_h" != "$spd_prev" ]] || continue
    spd_prev="$spd_h"
    spd_h="${spd_h//\\//}"
    spd_h="${spd_h%/}"
    while [[ "$spd_h" == */* ]]; do
      if [[ "$spd_scope_root" -ef "$spd_h" ]]; then
        spd_keep=0
        break
      fi
      spd_h="${spd_h%/*}"
    done
  done
  if ((spd_keep == 0)); then
    spd_scope_root=""
    PROJECT_DIR=""
  fi
fi
if [[ -n "$PROJECT_DIR" ]]; then
  case "$NORM_FILE" in
  "$PROJECT_DIR"/*) ;; # inside the project — proceed
  *) exit 0 ;;         # outside the project — not this hook's concern
  esac
fi

# --- Allowlist: files that legitimately contain secret patterns ---
# Each entry grants a narrow hole — keep it tight:
#   - hook scripts: contain regex strings for the patterns themselves
#   - settings.local.json / CLAUDE.local.md: gitignored, designed for real secrets
#   - .venv / node_modules: gitignored dependency caches
#   - .env.example/sample/template: placeholder format; the patterns require
#     10+ chars after prefix so `sk_test_xxx`-style placeholders don't match
#   - tests/fixtures, tests/testdata: scoped to test trees only
#   - CC skill context/completed: research notes; code review is the backstop
secret_path_allowlisted "$ALLOW_FILE" && exit 0

# --- Extract content to check ---
case "$TOOL" in
Write) CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
Edit) CONTENT="${HOOK_JQ_FIELDS[3]}" ;;
NotebookEdit) CONTENT="${HOOK_JQ_FIELDS[4]}" ;;
*) exit 0 ;; # unreachable — $TOOL filtered to Write|Edit|NotebookEdit above
esac
[[ -n "$CONTENT" ]] || exit 0

# Emit one telemetry envelope: $1 status, $2 labels JSON array. Gated on the
# high-res start stamp and the opt-in sink — the unwired path spawns nothing,
# which is also why the repo-relative path is resolved in here rather than at
# the top level: the default unwired run never pays for it.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  # The helper carries the redaction: a path it could not make repo-relative
  # comes back as the basename, never an absolute path (which would embed the
  # developer's username) and never a UNC share (which would name an internal
  # host). data.file is anchored on the root the scope guard validated, so it
  # is repo-relative to the project when that root was honored. When the root
  # was unset or cleared as untrustworthy, the hook scans on without one, and
  # an unanchored path can only degrade to a bare basename, so resolve the
  # file's own checkout for that case. The envelope's project-dir argument
  # stays the raw CLAUDE_PROJECT_DIR: it records what the harness set, not
  # what this guard decided to honor.
  local file_rel root="$spd_scope_root"
  # Parameter expansion, not a `$(dirname …)` subshell: a command substitution
  # is a fork per call on Windows Git Bash and this guard runs on every write.
  # Same answers as `dirname`: no slash -> `.`, and a root-level `/x` -> `/`
  # rather than the empty string, which hook::repo_root would read as `.`.
  local file_dir="${FILE%/*}"
  [[ "$file_dir" == "$FILE" ]] && file_dir="."
  [[ -n "$file_dir" ]] || file_dir=/
  [[ -n "$root" ]] || hook::repo_root_to root "$file_dir"
  # hook::repo_root_to returns the hint unchanged when git finds no repo, and
  # the hint ends in "/" for a root-level file; the helper strips "$root/".
  root="${root%/}"
  file_rel=""
  hook::repo_relative_path_to file_rel "$FILE" "$root"
  local data
  data=$(jq -n --arg file "$file_rel" --argjson violations "$2" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "secret-pattern-detection" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# --- High-confidence secret patterns (shared lib) ---------------------------
# Patterns + scan live in lib/secret-detection/secret-patterns.sh so the
# pre-commit content-invariants hook enforces the same set (#2731).
labels=()
scan_out=""
secret_scan "$CONTENT"
if [[ -z "$scan_out" ]]; then
  emit_tel "ok" '[]'
  exit 0
fi

# --- Report violations ---
{
  printf 'Secret/credential pattern(s) detected in %s:\n\n' "$FILE"
  printf '%s\n' "$scan_out"
  printf 'If this is a test fixture or example, add the file to the allowlist\n'
  printf 'in secret-pattern-detection.sh. Never commit real secrets — use\n'
  printf 'environment variables, settings.local.json, or a secret manager.\n'
} >&2
labels_json=$(printf '%s\n' "${labels[@]}" | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
emit_tel "blocked" "$labels_json"
exit 2

#!/usr/bin/env bash
# PreToolUse hook: detect hardcoded machine-specific paths before file writes.
# Triggered on Write|Edit|NotebookEdit of any file.
#
# BLOCKING: exits 2 when hardcoded user home directories or drive-letter paths
# are detected in new content. Stderr feedback tells Claude what was found and
# how to fix it.
#
# Cross-platform: detects Windows drive-letter user homes, macOS user homes,
# and Linux user homes. Excludes dynamic references, documentation
# placeholders, and legitimate system paths.
#
# Detection patterns live in the bundled lib/path-detection/hardcoded-path-patterns.sh.
# This script keeps the tool-specific I/O glue: kill switch, JSON stdin parsing,
# exemption set, exit-code mapping.
#
# Consumer seams: gitignored files are skipped (git check-ignore against
# $CLAUDE_PROJECT_DIR) — designate machine-local files there. Disable entirely
# with the hardcoded_path_check_enabled userConfig option set to false.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off. Inlined rather than read through
# hook::is_enabled because the library IS the cost the hoist avoids;
# scripts/check-killswitch-hoist.sh pins this line to that helper's semantics
# and fails a guard that sources anything ahead of it.
[[ "${CLAUDE_PLUGIN_OPTION_HARDCODED_PATH_CHECK_ENABLED:-true}" == "true" ]] || exit 0

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
# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh"

# Bundled pattern lib — resolved under the plugin root (CC sets
# CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract tests working
# when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$_HOOK_SELF/.." && pwd)}"
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
source "$PLUGIN_ROOT/lib/path-detection/hardcoded-path-patterns.sh"

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; buffer
# once, parse each field from it. rc 1 (empty stdin) skips like the empty-field
# guards below; rc 2 (read timed out before a complete payload) FAILS CLOSED —
# the guard cannot evaluate the tool call, and a silent skip would pass exactly
# the traffic this guard exists to stop. buffer_stdin already printed the
# BLOCKED reason to stderr. Buffering does not require jq (hook::buffer_stdin's
# own JSON-completeness check is jq-optional), so it runs before the jq gate
# below — hook::require_jq needs the buffered input for its once-per-session
# notice scoping.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}

# jq is required to parse the tool payload. hook::require_jq fails OPEN
# (advisory hooks never block over a missing prerequisite) but makes the
# degraded state visible to both the user (systemMessage) and the agent
# (additionalContext), once per session — see docs/conventions/hook-observability/.
hook::require_jq "PreToolUse" "guardrails-hardcoded-path-check" "$INPUT"

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
# text across the byte, so a clean scan would not reflect the bytes carried.
if ((HOOK_JQ_FIELDS_NUL)); then
  echo "BLOCKED: the payload carries a NUL byte in scanned content." >&2
  echo "The helper strips NUL bytes before matching, so a clean scan would not reflect the bytes the payload carried." >&2
  echo "Fix: reissue the tool call without the embedded NUL." >&2
  exit 2
fi

TOOL="${HOOK_JQ_FIELDS[0]}"

# 0 when <slash-normalized path> legitimately contains path patterns. A function
# rather than the inline case it replaced because the MCP lane asks the same
# question of a repo-relative path: one list, two callers.
hpc_path_allowlisted() {
  case "$1" in
  # Hook / hook-manager scripts contain path-detection patterns as regex strings.
  *.claude/hooks/* | *.lefthook/*) return 0 ;;
  # Claude Code session/workflow state (under ~/.claude/projects/) lives OUTSIDE
  # any repo working tree and is never committed; absolute paths there are expected
  # machine-local glue. The gitignore check cannot catch it — the path is outside
  # $CLAUDE_PROJECT_DIR, so `git check-ignore` errors rather than matching.
  *.claude/projects/*) return 0 ;;
  *) return 1 ;;
  esac
}

# Set SCAN_ROOT for hpp::scan_text's repo-path branch, from <project root>.
#
# That branch matches the project root as a literal substring and is never
# OS-suppressed. It is a valid machine-specific marker ONLY when the root sits
# inside a genuine git checkout whose TOPLEVEL is not the user's home (nor an
# ancestor of it): a project dir can be a subdirectory of its checkout, and when
# home is itself a checkout (chezmoi-managed dotfiles) a project dir like
# $HOME/Desktop would clear a root-only home test and wrongly re-enable the
# branch, hard-denying every path under it. Empty is the lib's documented seam to
# skip the branch. Native Windows exposes home as %USERPROFILE%, not $HOME, so
# fall back to it; a missing home leaves the branch active (fail toward
# detection, never a false negative).
hpc_resolve_scan_root() {
  local root="$1" toplevel tl_norm home_norm
  SCAN_ROOT=""
  [[ -n "$root" ]] || return 0
  toplevel="$(git -C "$root" rev-parse --show-toplevel 2>/dev/null)"
  [[ -n "$toplevel" ]] || return 0
  tl_norm="$(hook::normalize_path "$toplevel")"
  tl_norm="${tl_norm%/}"
  home_norm="$(hook::normalize_path "${HOME:-${USERPROFILE:-}}")"
  home_norm="${home_norm%/}"
  if [[ -n "$home_norm" && ("$tl_norm" == "$home_norm" || "$home_norm" == "$tl_norm"/*) ]]; then
    SCAN_ROOT="" # enclosing checkout is home or an ancestor of home — suppress the branch
  else
    SCAN_ROOT="$root"
  fi
}

# Scan every file a GitHub MCP write carries, and block the whole tool call if
# any of them holds a machine-specific path. Exits 2 on a violation; returns for
# a clean call.
#
# WHAT THIS LANE DELIBERATELY DOES NOT REUSE, and why. All three are statements
# about a LOCAL file, and an MCP write has none — it names `owner/repo` and a
# repo-relative path, and the bytes go straight to GitHub:
#
#   The project-scope guard, which exists because a local Write can target
#   another checkout on this machine. Applied here it would skip every MCP write
#   (a relative path is never under the project root) — a silent hole, not a
#   scope.
#
#   The git-working-tree requirement on CLAUDE_PROJECT_DIR. The destination's
#   tree is on GitHub; this session's own tree says nothing about it.
#
#   `git check-ignore`. It answers whether THIS checkout ignores a path. The
#   destination repo's ignore rules are not readable from here, and a path that
#   happens to be gitignored locally can be tracked there.
#
# SCAN_ROOT is still resolved, and it is the most valuable half of this lane:
# when the session's own checkout path appears verbatim in content being pushed
# to a repository, that is precisely the leak this guard exists to stop, and it
# is unrecoverable once pushed. It resolves to empty when there is no usable
# project root, which only turns that one branch off.
hpc_mcp_lane() {
  local count=1 i path content violations="" first_offender="" scan_out
  local single_path="${HOOK_JQ_FIELDS[5]}" single_content="${HOOK_JQ_FIELDS[2]}"

  hpc_resolve_scan_root "${CLAUDE_PROJECT_DIR:-}"

  if [[ "$TOOL" == "mcp__github__push_files" ]]; then
    hook::jq_fields "$INPUT" '.tool_input.files | length' || return 0
    count="${HOOK_JQ_FIELDS[0]}"
    [[ "$count" =~ ^[0-9]+$ ]] || return 0
  fi

  for ((i = 0; i < count; i++)); do
    if [[ "$TOOL" == "mcp__github__push_files" ]]; then
      # One jq process per file, on a lane that fires only on a GitHub MCP write
      # — never on the Write/Edit path this guard runs on for authored content.
      hook::jq_fields "$INPUT" ".tool_input.files[$i].path" ".tool_input.files[$i].content" || continue
      path="${HOOK_JQ_FIELDS[0]}"
      content="${HOOK_JQ_FIELDS[1]}"
    else
      path="$single_path"
      content="$single_content"
    fi

    if ((HOOK_JQ_FIELDS_NUL)); then
      echo "BLOCKED: the payload carries a NUL byte in scanned content." >&2
      echo "The helper strips NUL bytes before matching, so a clean scan would not reflect the bytes the payload carried." >&2
      echo "Fix: reissue the tool call without the embedded NUL." >&2
      exit 2
    fi

    [[ -n "$path" && -n "$content" ]] || continue
    hpc_path_allowlisted "${path//\\//}" && continue

    scan_out=$(
      hpp::scan_text "$content" "$SCAN_ROOT" "$path"
      printf x
    )
    scan_out=${scan_out%x}
    [[ -n "$scan_out" ]] || continue
    [[ -n "$first_offender" ]] || first_offender="$path"
    violations+="$path:"$'\n'"$scan_out"
  done

  [[ -n "$violations" ]] || return 0

  {
    printf 'Hardcoded machine-specific path(s) in content bound for GitHub:\n\n'
    printf '%s' "$violations"
    # shellcheck disable=SC2016
    printf 'Use portable alternatives: ~/,  $HOME, $(pwd), $TMPDIR, '
    printf 'git rev-parse --show-toplevel, or <placeholder> notation.\n'
    printf 'This write goes straight to a repository — there is no local file to\n'
    printf 'fix afterwards, and no pre-commit hook on this path.\n'
  } >&2

  if [[ -n "$start" ]] && hook::telemetry_enabled; then
    local labels_json data
    # Block headers only (e.g. "Linux user path detected"), never the matched
    # lines — those carry the actual machine-specific path. Process substitution,
    # not `<<<`: $violations embeds matched lines verbatim and a here-string of
    # 65536-65663 bytes deadlocks (see lib/path-detection/hardcoded-path-patterns.sh).
    labels_json=$(grep -E 'detected:$' < <(printf '%s' "$violations") 2>/dev/null | sed 's/:$//' | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
    data=$(jq -n --arg file "$first_offender" --argjson violations "$labels_json" \
      '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
      data='{"tool":"","file":"","violations":[]}'
    hook::emit_telemetry "hardcoded-path-check" "PreToolUse" "blocked" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
  fi
  exit 2
}

case "$TOOL" in
Write | Edit | NotebookEdit) IS_MCP=0 ;;
# The GitHub MCP write lane (#3719). A Write|Edit matcher does not see a write
# issued through an MCP tool, so a machine-specific path this session authored
# could reach a repository by a route this guard never inspected.
#
# mcp__github__delete_file is deliberately absent: its schema carries owner,
# repo, path, message and branch, and NO content. There is nothing for a content
# guard to scan, and a delete cannot introduce a hardcoded path. Naming it here
# would claim coverage that consists of skipping every call.
mcp__github__push_files | mcp__github__create_or_update_file) IS_MCP=1 ;;
*) exit 0 ;;
esac

if ((IS_MCP)); then
  hpc_mcp_lane
  exit 0
fi

FILE="${HOOK_JQ_FIELDS[1]}"
[[ -n "$FILE" ]] || exit 0

# Normalize path separators for cross-platform case matching.
NORM_FILE="${FILE//\\//}"

# --- Scope guard: police only files inside THIS project ---
# A PreToolUse Write|Edit hook fires on every file write regardless of which
# repo the target lives in. A file outside the project root is not ours to scan
# — that repo owns its own path policy. No active project (CLAUDE_PROJECT_DIR
# unset) → skip entirely: the target is machine-local (a $HOME dotfile, not a
# portable repo artifact this guard protects), and the gitignore escape hatch
# below needs a project root, so scanning here would leave no per-file
# exemption short of the global kill switch. Deliberately different from
# secret-pattern-detection, which scans even without a resolvable root —
# secrets are dangerous anywhere; hardcoded paths only harm portable artifacts.
[[ -n "${CLAUDE_PROJECT_DIR:-}" ]] || exit 0
# Same rationale when the project dir resolves but is NOT a git working tree
# (Claude Code sets CLAUDE_PROJECT_DIR for any directory — a home-directory
# session is the common case): the target is not a portable repo artifact, and
# every per-file exemption rung below is unreachable there — the .claude
# carve-outs don't cover machine-local plugin config, and git check-ignore
# errors outside a work tree — leaving only the global kill switch. A bare
# repo also skips (no working tree means no tracked portable artifacts to
# protect at this path).
[[ "$(git -C "$CLAUDE_PROJECT_DIR" rev-parse --is-inside-work-tree 2>/dev/null)" == "true" ]] || exit 0
_scope_file="$(hook::normalize_path "$FILE")"
_scope_project="$(hook::normalize_path "${CLAUDE_PROJECT_DIR}")"
_scope_project="${_scope_project%/}"
case "$_scope_file" in
"$_scope_project"/*) ;; # inside the project — proceed
*) exit 0 ;;            # outside the project — not this hook's concern
esac

hpc_path_allowlisted "$NORM_FILE" && exit 0

# Skip gitignored files — designated for machine-specific state (settings.local.json,
# CLAUDE.local.md, .venv/, node_modules/, etc.). git check-ignore does not require
# the file to exist on disk, so this works for new Write operations too.
# CLAUDE_PROJECT_DIR is guaranteed non-empty here — the scope guard above
# exited on the no-project case.
if git -C "$CLAUDE_PROJECT_DIR" check-ignore -q "$FILE" 2>/dev/null; then
  exit 0
fi

# Extract content to check — Write has .content, Edit has .new_string,
# NotebookEdit has .new_source.
case "$TOOL" in
Write) CONTENT="${HOOK_JQ_FIELDS[2]}" ;;
Edit) CONTENT="${HOOK_JQ_FIELDS[3]}" ;;
NotebookEdit) CONTENT="${HOOK_JQ_FIELDS[4]}" ;;
*) exit 0 ;; # unreachable — $TOOL filtered to Write|Edit|NotebookEdit above
esac
[[ -n "${CONTENT:-}" ]] || exit 0

# Resolve current repo root for the machine-specific-path check. Comments are
# NOT exempt — examples and "do not use" comments still ship as hardcoded paths
# in fresh clones, get copy-pasted, and rot. Use placeholders in comments too.
# The scope guard above guarantees CLAUDE_PROJECT_DIR is set.
PROJECT_ROOT=$CLAUDE_PROJECT_DIR

# hpp::scan_text's repo-path branch matches PROJECT_ROOT as a
# literal substring and is never OS-suppressed. That is a valid machine-specific
# marker ONLY when PROJECT_ROOT sits inside a genuine git checkout whose ROOT is
# not the user's home (nor an ancestor of it). The comparison is against the
# discovered TOPLEVEL, not PROJECT_ROOT itself: a project dir can be a
# subdirectory of its checkout, and when home is itself a checkout (e.g.
# chezmoi-managed dotfiles) a project dir like $HOME/Desktop would clear a
# PROJECT_ROOT-only home test and wrongly re-enable the branch, hard-denying
# every path under it. When the enclosing checkout is home — or the path is not
# in a checkout at all — skip the branch. Resolve a SCAN_ROOT the scanner uses
# for it: PROJECT_ROOT when the gate passes (the literal being scanned for is
# still the project dir), empty otherwise (empty is the lib's documented seam to
# skip the branch). PROJECT_ROOT is unchanged — telemetry below still uses it for
# the repo-relative path. Native Windows exposes home as %USERPROFILE%, not $HOME,
# so fall back to it; a missing home leaves the branch active (fail toward
# detection, never a false negative).
hpc_resolve_scan_root "$PROJECT_ROOT"

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
  # host). PROJECT_ROOT is the anchor the envelope itself carries, and the
  # scope guard above guarantees it is set, so no fallback root is needed.
  # The helper strips "$root/", so a root that already ends in a separator
  # makes the prefix "/repo//" and matches nothing: every in-project file
  # would collapse to its basename. PROJECT_ROOT comes from the caller-supplied
  # CLAUDE_PROJECT_DIR, where a trailing slash is a supported spelling, so trim
  # it here. The copy this replaced did the same.
  local file_rel
  file_rel="$(hook::repo_relative_path "$FILE" "${PROJECT_ROOT%/}")"
  local data
  data=$(jq -n --arg file "$file_rel" --argjson violations "$2" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "hardcoded-path-check" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# `$(…)` strips every trailing newline. Each violation block ends with a blank
# line terminator (`\n\n`); without a sentinel those separators vanish and the
# guidance line glues onto the last path (`…/repoUse portable alternatives:`).
# printf x absorbs the strip; peeling it restores the block terminators intact.
VIOLATIONS=$(
  hpp::scan_text "$CONTENT" "$SCAN_ROOT" "$FILE"
  printf x
)
VIOLATIONS=${VIOLATIONS%x}
if [[ -n "$VIOLATIONS" ]]; then
  {
    printf 'Hardcoded machine-specific path(s) in %s:\n\n' "$FILE"
    printf '%s' "$VIOLATIONS"
    # shellcheck disable=SC2016
    printf 'Use portable alternatives: ~/,  $HOME, $(pwd), $TMPDIR, '
    printf 'git rev-parse --show-toplevel, or <placeholder> notation.\n'
  } >&2
  # Telemetry labels = the block headers only (e.g. "Linux user path detected"),
  # never the matched lines — those carry the actual machine-specific path.
  # Process substitution, not `<<<`. $VIOLATIONS is NOT small: each block embeds
  # up to three MATCHED LINES verbatim, and the lib's `head -3` bounds the line
  # COUNT, not the byte count — one 65KB minified line carrying a hardcoded path
  # makes $VIOLATIONS payload-sized. A here-string of 65536-65663 bytes deadlocks
  # (see lib/path-detection/hardcoded-path-patterns.sh), and it would deadlock
  # HERE, on the blocked path, after the stderr message but before `exit 2` —
  # turning a detected violation into a hook the harness cancels at its timeout.
  labels_json=$(grep -E 'detected:$' < <(printf '%s' "$VIOLATIONS") 2>/dev/null | sed 's/:$//' | jq -Rn '[inputs]' 2>/dev/null) || labels_json='[]'
  emit_tel "blocked" "$labels_json"
  exit 2
fi

emit_tel "ok" '[]'
exit 0

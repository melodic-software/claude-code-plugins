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

# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

# Bundled pattern lib — resolved under the plugin root (CC sets
# CLAUDE_PLUGIN_ROOT; the BASH_SOURCE fallback keeps the contract tests working
# when it is unset).
PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
# shellcheck source=../lib/path-detection/hardcoded-path-patterns.sh
source "$PLUGIN_ROOT/lib/path-detection/hardcoded-path-patterns.sh"

hook::check_enabled "HARDCODED_PATH_CHECK"

# High-res start stamp for telemetry (Bash 5.0+; empty on older bash → skip).
start=${EPOCHREALTIME:-}

# jq is required to parse the tool payload. Fail OPEN when it is absent, but make
# the degraded state visible rather than silently disabling the guard.
if ! command -v jq >/dev/null 2>&1; then
  echo "guardrails/hardcoded-path-check: jq not found on PATH — guard disabled (install jq to enable)." >&2
  exit 0
fi

# hook::buffer_stdin encapsulates the Win32-pipe-safe bounded fd0 read; buffer
# once, parse each field from it. rc 1 (empty stdin) skips like the empty-field
# guards below; rc 2 (read timed out before a complete payload) FAILS CLOSED —
# the guard cannot evaluate the tool call, and a silent skip would pass exactly
# the traffic this guard exists to stop. buffer_stdin already printed the
# BLOCKED reason to stderr.
INPUT=$(hook::buffer_stdin) || {
  rc=$?
  ((rc == 2)) && exit 2
  exit 0
}
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null | tr -d '\r')

case "$TOOL" in
Write | Edit | NotebookEdit) ;;
*) exit 0 ;;
esac

FILE=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null | tr -d '\r')
[[ -n "$FILE" ]] || exit 0

# Normalize path separators for cross-platform case matching.
NORM_FILE="${FILE//\\//}"

# --- Scope guard: police only files inside THIS project ---
# A PreToolUse Write|Edit hook fires on every file write regardless of which
# repo the target lives in. A file outside the project root is not ours to scan
# — that repo owns its own path policy. Fail OPEN: when CLAUDE_PROJECT_DIR is
# unset, fall through and scan rather than skip.
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  _scope_file="$(hook::normalize_path "$FILE")"
  _scope_project="$(hook::normalize_path "${CLAUDE_PROJECT_DIR}")"
  _scope_project="${_scope_project%/}"
  case "$_scope_file" in
  "$_scope_project"/*) ;; # inside the project — proceed
  *) exit 0 ;;            # outside the project — not this hook's concern
  esac
fi

# Skip files that legitimately contain path patterns (regex strings). These
# cannot rely on the gitignore check below because they are tracked.
case "$NORM_FILE" in
# Hook / hook-manager scripts contain path-detection patterns as regex strings.
*.claude/hooks/* | *.lefthook/*) exit 0 ;;
# Claude Code session/workflow state (under ~/.claude/projects/) lives OUTSIDE
# any repo working tree and is never committed; absolute paths there are expected
# machine-local glue. The gitignore check below cannot catch it — the path is
# outside $CLAUDE_PROJECT_DIR, so `git check-ignore` errors rather than matching.
*.claude/projects/*) exit 0 ;;
*) ;;
esac

# Skip gitignored files — designated for machine-specific state (settings.local.json,
# CLAUDE.local.md, .venv/, node_modules/, etc.). git check-ignore does not require
# the file to exist on disk, so this works for new Write operations too.
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]] &&
  git -C "$CLAUDE_PROJECT_DIR" check-ignore -q "$FILE" 2>/dev/null; then
  exit 0
fi

# Extract content to check — Write has .content, Edit has .new_string,
# NotebookEdit has .new_source.
case "$TOOL" in
Write) CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.content // empty' 2>/dev/null | tr -d '\r') ;;
Edit) CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_string // empty' 2>/dev/null | tr -d '\r') ;;
NotebookEdit) CONTENT=$(printf '%s' "$INPUT" | jq -r '.tool_input.new_source // empty' 2>/dev/null | tr -d '\r') ;;
*) exit 0 ;; # unreachable — $TOOL filtered to Write|Edit|NotebookEdit above
esac
[[ -n "${CONTENT:-}" ]] || exit 0

# Resolve current repo root for the machine-specific-path check. Comments are
# NOT exempt — examples and "do not use" comments still ship as hardcoded paths
# in fresh clones, get copy-pasted, and rot. Use placeholders in comments too.
PROJECT_ROOT=""
if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
  PROJECT_ROOT=$CLAUDE_PROJECT_DIR
elif PROJECT_ROOT=$(git -C "$(dirname "$FILE")" rev-parse --show-toplevel 2>/dev/null); then
  :
else
  PROJECT_ROOT=""
fi

# issue #389 F1: hpp::scan_text's repo-path branch matches PROJECT_ROOT as a
# literal substring and is never OS-suppressed. That is a valid machine-specific
# marker ONLY when PROJECT_ROOT is a genuine git checkout that is not the user's
# home (nor an ancestor of it). When the project dir is home — e.g. a
# chezmoi-managed home, which is not itself a work tree — or any non-repo dir,
# every absolute path under it contains the root as a substring and would be
# hard-denied. Resolve a SCAN_ROOT the scanner uses for that branch: PROJECT_ROOT
# when it clears both gates, empty otherwise (empty is the lib's documented seam
# to skip the branch). PROJECT_ROOT is unchanged — telemetry below still uses it
# for the repo-relative path. Native Windows exposes home as %USERPROFILE%, not
# $HOME, so fall back to it; a missing home leaves the branch active (fail toward
# detection, never a false negative).
SCAN_ROOT=""
if [[ -n "$PROJECT_ROOT" ]] &&
  git -C "$PROJECT_ROOT" rev-parse --show-toplevel >/dev/null 2>&1; then
  _pr_norm="$(hook::normalize_path "$PROJECT_ROOT")"
  _pr_norm="${_pr_norm%/}"
  _home_norm="$(hook::normalize_path "${HOME:-${USERPROFILE:-}}")"
  _home_norm="${_home_norm%/}"
  if [[ -n "$_home_norm" && ( "$_pr_norm" == "$_home_norm" || "$_home_norm" == "$_pr_norm"/* ) ]]; then
    SCAN_ROOT="" # project dir is home or an ancestor of home — suppress the branch
  else
    SCAN_ROOT="$PROJECT_ROOT"
  fi
fi

# Repo-relative file for telemetry data.file (best-effort prefix strip).
FILE_REL="$FILE"
if [[ -n "$PROJECT_ROOT" ]]; then
  _root="${PROJECT_ROOT//\\//}"
  _root="${_root%/}"
  _fwd="${FILE//\\//}"
  FILE_REL="${_fwd#"$_root"/}"
fi
# Redaction: if the path could not be made repo-relative, emit the basename only
# — never an absolute path (it would embed the developer's username) into telemetry.
case "$FILE_REL" in
/* | [A-Za-z]:*)
  FILE_REL="${FILE_REL##*/}"
  FILE_REL="${FILE_REL##*\\}"
  ;;
*) ;;
esac

# Emit one telemetry envelope: $1 status, $2 labels JSON array. Gated on the
# high-res start stamp and the opt-in sink — the unwired path spawns nothing.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local data
  data=$(jq -n --arg file "$FILE_REL" --argjson violations "$2" \
    '{tool:"'"$TOOL"'",file:$file,violations:$violations}' 2>/dev/null) ||
    data='{"tool":"","file":"","violations":[]}'
  hook::emit_telemetry "hardcoded-path-check" "PreToolUse" "$1" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

VIOLATIONS=$(hpp::scan_text "$CONTENT" "$SCAN_ROOT" "$FILE")
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
  labels_json=$(grep -E 'detected:$' <<<"$VIOLATIONS" 2>/dev/null | sed 's/:$//' | jq -R . | jq -s . 2>/dev/null) || labels_json='[]'
  emit_tel "blocked" "$labels_json"
  exit 2
fi

emit_tel "ok" '[]'
exit 0

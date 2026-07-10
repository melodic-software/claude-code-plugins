#!/usr/bin/env bash
# PostToolUse hook: normalize a written file's working-tree line endings to its
# .gitattributes `eol=` value (symmetric, git check-attr-driven).
# Triggered on Write|Edit of any file in the consuming repo.
#
# ADVISORY / NON-BLOCKING: always exits 0. The normalization is best-effort;
# the consuming repo's commit hook / CI (editorconfig, git renormalize) remains
# the authoritative gate.
#
# CROSS-PLATFORM: both arms (CRLF->LF and LF->CRLF) run on every OS — the hook
# compensates for tool writes that bypass git's checkout smudge, and such
# writes happen on any platform.
#
# Uses the consuming repo's own .gitattributes — it ships no policy of its own.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and reused for both
# hook::read_file_path (file_path) and the tool_name parse; reading fd0 twice
# would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "EOL_NORMALIZER"

# Capture $EPOCHREALTIME immediately after the kill switch so duration_ms covers
# the work below. EPOCHREALTIME is Bash 5.0+; on older bash it is unset, so
# default to empty — referencing it bare under `set -u` would abort before the
# advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# normalizes on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

# The bundled EOL library (normalize_eol_file).
# Sourced from the plugin's own hooks dir so it is self-contained on install.
# shellcheck source=normalize-eol.sh
source "$(dirname "${BASH_SOURCE[0]}")/normalize-eol.sh"

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve the repo root that anchors `git check-attr` (CWD-independent — the hook
# process CWD is not guaranteed to be the repo root). File-anchored so it is
# correct for clones, linked worktrees, and bare-hub clones.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# Repo-relative path for the telemetry data.file. On Windows Git Bash,
# git rev-parse --show-toplevel returns a drive-letter path while FILE may be in
# POSIX mount form; normalize both through cygpath -lm (long, forward-slash mixed
# form) when available so the prefix strip compares the same representation. On
# Linux/macOS cygpath is absent and both paths are already POSIX. Falls back to
# raw FILE on any normalization error.
FILE_REL="$FILE"
if command -v cygpath >/dev/null 2>&1; then
  _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
  _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
  if [[ -n "$_file_lm" && -n "$_root_lm" ]]; then
    FILE_REL="${_file_lm#"$_root_lm"/}"
  fi
else
  FILE_REL="${FILE#"$REPO_ROOT"/}"
fi

# Build the telemetry data object. jq is authoritative; the fallback is a fixed
# empty-shape object (never an interpolation of TOOL/FILE_REL, which could inject
# quotes or backslashes from a path and corrupt the envelope).
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --arg action "$1" \
    '{tool:$tool,file:$file,action:$action}' 2>/dev/null \
    || printf '{"tool":"","file":"","action":""}'
}

# The lib mutates the file in place (side effect persists past the subshell) and
# echoes the action taken: lf | crlf | skip.
ACTION=$(normalize_eol_file "$REPO_ROOT" "$FILE")

# status "ok" when the file was actually normalized (lf/crlf); "skipped" when the
# attr was unspecified, the path is -text, or content sniffed binary.
case "$ACTION" in
  lf | crlf) status="ok" ;;
  *) status="skipped" ;;
esac

data_json=$(build_data_json "$ACTION")
emit_tel "eol-normalizer" "PostToolUse" "$status" "$start" "$data_json" "$REPO_ROOT"
exit 0

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
# shellcheck source=rewrite-guard.sh
source "$(dirname "${BASH_SOURCE[0]}")/rewrite-guard.sh"

hook::check_enabled "EOL_NORMALIZER"

# Capture $EPOCHREALTIME immediately after the kill switch so duration_ms covers
# the work below. EPOCHREALTIME is Bash 5.0+; on older bash it is unset, so
# default to empty — referencing it bare under `set -u` would abort before the
# advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 action taken.
# Two guards: the high-res start stamp (EPOCHREALTIME is Bash 5.0+; on older
# bash it is empty and telemetry is skipped, so the hook still normalizes
# rather than aborting) and the sink opt-in. The data payload costs a jq
# subprocess, so it is built here after both guards — never on the unwired
# path. This hook's matcher is every file write, so that is the hottest path in
# the fleet.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "eol-normalizer" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

# The bundled EOL library (normalize_eol_file).
# Sourced from the plugin's own hooks dir so it is self-contained on install.
# shellcheck source=normalize-eol.sh
source "$(dirname "${BASH_SOURCE[0]}")/normalize-eol.sh"

INPUT=$(hook::buffer_stdin) || exit 0

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of silently disabling the whole hook (dim-9 doctrine).
hook::require_jq PostToolUse eol-normalizer "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0

# Resolve the repo root that anchors `git check-attr` (CWD-independent — the hook
# process CWD is not guaranteed to be the repo root). File-anchored so it is
# correct for clones, linked worktrees, and bare-hub clones.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# TOOL and FILE_REL feed the telemetry data object and nothing else, so both are
# resolved only when a sink is wired: the unwired default path spawns zero
# telemetry-only subprocesses (the tool_name jq parse, and 2× cygpath on
# Windows).
#
# FILE_REL is the repo-relative path for the telemetry data.file, degrading to
# the basename when the prefix strip does not match, so an absolute path never
# reaches telemetry.
TOOL=""
FILE_REL="$FILE"
if hook::telemetry_enabled; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  FILE_REL="$(hook::repo_relative_path "$FILE" "$REPO_ROOT")"
fi

# Build the telemetry data object. jq is authoritative; the fallback is a fixed
# empty-shape object (never an interpolation of TOOL/FILE_REL, which could inject
# quotes or backslashes from a path and corrupt the envelope).
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --arg action "$1" \
    '{tool:$tool,file:$file,action:$action}' 2>/dev/null ||
    printf '{"tool":"","file":"","action":""}'
}

# The lib mutates the file in place (side effect persists past the subshell) and
# echoes the action taken: lf | crlf | skip. Content-mutation disclosure
# (#1596): line-ending normalization is a structural rewrite the user did not
# request; name what changed on the user channel and stay silent on skip/no-op
# paths. Snapshot lifecycle lives in the shared rewrite-guard lib (#3409); the
# taken message doubles as the changed/unchanged verdict EFFECTIVE_ACTION needs.
hook::rewrite_guard_begin "$FILE"
ACTION=$(normalize_eol_file "$REPO_ROOT" "$FILE")
case "$ACTION" in
lf) EOL_MSG="eol-normalizer: normalized line endings to LF in $(basename "$FILE")." ;;
crlf) EOL_MSG="eol-normalizer: normalized line endings to CRLF in $(basename "$FILE")." ;;
*) EOL_MSG="" ;;
esac
hook::rewrite_take_disclosure "$FILE" "$EOL_MSG"
if [[ -n "$HOOK_REWRITE_MESSAGE" ]]; then
  EFFECTIVE_ACTION="$ACTION"
else
  EFFECTIVE_ACTION="skip"
fi

# status "ok" when the file was actually normalized (lf/crlf); "skipped" when the
# attr was unspecified, the path is -text, content sniffed binary, or idempotent.
case "$EFFECTIVE_ACTION" in
lf | crlf) status="ok" ;;
*) status="skipped" ;;
esac

emit_tel "$status" "$ACTION"

[[ -n "$HOOK_REWRITE_MESSAGE" ]] && hook::emit_system_message "$HOOK_REWRITE_MESSAGE"

exit 0

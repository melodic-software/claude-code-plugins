#!/usr/bin/env bash
# PostToolUse hook: lint GitHub Actions workflow files via actionlint.
# Triggered on Write|Edit of .github/workflows/*.yml and *.yaml files.
#
# ADVISORY: always exits 0. actionlint findings surface via additionalContext
# but never block the edit. Make a commit hook or CI your hard gate.
#
# Graceful degrade: when actionlint is not on PATH the hook is a silent no-op
# (exit 0) — the plugin ships no binary of its own.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "ACTIONLINT"

# Capture $EPOCHREALTIME immediately after the kill-switch so duration_ms covers
# the work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash
# 5.0+; on older bash it is unset, so default to empty — referencing it bare
# under `set -u` would abort before the advisory exit 0.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# lints on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
# Only GitHub Actions workflow files. actionlint recognizes both .yml and .yaml
# under .github/workflows/; other YAML is not a workflow and must be skipped.
case "$FILE" in
  */.github/workflows/*.yml | */.github/workflows/*.yaml) ;;
  *) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used to compute the schema-required repo-relative
# path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"
# Repo-relative path: schema requires "relative to the consuming repo root".
# On Windows Git Bash, git rev-parse --show-toplevel returns a drive-letter path
# while FILE may be in POSIX mount form. Normalize both through cygpath -lm
# (long name, forward-slash mixed form) when available so the prefix strip
# compares the same representation. On Linux/macOS, cygpath is absent and both
# paths are already POSIX. Falls back to raw FILE on any normalization error.
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

# Build the telemetry data object for the current TOOL/FILE_REL. $1 is the
# findings JSON array. jq is authoritative. The fallback is a fixed empty-shape
# object — NOT an interpolation of TOOL/FILE_REL, which could inject quotes or
# backslashes from a path and corrupt the envelope. The fallback is essentially
# unreachable in practice (it fires only if `jq -n` fails, and when jq is absent
# hook::emit_telemetry drops the envelope anyway).
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null \
    || printf '{"tool":"","file":"","findings":[]}'
}

# Graceful degrade: actionlint absent -> silent no-op. Telemetry (opt-in) records
# a "skipped" status so a consumer sink can observe the coverage gap.
if ! command -v actionlint >/dev/null 2>&1; then
  data_json=$(build_data_json '[]')
  emit_tel "actionlint" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# -shellcheck= disables actionlint's embedded-bash ShellCheck integration. That
# integration spawns a ShellCheck subprocess per `run:` block, which (1) deadlocks
# on large blocks under the Windows subprocess IPC path in actionlint 1.7.x and
# (2) adds latency unsuited to an edit-time advisory hook. Native workflow
# diagnostics (the value of this hook) are unaffected; deep embedded-bash linting
# belongs in a commit hook or CI, not here.
AL_OUTPUT=$(actionlint -shellcheck= -- "$FILE" 2>&1) || true

if [[ -n "$AL_OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "actionlint: $(basename "$FILE") has findings:"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$AL_OUTPUT"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  data_json=$(build_data_json "$FINDINGS_JSON")
  emit_tel "actionlint" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# Clean workflow.
data_json=$(build_data_json '[]')
emit_tel "actionlint" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
exit 0

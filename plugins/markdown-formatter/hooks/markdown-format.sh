#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint Markdown via markdownlint-cli2.
# Triggered on Write|Edit of *.md and *.mdc (Cursor MDC = markdown + frontmatter).
#
# ADVISORY: always exits 0. markdownlint-cli2 --fix auto-format always applies;
# unfixable markdownlint violations surface via additionalContext but never
# block the edit. Uses the consuming repo's own markdownlint config — ships none.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "MARKDOWN_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# formatting work (pre-format exits below do not emit telemetry). EPOCHREALTIME is
# Bash 5.0+; on older bash it is unset, so default to empty — referencing it bare
# under `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array.
# Two guards: the high-res start stamp (EPOCHREALTIME is Bash 5.0+; on older
# bash it is empty and telemetry is skipped, so the hook still formats rather
# than aborting) and the sink opt-in. The data payload costs a jq subprocess,
# so it is built here after both guards — never on the unwired path.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "markdown-format" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
  *.md | *.mdc) ;;
  *) exit 0 ;;
esac

# Resolve repo root early — needed for CWD-anchored config discovery and for
# computing the schema-required repo-relative path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# Telemetry-payload precursors — TOOL and FILE_REL feed only the envelope's
# data object, so both are built only when a sink is wired: the unwired
# default path spawns zero telemetry-only subprocesses (the tool_name jq
# parse, and 2× cygpath on Windows).
#
# FILE_REL is the repo-relative path: schema requires "relative to the
# consuming repo root". On Windows Git Bash, git rev-parse --show-toplevel
# returns a drive-letter path while FILE may be in POSIX mount form. Normalize
# both through cygpath -lm (long name, forward-slash mixed form) when
# available so the prefix strip compares the same representation. On
# Linux/macOS, cygpath is absent and both paths are already POSIX. Falls back
# to raw FILE on any normalization error.
TOOL=""
FILE_REL="$FILE"
if hook::telemetry_enabled; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
  if command -v cygpath >/dev/null 2>&1; then
    _file_lm=$(cygpath -lm "$FILE" 2>/dev/null)
    _root_lm=$(cygpath -lm "$REPO_ROOT" 2>/dev/null)
    if [[ -n "$_file_lm" && -n "$_root_lm" ]]; then
      FILE_REL="${_file_lm#"$_root_lm"/}"
    fi
  else
    FILE_REL="${FILE#"$REPO_ROOT"/}"
  fi
fi

# Build the telemetry data object for the current TOOL/FILE_REL. $1 is the
# findings JSON array. jq is authoritative. The fallback is a fixed empty-shape
# object — NOT an interpolation of TOOL/FILE_REL, which could inject quotes or
# backslashes from a path and corrupt the envelope. The fallback is essentially
# unreachable in practice (it fires only if `jq -n` fails, and when jq is absent
# hook::emit_telemetry drops the envelope anyway), so losing the values here is
# harmless and strictly safer than emitting malformed JSON.
build_data_json() {
  jq -n \
    --arg tool     "$TOOL" \
    --arg file     "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null \
    || printf '{"tool":"","file":"","findings":[]}'
}

MDLINT=()
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  MDLINT=(markdownlint-cli2)
elif command -v npx >/dev/null 2>&1; then
  MDLINT=(npx markdownlint-cli2)
else
  # markdownlint unavailable — emit skipped telemetry then exit cleanly.
  emit_tel "skipped" '[]'
  exit 0
fi

if FIX_OUTPUT=$(cd "$REPO_ROOT" && "${MDLINT[@]}" --fix "$FILE" 2>&1); then
  # Clean after fix — emit ok with empty findings.
  emit_tel "ok" '[]'
  exit 0
fi

# Residual findings — surface via additionalContext, then emit ok with findings.
# ctx_append receives all output lines (human-readable context for Claude Code).
# FINDINGS_JSON is filtered to violation lines only — schema requires
# "Unfixable markdownlint violations remaining after --fix, one per line";
# banner/diagnostic lines (version, Finding:, Linting:, Summary:) are excluded.
# Violation lines are identified by the " MD<digits>/" rule-code pattern.
hook::ctx_reset
hook::ctx_append "markdown-format: $(basename "$FILE") has markdownlint findings:"
findings_raw=""
while IFS= read -r line; do
  hook::ctx_append "  $line"
  if [[ "$line" =~ [[:space:]]MD[0-9]+/ ]]; then
    findings_raw+="$line"$'\n'
  fi
done <<<"$FIX_OUTPUT"
hook::ctx_flush PostToolUse

# Build the findings array in one jq pass (one JSON string per matched line).
FINDINGS_JSON='[]'
if [[ -n "$findings_raw" ]]; then
  FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
fi

emit_tel "ok" "$FINDINGS_JSON"
exit 0

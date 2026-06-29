#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint JS/TS/JSX/JSON files via Biome.
# Triggered on Write|Edit of *.ts, *.tsx, *.js, *.jsx, *.mjs, *.cjs, *.mts,
# *.cts, *.json, *.jsonc files.
#
# ADVISORY: always exits 0. `biome check --write` applies safe fixes, formatting,
# and import sorting; residual Biome diagnostics (errors and, via
# --error-on-warnings, warnings) surface via additionalContext but never block
# the edit. A commit hook or CI is the hard gate.
#
# Opt-in: Biome runs ONLY when a biome.json (or .jsonc / dotted) config governs
# the edited file — found by walking up from the file to the repo root. A repo
# that has not adopted a Biome config is left untouched rather than rewritten to
# Biome's built-in defaults, so the plugin never imposes a style it did not
# choose. The Biome binary is resolved from the repo's own node_modules (or PATH)
# — never downloaded.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BIOME_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# formats and lints on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
  *.ts | *.tsx | *.js | *.jsx | *.mjs | *.cjs | *.mts | *.cts | *.json | *.jsonc) ;;
  *) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used to bound the biome-config opt-in walk and to
# compute the schema-required repo-relative path in data.file.
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
# hook::emit_telemetry drops the envelope anyway), so losing the values here is
# harmless and strictly safer than emitting malformed JSON.
build_data_json() {
  jq -n \
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null \
    || printf '{"tool":"","file":"","findings":[]}'
}

emit_skipped() {
  local data_json
  data_json=$(build_data_json '[]')
  emit_tel "biome-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

# Resolve the file's directory in `pwd` form once. Both walks below start here,
# and it anchors the CONFIG_DIR-relative path passed to Biome.
FILE_DIR_POSIX="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)" || FILE_DIR_POSIX=""
root="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || root=""

# Consumer opt-in: a Biome configuration that governs the edited file. Walk up
# from the file's directory to the repo root, recording the TOPMOST config dir
# (closest to the repo root). Biome discovers its configuration from the CWD
# upward — not from the target file — and a "root" config orchestrates any nested
# (`"root": false`) configs beneath it, so running from the topmost config's
# directory is the correct, monorepo-safe CWD. Absence of any config is the
# opt-out: the file is left untouched.
CONFIG_DIR=""
dir="$FILE_DIR_POSIX"
while [[ -n "$dir" ]]; do
  for name in biome.json biome.jsonc .biome.json .biome.jsonc; do
    [[ -f "$dir/$name" ]] && CONFIG_DIR="$dir" && break
  done
  [[ -n "$root" && "$dir" == "$root" ]] && break
  parent="$(dirname "$dir")"
  [[ "$parent" == "$dir" ]] && break # reached filesystem root
  dir="$parent"
done

[[ -n "$CONFIG_DIR" ]] || emit_skipped

# Resolve the Biome binary from the repo's own install (node_modules/.bin/biome,
# walking up from the file) or PATH — never `npx`, which would download Biome on
# a per-edit hook. Absent -> skip (the repo opted into config but Biome is not
# installed; nothing to run).
BIOME_BIN=""
dir="$FILE_DIR_POSIX"
while [[ -n "$dir" ]]; do
  if [[ -f "$dir/node_modules/.bin/biome" ]]; then
    BIOME_BIN="$dir/node_modules/.bin/biome"
    break
  fi
  [[ -n "$root" && "$dir" == "$root" ]] && break
  parent="$(dirname "$dir")"
  [[ "$parent" == "$dir" ]] && break
  dir="$parent"
done
if [[ -z "$BIOME_BIN" ]]; then
  BIOME_BIN="$(command -v biome 2>/dev/null)" || BIOME_BIN=""
fi

[[ -n "$BIOME_BIN" ]] || emit_skipped

# Pass the file as a path relative to CONFIG_DIR (the CWD Biome runs in) so the
# github reporter echoes a clean repo-relative path (e.g. src/app.ts) instead of
# an absolute, URL-encoded one. CONFIG_DIR and FILE_DIR_POSIX both come from
# `pwd`, so the prefix strip compares the same form; CONFIG_DIR is an ancestor of
# the file, so it always matches. Falls back to the absolute path if it does not.
BIOME_ARG="$FILE"
if [[ -n "$FILE_DIR_POSIX" ]]; then
  _file_posix="$FILE_DIR_POSIX/$(basename "$FILE")"
  _rel="${_file_posix#"$CONFIG_DIR"/}"
  [[ "$_rel" != "$_file_posix" ]] && BIOME_ARG="$_rel"
fi

# Run Biome from the governing config's directory (CWD-anchored discovery).
# `check` = format + lint + import sorting; --write applies safe fixes;
# --error-on-warnings makes residual warnings (not just errors) exit non-zero so
# they surface as advisory context. --reporter=github emits one compact
# workflow-command line per diagnostic (::warning/::error/::notice with rule,
# file, line, and message) instead of the verbose default boxes — the analog of
# ShellCheck's gcc format: actionable findings without the decorative noise.
if OUTPUT=$(cd "$CONFIG_DIR" && "$BIOME_BIN" check --write --error-on-warnings --reporter=github "$BIOME_ARG" 2>&1); then
  data_json=$(build_data_json '[]')
  emit_tel "biome-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# Non-zero exit. The github reporter emits one `::warning`/`::error`/`::notice`
# line per diagnostic; their presence is the unambiguous signal that Biome made a
# lint/format judgment with residual findings. Surface just those lines (not the
# decorative footer). Status "ok" — the linter RAN and produced a judgment
# (findings live in data.findings), mirroring the bash-lint model where status
# reflects whether the tool ran, not whether it was clean.
FINDINGS=$(grep -E '^::(warning|error|notice)' <<<"$OUTPUT" || true)
if [[ -n "$FINDINGS" ]]; then
  hook::ctx_reset
  hook::ctx_append "biome-format: $(basename "$FILE") has Biome findings (advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$FINDINGS"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  data_json=$(build_data_json "$FINDINGS_JSON")
  emit_tel "biome-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# No findings, but the file was deliberately ignored by the consumer's Biome
# config (or a built-in default ignore such as node_modules). Biome exits 1 with
# "No files were processed in the specified paths." — this is the repo's opt-out,
# not a finding and not a break, so skip silently without nagging via context.
# (Biome 2.x respects files.includes ignores even for explicitly-passed paths.)
if grep -qE 'No files were processed|provided but ignored' <<<"$OUTPUT"; then
  emit_skipped
fi

# Biome broke for non-lint reasons (config parse error, panic, ENOENT) — no
# judgment was made. Surface the diagnostic via additionalContext (NOT stderr —
# an advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (the linter never ran), the same status as the no-config /
# no-binary paths.
hook::ctx_reset
hook::ctx_append "biome-format: biome failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  hook::ctx_append "  $line"
done <<<"$OUTPUT"
hook::ctx_flush PostToolUse
data_json=$(build_data_json '[]')
emit_tel "biome-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
exit 0

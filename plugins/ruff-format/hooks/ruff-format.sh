#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint Python files via Ruff.
# Triggered on Write|Edit of *.py and *.pyi files.
#
# ADVISORY: always exits 0. `ruff check --fix` applies safe fixes and
# `ruff format` formats in place; residual diagnostics surface via
# additionalContext but never block the edit. A commit hook or CI is the hard
# gate.
#
# Opt-in: Ruff runs ONLY when a Ruff configuration governs the edited file — a
# .ruff.toml, ruff.toml, or pyproject.toml with a [tool.ruff] section, found by
# walking up from the file to the repo root (Ruff ignores a pyproject.toml
# without [tool.ruff] for discovery, so the gate does too). A repo that has not
# adopted a Ruff config is left untouched rather than rewritten to Ruff's
# built-in defaults, so the plugin never imposes a style it did not choose. The
# Ruff binary is resolved from the repo's own .venv (or PATH) — never
# downloaded.
#
# --unfixable F401 protects just-added imports: during iterative editing an
# import often lands one edit before the code that uses it, and Ruff's F401
# auto-fix would delete it in between. The flag EXTENDS the consumer config's
# own unfixable list rather than replacing it (verified against ruff 0.15).
# F401 still surfaces as an advisory finding — only the auto-deletion is
# suppressed.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "RUFF_FORMAT"

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

# jq-free applicability pre-filter: never emit the jq notice for an edit this
# hook would not process anyway (the Write|Edit matcher is broader than the
# Python-file filter).
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
case "$RAW_FILE" in
*.py | *.pyi) ;;
*) exit 0 ;;
esac

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine).
hook::require_jq PostToolUse ruff-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.py | *.pyi) ;;
*) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used to bound the config opt-in walk and to compute
# the schema-required repo-relative path in data.file.
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
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

emit_skipped() {
  local data_json
  data_json=$(build_data_json '[]')
  emit_tel "ruff-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

# Resolve the file's directory in `pwd` form once. Both walks below start here,
# and it anchors the repo-root-relative path passed to Ruff.
FILE_DIR_POSIX="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)" || FILE_DIR_POSIX=""
root="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || root=""

# Consumer opt-in: a Ruff configuration that governs the edited file. Walk up
# from the file's directory to the repo root, stopping at the FIRST config found
# — Ruff itself resolves the closest config per file (file-anchored, not
# CWD-anchored), so the closest hit is exactly the config that will govern the
# run. Same-directory precedence mirrors Ruff's (.ruff.toml > ruff.toml >
# pyproject.toml). A pyproject.toml counts only when it carries a [tool.ruff]
# section (or a [tool.ruff.*] subtable) — Ruff skips it for discovery otherwise.
# Absence of any config is the opt-out: the file is left untouched.
CONFIG_FOUND=""
dir="$FILE_DIR_POSIX"
while [[ -n "$dir" ]]; do
  for name in .ruff.toml ruff.toml; do
    [[ -f "$dir/$name" ]] && CONFIG_FOUND="$dir/$name" && break
  done
  if [[ -z "$CONFIG_FOUND" && -f "$dir/pyproject.toml" ]] &&
    grep -qE '^[[:space:]]*\[tool\.ruff(\]|[.])' "$dir/pyproject.toml" 2>/dev/null; then
    CONFIG_FOUND="$dir/pyproject.toml"
  fi
  [[ -n "$CONFIG_FOUND" ]] && break
  [[ -n "$root" && "$dir" == "$root" ]] && break
  parent="$(dirname "$dir")"
  [[ "$parent" == "$dir" ]] && break # reached filesystem root
  dir="$parent"
done

[[ -n "$CONFIG_FOUND" ]] || emit_skipped

# Resolve the Ruff binary from the repo's own virtual environment (.venv,
# walking up from the file; bin/ on POSIX, Scripts/ on Windows) or PATH — never
# `uvx`/`pipx run`, which would download Ruff on a per-edit hook. Absent -> skip
# (the repo opted into config but Ruff is not installed; nothing to run).
RUFF_BIN=""
dir="$FILE_DIR_POSIX"
while [[ -n "$dir" ]]; do
  for cand in "$dir/.venv/bin/ruff" "$dir/.venv/Scripts/ruff.exe"; do
    if [[ -x "$cand" ]]; then
      RUFF_BIN="$cand"
      break
    fi
  done
  [[ -n "$RUFF_BIN" ]] && break
  [[ -n "$root" && "$dir" == "$root" ]] && break
  parent="$(dirname "$dir")"
  [[ "$parent" == "$dir" ]] && break
  dir="$parent"
done
if [[ -z "$RUFF_BIN" ]]; then
  RUFF_BIN="$(command -v ruff 2>/dev/null)" || RUFF_BIN=""
fi

# The repo opted in via a Ruff config but no binary is available → visible
# once-per-session skip notice, not a silent gap (dim-9 doctrine).
if [[ -z "$RUFF_BIN" ]]; then
  if hook::notice_once "ruff-format-ruff" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "ruff-format: a Ruff config governs this repo but no 'ruff' binary was found (.venv or PATH) — format/lint skipped for this session. Install: https://docs.astral.sh/ruff/installation/"
  fi
  emit_skipped
fi

# Pass the file as a path relative to the repo root (the CWD Ruff runs in) so
# concise diagnostics echo a clean repo-relative path (e.g. src/app.py) instead
# of an absolute one. FILE_REL already holds that path, computed above with
# cygpath long-form normalization — a raw prefix strip against `pwd` output is
# NOT enough on Windows Git Bash, where the same directory can surface as
# /tmp/..., /c/..., or a short-name (KYLESE~1) form depending on how it was
# reached. Falls back to the absolute path when the repo root did not resolve
# (RUN_DIR would not anchor FILE_REL) or the file is outside it.
RUFF_ARG="$FILE"
RUN_DIR="${root:-$FILE_DIR_POSIX}"
if [[ -n "$root" && -n "$FILE_REL" && "$FILE_REL" != "$FILE" ]]; then
  RUFF_ARG="$FILE_REL"
fi

# Common flags for every Ruff invocation. --force-exclude honors the config's
# exclude/extend-exclude even for this explicitly-passed path, so a file the
# repo excludes (generated or vendored code) is left untouched with no advisory
# noise. --no-cache keeps Ruff from writing a .ruff_cache directory into the
# consumer's repo on every edit — a single-file run gains nothing from the
# cache. Discovery is file-anchored, so the config that governs is the repo's
# own regardless of flags.
RUFF_COMMON=(--force-exclude --no-cache --quiet)

# Pass 1: apply safe lint fixes, keeping F401 unfixable per the header
# rationale. --no-unsafe-fixes is explicit, not the default restated: a
# consumer config may set unsafe-fixes = true, aimed at interactive runs —
# an unattended edit-time pass must never apply fixes Ruff itself labels as
# possibly not intent-preserving (same principle as --no-fix on the verify
# pass below). Pass 2: format. Both are best-effort; the verify pass below
# is the single source of residual findings.
(cd "$RUN_DIR" && "$RUFF_BIN" check --fix --no-unsafe-fixes --unfixable F401 "${RUFF_COMMON[@]}" "$RUFF_ARG") >/dev/null 2>&1 || true
(cd "$RUN_DIR" && "$RUFF_BIN" format "${RUFF_COMMON[@]}" "$RUFF_ARG") >/dev/null 2>&1 || true

# Verify pass — a pure reporter. --no-fix matters: a consumer config may set
# fix=true, which would make a bare `ruff check` re-apply fixes here, including
# the F401 deletion the --unfixable guard above just prevented. One concise
# line per diagnostic; syntax errors (including target-version-aware ones —
# Ruff's parser flags syntax not yet valid on the configured Python floor)
# arrive on the same channel. Exit 0 = clean, 1 = findings, 2 = Ruff itself
# failed (bad config, internal error).
OUTPUT=$(cd "$RUN_DIR" && "$RUFF_BIN" check --no-fix --output-format concise "${RUFF_COMMON[@]}" "$RUFF_ARG" 2>&1)
RC=$?

if [[ $RC -eq 0 ]]; then
  data_json=$(build_data_json '[]')
  emit_tel "ruff-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

if [[ $RC -eq 1 && -n "$OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "ruff-format: $(basename "$FILE") has Ruff findings (advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$OUTPUT"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  data_json=$(build_data_json "$FINDINGS_JSON")
  # Status "ok" — the linter RAN and produced a judgment (findings live in
  # data.findings), mirroring the sibling formatter plugins where status
  # reflects whether the tool ran, not whether it was clean.
  emit_tel "ruff-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# Ruff broke for non-lint reasons (config parse error, internal error) — no
# judgment was made. Surface the diagnostic via additionalContext (NOT stderr —
# an advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (the linter never ran to judgment), the same status as the
# no-config / no-binary paths.
hook::ctx_reset
hook::ctx_append "ruff-format: ruff failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  hook::ctx_append "  $line"
done <<<"$OUTPUT"
hook::ctx_flush PostToolUse
data_json=$(build_data_json '[]')
emit_tel "ruff-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
exit 0

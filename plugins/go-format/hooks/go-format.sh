#!/usr/bin/env bash
# PostToolUse hook: auto-format Go source files via gofmt.
# Triggered on Write|Edit of *.go files.
#
# ADVISORY: always exits 0. `gofmt -w` reformats in place; a syntax error
# (gofmt cannot format code it cannot parse — common mid-edit) surfaces via
# additionalContext but never blocks the edit. A commit hook or CI is the
# hard gate.
#
# Unconditional: gofmt ships with the Go toolchain and has no configuration
# surface — there is one canonical Go style, unlike Ruff/Prettier-class
# formatters with per-repo rule config — so this hook runs on every *.go edit
# regardless of repo configuration, matching the sibling typos-format/
# markdown-format hooks' unconditional pattern. The gofmt binary is resolved
# from PATH only — never downloaded (it ships alongside `go` in the Go
# distribution's bin directory; a repo with `go` on PATH has `gofmt` too).
#
# Formatter choice (field survey — gofmt vs goimports vs gofumpt vs
# `golangci-lint fmt`): gofmt is the only candidate safe to run unconditionally
# on every edit. goimports removes unreferenced imports — the same hazard
# ruff-format's --unfixable F401 guard exists to prevent for Python, but Go
# imports have no per-tool "unfixable" escape hatch, so goimports would delete
# an import added one edit before the code that uses it. gofumpt (mvdan.cc/
# gofumpt) is third-party and stricter-than-canonical, an opinion this plugin
# does not ship unconditionally. `golangci-lint fmt` requires an explicit
# `formatters.enable` in the repo's own golangci-lint v2 config — verified
# empirically against golangci-lint v2.12.2 (pkg/config/config.go's
# NewDefault leaves Formatters.Enable empty with no config file) that it runs
# zero formatters with none, so it cannot be this hook's unconditional
# default either. Import-organizing and stricter formatting stay available as
# an opt-in through the toolchain plugin's batch `go` ecosystem entry
# (reference/ecosystems/go.yaml) once a repo configures them.
#
# KNOWN RISK (not fixed here): Claude Code runs every matching PostToolUse
# hook in parallel for one tool call. This hook has no interaction with other
# format hooks (its *.go filter never overlaps another shipped hook's
# extension filter), so the clobber race documented in typos-format.sh
# (language-agnostic hooks racing an extension-scoped one) does not apply
# here.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "GO_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# formats on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice for an edit this
# hook would not process anyway (the Write|Edit matcher is broader than the
# Go-file filter).
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
case "$RAW_FILE" in
*.go) ;;
*) exit 0 ;;
esac

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine).
hook::require_jq PostToolUse go-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.go) ;;
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
  emit_tel "go-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

# Resolve gofmt from PATH only — never downloaded. gofmt ships in the Go
# distribution's bin directory alongside `go`, so a repo with the Go
# toolchain on PATH has it too.
GOFMT_BIN="$(command -v gofmt 2>/dev/null)" || GOFMT_BIN=""

# No binary available → visible once-per-session skip notice, not a silent gap
# (dim-9 doctrine).
if [[ -z "$GOFMT_BIN" ]]; then
  if hook::notice_once "go-format-gofmt" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "go-format: no 'gofmt' binary was found on PATH — Go format skipped for this session. Install the Go toolchain: https://go.dev/dl/"
  fi
  emit_skipped
fi

# Reformat in place. gofmt parses before writing: on a syntax error it writes
# nothing (verified empirically against Go 1.26.5 — the file is left
# byte-for-byte untouched) and reports one "file:line:col: message" diagnostic
# per line on stderr with exit 2. Exit 0 = clean or successfully reformatted.
OUTPUT=$("$GOFMT_BIN" -w "$FILE" 2>&1)
RC=$?

if [[ $RC -eq 0 ]]; then
  data_json=$(build_data_json '[]')
  emit_tel "go-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

if [[ -n "$OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "go-format: $(basename "$FILE") could not be formatted (syntax error — left unchanged):"
  findings_raw="[]"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    # Parse "file:line:col: message" — gofmt's own diagnostic format. The
    # leading path is matched greedily (.+), not [^:]*, because the file path
    # itself can contain a colon (a Windows drive letter, e.g. "C:/Users/...")
    # that would otherwise be mistaken for the line-number separator.
    if [[ "$line" =~ ^.+:([0-9]+):([0-9]+):[[:space:]]*(.*)$ ]]; then
      obj=$(jq -n \
        --arg l "${BASH_REMATCH[1]}" \
        --arg c "${BASH_REMATCH[2]}" \
        --arg m "${BASH_REMATCH[3]}" \
        '{line:($l|tonumber),col:($c|tonumber),message:$m}' 2>/dev/null) || continue
      findings_raw=$(printf '%s' "$findings_raw" | jq -c --argjson f "$obj" '. + [$f]' 2>/dev/null) || true
    fi
  done <<<"$OUTPUT"
  hook::ctx_flush PostToolUse

  data_json=$(build_data_json "$findings_raw")
  # Status "ok" — gofmt RAN and produced a judgment (a syntax diagnostic lives
  # in data.findings), mirroring the sibling formatter plugins where status
  # reflects whether the tool ran, not whether the file was clean.
  emit_tel "go-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# gofmt broke for non-diagnostic reasons (no stderr output yet non-zero exit —
# an internal error) — no judgment was made. Record as "skipped" (gofmt never
# ran to judgment), the same status as the no-binary path.
data_json=$(build_data_json '[]')
emit_tel "go-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
exit 0

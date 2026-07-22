#!/usr/bin/env bash
# PostToolUse hook: auto-format and manage imports for Go files via goimports.
# Triggered on Write|Edit of *.go files.
#
# ADVISORY: always exits 0. `goimports -w` rewrites the file in place;
# a residual syntax error goimports cannot parse surfaces via
# additionalContext but never blocks the edit. A commit hook or CI is the
# hard gate.
#
# UNCONDITIONAL — no consumer-config opt-in gate, unlike the sibling
# ruff-format/typos-format/dotnet ecosystem entry. goimports' own docs state
# it "formats your code in the same style as gofmt so it can be used as a
# replacement for your editor's gofmt-on-save hook" — an explicit official
# statement of intent for exactly this per-file/on-save scenario, and it has
# no meaningful config-divergence axis when left unconfigured (unlike
# ruff/dotnet format, whose underlying tools DO have configurable, genuinely
# divergent output).
#
# GENERATED-FILE GUARD: goimports has zero awareness of Go's own
# `// Code generated ... DO NOT EDIT.` convention — empirically confirmed it
# rewrites such files with no warning. Generated Go files (protobuf, mockgen,
# sqlc, stringer, wire output) are common; this hook skips any file whose
# leading comment/blank-line block (scanned below) contains that marker,
# mirroring the precision `--force-exclude` gives Ruff/typos for free via
# consumer config (this hook has no config to consult, so the marker check
# is the equivalent guard).
#
# The goimports binary is resolved from PATH only — never downloaded. Go
# binaries are conventionally `go install`ed to $GOPATH/bin, which a
# developer adds to PATH themselves; there is no per-project virtualenv
# concept in Go the way ruff-format walks a .venv.

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
# backslashes from a path and corrupt the envelope.
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

# Generated-file guard: skip files carrying Go's canonical generated-code
# marker — goimports itself has no awareness of this convention (empirically
# confirmed it rewrites such files silently). Go's own convention (`go help
# generate`, verified live: "This line must appear before the first
# non-comment, non-blank text in the file") does not restrict "comment" to
# `//` style — a `/* ... */` block comment (e.g. a conventional block
# license header) is a comment for this purpose too, so it must not end the
# leading-block scan early. Scan the file's leading comment/blank-line run,
# tracking open `/* */` blocks, and stop only at the first line that is
# genuinely neither blank, a `//` comment, nor inside/starting a `/* */`
# block (e.g. `package foo`). A trailing CRLF `\r` and a leading UTF-8 BOM
# are stripped per line so a Windows-checked-out or BOM-prefixed file still
# matches. (The marker itself can only ever appear on a `//`-prefixed line —
# `^// Code generated .* DO NOT EDIT\.$` — never inside a `/* */` block, so
# block-comment lines are only ever scanned-through, not matched against.)
#
# APPROXIMATION: this string-match scan is a deliberate stand-in for Go's own
# `ast.IsGenerated`, which classifies a *parsed* `*ast.File` (via `go/parser`).
# The two cannot be made equal by adding patterns — the gap is structural, so
# exotic shapes (unusual build-tag/comment interleavings, nested block
# comments, atypical Unicode whitespace) can keep surfacing indefinitely. That
# is tolerable because the guard is advisory (see ADVISORY, top of file): an
# unhandled shape only means goimports reformats a generated file — visible in
# the diff, no gate broken. So no further pattern patches are planned unless a
# *real-world* generated file is observed defeating this scan; a synthetic
# counter-example alone is not enough. The actual structural fix, should a real
# case ever warrant it, is to shell out to the `go` toolchain (`go/parser` plus
# the real `ast.IsGenerated` logic) instead of extending this matcher — not
# done here because it would add per-edit latency and a hard `go`-toolchain
# dependency this hook otherwise keeps optional (only `-local` grouping needs
# `go`).
GENERATED=0
IN_BLOCK=0
while IFS= read -r _line || [[ -n "$_line" ]]; do
  _line="${_line%$'\r'}"
  _line="${_line#$'\xEF\xBB\xBF'}"
  if [[ $IN_BLOCK -eq 1 ]]; then
    [[ "$_line" == *'*/'* ]] && IN_BLOCK=0
    continue # still inside (or just closed) a block comment: keep scanning
  fi
  [[ -n "${_line//[[:space:]]/}" ]] || continue # blank line (any whitespace, incl. tabs): keep scanning the leading block
  # Trimmed only for comment-shape classification (an indented `//`/`/*`
  # still counts as "still within the leading comment block") — the marker
  # regex itself stays column-0-anchored, matching Go's own convention.
  _trimmed="${_line#"${_line%%[![:space:]]*}"}"
  if [[ "$_line" == //* ]]; then
    if [[ "$_line" =~ ^//\ Code\ generated\ .*\ DO\ NOT\ EDIT\.$ ]]; then
      GENERATED=1
    fi
    [[ $GENERATED -eq 1 ]] && break
    continue # a different // comment line: still within the leading block
  fi
  if [[ "$_trimmed" == //* ]]; then
    continue # an indented // comment line: still within the leading block
  fi
  if [[ "$_trimmed" == /\** ]]; then
    [[ "$_trimmed" == *'*/'* ]] || IN_BLOCK=1 # opens a block comment spanning further lines
    continue # an indented /* ... */ comment (single- or multi-line): still within the leading block
  fi
  break # first non-comment, non-blank line: leading block ended, marker absent
done <"$FILE"
[[ $GENERATED -eq 1 ]] && emit_skipped

# Resolve the goimports binary from PATH — never downloaded.
GOIMPORTS_BIN="$(command -v goimports 2>/dev/null)" || GOIMPORTS_BIN=""

if [[ -z "$GOIMPORTS_BIN" ]]; then
  if hook::notice_once "go-format-goimports" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "go-format: no 'goimports' binary found on PATH — format/import-fix skipped for this session. Install: go install golang.org/x/tools/cmd/goimports@latest"
  fi
  emit_skipped
fi

# Auto-derive goimports' -local grouping prefix from the edited file's own
# module path (`go list -m`, which walks up to the nearest go.mod using
# Go's own module resolution — more robust than hand-parsing the module
# directive). Without -local, goimports lumps a repo's own internal
# packages into the same group as third-party imports; a repo that already
# formats with -local (a common Go convention, e.g. wired into its own CI
# or editor config) would have this hook re-collapse that grouping on every
# edit — empirically confirmed this materially changes output when a
# third-party import is also present. Deriving the LOCAL prefix from the
# file's own module path (self-grouping) requires no new consumer-config
# surface, so it stays within the unconditional/no-opt-in design while
# covering the single most common -local use case. `go` absent, the file
# outside any module, or any other resolution failure all degrade to no
# -local flag (goimports' plain default grouping), never a hard stop.
LOCAL_PREFIX=""
if command -v go >/dev/null 2>&1; then
  LOCAL_PREFIX="$(cd "$(dirname "$FILE")" 2>/dev/null && go list -m 2>/dev/null)" || LOCAL_PREFIX=""
  [[ "$LOCAL_PREFIX" == "command-line-arguments" ]] && LOCAL_PREFIX=""
fi
GOIMPORTS_ARGS=(-w -l)
[[ -n "$LOCAL_PREFIX" ]] && GOIMPORTS_ARGS+=(-local "$LOCAL_PREFIX")

# -w writes the fix in place; -l (combined with -w) lists the changed
# filename on stdout, which this hook doesn't need (a successful autofix
# carries no advisory noise, same posture as a successful ruff/typos fix
# pass — only a genuine syntax error below produces a finding). Verified
# empirically (goimports v0.48.0): -l ALWAYS exits 0, even when it lists a
# file — there is no exit-1-style "findings" signal like ruff/typos have.
# Non-zero exit (verified: 2, with a parseable message on stderr) occurs
# only on a genuine parse/syntax error — captured via command substitution
# (stdout discarded, stderr redirected to fd1) the same way every sibling
# hook in this repo captures tool output, rather than a temp file. `--`
# ends flag parsing before $FILE — defense-in-depth against a path that
# happens to start with `-` being misread as a flag by Go's flag package.
STDERR=$("$GOIMPORTS_BIN" "${GOIMPORTS_ARGS[@]}" -- "$FILE" 2>&1 >/dev/null)
RC=$?

if [[ $RC -eq 0 ]]; then
  # Clean, or fixed silently (formatting/import changes carry no advisory
  # noise — same posture as a successful ruff/typos autofix pass).
  data_json=$(build_data_json '[]')
  emit_tel "go-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

if [[ $RC -eq 2 && -n "$STDERR" ]]; then
  # goimports ran and produced a judgment: the file has a syntax error it
  # cannot parse. This is a finding, not a tool break — mirrors how
  # ruff-format surfaces a mid-edit syntax error as a finding.
  hook::ctx_reset
  hook::ctx_append "go-format: $(basename "$FILE") has a syntax error goimports could not parse (advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    hook::ctx_append "  $line"
    findings_raw+="$line"$'\n'
  done <<<"$STDERR"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  data_json=$(build_data_json "$FINDINGS_JSON")
  emit_tel "go-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# goimports broke for non-syntax reasons (internal error, unexpected exit
# code) — no judgment was made. Surface the diagnostic via additionalContext
# (NOT stderr — an advisory hook's exit-0 stderr can trip a false "Hook
# Error" label). Record as "skipped" (the tool never ran to judgment).
hook::ctx_reset
hook::ctx_append "go-format: goimports failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  hook::ctx_append "  $line"
done <<<"$STDERR"
hook::ctx_flush PostToolUse
data_json=$(build_data_json '[]')
emit_tel "go-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
exit 0

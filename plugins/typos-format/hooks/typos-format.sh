#!/usr/bin/env bash
# PostToolUse hook: auto-fix source-code spelling mistakes via typos.
# Triggered on every Write|Edit — typos is a cross-language spell checker, not
# a single-ecosystem formatter, so no extension filter narrows it; typos' own
# binary-content detection and the consumer's _typos.toml [files] excludes
# (honored via --force-exclude below) decide what actually gets checked.
#
# ADVISORY: always exits 0. `typos -w` auto-fixes every unambiguous typo;
# residual findings (ambiguous corrections typos declines to apply
# unassisted) surface via additionalContext but never block the edit. A
# commit hook or CI is the hard gate.
#
# Zero-config: typos ships a built-in dictionary and runs immediately with no
# required setup — it ships none of its own rules and imposes nothing beyond
# that dictionary. It discovers the consuming repo's own optional
# typos.toml/_typos.toml/.typos.toml (or a [tool.typos] section in
# Cargo.toml/pyproject.toml) by walking up from the edited file itself, not
# from the hook's CWD (verified against typos-cli 1.44.0: passing an absolute
# file path from an unrelated working directory still discovers a config
# several directories above it) — so, unlike markdownlint-cli2, this hook
# never needs to `cd` to the repo root for discovery to work.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "TYPOS_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers
# the fix work (pre-fix exits below do not emit telemetry). EPOCHREALTIME is
# Bash 5.0+; on older bash it is unset, so default to empty — referencing it
# bare under `set -u` would abort before the advisory exit 0, failing every
# edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array. Two
# guards: the high-res start stamp (empty on Bash < 5.0, so telemetry is
# skipped rather than aborting the fix) and the sink opt-in. The data payload
# costs a jq subprocess, so it is built here after both guards — never on the
# unwired path.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "typos-format" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq is required to parse Claude Code's hook payload and to emit structured
# PostToolUse context. Absent -> visible once-per-session skip notice on both
# the agent and user channels, exit 0.
hook::require_jq PostToolUse typos-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0

# Resolve repo root early — only needed to compute the schema-required
# repo-relative path in data.file (typos' own config discovery is
# file-anchored, so nothing else here depends on it).
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# Telemetry-payload precursors — TOOL and FILE_REL feed only the envelope's
# data object, so both are built only when a sink is wired: the unwired
# default path spawns zero telemetry-only subprocesses (the tool_name jq
# parse, and 2x cygpath on Windows).
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
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

TYPOS_BIN="$(command -v typos 2>/dev/null)" || TYPOS_BIN=""
if [[ -z "$TYPOS_BIN" ]]; then
  if hook::notice_once "typos-format-typos" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "typos-format: 'typos' was not found on PATH — spell-check skipped for this session. Install: https://github.com/crate-ci/typos#install (this hook never downloads or executes an unpinned tool)."
  fi
  emit_tel "skipped" '[]'
  exit 0
fi

# --force-exclude makes the consumer's own [files] extend-exclude apply even
# to this explicitly-named file — typos otherwise only honors that exclude
# list during its own directory walk, not for a path given directly on the
# command line (verified against typos-cli 1.44.0). -w applies every
# unambiguous fix in place; --format json emits one compact JSON object per
# REMAINING (unfixed) finding and nothing at all for a fully-fixed file —
# verified empirically that fixed typos never appear in this output, only
# residual ambiguous corrections typos declined to apply unassisted.
#
# Exit codes (typos-cli 1.44.0, undocumented beyond the README's --format
# json callout but verified to hold for the default text format too): 0 =
# clean (nothing remains after -w), 2 = findings remain, anything else = the
# tool itself broke (bad invocation, internal error) rather than rendering a
# spelling judgment. No `cd` here — unlike markdownlint-cli2's CWD-anchored
# discovery, typos resolves config from the FILE argument itself, so this
# hook's own CWD is irrelevant to what governs the run.
OUTPUT=$("$TYPOS_BIN" --force-exclude -w --format json "$FILE" 2>&1)
RC=$?

if [[ $RC -eq 0 ]]; then
  emit_tel "ok" '[]'
  exit 0
fi

if [[ $RC -eq 2 && -n "$OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "typos-format: $(basename "$FILE") has residual spelling findings (ambiguous corrections, advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    desc=$(printf '%s' "$line" | jq -r 'select(.type=="typo") | "\(.typo) -> \(.corrections | join(", ")) (line \(.line_num))"' 2>/dev/null)
    [[ -n "$desc" ]] || continue
    hook::ctx_append "  $desc"
    findings_raw+="$desc"$'\n'
  done <<<"$OUTPUT"
  hook::ctx_flush PostToolUse

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  emit_tel "ok" "$FINDINGS_JSON"
  exit 0
fi

# typos broke for non-lint reasons (bad config, internal error) — no judgment
# was made. Surface the diagnostic via additionalContext (NOT stderr — an
# advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (the tool never ran to judgment), the same status as the
# no-binary path.
hook::ctx_reset
hook::ctx_append "typos-format: typos failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  hook::ctx_append "  $line"
done <<<"$OUTPUT"
hook::ctx_flush PostToolUse
emit_tel "skipped" '[]'
exit 0

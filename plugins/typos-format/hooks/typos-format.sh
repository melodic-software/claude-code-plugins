#!/usr/bin/env bash
# PostToolUse hook: auto-fix spelling typos via typos-cli (crate-ci/typos).
# Triggered on Write|Edit of ANY file — typos is language-agnostic, unlike the
# sibling ruff-format/markdown-format hooks, which are extension-scoped.
#
# ADVISORY: always exits 0. `typos --write-changes` applies every correction it
# has confidence in; residual (unfixable, e.g. a blank-correction "disallowed"
# entry) findings surface via additionalContext but never block the edit. A
# commit hook or CI is the hard gate.
#
# Unconditional: typos ships a built-in spelling dictionary and runs with zero
# configuration, so this hook runs on every edit regardless of whether the
# repo has adopted a typos config — matching the sibling markdown-format
# hook's unconditional pattern. When a config IS present (typos.toml,
# _typos.toml, .typos.toml, Cargo.toml with [workspace.metadata.typos] or
# [package.metadata.typos], or pyproject.toml with [tool.typos], per
# crate-ci/typos' own docs at
# https://github.com/crate-ci/typos/blob/master/docs/reference.md), typos'
# own file-anchored discovery finds and honors it (allowlist/exclude) — this
# hook never re-implements that walk itself. The typos binary is resolved
# from PATH only — never downloaded (typos is a standalone Rust binary with no
# per-repo dependency-manager convention, unlike ruff's .venv).
#
# Hook-precision: this convention is fleet-wide by intent (its owner doc says
# "every plugin hook follows" it), even though today's CI-audited enforcement
# is narrower (plugins/guardrails/hooks/** only). This hook opts in
# voluntarily. Rule 1 (diff-scope Edit checks to the changed hunk): N/A for a
# formatter/autofix hook — whole-file scanning is the accepted posture here
# (ruff-format/markdown-format do the same); rule 1's "changed hunk" framing
# targets detector/guard hooks flagging pre-existing lines the edit never
# touched. Rule 3 (bounded stdin): inherited via hook::buffer_stdin. Rules 2/4/5
# (command-structure parsing, canonical-marker gating, repo-path/home-dir
# branching): N/A — this hook has none of those shapes.
#
# KNOWN RISK (not fixed here): Claude Code runs every matching PostToolUse hook
# in parallel for one tool call. This hook has no extension filter, so on a
# repo with both a typos config and (e.g.) a Ruff config, editing a .py file
# fires this hook and ruff-format.sh concurrently — each independently
# reading-then-writing the same file with no locking, so a nondeterministic
# clobber is possible. This race class already exists between eol-normalizer
# (also extension-unscoped) and every formatter hook; no hook-level
# locking/ordering primitive exists in Claude Code today. Tracked separately,
# not addressed in this plugin.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT -> silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "TYPOS_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# fixes typos on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice when there is no
# file_path at all (e.g. a tool_input shape this hook cannot act on regardless).
# shellcheck disable=SC2034  # existence-only check; no extension filter to apply (typos is language-agnostic)
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine).
hook::require_jq PostToolUse typos-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used as the CWD typos runs in and to compute
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
  emit_tel "typos-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
  exit 0
}

root="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || root=""

# Resolve the typos binary from PATH — never downloaded (typos is a standalone
# Rust binary; no per-repo dependency-manager convention exists for it, unlike
# ruff's .venv or markdownlint's node_modules).
TYPOS_BIN="$(command -v typos 2>/dev/null)" || TYPOS_BIN=""

# No binary available → visible once-per-session skip notice, not a silent gap
# (dim-9 doctrine).
if [[ -z "$TYPOS_BIN" ]]; then
  if hook::notice_once "typos-format-typos" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "typos-format: no 'typos' binary was found on PATH — spell-check skipped for this session. Install: https://github.com/crate-ci/typos#install"
  fi
  emit_skipped
fi

# Pass the file as a path relative to the repo root (the CWD typos runs in) so
# concise diagnostics echo a clean repo-relative path instead of an absolute
# one. typos resolves config relative to the TARGET PATH passed on the command
# line, not the process CWD (verified empirically: running from the repo root
# with a relative subdirectory path still discovers and honors that
# subdirectory's own config) — so running from repo root here does not change
# which config governs, regardless of nesting depth. Falls back to the
# absolute path and the file's own directory when the repo root did not
# resolve or the file is outside it.
TYPOS_ARG="$FILE"
RUN_DIR="${root:-$(dirname "$FILE")}"
if [[ -n "$root" && -n "$FILE_REL" && "$FILE_REL" != "$FILE" ]]; then
  TYPOS_ARG="$FILE_REL"
fi

# Apply every correction typos has confidence in, in place. --force-exclude
# honors the config's own exclude/extend-exclude even for this explicitly-passed
# path, so a file the repo excludes (generated or vendored code, intentional-
# misspelling fixtures) is left untouched with no advisory noise — same
# rationale as ruff-format.sh's identical flag. jsonlines output captured for
# the residual-findings pass below. Verified against typos-cli 1.44.0: exit 0 =
# clean or fully fixed; exit 2 = residual (unfixable, e.g. a blank-correction
# "disallowed" entry) findings remain even after write; any other code = typos
# itself failed (bad config, internal error) — not a judgment, no findings.
OUTPUT=$(cd "$RUN_DIR" && "$TYPOS_BIN" --write-changes --force-exclude --format json "$TYPOS_ARG" 2>&1)
RC=$?

if [[ $RC -eq 0 ]]; then
  data_json=$(build_data_json '[]')
  emit_tel "typos-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

if [[ $RC -eq 2 && -n "$OUTPUT" ]]; then
  hook::ctx_reset
  hook::ctx_append "typos-format: $(basename "$FILE") has residual typos findings (advisory):"
  findings_raw="[]"
  parsed=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    obj=$(printf '%s' "$line" | jq -c 'select(.type == "typo")' 2>/dev/null) || continue
    [[ -n "$obj" ]] || continue
    typo=$(printf '%s' "$obj" | jq -r '.typo // empty' 2>/dev/null)
    [[ -n "$typo" ]] || continue
    corrections=$(printf '%s' "$obj" | jq -c '.corrections // null' 2>/dev/null)
    if [[ "$corrections" == "null" ]]; then
      hook::ctx_append "  \"$typo\" is disallowed with no known correction — if intentional, add it to extend-words / extend-identifiers (or an extend-ignore-re pattern) in your typos config."
    else
      first_correction=$(printf '%s' "$obj" | jq -r '.corrections[0] // empty' 2>/dev/null)
      hook::ctx_append "  \"$typo\" should be \"$first_correction\" — if intentional, add it to extend-words / extend-identifiers in your typos config."
    fi
    parsed=$(printf '%s' "$obj" | jq -c --arg typo "$typo" --argjson corrections "$corrections" '{typo:$typo,corrections:$corrections}' 2>/dev/null) || continue
    findings_raw=$(printf '%s' "$findings_raw" | jq -c --argjson f "$parsed" '. + [$f]' 2>/dev/null) || true
  done <<<"$OUTPUT"
  hook::ctx_flush PostToolUse

  data_json=$(build_data_json "$findings_raw")
  # Status "ok" — typos RAN and produced a judgment (findings live in
  # data.findings), mirroring the sibling formatter plugins where status
  # reflects whether the tool ran, not whether it was clean.
  emit_tel "typos-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
  exit 0
fi

# typos broke for non-lint reasons (config parse error, internal error) — no
# judgment was made. Surface the diagnostic via additionalContext (NOT stderr —
# an advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (typos never ran to judgment), the same status as the
# no-binary path.
hook::ctx_reset
hook::ctx_append "typos-format: typos failed for $(basename "$FILE") (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  hook::ctx_append "  $line"
done <<<"$OUTPUT"
hook::ctx_flush PostToolUse
data_json=$(build_data_json '[]')
emit_tel "typos-format" "PostToolUse" "skipped" "$start" "$data_json" "$REPO_ROOT"
exit 0

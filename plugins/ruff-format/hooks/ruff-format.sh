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
# Kill switch FIRST, before any library is sourced: a disabled hook must not
# pay to parse hook-utils.sh to learn it is off. Same predicate as
# hook::is_enabled; scripts/check-killswitch-hoist.sh pins the two together.
[[ "${CLAUDE_PLUGIN_OPTION_RUFF_FORMAT_ENABLED:-true}" == "true" ]] || exit 0
# Hook directory by parameter expansion, never `dirname`. GNU Bash forks a
# subshell for every command substitution even when the body is a builtin
# (Command Substitution, Bash Reference Manual). On Windows Git Bash that
# fork is a process. `${BASH_SOURCE[0]%/*}` equals dirname for every shape
# BASH_SOURCE takes; the fallback covers a bare filename, where the strip is a
# no-op and dirname answers `.`.
HOOK_DIR="${BASH_SOURCE[0]%/*}"
[[ "$HOOK_DIR" == "${BASH_SOURCE[0]}" ]] && HOOK_DIR=.

# shellcheck source=hook-utils.sh
source "$HOOK_DIR/hook-utils.sh"
# shellcheck source=rewrite-guard.sh
source "$HOOK_DIR/rewrite-guard.sh"
# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array.
# Two guards: the high-res start stamp (EPOCHREALTIME is Bash 5.0+; on older
# bash it is empty and telemetry is skipped, so the hook still formats and
# lints rather than aborting) and the sink opt-in. The data payload costs a jq
# subprocess, so it is built here after both guards — never on the unwired path.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "ruff-format" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

hook::buffer_stdin_to INPUT || exit 0

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
# Basename via parameter expansion, not `basename(1)`: this hook fires on
# every Write/Edit of a Python file, and GNU Bash forks a subshell for
# `$(basename "$FILE")` even though the body is a single exec (Command
# Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). Trim on either separator
# so a mixed-form Windows path still yields the final component.
FILE_BASE="${FILE##*/}"
FILE_BASE="${FILE_BASE##*\\}"

# Telemetry-only. Parsed behind the sink opt-in so the unwired default path
# spawns zero telemetry-only subprocesses (FILE_REL below is NOT gated — it is
# also the path Ruff itself is invoked with).
TOOL=""
if hook::telemetry_enabled; then
  TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
fi

# Resolve repo root early — used to bound the config opt-in walk and to compute
# the schema-required repo-relative path in data.file.
FILE_DIR="${FILE%/*}"
[[ "$FILE_DIR" == "$FILE" ]] && FILE_DIR=.
[[ -n "$FILE_DIR" ]] || FILE_DIR=/
REPO_ROOT=""
hook::repo_root_to REPO_ROOT "$FILE_DIR"
# Repo-relative path, serving two consumers: the schema-required data.file, and
# the argument Ruff runs on from the repo root. A path the prefix strip could
# not make relative degrades to its basename, which is right for telemetry but
# names a DIFFERENT file when resolved against the repo root, so the invocation
# below has to know which of the two it holds. `_to` writes FILE_REL and
# HOOK_REPO_RELATIVE_DEGRADED in this shell, so the capture subshell that used
# to hide the global is gone (Command Substitution, Bash Reference Manual;
# https://mywiki.wooledge.org/CommandSubstitution). Status remains the
# distinguishable channel.
FILE_REL_DEGRADED=0
FILE_REL=""
hook::repo_relative_path_to FILE_REL "$FILE" "$REPO_ROOT" || FILE_REL_DEGRADED=1

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
    --arg changed "${HOOK_REWRITE_CHANGED:-}" \
    '{tool:$tool,file:$file,findings:$findings}
     + (if $changed == "" then {} else {changed: ($changed == "true")} end)' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

emit_skipped() {
  emit_tel "skipped" '[]'
  exit 0
}

# Existence check is a builtin; the previous `$(cd && pwd)` forked a subshell
# (and pwd) on every fire to canonicalize a path git already answered as
# absolute, or a fallback hint that `cd "$RUN_DIR"` already accepts relative.
FILE_DIR_POSIX=""
[[ -d "$FILE_DIR" ]] && FILE_DIR_POSIX="$FILE_DIR"
root=""
[[ -d "$REPO_ROOT" ]] && root="$REPO_ROOT"

# Consumer opt-in: a Ruff configuration that governs the edited file. Walk up
# from the file's directory to the repo root, stopping at the FIRST config found
# — Ruff itself resolves the closest config per file (file-anchored, not
# CWD-anchored), so the closest hit is exactly the config that will govern the
# run. Same-directory precedence mirrors Ruff's (.ruff.toml > ruff.toml >
# pyproject.toml). A pyproject.toml counts only when it carries a [tool.ruff]
# section (or a [tool.ruff.*] subtable) — Ruff skips it for discovery otherwise.
# Absence of any config is the opt-out: the file is left untouched.
#
# Known limitation: this line-anchored grep only recognizes the `[tool.ruff]`
# header form. TOML also allows the equivalent config as an inline table under
# a bare `[tool]` header (`[tool]` + `ruff = { ... }`), which Ruff itself does
# honor — a repo using that form is treated as un-configured here and the gate
# skips it. Fails safe (a missed opt-in, never a wrong edit); left undetected
# rather than heuristically matched because a robust check needs real TOML
# parsing (inline tables span lines, nest arbitrarily, and the `ruff` key can
# appear in any order under `[tool]`), and a multi-pass grep risks a false
# positive from an unrelated `ruff = "..."` key in a different table or a
# commented-out line.
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
  parent="${dir%/*}"
  [[ -n "$parent" ]] || parent=/
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
  parent="${dir%/*}"
  [[ -n "$parent" ]] || parent=/
  [[ "$parent" == "$dir" ]] && break
  dir="$parent"
done
if [[ -z "$RUFF_BIN" ]]; then
  # `command -v` is a builtin; capturing it with `$( )` was a leftover subshell
  # just to learn the path. The later exec looks the name up on PATH itself.
  command -v ruff >/dev/null 2>&1 && RUFF_BIN=ruff
fi

# The repo opted in via a Ruff config but no binary is available → visible
# once-per-session skip notice, not a silent gap (dim-9 doctrine).
if [[ -z "$RUFF_BIN" ]]; then
  if hook::notice_once "ruff-format-ruff" "$INPUT"; then
    hook::emit_skip_notice PostToolUse "ruff-format: a Ruff config governs this repo but no 'ruff' binary was found (.venv or this hook's PATH) — format/lint skipped for this edit (probe re-runs on every matching edit; only this notice latches once per session — there is no skip latch). Hook processes inherit Claude Code's own environment, not the interactive shell's profile, so a version-manager install the Bash tool can see may be invisible here; a project .venv install is the reliable route. Install: https://docs.astral.sh/ruff/installation/
PATH probed: ${PATH:-<unset>}"
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
# (RUN_DIR would not anchor FILE_REL), the file is outside it, or FILE_REL
# degraded to a bare basename — that basename is a redaction for telemetry, and
# resolving it against the repo root would lint a different file or none, which
# on this advisory hook means real findings silently disappear.
RUFF_ARG="$FILE"
RUN_DIR="${root:-$FILE_DIR_POSIX}"
if [[ -n "$root" && "$FILE_REL_DEGRADED" -eq 0 && -n "$FILE_REL" && "$FILE_REL" != "$FILE" ]]; then
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
#
# Content-mutation disclosure (#1596): Ruff may auto-fix lint issues and/or
# reformat layout the user did not request. Name the rewrite on the user
# channel; stay silent when the file is unchanged. Snapshot lifecycle and
# single-document composition live in the shared rewrite-guard lib (#3406,
# #3409): the disclosure is TAKEN at each exit arm and composed into that
# arm's one JSON document, never emitted mid-run as a second document.
RUFF_REWRITE_MESSAGE="ruff-format: auto-fixed and/or reformatted $FILE_BASE via Ruff."
hook::rewrite_guard_begin "$FILE"
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
  # Take before the telemetry emit so data.changed carries the byte verdict;
  # the disclosure is still one systemMessage-only document, or nothing.
  hook::rewrite_take_disclosure "$FILE" "$RUFF_REWRITE_MESSAGE"
  emit_tel "ok" '[]'
  [[ -z "$HOOK_REWRITE_MESSAGE" ]] || hook::emit_channels PostToolUse "" "$HOOK_REWRITE_MESSAGE"
  exit 0
fi

if [[ $RC -eq 1 && -n "$OUTPUT" ]]; then
  RUFF_CTX="ruff-format: $FILE_BASE has Ruff findings (advisory):"
  findings_raw=""
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    RUFF_CTX+=$'\n'"  $line"
    findings_raw+="$line"$'\n'
  done <<<"$OUTPUT"
  # Findings AND a rewrite disclosure compose into one document (#3406).
  hook::rewrite_take_disclosure "$FILE" "$RUFF_REWRITE_MESSAGE"
  hook::emit_channels PostToolUse "$RUFF_CTX" "$HOOK_REWRITE_MESSAGE"

  FINDINGS_JSON='[]'
  if [[ -n "$findings_raw" ]]; then
    FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
  fi
  # Status "ok" — the linter RAN and produced a judgment (findings live in
  # data.findings), mirroring the sibling formatter plugins where status
  # reflects whether the tool ran, not whether it was clean.
  emit_tel "ok" "$FINDINGS_JSON"
  exit 0
fi

# Ruff broke for non-lint reasons (config parse error, internal error) — no
# judgment was made. Surface the diagnostic via additionalContext (NOT stderr —
# an advisory hook's exit-0 stderr can trip a false "Hook Error" label). Record
# as "skipped" (the linter never ran to judgment), the same status as the
# no-config / no-binary paths.
RUFF_CTX="ruff-format: ruff failed for $FILE_BASE (no diagnostics; tool break, not a finding):"
while IFS= read -r line; do
  [[ -n "$line" ]] || continue
  RUFF_CTX+=$'\n'"  $line"
done <<<"$OUTPUT"
# The fix/format passes may already have rewritten the file before the verify
# pass broke; take the disclosure and compose it with the tool-break context
# as one document (#3406). Taken before the telemetry emit so data.changed
# records that rewrite too.
hook::rewrite_take_disclosure "$FILE" "$RUFF_REWRITE_MESSAGE"
emit_tel "skipped" '[]'
hook::emit_channels PostToolUse "$RUFF_CTX" "$HOOK_REWRITE_MESSAGE"
exit 0

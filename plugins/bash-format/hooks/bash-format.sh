#!/usr/bin/env bash
# PostToolUse hook: auto-format and lint shell scripts via shfmt + ShellCheck.
# Triggered on Write|Edit of *.sh and *.bash files.
#
# ADVISORY: always exits 0. ShellCheck findings (warning severity and above)
# surface via additionalContext but never block the edit. Uses the consuming
# repo's own .shellcheckrc and .editorconfig — ships none.
#
# shfmt is gated on the consumer opting in: it runs only when an .editorconfig
# governs the edited file (walking up to the repo root). Without that opt-in the
# file is left unformatted rather than rewritten to shfmt's built-in defaults.
# ShellCheck (non-mutating) always runs when available.

set -uo pipefail

# Read inherited fd0 directly (bare cat) — NEVER `</dev/stdin`: on Windows Git
# Bash, CC spawns hooks with stdin = a Win32 pipe that `/dev/stdin` cannot
# resolve (ENOENT → silent no-op). stdin is read ONCE here and fed to both
# hook::read_file_path (file_path) and the tool_name parse below; reading fd0
# twice would drain the pipe on the second call.
# shellcheck source=hook-utils.sh
source "$(dirname "${BASH_SOURCE[0]}")/hook-utils.sh"

hook::check_enabled "BASH_FORMAT"

# Capture $EPOCHREALTIME immediately after kill-switch so duration_ms covers the
# work below (pre-work exits do not emit telemetry). EPOCHREALTIME is Bash 5.0+;
# on older bash it is unset, so default to empty — referencing it bare under
# `set -u` would abort before the advisory exit 0, failing every edit.
start=${EPOCHREALTIME:-}

# Emit this run's telemetry envelope: $1 status, $2 findings JSON array.
# Two guards: the high-res start stamp (EPOCHREALTIME is Bash 5.0+; on older
# bash it is empty and telemetry is skipped, so the hook still lints and
# formats rather than aborting) and the sink opt-in. The data payload costs a
# jq subprocess, so it is built here after both guards — never on the unwired
# path.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  hook::emit_telemetry "bash-format" "PostToolUse" "$1" "$start" "$(build_data_json "$2")" "$REPO_ROOT"
}

INPUT=$(hook::buffer_stdin) || exit 0

# jq-free applicability pre-filter: never emit the jq notice for an edit this
# hook would not process anyway (the Write|Edit matcher is broader than the
# shell-file filter).
RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
case "$RAW_FILE" in
*.sh | *.bash) ;;
*) exit 0 ;;
esac

# jq is load-bearing for input parsing; absent → visible once-per-session skip
# notice instead of a silent no-op (dim-9 doctrine).
hook::require_jq PostToolUse bash-format "$INPUT"

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.sh | *.bash) ;;
*) exit 0 ;;
esac

# Resolve repo root early — used to bound the .editorconfig opt-in walk and to
# compute the schema-required repo-relative path in data.file.
REPO_ROOT="$(hook::repo_root "$(dirname "$FILE")")"

# TOOL and FILE_REL feed the telemetry data object and nothing else, so both are
# resolved only when a sink is wired: the unwired default path spawns zero
# telemetry-only subprocesses (the tool_name jq parse, and 2× cygpath on
# Windows).
#
# FILE_REL is the repo-relative path: schema requires "relative to the consuming
# repo root". On Windows Git Bash, git rev-parse --show-toplevel returns a
# drive-letter path while FILE may be in POSIX mount form. Normalize both
# through cygpath -lm (long name, forward-slash mixed form) when available so
# the prefix strip compares the same representation. On Linux/macOS, cygpath is
# absent and both paths are already POSIX. Falls back to raw FILE on any
# normalization error.
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

# A section header governs shell files when it names a shell extension —
# `[*.sh]` / `[*.bash]` (incl. path prefixes like `[**/*.sh]`) or a brace list
# naming sh or bash (`[*.{sh,bash}]`). A bare `[*]` catch-all is intentionally
# NOT treated as shell opt-in (#1817): most repos set only line-ending / charset
# properties under `[*]`, and treating that as an shfmt opt-in rewrote shell
# files to shfmt's built-in defaults. Path-only sections such as `[scripts/**]`
# are also excluded — matching those correctly means reimplementing EditorConfig
# globbing, and the safe bias is to leave files untouched when unsure. $1 is the
# text inside the brackets.
section_applies_to_shell() {
  local h="$1"
  [[ "$h" =~ \*\.(sh|bash)([^[:alnum:]]|$) ]] && return 0
  [[ "$h" =~ [{,](sh|bash)[,}] ]] && return 0
  return 1
}

# Consumer opt-in for shfmt: an EditorConfig SECTION that names shell files
# (not merely the presence of any .editorconfig — a repo whose .editorconfig
# only configures other languages, or only a bare `[*]` for line endings, must
# not have its shell files rewritten to shfmt's built-in defaults). Walks up
# from the file to the repo root, stopping at a `root = true` config per
# EditorConfig search semantics. This gate is the whole formatting opt-in.
shell_editorconfig_opt_in() {
  local dir root cfg line is_root parent
  dir="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd)" || return 1
  root="$(cd "$REPO_ROOT" 2>/dev/null && pwd)" || root=""
  while :; do
    cfg="$dir/.editorconfig"
    if [[ -f "$cfg" ]]; then
      is_root=0
      while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*\[(.+)\][[:space:]]*$ ]]; then
          section_applies_to_shell "${BASH_REMATCH[1]}" && return 0
        elif [[ "$line" =~ ^[[:space:]]*[Rr][Oo][Oo][Tt][[:space:]]*=[[:space:]]*[Tt][Rr][Uu][Ee][[:space:]]*$ ]]; then
          is_root=1
        fi
      done <"$cfg"
      [[ $is_root -eq 1 ]] && return 1 # root config, no shell section → stop
    fi
    [[ -n "$root" && "$dir" == "$root" ]] && return 1
    parent="$(dirname "$dir")"
    [[ "$parent" == "$dir" ]] && return 1 # reached filesystem root
    dir="$parent"
  done
}

ran_any=0

# Missing-tool notice accumulator: a run can lack shfmt AND shellcheck, and can
# carry ShellCheck findings alongside a pending shfmt notice — everything must
# compose into the single JSON document emitted at the end (hook::emit_channels).
NOTICE=""
append_notice() {
  [[ -n "$NOTICE" ]] && NOTICE+=" "
  NOTICE+="$1"
}

# Tool path for shfmt/ShellCheck. On Windows/MSYS, Claude Code may hand the
# hook a POSIX mount path (`/c/...`), a mixed drive path (`C:/...`), or a
# backslash Win32 path. GHC-based ShellCheck opens paths via openBinaryFile and
# can fail that open on some spellings even when bash's `[[ -f ]]` succeeded on
# the original (#1817). Prefer cygpath's mixed long form when available so both
# tools see one stable existing path; fall back to FILE unchanged elsewhere.
TOOL_FILE="$FILE"
if command -v cygpath >/dev/null 2>&1; then
  _tool_lm=$(cygpath -lm -- "$FILE" 2>/dev/null)
  if [[ -n "$_tool_lm" && -f "$_tool_lm" ]]; then
    TOOL_FILE="$_tool_lm"
  fi
fi

# Format pass (opt-in, mutating). No parser/printer flags — that keeps
# .editorconfig formatting in effect. --apply-ignore is a utility flag (not a
# parser/printer flag, so it does not disable editorconfig formatting): it makes
# shfmt honor `ignore = true` editorconfig rules for this single direct file,
# which it otherwise skips for direct-file invocations — so a repo's opt-out for
# generated/vendored scripts is respected, not overwritten.
# The consumer opted in via .editorconfig but shfmt is absent → visible
# once-per-session skip notice, not a silent gap (dim-9 doctrine). No opt-in →
# quiet (N/A, the repo chose not to format).
if shell_editorconfig_opt_in; then
  if command -v shfmt >/dev/null 2>&1; then
    # --apply-ignore requires shfmt 3.8+ (2024-02). Older versions reject the
    # flag, and they cannot honor direct-file ignore rules anyway — that is
    # exactly the capability the flag adds — so they get a plain in-place format.
    #
    # The version is decided by PROBING the flag, not by inferring it from a
    # failed format run. `--apply-ignore -w || -w` re-formatted WITHOUT the flag
    # whenever the first call failed for ANY reason, so a transient failure on a
    # 3.8+ shfmt silently discarded the repo's `ignore = true` opt-out and
    # re-tabbed a file the consumer had asked shfmt to leave alone (#1817). A
    # capability probe cannot confuse "this shfmt has no such flag" with "this
    # run failed": where the flag exists, a failing run now leaves the file
    # untouched, which is the only safe reading of a formatter that did not
    # complete.
    #
    # The probe's own failure is classified the same way: only a confirmed
    # unsupported-flag rejection (the Go flag parser's "flag provided but not
    # defined", or a wrapper's "unknown flag", naming apply-ignore) takes the
    # plain-format compatibility path. Any other probe failure — a wrapper
    # flaking on its first invocation, a transient exec error — says nothing
    # about the flag, so falling back would mutate through the same discarded
    # opt-out; the file is left untouched and the skip is said out loud.
    #
    # Re-check existence immediately before mutating: the earlier
    # hook::read_file_path guard can race a deleted scratch/worktree file, and
    # shfmt/ShellCheck then surface GHC's openBinaryFile error (#1817).
    if [[ -f "$TOOL_FILE" || -f "$FILE" ]]; then
      probe_err=""
      _fmt_target="$TOOL_FILE"
      [[ -f "$_fmt_target" ]] || _fmt_target="$FILE"
      # Content-mutation disclosure (#1596): shfmt rewrites structural layout
      # only; name the rewrite on the user channel and stay silent on no-op paths.
      _fmt_before=""
      if _fmt_before=$(mktemp 2>/dev/null); then
        cp "$_fmt_target" "$_fmt_before" 2>/dev/null || _fmt_before=""
      fi
      if probe_err=$(shfmt --apply-ignore --version 2>&1 >/dev/null); then
        shfmt --apply-ignore -w "$_fmt_target" 2>/dev/null
      elif [[ "$probe_err" == *apply-ignore* ]] &&
        [[ "$probe_err" == *"flag provided but not defined"* || "$probe_err" == *"unknown flag"* ]]; then
        shfmt -w "$_fmt_target" 2>/dev/null
      else
        append_notice "bash-format: shfmt capability probe failed unexpectedly (${probe_err%%$'\n'*}) — formatting skipped for this file, opt-outs preserved."
      fi
      if [[ -n "$_fmt_before" ]]; then
        if ! cmp -s "$_fmt_before" "$_fmt_target" 2>/dev/null; then
          hook::emit_system_message "bash-format: reformatted $(basename "$FILE") via shfmt (structural layout only)."
        fi
        rm -f "$_fmt_before"
      fi
      ran_any=1
    fi
  elif hook::notice_once "bash-format-shfmt" "$INPUT"; then
    append_notice "bash-format: .editorconfig opts this repo into shell formatting but 'shfmt' is not on PATH — formatting skipped for this session. Install: https://github.com/mvdan/sh#shfmt"
  fi
fi

# Lint pass (always-on, non-mutating). -x follows `source`/`.` directives;
# -f gcc gives one finding per line; -S warning drops info/style noise. Config
# (.shellcheckrc) is auto-discovered from the file's directory upward.
# ShellCheck absent → visible once-per-session skip notice (dim-9 doctrine).
CTX=""
FINDINGS_JSON='[]'
if command -v shellcheck >/dev/null 2>&1; then
  # Same race window as the format pass: skip quietly if the file is already
  # gone rather than reporting GHC's openBinaryFile as a ShellCheck finding.
  if [[ -f "$TOOL_FILE" || -f "$FILE" ]]; then
    ran_any=1
    _lint_target="$TOOL_FILE"
    [[ -f "$_lint_target" ]] || _lint_target="$FILE"
    SC_OUTPUT=$(shellcheck -x -f gcc -S warning "$_lint_target" 2>&1) || true
    # If ShellCheck still failed to open the path, retry the original spelling
    # once — some hosts accept only one of the two forms — then drop any
    # remaining openBinaryFile noise so a path/race miss is never a finding.
    if [[ "$SC_OUTPUT" == *openBinaryFile* && "$_lint_target" != "$FILE" && -f "$FILE" ]]; then
      SC_OUTPUT=$(shellcheck -x -f gcc -S warning "$FILE" 2>&1) || true
    fi
    if [[ "$SC_OUTPUT" == *openBinaryFile* ]]; then
      SC_OUTPUT=$(printf '%s\n' "$SC_OUTPUT" | grep -v 'openBinaryFile' || true)
    fi
    if [[ -n "$SC_OUTPUT" ]]; then
      CTX="bash-format: $(basename "$FILE") has ShellCheck findings:"$'\n'
      findings_raw=""
      while IFS= read -r line; do
        [[ -n "$line" ]] || continue
        CTX+="  $line"$'\n'
        findings_raw+="$line"$'\n'
      done <<<"$SC_OUTPUT"
      if [[ -n "$findings_raw" ]]; then
        FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
      fi
    fi
  fi
elif hook::notice_once "bash-format-shellcheck" "$INPUT"; then
  append_notice "bash-format: 'shellcheck' not found on PATH — shell lint skipped for this session. Install: https://github.com/koalaman/shellcheck#installing"
fi

# Single emission point: findings on the agent channel, missing-tool notice on
# both channels, composed into one JSON document.
CTX="${CTX%$'\n'}"
if [[ -n "$NOTICE" ]]; then
  AGENT_CTX="$CTX"
  [[ -n "$AGENT_CTX" ]] && AGENT_CTX+=$'\n'
  AGENT_CTX+="$NOTICE"
  hook::emit_channels PostToolUse "$AGENT_CTX" "$NOTICE"
else
  hook::emit_channels PostToolUse "$CTX" ""
fi

status="ok"
[[ $ran_any -eq 0 ]] && status="skipped"
emit_tel "$status" "$FINDINGS_JSON"
exit 0

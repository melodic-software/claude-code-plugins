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

# Telemetry needs the high-res start stamp. When EPOCHREALTIME is unavailable
# (Bash < 5.0) the stamp is empty and telemetry is skipped, so the hook still
# lints and formats on older bash rather than aborting.
emit_tel() {
  [[ -n "$start" ]] || return 0
  hook::emit_telemetry "$@"
}

INPUT=$(cat)

FILE=$(printf '%s' "$INPUT" | hook::read_file_path) || exit 0
case "$FILE" in
*.sh | *.bash) ;;
*) exit 0 ;;
esac

TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)

# Resolve repo root early — used to bound the .editorconfig opt-in walk and to
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
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

# A section header governs shell files when it is the `[*]` catch-all or names a
# shell extension — `[*.sh]` / `[*.bash]` (incl. path prefixes like `[**/*.sh]`)
# or a brace list naming sh or bash (`[*.{sh,bash}]`). Path-only sections such as
# `[scripts/**]` are intentionally NOT treated as shell opt-in: matching those
# correctly means reimplementing EditorConfig globbing, and the safe bias is to
# leave files untouched when unsure. $1 is the text inside the brackets.
section_applies_to_shell() {
  local h="$1"
  [[ "$h" == '*' ]] && return 0
  [[ "$h" =~ \*\.(sh|bash)([^[:alnum:]]|$) ]] && return 0
  [[ "$h" =~ [{,](sh|bash)[,}] ]] && return 0
  return 1
}

# Consumer opt-in for shfmt: an EditorConfig SECTION that governs the edited
# shell file (not merely the presence of any .editorconfig — a repo whose
# .editorconfig only configures other languages must not have its shell files
# rewritten to shfmt's built-in defaults). Walks up from the file to the repo
# root, stopping at a `root = true` config per EditorConfig search semantics.
# This gate is the whole formatting opt-in.
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

# Format pass (opt-in, mutating). No parser/printer flags — that keeps
# .editorconfig formatting in effect. --apply-ignore is a utility flag (not a
# parser/printer flag, so it does not disable editorconfig formatting): it makes
# shfmt honor `ignore = true` editorconfig rules for this single direct file,
# which it otherwise skips for direct-file invocations — so a repo's opt-out for
# generated/vendored scripts is respected, not overwritten.
if command -v shfmt >/dev/null 2>&1 && shell_editorconfig_opt_in; then
  # --apply-ignore requires shfmt 3.8+ (2024-02). On older shfmt the flag is
  # unknown and the call fails without formatting, so fall back to a plain
  # in-place format — those versions cannot honor direct-file ignore rules
  # anyway (that is exactly the capability --apply-ignore adds). On shfmt 3.8+
  # the first call succeeds (skipping ignored files), so the fallback never runs.
  shfmt --apply-ignore -w "$FILE" 2>/dev/null || shfmt -w "$FILE" 2>/dev/null
  ran_any=1
fi

# Lint pass (always-on, non-mutating). -x follows `source`/`.` directives;
# -f gcc gives one finding per line; -S warning drops info/style noise. Config
# (.shellcheckrc) is auto-discovered from the file's directory upward.
if command -v shellcheck >/dev/null 2>&1; then
  ran_any=1
  SC_OUTPUT=$(shellcheck -x -f gcc -S warning "$FILE" 2>&1) || true
  if [[ -n "$SC_OUTPUT" ]]; then
    hook::ctx_reset
    hook::ctx_append "bash-format: $(basename "$FILE") has ShellCheck findings:"
    findings_raw=""
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      hook::ctx_append "  $line"
      findings_raw+="$line"$'\n'
    done <<<"$SC_OUTPUT"
    hook::ctx_flush PostToolUse

    FINDINGS_JSON='[]'
    if [[ -n "$findings_raw" ]]; then
      FINDINGS_JSON=$(printf '%s' "$findings_raw" | jq -R . | jq -s . 2>/dev/null) || FINDINGS_JSON='[]'
    fi
    data_json=$(build_data_json "$FINDINGS_JSON")
    emit_tel "bash-format" "PostToolUse" "ok" "$start" "$data_json" "$REPO_ROOT"
    exit 0
  fi
fi

# No findings. "skipped" when neither tool did anything (both absent / no opt-in);
# "ok" when at least one pass ran cleanly.
status="ok"
[[ $ran_any -eq 0 ]] && status="skipped"
data_json=$(build_data_json '[]')
emit_tel "bash-format" "PostToolUse" "$status" "$start" "$data_json" "$REPO_ROOT"
exit 0

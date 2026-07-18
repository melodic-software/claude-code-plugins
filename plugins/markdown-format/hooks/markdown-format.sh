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

# jq is required to parse Claude Code's hook payload and to emit structured
# PostToolUse context. Absent → visible once-per-session skip notice on both
# the agent and user channels (dim-9 doctrine), exit 0.
hook::require_jq PostToolUse markdown-format "$INPUT"

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
    --arg tool "$TOOL" \
    --arg file "$FILE_REL" \
    --argjson findings "$1" \
    '{tool:$tool,file:$file,findings:$findings}' 2>/dev/null ||
    printf '{"tool":"","file":"","findings":[]}'
}

# Resolve the consuming repository's pinned npm binary without invoking a
# package runner. npm creates an extensionless POSIX shim in node_modules/.bin
# alongside its Windows .cmd launcher; Git Bash executes the POSIX shim. Follow
# symlinks before accepting it and require the physical target to remain inside
# this repository's node_modules tree. This rejects a checked-in or replaced
# .bin symlink that escapes the repository trust boundary.
resolve_repo_markdownlint() {
  local candidate="$REPO_ROOT/node_modules/.bin/markdownlint-cli2"
  local root_physical target link target_dir depth=0

  [[ -f "$candidate" && -x "$candidate" ]] || return 1
  root_physical="$(cd -P -- "$REPO_ROOT" 2>/dev/null && pwd -P)" || return 1
  target="$candidate"

  while [[ -L "$target" ]]; do
    depth=$((depth + 1))
    ((depth <= 32)) || return 1
    link="$(readlink "$target" 2>/dev/null)" || return 1
    case "$link" in
    /*) target="$link" ;;
    [A-Za-z]:[\\/]*)
      command -v cygpath >/dev/null 2>&1 || return 1
      target="$(cygpath -u "$link" 2>/dev/null)" || return 1
      ;;
    *) target="$(dirname -- "$target")/$link" ;;
    esac
  done

  [[ -f "$target" && -x "$target" ]] || return 1
  target_dir="$(cd -P -- "$(dirname -- "$target")" 2>/dev/null && pwd -P)" || return 1
  target="$target_dir/$(basename -- "$target")"
  case "$target" in
  "$root_physical"/node_modules/*) ;;
  *) return 1 ;;
  esac

  printf '%s' "$candidate"
}

MDLINT=()
if command -v markdownlint-cli2 >/dev/null 2>&1; then
  MDLINT=(markdownlint-cli2)
elif REPO_MDLINT="$(resolve_repo_markdownlint)"; then
  MDLINT=("$REPO_MDLINT")
else
  # Never invoke a package runner here: hooks must not download or execute an
  # unpinned package as a side effect of editing a file. Degrade visibly on
  # both channels, once per session (dim-9 doctrine).
  if hook::notice_once "markdown-format-markdownlint" "$INPUT"; then
    hook::emit_skip_notice PostToolUse \
      "markdown-format: markdownlint-cli2 is neither on PATH nor available as a contained repository-local node_modules/.bin executable — Markdown lint skipped for this session. Install it explicitly; this hook does not invoke npx or download tools."
  fi
  emit_tel "skipped" '[]'
  exit 0
fi

# markdownlint-cli2 configuration can cross a code-execution boundary. Its
# official configuration contract loads .cjs/.mjs modules directly and passes
# customRules, markdownItPlugins, and outputFormatters module identifiers to
# Node's require/import machinery. Discover only the configuration files that
# apply to this file (repo root through its parent directory), honoring the
# documented same-directory precedence so a shadowed executable config does not
# create a false warning.
RISK_CONFIGS=()
CONFIG_ROOT="$(cd "$REPO_ROOT" 2>/dev/null && pwd -P)" || CONFIG_ROOT="$REPO_ROOT"
CONFIG_TARGET_DIR="$(cd "$(dirname "$FILE")" 2>/dev/null && pwd -P)" ||
  CONFIG_TARGET_DIR="$(dirname "$FILE")"
collect_risky_configs() {
  local cursor dir candidate config
  local dirs=()

  cursor="$CONFIG_TARGET_DIR"
  while :; do
    dirs=("$cursor" "${dirs[@]}")
    [[ "$cursor" == "$CONFIG_ROOT" ]] && break
    dir="$(dirname "$cursor")"
    [[ "$dir" != "$cursor" ]] || return 0
    cursor="$dir"
  done

  for dir in "${dirs[@]}"; do
    config=""
    for candidate in \
      .markdownlint-cli2.jsonc \
      .markdownlint-cli2.yaml \
      .markdownlint-cli2.cjs \
      .markdownlint-cli2.mjs; do
      if [[ -f "$dir/$candidate" ]]; then
        config="$dir/$candidate"
        break
      fi
    done
    if [[ -n "$config" ]]; then
      case "$config" in
      *.cjs | *.mjs) RISK_CONFIGS+=("$config") ;;
      *)
        if grep -Eq "[\"']?(customRules|markdownItPlugins|outputFormatters)[\"']?[[:space:]]*:" "$config" 2>/dev/null; then
          RISK_CONFIGS+=("$config")
        fi
        ;;
      esac
    fi

    config=""
    for candidate in \
      .markdownlint.jsonc \
      .markdownlint.json \
      .markdownlint.yaml \
      .markdownlint.yml \
      .markdownlint.cjs \
      .markdownlint.mjs; do
      if [[ -f "$dir/$candidate" ]]; then
        config="$dir/$candidate"
        break
      fi
    done
    case "$config" in
    *.cjs | *.mjs) RISK_CONFIGS+=("$config") ;;
    *) ;;
    esac
  done
}

# Return success only for the first observation of this repo + risky-config
# content state. CLAUDE_PLUGIN_DATA is the official persistent plugin-state
# location and survives plugin updates. If it is unavailable or unwritable
# (for example, a direct development invocation), fail open by warning again;
# never suppress a trust warning merely because its marker could not be saved.
claim_trust_advisory() {
  local state_base="${CLAUDE_PLUGIN_DATA:-}" state_dir signature config digest
  [[ -n "$state_base" ]] || return 0
  if command -v cygpath >/dev/null 2>&1 && [[ "$state_base" == [A-Za-z]:\\* ]]; then
    state_base="$(cygpath -u "$state_base" 2>/dev/null)" || return 0
  fi
  state_dir="${state_base%/}/trust-advisories"
  signature=$(
    {
      printf '%s\n' "$REPO_ROOT"
      for config in "${RISK_CONFIGS[@]}"; do
        digest=$(git hash-object "$config" 2>/dev/null) || return 1
        printf '%s\t%s\n' "$config" "$digest"
      done
    } | git hash-object --stdin 2>/dev/null
  ) || return 0
  [[ -n "$signature" ]] || return 0
  mkdir -p "$state_dir" 2>/dev/null || return 0
  mkdir "$state_dir/$signature" 2>/dev/null
}

hook::ctx_reset
collect_risky_configs
if ((${#RISK_CONFIGS[@]} > 0)) && claim_trust_advisory; then
  RISK_LIST=""
  for config in "${RISK_CONFIGS[@]}"; do
    config="${config#"$CONFIG_ROOT"/}"
    RISK_LIST+="${RISK_LIST:+, }$config"
  done
  hook::ctx_append \
    "markdown-format trust advisory: markdownlint-cli2 will load executable or module-loading repository configuration ($RISK_LIST). Formatting continues, but review these files and their installed dependencies before trusting this repository. This warning appears once per configuration state."
fi

if FIX_OUTPUT=$(cd "$REPO_ROOT" && "${MDLINT[@]}" --fix "$FILE" 2>&1); then
  # Clean after fix — emit ok with empty findings.
  hook::ctx_flush PostToolUse
  emit_tel "ok" '[]'
  exit 0
fi

# Residual findings — append to any trust advisory, surface one JSON object via
# additionalContext, then emit ok with findings.
# ctx_append receives all output lines (human-readable context for Claude Code).
# FINDINGS_JSON is filtered to violation lines only — schema requires
# "Unfixable markdownlint violations remaining after --fix, one per line";
# banner/diagnostic lines (version, Finding:, Linting:, Summary:) are excluded.
# Violation lines are identified by the " MD<digits>/" rule-code pattern.
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

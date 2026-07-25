# shellcheck shell=bash
# Shared hook utility library for this marketplace's hook plugins. Sourced
# (not executed): kill switch, file_path parsing + path normalization,
# repo-root resolution, additionalContext accumulator, telemetry envelope.
#
# SINGLE SOURCE OF TRUTH: lib/hook-utils.sh at the marketplace repo root. The
# copies at plugins/*/hooks/hook-utils.sh exist because installed plugins are
# cache-isolated and must be self-contained — never edit a copy. Edit the
# source and run scripts/sync-hook-utils.sh; CI rejects drifted copies.

# Guard against double-sourcing.
[[ -n "${_HOOK_UTILS_LOADED:-}" ]] && return 0
readonly _HOOK_UTILS_LOADED=1

# Per-hook kill switch via the plugin's <name>_enabled userConfig boolean,
# read from the hook-process CLAUDE_PLUGIN_OPTION_<NAME>_ENABLED mirror.
# Exits 0 (allow) if disabled. Place after source, before stdin parsing.
#   hook::check_enabled "MARKDOWN_FORMAT"  # checks CLAUDE_PLUGIN_OPTION_MARKDOWN_FORMAT_ENABLED
hook::check_enabled() {
  local var_name="CLAUDE_PLUGIN_OPTION_${1}_ENABLED"
  if [[ "${!var_name:-true}" != "true" ]]; then
    exit 0
  fi
}

# --- Prerequisite visibility --------------------------------------------------
# Doctrine: a missing runtime prerequisite must surface to BOTH the agent
# (additionalContext) and the user (systemMessage) — a silently skipped feature
# is a defect. Everything in this section is jq-FREE by design: the most common
# missing prerequisite is jq itself.

# JSON-escape a string for embedding in a hand-built JSON document. Escapes
# backslash, double quote, and the line-structure control bytes by name
# (\n \r \t); the remaining C0 bytes JSON forbids raw are dropped — notice text
# never carries meaningful control bytes beyond line structure. Byte-safe under
# UTF-8: every escaped byte is ASCII, and UTF-8 continuation bytes are >= 0x80.
hook::json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  # tr drops the residual C0 bytes; if tr itself is unavailable, fall back to
  # the escaped string as-is — notice text is hook-authored and does not carry
  # raw control bytes in practice.
  local out
  out=$(printf '%s' "$s" | tr -d '\000-\010\013\014\016-\037' 2>/dev/null) || out="$s"
  printf '%s' "$out"
}

# Emit hook JSON carrying an agent-channel context (additionalContext) and/or a
# user-channel message (systemMessage) as ONE document — CC parses the hook's
# whole stdout as a single JSON doc, so a run that has both lint findings and a
# pending skip notice must compose them here rather than print twice. Either
# channel may be empty; emits nothing when both are.
#   hook::emit_channels PostToolUse "$ctx" "$sysmsg"
hook::emit_channels() {
  local event="$1" ctx="$2" sysmsg="$3"
  [[ -n "$ctx" || -n "$sysmsg" ]] || return 0
  local out="{"
  if [[ -n "$ctx" ]]; then
    out+='"hookSpecificOutput":{"hookEventName":"'"$(hook::json_escape "$event")"'","additionalContext":"'"$(hook::json_escape "$ctx")"'"}'
    [[ -n "$sysmsg" ]] && out+=","
  fi
  [[ -n "$sysmsg" ]] && out+='"systemMessage":"'"$(hook::json_escape "$sysmsg")"'"'
  out+="}"
  printf '%s\n' "$out"
}

# Visible skip notice: the same message on both channels. The caller must exit 0
# right after unless it composes via hook::emit_channels itself.
#   hook::emit_skip_notice PostToolUse "my-plugin: tool X not found — ..."
hook::emit_skip_notice() {
  hook::emit_channels "$1" "$2" "$2"
}

# systemMessage-only variant for hook events with no additionalContext channel
# (e.g. Notification).
hook::emit_system_message() {
  hook::emit_channels "" "" "$1"
}

# Once-per-session gate for skip notices. Returns 0 (emit now) the first time a
# given <key> fires in the current session, 1 afterwards — a missing-tool notice
# behind a broad matcher (every Write|Edit) must not repeat on every edit. The
# session id is regex-extracted from the raw hook input JSON (jq-free, see
# section header); marker files live under ${CLAUDE_PLUGIN_DATA} (survives
# plugin updates; mkdir -p defensively since creation is documented only on
# first *reference*) and markers older than 7 days are pruned so per-session
# files cannot accumulate unboundedly. Fails open toward visibility: when no
# marker can be tracked, emit every time.
#   hook::notice_once "my-plugin-jq" "$INPUT" && hook::emit_skip_notice ...
hook::notice_once() {
  local key="$1" input="${2:-}" session="no-session"
  if [[ "$input" =~ \"session_id\"[[:space:]]*:[[:space:]]*\"([^\"]+)\" ]]; then
    session="${BASH_REMATCH[1]}"
    session="${session//[^A-Za-z0-9_-]/-}"
  fi
  local dir="${CLAUDE_PLUGIN_DATA:-}"
  [[ -n "$dir" ]] || return 0
  dir="$dir/skip-notices"
  mkdir -p "$dir" 2>/dev/null || return 0
  find "$dir" -type f -mtime +7 -delete 2>/dev/null
  local marker="$dir/${key}.${session}"
  [[ -f "$marker" ]] && return 1
  : >"$marker" 2>/dev/null
  return 0
}

# Best-effort jq-free extraction of tool_input.file_path from the raw hook
# input, for the applicability pre-filter an extension-scoped hook runs BEFORE
# its jq gate — a missing-jq notice must never fire for an edit the hook would
# not process anyway (e.g. a README edit reaching a workflow-lint hook whose
# Write|Edit matcher is broader than its file filter). The value is returned
# JSON-escaped (backslashes doubled); that is fine for extension/segment
# matching, which is all the pre-filter does. Returns 1 when no file_path is
# present.
#   RAW_FILE=$(hook::raw_file_path "$INPUT") || exit 0
hook::raw_file_path() {
  [[ "$1" =~ \"file_path\"[[:space:]]*:[[:space:]]*\"(([^\"\\]|\\.)*)\" ]] || return 1
  [[ -n "${BASH_REMATCH[1]}" ]] || return 1
  printf '%s' "${BASH_REMATCH[1]}"
}

# jq gate for hooks whose input parsing cannot proceed without it. When jq is
# absent: one visible skip notice per session, then exit 0 — an advisory hook
# never blocks the tool over a missing prerequisite. Place after
# hook::check_enabled (and after any jq-free applicability pre-filter), passing
# the buffered stdin for session scoping.
#   hook::require_jq PostToolUse my-plugin "$INPUT"
hook::require_jq() {
  command -v jq >/dev/null 2>&1 && return 0
  local event="$1" plugin="$2" input="${3:-}"
  if hook::notice_once "${plugin}-jq" "$input"; then
    hook::emit_skip_notice "$event" \
      "$plugin: jq not found on PATH — hook skipped for this session. Install jq (https://jqlang.org/download/) to enable it."
  fi
  exit 0
}

# Normalize a path for the membership comparison below: backslashes → forward
# slashes, and — only on Windows/MSYS, whose filesystem is case-insensitive —
# fold a leading drive (POSIX `/c/...` or `c:/...`) to an upper-case drive
# letter + lower-cased remainder so the byte-exact comparison is effectively
# case-insensitive. The fold is gated on the host (OSTYPE), NOT on the path
# shape: on a case-sensitive POSIX filesystem a real single-letter top-level
# directory such as `/c/Repo` must pass through unchanged, otherwise it would
# collapse with `/c/repo` and the membership guard would admit a sibling
# outside CLAUDE_PROJECT_DIR. The result is used ONLY for comparison; the
# emitted path is always the caller's original.
hook::normalize_path() {
  local p="${1//\\//}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    if [[ "$p" =~ ^/([a-zA-Z])/ || "$p" =~ ^([a-zA-Z]):/ ]]; then
      local rest="${p:2}"
      printf '%s' "${BASH_REMATCH[1]^}:${rest,,}"
      return
    fi
    ;;
  *) ;; # POSIX hosts: case-sensitive FS, no drive fold — pass through below
  esac
  printf '%s' "$p"
}

# Canonicalize to a physical path — symlinks resolved — for the membership
# comparison below, so an in-project symlink pointing outside the project root
# cannot defeat the guard (the lexical path would pass the prefix check while
# the write lands elsewhere). GNU realpath ships with Git Bash and Linux
# coreutils; readlink -f covers the BSD/macOS hosts that have no realpath.
# When neither resolver exists the caller falls back to comparing the lexical
# path as before — the guard is defense-in-depth scoping for a file the agent
# already wrote via its own tools, so degrading to the historical comparison
# beats silently disabling the hook on those hosts.
hook::physical_path() {
  local resolved
  if resolved=$(realpath -- "$1" 2>/dev/null) || resolved=$(readlink -f -- "$1" 2>/dev/null); then
    if [[ -n "$resolved" ]]; then
      printf '%s' "$resolved"
      return
    fi
  fi
  printf '%s' "$1"
}

# Parse file_path from PostToolUse JSON on stdin; validate existence and (when
# CLAUDE_PROJECT_DIR is set) project membership. Both sides of the membership
# comparison are canonicalized (symlinks resolved) first, so neither an
# escaping symlink nor a project root reached via a symlinked path (e.g.
# macOS /tmp) skews the verdict. Outputs the path on success. Returns 1 to skip.
#   FILE=$(hook::read_file_path) || exit 0
hook::read_file_path() {
  local file
  file=$(jq -r '(.tool_input.file_path // empty) | gsub("\r";"")' 2>/dev/null)
  [[ -n "$file" ]] || return 1
  [[ -f "$file" ]] || return 1
  if [[ -n "${CLAUDE_PROJECT_DIR:-}" ]]; then
    local norm_file norm_project
    norm_file=$(hook::normalize_path "$(hook::physical_path "$file")")
    norm_project=$(hook::normalize_path "$(hook::physical_path "${CLAUDE_PROJECT_DIR}")")
    norm_project="${norm_project%/}"
    # Anchor on a path-segment boundary: accept the project root itself or a
    # child under it, but not a sibling whose name merely shares the prefix
    # (e.g. /c/repo must not admit /c/repo-backup/...).
    if [[ "$norm_file" != "$norm_project" && "$norm_file" != "$norm_project"/* ]]; then
      return 1
    fi
  fi
  printf '%s' "$file"
}

# Resolve the repository root (working-tree top) for a path inside the tree.
# markdownlint config auto-discovery is CWD-anchored, so the hook cd's here
# before linting. File-anchored (`git -C "$hint" rev-parse --show-toplevel`)
# so it is correct for clones, linked worktrees, and bare-hub clones; falls
# back to the hint (with a trailing /.claude stripped) when git cannot resolve.
#   ROOT=$(hook::repo_root "$some_path")
hook::repo_root() {
  local hint="${1:-.}"
  local root
  root=$(git -C "$hint" rev-parse --show-toplevel 2>/dev/null | tr -d '\r')
  if [[ -z "$root" ]]; then
    root="$hint"
    root="${root%/.claude}"
    root="${root%\\.claude}"
  fi
  printf '%s' "$root"
}

# Buffer a complete JSON payload from stdin, tolerating Windows Win32-pipe
# late-EOF stalls via a bounded read on the inherited fd0. Returns the payload
# on success; returns 1 on empty/incomplete stdin (caller skips), or 2 when the
# read timed out before a complete JSON payload arrived (caller may block).
# Bound is the stdin_read_timeout userConfig option in seconds (read via
# CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT, default 2). jq (when present)
# distinguishes a truncated read from a genuinely small-but-complete payload; a
# missing/broken jq (exit 127) fails open like absent jq.
#   INPUT=$(hook::buffer_stdin) || exit 0
hook::buffer_stdin() {
  local input="" read_status=0 read_timeout="${CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT:-2}" start_epoch elapsed_ms timeout_ms
  start_epoch=${EPOCHREALTIME:-}
  IFS= read -r -d '' -t "$read_timeout" input || read_status=$?
  # Parameter expansion, not `$(printf … | tr -d …)`: this runs in every hook on
  # every tool call, and two process spawns per invocation is the single largest
  # fixed cost in the hook layer on Windows, where fork emulation makes a spawn
  # cost hundreds of milliseconds. The trailing-newline trim reproduces exactly
  # what the command substitution used to strip, so the returned payload — and
  # the emptiness test below — are byte-identical to the previous form.
  input="${input//$'\r'/}"
  while [[ "$input" == *$'\n' ]]; do input="${input%$'\n'}"; done
  [[ -n "$input" ]] || return 1
  local jq_rc=0
  if [[ "$read_status" -ne 0 ]] && command -v jq >/dev/null 2>&1; then
    jq -e . >/dev/null 2>&1 <<<"$input" || jq_rc=$?
  fi
  if [[ "$read_status" -ne 0 && "$jq_rc" -ne 0 && "$jq_rc" -ne 127 ]]; then
    elapsed_ms=$(awk -v start="$start_epoch" -v end="$EPOCHREALTIME" 'BEGIN { printf "%.0f", (end - start) * 1000 }')
    timeout_ms=$(awk -v timeout="$read_timeout" 'BEGIN { printf "%.0f", timeout * 1000 }')
    if [[ "$elapsed_ms" =~ ^[0-9]+$ && "$timeout_ms" =~ ^[0-9]+$ ]] &&
      ((elapsed_ms + 100 >= timeout_ms)); then
      echo "BLOCKED: hook stdin timed out before a complete JSON payload arrived." >&2
      return 2
    fi
    return 1
  fi
  printf '%s' "$input"
}

# Extract a single jq field from a buffered input string. CR-stripped. Returns 1
# when the field is empty or jq fails, so the caller can skip.
#   FIELD=$(hook::jq_field "$INPUT" '.tool_input.file_path') || exit 0
hook::jq_field() {
  local field
  field=$(jq -r "(${2} // empty)"' | gsub("\r";"")' <<<"$1" 2>/dev/null)
  [[ -n "$field" ]] || return 1
  printf '%s' "$field"
}

# Extract several jq fields from a buffered input string in ONE jq process,
# into the HOOK_JQ_FIELDS array (one element per expression, same order).
# Each value is CR-stripped, exactly as a per-field `jq -r … | tr -d '\r'`
# pipeline was. Always returns 0 when given at least one expression: a missing
# field, a null, or unparsable input yields an empty element, so callers keep
# their own emptiness checks. Supply each expression's own default
# (`… // ""`, `… // "Bash"`).
#   hook::jq_fields "$INPUT" '.tool_name // "Bash"' '.tool_input.command // ""'
#   TOOL_NAME=${HOOK_JQ_FIELDS[0]} COMMAND=${HOOK_JQ_FIELDS[1]}
#
# A hook pays hundreds of milliseconds per process spawn on Windows, so the
# per-field pipelines this replaces dominated hook latency. Values are joined on
# U+001E (RECORD SEPARATOR) and split with parameter expansion alone — no
# subshell, and no constraint on which field may contain newlines, unlike a
# newline-delimited read. jq strips U+001E from every value before joining, so
# payload text can never shift a later field into an earlier one — a caller
# whose earlier field is attacker-influenced (a file path) would otherwise
# misassign the content field and scan the wrong bytes. Stripping is the same
# contract the per-field pipelines already applied to CR, and removing a
# character can only merge adjacent text, never split a token, so no detection
# pattern is weakened.
#
# Each expression must yield exactly one value; a multi-output expression
# (`.[]`) desynchronizes the array.
hook::jq_fields() {
  local input="$1" prog="" expr rest field sep=$'\x1e' i n
  shift
  HOOK_JQ_FIELDS=()
  (($#)) || return 1
  for expr in "$@"; do
    [[ -n "$prog" ]] && prog+=","
    prog+="($expr)"
  done
  rest=$(jq -r "[$prog]"' | map(tostring | gsub("[\r\u001e]";"")) | join("\u001e")' <<<"$input" 2>/dev/null)
  n=$#
  for ((i = 1; i < n; i++)); do
    field="${rest%%"$sep"*}"
    rest="${rest#*"$sep"}"
    HOOK_JQ_FIELDS+=("$field")
  done
  HOOK_JQ_FIELDS+=("$rest")
}

# Reduce a tool + optional Bash command to a privacy-safe subject label. For
# Bash, returns "Bash:<first-token>" (leading sudo / VAR=val prefixes stripped,
# basename applied) — never the full command. For any other tool, returns the
# tool name unchanged. Carries no argument body, path, or command tail.
#
# Whitespace-splitting is only safe when no quoted value spans the whitespace.
# A quoted assignment value (e.g. `TOKEN="a b" curl …`) would otherwise leak a
# fragment of the value into the token, so any token carrying a quote aborts to a
# bare "Bash" subject rather than risk exposing part of the value.
#   SUBJECT=$(hook::extract_bash_subject "$TOOL" "$CMD")
hook::extract_bash_subject() {
  local tool="$1" cmd="${2:-}"
  if [[ "$tool" != "Bash" ]]; then
    printf '%s' "$tool"
    return 0
  fi
  # Trim leading whitespace so the first token is real.
  cmd="${cmd#"${cmd%%[![:space:]]*}"}"
  local first_token="${cmd%%[[:space:]]*}"
  while [[ "$first_token" == "sudo" || "$first_token" == *=* ]] &&
    [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
    # A quote in the prefix token means a quoted value spans the next whitespace;
    # we cannot tokenize it safely — bail rather than leak a value fragment.
    if [[ "$first_token" == *[\"\']* ]]; then
      printf '%s' "$tool"
      return 0
    fi
    cmd="${cmd#*[[:space:]]}"
    cmd="${cmd#"${cmd%%[![:space:]]*}"}"
    first_token="${cmd%%[[:space:]]*}"
  done
  # The resolved command token itself must not carry a quote (e.g. a value that
  # ended here), which would likewise be a value fragment.
  if [[ "$first_token" == *[\"\']* ]]; then
    printf '%s' "$tool"
    return 0
  fi
  first_token="${first_token##*/}"
  if [[ -n "$first_token" ]]; then
    printf 'Bash:%s' "$first_token"
  else
    printf '%s' "$tool"
  fi
}

# Append one line to a JSONL file, serialized under an flock advisory lock when
# flock is present (bounded 2s wait; a lost race drops the line rather than
# blocking) and a best-effort bare append otherwise. Fire-and-forget: never
# fails the caller. Used by audit hooks that maintain a bespoke second store.
#   hook::append_jsonl <file> <line>
hook::append_jsonl() {
  local file="$1" line="$2"
  if command -v flock >/dev/null 2>&1; then
    (
      flock -w 2 9 || exit 0
      printf '%s\n' "$line" >>"$file"
    ) 9>"${file}.lock" 2>/dev/null
  else
    printf '%s\n' "$line" >>"$file" 2>/dev/null
  fi
}

# Per-hook stdout context accumulator. ctx_reset at entry, ctx_append per line,
# ctx_flush once at exit with the hook event name.
_HOOK_CTX_BUFFER=""

hook::ctx_reset() {
  _HOOK_CTX_BUFFER=""
}

hook::ctx_append() {
  _HOOK_CTX_BUFFER+="$1"$'\n'
}

# Emit the accumulated context as hookSpecificOutput JSON, then clear the buffer.
hook::ctx_flush() {
  local event_name="$1"
  local trimmed="${_HOOK_CTX_BUFFER%"${_HOOK_CTX_BUFFER##*[![:space:]]}"}"
  trimmed="${trimmed#"${trimmed%%[![:space:]]*}"}"
  hook::emit_additional_context "$event_name" "$trimmed"
  hook::ctx_reset
}

# Cheap telemetry opt-in probe — true iff a consumer wired a sink. Producers
# gate telemetry-payload construction on this (repo-relative path
# normalization, data JSON) so the unwired default path spawns zero
# telemetry-only subprocesses. Pure shell test, no subprocess.
# hook::emit_telemetry re-checks the sink itself, so skipping this probe
# costs only wasted payload work, never correctness.
hook::telemetry_enabled() {
  [[ -n "${HOOK_TELEMETRY_SINK:-}" ]]
}

# Emit one telemetry envelope per hook run to the consumer-set sink.
# Fire-and-forget: sink is dispatched in the background; the hook never waits
# on it and its failure never affects the hook's own exit code or stdout.
# Opt-in guard: HOOK_TELEMETRY_SINK unset or empty → return 0 immediately.
# Fail-open: jq absent → return 0 immediately.
#
# Usage:
#   hook::emit_telemetry <hook_id> <hook_event> <status> <start_epoch> <data_json> [repo_root]
#
# <start_epoch>  Value of $EPOCHREALTIME captured by the caller before work began.
#               Handles both '.' and ',' as the decimal separator (LC_NUMERIC).
# <data_json>   Pre-built JSON object for the `data` field.
# <repo_root>   Optional consuming-repo root, used to resolve a RELATIVE
#               HOOK_TELEMETRY_SINK. The caller passes the root it already
#               resolved for data.file; ignored when the sink is absolute.
#
# Sink path resolution: HOOK_TELEMETRY_SINK may be absolute OR relative to the
# consuming repo root. Absolute (POSIX /… or Windows X:\ / X:/) is used as-is; a
# relative value is joined onto <repo_root> (or $CLAUDE_PROJECT_DIR when no root
# is passed), and skipped fail-open if neither is available. Relative is the
# portable, team-shared wiring form: CC injects settings.json env values
# literally (no ${VAR} expansion), so a relative path tracked in settings.json is
# the only clone-portable, worktree-safe option.
#
# NEVER writes to fd1 (the hook's stdout / additionalContext channel).
hook::emit_telemetry() {
  # Opt-in guard.
  [[ -n "${HOOK_TELEMETRY_SINK:-}" ]] || return 0
  # Fail-open when jq is absent.
  command -v jq >/dev/null 2>&1 || return 0

  local hook_id="$1"
  local hook_event="$2"
  local status="$3"
  local start_epoch="$4"
  local data_json="$5"
  local repo_root="${6:-}"

  # Compute duration_ms from caller's $EPOCHREALTIME snapshot to now.
  # Both '.' and ',' separators handled; 10# prefix prevents octal misreading
  # of fractional parts with leading zeros (e.g. .045123 → 10#045123 = 45123).
  # EPOCHREALTIME is Bash 5.0+; on an older host it (and the caller's start
  # snapshot) is empty. Skip telemetry fail-open rather than abort under set -u —
  # the same silent-skip the caller's `START=${EPOCHREALTIME:-}` guard intends.
  local now=${EPOCHREALTIME:-}
  [[ -n "$start_epoch" && -n "$now" ]] || return 0
  local s_s="${start_epoch%[.,]*}" s_f="${start_epoch#*[.,]}"
  local e_s="${now%[.,]*}" e_f="${now#*[.,]}"
  local duration_ms=$(((e_s * 1000000 + 10#$e_f - s_s * 1000000 - 10#$s_f) / 1000))

  # True UTC timestamp (TZ= prefix overrides LC_ALL / local TZ; the Z is not a lie).
  local timestamp
  timestamp=$(TZ=UTC printf '%(%Y-%m-%dT%H:%M:%SZ)T' -1)

  # Build the envelope. Redirect jq stderr to /dev/null; output goes to a local
  # variable — never to fd1.
  local envelope
  envelope=$(jq -n \
    --arg schema_version "1.0" \
    --arg timestamp "$timestamp" \
    --arg hook "$hook_id" \
    --arg hook_event "$hook_event" \
    --arg status "$status" \
    --argjson duration_ms "$duration_ms" \
    --argjson data "$data_json" \
    '{schema_version:$schema_version,timestamp:$timestamp,hook:$hook,hook_event:$hook_event,status:$status,duration_ms:$duration_ms,data:$data}' \
    2>/dev/null) || return 0

  # Resolve the sink path. A relative HOOK_TELEMETRY_SINK is joined onto the
  # consuming repo root (portable, tracked wiring); absolute is used as-is. A
  # relative value with no anchor is skipped fail-open — never exec a path the
  # drifted hook CWD would resolve incorrectly.
  local sink="$HOOK_TELEMETRY_SINK"
  case "$sink" in
  /* | [A-Za-z]:[/\\]*) ;;
  *)
    local root="${repo_root:-${CLAUDE_PROJECT_DIR:-}}"
    [[ -n "$root" ]] || return 0
    sink="${root%/}/$sink"
    ;;
  esac

  # Fire-and-forget: pipe the envelope to the sink in a background subshell.
  # The subshell's stdout AND stderr are redirected to /dev/null so the sink
  # cannot write to the hook's fd1 (the additionalContext channel) and the
  # backgrounded subshell does not hold a copy of the hook's fd1 open — which
  # would block any command substitution wrapping the hook until the sink exits
  # (the "C1 fd1-inheritance blocker"). The sink is quoted — it is a single
  # executable path (wrap in a script to pass arguments).
  printf '%s\n' "$envelope" | ("$sink" >/dev/null 2>&1) &
}

# Print cross-host hook JSON to stdout (exit 0). No-op when context is empty.
# Shape: { hookSpecificOutput: { hookEventName[, additionalContext] } }.
hook::emit_additional_context() {
  local event_name="$1"
  local context="$2"
  [[ -n "$context" ]] || return 0
  command -v jq >/dev/null 2>&1 || return 0
  jq -n \
    --arg event "$event_name" \
    --arg ctx "$context" \
    '{hookSpecificOutput: (
      {hookEventName: $event}
      + (if $ctx != "" then {additionalContext: $ctx} else {} end)
    )}'
}

# ---------------------------------------------------------------------------
# Argv-grammar-faithful Bash command parsing for git guards. The command is
# parsed the way the shell builds argv — top-level segments split on unquoted
# control operators, each tokenized into argv words honoring '…', "…", $'…'
# (ANSI-C), and backslash escapes — then a real git executable is resolved at
# the segment's command position past env-var assignments and known wrappers,
# and its subcommand resolved past git global options.
#
# Static matching over the literal command string only: shell variable and
# command substitution ($VAR, $(…)) are NOT evaluated. Guards built on this
# are friction against accidental/casual bypass, not a sandbox.

# Decode an ANSI-C `$'…'` body to its literal bytes (\xHH, \NNN octal, \uHHHH,
# \n, \\, …). %-escaped so the body can never act as a printf format specifier;
# `--` guards a body that begins with `-`. Errors are swallowed (fail-open on a
# malformed body — the raw text still flows through the caller unchanged).
hook::ansi_c_decode() {
  local b="${1//%/%%}"
  # shellcheck disable=SC2059  # the body IS the format — that is how ANSI-C escapes decode; %-escaped above so it cannot inject a specifier
  printf -- "$b" 2>/dev/null
}

# Split a GNU `env -S` operand the way env does: whitespace-separated words
# honoring "…" and '…' quotes and backslash escapes — so a flag quoted inside
# the operand (`env -S 'git push "--force"'`) still surfaces as its unquoted
# argv word. env's $VAR expansion inside the operand is NOT evaluated (static
# analysis over the literal string — same residual as the segment tokenizer).
# Result in the global HOOK_ENV_S_WORDS array.
# shellcheck disable=SC2034  # result global is consumed by hook::git_resolve_index
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
hook::env_s_split() {
  local s="$1" i c n=${#1} word="" have=0
  HOOK_ENV_S_WORDS=()
  for ((i = 0; i < n; i++)); do
    c="${s:i:1}"
    case "$c" in
    "'")
      ((i++))
      while ((i < n)) && [[ "${s:i:1}" != "'" ]]; do
        word+="${s:i:1}"
        ((i++))
      done
      have=1
      ;;
    '"')
      ((i++))
      while ((i < n)) && [[ "${s:i:1}" != '"' ]]; do
        if [[ "${s:i:1}" == '\' ]] && ((i + 1 < n)); then
          word+="${s:i+1:1}"
          ((i += 2))
          continue
        fi
        word+="${s:i:1}"
        ((i++))
      done
      have=1
      ;;
    '\')
      if ((i + 1 < n)); then
        word+="${s:i+1:1}"
        ((i++))
      fi
      have=1
      ;;
    ' ' | $'\t')
      if ((have)); then
        HOOK_ENV_S_WORDS+=("$word")
        word=""
        have=0
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  ((have)) && HOOK_ENV_S_WORDS+=("$word")
}

# Detect a `sh -c` style shell wrapper in a segment's argv: a shell at the
# command position (after leading env-var assignments) carrying a `-c` flag.
# On match, the command-string operand lands in HOOK_SHELL_C_OPERAND for the
# caller to re-parse with hook::bash_parse_segments — the operand is a full
# shell command (operators, quoting, everything), so re-parsing with the same
# tokenizer is the faithful treatment. Wrappers stacked in front of the shell
# (`sudo bash -c …`) are NOT resolved here — a documented residual of the
# static-matcher posture. A shell invoked on a script file (no -c) never
# matches: file contents cannot be inspected statically.
# shellcheck disable=SC2034  # result global is consumed by the sourcing guard
hook::shell_c_operand() {
  local -a w=("$@")
  local n=${#w[@]} i=0 b t has_c=0
  # Skip leading VAR=val assignments, mirroring the git resolver.
  while ((i < n)) && [[ "${w[i]}" == *=* && "${w[i]}" != -* ]]; do ((i++)); done
  ((i < n)) || return 1
  b="${w[i]##*/}"
  b="${b##*\\}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    b="${b,,}"
    b="${b%.exe}"
    ;;
  *) ;;
  esac
  case "$b" in
  bash | sh | zsh | dash | ksh | mksh) ;;
  *) return 1 ;;
  esac
  ((i++))
  while ((i < n)); do
    t="${w[i]}"
    case "$t" in
    --)
      ((i++))
      break
      ;;
    # -o/-O (and +o/+O) consume a set/shopt operand; --rcfile/--init-file
    # consume a startup-file operand (bash) — none of these ends the option
    # scan, so `bash --rcfile /dev/null -c '…'` still reaches its -c.
    -o | +o | -O | +O | --rcfile | --init-file) ((i += 2)) ;;
    -*)
      [[ "$t" =~ ^-[A-Za-z]+$ && "$t" == *c* ]] && has_c=1
      ((i++))
      ;;
    *) break ;;
    esac
  done
  ((has_c)) || return 1
  ((i < n)) || return 1
  HOOK_SHELL_C_OPERAND="${w[i]}"
  return 0
}

# Does an argv word name the git executable? Basename compared exactly on
# POSIX; on Windows/MSYS also case-folded and `.exe`-stripped (mirrors the
# OS-gate in hook::normalize_path) so `GIT` / `git.exe` are caught there but a
# case-variant stays distinct on a case-sensitive POSIX filesystem.
hook::git_is_bin() {
  local b="${1##*/}"
  b="${b##*\\}"
  case "${OSTYPE:-}" in
  msys* | cygwin* | win32)
    local lc="${b,,}"
    lc="${lc%.exe}"
    [[ "$lc" == "git" ]]
    ;;
  *) [[ "$b" == "git" ]] ;;
  esac
}

# Locate a real `git` executable at the segment's command position (after
# env-var prefixes and known wrappers), or return 1 when absent. Results go in
# globals, NOT a $( ) echo: `env -S` splicing rewrites the argv, and the caller
# must match on the rewritten words, so the index alone is not enough.
#   HOOK_GIT_RESOLVED_GI    — index of git in HOOK_GIT_RESOLVED_WORDS
#   HOOK_GIT_RESOLVED_WORDS — the (possibly rewritten) segment argv
# Leading `NAME=value` env-assignment prefixes and `env NAME=value` operands are walked
# PAST to reach the git token, but their values are not collected: a `--config-env` alias
# for the invoked subcommand is refused by SHAPE (hook::git_alias_expansion), so the
# resolver never needs to know what an environment variable holds.
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_resolve_index() {
  HOOK_GIT_RESOLVED_WORDS=("$@")
  HOOK_GIT_RESOLVED_GI=-1
  # shellcheck disable=SC2178  # nameref to the array result global, not a string assignment
  local -n w=HOOK_GIT_RESOLVED_WORDS
  local n=${#w[@]} i=0 tok

  while ((i < n)); do
    tok="${w[i]}"
    if [[ "$tok" == *=* ]]; then
      # A leading NAME=value token is a command-line env-assignment prefix; skip it to
      # reach the git token (the shell treats only a valid-name assignment as such, but
      # skipping any `*=*` word here is harmless — a non-assignment command word never
      # contains an unquoted `=` at argv position 0 in a real invocation).
      ((i++))
      continue
    fi

    case "${tok##*/}" in
    env)
      # env [OPTION]... [--] [NAME=VALUE]... [COMMAND ...]: options first, then
      # operand assignments, then the command. `--` ends option parsing (so a
      # following leading-dash operand like `-AV=…` is an assignment, not an
      # option). Unlike a shell prefix, env sets any name — collect every operand
      # assignment regardless of name shape so a hyphenated/leading-dash name git
      # reads via --config-env is captured, not dropped.
      ((i++))
      local env_past_optmark=0
      while ((i < n)); do
        if ((env_past_optmark == 0)) && [[ "${w[i]}" == -* ]]; then
          case "${w[i]}" in
          --)
            ((i++))
            env_past_optmark=1
            ;;
          # -S/--split-string re-splits its operand into argv (GNU env), so a
          # quoted 'git commit --no-verify' would otherwise hide from the
          # resolver as one non-git word. Splice the split words back into the
          # scan and restart at the command position.
          -S | --split-string)
            local sval=""
            ((i + 1 < n)) && sval="${w[i + 1]}"
            hook::env_s_split "$sval"
            w=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} "${w[@]:i+2}")
            n=${#w[@]}
            i=0
            continue 2
            ;;
          -S* | --split-string=*)
            local sval="${w[i]#-S}"
            sval="${sval#--split-string=}"
            hook::env_s_split "$sval"
            w=(${HOOK_ENV_S_WORDS[@]+"${HOOK_ENV_S_WORDS[@]}"} "${w[@]:i+1}")
            n=${#w[@]}
            i=0
            continue 2
            ;;
          -u | --unset | -C | --chdir) ((i += 2)) ;;
          -*) ((i++)) ;;
          *) ((i++)) ;;
          esac
        elif [[ "${w[i]}" == *=* ]]; then
          # An `env NAME=value` operand — skip it to reach the command (git). Its value
          # is never read: a --config-env alias is refused by shape, not resolved.
          ((i++))
        else
          break
        fi
      done
      continue
      ;;
    nice | nohup)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -n | --adjustment) ((i += 2)) ;;
        --adjustment=*) ((i++)) ;;
        -*) ((i++)) ;;
        *) break ;;
        esac
      done
      if ((i < n)) && [[ "${w[i]}" =~ ^-?[0-9]+$ ]]; then
        ((i++))
      fi
      continue
      ;;
    sudo)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -u | -g | -h | -p | -C | -D | -R | -T | --user | --group | --chdir) ((i += 2)) ;;
        -*) ((i++)) ;;
        *) ((i++)) ;;
        esac
      done
      continue
      ;;
    timeout)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
        -s | --signal | -k | --kill-after) ((i += 2)) ;;
        --preserve-status | --foreground | --verbose) ((i++)) ;;
        -*) ((i++)) ;;
        *) break ;;
        esac
      done
      if ((i < n)) && [[ "${w[i]}" =~ ^[0-9]+([.][0-9]+)?(s|m|h|d)?$ ]]; then
        ((i++))
      fi
      continue
      ;;
    # eval concatenates and re-executes its arguments, so for the unquoted
    # form (`eval git commit ...`) scanning the following words is exact.
    # command/exec carry their own options before the real command
    # (`command [-pVv]`, `exec [-cl] [-a name]`) and an optional `--`
    # end-of-options marker (`command -- git …`) — skip them so the git
    # command behind the wrapper is still resolved. But `command -v`/`-V`
    # only PRINT the command's path/description — nothing runs — so a git
    # word behind them is a probe, not an invocation: bail out.
    command | exec | builtin | eval | !)
      local is_command=0
      [[ "${tok##*/}" == "command" ]] && is_command=1
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* && "${w[i]}" != "--" ]]; do
        if ((is_command)) && [[ "${w[i]}" == -*[vV]* ]]; then
          return 1
        fi
        [[ "${w[i]}" == "-a" ]] && ((i++))
        ((i++))
      done
      ((i < n)) && [[ "${w[i]}" == "--" ]] && ((i++))
      continue
      ;;
    time)
      ((i++))
      if ((i < n)) && [[ "${w[i]}" == "-p" ]]; then
        ((i++))
      fi
      continue
      ;;
    # Compound-command reserved words at the execution position: a command
    # can directly follow any of these within one segment (`if git …`,
    # `then git …`, `do git …`), so skip them and keep resolving.
    if | then | elif | else | while | until | for | do | case | select | coproc | '{' | '}')
      ((i++))
      continue
      ;;
    *)
      if hook::git_is_bin "$tok"; then
        HOOK_GIT_RESOLVED_GI=$i
        return 0
      fi
      return 1
      ;;
    esac
  done
  return 1
}

# Resolve the git subcommand in an already-resolved segment: walk words after
# the git executable, skipping git global options. The listed options consume
# the FOLLOWING word as their value (two-word form); their =-forms and every
# other option are single words handled by the generic `-*` skip. Results in
# globals:
#   HOOK_GIT_SUB           — the subcommand word ("" when none found)
#   HOOK_GIT_SUB_IDX       — its index in the argv (-1 when none)
#   HOOK_GIT_CONFIG_VALUES — values of -c/--config/--config-env options, in
#                            order, so a guard can inspect config assignments
#                            without re-walking (commit messages and pathspecs
#                            are never collected here)
#   HOOK_GIT_CONFIG_VALUE_KINDS — parallel to HOOK_GIT_CONFIG_VALUES (1:1 by
#                            index): "inline" for a -c/--config value (the literal
#                            assignment) or "env" for a --config-env value (whose
#                            operand is `<key>=<envvar>`, an environment-variable
#                            NAME, not the value). An env-kind alias for the invoked
#                            subcommand is REFUSED by shape (hook::git_alias_expansion),
#                            never resolved — the value is deliberately never read.
# Call as: hook::git_resolve_subcommand <git-index> <argv words...>
# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_resolve_subcommand() {
  local gi="$1"
  shift
  local -a w=("$@")
  local nseg=${#w[@]} j gw
  HOOK_GIT_SUB=""
  HOOK_GIT_SUB_IDX=-1
  HOOK_GIT_CONFIG_VALUES=()
  HOOK_GIT_CONFIG_VALUE_KINDS=()

  j=$((gi + 1))
  while ((j < nseg)); do
    gw="${w[j]}"
    case "$gw" in
    -c | --config)
      ((j + 1 < nseg)) && {
        HOOK_GIT_CONFIG_VALUES+=("${w[j + 1]}")
        HOOK_GIT_CONFIG_VALUE_KINDS+=("inline")
      }
      ((j += 2))
      ;;
    --config-env)
      ((j + 1 < nseg)) && {
        HOOK_GIT_CONFIG_VALUES+=("${w[j + 1]}")
        HOOK_GIT_CONFIG_VALUE_KINDS+=("env")
      }
      ((j += 2))
      ;;
    --config=*)
      HOOK_GIT_CONFIG_VALUES+=("${gw#*=}")
      HOOK_GIT_CONFIG_VALUE_KINDS+=("inline")
      ((j++))
      ;;
    --config-env=*)
      HOOK_GIT_CONFIG_VALUES+=("${gw#*=}")
      HOOK_GIT_CONFIG_VALUE_KINDS+=("env")
      ((j++))
      ;;
    -C | --git-dir | --work-tree | --namespace | --super-prefix | --attr-source | --exec-path)
      ((j += 2))
      ;;
    -*)
      ((j++))
      ;;
    *)
      HOOK_GIT_SUB="$gw"
      HOOK_GIT_SUB_IDX=$j
      return 0
      ;;
    esac
  done
  return 1
}

# Classify how a guard should treat the alias for the invoked subcommand, from the
# config values collected by hook::git_resolve_subcommand. git reads TWO spellings as the
# alias for a subcommand — `alias.<sub>` and its `alias.<sub>.command` subkey (the only
# alias subkey git reads) — and which spelling wins when both are set is git-version-
# dependent. Rather than model that precedence (and risk a benign value in one spelling
# masking a dangerous value in the other on a git that resolves it the opposite way), this
# classifier fails closed on the MAX-DANGER UNION of the two spellings: the LAST value
# WITHIN each spelling decides that spelling (git applies the last value for a given key),
# then the spellings combine so the guard blocks if EITHER could carry a guarded op.
#
#   - "env" (--config-env=<key>=<envvar>) in EITHER spelling: the expansion lives in an
#     environment variable whose VALUE is deliberately never read — that value is the
#     recurring attack surface (an ambient var, an inline/`env` prefix, an `export`,
#     `set -a`, or a nested `bash -c`, in this or any enclosing wrapper), and each attempt
#     to resolve it has reopened a fail-open. Nobody legitimately defines an alias for a
#     guarded subcommand via --config-env on the invoking command line (the canonical form
#     is a gitconfig alias or the plain subcommand), so the SHAPE alone is sufficient.
#     Returns 2 — the guard blocks without reading anything.
#   - "inline" (-c/--config), no env spelling: each present spelling's expansion is
#     literally present and bounded. Returns 0 with HOOK_GIT_ALIAS_EXPS holding one entry
#     per present spelling (1 or 2), so the guard re-checks every expansion and blocks if
#     any is dangerous — a benign expansion never suppresses a dangerous sibling.
#   - neither spelling present: returns 1, the subcommand is not an inline/env alias here.
#
# A --config-env that sets a NON-alias key, or an alias for a subcommand OTHER than the
# invoked one, never matches — those stay resolvable/allowed. Call after
# hook::git_resolve_subcommand; read HOOK_GIT_ALIAS_EXPS only on return 0.
# shellcheck disable=SC2034  # HOOK_GIT_ALIAS_EXPS is consumed by the sourcing guard
hook::git_alias_expansion() {
  local sub="$1" i cv key kind
  local plain_exp="" plain_kind="" cmd_exp="" cmd_kind=""
  HOOK_GIT_ALIAS_EXPS=()
  # git config names are case-insensitive: fold both sides of the exact key match. Keep
  # the LAST value WITHIN each spelling separately, never collapsed across the two, so one
  # spelling's value cannot mask the other's.
  for i in "${!HOOK_GIT_CONFIG_VALUES[@]}"; do
    cv="${HOOK_GIT_CONFIG_VALUES[i]}"
    key="${cv%%=*}"
    kind="${HOOK_GIT_CONFIG_VALUE_KINDS[i]:-inline}"
    if [[ "${key,,}" == "alias.${sub,,}" ]]; then
      plain_exp="${cv#*=}"
      plain_kind="$kind"
    elif [[ "${key,,}" == "alias.${sub,,}.command" ]]; then
      cmd_exp="${cv#*=}"
      cmd_kind="$kind"
    fi
  done
  # Max-danger union: an env spelling in either place is unreadable — value-blind refusal.
  [[ "$plain_kind" == "env" || "$cmd_kind" == "env" ]] && return 2
  [[ -n "$plain_kind" ]] && HOOK_GIT_ALIAS_EXPS+=("$plain_exp")
  [[ -n "$cmd_kind" ]] && HOOK_GIT_ALIAS_EXPS+=("$cmd_exp")
  ((${#HOOK_GIT_ALIAS_EXPS[@]})) && return 0
  return 1
}

# Single linear pass: read the command into a char array once (O(n)), then walk
# it splitting top-level segments on UNQUOTED control operators and tokenizing
# each segment into argv words honoring '…', "…", $'…', and backslash escapes
# (including backslash-newline continuation). Each completed segment is passed
# to the callback as it closes, so no full segment list is retained.
# Call as: hook::bash_parse_segments <command-string> <callback>; the callback
# receives one segment's argv words as "$@".
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
hook::bash_parse_segments() {
  local cmd="$1" cb="$2"
  local -a chars=()
  local c nx
  while IFS= read -rN1 c; do chars+=("$c"); done < <(printf '%s' "$cmd")
  local n=${#chars[@]} i
  local word="" have=0 skipnext=0
  local -a seg=()
  # Pending heredoc delimiters (FIFO) and their `<<-` tab-strip flags. A
  # heredoc body is the command's stdin, not commands — recorded when `<<`
  # is seen and skipped wholesale at the command-line newline.
  local -a hd_delims=() hd_strip=()

  for ((i = 0; i < n; i++)); do
    c="${chars[i]}"
    case "$c" in
    "'")
      ((i++))
      while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
        word+="${chars[i]}"
        ((i++))
      done
      have=1
      ;;
    '"')
      ((i++))
      while ((i < n)) && [[ "${chars[i]}" != '"' ]]; do
        if [[ "${chars[i]}" == '\' ]] && ((i + 1 < n)); then
          nx="${chars[i + 1]}"
          case "$nx" in
          '"' | '\' | '$' | '`')
            word+="$nx"
            ((i += 2))
            continue
            ;;
          $'\n')
            ((i += 2))
            continue
            ;;
          *) ;;
          esac
        fi
        word+="${chars[i]}"
        ((i++))
      done
      have=1
      ;;
    '$')
      if ((i + 1 < n)) && [[ "${chars[i + 1]}" == "'" ]]; then
        i=$((i + 2))
        local body=""
        while ((i < n)) && [[ "${chars[i]}" != "'" ]]; do
          if [[ "${chars[i]}" == '\' ]] && ((i + 1 < n)); then
            body+="${chars[i]}${chars[i + 1]}"
            ((i += 2))
            continue
          fi
          body+="${chars[i]}"
          ((i++))
        done
        word+="$(hook::ansi_c_decode "$body")"
        have=1
      else
        word+="$c"
        have=1
      fi
      ;;
    '\')
      if ((i + 1 < n)); then
        nx="${chars[i + 1]}"
        if [[ "$nx" == $'\n' ]]; then
          ((i++))
        else
          word+="$nx"
          ((i++))
          have=1
        fi
      else
        have=1
      fi
      ;;
    ' ' | $'\t')
      if ((have)); then
        if ((skipnext)); then skipnext=0; else seg+=("$word"); fi
        word=""
        have=0
      fi
      ;;
    '>' | '<')
      # Redirection: bash removes the operator and its target word from
      # argv (redirections may appear anywhere in a simple command), so
      # `git reset --hard>/tmp/out` still runs reset --hard. A pure-digit
      # word immediately before the operator is its fd prefix, not argv;
      # an fd-dup/close form (`2>&1`, `>&-`) has no target word to skip.
      if ((have)); then
        if [[ "$word" =~ ^[0-9]+$ ]]; then
          :
        elif ((skipnext)); then
          skipnext=0
        else
          seg+=("$word")
        fi
        word=""
        have=0
      fi
      # Heredoc `<<` / `<<-` (but NOT here-string `<<<`): the body on the
      # following lines is the command's stdin, so record the delimiter and
      # let the newline handler skip the body. A quoted/backslashed delimiter
      # (`<<'EOF'`, `<<\EOF`) still terminates on a line reading `EOF`.
      if [[ "$c" == '<' ]] && ((i + 1 < n)) && [[ "${chars[i + 1]}" == '<' ]] &&
        { ((i + 2 >= n)) || [[ "${chars[i + 2]}" != '<' ]]; }; then
        ((i++))
        local hstrip=0
        if ((i + 1 < n)) && [[ "${chars[i + 1]}" == '-' ]]; then
          hstrip=1
          ((i++))
        fi
        while ((i + 1 < n)) && [[ "${chars[i + 1]}" == ' ' || "${chars[i + 1]}" == $'\t' ]]; do ((i++)); done
        local delim=""
        while ((i + 1 < n)); do
          nx="${chars[i + 1]}"
          case "$nx" in
          ' ' | $'\t' | $'\n' | ';' | '&' | '|' | '<' | '>') break ;;
          "'")
            ((i++))
            while ((i + 1 < n)) && [[ "${chars[i + 1]}" != "'" ]]; do
              delim+="${chars[i + 1]}"
              ((i++))
            done
            ((i + 1 < n)) && ((i++))
            ;;
          '"')
            ((i++))
            while ((i + 1 < n)) && [[ "${chars[i + 1]}" != '"' ]]; do
              delim+="${chars[i + 1]}"
              ((i++))
            done
            ((i + 1 < n)) && ((i++))
            ;;
          '\')
            ((i++))
            ((i + 1 < n)) && {
              delim+="${chars[i + 1]}"
              ((i++))
            }
            ;;
          *)
            delim+="$nx"
            ((i++))
            ;;
          esac
        done
        hd_delims+=("$delim")
        hd_strip+=("$hstrip")
        continue
      fi
      if ((i + 1 < n)) && [[ "${chars[i + 1]}" == '(' ]]; then
        # Process substitution <(list)/>(list): the list is a real command
        # substituted as a filename — it satisfies any pending target and
        # the '(' separator splits it into a segment that gets scanned.
        skipnext=0
      else
        while ((i + 1 < n)) && [[ "${chars[i + 1]}" == [\<\>] ]]; do ((i++)); done
        if ((i + 1 < n)) && [[ "${chars[i + 1]}" == '&' ]]; then
          ((i++))
          if ((i + 1 < n)) && [[ "${chars[i + 1]}" == [0-9-] ]]; then
            while ((i + 1 < n)) && [[ "${chars[i + 1]}" == [0-9-] ]]; do ((i++)); done
          else
            skipnext=1
          fi
        else
          skipnext=1
        fi
      fi
      ;;
    ';' | '&' | '|' | '(' | ')' | '`' | $'\n')
      if ((have)); then
        if ((skipnext)); then skipnext=0; else seg+=("$word"); fi
        word=""
        have=0
      fi
      if ((${#seg[@]})); then
        "$cb" "${seg[@]}"
        seg=()
      fi
      # A command-line newline ends the line that introduced any pending
      # heredocs; their bodies (up to and including each delimiter line) are
      # stdin, so consume them without tokenizing. Delimiters match in FIFO
      # order; `<<-` strips leading tabs from body lines before comparing.
      if [[ "$c" == $'\n' ]] && ((${#hd_delims[@]})); then
        local hidx line lc d strip
        for ((hidx = 0; hidx < ${#hd_delims[@]}; hidx++)); do
          d="${hd_delims[hidx]}"
          strip="${hd_strip[hidx]}"
          while ((i + 1 < n)); do
            line=""
            while ((i + 1 < n)) && [[ "${chars[i + 1]}" != $'\n' ]]; do
              line+="${chars[i + 1]}"
              ((i++))
            done
            ((i + 1 < n)) && ((i++))
            lc="$line"
            if ((strip)); then
              while [[ "$lc" == $'\t'* ]]; do lc="${lc#?}"; done
            fi
            [[ "$lc" == "$d" ]] && break
          done
        done
        hd_delims=()
        hd_strip=()
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  if ((have)) && ((!skipnext)); then seg+=("$word"); fi
  if ((${#seg[@]})); then "$cb" "${seg[@]}"; fi
}

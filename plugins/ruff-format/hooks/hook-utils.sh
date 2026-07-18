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

# jq gate for hooks whose input parsing cannot proceed without it. When jq is
# absent: one visible skip notice per session, then exit 0 — an advisory hook
# never blocks the tool over a missing prerequisite. Place after
# hook::check_enabled, passing the buffered stdin for session scoping.
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
  input=$(printf '%s' "$input" | tr -d '\r')
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

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

# Per-hook kill switch via HOOK_<NAME>_ENABLED env var. Exits 0 (allow) if
# disabled. Place after source, before stdin parsing.
#   hook::check_enabled "MARKDOWN_FORMAT"  # checks HOOK_MARKDOWN_FORMAT_ENABLED
hook::check_enabled() {
  local var_name="HOOK_${1}_ENABLED"
  if [[ "${!var_name:-true}" != "true" ]]; then
    exit 0
  fi
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
# Bound is HOOK_STDIN_READ_TIMEOUT seconds (default 2). jq (when present)
# distinguishes a truncated read from a genuinely small-but-complete payload; a
# missing/broken jq (exit 127) fails open like absent jq.
#   INPUT=$(hook::buffer_stdin) || exit 0
hook::buffer_stdin() {
  local input="" read_status=0 read_timeout="${HOOK_STDIN_READ_TIMEOUT:-2}" start_epoch elapsed_ms timeout_ms
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
    if [[ "$elapsed_ms" =~ ^[0-9]+$ && "$timeout_ms" =~ ^[0-9]+$ ]] \
      && ((elapsed_ms + 100 >= timeout_ms)); then
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
  while [[ "$first_token" == "sudo" || "$first_token" == *=* ]] \
    && [[ -n "$cmd" && "$cmd" == *[[:space:]]* ]]; do
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
# shellcheck disable=SC1003  # '\' compares a literal backslash char, not a quote escape
# shellcheck disable=SC2034  # result globals are consumed by the sourcing guard, not this file
hook::git_resolve_index() {
  HOOK_GIT_RESOLVED_WORDS=("$@")
  HOOK_GIT_RESOLVED_GI=-1
  local -n w=HOOK_GIT_RESOLVED_WORDS
  local n=${#w[@]} i=0 tok

  while ((i < n)); do
    tok="${w[i]}"
    if [[ "$tok" == *=* ]]; then
      ((i++))
      continue
    fi

    case "${tok##*/}" in
    env)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do
        case "${w[i]}" in
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
        -u | -C | --chdir) ((i += 2)) ;;
        -*) ((i++)) ;;
        *) ((i++)) ;;
        esac
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
    command | exec | builtin | eval | !)
      ((i++))
      continue
      ;;
    time)
      ((i++))
      if ((i < n)) && [[ "${w[i]}" == "-p" ]]; then
        ((i++))
      fi
      continue
      ;;
    if | while | until | for | case | select | coproc | '{' | '}')
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

  j=$((gi + 1))
  while ((j < nseg)); do
    gw="${w[j]}"
    case "$gw" in
    -c | --config | --config-env)
      ((j + 1 < nseg)) && HOOK_GIT_CONFIG_VALUES+=("${w[j + 1]}")
      ((j += 2))
      ;;
    --config=* | --config-env=*)
      HOOK_GIT_CONFIG_VALUES+=("${gw#*=}")
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
  local word="" have=0
  local -a seg=()

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
        seg+=("$word")
        word=""
        have=0
      fi
      ;;
    ';' | '&' | '|' | '(' | ')' | '`' | $'\n')
      if ((have)); then
        seg+=("$word")
        word=""
        have=0
      fi
      if ((${#seg[@]})); then
        "$cb" "${seg[@]}"
        seg=()
      fi
      ;;
    *)
      word+="$c"
      have=1
      ;;
    esac
  done
  if ((have)); then seg+=("$word"); fi
  if ((${#seg[@]})); then "$cb" "${seg[@]}"; fi
}

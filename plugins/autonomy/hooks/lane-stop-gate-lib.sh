# shellcheck shell=bash
# Trusted-config helpers shared by lane-stop-gate.sh (the Stop hook) and
# lane-stop-gate-arm.sh (the operator-side arming helper). Sourced, not
# executed.
#
# Everything here exists to keep the gate's configuration off the bare
# environment (channel B), which docs/conventions/hook-config-delivery forbids
# for a safety-critical toggle: for an unconfigured key, a watched repository's
# own `.claude/settings.json` `env` block populates `CLAUDE_PLUGIN_OPTION_*`
# freely, and env carries no provenance a hook could check. The trusted sources
# are, in precedence order (mirroring Claude Code's own pluginConfigs merge):
#
#   1. managed settings — fixed root-owned system paths plus the
#      `managed-settings.d/` drop-in directory; a repo cannot forge them. The
#      Windows path is hard-coded, NOT %ProgramFiles%-derived, AND the platform
#      is read from `uname -s` (a process-intrinsic syscall) not `$OSTYPE` (a
#      bash variable a repo `env` block can set): env reaches hook subprocesses,
#      so anything env-derived — a base path OR the branch that selects one —
#      would let a repo redirect or suppress the HIGHEST-precedence scope. The
#      resolved primary path is asserted absolute before use, so a future
#      platform-detection regression cannot yield a cwd-relative managed path a
#      repo could plant inside its own checkout.
#   2. the per-session arm record (gate only) — see lane-stop-gate.sh.
#   3. the user settings.json, located ONLY from this script's own install path
#      via the documented `<config>/plugins/cache/<marketplace>/<name>/<ver>`
#      layout. The script's own location is not something a repo file can
#      redirect; CLAUDE_CONFIG_DIR / HOME are env values and are deliberately
#      not consulted.
#
# A `--plugin-dir` checkout install carries no `plugins/cache` anchor: it has
# no trusted user-settings or record location, so only managed settings can
# configure the gate there (same stance as disk-hygiene's kill-switch reader,
# the convention's channel-F exemplar).

[[ -n "${_LANE_STOP_GATE_LIB_LOADED:-}" ]] && return 0
readonly _LANE_STOP_GATE_LIB_LOADED=1

# Shape of a valid arm-record id: filename-safe, unguessable-length floor. The
# id arrives over the environment (untrusted input), so it is validated before
# it ever touches a path.
readonly GATE_ARM_ID_RE='^[A-Za-z0-9_-]{8,64}$'

# --- Install anchor -----------------------------------------------------------
# Parse this plugin's install layout from the CALLER-SUPPLIED plugin root
# (each entry script passes its own `dirname BASH_SOURCE/..`). Claude Code lays
# a marketplace plugin out at <config>/plugins/cache/<marketplace>/<name>/<ver>
# and persists its data at <config>/plugins/data/<id>, where <id> is
# "<name>@<marketplace>" with every character outside [A-Za-z0-9_-] replaced by
# "-" (plugins reference, "Persistent data directory").
GATE_CONFIG_ROOT=""
GATE_PLUGIN_ID=""
GATE_PLUGIN_ID_SAFE=""
GATE_PLUGIN_NAME=""

gate_resolve_anchor() {
  local root="$1" rest marketplace name
  [[ -n "$root" && "$root" == */plugins/cache/*/*/* ]] || return 1
  rest="${root#*/plugins/cache/}"
  marketplace="${rest%%/*}"
  rest="${rest#*/}"
  name="${rest%%/*}"
  [[ -n "$marketplace" && -n "$name" ]] || return 1
  GATE_CONFIG_ROOT="${root%%/plugins/cache/*}"
  GATE_PLUGIN_ID="${name}@${marketplace}"
  GATE_PLUGIN_ID_SAFE="${GATE_PLUGIN_ID//[^A-Za-z0-9_-]/-}"
}

# This plugin's name, from the manifest beside the caller. The manifest sits at
# a path derived from the caller's own location — the same trust anchor
# everything else here uses — so a repo cannot redirect it.
gate_resolve_plugin_name() {
  local manifest="$1/.claude-plugin/plugin.json" name
  [[ -f "$manifest" ]] || return 1
  # Redirections sit on the enclosing group, not inside the substitution: bash
  # execs a bare `$(jq …)` in the substitution's own subshell, but a redirect
  # written inside it forces a second fork for the same one program. Same
  # program, same input, same suppressed stderr, one process instead of two.
  { name=$(jq -r '.name | select(type == "string")'); } <"$manifest" 2>/dev/null || return 1
  [[ -n "$name" ]] || return 1
  GATE_PLUGIN_NAME="$name"
}

# --- In-process result forms --------------------------------------------------
# Every path helper below has a `_to <var>` form that writes its result into
# the caller's variable with `printf -v`, and a print form that delegates to
# it. The gate hook uses the `_to` forms: a `v=$(gate_x)` capture forks a
# subshell for a function that is nothing but parameter expansion, and on the
# Windows Git Bash host this gate is tuned for that fork is a process. The print
# forms stay for the arm helper and for callers that capture stdout.

# Resolve this install's identity from the caller-supplied plugin root: the
# marketplace-qualified id when the plugins/cache anchor is present, else the
# manifest name. The name path exists for the --plugin-dir install, where
# managed settings are the only enable path and there is no marketplace
# qualifier to match — without it an org's managed mandate would silently not
# apply to that install class.
gate_resolve_install() {
  local root="$1"
  gate_resolve_anchor "$root" && return 0
  gate_resolve_plugin_name "$root"
}

# This plugin's persistent data directory: install-derived when anchored, else
# the CLAUDE_PLUGIN_DATA env fallback (a --plugin-dir install). Used ONLY for the
# marker-consumption ledger, never for enablement or the arm record — those read
# gate_trusted_data_dir (install-anchored, no env fallback). What a redirected
# CLAUDE_PLUGIN_DATA can therefore reach is only the ledger, and only for the
# MARKER completion channel, which is itself an agent-writable declaration: the
# marker file lives in the watched checkout. It cannot enable the gate or forge
# an arm record. The redirect is not failure-direction-safe on its own — an
# empty/unwritable target makes marker_already_consumed find no ledger and a
# surviving marker RE-authorizes (a granted stop) — but that is exactly the
# "no writable data dir → deletion is the only latch" behavior #1851 already
# documented and accepted for the marker channel, not a new exposure. Anchored
# installs never touch this fallback.
gate_data_dir_to() {
  if [[ -n "$GATE_CONFIG_ROOT" ]]; then
    printf -v "$1" '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
  else
    printf -v "$1" '%s' "${CLAUDE_PLUGIN_DATA:-}"
  fi
}
gate_data_dir() {
  local __gate_out
  gate_data_dir_to __gate_out
  printf '%s' "$__gate_out"
}

# Install-derived data directory ONLY — no env fallback. Fails when unanchored.
# Arm records live here because a record can GRANT gate behavior: an env-derived
# store would let a repo point the gate at records it authored.
gate_trusted_data_dir_to() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf -v "$1" '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
}
gate_trusted_data_dir() {
  local __gate_out
  gate_trusted_data_dir_to __gate_out || return 1
  printf '%s' "$__gate_out"
}

gate_arm_record_path_to() {
  local id="$2" dir
  [[ "$id" =~ $GATE_ARM_ID_RE ]] || return 1
  gate_trusted_data_dir_to dir || return 1
  printf -v "$1" '%s/lane-arms/%s' "$dir" "$id"
}
gate_arm_record_path() {
  local __gate_out
  gate_arm_record_path_to __gate_out "$1" || return 1
  printf '%s' "$__gate_out"
}

# The sidecar that binds an arm record to exactly one session: the gate creates
# it exclusively to claim a record, the arm helper clears it so a re-armed id
# starts unclaimed. One spelling so those two can never diverge. It sits beside
# the record, inside lane-arms/, so the helper's own TTL sweep retires it too.
gate_arm_claim_path_to() {
  local rec
  gate_arm_record_path_to rec "$2" || return 1
  printf -v "$1" '%s.claim' "$rec"
}
gate_arm_claim_path() {
  local __gate_out
  gate_arm_claim_path_to __gate_out "$1" || return 1
  printf '%s' "$__gate_out"
}

# The user settings file that carries pluginConfigs, derived from the anchor.
gate_user_settings_file_to() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf -v "$1" '%s/settings.json' "$GATE_CONFIG_ROOT"
}
gate_user_settings_file() {
  local __gate_out
  gate_user_settings_file_to __gate_out || return 1
  printf '%s' "$__gate_out"
}

# --- Managed settings ---------------------------------------------------------
# Fixed per-platform paths (settings docs), primary file first, then the
# `managed-settings.d/` drop-ins in glob (sorted) order — later files override
# earlier ones in gate_managed_options_to, mirroring Claude Code's merge. Yields
# nothing on an unrecognized platform. Platform comes from `uname -s`, never
# `$OSTYPE` (see the header): the exemplar killswitch_config.py keys on
# sys.platform, and this is the bash equivalent.
# Server-managed settings (code.claude.com/docs/en/server-managed-settings) are
# deliberately excluded: their only on-disk artifact is the user-writable cache
# `~/.claude/remote-settings.json`, which fails this list's trust test —
# root-owned paths a repo cannot forge — and the page itself calls the channel
# "a client-side control, not a security boundary".
#
# gate_managed_settings_files_load fills the GATE_MANAGED_FILES array in THIS
# shell and marks it loaded; the print form below re-derives the list on every
# call. The `uname -s` it runs is the one process the gate's interactive
# default path pays, so a caller that needs the list twice in one run (the
# gate's payload-free pre-filter, then its option resolution) loads it once and
# gate_managed_options_to reuses the loaded list rather than asking the kernel
# a second time for an answer that cannot have changed.
GATE_MANAGED_FILES=()
GATE_MANAGED_FILES_LOADED=0
gate_managed_settings_files_load() {
  local primary platform=""
  GATE_MANAGED_FILES=()
  GATE_MANAGED_FILES_LOADED=1
  # Redirect on the group, not inside the substitution (see
  # gate_resolve_plugin_name): one process for uname, not two.
  { platform=$(uname -s); } 2>/dev/null || platform=""
  case "$platform" in
  Darwin) primary="/Library/Application Support/ClaudeCode/managed-settings.json" ;;
  MINGW* | MSYS* | CYGWIN*) primary="C:/Program Files/ClaudeCode/managed-settings.json" ;;
  Linux) primary="/etc/claude-code/managed-settings.json" ;;
  *) return 0 ;;
  esac
  # Defense in depth: a managed path MUST be absolute (POSIX /… or a Windows
  # drive). A relative value would resolve against the hook's cwd — the watched
  # checkout — turning the highest-precedence scope into a repo-plantable file.
  case "$primary" in
  /* | [A-Za-z]:[/\\]*) ;;
  *) return 0 ;;
  esac
  [[ -f "$primary" ]] && GATE_MANAGED_FILES+=("$primary")
  local dropin="${primary%/*}/managed-settings.d" f
  if [[ -d "$dropin" ]]; then
    for f in "$dropin"/*.json; do
      [[ -f "$f" ]] && GATE_MANAGED_FILES+=("$f")
    done
  fi
  return 0
}
gate_managed_settings_files() {
  local f
  gate_managed_settings_files_load
  for f in ${GATE_MANAGED_FILES[@]+"${GATE_MANAGED_FILES[@]}"}; do
    printf '%s\n' "$f"
  done
  return 0
}

# --- Option reads -------------------------------------------------------------
# Read the configured value of pluginConfigs[<this plugin>].options[<key>]
# from one settings file for EVERY key asked for, in ONE jq process: a boolean
# as true/false, a string as-is (including the empty string). Results land in
# GATE_FILE_OPT_HAVE / GATE_FILE_OPT_VALUE, index-parallel to the keys: HAVE is
# 1 where the file configures the key and 0 where it contributes no verdict —
# no entry, JSON null, or a non-boolean/string type. Returns 1, with every HAVE
# at 0, when the file contributes no verdict for any key: absent file,
# unparsable JSON, no entry at all.
#
# One pass, not one per key, because the gate resolves three keys per stop and
# a jq process is the unit of cost on the host this gate is tuned for. The
# per-key verdicts are the same as three single-key passes would give: the
# entry selection does not depend on the key, and the one jq error the filter
# can raise (`.value.options` holding a non-object) is raised for every key
# alike, so a file either answers for all keys or for none — exactly as before.
#
# An anchored install matches the EXACT marketplace-qualified id, as the
# channel-F exemplar does, so another marketplace's entry cannot mask this
# install's; an unanchored one has no qualifier to match and falls back to the
# manifest name, accepting a bare or any qualified key (last wins). Only
# managed settings ever reach the name path — gate_user_settings_file has no
# location to offer without the anchor.
# The file is opened by bash (`< file`), not by jq: a native jq on Windows
# cannot open an MSYS-style path, while a shell redirection always can.
#
# Values travel NUL-separated through a process substitution (a `$( )` capture
# would drop the separators): a string option may carry a newline, so no
# printable delimiter is safe, and a value cannot itself carry a NUL the way a
# bash variable cannot. The separator is built with `[0] | implode` so the jq
# program text holds no NUL byte. The redirections sit on the group around the
# loop, so jq is exec'd straight from the substitution's fork: one process.
# Trailing newlines are removed from each value as the former `$(jq -r …)`
# capture removed them, so a value reads the same on either path.
#   gate_settings_options_to <file> <key>...
# shellcheck disable=SC2034 # result arrays are consumed by the sourcing hook
gate_settings_options_to() {
  local file="$1"
  shift
  GATE_FILE_OPT_HAVE=()
  GATE_FILE_OPT_VALUE=()
  local i
  for ((i = 0; i < $#; i++)); do
    GATE_FILE_OPT_HAVE[i]=0
    GATE_FILE_OPT_VALUE[i]=""
  done
  (($#)) || return 1
  [[ -f "$file" ]] || return 1
  [[ -n "$GATE_PLUGIN_ID" || -n "$GATE_PLUGIN_NAME" ]] || return 1
  local keys="" k
  for k in "$@"; do
    # The key list is a JSON array literal built here, so only identifier-shaped
    # keys are accepted; every caller passes the fixed lane_stop_gate_* names.
    [[ "$k" =~ ^[A-Za-z0-9_]+$ ]] || return 1
    keys+="${keys:+,}\"$k\""
  done
  local -a recs=()
  local rec
  {
    while IFS= read -r -d '' rec; do
      while [[ "$rec" == *$'\n' ]]; do rec="${rec%$'\n'}"; done
      recs+=("$rec")
    done < <(jq -j --arg id "$GATE_PLUGIN_ID" --arg n "$GATE_PLUGIN_NAME" --argjson keys "[$keys]" '
      [ (.pluginConfigs // {}) | to_entries[]
        | select(if $id != "" then .key == $id
                 else .key == $n or (.key | startswith($n + "@")) end)
        | .value.options ] as $opts
      | $keys[] as $k
      | ([ $opts[] | .[$k]
           | if type == "boolean" then (if . then "v:true" else "v:false" end)
             elif type == "string" then "v:" + .
             else empty end ] | last // "-")
      | (., ([0] | implode))')
  } <"$file" 2>/dev/null
  ((${#recs[@]} == $#)) || return 1
  local have=1
  for ((i = 0; i < $#; i++)); do
    [[ "${recs[i]}" == v:* ]] || continue
    GATE_FILE_OPT_HAVE[i]=1
    GATE_FILE_OPT_VALUE[i]="${recs[i]#v:}"
    have=0
  done
  return "$have"
}

# Print form, one key: the value, or return 1 when the file contributes no
# verdict for it.
gate_settings_option() {
  gate_settings_options_to "$1" "$2" || return 1
  ((GATE_FILE_OPT_HAVE[0])) || return 1
  printf '%s' "${GATE_FILE_OPT_VALUE[0]}"
}

# The managed-scope verdict for every key asked for, in GATE_MANAGED_OPT_HAVE /
# GATE_MANAGED_OPT_VALUE (index-parallel to the keys); return 1 when managed
# configures none of them. Later files override earlier ones (drop-ins over the
# primary), key by key. Reuses a GATE_MANAGED_FILES list the caller already
# loaded this run, else loads one.
#   gate_managed_options_to <key>...
# shellcheck disable=SC2034 # result arrays are consumed by the sourcing hook
gate_managed_options_to() {
  GATE_MANAGED_OPT_HAVE=()
  GATE_MANAGED_OPT_VALUE=()
  local i f have=1
  for ((i = 0; i < $#; i++)); do
    GATE_MANAGED_OPT_HAVE[i]=0
    GATE_MANAGED_OPT_VALUE[i]=""
  done
  ((GATE_MANAGED_FILES_LOADED)) || gate_managed_settings_files_load
  for f in ${GATE_MANAGED_FILES[@]+"${GATE_MANAGED_FILES[@]}"}; do
    [[ -n "$f" ]] || continue
    gate_settings_options_to "$f" "$@" || continue
    for ((i = 0; i < $#; i++)); do
      ((GATE_FILE_OPT_HAVE[i])) || continue
      GATE_MANAGED_OPT_HAVE[i]=1
      GATE_MANAGED_OPT_VALUE[i]="${GATE_FILE_OPT_VALUE[i]}"
      have=0
    done
  done
  return "$have"
}

# Print form, one key: the managed verdict, or return 1 when managed configures
# none. Derives the file list fresh, as it always did.
gate_managed_option() {
  GATE_MANAGED_FILES_LOADED=0
  gate_managed_options_to "$1" || return 1
  ((GATE_MANAGED_OPT_HAVE[0])) || return 1
  printf '%s' "${GATE_MANAGED_OPT_VALUE[0]}"
}

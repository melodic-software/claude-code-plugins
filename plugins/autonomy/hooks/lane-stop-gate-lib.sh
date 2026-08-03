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
  name=$(jq -r '.name | select(type == "string")' <"$manifest" 2>/dev/null) || return 1
  [[ -n "$name" ]] || return 1
  GATE_PLUGIN_NAME="$name"
}

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
gate_data_dir() {
  if [[ -n "$GATE_CONFIG_ROOT" ]]; then
    printf '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
  else
    printf '%s' "${CLAUDE_PLUGIN_DATA:-}"
  fi
}

# Install-derived data directory ONLY — no env fallback. Fails when unanchored.
# Arm records live here because a record can GRANT gate behavior: an env-derived
# store would let a repo point the gate at records it authored.
gate_trusted_data_dir() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf '%s/plugins/data/%s' "$GATE_CONFIG_ROOT" "$GATE_PLUGIN_ID_SAFE"
}

gate_arm_record_path() {
  local id="$1" dir
  [[ "$id" =~ $GATE_ARM_ID_RE ]] || return 1
  dir=$(gate_trusted_data_dir) || return 1
  printf '%s/lane-arms/%s' "$dir" "$id"
}

# The user settings file that carries pluginConfigs, derived from the anchor.
gate_user_settings_file() {
  [[ -n "$GATE_CONFIG_ROOT" ]] || return 1
  printf '%s/settings.json' "$GATE_CONFIG_ROOT"
}

# --- Managed settings ---------------------------------------------------------
# Fixed per-platform paths (settings docs), primary file first, then the
# `managed-settings.d/` drop-ins in glob (sorted) order — later files override
# earlier ones in gate_managed_option, mirroring Claude Code's merge. Prints
# nothing on an unrecognized platform. Platform comes from `uname -s`, never
# `$OSTYPE` (see the header): the exemplar killswitch_config.py keys on
# sys.platform, and this is the bash equivalent.
gate_managed_settings_files() {
  local primary
  case "$(uname -s 2>/dev/null)" in
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
  [[ -f "$primary" ]] && printf '%s\n' "$primary"
  local dropin="${primary%/*}/managed-settings.d" f
  if [[ -d "$dropin" ]]; then
    for f in "$dropin"/*.json; do
      [[ -f "$f" ]] && printf '%s\n' "$f"
    done
  fi
  return 0
}

# --- Option reads -------------------------------------------------------------
# Print the configured value of pluginConfigs[<this plugin>].options[<key>]
# from one settings file: a boolean as true/false, a string as-is (including
# the empty string). Returns 1 when the file contributes no verdict for the key
# — absent file, unparsable JSON, no entry, JSON null, or a non-boolean/string
# type. An anchored install matches the EXACT marketplace-qualified id, as the
# channel-F exemplar does, so another marketplace's entry cannot mask this
# install's; an unanchored one has no qualifier to match and falls back to the
# manifest name, accepting a bare or any qualified key (last wins). Only
# managed settings ever reach the name path — gate_user_settings_file has no
# location to offer without the anchor.
# The file is opened by bash (`< file`), not by jq: a native jq on Windows
# cannot open an MSYS-style path, while a shell redirection always can.
gate_settings_option() {
  local file="$1" key="$2" out
  [[ -f "$file" ]] || return 1
  [[ -n "$GATE_PLUGIN_ID" || -n "$GATE_PLUGIN_NAME" ]] || return 1
  out=$(jq -r --arg id "$GATE_PLUGIN_ID" --arg n "$GATE_PLUGIN_NAME" --arg k "$key" '
    [ (.pluginConfigs // {}) | to_entries[]
      | select(if $id != "" then .key == $id
               else .key == $n or (.key | startswith($n + "@")) end)
      | .value.options[$k]
      | if type == "boolean" then (if . then "v:true" else "v:false" end)
        elif type == "string" then "v:" + .
        else empty end ] | last // empty' <"$file" 2>/dev/null) || return 1
  [[ "$out" == v:* ]] || return 1
  printf '%s' "${out#v:}"
}

# The managed-scope verdict for a key, or return 1 when managed configures
# none. Later files override earlier ones (drop-ins over the primary).
gate_managed_option() {
  local key="$1" f v verdict="" have=1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    if v=$(gate_settings_option "$f" "$key"); then
      verdict="$v"
      have=0
    fi
  done < <(gate_managed_settings_files)
  ((have == 0)) || return 1
  printf '%s' "$verdict"
}

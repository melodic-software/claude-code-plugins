#!/usr/bin/env bash
# PreToolUse hook: classify a Bash or PowerShell call against this machine's
# identity domains.
#
# An identity domain is a set of trees one identity owns, with its own git
# author, gh and az config directories and remote owners. THE MAP names each
# domain's roots and markers; this guard classifies the session cwd into a
# domain or neutral, finds the domains a command names, and holds gh and az to
# the cwd's domain's config directories.
#
# THE MAP. ${CLAUDE_PLUGIN_DATA}/identity-domains.json, machine-local and never
# tracked. Its keys follow docs/conventions/plugin-option-naming:
#
#   {
#     "domains": {
#       "<name>": {
#         "roots": { "linux": ["<abs>"], "macos": ["<abs>"], "windows": ["<abs>"] },
#         "owners": ["<owner>"],
#         "identity_markers": ["<text>"],
#         "gh_config_dir": "<dir>",
#         "az_config_dir": "<dir>"
#       }
#     },
#     "identity_files": ["<path>"],
#     "shared_exceptions": ["<path>"],
#     "messages": { "<key>": "<text>" }
#   }
#
# `domains` and each domain's `roots` are required; every other key may be left
# out. A domain name is letters, digits, `.`, `_` and `-`; every value is a
# non-empty one-line string; a root is absolute and below a filesystem root
# (`/x`, and on Windows also `C:/x`, `C:\x` or `/c/x`). An unknown key or any
# other shape makes the map malformed. Only this host's roots (OSTYPE: msys,
# cygwin and win32 read `windows`, darwin `macos`, every other host `linux`)
# and the markers, and the config directories by the rule below, are used here;
# the other keys are validated and kept for the rules that read them.
#
# THE CONFIG DIRECTORY RULE. gh reads its configuration from GH_CONFIG_DIR and
# az from AZURE_CONFIG_DIR, each falling back to a default directory when the
# variable is unset. In a domain whose map entry names a tool's directory
# (`gh_config_dir`, `az_config_dir`), a call of that tool is denied unless the
# variable it gets is that directory. In a domain that names none for the tool,
# its default domain, a call is denied when the variable names another
# domain's directory. A neutral cwd asks nothing of either tool, and
# `gh --version` or `az --version` alone is never denied. The variable a call
# gets is, in order: an assignment on its own command (`GH_CONFIG_DIR=<dir> gh`,
# `env GH_CONFIG_DIR=<dir> gh`, `env -u` and `env -i` too); an earlier
# `export`, assignment or `unset` in the same command, or a PowerShell
# `$env:GH_CONFIG_DIR = '<dir>'`; else the hook's own environment, which the
# tool's shell inherits. Directories are compared as paths, with a leading `~`,
# `$HOME` or `%USERPROFILE%` read as HOME. On the Bash tool the tool must sit at
# the command position, after any assignments and the env, command, exec, nohup
# or time launchers; on PowerShell it must be the first word of a statement,
# after an optional `&`.
#
# WHAT A CALL COSTS. Each step leaves at the first that settles the call:
#   1. the kill switch, before any source;
#   2. no map file: exit 0, having read and parsed nothing;
#   3. the map, compiled by jq into CACHE (identity-domains.cache beside it)
#      once per change of its bytes and read back with builtins otherwise, so a
#      steady call starts no process; a malformed map is reported to the user
#      once per session and the call is allowed unchecked;
#   4. the cwd, classified into the domain whose root holds it (the longest
#      root wins), else neutral;
#   5. the prefilter: the command text, lowercased with `\` read as `/`, is
#      tested for each root and marker, and, when the config directory rule
#      asks anything of the cwd's domain, for the word gh or az. A command that
#      names none leaves here, before it is parsed;
#   6. the parse: on the Bash tool hook::bash_parse_segments, whose argv words
#      and redirection targets are tested the same way and whose segments the
#      config directory rule reads; on PowerShell the text as a whole, and its
#      statements for that rule.
#
# A text NAMES a root or marker when it holds it with no letter, digit, `.`,
# `_` or `-` right before or after it: the root /x/work names neither
# /x/workshop nor /y/x/work. A root is also named in its MSYS form on Windows
# (`/c/x` for `C:/x`) and, below $HOME, after `~`, `$HOME`, `${HOME}`,
# `$env:HOME`, `$env:USERPROFILE` or `%USERPROFILE%`. A path below two nested
# roots names the domain of the inner one only; every other root and every
# marker a text names counts. Text is compared in any case, so on Linux a path
# that differs from a root only in case names it too.
#
# Steps 4 and 6 feed the telemetry envelope: `cwd` is domain or neutral, and
# `form` is prefilter-miss, not-named, own-domain (the cwd's domain alone is
# named), other-domain, map-malformed (whose cwd is always neutral), or, for a
# call the config directory rule denies, config-dir-missing or
# config-dir-foreign with status `blocked`. The envelope names no domain and no
# directory; `subject` is the command word, as in every guard's.
#
# DECLARED GAPS. The guard reads command text: a deterrent, not a sandbox.
#   - a computed path: a variable, a substitution, or a path spelled in pieces
#     (`"/x/wo"rk`); a config directory given that way is not judged
#   - a gh or az the config directory rule cannot see at a command position: a
#     launcher other than those it reads (`sudo`, `timeout`, `env -S`), a
#     PowerShell call that is not the first word of its statement, and a
#     variable set by a means it does not read (`declare -x`, `Remove-Item
#     env:`)
#   - a script run by name, whose own commands the guard never sees, and a
#     heredoc body, which the parse skips even when a shell runs it
#     (`bash <<'EOF'`)
#   - a path relative to the cwd (`../other`), and a symlink into a root
#   - on macOS, a cwd spelled in another case than its root, which reads as
#     neutral
#
# TEST HOOK. GUARDRAILS_CROSS_DOMAIN_TRACE=1 writes one stderr line per step a
# call reaches (`block-cross-domain: trace <step>`).
#
# Kill switch: block_cross_domain_enabled userConfig option.
#
# Every exit is 0, an internal error included: a deny is a PreToolUse
# `permissionDecision` on stdout.

set -uo pipefail

# Kill switch FIRST, above every source: a disabled guard must not pay to parse
# hook-utils.sh before finding out it is off (scripts/check-killswitch-hoist.sh).
[[ "${CLAUDE_PLUGIN_OPTION_BLOCK_CROSS_DOMAIN_ENABLED:-true}" == "true" ]] || exit 0

_HOOK_SELF="${BASH_SOURCE[0]%/*}"
[[ "$_HOOK_SELF" == "${BASH_SOURCE[0]}" ]] && _HOOK_SELF=.
# shellcheck source=abort-boundary.sh
source "$_HOOK_SELF/abort-boundary.sh"
# Could-not-run posture: fail-open with a "guard did not run" notice. 0 is the
# only chosen status: this guard never blocks by exit code.
guard::abort_boundary block-cross-domain PreToolUse open 0

# No map, nothing to do: leave before the library is parsed.
BCD_MAP="${CLAUDE_PLUGIN_DATA:-}"
[[ -n "$BCD_MAP" ]] || exit 0
BCD_MAP="${BCD_MAP%/}/identity-domains.json"
[[ -f "$BCD_MAP" ]] || exit 0

# shellcheck source=hook-utils.sh
source "$_HOOK_SELF/hook-utils.sh" || exit 70 # not a chosen status: the boundary reports it

start=${EPOCHREALTIME:-}

# Every stdin failure (empty, stalled, not JSON, cut short) allows the call.
hook::buffer_stdin_to INPUT || exit 0

# The map is compiled by jq. Without it: one notice per session, then allow.
hook::require jq PreToolUse guardrails "$INPUT"

jq_rc=0
hook::jq_fields "$INPUT" '.tool_input.command' '.tool_name' '.cwd' || jq_rc=$?
((jq_rc == 0 && HOOK_JQ_FIELDS_NUL == 0)) || exit 0
COMMAND="${HOOK_JQ_FIELDS[0]}"
[[ -n "$COMMAND" ]] || exit 0
TOOL_NAME="${HOOK_JQ_FIELDS[1]:-Bash}"
BCD_CWD_RAW="${HOOK_JQ_FIELDS[2]}"

case "${OSTYPE:-}" in
msys* | cygwin* | win32) BCD_OS=windows ;;
darwin*) BCD_OS=macos ;;
*) BCD_OS=linux ;;
esac

# What the compiler below writes. A change to the jq program or to how the
# records are read changes it, so a cache an older guard wrote is compiled again.
BCD_FORMAT=2
BCD_CACHE="${BCD_MAP%.json}.cache"
BCD_TAB=$'\t'
BCD_CWD_DOMAIN=""
BCD_RECORDS=()
BCD_ROOT=()
BCD_ROOT_DOMAIN=()
BCD_NEEDLE=()
BCD_NEEDLE_DOMAIN=()
BCD_NEEDLE_ROOT=()
BCD_NAMED=" "
BCD_SUBJECT=""

# The config directory rule, per tool index (0 gh, 1 az): the variable naming
# its directory; the `gh` and `az` records; the cwd's domain's directory as
# compared and as the map spells it; in a default domain, every other domain's
# directory, one per line; and the variable as the command has set it so far,
# with 1 in BCD_EXP once it is in the environment the tool gets.
BCD_TOOL_VAR=(GH_CONFIG_DIR AZURE_CONFIG_DIR)
BCD_CFG_KIND=()
BCD_CFG_DOM=()
BCD_CFG_DIR=()
BCD_NEED=("" "")
BCD_NEED_TEXT=("" "")
BCD_FOREIGN=("" "")
BCD_SH=("" "")
BCD_EXP=(0 0)
BCD_CFG_ARMED=0
BCD_CFG_HIT=0
BCD_DENY=""
BCD_DENY_FORM=""
BCD_ASSIGN_RE='^([A-Za-z_][A-Za-z0-9_]*)=(.*)$'
BCD_PS_ENV_RE='^\$[Ee][Nn][Vv]:([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=[[:space:]]*(.*)$'
BCD_TOOL_RE='(^|[^a-z0-9_-])(gh|az)([^a-z0-9_-]|$)'

# The compiler: the map's raw text in, one line per record out: `marker`
# records, then this host's `root` records longest first, then `gh` and `az`
# records (`<kind><TAB><domain><TAB><value>`), or one `invalid<TAB><reason>` line for a
# map it rejects. The whole map is validated before any record is written, so a
# rejected map yields no partial set. The reason names keys, never values.
# shellcheck disable=SC2016  # a jq program: its $names are jq variables
BCD_COMPILE='
def fail($m): error({bcd: $m});
def oneline: explode | map(if . < 32 or . == 127 then 63 else . end) | implode;
def line($what):
  if type == "string" and length > 0 and (explode | all(. >= 32 and . != 127)) then .
  else fail("\($what) is not a non-empty one-line string") end;
def list($what):
  if type != "array" then fail("\($what) is not an array")
  else range(length) as $i | .[$i] | line("\($what)[\($i)]") end;
def object($what): if type == "object" then . else fail("\($what) is not an object") end;
def only($what; $allowed):
  object($what)
  | if (keys - $allowed) != [] then fail("\($what) has an unknown key, \((keys - $allowed)[0])") else . end;
def optional($key; f): if has($key) then .[$key] | f else empty end;
def absolute($os):
  if $os == "windows"
  then test("^[A-Za-z]:[\\\\/]+[^\\\\/]") or (test("^/[^/]") and (test("^/[A-Za-z][\\\\/]*$") | not))
  else test("^/[^/]") end;
def domain($d; $os):
  if ($d | test("\\A[A-Za-z0-9_.-]+\\z")) | not
  then fail("a domain name holds a character other than a letter, digit, dot, underscore or hyphen")
  else . end
  | only("domains.\($d)"; ["roots", "owners", "identity_markers", "gh_config_dir", "az_config_dir"])
  | if has("roots") | not then fail("domains.\($d) has no roots") else . end
  | [optional("owners"; list("domains.\($d).owners"))] as $owners
  | [optional("gh_config_dir"; line("domains.\($d).gh_config_dir"))] as $gh
  | [optional("az_config_dir"; line("domains.\($d).az_config_dir"))] as $az
  | [optional("identity_markers"; list("domains.\($d).identity_markers"))] as $markers
  | [.roots | only("domains.\($d).roots"; ["linux", "macos", "windows"])
      | to_entries[] | .key as $o | .value
      | list("domains.\($d).roots.\($o)")
      | if absolute($o) then select($o == $os)
        else fail("domains.\($d).roots.\($o) holds a path that is not absolute below a filesystem root") end] as $roots
  | ($roots[] | {kind: "root", d: $d, v: .}), ($markers[] | {kind: "marker", d: $d, v: .}),
    ($gh[] | {kind: "gh", d: $d, v: .}), ($az[] | {kind: "az", d: $d, v: .});
def compile($os):
  only("the map"; ["domains", "identity_files", "shared_exceptions", "messages"])
  | if has("domains") | not then fail("the map has no domains") else . end
  | [optional("identity_files"; list("identity_files"))] as $files
  | [optional("shared_exceptions"; list("shared_exceptions"))] as $shared
  | [optional("messages"; object("messages") | to_entries[] | .key as $k | .value | line("messages.\($k)"))] as $messages
  | .domains | object("domains")
  | [to_entries[] | .key as $d | .value | domain($d; $os)]
  | map(select(.kind == "marker"))
    + (map(select(.kind == "root")) | sort_by(.v | sub("[\\\\/]+$"; "") | length) | reverse)
    + map(select(.kind == "gh" or .kind == "az"))
  | map("\(.kind)\t\(.d)\t\(.v)");
(try [fromjson] catch null) as $doc
| if $doc == null then ["invalid\tit is not valid JSON"]
  else try ($doc[0] | compile($os))
    catch (if type == "object" and has("bcd") then ["invalid\t" + (.bcd | oneline | .[0:300])]
      else ["invalid\tit cannot be read"] end)
  end
| .[]
'

bcd::trace() {
  [[ "${GUARDRAILS_CROSS_DOMAIN_TRACE:-}" == 1 ]] || return 0
  printf 'block-cross-domain: trace %s\n' "$1" >&2
}

bcd::emit_tel() { # <form> [status, default ok]
  [[ -n "$start" ]] || return 0
  hook::telemetry_enabled || return 0
  local subject data cwd=neutral
  [[ -n "$BCD_CWD_DOMAIN" ]] && cwd=domain
  hook::extract_bash_subject_to subject "$TOOL_NAME" "$COMMAND"
  hook::json_str_object_to data tool "$TOOL_NAME" subject "$subject" form "$1" cwd "$cwd"
  hook::emit_telemetry "block-cross-domain" "PreToolUse" "${2:-ok}" "$start" "$data" "${CLAUDE_PROJECT_DIR:-}"
}

# bcd::malformed <reason>: tell the user once per session, then allow.
# shellcheck disable=SC2154  # HOOK_NOTICE_TO_USER is set by hook::notice_once
bcd::malformed() {
  bcd::emit_tel map-malformed
  if hook::notice_once guardrails-cross-domain-map "$INPUT" && [[ "$HOOK_NOTICE_TO_USER" == 1 ]]; then
    hook::emit_channels PreToolUse "" "guardrails block-cross-domain: the domain map $BCD_MAP is malformed ($1), so this guard checks nothing. Fix the file, or turn the guard off with block_cross_domain_enabled."
  fi
  exit 0
}

# bcd::compile: run the compiler over BCD_MAP_RAW into BCD_RECORDS and store
# them in CACHE, the key last, so a cache cut short ends in a partial key and is
# compiled again. A jq that fails is not cached. Two processes: jq, then the mv
# that puts the cache in place whole.
bcd::compile() {
  local out rc=0 tmp
  bcd::trace map-compile
  out=$(exec jq -r -R -s --arg os "$BCD_OS" "$BCD_COMPILE" 2>/dev/null <<<"$BCD_MAP_RAW") || rc=$?
  if ((rc != 0)); then
    BCD_RECORDS=("invalid${BCD_TAB}jq exited $rc reading it")
    return 0
  fi
  # The Windows jq build writes CRLF.
  out=${out//$'\r'/}
  BCD_RECORDS=()
  [[ -n "$out" ]] && mapfile -t BCD_RECORDS <<<"$out"
  tmp="$BCD_CACHE.$$.$RANDOM"
  if printf '%s\0' ${BCD_RECORDS[@]+"${BCD_RECORDS[@]}"} "$BCD_KEY" 2>/dev/null >"$tmp"; then
    mv -f -- "$tmp" "$BCD_CACHE" 2>/dev/null || rm -f -- "$tmp" 2>/dev/null
  fi
  return 0
}

# bcd::load: BCD_RECORDS for the map as it is now, from CACHE when its key is
# this map's bytes under this format and host, else from the compiler.
bcd::load() {
  local -a cache=()
  BCD_MAP_RAW=""
  if [[ ! -r "$BCD_MAP" ]]; then
    BCD_RECORDS=("invalid${BCD_TAB}it cannot be read")
    return 0
  fi
  IFS= read -r -d '' BCD_MAP_RAW 2>/dev/null <"$BCD_MAP"
  if ((${#BCD_MAP_RAW} > 65536)); then
    BCD_RECORDS=("invalid${BCD_TAB}it is over 64 KiB")
    return 0
  fi
  BCD_KEY="block-cross-domain cache $BCD_FORMAT $BCD_OS"$'\n'"$BCD_MAP_RAW"
  [[ -f "$BCD_CACHE" ]] && mapfile -d '' -t cache 2>/dev/null <"$BCD_CACHE"
  if ((${#cache[@]})) && [[ "${cache[-1]}" == "$BCD_KEY" ]]; then
    bcd::trace map-cached
    BCD_RECORDS=("${cache[@]:0:${#cache[@]}-1}")
    return 0
  fi
  bcd::compile
}

# bcd::norm_to <var> <path>: the form a cwd and a root are compared in: the
# library's normalizer (`\` as `/`; on Windows the drive folded to `C:` and the
# rest lowercased), runs of `/` as one, no trailing `/`.
bcd::norm_to() {
  local __bcd_p __bcd_s='/' __bcd_d='//'
  hook::normalize_path_to __bcd_p "$2"
  while [[ "$__bcd_p" == *//* ]]; do __bcd_p=${__bcd_p//"$__bcd_d"/"$__bcd_s"}; done
  while [[ "$__bcd_p" == ?*/ ]]; do __bcd_p=${__bcd_p%/}; done
  printf -v "$1" '%s' "$__bcd_p"
}

# bcd::fold_to <var> <text>: the form the prefilter and the parse test in:
# lowercased, `\` as `/`, runs of `/` as one, no trailing `/`.
bcd::fold_to() {
  local __bcd_t="${2,,}" __bcd_s='/' __bcd_d='//'
  __bcd_t=${__bcd_t//\\//}
  while [[ "$__bcd_t" == *//* ]]; do __bcd_t=${__bcd_t//"$__bcd_d"/"$__bcd_s"}; done
  while [[ "$__bcd_t" == ?*/ ]]; do __bcd_t=${__bcd_t%/}; done
  printf -v "$1" '%s' "$__bcd_t"
}

bcd::add_needle() { # <domain> <folded text> <1 for a root, 0 for a marker>
  [[ -n "$2" ]] || return 0
  BCD_NEEDLE+=("$2")
  BCD_NEEDLE_DOMAIN+=("$1")
  BCD_NEEDLE_ROOT+=("$3")
}

# bcd::add_root <domain> <root as the map spells it>: the root for the cwd and
# every spelling of it a command can name.
bcd::add_root() {
  local c n rest p
  bcd::norm_to c "$2"
  BCD_ROOT+=("$c")
  BCD_ROOT_DOMAIN+=("$1")
  bcd::fold_to n "$2"
  bcd::add_needle "$1" "$n" 1
  if [[ "$n" =~ ^([a-z]):(/.*)$ ]]; then
    bcd::add_needle "$1" "/${BASH_REMATCH[1]}${BASH_REMATCH[2]}" 1
  elif [[ "$BCD_OS" == windows && "$n" =~ ^/([a-z])(/.*)$ ]]; then
    bcd::add_needle "$1" "${BASH_REMATCH[1]}:${BASH_REMATCH[2]}" 1
  fi
  if [[ -n "$BCD_HOME" && "$c" == "$BCD_HOME"/?* ]]; then
    bcd::fold_to rest "${c#"$BCD_HOME"}"
    # shellcheck disable=SC2016,SC2088  # spellings matched as text, never expanded
    for p in '~' '$home' '${home}' '$env:home' '${env:home}' '$env:userprofile' '${env:userprofile}' '%userprofile%'; do
      bcd::add_needle "$1" "$p$rest" 1
    done
  fi
}

bcd::named() { [[ "$BCD_NAMED" == *" $1 "* ]] || BCD_NAMED+="$1 "; }

# bcd::names <folded text>: add to BCD_NAMED each domain whose marker or root
# the text names. The needles come markers first, then roots longest first, and
# a root that names its domain spends its text: an outer root that text holds
# (a nested pair) is not named by it, while one named elsewhere in the text is.
bcd::names() {
  local t="$1" n i
  for ((i = 0; i < ${#BCD_NEEDLE[@]}; i++)); do
    n=${BCD_NEEDLE[i]}
    [[ "$t" == *"$n"* ]] || continue
    case "$t" in
    "$n" | "$n"[!a-z0-9._-]* | *[!a-z0-9._-]"$n" | *[!a-z0-9._-]"$n"[!a-z0-9._-]*) ;;
    *) continue ;;
    esac
    bcd::named "${BCD_NEEDLE_DOMAIN[i]}"
    ((BCD_NEEDLE_ROOT[i])) && t=${t//"$n"/ }
  done
  return 0
}

# The parse callback: every argv word and redirection target of one segment.
# shellcheck disable=SC2329  # invoked by hook::bash_parse_segments
bcd::segment() {
  local __bcd_w __bcd_f
  for __bcd_w in "$@" ${HOOK_SEG_REDIR_TARGET[@]+"${HOOK_SEG_REDIR_TARGET[@]}"}; do
    bcd::fold_to __bcd_f "$__bcd_w"
    bcd::names "$__bcd_f"
  done
  ((BCD_CFG_HIT)) && bcd::config_segment "$@"
  return 0
}

bcd::classify_cwd() {
  local cwd r i best=0
  [[ -n "$BCD_CWD_RAW" ]] || return 0
  bcd::norm_to cwd "$BCD_CWD_RAW"
  for ((i = 0; i < ${#BCD_ROOT[@]}; i++)); do
    r=${BCD_ROOT[i]}
    if ((${#r} > best)) && [[ "$cwd" == "$r" || "$cwd" == "$r"/* ]]; then
      best=${#r}
      BCD_CWD_DOMAIN=${BCD_ROOT_DOMAIN[i]}
    fi
  done
}

# bcd::dir_to <var> <directory as written>: the form a config directory is
# compared in: a leading HOME spelling read as $HOME, then bcd::norm_to.
bcd::dir_to() {
  local __bcd_v="$2" __bcd_l="${2,,}" __bcd_p
  if [[ -n "${HOME:-}" ]]; then
    # shellcheck disable=SC2016  # spellings matched as text, never expanded
    for __bcd_p in '~' '$home' '${home}' '$env:home' '${env:home}' '$env:userprofile' '${env:userprofile}' '%userprofile%'; do
      if [[ "$__bcd_l" == "$__bcd_p" || "$__bcd_l" == "$__bcd_p"[/\\]* ]]; then
        __bcd_v="$HOME${__bcd_v:${#__bcd_p}}"
        break
      fi
    done
  fi
  bcd::norm_to "$1" "$__bcd_v"
}

# bcd::arm_config: what the config directory rule asks of each tool in the
# cwd's domain, and the variables as the hook's own environment holds them.
bcd::arm_config() {
  local i t v
  [[ -n "$BCD_CWD_DOMAIN" ]] || return 0
  for ((i = 0; i < ${#BCD_CFG_KIND[@]}; i++)); do
    t=1
    [[ "${BCD_CFG_KIND[i]}" == gh ]] && t=0
    bcd::dir_to v "${BCD_CFG_DIR[i]}"
    if [[ "${BCD_CFG_DOM[i]}" == "$BCD_CWD_DOMAIN" ]]; then
      BCD_NEED[t]=$v
      BCD_NEED_TEXT[t]=${BCD_CFG_DIR[i]}
    else
      BCD_FOREIGN[t]+="$v"$'\n'
    fi
  done
  for t in 0 1; do
    [[ -n "${BCD_NEED[t]}" ]] && BCD_FOREIGN[t]=""
    [[ -n "${BCD_NEED[t]}${BCD_FOREIGN[t]}" ]] && BCD_CFG_ARMED=1
    v=${BCD_TOOL_VAR[t]}
    if [[ -n "${!v+set}" ]]; then
      BCD_SH[t]=${!v}
      BCD_EXP[t]=1
    fi
  done
}

bcd::tool_of_var() { # <var> <variable name>: its tool index, else 1
  case "$2" in
  GH_CONFIG_DIR) printf -v "$1" 0 ;;
  AZURE_CONFIG_DIR) printf -v "$1" 1 ;;
  *) return 1 ;;
  esac
}

# bcd::tool_word_to <var> <command word>: the tool index of gh or az, spelled
# with any directory and a .exe, .cmd or .bat suffix; 1 for any other word.
bcd::tool_word_to() {
  local __bcd_b="${2,,}"
  __bcd_b=${__bcd_b##*[/\\]}
  __bcd_b=${__bcd_b%.exe}
  __bcd_b=${__bcd_b%.cmd}
  __bcd_b=${__bcd_b%.bat}
  case "$__bcd_b" in
  gh) printf -v "$1" 0 ;;
  az) printf -v "$1" 1 ;;
  *) return 1 ;;
  esac
}

bcd::deny() { # <form> <reason>: the first deny is the one reported
  [[ -z "$BCD_DENY" ]] || return 0
  BCD_DENY_FORM=$1
  BCD_DENY=$2
}

# bcd::config_judge <tool index> <directory the call gets, empty when unset>
bcd::config_judge() {
  local t=$1 v="" var=${BCD_TOOL_VAR[$1]} tool=gh
  ((t)) && tool=az
  if [[ -n "$2" ]]; then
    bcd::dir_to v "$2"
    [[ "$v" == *[\$\`]* ]] && return 0 # a computed directory: a declared gap
  fi
  if [[ -n "${BCD_NEED[t]}" ]]; then
    [[ "$v" == "${BCD_NEED[t]}" ]] && return 0
    bcd::deny config-dir-missing "BLOCKED: this directory's identity domain keeps $tool's configuration in its own directory, and this $tool call does not get it. Set $var=${BCD_NEED_TEXT[t]} on the command or in the session environment."
  elif [[ -n "$v" && $'\n'"${BCD_FOREIGN[t]}" == *$'\n'"$v"$'\n'* ]]; then
    bcd::deny config-dir-foreign "BLOCKED: $var names another identity domain's $tool config directory, and this directory's domain uses $tool's default. Drop $var from the command, or unset it in the session environment."
  fi
  return 0
}

# bcd::config_export <export|unset> <word...>: the variables later calls get.
bcd::config_export() {
  local verb=$1 w t
  shift
  for w in "$@"; do
    if [[ "$w" =~ $BCD_ASSIGN_RE ]]; then
      if [[ "$verb" == export ]] && bcd::tool_of_var t "${BASH_REMATCH[1]}"; then
        BCD_SH[t]=${BASH_REMATCH[2]}
        BCD_EXP[t]=1
      fi
    elif bcd::tool_of_var t "$w"; then
      if [[ "$verb" == export ]]; then
        BCD_EXP[t]=1
      else
        BCD_SH[t]=""
        BCD_EXP[t]=0
      fi
    fi
  done
}

# bcd::config_segment <argv...>: the config directory rule on one Bash segment.
bcd::config_segment() {
  local -a w=("$@") val=("" "") given=(0 0)
  local n=$# i=0 t clear=0 v
  while ((i < n)) && [[ "${w[i]}" =~ $BCD_ASSIGN_RE ]]; do
    bcd::tool_of_var t "${BASH_REMATCH[1]}" && val[t]=${BASH_REMATCH[2]} && given[t]=1
    ((i++))
  done
  if ((i == n)); then
    # Assignments alone set shell variables, which reach a later call only
    # when the variable is exported.
    for t in 0 1; do ((given[t])) && BCD_SH[t]=${val[t]}; done
    return 0
  fi
  if [[ "${w[i]}" == export || "${w[i]}" == unset ]]; then
    bcd::config_export "${w[@]:i}"
    return 0
  fi
  while ((i < n)); do
    case "${w[i]}" in
    env)
      ((i++))
      while ((i < n)); do
        case "${w[i]}" in
        -i | - | --ignore-environment)
          clear=1
          given=(0 0)
          ;;
        -u | --unset)
          ((i++))
          ((i < n)) && bcd::tool_of_var t "${w[i]}" && val[t]="" && given[t]=1
          ;;
        --)
          ((i++))
          break
          ;;
        -*) ;;
        *)
          [[ "${w[i]}" =~ $BCD_ASSIGN_RE ]] || break
          bcd::tool_of_var t "${BASH_REMATCH[1]}" && val[t]=${BASH_REMATCH[2]} && given[t]=1
          ;;
        esac
        ((i++))
      done
      ;;
    command | exec | nohup | time)
      ((i++))
      while ((i < n)) && [[ "${w[i]}" == -* ]]; do ((i++)); done
      ;;
    *) break ;;
    esac
  done
  if ((i == n)) || ! bcd::tool_word_to t "${w[i]}"; then return 0; fi
  ((n - i == 2)) && [[ "${w[i + 1]}" == --version ]] && return 0
  v=""
  if ((given[t])); then
    v=${val[t]}
  elif ((!clear && BCD_EXP[t])); then
    v=${BCD_SH[t]}
  fi
  bcd::config_judge "$t" "$v"
}

# bcd::config_ps: the config directory rule on PowerShell text, statement by
# statement (split at `;`, `|`, `{`, `}`, `&&` and newlines): a `$env:`
# assignment, or a call whose first word, after an optional `&`, is gh or az.
bcd::config_ps() {
  local text="$COMMAND" stmt word rest t v
  text=${text//&&/$'\n'}
  text=${text//[;|\{\}]/$'\n'}$'\n'
  while [[ -n "$text" ]]; do
    stmt=${text%%$'\n'*}
    text=${text#*$'\n'}
    stmt=${stmt#"${stmt%%[![:space:]]*}"}
    stmt=${stmt%"${stmt##*[![:space:]]}"}
    if [[ "$stmt" =~ $BCD_PS_ENV_RE ]]; then
      bcd::tool_of_var t "${BASH_REMATCH[1]^^}" || continue
      v=${BASH_REMATCH[2]}
      if ((${#v} >= 2)) && [[ "$v" == \'*\' || "$v" == \"*\" ]]; then v=${v:1:-1}; fi
      [[ "${v,,}" == "\$null" ]] && v=""
      BCD_SH[t]=$v
      BCD_EXP[t]=1
      continue
    fi
    if [[ "$stmt" == '&'* ]]; then
      stmt=${stmt#&}
      stmt=${stmt#"${stmt%%[![:space:]]*}"}
    fi
    case "$stmt" in
    \'* | \"*)
      word=${stmt:1}
      word=${word%%"${stmt:0:1}"*}
      rest=${stmt:${#word}+2}
      ;;
    *)
      word=${stmt%%[[:space:]]*}
      rest=${stmt:${#word}}
      ;;
    esac
    bcd::tool_word_to t "$word" || continue
    rest=${rest#"${rest%%[![:space:]]*}"}
    [[ "$rest" == --version ]] && continue
    v=""
    ((BCD_EXP[t])) && v=${BCD_SH[t]}
    bcd::config_judge "$t" "$v"
  done
}

bcd::load
[[ "${BCD_RECORDS[0]-}" == invalid"$BCD_TAB"* ]] && bcd::malformed "${BCD_RECORDS[0]#invalid"$BCD_TAB"}"

BCD_HOME=""
[[ -n "${HOME:-}" ]] && bcd::norm_to BCD_HOME "$HOME"
for BCD_REC in ${BCD_RECORDS[@]+"${BCD_RECORDS[@]}"}; do
  BCD_KIND=${BCD_REC%%"$BCD_TAB"*}
  BCD_REC=${BCD_REC#*"$BCD_TAB"}
  BCD_DOM=${BCD_REC%%"$BCD_TAB"*}
  BCD_VAL=${BCD_REC#*"$BCD_TAB"}
  case "$BCD_KIND" in
  root) bcd::add_root "$BCD_DOM" "$BCD_VAL" ;;
  marker)
    bcd::fold_to BCD_VAL "$BCD_VAL"
    bcd::add_needle "$BCD_DOM" "$BCD_VAL" 0
    ;;
  gh | az)
    BCD_CFG_KIND+=("$BCD_KIND")
    BCD_CFG_DOM+=("$BCD_DOM")
    BCD_CFG_DIR+=("$BCD_VAL")
    ;;
  *) ;; # a kind a newer guard writes: CACHE is keyed by BCD_FORMAT, so none reaches here
  esac
done

bcd::classify_cwd
bcd::arm_config

bcd::fold_to BCD_SUBJECT "$COMMAND"
bcd::names "$BCD_SUBJECT"
((BCD_CFG_ARMED)) && [[ "$BCD_SUBJECT" =~ $BCD_TOOL_RE ]] && BCD_CFG_HIT=1
if [[ "$BCD_NAMED" == " " ]] && ((!BCD_CFG_HIT)); then
  bcd::trace prefilter-miss
  bcd::emit_tel prefilter-miss
  exit 0
fi
bcd::trace prefilter-hit

if [[ "$TOOL_NAME" == Bash ]]; then
  bcd::trace parse
  BCD_NAMED=" "
  hook::bash_parse_segments "$COMMAND" bcd::segment
elif ((BCD_CFG_HIT)); then
  bcd::config_ps
fi

if [[ -n "$BCD_DENY" ]]; then
  bcd::trace "deny $BCD_DENY_FORM"
  bcd::emit_tel "$BCD_DENY_FORM" blocked
  hook::json_escape_to BCD_DENY "$BCD_DENY"
  hook::emit_document '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"'"$BCD_DENY"'"}}'
  exit 0
fi

if [[ "$BCD_NAMED" == " " ]]; then
  BCD_FORM=not-named
elif [[ "$BCD_NAMED" == " $BCD_CWD_DOMAIN " ]]; then
  BCD_FORM=own-domain
else
  BCD_FORM=other-domain
fi
bcd::emit_tel "$BCD_FORM"
exit 0

# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154 # HOOK_DIR and SCANNER come from the hook; DATA, PKEY and SCAN_RC go back to it

case "${TESTING_OSTYPE:-${OSTYPE:-}}" in
msys* | cygwin*) type -P jq >/dev/null && jq() { command jq -b "$@"; } ;;
*) ;;
esac

testing::fields() {
  local in="$1" prog="" e v
  shift
  for e in "$@"; do prog+="${prog:+, }((${e}) // \"\" | tostring | gsub(\"\\u0000\"; \"\")), \"\\u0000\""; done
  FIELDS=()
  while IFS= read -r -d '' v; do FIELDS+=("$v"); done < <(jq -j "$prog" <<<"$in" 2>/dev/null)
  ((${#FIELDS[@]} == $#))
}

testing::pkey() {
  local sum sha=(sha256sum)
  PKEY=""
  [[ -n "$1" && -n "$2" ]] || return 1
  command -v sha256sum >/dev/null || sha=(shasum -a 256)
  sum="$(printf '%s\n%s' "$1" "${2%[/\\]*}" | "${sha[@]}")" || return 1
  PKEY="${sum:0:16}"
}

testing::data_dir() {
  local rest
  DATA="${CLAUDE_PLUGIN_DATA:-}"
  [[ -z "$DATA" ]] || return 0
  DATA="${XDG_STATE_HOME:-${HOME:-}/.local/state}/claude-testing"
  rest="$(cd "$HOOK_DIR/.." && pwd)"
  rest="${rest#"${HOME:-}"/.claude/plugins/cache/}"
  if [[ "$rest" =~ ^([^/]+)/testing/[^/]+$ ]]; then
    DATA="${HOME:-}/.claude/plugins/data/testing-${BASH_REMATCH[1]//[^A-Za-z0-9_-]/-}"
  fi
}

testing::run_scanner() {
  local t="$1" out="$2"
  shift 2
  testing::run_bounded "$t" "$out" - bash "$SCANNER" "$@"
}

testing::run_bounded() {
  local t="$1" out="$2" err="$3" pid watchdog
  shift 3
  set -m
  if [[ "$err" == - ]]; then
    "$@" >"$out" 2>&1 &
  else
    "$@" >"$out" 2>"$err" &
  fi
  pid=$!
  set +m
  (
    trap 'kill "$s"; wait "$s"; exit' TERM
    sleep "$t" &
    s=$!
    wait "$s"
    trap '' TERM
    : >"$out.timeout"
    if pkill -TERM -P "$pid"; then
      for ((i = 0; i < 10; i++)); do
        kill -0 "$pid" || break
        sleep 0.1
      done
    fi
    kill -TERM -- "-$pid"
    for ((i = 0; i < 50; i++)); do
      kill -0 -- "-$pid" || exit
      sleep 0.1
    done
    kill -KILL -- "-$pid"
  ) >/dev/null 2>&1 &
  watchdog=$!
  wait "$pid"
  SCAN_RC=$?
  kill "$watchdog" 2>/dev/null
  wait "$watchdog"
  if [[ -e "$out.timeout" ]]; then
    rm -f "$out.timeout"
    ((SCAN_RC > 128)) || SCAN_RC=143
  fi
}

testing::norm_copy_path() {
  local v="$2"
  case "${TESTING_OSTYPE:-${OSTYPE:-}}" in
  msys* | cygwin* | win32)
    v="${v//\\//}"
    v="${v,,}"
    ;;
  *) ;;
  esac
  v="${v%/}"
  printf -v "$1" '%s' "$v"
}

testing::under_copy_root() {
  local p="$1" root="$2"
  [[ -n "$root" && "$root" != / ]] || return 1
  [[ "$p" == "$root" || "${p#"$root"/}" != "$p" ]]
}

testing::record_skip() {
  local p raw root out form seen="|"
  local -a raws=() dirs=() cyg_lines=()
  testing::norm_copy_path p "$1"
  [[ -n "$p" ]] || return 1
  [[ "$p" =~ (^|/)claude/[^/]+/[^/]+/scratchpad/ ]] && return 0
  if [[ -n "${TEST_SCAN_SKIP_ROOT+x}" ]]; then
    raws=("$TEST_SCAN_SKIP_ROOT")
  else
    raws=("${TMPDIR:-}" "${TMP:-}" "${TEMP:-}" /tmp /var/tmp)
  fi
  for raw in "${raws[@]}"; do
    [[ -n "$raw" && "$seen" != *"|$raw|"* ]] || continue
    seen+="$raw|"
    testing::norm_copy_path root "$raw"
    testing::under_copy_root "$p" "$root" && return 0
    [[ -d "$raw" && "$raw" != *$'\n'* ]] && dirs+=("$raw")
  done
  case "${TESTING_OSTYPE:-${OSTYPE:-}}" in
  msys* | cygwin* | win32) ;;
  *) return 1 ;;
  esac
  ((${#dirs[@]})) && command -v cygpath >/dev/null 2>&1 || return 1
  for form in -l -s; do
    out="$(cygpath "$form" -m -- "${dirs[@]}" 2>/dev/null)" || continue
    mapfile -t cyg_lines <<<"$out"
    ((${#cyg_lines[@]} == ${#dirs[@]})) || continue
    for root in "${cyg_lines[@]}"; do
      testing::norm_copy_path root "$root"
      testing::under_copy_root "$p" "$root" && return 0
    done
  done
  return 1
}

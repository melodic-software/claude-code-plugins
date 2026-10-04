# shellcheck shell=bash
# Shared by test-scan.sh, test-weaken.sh and the test-judge hooks, which set
# HOOK_DIR before sourcing. It only defines functions, so the judge hooks may
# source it before their no-state exit.
# shellcheck disable=SC2034,SC2154 # HOOK_DIR and SCANNER come from the hook; DATA, PKEY and SCAN_RC go back to it

# Windows' native jq.exe writes its stdout in text mode, turning every LF into
# CRLF, and `read`, `mapfile` and $(...) keep the CR. -b (--binary, jq 1.6 and
# later, "Windows users using WSL, MSYS2, or Cygwin, should use this option
# when using a native jq.exe") writes the bytes as they are, so no field, path
# or diff gains a CR and none loses one it carried. Added under Git Bash and
# Cygwin only, and only when a jq binary exists, so `command -v jq` still
# reports a missing one; TESTING_OSTYPE is the test seam for the platform.
case "${TESTING_OSTYPE:-${OSTYPE:-}}" in
msys* | cygwin*) type -P jq >/dev/null && jq() { command jq -b "$@"; } ;;
*) ;;
esac

# testing::fields <json> <jq expression>...: set FIELDS to one value per
# expression (null and false as ""), read NUL-separated: never through @tsv,
# which doubles every backslash in a Windows path, and never split on a tab or
# a newline inside a value.
testing::fields() {
  local in="$1" prog="" e v
  shift
  for e in "$@"; do prog+="${prog:+, }((${e}) // \"\" | tostring | gsub(\"\\u0000\"; \"\")), \"\\u0000\""; done
  FIELDS=()
  while IFS= read -r -d '' v; do FIELDS+=("$v"); done < <(jq -j "$prog" <<<"$in" 2>/dev/null)
  ((${#FIELDS[@]} == $#))
}

# testing::pkey <project dir> <transcript path>: set PKEY to the project key,
# the first 16 hex of the sha256 of the project directory, a newline and the
# transcript directory. A /clear or fork successor gets a new session id but
# keeps both. The project directory is CLAUDE_PROJECT_DIR, else the payload
# cwd, which a Bash cd moves; the caller picks.
testing::pkey() {
  local sum sha=(sha256sum)
  PKEY=""
  [[ -n "$1" && -n "$2" ]] || return 1
  command -v sha256sum >/dev/null || sha=(shasum -a 256)
  sum="$(printf '%s\n%s' "$1" "${2%[/\\]*}" | "${sha[@]}")" || return 1
  PKEY="${sum:0:16}"
}

# testing::data_dir: set DATA to the plugin's data directory, never under
# TMPDIR. The consumer settings entry gets no CLAUDE_PLUGIN_DATA; it derives
# the same directory from this copy's cache path (~/.claude/plugins/cache/
# <mkt>/testing/<version>/hooks), so a call through both paths shares one set
# of markers.
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

# testing::run_scanner <seconds> <out file> <scanner arg>...: run $SCANNER with
# stdout and stderr to <out file> under testing::run_bounded.
testing::run_scanner() {
  local t="$1" out="$2"
  shift 2
  testing::run_bounded "$t" "$out" - bash "$SCANNER" "$@"
}

# testing::run_bounded <seconds> <out file> <err file|-> <command>...: run the
# command with stdout to <out file> and stderr to <err file> (- : the out file)
# and set SCAN_RC. It needs no coreutils timeout, which stock macOS lacks and
# Git Bash may resolve to Windows' timeout.exe. The command runs in its own
# process group (set -m), so the timeout signals the whole group and an awk
# the scanner or a tool the judge started dies with it; a group member that
# ignores TERM gets KILL 5 s later. A timed-out run leaves SCAN_RC above 128.
# Every process here is reaped by its parent: an orphan goes to PID 1, which
# in a container without an init never reaps it.
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
    # The scanner's children first, so the scanner reaps them.
    # ponytail: one level; a grandchild still orphans, and without pkill the group kill alone runs.
    if pkill -TERM -P "$pid"; then
      for _ in 1 2 3 4 5 6 7 8 9 10; do
        kill -0 "$pid" || break
        sleep 0.1
      done
    fi
    kill -TERM -- "-$pid"
    for _ in $(seq 1 50); do
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

# testing::norm_copy_path <var> <path>: the path as the copy check compares
# it. On Windows, backslashes become slashes and case is folded; a trailing
# slash is always dropped. A POSIX host keeps a backslash: it is a filename
# byte there.
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

# testing::under_copy_root <path> <root>: true when path is the root or a
# file under it, on a segment boundary. The root is literal text, not a glob.
testing::under_copy_root() {
  local p="$1" root="$2"
  [[ -n "$root" && "$root" != / ]] || return 1
  [[ "$p" == "$root" || "${p#"$root"/}" != "$p" ]]
}

# testing::record_skip <path>: true when this test file is a working copy the
# task-end judge must not record. A file under the system temp directory, or
# in a Claude session scratchpad (.../claude/<project>/<session>/scratchpad/),
# was copied to be run, not authored. The temp roots are TMPDIR, TMP, TEMP
# and the POSIX defaults /tmp and /var/tmp, which hold when none is set.
# TEST_SCAN_SKIP_ROOT replaces them all, so a harness whose fixtures live
# under the real temp dir can point it elsewhere. On Windows each existing
# root's long and 8.3 short drive forms (cygpath -l -m, -s -m) are matched
# too: Git Bash reports TMP and TEMP as /tmp, its mount of the Windows temp
# folder, and a payload names the file by either drive spelling. Only
# directories go to cygpath: -s exits on a path that does not exist, which
# would lose the whole batch.
testing::record_skip() {
  local p raw root out form seen="|"
  local -a raws=() dirs=() lines=()
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
    mapfile -t lines <<<"$out"
    ((${#lines[@]} == ${#dirs[@]})) || continue
    for root in "${lines[@]}"; do
      testing::norm_copy_path root "$root"
      testing::under_copy_root "$p" "$root" && return 0
    done
  done
  return 1
}

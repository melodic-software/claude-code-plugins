# shellcheck shell=bash
# Shared by test-scan.sh, test-weaken.sh and the test-judge hooks, which set
# HOOK_DIR before sourcing. It only defines functions, so the judge hooks may
# source it before their no-state exit.
# shellcheck disable=SC2034,SC2154 # HOOK_DIR and SCANNER come from the hook; DATA, PKEY and SCAN_RC go back to it

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
# stdout and stderr to <out file> and set SCAN_RC. It runs in its own process
# group (set -m), so the timeout signals the whole group and an awk the
# scanner started dies with it; a timed-out run leaves SCAN_RC above 128.
# Every process here is reaped by its parent: an orphan goes to PID 1, which
# in a container without an init never reaps it.
testing::run_scanner() {
  local t="$1" out="$2" pid watchdog
  shift 2
  set -m
  bash "$SCANNER" "$@" >"$out" 2>&1 &
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

#!/usr/bin/env bash
# The four Windows Git Bash figures #3757 records.
#
#   plugins/claude-ops/hooks/windows-git-bash-figures.sh
#
# Prints one `FIGURE key=value` line per measurement on stdout. Exits 2 on any
# host that is not Windows Git Bash: a Linux number is not this issue's
# evidence. Exits 0 after printing the figures, including an explicit tie.
set -euo pipefail

uname_s="$(uname -s 2>/dev/null || true)"
case "$uname_s" in
MINGW* | MSYS* | CYGWIN*) ;;
*)
  echo "windows-git-bash-figures: host is ${uname_s:-unknown}; take these figures on Windows Git Bash" >&2
  exit 2
  ;;
esac

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOOK="$HOOK_DIR/session-event-log.sh"
date_utc="$(date -u +%Y-%m-%d)"
echo "FIGURE date=${date_utc}"
echo "FIGURE uname=${uname_s}"
echo "FIGURE bash=${BASH_VERSION}"

median_ms() {
  local samples="$1"
  printf '%s\n' "$samples" | awk '
    { a[NR] = $1 }
    END {
      n = NR
      if (n == 0) { print 0; exit }
      # insertion sort; n is 5
      for (i = 2; i <= n; i++) {
        v = a[i]
        j = i - 1
        while (j >= 1 && a[j] > v) { a[j + 1] = a[j]; j-- }
        a[j + 1] = v
      }
      if (n % 2 == 1) printf "%d\n", a[(n + 1) / 2]
      else printf "%d\n", int((a[n / 2] + a[n / 2 + 1]) / 2)
    }
  '
}

time_ms() {
  local t0 t1
  t0=$EPOCHREALTIME
  "$@" >/dev/null 2>&1
  local status=$?
  t1=$EPOCHREALTIME
  awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d\n", (b - a) * 1000 }'
  return "$status"
}

samples=""
for _ in 1 2 3 4 5; do
  samples+=$(time_ms bash -c 'exit 0')
  samples+=$'\n'
done
echo "FIGURE spawn_floor_ms=$(median_ms "$samples")"

samples=""
# The single quotes are the measured command: the inner bash expands the option.
# shellcheck disable=SC2016
kill_switch='[ "$CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED" = true ] || exit 0'
for _ in 1 2 3 4 5; do
  samples+=$(env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED bash -c "$kill_switch")
  samples+=$'\n'
done
echo "FIGURE kill_switch_ms=$(median_ms "$samples")"

t0=$EPOCHREALTIME
for _ in $(seq 1 30); do
  env -u CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED bash -c "$kill_switch" &
done
wait
t1=$EPOCHREALTIME
echo "FIGURE parallel_wall_30_ms=$(awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }')"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
append_file="$work/append.txt"
: >"$append_file"
body="$(head -c 4000 /dev/zero | tr '\0' 'a')"
for i in $(seq 1 33); do
  printf 'id-%s %s\n' "$i" "$body" >>"$append_file" &
done
wait
lines="$(wc -l <"$append_file" | tr -d ' ')"
good="$(grep -cE '^id-[0-9]+ a{4000}$' "$append_file" || true)"
echo "FIGURE append_4kb_lines=${lines}"
echo "FIGURE append_4kb_intact=${good}"

: >"$work/first"
: >"$work/second"
order="$(ls -t "$work/first" "$work/second")"
# portability-ok: GNU stat -c with a BSD stat -f fallback; the redirect between them hides the fallback from the co-location guard.
first_mtime="$(stat -c %Y "$work/first" 2>/dev/null || stat -f %m "$work/first")"
# portability-ok: GNU stat -c with a BSD stat -f fallback; the redirect between them hides the fallback from the co-location guard.
second_mtime="$(stat -c %Y "$work/second" 2>/dev/null || stat -f %m "$work/second")"
if [[ "$first_mtime" == "$second_mtime" ]]; then
  echo "FIGURE ls_t_same_second=tie mtime=${first_mtime} order=$(printf '%s' "$order" | tr '\n' ',')"
else
  echo "FIGURE ls_t_same_second=ordered first=${first_mtime} second=${second_mtime}"
fi

proj="$work/proj"
mkdir -p "$proj/.git"
payload='{"session_id":"fig-eof","cwd":"/x","hook_event_name":"PostToolUse","tool_name":"Write","tool_input":{"file_path":"a.md"}}'
elapsed=$(
  {
    printf '%s' "$payload"
    sleep 3
  } | {
    t0=$EPOCHREALTIME
    env CLAUDE_PROJECT_DIR="$proj" CLAUDE_PLUGIN_OPTION_SESSION_EVENT_LOG_ENABLED=true \
      CLAUDE_PLUGIN_OPTION_STDIN_READ_TIMEOUT=1 bash "$HOOK" >/dev/null 2>&1 || true
    t1=$EPOCHREALTIME
    awk -v a="$t0" -v b="$t1" 'BEGIN { printf "%d", (b - a) * 1000 }'
  }
)
echo "FIGURE late_eof_ms=${elapsed}"
log="$proj/.observability/claude/sessions/fig-eof.jsonl"
if [[ -s "$log" ]]; then
  echo "FIGURE late_eof_line=written"
else
  echo "FIGURE late_eof_line=missing"
fi

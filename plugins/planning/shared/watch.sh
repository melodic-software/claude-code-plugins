#!/usr/bin/env bash
# GENERATED from lib/session-bridge/watch.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# session-bridge's watcher (the loopback adapter's client). Run in a background Bash task; it exits
# when the page has something new.
#   bash watch.sh '<data_dir>'
# Reads NAME and CONTROL from session-bridge.conf beside this script: NAME names the session env
# file (.<NAME>-session.env) and the token header (X-<Name>-Token); CONTROL is the app's control
# script beside this one, named in messages and run by wake.sh.
# Long-polls /api/wait (each poll is the heartbeat the page shows as "Claude is listening"),
# prints the unhandled events as one JSON line carrying "dataDir" and "next" (the exact re-arm
# command, wake.sh beside this script), stores the seq in .watch-seq, and exits 0. Events a dead
# turn never handled come back at once on the next arm; after that re-delivery (recorded in
# .watch-replay) an arm waits for a new event.
# Exits 2 when curl is missing, when session-bridge.conf is missing or malformed, when the env
# file's PORT is not all digits, when the token was rejected (the server restarted), or when the
# server stays unreachable for WAIT_FAILS polls (default 12, 5 s apart).
# Exits 3 when another watcher holds the server's lease (one session watches a data dir at a
# time), when this watcher's lease was released while it waited, or when a poll fails after
# `CONTROL stop` removed the env file; it prints why to stderr and does not retry. Each poll sends
# this process's pid (&pid=$$), which the lease records so `CONTROL stop` can end this watcher.
# Each poll names this watcher: WATCH_ID, else CLAUDE_CODE_SESSION_ID (Claude Code exports it to
# every shell a session runs, so every re-arm shares it), else <hostname>-<parent pid>. A parent
# pid of 1 (a Claude Code Bash shell on Windows reports it, for every session) names no one, so
# then it exits 2 asking for WATCH_ID. The id is never written to the data dir, which two sessions
# share. WATCH_PPID stands in for $PPID in tests.
# WAIT_TIMEOUT comes from the session env file (default 90); curl allows 10 s more.
curl_bin=${WATCH_CURL:-curl}
command -v "$curl_bin" >/dev/null 2>&1 || { echo "missing prerequisite: curl (watch.sh needs it on PATH)" >&2; exit 2; }
[[ -n "${1:-}" ]] || { echo "usage: watch.sh <data_dir>" >&2; exit 2; }
# Absolute paths in the platform's native form: Git Bash's `pwd -W` gives C:/..., which a native
# Python takes as is (Git Bash does not convert a POSIX path holding a quote or a backtick).
# Elsewhere `pwd -W` fails and plain `pwd` applies.
abs_dir() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
here=$(abs_dir "$(dirname "${BASH_SOURCE[0]}")")
conf="$here/session-bridge.conf"
NAME=$(sed -n 's/^NAME=//p' "$conf" 2>/dev/null | tr -d '\r')
CONTROL=$(sed -n 's/^CONTROL=//p' "$conf" 2>/dev/null | tr -d '\r')
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ && "$CONTROL" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { echo "no valid NAME and CONTROL in $conf" >&2; exit 2; }
header="X-$(printf '%s' "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}-Token"
dir=$(abs_dir "$1") || { echo "no such data dir: $1" >&2; exit 2; }
env_file="$dir/.$NAME-session.env"
[[ -f "$env_file" ]] || { echo "no $env_file: run $CONTROL ensure-running first" >&2; exit 2; }
PORT=$(sed -n 's/^PORT=//p' "$env_file" | tr -d '\r')
TOKEN=$(sed -n 's/^TOKEN=//p' "$env_file" | tr -d '\r')
WAIT_TIMEOUT=$(sed -n 's/^WAIT_TIMEOUT=//p' "$env_file" | tr -dc '0-9')
WAIT_TIMEOUT=${WAIT_TIMEOUT:-90}
[[ -n "$PORT" && -n "$TOKEN" ]] || { echo "server not running (empty $env_file)" >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "PORT in $env_file is not a number: re-run ensure-running" >&2; exit 2; }
max_fails=${WAIT_FAILS:-12}
# after=handled returns every unhandled event; .watch-replay bounds re-delivery to one extra wake.
replayed=$(tr -dc '0-9' 2>/dev/null <"$dir/.watch-replay")
replayed=${replayed:-0}

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "${s//$'\t'/\\t}"
}

# One shell word: single quotes, with each single quote inside written as '\''.
shell_quote() {
  local q="'\\''"
  printf "'%s'" "${1//\'/$q}"
}

# Percent-encode every byte outside A-Z a-z 0-9 . _ ~ - for the query string.
url_encode() {
  local LC_ALL=C s=$1 c out='' i
  for ((i = 0; i < ${#s}; i++)); do
    c=${s:i:1}
    case "$c" in
      [A-Za-z0-9._~-]) out+=$c ;;
      *) out+=$(printf '%%%02X' "'$c") ;;
    esac
  done
  printf '%s' "$out"
}
watcher=${WATCH_ID:-${CLAUDE_CODE_SESSION_ID:-}}
if [[ -z "$watcher" ]]; then
  parent=${WATCH_PPID:-$PPID}
  if [[ "$parent" == 1 ]]; then
    echo "no watcher id: the parent pid is 1, which every session shares here; export WATCH_ID=<a name for this session> and re-arm" >&2
    exit 2
  fi
  watcher="$(hostname)-$parent"
fi
watcher=$(url_encode "$watcher")

# The value of one string field in the 409 body.
field() { printf '%s' "$out" | sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p"; }

fails=0
while :; do
  # The body comes back on stdout (no file path reaches curl), with the status on a last line.
  resp=$("$curl_bin" -s -w '\n%{http_code}' --noproxy '*' --max-time $((WAIT_TIMEOUT + 10)) \
    -H "$header: $TOKEN" "http://127.0.0.1:$PORT/api/wait?after=handled&replayed=$replayed&timeout=$WAIT_TIMEOUT&watcher=$watcher&pid=$$")
  code=${resp##*$'\n'}
  out=${resp%$'\n'*}
  if [[ "$code" == 409 && "$out" == *'"lease held"'* ]]; then
    echo "another watcher holds this $NAME's lease: session $(field holder), since $(field since), last poll $(field lastWaitAt); one session watches a data dir at a time; coordinate with that session, or wait for the lease to expire ($(field expiresAt))" >&2
    exit 3
  fi
  if [[ "$code" == 409 && "$out" == *'"lease released"'* ]]; then
    echo "this watcher's lease was released while it waited ($CONTROL lease --release); another session may hold it now; run $CONTROL lease to see, and re-arm only if this session should watch" >&2
    exit 3
  fi
  case "$code" in
    200) ;;
    403)
      echo "token changed: re-run ensure-running" >&2
      exit 2
      ;;
    *)
      # `CONTROL stop` removes the env file once the server is down: a refused poll after that is
      # a clean stop, not an outage to retry.
      if [[ ! -f "$env_file" ]]; then
        echo "the $NAME server was stopped ($CONTROL stop): not re-arming" >&2
        exit 3
      fi
      fails=$((fails + 1))
      if [[ "$fails" -ge "$max_fails" ]]; then
        echo "server unreachable on $PORT" >&2
        exit 2
      fi
      sleep 5
      continue
      ;;
  esac
  fails=0
  case "$out" in
    *'"timedOut": false'*)
      next="bash $(shell_quote "$here/wake.sh") $(shell_quote "$dir")"
      printf '%s, "dataDir": "%s", "next": "%s"}\n' "${out%\}}" "$(json_escape "$dir")" "$(json_escape "$next")"
      printf '%s' "$out" | sed -n 's/^{"seq": \([0-9]*\).*/\1/p' >"$dir/.watch-seq"
      case "$out" in
        '{"seq": '*', "timedOut": false, "replayed": '*)
          printf '%s' "$out" | sed -n 's/^{"seq": [0-9]*, "timedOut": false, "replayed": \([0-9]*\).*/\1/p' >"$dir/.watch-replay"
          ;;
        *) ;;
      esac
      exit 0
      ;;
    *) ;;
  esac
done

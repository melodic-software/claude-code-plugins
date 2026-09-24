#!/usr/bin/env bash
# Claude's watcher. Run in a background Bash task; it exits when the page has something new.
#   bash watch.sh <data_dir>
# Long-polls /api/wait (each poll is the heartbeat the page shows as "Claude is listening"),
# prints the unhandled events as one JSON line carrying "dataDir" and "next" (the exact re-arm
# command), stores the seq in .watch-seq, and exits 0. Events a dead turn never handled come
# back at once on the next arm; after that re-delivery (recorded in .watch-replay) an arm waits
# for a new event.
# Exits 2 when curl is missing, when the token was rejected (the server restarted), or when
# the server stays unreachable for WAIT_FAILS polls (default 12, 5 s apart).
# WAIT_TIMEOUT comes from the session env file (default 90); curl allows 10 s more.
curl_bin=${WATCH_CURL:-curl}
command -v "$curl_bin" >/dev/null 2>&1 || { echo "missing prerequisite: curl (watch.sh needs it on PATH)" >&2; exit 2; }
[[ -n "${1:-}" ]] || { echo "usage: watch.sh <data_dir>" >&2; exit 2; }
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dir=$(cd "$1" 2>/dev/null && pwd) || { echo "no such data dir: $1" >&2; exit 2; }
env_file="$dir/.interview-session.env"
[[ -f "$env_file" ]] || { echo "no $env_file: run round.sh ensure-running first" >&2; exit 2; }
PORT=$(sed -n 's/^PORT=//p' "$env_file" | tr -d '\r')
TOKEN=$(sed -n 's/^TOKEN=//p' "$env_file" | tr -d '\r')
WAIT_TIMEOUT=$(sed -n 's/^WAIT_TIMEOUT=//p' "$env_file" | tr -dc '0-9')
WAIT_TIMEOUT=${WAIT_TIMEOUT:-90}
[[ -n "$PORT" && -n "$TOKEN" ]] || { echo "server not running (empty $env_file)" >&2; exit 2; }
max_fails=${WAIT_FAILS:-12}
# after=handled returns every unhandled event; .watch-replay bounds re-delivery to one extra wake.
replayed=$(tr -dc '0-9' <"$dir/.watch-replay" 2>/dev/null)
replayed=${replayed:-0}
body="$dir/.watch-body.$$"
trap 'rm -f "$body"' EXIT

json_escape() {
  local s=${1//\\/\\\\}
  printf '%s' "${s//\"/\\\"}"
}

fails=0
while :; do
  code=$("$curl_bin" -s -o "$body" -w '%{http_code}' --max-time $((WAIT_TIMEOUT + 10)) \
    -H "X-Interview-Token: $TOKEN" "http://127.0.0.1:$PORT/api/wait?after=handled&replayed=$replayed&timeout=$WAIT_TIMEOUT")
  case "$code" in
    200) ;;
    403)
      echo "token changed: re-run ensure-running" >&2
      exit 2
      ;;
    *)
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
  out=$(cat "$body")
  case "$out" in
    *'"timedOut": false'*)
      next="bash \"$here/round.sh\" --dir \"$dir\" apply --file ops.json && bash \"$here/watch.sh\" \"$dir\""
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

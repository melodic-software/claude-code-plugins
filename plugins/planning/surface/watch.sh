#!/usr/bin/env bash
# Claude's watcher. Run in a background Bash task; it exits when the page has something new.
#   bash watch.sh '<data_dir>'
# Long-polls /api/wait (each poll is the heartbeat the page shows as "Claude is listening"),
# prints the unhandled events as one JSON line carrying "dataDir" and "next" (the exact re-arm
# command), stores the seq in .watch-seq, and exits 0. Events a dead turn never handled come
# back at once on the next arm; after that re-delivery (recorded in .watch-replay) an arm waits
# for a new event.
# Exits 2 when curl is missing, when the env file's PORT is not all digits, when the token was
# rejected (the server restarted), or when the server stays unreachable for WAIT_FAILS polls
# (default 12, 5 s apart).
# Exits 3 when another watcher holds the server's lease (one session watches a data dir at a
# time); it prints the holder to stderr and does not retry.
# Each poll names this watcher: WATCH_ID, else CLAUDE_CODE_SESSION_ID (the Bash tool exports it,
# so every re-arm from one session shares it), else <hostname>-<parent pid>. The id is never
# written to the data dir, which two sessions share.
# WAIT_TIMEOUT comes from the session env file (default 90); curl allows 10 s more.
curl_bin=${WATCH_CURL:-curl}
command -v "$curl_bin" >/dev/null 2>&1 || { echo "missing prerequisite: curl (watch.sh needs it on PATH)" >&2; exit 2; }
[[ -n "${1:-}" ]] || { echo "usage: watch.sh <data_dir>" >&2; exit 2; }
# Absolute paths in the platform's native form: Git Bash's `pwd -W` gives C:/..., which a native
# Python takes as is (Git Bash does not convert a POSIX path holding a quote or a backtick).
# Elsewhere `pwd -W` fails and plain `pwd` applies.
abs_dir() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
here=$(abs_dir "$(dirname "${BASH_SOURCE[0]}")")
dir=$(abs_dir "$1") || { echo "no such data dir: $1" >&2; exit 2; }
env_file="$dir/.interview-session.env"
[[ -f "$env_file" ]] || { echo "no $env_file: run round.sh ensure-running first" >&2; exit 2; }
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
watcher=$(url_encode "${WATCH_ID:-${CLAUDE_CODE_SESSION_ID:-$(hostname)-$PPID}}")

# The value of one string field in the 409 body.
field() { printf '%s' "$out" | sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p"; }

fails=0
while :; do
  # The body comes back on stdout (no file path reaches curl), with the status on a last line.
  resp=$("$curl_bin" -s -w '\n%{http_code}' --noproxy '*' --max-time $((WAIT_TIMEOUT + 10)) \
    -H "X-Interview-Token: $TOKEN" "http://127.0.0.1:$PORT/api/wait?after=handled&replayed=$replayed&timeout=$WAIT_TIMEOUT&watcher=$watcher")
  code=${resp##*$'\n'}
  out=${resp%$'\n'*}
  if [[ "$code" == 409 && "$out" == *'"lease held"'* ]]; then
    echo "another watcher holds this interview's lease: session $(field holder), since $(field since), last poll $(field lastWaitAt); one session watches a data dir at a time; coordinate with that session, or wait for the lease to expire ($(field expiresAt))" >&2
    exit 3
  fi
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
  case "$out" in
    *'"timedOut": false'*)
      next="bash $(shell_quote "$here/round.sh") --dir $(shell_quote "$dir") apply --file $(shell_quote "$dir/ops.json") && bash $(shell_quote "$here/watch.sh") $(shell_quote "$dir")"
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

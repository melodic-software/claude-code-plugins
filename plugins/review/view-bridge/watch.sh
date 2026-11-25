#!/usr/bin/env bash
# GENERATED from lib/session-bridge/watch.sh by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
curl_bin=${WATCH_CURL:-curl}
command -v "$curl_bin" >/dev/null 2>&1 || { echo "missing prerequisite: curl (watch.sh needs it on PATH)" >&2; exit 2; }
[[ -n "${1:-}" ]] || { echo "usage: watch.sh <data_dir>" >&2; exit 2; }
abs_dir() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
value() { sed -n "s/^$1=//p" "$2" | tr -d '\r'; }
here=$(abs_dir "$(dirname "${BASH_SOURCE[0]}")")
conf="$here/session-bridge.conf"
NAME=$(value NAME "$conf" 2>/dev/null)
CONTROL=$(value CONTROL "$conf" 2>/dev/null)
[[ "$NAME" =~ ^[a-z][a-z0-9-]*$ && "$CONTROL" =~ ^[A-Za-z0-9._-]+$ ]] ||
  { echo "no valid NAME and CONTROL in $conf" >&2; exit 2; }
header="X-$(printf '%s' "${NAME:0:1}" | tr '[:lower:]' '[:upper:]')${NAME:1}-Token"
dir=$(abs_dir "$1") || { echo "no such data dir: $1" >&2; exit 2; }
env_file="$dir/.$NAME-session.env"
[[ -f "$env_file" ]] || { echo "no $env_file: run $CONTROL ensure-running first" >&2; exit 2; }
PORT=$(value PORT "$env_file")
TOKEN=$(value WATCH_TOKEN "$env_file")
[[ -n "$TOKEN" ]] || TOKEN=$(value TOKEN "$env_file")
WAIT_TIMEOUT=$(value WAIT_TIMEOUT "$env_file" | tr -dc '0-9')
WAIT_TIMEOUT=${WAIT_TIMEOUT:-90}
[[ -n "$PORT" && -n "$TOKEN" ]] || { echo "server not running (empty $env_file)" >&2; exit 2; }
[[ "$PORT" =~ ^[0-9]+$ ]] || { echo "PORT in $env_file is not a number: re-run ensure-running" >&2; exit 2; }
manifest="$here/../.claude-plugin/plugin.json"
if [[ -f "$manifest" ]]; then
  installed=$(sed -n 's/^[[:space:]]*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$manifest" | head -n 1)
  recorded=$(value PLUGIN_VERSION "$env_file")
  if [[ -n "$installed" && "$recorded" != "$installed" ]]; then
    echo "note: the $NAME server runs ${recorded:-a version that records none}, not this plugin's $installed: run $CONTROL ensure-running to restart it, then re-arm" >&2
  fi
fi
max_fails=${WAIT_FAILS:-12}
max_empty=${WAIT_EMPTY:-40}
[[ "$max_empty" =~ ^[0-9]+$ && "$max_empty" -gt 0 ]] || max_empty=40
replayed=$(tr -dc '0-9' 2>/dev/null <"$dir/.watch-replay")
replayed=${replayed:-0}

json_escape() {
  local s=${1//\\/\\\\}
  s=${s//\"/\\\"}
  s=${s//$'\n'/\\n}
  s=${s//$'\r'/\\r}
  printf '%s' "${s//$'\t'/\\t}"
}

shell_quote() {
  local q="'\\''"
  printf "'%s'" "${1//\'/$q}"
}

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

field() { printf '%s' "$out" | sed -n "s/.*\"$1\": \"\\([^\"]*\\)\".*/\\1/p"; }

fails=0
empty=0
while :; do
  resp=$("$curl_bin" -s -w '\n%{http_code}' --noproxy '*' --max-time $((WAIT_TIMEOUT + 10)) \
    -H @- "http://127.0.0.1:$PORT/api/wait?after=handled&replayed=$replayed&timeout=$WAIT_TIMEOUT&watcher=$watcher&pid=$$" \
    <<<"$header: $TOKEN")
  code=${resp##*$'\n'}
  out=${resp%$'\n'*}
  if [[ "$code" == 409 && "$out" == *'"lease held"'* ]]; then
    echo "another watcher holds this $NAME's lease: session $(field holder), since $(field since), last poll $(field lastWaitAt); one session watches a data dir at a time; coordinate with that session, or wait for the lease to expire ($(field expiresAt))" >&2
    exit 3
  fi
  if [[ "$code" == 409 && "$out" == *'"lease released"'* ]]; then
    echo "handed over, not a failure: this watcher's lease was released while it waited ($CONTROL lease --release or --takeover); another session holds or may hold it now; run $CONTROL lease to see, and re-arm only if this session should watch" >&2
    exit 3
  fi
  case "$code" in
    200) ;;
    403)
      echo "token changed: re-run ensure-running" >&2
      exit 2
      ;;
    *)
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
      printf -v payload '%s, "dataDir": "%s", "next": "%s"}' "${out%\}}" "$(json_escape "$dir")" "$(json_escape "$next")"
      { (umask 077 && rm -f "$dir/.watch-wake.json.tmp" && printf '%s\n' "$payload" >"$dir/.watch-wake.json.tmp") &&
        mv -f "$dir/.watch-wake.json.tmp" "$dir/.watch-wake.json"; } 2>/dev/null ||
        { rm -f "$dir/.watch-wake.json" "$dir/.watch-wake.json.tmp"
          echo "could not write $dir/.watch-wake.json: take the JSON line from this task's output" >&2; }
      printf '%s\n' "$payload"
      printf '%s' "$out" | sed -n 's/^{"seq": \([0-9]*\).*/\1/p' >"$dir/.watch-seq"
      if [[ "$out" == '{"seq": '*', "timedOut": false, "replayed": '* ]]; then
        printf '%s' "$out" | sed -n 's/^{"seq": [0-9]*, "timedOut": false, "replayed": \([0-9]*\).*/\1/p' >"$dir/.watch-replay"
      fi
      exit 0
      ;;
    *)
      empty=$((empty + 1))
      if [[ "$empty" -ge "$max_empty" ]]; then
        echo "no events in $empty consecutive waits: this watcher is exiting so an orphan does not keep the $NAME server alive; a live session re-arms with: bash $(shell_quote "$here/wake.sh") $(shell_quote "$dir")" >&2
        exit 4
      fi
      ;;
  esac
done

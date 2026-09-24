#!/usr/bin/env bash
# Tests for watch.sh against a live server started through round.sh ensure-running.
#   bash watch.test.sh
# Cases: curl missing (WATCH_CURL override), wrong token (exit 2 at once), a delivery
# (one JSON line carrying dataDir and next, .watch-seq stored), server gone (WAIT_FAILS=1).
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
pass=0
fail=0
ok() { echo "ok: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1"; fail=$((fail + 1)); }

py=$(command -v python3 || command -v python)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/iv-watch.XXXXXX")
d="$tmp/data"
mkdir -p "$d"
cleanup() {
  bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1
  case "$tmp" in
    */iv-watch.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap cleanup EXIT

# Run a command in the background with a deadline; returns its exit code, or 124 on timeout.
bounded() { # seconds out err cmd...
  local end=$((SECONDS + $1)) out=$2 err=$3 pid
  shift 3
  "$@" >"$out" 2>"$err" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    if [[ "$SECONDS" -ge "$end" ]]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep 0.1
  done
  wait "$pid"
}

if url=$(bash "$here/round.sh" --dir "$d" ensure-running --port 0) && [[ -n "$url" ]]; then
  ok "server started through round.sh ensure-running ($url)"
else
  bad "round.sh ensure-running did not start a server"
  echo "PASS=$pass FAIL=$fail"
  exit 1
fi
PORT=$(sed -n 's/^PORT=//p' "$d/.interview-session.env" | tr -d '\r')
TOKEN=$(sed -n 's/^TOKEN=//p' "$d/.interview-session.env" | tr -d '\r')
cp "$d/.interview-session.env" "$tmp/env.saved"

# (a) curl missing
WATCH_CURL=/nonexistent bounded 10 "$tmp/a.out" "$tmp/a.err" bash "$here/watch.sh" "$d"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q curl "$tmp/a.err"; then
  ok "exits 2 naming curl when curl is missing"
else
  bad "curl missing: rc=$rc err=$(cat "$tmp/a.err")"
fi

# (b) wrong token: a second data dir whose env file points at the live port with another token
mkdir -p "$tmp/wrong"
sed 's/^TOKEN=.*/TOKEN=not-the-token/' "$tmp/env.saved" >"$tmp/wrong/.interview-session.env"
start=$SECONDS
bounded 10 "$tmp/b.out" "$tmp/b.err" bash "$here/watch.sh" "$tmp/wrong"
rc=$?
took=$((SECONDS - start))
if [[ "$rc" -eq 2 && "$took" -le 5 ]] && grep -q "token changed: re-run ensure-running" "$tmp/b.err"; then
  ok "exits 2 at once on a wrong token (${took}s)"
else
  bad "wrong token: rc=$rc took=${took}s err=$(cat "$tmp/b.err")"
fi

# (c) a delivery prints one self-describing JSON line and exits 0
bash "$here/watch.sh" "$d" >"$tmp/c.out" 2>"$tmp/c.err" &
wpid=$!
sleep 1
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "X-Interview-Token: $TOKEN" \
  -H 'Content-Type: application/json' --data '{"kind": "note", "text": "watch test note"}' \
  "http://127.0.0.1:$PORT/api/answer")
end=$((SECONDS + 10))
while kill -0 "$wpid" 2>/dev/null && [[ "$SECONDS" -lt "$end" ]]; do
  sleep 0.1
done
if kill -0 "$wpid" 2>/dev/null; then kill "$wpid" 2>/dev/null; fi
wait "$wpid"
rc=$?
lines=$(wc -l <"$tmp/c.out" | tr -d ' ')
fields=$("$py" -c '
import json, sys
line = open(sys.argv[1], encoding="utf-8").read().strip()
d = json.loads(line)
print(d["dataDir"])
print(d["next"])
print(d["events"][0]["kind"])
' "$tmp/c.out" 2>&1)
data_dir=$(printf '%s\n' "$fields" | sed -n 1p)
next=$(printf '%s\n' "$fields" | sed -n 2p)
kind=$(printf '%s\n' "$fields" | sed -n 3p)
want_next="bash \"$here/round.sh\" --dir \"$d\" apply --file ops.json && bash \"$here/watch.sh\" \"$d\""
if [[ "$code" == 200 && "$rc" -eq 0 && "$lines" == 1 && "$data_dir" == "$d" && "$next" == "$want_next" && "$kind" == note ]]; then
  ok "a delivery prints one JSON line with dataDir and next, exit 0"
else
  bad "delivery: post=$code rc=$rc lines=$lines fields=[$fields] out=$(cat "$tmp/c.out") err=$(cat "$tmp/c.err")"
fi
seq=$(tr -dc '0-9' <"$d/.watch-seq" 2>/dev/null)
if [[ -n "$seq" && "$seq" -ge 1 ]]; then ok ".watch-seq stores the delivered seq ($seq)"; else bad ".watch-seq not stored"; fi

# (d) server gone: stop it, put the old env file back, and expect exit 2 after one failed poll
if bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1; then ok "round.sh stop stops the server"; else bad "round.sh stop failed"; fi
cp "$tmp/env.saved" "$d/.interview-session.env"
WAIT_FAILS=1 bounded 15 "$tmp/d.out" "$tmp/d.err" bash "$here/watch.sh" "$d"
rc=$?
if [[ "$rc" -eq 2 ]] && grep -q "unreachable" "$tmp/d.err"; then
  ok "exits 2 when the server is gone"
else
  bad "server gone: rc=$rc err=$(cat "$tmp/d.err")"
fi

echo "PASS=$pass FAIL=$fail"
[[ "$fail" -eq 0 ]]

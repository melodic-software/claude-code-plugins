#!/usr/bin/env bash
# Tests for watch.sh against a live server started through round.sh ensure-running.
#   bash watch.test.sh
# Cases: curl missing (WATCH_CURL override), wrong token (exit 2 at once), a delivery
# (one JSON line carrying dataDir and next, .watch-seq stored), re-delivery bounds, the
# skill's documented wake command read from context/surface.md (AC9, AC10), a dead http_proxy
# the watcher bypasses, a data dir named with $( ), a backtick and a single quote, server gone
# (WAIT_FAILS=1).
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
# The native absolute form watch.sh prints (C:/... under Git Bash, the plain path elsewhere).
abs_dir() { (cd "$1" 2>/dev/null && { pwd -W 2>/dev/null || pwd; }); }
# A data dir whose name carries shell syntax: $( ), a backtick and a single quote. It is built on
# the native form, which a native Python takes as is.
odd="$(abs_dir "$tmp")/odd \$(true) \`x\` it's"
cleanup() {
  bash "$here/round.sh" --dir "$d" stop >/dev/null 2>&1
  if [[ -d "$odd" ]]; then bash "$here/round.sh" --dir "$odd" stop >/dev/null 2>&1; fi
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

# Block until the server reports a waiting watcher (up to 10 s), so a POST lands mid-wait.
until_waiting() {
  local end=$((SECONDS + 10))
  while [[ "$SECONDS" -lt "$end" ]]; do
    curl -s --max-time 2 "http://127.0.0.1:$PORT/api/state" | grep -q '"waiters": 1' && return 0
    sleep 0.1
  done
  return 1
}

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
until_waiting
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
nd=$(abs_dir "$d")
nh=$(abs_dir "$here")
want_next="bash '$nh/round.sh' --dir '$nd' apply --file '$nd/ops.json' && bash '$nh/watch.sh' '$nd'"
if [[ "$code" == 200 && "$rc" -eq 0 && "$lines" == 1 && "$data_dir" == "$nd" && "$next" == "$want_next" && "$kind" == note ]]; then
  ok "a delivery prints one JSON line with dataDir and next, exit 0"
else
  bad "delivery: post=$code rc=$rc lines=$lines fields=[$fields] out=$(cat "$tmp/c.out") err=$(cat "$tmp/c.err")"
fi
seq=$(tr -dc '0-9' <"$d/.watch-seq" 2>/dev/null)
if [[ -n "$seq" && "$seq" -ge 1 ]]; then ok ".watch-seq stores the delivered seq ($seq)"; else bad ".watch-seq not stored"; fi
if [[ ! -f "$d/.watch-replay" ]]; then ok "a blocking delivery writes no .watch-replay"; else bad ".watch-replay written after a blocking delivery"; fi

post_note() {
  curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "X-Interview-Token: $TOKEN" \
    -H 'Content-Type: application/json' --data "{\"kind\": \"note\", \"text\": \"$1\"}" \
    "http://127.0.0.1:$PORT/api/answer"
}
event_seqs() { # file: the delivered seqs, space-separated
  "$py" -c '
import json, sys
print(" ".join(str(e["seq"]) for e in json.loads(open(sys.argv[1], encoding="utf-8").read())["events"]))
' "$1" 2>&1
}

# (e) AC8: the turn died before handling; the next arm re-delivers at once and records the replay.
# A wait that did not re-deliver would hold the watcher for the whole WAIT_TIMEOUT, so the watcher
# exiting inside a third of it proves "at once". The bound is on the watcher's exit, not on wall
# seconds, which on a loaded Windows host mostly count Git Bash process spawns.
wait_timeout=$(sed -n 's/^WAIT_TIMEOUT=//p' "$d/.interview-session.env" | tr -dc '0-9')
bound=$((${wait_timeout:-90} / 3))
bounded "$bound" "$tmp/e.out" "$tmp/e.err" bash "$here/watch.sh" "$d"
rc=$?
got=$(event_seqs "$tmp/e.out")
replay=$(tr -dc '0-9' <"$d/.watch-replay" 2>/dev/null)
if [[ "$bound" -ge 10 && "$rc" -eq 0 && "$got" == "$seq" && "$replay" == "$seq" ]]; then
  ok "AC8: an unhandled event re-delivers on the next arm within ${bound}s of a ${wait_timeout:-90}s wait; .watch-replay=$replay"
else
  bad "AC8 re-delivery: bound=${bound}s rc=$rc got=[$got] replay=[$replay] err=$(cat "$tmp/e.err")"
fi

# (f) a second arm with no new event keeps waiting
bounded 3 "$tmp/f.out" "$tmp/f.err" bash "$here/watch.sh" "$d"
rc=$?
if [[ "$rc" -eq 124 && ! -s "$tmp/f.out" ]]; then
  ok "a second arm without a new event does not return"
else
  bad "second arm returned: rc=$rc out=$(cat "$tmp/f.out") err=$(cat "$tmp/f.err")"
fi

# (g) a new event during the wait returns the old unhandled event and the new one; the watcher
# runs with a dead proxy in http_proxy, which its curl call must bypass for 127.0.0.1.
http_proxy=http://127.0.0.1:9 HTTP_PROXY=http://127.0.0.1:9 bash "$here/watch.sh" "$d" >"$tmp/g.out" 2>"$tmp/g.err" &
wpid=$!
until_waiting
code=$(post_note "second watch note")
end=$((SECONDS + 10))
while kill -0 "$wpid" 2>/dev/null && [[ "$SECONDS" -lt "$end" ]]; do
  sleep 0.1
done
if kill -0 "$wpid" 2>/dev/null; then kill "$wpid" 2>/dev/null; fi
wait "$wpid"
rc=$?
got=$(event_seqs "$tmp/g.out")
if [[ "$code" == 200 && "$rc" -eq 0 && "$got" == "$seq $((seq + 1))" ]]; then
  ok "a new event returns the unhandled set past a dead http_proxy ($got)"
else
  bad "new event: post=$code rc=$rc got=[$got] err=$(cat "$tmp/g.err")"
fi

# (h) AC9, AC10: the wake command exactly as the skill documents it in context/surface.md, run
# as one bash invocation with an ops.json holding one handle op for every unhandled event.
doc="$here/../skills/interview/context/surface.md"
marker='<!-- wake-command: surface/watch.test.sh runs the fenced command below -->'
n_marker=$(grep -cxF -- "$marker" "$doc" 2>/dev/null)
cmd=$(awk -v m="$marker" '
  found == 0 && $0 == m { found = 1; next }
  found == 1 { if ($0 == "```bash") { found = 2; next } else { exit } }
  found == 2 { if ($0 == "```") exit; print }
' "$doc" 2>/dev/null)
cmd_lines=$(printf '%s\n' "$cmd" | grep -c .)
if [[ "$n_marker" == 1 && "$cmd_lines" == 1 ]]; then
  ok "context/surface.md documents the wake command as one line after its marker"
else
  bad "documented wake command: marker x${n_marker:-0}, command lines $cmd_lines"
fi
add_out=$(bash "$here/round.sh" --dir "$d" add --id Q1 --short Store --title "Which store keeps the answers?" \
  --rec "JSON files in the data dir." --commit none --alt "a:SQLite" --alt "b:One file per answer" 2>&1)
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "X-Interview-Token: $TOKEN" \
  -H 'Content-Type: application/json' --data '{"kind": "accept", "id": "Q1"}' \
  "http://127.0.0.1:$PORT/api/answer")
rev() { "$py" -c 'import json, sys; print(json.load(open(sys.argv[1], encoding="utf-8"))["rev"])' "$d/questions.json" 2>&1; }
claude_lines() { # Claude thread lines on Q1 (add writes the first one)
  "$py" -c '
import json, sys
q = next(q for q in json.load(open(sys.argv[1], encoding="utf-8"))["questions"] if q["id"] == "Q1")
print(sum(1 for h in q.get("history", []) if h.get("by") == "claude"))
' "$d/questions.json" 2>&1
}
rev_before=$(rev)
lines_before=$(claude_lines)
printf '{"ops": [{"op": "handle", "seqs": [%s, %s, %s]}]}\n' "$seq" "$((seq + 1))" "$((seq + 2))" >"$d/ops.json"
run="${cmd//<data_dir>/$d}"
CLAUDE_PLUGIN_ROOT="$(cd "$here/.." && pwd)" WAIT_FAILS=1 bounded 4 "$tmp/h.out" "$tmp/h.err" bash -c "$run"
rc=$?
rev_after=$(rev)
lines_after=$(claude_lines)
# Every event is handled, so the re-armed watcher waits (a clean timeout here) and prints no line.
if [[ "$code" == 200 && "$rc" -eq 124 && "$rev_after" == $((rev_before + 1)) ]] &&
  grep -q '^applied 1 ops' "$tmp/h.out" && ! grep -q '^{' "$tmp/h.out"; then
  ok "AC10: the documented chain applies once (rev $rev_before to $rev_after) and re-arms a waiting watcher"
else
  bad "documented chain: add=[$add_out] post=$code rc=$rc rev $rev_before to $rev_after out=$(cat "$tmp/h.out") err=$(cat "$tmp/h.err")"
fi
if [[ "$rc" -eq 124 && "$lines_before" =~ ^[0-9]+$ && "$lines_after" == "$lines_before" ]]; then
  ok "AC9: handling a plain accept writes no Claude thread line"
else
  bad "AC9: Claude lines on Q1 went from $lines_before to $lines_after (chain rc=$rc)"
fi

# (i) a data dir named with $( ), a backtick and a single quote: `next` stays one literal command
# for that exact dir.
mkdir -p "$odd"
if bash "$here/round.sh" --dir "$odd" ensure-running --port 0 >/dev/null 2>"$tmp/i.start"; then
  oport=$(sed -n 's/^PORT=//p' "$odd/.interview-session.env" | tr -d '\r')
  otoken=$(sed -n 's/^TOKEN=//p' "$odd/.interview-session.env" | tr -d '\r')
  WAIT_FAILS=1 bash "$here/watch.sh" "$odd" >"$tmp/i.out" 2>"$tmp/i.err" &
  wpid=$!
  end=$((SECONDS + 10))
  until curl -s --max-time 2 "http://127.0.0.1:$oport/api/state" | grep -q '"waiters": 1' || [[ "$SECONDS" -ge "$end" ]]; do
    sleep 0.1
  done
  code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 -H "X-Interview-Token: $otoken" \
    -H 'Content-Type: application/json' --data '{"kind": "note", "text": "odd dir note"}' \
    "http://127.0.0.1:$oport/api/answer")
  end=$((SECONDS + 10))
  while kill -0 "$wpid" 2>/dev/null && [[ "$SECONDS" -lt "$end" ]]; do
    sleep 0.1
  done
  if kill -0 "$wpid" 2>/dev/null; then kill "$wpid" 2>/dev/null; fi
  wait "$wpid"
  rc=$?
  fields=$("$py" -c '
import json, shlex, sys
d = json.loads(open(sys.argv[1], encoding="utf-8").read().strip())
t = shlex.split(d["next"])
print(d["dataDir"]); print(t[3]); print(t[6]); print(t[-1]); print(len(t)); print(d["next"])
print(d["events"][0]["seq"])
' "$tmp/i.out" 2>&1)
  line() { printf '%s\n' "$fields" | sed -n "$1p"; }
  next=$(line 6)
  if [[ "$code" == 200 && "$rc" -eq 0 && "$(line 1)" == "$odd" && "$(line 2)" == "$odd" && "$(line 3)" == "$odd/ops.json" && "$(line 4)" == "$odd" && "$(line 5)" == 11 ]]; then
    ok "next names an odd data dir as literal words"
  else
    bad "odd dir: post=$code rc=$rc fields=[$fields] out=$(cat "$tmp/i.out") err=$(cat "$tmp/i.err")"
  fi
  if bash -n -c "$next" 2>/dev/null; then ok "next for an odd data dir passes bash -n"; else bad "odd dir next fails bash -n: $next"; fi
  # Running next applies ops.json in that exact dir, then re-arms a watcher that waits.
  oseq=$(line 7)
  printf '{"ops": [{"op": "handle", "seqs": [%s]}]}\n' "$oseq" >"$odd/ops.json"
  CLAUDE_PLUGIN_ROOT="$(cd "$here/.." && pwd)" WAIT_FAILS=1 bounded 4 "$tmp/j.out" "$tmp/j.err" bash -c "$next"
  rc=$?
  if [[ "$rc" -eq 124 && "$oseq" =~ ^[0-9]+$ ]] && grep -q '^applied 1 ops' "$tmp/j.out" &&
    bash "$here/round.sh" --dir "$odd" status | grep -q "handledSeq $oseq;"; then
    ok "running next applies ops.json in the odd data dir and re-arms"
  else
    bad "odd dir next: rc=$rc seq=[$oseq] out=$(cat "$tmp/j.out") err=$(cat "$tmp/j.err")"
  fi
else
  bad "odd dir: ensure-running failed: $(cat "$tmp/i.start")"
  bad "odd dir next: not run"
  bad "odd dir next run: not run"
fi

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

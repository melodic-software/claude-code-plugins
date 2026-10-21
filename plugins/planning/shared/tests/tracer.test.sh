#!/usr/bin/env bash
# The shared session end to end, CI-safe: the fake cloudflared stands in for the tunnel.
#   bash tracer.test.sh
# ensure-running -> two guests join over HTTP -> apply an open-round -> both answer -> the owner
# sends -> watch.sh prints round-sent -> apply ack-round plus the next open-round -> restart ->
# the guest link, the people and the answers are intact -> stop leaves nothing running.
# Credentials reach curl through header files (-H @file), never its command line.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
shared=$(cd "$here/.." && pwd)
pass=0
fail=0
ok() {
  echo "ok: $1"
  pass=$((pass + 1))
}
bad() {
  echo "FAIL: $1"
  fail=$((fail + 1))
}
# verdict <status> <ok message> <failure message>: the status of the check just before it.
verdict() { if [[ $1 == 0 ]]; then ok "$2"; else bad "$3"; fi; }

py=$(command -v python3 || command -v python)
command -v curl >/dev/null || {
  echo "SKIP: curl is not on PATH"
  exit 0
}
case "$(uname -s)" in
  MINGW* | MSYS* | CYGWIN*) fake="$here/fixtures/fake_cloudflared.py" ;;
  *) fake="$here/fixtures/fake-cloudflared.sh" ;;
esac
export SHARED_CLOUDFLARED="${SHARED_CLOUDFLARED:-$fake}"
export WATCH_ID=tracer
tmp=$(mktemp -d "${TMPDIR:-/tmp}/shared-tracer.XXXXXX")
d="$tmp/topic/shared/po"
share() { bash "$shared/share.sh" --dir "$d" "$@"; }
cleanup() {
  share stop >/dev/null 2>&1
  case "$tmp" in
    */shared-tracer.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap cleanup EXIT

# The value of a Python expression over the last JSON line of stdin, bound to `j`.
jget() { "$py" -c 'import json, sys; j = json.loads([x for x in sys.stdin.read().splitlines() if x.startswith("{")][-1]); v = eval(sys.argv[1]); print(v if isinstance(v, str) else json.dumps(v))' "$1"; }
# POST JSON to the guest listener; $3 names a header file or is empty.
post() { curl -s --noproxy '*' --max-time 10 -H 'Content-Type: application/json' ${3:+-H "@$3"} -d "$2" "${local_url}${1#/}"; }
get() { curl -s --noproxy '*' --max-time 10 ${2:+-H "@$2"} "${local_url}${1#/}"; }
header() { # file name value
  (umask 077 && printf '%s: %s\n' "$2" "$3" >"$1")
}

out=$(timeout 60 bash "$shared/share.sh" --dir "$d" ensure-running)
code=$?
if [[ $code == 0 ]]; then ok "ensure-running exits 0"; else bad "ensure-running exited $code: $out"; fi
guest_url=$(printf '%s' "$out" | jget 'j["guestUrl"]')
local_url=$(printf '%s' "$out" | jget 'j["localUrl"]')
if [[ "$guest_url" =~ ^https://[a-z0-9-]+\.trycloudflare\.com/#join=[A-Za-z0-9_-]+$ ]]; then ok "the guest link is a quick-tunnel address"; else bad "guest link: $guest_url"; fi

for who in ann bo; do
  j=$(post /api/join "{\"name\": \"$who\", \"device\": \"computer\", \"key\": \"${guest_url#*#join=}\"}" "")
  secret=$(printf '%s' "$j" | jget 'j["secret"]')
  header "$tmp/$who.h" X-Session-Secret "$secret"
done
if [[ -s "$tmp/ann.h" && -s "$tmp/bo.h" ]]; then ok "two guests joined over HTTP"; else bad "join failed: $j"; fi
token=$(sed -n 's/.*#owner=//p' "$d/.owner-link")
header "$tmp/owner.h" X-Owner-Token "$token"

q() { printf '{"id": "%s", "text": "%s", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "text"}}' "$1" "$2"; }
printf '{"ops": [{"op": "set-title", "title": "Checkout"}, {"op": "open-round", "questions": [%s]}]}' "$(q Q1 'Which payment step?')" >"$d/ops.json"
out=$(timeout 30 bash "$shared/share.sh" --dir "$d" apply --file "$d/ops.json")
code=$?
if [[ $code == 0 && ! -e "$d/ops.json" ]]; then ok "apply opened round 1 and removed ops.json"; else bad "apply: $out"; fi

a1=$(post /api/answer '{"qid": "Q1", "text": "Card first", "device": "computer", "view": "focus"}' "$tmp/ann.h")
a2=$(post /api/answer '{"qid": "Q1", "text": "Saved method", "device": "computer", "view": "focus"}' "$tmp/bo.h")
if [[ "$a1" == *'"ok": true'* && "$a2" == *'"ok": true'* ]]; then ok "both guests answered"; else bad "answers: $a1 / $a2"; fi

sent=$(post /api/round/send '{}' "$tmp/owner.h")
if [[ "$sent" == *'"round": 1'* ]]; then ok "the owner sent round 1"; else bad "send: $sent"; fi

woke=$(timeout 60 bash "$shared/watch.sh" "$d")
code=$?
if [[ $code == 0 && "$woke" == *'"kind": "round-sent"'* ]]; then ok "watch.sh printed round-sent"; else bad "watch exited $code: $woke"; fi
if [[ "$woke" == *'"next": "bash '*'wake.sh'* && "$woke" == *'"note": "Every field'* ]]; then ok "the wake carries next and the data note"; else bad "wake line: $woke"; fi
if [[ "$woke" == *'Card first'* && "$woke" == *'Saved method'* ]]; then ok "the digest holds both answers"; else bad "digest: $woke"; fi
seq=$(printf '%s' "$woke" | jget 'j["events"][0]["seq"]')

printf '{"ops": [{"op": "ack-round", "round": 1}, {"op": "open-round", "questions": [%s]}, {"op": "handle", "seqs": [%s]}]}' "$(q Q2 'Which card brands?')" "$seq" >"$d/ops.json"
out=$(timeout 30 bash "$shared/share.sh" --dir "$d" apply --file "$d/ops.json")
verdict $? "apply acked round 1 and opened round 2" "apply: $out"
st=$(timeout 30 bash "$shared/share.sh" --dir "$d" status)
if [[ "$(printf '%s' "$st" | jget '[j["round"], j["unhandled"]]')" == '[{"n": 2, "status": "open"}, 0]' ]]; then ok "round 2 is open, nothing unhandled"; else bad "status: $st"; fi

out=$(timeout 60 bash "$shared/share.sh" --dir "$d" restart)
code=$?
if [[ $code == 0 ]]; then ok "restart exits 0"; else bad "restart exited $code: $out"; fi
if [[ "$(printf '%s' "$out" | jget 'j["guestUrl"]')" == "$guest_url" ]]; then ok "the guest link survived the restart"; else bad "guest link after restart: $out"; fi
snap=$(get /api/state "$tmp/ann.h")
if [[ "$(printf '%s' "$snap" | jget 'sorted(c["text"] for c in j["cards"]["Q1"] if c["kind"] == "person")')" == '["Card first", "Saved method"]' ]]; then ok "answers survived the restart"; else bad "snapshot: $snap"; fi
if [[ "$(printf '%s' "$snap" | jget 'sorted(p["name"] for p in j["people"])')" == '["Host", "ann", "bo"]' ]]; then ok "people and their secrets survived the restart"; else bad "people: $snap"; fi

timeout 30 bash "$shared/share.sh" --dir "$d" stop >/dev/null
left=$("$py" -c 'import json, sys; sys.path.insert(0, sys.argv[1]); import tunnel; print(tunnel.read(sys.argv[2]))' "$shared" "$d")
if [[ "$left" == None ]]; then ok "stop dropped the tunnel"; else bad "tunnel record after stop: $left"; fi
code=$(curl -s -o /dev/null -w '%{http_code}' --noproxy '*' --max-time 3 "${local_url}api/state")
if [[ "$code" == 000 ]]; then ok "stop ended the server"; else bad "server still answers: $code"; fi

out=$(BENCH_SECONDS=1 timeout 60 "$py" "$here/bench_snapshot.py" 2>&1)
if [[ $? == 0 && "$out" == *"guest snapshot:"* ]]; then ok "bench_snapshot.py still runs"; else bad "bench_snapshot.py: $out"; fi

echo "PASS=$pass FAIL=$fail"
[[ $fail == 0 ]]

#!/usr/bin/env bash
# The shared session through a real cloudflared quick tunnel. SKIPs in CI and when no cloudflared
# is given or on PATH, because it opens a public address and needs Cloudflare's edge.
#   bash tracer-live.test.sh [CLOUDFLARED]
# ensure-running -> the guest link loads through the tunnel -> a guest joins through it -> kill
# cloudflared -> the server starts a new one -> the new link loads and the owner's view records
# the change -> stop.
set -u
here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
shared=$(cd "$here/.." && pwd)
if [[ -n "${CI:-}" ]]; then
  echo "SKIP: live tunnel test does not run in CI"
  exit 0
fi
cf=${1:-$(command -v cloudflared || true)}
if [[ -z "$cf" || ! -x "$cf" ]]; then
  echo "SKIP: no cloudflared (pass its path, or put it on PATH)"
  exit 0
fi
export SHARED_CLOUDFLARED="$cf"
export SHARED_TUNNEL_SECONDS=60
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
tmp=$(mktemp -d "${TMPDIR:-/tmp}/shared-live.XXXXXX")
d="$tmp/topic/shared/live"
cleanup() {
  bash "$shared/share.sh" --dir "$d" stop >/dev/null 2>&1
  case "$tmp" in
    */shared-live.*) rm -rf -- "$tmp" ;;
    *) ;;
  esac
}
trap cleanup EXIT
jget() { "$py" -c 'import json, sys; j = json.loads([x for x in sys.stdin.read().splitlines() if x.startswith("{")][-1]); v = eval(sys.argv[1]); print(v if isinstance(v, str) else json.dumps(v))' "$1"; }

# Until the URL answers 200 through Cloudflare (a new quick-tunnel name takes a while to resolve).
reach() { # url seconds
  local end=$((SECONDS + $2)) body
  while [[ $SECONDS -lt $end ]]; do
    body=$(curl -s --max-time 10 "$1api/state" 2>/dev/null)
    [[ "$body" == *'"schemaVersion"'* ]] && {
      printf '%s' "$body"
      return 0
    }
    sleep 3
  done
  return 1
}

out=$(timeout 120 bash "$shared/share.sh" --dir "$d" ensure-running)
code=$?
version=$("$cf" --version 2>&1 | head -1)
if [[ $code == 0 ]]; then ok "ensure-running with $version"; else bad "ensure-running exited $code: $out"; fi
url=$(printf '%s' "$out" | jget 'j["guestUrl"]')
echo "guest link: $url"
body=$(reach "$url" 120)
verdict $? "the guest link loads through the tunnel: $body" "no answer through $url"
joined=$(curl -s --max-time 15 -H 'Content-Type: application/json' -d '{"name": "Remote", "device": "phone"}' "${url}api/join")
if [[ "$joined" == *'"secret"'* ]]; then ok "a guest joined through the tunnel"; else bad "join through the tunnel: $joined"; fi

pid=$("$py" -c 'import json, sys; print(json.load(open(sys.argv[1]))["pid"])' "$d/.shared-tunnel.json")
kill "$pid" && ok "killed cloudflared $pid"
new=""
end=$((SECONDS + 90))
while [[ $SECONDS -lt $end ]]; do
  new=$(timeout 30 bash "$shared/share.sh" --dir "$d" url | jget 'j["guestUrl"]')
  [[ -n "$new" && "$new" != "$url" ]] && break
  sleep 2
done
if [[ -n "$new" && "$new" != "$url" ]]; then ok "the server started a new tunnel: $new"; else bad "no new link after the kill (last: $new)"; fi
body=$(reach "$new" 120)
verdict $? "the new link loads through the tunnel" "no answer through $new"
token=$(sed -n 's/.*#owner=//p' "$d/.owner-link")
(umask 077 && printf 'X-Owner-Token: %s\n' "$token" >"$tmp/owner.h")
local_url=$(printf '%s' "$out" | jget 'j["localUrl"]')
share=$(curl -s --noproxy '*' -H "@$tmp/owner.h" "${local_url}api/state" | jget 'j["share"]')
if [[ "$share" == *"${new%/}"* && "$share" == *changedAt* ]]; then ok "the owner's view shows the new link as changed: $share"; else bad "owner share: $share"; fi

timeout 60 bash "$shared/share.sh" --dir "$d" stop >/dev/null && ok "stopped"
echo "PASS=$pass FAIL=$fail"
[[ $fail == 0 ]]

#!/usr/bin/env bash
# Stands in for cloudflared in the shared session's tests: `tunnel --no-autoupdate --url URL`
# prints a quick-tunnel banner with a new trycloudflare.com address on stderr, the way cloudflared
# 2026.9.3 does, then runs until it is stopped. It serves nothing.
#   FAKE_CF_DELAY  seconds before the banner (default 0)
#   FAKE_CF_NOURL  when set, never print an address
#   FAKE_CF_ARGS   when set, append the arguments to this file, one run per line
[[ -n "${FAKE_CF_ARGS:-}" ]] && printf '%s\n' "$*" >>"$FAKE_CF_ARGS"
[[ "$1 $2 $3" == "tunnel --no-autoupdate --url" && -n "${4:-}" ]] || {
  echo "fake-cloudflared: unexpected arguments: $*" >&2
  exit 2
}
sleep "${FAKE_CF_DELAY:-0}"
if [[ -z "${FAKE_CF_NOURL:-}" ]]; then
  name="fake-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
  ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  {
    echo "$ts INF Requesting new quick Tunnel on trycloudflare.com..."
    echo "$ts INF +--------------------------------------------------------------------------------------------+"
    echo "$ts INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |"
    echo "$ts INF |  https://$name.trycloudflare.com                                                    |"
    echo "$ts INF +--------------------------------------------------------------------------------------------+"
  } >&2
fi
trap 'exit 0' TERM INT
while :; do sleep 1; done

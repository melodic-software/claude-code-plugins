#!/usr/bin/env bash
# Stderr as https://github.com/cloudflare/cloudflared/blob/2026.9.3/connection/observer.go and
# https://github.com/cloudflare/cloudflared/blob/2026.9.3/cmd/cloudflared/tunnel/configuration.go log it
[[ -n "${FAKE_CF_ARGS:-}" ]] && printf '%s\n' "$*" >>"$FAKE_CF_ARGS"
if [[ -n "${TUNNEL_TOKEN:-}${TUNNEL_TOKEN_FILE:-}${CLOUDFLARE_API_TOKEN:-}${CF_API_TOKEN:-}" ]]; then
  echo "fake-cloudflared: a token variable was inherited" >&2
  exit 2
fi
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
if [[ "$1 $2 $3 $4" == "tunnel --no-autoupdate run --token-file" && -n "${5:-}" ]]; then
  [[ -r "$5" && -s "$5" ]] || {
    echo "$ts ERR cannot read the tunnel token file $5" >&2
    exit 1
  }
  echo "$ts INF Generated Connector ID: ${FAKE_CF_CONNECTOR:-00000000-0000-4000-8000-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')}" >&2
  sleep "${FAKE_CF_DELAY:-0}"
  [[ -z "${FAKE_CF_NOURL:-}" ]] &&
    echo "$ts INF Registered tunnel connection connIndex=0 connection=00000000-0000-4000-8000-000000000000 event=0 ip=192.0.2.10 location=fake01 protocol=quic" >&2
  trap 'exit 0' TERM INT
  while :; do sleep 1; done
fi
[[ "$1 $2 $3" == "tunnel --no-autoupdate --url" && -n "${4:-}" ]] || {
  echo "fake-cloudflared: unexpected arguments: $*" >&2
  exit 2
}
sleep "${FAKE_CF_DELAY:-0}"
if [[ -z "${FAKE_CF_NOURL:-}" ]]; then
  name="fake-$(od -An -N6 -tx1 /dev/urandom | tr -d ' \n')"
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

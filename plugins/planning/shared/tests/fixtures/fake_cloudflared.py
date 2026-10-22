"""fake-cloudflared.sh for hosts without bash on PATH for a spawned script (Windows): same
arguments (the quick and the named form), same output, same knobs (FAKE_CF_DELAY, FAKE_CF_NOURL, FAKE_CF_ARGS)."""

import os
import secrets
import sys
import time

args = sys.argv[1:]
if os.environ.get("FAKE_CF_ARGS"):
    with open(os.environ["FAKE_CF_ARGS"], "a", encoding="utf-8") as f:
        f.write(" ".join(args) + "\n")
if any(os.environ.get(k) for k in ("TUNNEL_TOKEN", "TUNNEL_TOKEN_FILE", "CLOUDFLARE_API_TOKEN", "CF_API_TOKEN")):
    sys.exit("fake-cloudflared: a token variable was inherited")
ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
if args[:4] == ["tunnel", "--no-autoupdate", "run", "--token-file"] and len(args) > 4:
    try:
        with open(args[4], "rb") as f:
            ok = bool(f.read(1))
    except OSError:
        ok = False
    if not ok:
        print(f"{ts} ERR cannot read the tunnel token file {args[4]}", file=sys.stderr)
        sys.exit(1)
    time.sleep(float(os.environ.get("FAKE_CF_DELAY") or 0))
    if not os.environ.get("FAKE_CF_NOURL"):
        print(f"{ts} INF Registered tunnel connection connIndex=0 connection=00000000-0000-4000-8000-000000000000 event=0 ip=192.0.2.10 location=fake01 protocol=quic", file=sys.stderr, flush=True)
    while True:
        time.sleep(1)
if args[:3] != ["tunnel", "--no-autoupdate", "--url"] or len(args) < 4:
    sys.exit(f"fake-cloudflared: unexpected arguments: {' '.join(args)}")
time.sleep(float(os.environ.get("FAKE_CF_DELAY") or 0))
if not os.environ.get("FAKE_CF_NOURL"):
    print(f"{ts} INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |", file=sys.stderr)
    print(f"{ts} INF |  https://fake-{secrets.token_hex(6)}.trycloudflare.com  |", file=sys.stderr, flush=True)
while True:
    time.sleep(1)

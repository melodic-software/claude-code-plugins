"""fake-cloudflared.sh for hosts without bash on PATH for a spawned script (Windows): same
arguments, same banner, same knobs (FAKE_CF_DELAY, FAKE_CF_NOURL, FAKE_CF_ARGS)."""

import os
import secrets
import sys
import time

args = sys.argv[1:]
if os.environ.get("FAKE_CF_ARGS"):
    with open(os.environ["FAKE_CF_ARGS"], "a", encoding="utf-8") as f:
        f.write(" ".join(args) + "\n")
if args[:3] != ["tunnel", "--no-autoupdate", "--url"] or len(args) < 4:
    sys.exit(f"fake-cloudflared: unexpected arguments: {' '.join(args)}")
time.sleep(float(os.environ.get("FAKE_CF_DELAY") or 0))
if not os.environ.get("FAKE_CF_NOURL"):
    ts = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    print(f"{ts} INF |  Your quick Tunnel has been created! Visit it at (it may take some time to be reachable):  |", file=sys.stderr)
    print(f"{ts} INF |  https://fake-{secrets.token_hex(6)}.trycloudflare.com  |", file=sys.stderr, flush=True)
while True:
    time.sleep(1)

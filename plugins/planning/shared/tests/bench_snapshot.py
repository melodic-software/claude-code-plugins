"""What one guest page downloads while a session sits idle: 20 people, 500 chat messages.

Seeds the session, then for BENCH_SECONDS (default 30) every person's page beats every 2 s, as an open tab
does, while one guest page polls /api/state every 1.5 s with its ETag, and nobody writes. Prints the guest
snapshot's size (raw and gzip), how many polls got 304, a presence-only answer or the full snapshot, how
often the ETag changed, and the bytes the poller read. A benchmark, not a test: it asserts nothing.
    python3 plugins/planning/shared/tests/bench_snapshot.py
"""

from __future__ import annotations

import gzip
import json
import os
import shutil
import sys
import tempfile
import threading
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from support import call  # noqa: E402  (sys.path is set just above)

import server  # noqa: E402

PEOPLE = 20
MESSAGES = 500
BEAT_EVERY = 2.0  # core.js setInterval(beat, 2000)
POLL_EVERY = 1.5  # core.js setInterval(poll, 1500)


def ip(i):
    return {"CF-Connecting-IP": f"198.51.100.{i}"}


def seed(app):
    port = app.guest_port
    people = []
    for i in range(1, PEOPLE + 1):
        _, _, out = call(port, "POST", "/api/join", {"name": f"Person {i}", "device": "computer"}, ip(i))
        people.append({"X-Session-Secret": out["secret"], **ip(i)})
    real = app.session.clock
    t = [real() - MESSAGES * 1.1 - 100]  # the past, so every person's write limit has passed when the run starts
    app.session.clock = lambda: t[0]
    pids = [app.session.resolve(secret=h["X-Session-Secret"]) for h in people]
    for n in range(MESSAGES):
        t[0] += 1.1
        app.session.chat(pids[n % PEOPLE], {"text": f"Message {n + 1}: a line of chat about the payment step, long enough to read like one."})
    app.session.clock = real
    return people


def main():
    seconds = float(os.environ.get("BENCH_SECONDS") or 30)
    d = Path(tempfile.mkdtemp(prefix="shared-bench-"))
    app = server.App(d, watch_tunnel=False)
    app.serve()
    try:
        people = seed(app)
        port = app.guest_port
        _, _, snap = call(port, "GET", "/api/state?since=0", headers=people[0])
        raw = json.dumps(snap).encode()
        print(f"guest snapshot: {len(raw)} bytes raw, {len(gzip.compress(raw))} gzip, {len(snap.get('chat', []))} chat messages")
        stop = threading.Event()

        def page(h, k):
            nxt = time.monotonic() + k * BEAT_EVERY / PEOPLE
            while not stop.is_set():
                if time.monotonic() >= nxt:
                    call(port, "POST", "/api/heartbeat", {"q": "", "typing": False, "chatTyping": False, "visible": True, "lastInput": 5, "tab": f"t{k}"}, h)
                    nxt += BEAT_EVERY
                time.sleep(0.02)

        beaters = [threading.Thread(target=page, args=(h, k), daemon=True) for k, h in enumerate(people)]
        for b in beaters:
            b.start()
        counts = {"304": 0, "presence-only": 0, "full": 0}
        tags, read, rev, tag = set(), 0, snap["rev"], ""
        end = time.monotonic() + seconds
        while time.monotonic() < end:
            code, headers, body = call(port, "GET", f"/api/state?since={rev}", headers={**people[0], **({"If-None-Match": tag} if tag else {})})
            if code == 304:
                counts["304"] += 1
            else:
                read += len(json.dumps(body).encode())
                counts["presence-only" if body.get("presenceOnly") else "full"] += 1
                rev = body["rev"]
            tag = headers.get("ETag", tag)
            tags.add(tag)
            time.sleep(POLL_EVERY)
        stop.set()
        polls = sum(counts.values())
        print(f"idle {seconds:.0f} s, {PEOPLE} pages beating: {polls} polls: {counts['304']} not modified, {counts['presence-only']} presence-only, {counts['full']} full")
        print(f"ETag changed {len(tags) - 1} times; poller read {read} bytes ({read / seconds:.0f} bytes/s)")
    finally:
        app.shutdown()
        shutil.rmtree(d, ignore_errors=True)


if __name__ == "__main__":
    main()

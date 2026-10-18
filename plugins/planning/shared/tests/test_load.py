"""20 people writing once a second each, while each page polls /api/state every 1.5 s.

The figure in README.md "Load" comes from this test: it prints the p95 write latency. The bound
it asserts is a ceiling for a failure, not the figure: a write slower than a second at p95 means
people see their answers lag behind their typing. SHARED_LOAD_SECONDS sets the run (default 10).
"""

from __future__ import annotations

import os
import statistics
import threading
import time
import unittest

from support import call, tmpdir

import server

PEOPLE = 20
WRITE_EVERY = 1.05  # just over the one-write-per-second-per-route limit (Contracts, "Body caps and limits")
POLL_EVERY = 1.5  # the page's poll interval (Contracts, "Guest listener routes")
P95_CEILING = 1.0  # judgment: far above the measured 1.7 ms p95, so it catches a regression, not noise


class TestLoad(unittest.TestCase):
    def test_twenty_people_writing_once_a_second(self):
        d = tmpdir(self)
        app = server.App(d, watch_tunnel=False)
        app.serve()
        self.addCleanup(app.shutdown)
        port = app.guest_port
        q = {"id": "Q1", "text": "Which payment step?", "alternatives": [], "dependsOn": [], "purpose": "decide", "format": {"kind": "text"}}
        app.session.apply({"ops": [{"op": "open-round", "questions": [q]}]})
        seconds = float(os.environ.get("SHARED_LOAD_SECONDS") or 10)
        latencies, failures, lock = [], [], threading.Lock()

        def person(i):
            code, _, out = call(port, "POST", "/api/join", {"name": f"Person {i}", "device": "phone"}, {"CF-Connecting-IP": f"198.51.100.{i}"})
            if code != 200:
                failures.append(("join", code, out))
                return
            me = {"X-Session-Secret": out["secret"], "CF-Connecting-IP": f"198.51.100.{i}"}
            end = time.monotonic() + seconds
            next_write = time.monotonic() + (i % 10) / 10
            next_poll = time.monotonic()
            n = 0
            while time.monotonic() < end:
                now = time.monotonic()
                if now >= next_poll:
                    call(port, "GET", "/api/state", headers=me)
                    next_poll += POLL_EVERY
                if now >= next_write:
                    n += 1
                    t0 = time.perf_counter()
                    code, _, out = call(port, "POST", "/api/answer", {"qid": "Q1", "text": f"Answer {n} from {i}", "device": "phone", "view": "focus"}, me)
                    took = time.perf_counter() - t0
                    with lock:
                        (latencies if code == 200 else failures).append(took if code == 200 else ("answer", code, out))
                    next_write = time.monotonic() + WRITE_EVERY  # from the answer, so a late write never lands under the limit
                time.sleep(0.01)

        threads = [threading.Thread(target=person, args=(i,)) for i in range(1, PEOPLE + 1)]
        for t in threads:
            t.start()
        for t in threads:
            t.join(seconds + 60)
        self.assertEqual(failures, [])
        self.assertGreaterEqual(len(latencies), PEOPLE * int(seconds / WRITE_EVERY) * 0.9)
        p95 = statistics.quantiles(latencies, n=20)[-1]
        print(f"\nload: {PEOPLE} people, {len(latencies)} writes in {seconds:.0f} s, p50 {statistics.median(latencies) * 1000:.1f} ms, p95 {p95 * 1000:.1f} ms")
        self.assertLess(p95, P95_CEILING)


if __name__ == "__main__":
    unittest.main()

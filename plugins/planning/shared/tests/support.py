"""Helpers the shared session's runtime suites share: the fake cloudflared, HTTP calls, a server
App in this process, and share.py in a child process."""

from __future__ import annotations

import http.client
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SHARED = HERE.parent
FIXTURES = HERE / "fixtures"
if str(SHARED) not in sys.path:
    sys.path.insert(0, str(SHARED))

WINDOWS = os.name == "nt"
# The bash fake on POSIX; on Windows a spawned .sh needs bash, so the Python fake stands in.
FAKE = str(FIXTURES / ("fake_cloudflared.py" if WINDOWS else "fake-cloudflared.sh"))
SHARE = SHARED / "share.py"


def tmpdir(case):
    d = Path(tempfile.mkdtemp(prefix="shared-test-"))
    case.addCleanup(shutil.rmtree, d, ignore_errors=True)
    return d


def call(port, method, path, body=None, headers=None, raw=None, timeout=10):
    """(status, headers, parsed body or raw bytes) for one request to 127.0.0.1:port."""
    conn = http.client.HTTPConnection("127.0.0.1", port, timeout=timeout)
    try:
        h = {"Host": f"127.0.0.1:{port}"}
        if body is not None:
            raw = json.dumps(body).encode("utf-8")
            h["Content-Type"] = "application/json"
        h.update(headers or {})
        conn.putrequest(method, path, skip_host=True, skip_accept_encoding=True)
        for k, v in h.items():
            conn.putheader(k, v)
        if raw is not None and "Content-Length" not in h:
            conn.putheader("Content-Length", str(len(raw)))
        conn.endheaders(raw)
        resp = conn.getresponse()
        data = resp.read()
        try:
            parsed = json.loads(data) if data else None
        except ValueError:
            parsed = data
        return resp.status, dict(resp.getheaders()), parsed
    finally:
        conn.close()


def wait_for(predicate, seconds=10.0, step=0.1):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        got = predicate()
        if got:
            return got
        time.sleep(step)
    return predicate()


def env(**extra):
    out = dict(os.environ, SHARED_CLOUDFLARED=FAKE, SHARED_TUNNEL_SECONDS="10")
    out.update({k: v for k, v in extra.items() if v is not None})
    for k in [k for k, v in extra.items() if v is None]:
        out.pop(k, None)
    return out


def share(d, *args, environ=None, timeout=90):
    """Run share.py; (exit code, the last JSON line on stdout or None, stderr)."""
    cmd = [sys.executable, str(SHARE)] + (["--dir", str(d)] if d is not None else []) + list(args)
    p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, env=environ or env())
    lines = [x for x in p.stdout.splitlines() if x.startswith("{")]
    return p.returncode, (json.loads(lines[-1]) if lines else None), p.stderr


class ShareCase(unittest.TestCase):
    """A data dir whose server and tunnel are stopped after the test, whatever it did."""

    def setUp(self):
        self.root = tmpdir(self)
        self.d = self.root / "topic" / "shared" / "po"
        self.addCleanup(self.stop_all)

    def stop_all(self):
        if self.d.is_dir():
            share(self.d, "stop")

    def session_record(self):
        return json.loads((self.d / ".shared-session.json").read_text(encoding="utf-8"))

    def owner_token(self):
        return (self.d / ".owner-link").read_text(encoding="utf-8").strip().split("#owner=", 1)[1]

    def guest_port(self):
        return json.loads((self.d / ".shared-ports.json").read_text(encoding="utf-8"))["guest"]

    def control(self, method, path, body=None):
        s = self.session_record()
        return call(s["port"], method, path, body, {"X-Shared-Token": s["token"]})

"""Helpers the shared session's runtime suites share: the fake cloudflared, HTTP calls, a server
App in this process, and share.py in a child process."""

from __future__ import annotations

import http.client
import json
import os
import re
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

import detached  # noqa: E402  (sys.path is set just above)

WINDOWS = os.name == "nt"
# The bash fake on POSIX; on Windows a spawned .sh needs bash, so the Python fake stands in.
FAKE = str(FIXTURES / ("fake_cloudflared.py" if WINDOWS else "fake-cloudflared.sh"))
SHARE = SHARED / "share.py"


FIXTURE_TOKEN_HASH = "0" * 63 + "1"  # every fixture's owner tokenHash: low entropy, so secret scanners pass it


def write_state_fixture(state, name, folder=FIXTURES):
    """Save a state a build's session.py wrote (Session.state) as fixtures/<name>, for the forward-compatibility
    tests that load it unchanged: its owner tokenHash becomes FIXTURE_TOKEN_HASH, as no fixture test opens the owner
    view with the token that made it."""
    doc = json.loads(json.dumps(state))
    doc["credentials"]["owner"]["tokenHash"] = FIXTURE_TOKEN_HASH
    (Path(folder) / name).write_text(json.dumps(doc, ensure_ascii=False) + "\n", encoding="utf-8")


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


def outside_cloudflared(case, url_arg, log, *extra, named=True, environ=None):
    """(Popen, its trycloudflare.com address): a fake cloudflared started outside tunnel.py, as the
    prototype's is, run as `tunnel --no-autoupdate --url <url_arg> <extra...>`. With `named`, the
    program the OS reports for it is a file named cloudflared (cloudflared.exe on Windows), which
    adopt requires: on POSIX a copy of bash running fake-cloudflared.sh, on Windows a copy of the
    base Python, with its DLLs, running fake_cloudflared.py. Without, it runs FAKE as is (bash or
    python, with "cloudflared" only in its arguments). Skips when the copy cannot run here."""
    args = ["tunnel", "--no-autoupdate", "--url", url_arg, *extra]
    environ = dict(environ or os.environ)
    if not named:
        cmd = [sys.executable, FAKE] if FAKE.endswith(".py") else [FAKE]
    elif WINDOWS:
        base = Path(detached.interpreter())
        where = tmpdir(case)
        for dll in base.parent.glob("*.dll"):
            shutil.copy2(dll, where / dll.name)
        cmd = [str(shutil.copy2(base, where / "cloudflared.exe")), FAKE]
        environ["PYTHONHOME"] = sys.base_prefix
    else:
        cmd = [str(shutil.copy2(os.path.realpath(shutil.which("bash")), tmpdir(case) / "cloudflared")), FAKE]
    proc =detached.spawn([*cmd, *args], log=log, env=environ)
    case.addCleanup(lambda: (proc.kill(), proc.wait()))
    url = wait_for(lambda: (m := re.search(r"https://fake-[0-9a-f]{12}\.trycloudflare\.com", log.read_text(encoding="utf-8", errors="replace"))) and m.group(0))
    if not url and named:
        case.skipTest(f"a program named cloudflared could not run here: {log.read_text(encoding='utf-8', errors='replace')[-300:]}")
    case.assertTrue(url)
    return proc, url


def env(**extra):
    out = dict(os.environ, SHARED_CLOUDFLARED=FAKE, SHARED_TUNNEL_SECONDS="10")
    out.update({k: v for k, v in extra.items() if v is not None})
    for k in [k for k, v in extra.items() if v is None]:
        out.pop(k, None)
    return out


def share(d, *args, environ=None, timeout=90):
    """Run share.py; (exit code, the last JSON line on stdout or None, stderr)."""
    cmd = [sys.executable, str(SHARE)] + (["--dir", str(d)] if d is not None else []) + list(args)
    p = subprocess.run(cmd, capture_output=True, encoding="utf-8", timeout=timeout, env=environ or env())
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

"""cfdns.py: the zone listing, the planned record, the confirm-gated write and the connector check, against a fake API.

The fake answers in the shapes Cloudflare's API reference documents (`success`, `errors`, `result`,
`result_info.total_pages`; a connection's `id`, `version`, `run_at` and `conns[].origin_ip`), and the
planned record is the one step 3 of the create-remote-tunnel-api guide shows: a proxied CNAME to
<tunnel-id>.cfargotunnel.com. No test reaches the network or writes real DNS.
"""

from __future__ import annotations

import contextlib
import io
import json
import os
import threading
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from unittest import mock
from urllib.parse import parse_qs, urlsplit

from support import tmpdir

import cfdns

ZONE = "0123456789abcdef0123456789abcdef"
ACCOUNT = "fedcba9876543210fedcba9876543210"
TUNNEL = "c0ffee00-0000-4000-8000-000000000001"
HOST = "interview.example.com"
TOKEN = "fake-api-token-for-tests"
PLANNED = {"type": "CNAME", "name": HOST, "content": f"{TUNNEL}.cfargotunnel.com", "proxied": True}


class FakeApi:
    """A Cloudflare API stand-in on 127.0.0.1: zone records in pages of the requested size, record creation, connections."""

    def __init__(self, records=(), connectors=()):
        self.records, self.connectors, self.calls = list(records), list(connectors), []
        api = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *args):
                pass

            def answer(self, code, doc):
                body = json.dumps(doc).encode()
                self.send_response(code)
                self.send_header("Content-Type", "application/json")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)

            def handle_one(self, method):
                url = urlsplit(self.path)
                body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"null")
                api.calls.append((method, url.path, body))
                if self.headers.get("Authorization") != f"Bearer {TOKEN}":
                    return self.answer(403, {"success": False, "errors": [{"code": 10000, "message": "Authentication error"}], "result": None})
                if url.path == f"/zones/{ZONE}/dns_records" and method == "GET":
                    q = {k: int(v[0]) for k, v in parse_qs(url.query).items()}
                    per, page = q["per_page"], q["page"]
                    pages = max(1, -(-len(api.records) // per))
                    return self.answer(200, {"success": True, "errors": [], "result": api.records[(page - 1) * per : page * per], "result_info": {"page": page, "per_page": per, "total_pages": pages}})
                if url.path == f"/zones/{ZONE}/dns_records" and method == "POST":
                    rec = {"id": f"r{len(api.records)}", **body}
                    api.records.append(rec)
                    return self.answer(200, {"success": True, "errors": [], "result": rec})
                if url.path == f"/accounts/{ACCOUNT}/cfd_tunnel/{TUNNEL}/connections" and method == "GET":
                    return self.answer(200, {"success": True, "errors": [], "result": api.connectors})
                return self.answer(404, {"success": False, "errors": [{"code": 7003, "message": "No route for that URI"}], "result": None})

            def do_GET(self):
                self.handle_one("GET")

            def do_POST(self):
                self.handle_one("POST")

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        threading.Thread(target=self.server.serve_forever, daemon=True).start()
        self.url = f"http://127.0.0.1:{self.server.server_address[1]}"

    def close(self):
        self.server.shutdown()
        self.server.server_close()

    def posts(self):
        return [c for c in self.calls if c[0] == "POST"]


def filler(n):
    return [{"id": f"f{i}", "type": "A", "name": f"host{i}.example.com", "content": "192.0.2.1", "proxied": False} for i in range(n)]


class CfdnsCase(unittest.TestCase):
    def setUp(self):
        self.token_file = tmpdir(self) / "api.token"
        self.token_file.write_text(TOKEN + "\n", encoding="utf-8")

    def api(self, **kw):
        fake = FakeApi(**kw)
        self.addCleanup(fake.close)
        return fake

    def run_cli(self, fake, *args, token_file=None):
        """(exit code, the JSON line on stdout or None, stderr)."""
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"SHARED_CF_API": fake.url}), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cfdns.main([*args, "--api-token-file", str(token_file or self.token_file)])
        self.assertNotIn(TOKEN, out.getvalue() + err.getvalue())
        return code, (json.loads(out.getvalue()) if out.getvalue() else None), err.getvalue()

    def plan(self, fake, *extra):
        return self.run_cli(fake, "plan", "--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", TUNNEL, *extra)

    def write(self, fake, confirm=HOST):
        return self.run_cli(fake, "write", "--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", TUNNEL, "--confirm", confirm)


class TestPlan(CfdnsCase):
    def test_it_lists_every_page_and_shows_the_one_planned_record_with_no_clash(self):
        fake = self.api(records=filler(150))
        code, out, err = self.plan(fake)
        self.assertEqual(code, 0, err)
        self.assertEqual((out["zoneRecords"], out["planned"], out["named"], out["clash"], out["inPlace"]), (150, PLANNED, [], False, False))
        self.assertEqual(fake.posts(), [])

    def test_a_record_already_named_the_hostname_is_a_clash(self):
        other = {"id": "x", "type": "A", "name": HOST, "content": "192.0.2.9", "proxied": True}
        fake = self.api(records=filler(120) + [other])
        code, out, _ = self.plan(fake)
        self.assertEqual((code, out["clash"], [r["id"] for r in out["named"]]), (4, True, ["x"]))
        self.assertEqual(fake.posts(), [])

    def test_the_record_already_in_place_is_no_clash(self):
        fake = self.api(records=[{"id": "y", **PLANNED}])
        code, out, _ = self.plan(fake)
        self.assertEqual((code, out["inPlace"], out["clash"]), (0, True, False))

    def test_a_refused_token_is_an_api_error_with_exit_1(self):
        wrong = tmpdir(self) / "wrong.token"
        wrong.write_text("not-the-token", encoding="utf-8")
        code, out, err = self.run_cli(self.api(), "plan", "--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", TUNNEL, token_file=wrong)
        self.assertEqual((code, out), (1, None))
        self.assertIn("Authentication error", err)

    def test_no_token_is_refused_before_any_request(self):
        fake = self.api()
        out, err = io.StringIO(), io.StringIO()
        with mock.patch.dict(os.environ, {"SHARED_CF_API": fake.url, "CLOUDFLARE_API_TOKEN": ""}), contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = cfdns.main(["plan", "--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", TUNNEL])
        self.assertEqual(code, 1)
        self.assertIn("no API token", err.getvalue())
        self.assertEqual(fake.calls, [])

    def test_the_token_may_come_from_cloudflare_api_token(self):
        fake = self.api()
        out = io.StringIO()
        with mock.patch.dict(os.environ, {"SHARED_CF_API": fake.url, "CLOUDFLARE_API_TOKEN": TOKEN}), contextlib.redirect_stdout(out):
            self.assertEqual(cfdns.main(["plan", "--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", TUNNEL]), 0)
        self.assertNotIn(TOKEN, out.getvalue())

    def test_bad_ids_and_hostnames_are_refused_before_any_request(self):
        fake = self.api()
        for args in (["--zone-id", "nope", "--hostname", HOST, "--tunnel-id", TUNNEL], ["--zone-id", ZONE, "--hostname", f"https://{HOST}", "--tunnel-id", TUNNEL], ["--zone-id", ZONE, "--hostname", HOST, "--tunnel-id", "nope"]):
            with self.subTest(args=args):
                self.assertEqual(self.run_cli(fake, "plan", *args)[0], 1)
        self.assertEqual(fake.calls, [])


class TestWrite(CfdnsCase):
    def test_without_the_hostname_repeated_nothing_is_requested(self):
        fake = self.api()
        code, _, err = self.write(fake, confirm="yes")
        self.assertEqual(code, 1)
        self.assertIn("--confirm must repeat the hostname", err)
        self.assertEqual(fake.calls, [])

    def test_the_confirmed_write_creates_exactly_the_planned_record_once(self):
        fake = self.api(records=filler(3))
        code, out, err = self.write(fake)
        self.assertEqual(code, 0, err)
        self.assertEqual([(p[1], p[2]) for p in fake.posts()], [(f"/zones/{ZONE}/dns_records", PLANNED)])
        self.assertEqual((out["written"], out["record"]["name"], out["record"]["content"]), (True, HOST, PLANNED["content"]))

    def test_a_clash_writes_nothing(self):
        fake = self.api(records=[{"id": "x", "type": "CNAME", "name": HOST, "content": "elsewhere.example.net", "proxied": True}])
        code, out, _ = self.write(fake)
        self.assertEqual((code, out["written"]), (4, False))
        self.assertEqual(fake.posts(), [])

    def test_a_record_already_in_place_is_not_written_again(self):
        fake = self.api(records=[{"id": "y", **PLANNED}])
        code, out, _ = self.write(fake)
        self.assertEqual((code, out["written"], out["inPlace"]), (0, False, True))
        self.assertEqual(fake.posts(), [])


class TestConnectors(CfdnsCase):
    def connector(self, cid, ip):
        return {"id": cid, "version": "2026.10.2", "run_at": "2026-10-21T00:00:00Z", "conns": [{"origin_ip": ip, "colo_name": "fake01"}]}

    def connectors(self, fake):
        return self.run_cli(fake, "connectors", "--account-id", ACCOUNT, "--tunnel-id", TUNNEL)

    def test_one_machine_is_no_clash(self):
        code, out, err = self.connectors(self.api(connectors=[self.connector("a", "192.0.2.1")]))
        self.assertEqual((code, out["count"], out["clash"], out["connectors"][0]["originIps"]), (0, 1, False, ["192.0.2.1"]), err)

    def test_two_machines_running_the_tunnel_are_a_clash(self):
        code, out, _ = self.connectors(self.api(connectors=[self.connector("a", "192.0.2.1"), self.connector("b", "198.51.100.7")]))
        self.assertEqual((code, out["count"], out["clash"]), (4, 2, True))


if __name__ == "__main__":
    unittest.main()

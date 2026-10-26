"""Two-process eval fixture: an app that signs users in through a stub identity server.

Roles, each its own process:
  serve.py idp --port N                     identity server stub
  serve.py app --port N --identity URL      app whose /login redirects to the identity server
  serve.py --self-test                      start both on free ports, check the sign-in chain, stop both

Standard library only, so it runs under `python3 -I`.
"""

import argparse
import json
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CODE = "fixture-code"
SESSION = "session=signed-in"


def make_handler(role, identity):
    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *args):
            pass

        def send(self, status, body=b"", headers=()):
            self.send_response(status)
            for name, value in headers:
                self.send_header(name, value)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            url = urllib.parse.urlsplit(self.path)
            query = urllib.parse.parse_qs(url.query)
            if url.path == "/health":
                status = {"role": role}
                if role == "app":
                    status["identity"] = identity
                self.send(200, json.dumps(status).encode())
            elif role == "idp" and url.path == "/authorize":
                back = query.get("redirect_uri", [""])[0]
                u = urllib.parse.urlsplit(back)
                if (u.scheme, u.hostname, u.username) != ("http", "127.0.0.1", None) or (
                    "\r" in back or "\n" in back
                ):
                    self.send(400, b"redirect_uri must be a loopback URL")
                    return
                self.send(302, headers=[("Location", f"{back}?code={CODE}")])
            elif role == "app" and url.path == "/login":
                back = f"http://127.0.0.1:{self.server.server_address[1]}/callback"
                target = f"{identity}/authorize?" + urllib.parse.urlencode(
                    {"redirect_uri": back}
                )
                self.send(302, headers=[("Location", target)])
            elif role == "app" and url.path == "/callback":
                if query.get("code") != [CODE]:
                    self.send(401, b"bad code")
                    return
                self.send(200, b"signed in", [("Set-Cookie", SESSION)])
            else:
                self.send(404)

    return Handler


def serve(role, port, identity):
    server = ThreadingHTTPServer(("127.0.0.1", port), make_handler(role, identity))
    print(server.server_address[1], flush=True)
    server.serve_forever()


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args):
        return None


def get(url):
    opener = urllib.request.build_opener(NoRedirect)
    try:
        with opener.open(url, timeout=5) as response:
            return response.status, dict(response.headers), response.read()
    except urllib.error.HTTPError as error:
        return error.code, dict(error.headers), error.read()


def start(*role_args):
    proc = subprocess.Popen(
        [sys.executable, "-I", __file__, *role_args, "--port", "0"],
        stdout=subprocess.PIPE,
        text=True,
    )
    deadline = time.monotonic() + 10
    line = ""
    while not line and time.monotonic() < deadline and proc.poll() is None:
        line = proc.stdout.readline().strip()
    if not line.isdigit():
        proc.kill()
        raise SystemExit(f"self-test: {role_args[0]} did not report its port")
    return proc, f"http://127.0.0.1:{line}"


def check(condition, message):
    if not condition:
        raise SystemExit(f"self-test: {message}")


def self_test():
    procs = []
    try:
        idp, idp_url = start("idp")
        procs.append(idp)
        app, app_url = start("app", "--identity", idp_url)
        procs.append(app)

        status, _, body = get(f"{app_url}/health")
        check(status == 200, f"app /health returned {status}")
        check(
            json.loads(body).get("identity") == idp_url,
            "app does not report the identity server it sends to",
        )
        status, _, _ = get(f"{idp_url}/health")
        check(status == 200, f"identity /health returned {status}")

        status, headers, _ = get(f"{app_url}/login")
        check(status == 302, f"app /login returned {status}, expected 302")
        location = headers.get("Location", "")
        check(
            location.startswith(f"{idp_url}/authorize?"),
            f"app /login redirects to {location!r}",
        )

        status, headers, _ = get(location)
        check(status == 302, f"identity /authorize returned {status}, expected 302")
        callback = headers.get("Location", "")
        check(
            callback == f"{app_url}/callback?code={CODE}",
            f"identity redirects to {callback!r}",
        )

        status, headers, _ = get(callback)
        check(status == 200, f"app /callback returned {status}")
        check(
            headers.get("Set-Cookie") == SESSION,
            "app set no session after the callback",
        )

        status, _, _ = get(f"{app_url}/callback?code=wrong")
        check(status == 401, f"app accepted a wrong code with {status}")

        for bad in ("http://127.0.0.1:@evil.example/cb", "http://127.0.0.1:1/x\r\nX: y"):
            query = urllib.parse.urlencode({"redirect_uri": bad})
            status, _, _ = get(f"{idp_url}/authorize?{query}")
            check(status == 400, f"identity /authorize accepted {bad!r} with {status}")
    finally:
        for proc in procs:
            proc.terminate()
        for proc in procs:
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=5)
    print("self-test: ok")


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("role", nargs="?", choices=["app", "idp"])
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--identity", default="")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.role == "app" and not args.identity:
        parser.error("app needs --identity URL")
    elif args.role:
        serve(args.role, args.port, args.identity.rstrip("/"))
    else:
        parser.error("give a role or --self-test")


if __name__ == "__main__":
    main()

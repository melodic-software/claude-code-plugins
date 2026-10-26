"""Two-process eval fixture: an app that signs users in through a stub identity server.

Roles, each its own process:
  serve.py idp --port N | --url URL         identity server stub
  serve.py app --port N | --url URL --identity URL
                                            app whose /login redirects to the identity server
  serve.py health URL                       read URL/health; exit 0 on 200
  serve.py --self-test                      start both on free ports, check the sign-in chain, stop both

Standard library only, so it runs under `python3 -I`.
"""

import argparse
import json
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CODE = "fixture-code"
SESSION = "session=signed-in"
SHELL_CHARS = "$`'\"\\;|<>"


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


def http_url(value):
    """argparse type: an http(s) URL with a host and no whitespace, control or shell character."""
    if any(c.isspace() or ord(c) < 32 or ord(c) == 127 or c in SHELL_CHARS for c in value):
        raise argparse.ArgumentTypeError(
            f"{value!r} holds whitespace, a control character or a shell character"
        )
    try:
        u = urllib.parse.urlsplit(value)
        u.port
    except ValueError as error:
        raise argparse.ArgumentTypeError(f"{value!r}: {error}") from None
    if u.scheme not in ("http", "https") or not u.hostname:
        raise argparse.ArgumentTypeError(f"{value!r} is not an http or https URL")
    return value


def listen_port(url):
    """The loopback port a --url names."""
    u = urllib.parse.urlsplit(url)
    if u.hostname not in ("127.0.0.1", "localhost") or u.port is None:
        raise SystemExit(f"{url!r} must name a loopback host and a port")
    return u.port


def health(url):
    status, _, body = get(f"{url.rstrip('/')}/health")
    print(body.decode(errors="replace"))
    return 0 if status == 200 else 1


def free_port():
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        return probe.getsockname()[1]


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
    port_args = [] if "--url" in role_args else ["--port", "0"]
    proc = subprocess.Popen(
        [sys.executable, "-I", __file__, *role_args, *port_args],
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

        done = subprocess.run(
            [sys.executable, "-I", __file__, "health", idp_url],
            capture_output=True,
            text=True,
            timeout=10,
        )
        check(done.returncode == 0 and '"idp"' in done.stdout, "health did not read the idp")

        port = free_port()
        by_url, by_url_root = start("idp", "--url", f"http://127.0.0.1:{port}")
        procs.append(by_url)
        check(by_url_root == f"http://127.0.0.1:{port}", "--url did not set the listen port")

        for bad in (
            "file:///etc/passwd",
            "http://",
            f"{idp_url} --port 1",
            "http://127.0.0.1:x",
            "http://127.0.0.1:1/$(id)",
            "http://127.0.0.1:1/a;b",
        ):
            try:
                code = subprocess.run(
                    [sys.executable, "-I", __file__, "app", "--port", "0", "--identity", bad],
                    capture_output=True,
                    timeout=5,
                ).returncode
            except subprocess.TimeoutExpired:
                code = None
            check(code == 2, f"app accepted --identity {bad!r}")
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
    parser.add_argument("role", nargs="?", choices=["app", "idp", "health"])
    parser.add_argument("target", nargs="?", type=http_url)
    parser.add_argument("--port", type=int, default=0)
    parser.add_argument("--url", type=http_url)
    parser.add_argument("--identity", type=http_url)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    elif args.role == "health":
        if not args.target:
            parser.error("health needs a URL")
        sys.exit(health(args.target))
    elif args.target:
        parser.error(f"{args.role} takes no positional URL")
    elif args.role == "app" and not args.identity:
        parser.error("app needs --identity URL")
    elif args.role:
        port = listen_port(args.url) if args.url else args.port
        serve(args.role, port, (args.identity or "").rstrip("/"))
    else:
        parser.error("give a role or --self-test")


if __name__ == "__main__":
    main()

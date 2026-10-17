"""The shared interview session's server: one process, two 127.0.0.1 listeners. Python 3 stdlib.

Usage: python server.py --dir DATA_DIR [--guest-port P] [--control-port P] [--nonce N]
                        [--defaults-file F | --initial-state F]

Start it through `share.sh ensure-running`, which starts it detached and reuses a running one.
No secret travels on this command line: the control token and the owner token come from
`<data_dir>/.shared-secrets.json` (0600), made on the first start.

- Guest listener (`--guest-port`): the page, `/assets/*` and the `/api/*` routes in ROUTES. The
  tunnel's only target. Its own handler: Host and Origin checks, JSON-only POSTs with the body cap
  checked before reading, security headers on every answer, a per-address rate limit, and the
  auth class of each route. Identity is the `X-Owner-Token` or `X-Session-Secret` header, never a
  body field.
- Control listener (`--control-port`): session_bridge's `LoopbackHandler` with NAME `shared`
  (token header `X-Shared-Token`), for `share.sh`, `watch.sh` and `wake.sh` only, never tunneled.
  It adds `POST /api/ops` (Claude's ops) and `GET /api/status`.

The domain rules live in session.py; this file routes, authenticates, caps and renders. It also
watches the tunnel (tunnel.py): when its process exits it starts a new one, allows the new host and
records the new link, so the owner's view says to share it again.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import hashlib
import ipaddress
import json
import logging
import os
import re
import secrets
import signal
import socket
import sys
import threading
import time
import traceback
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from logging.handlers import RotatingFileHandler
from pathlib import Path
from urllib.parse import parse_qs, urlparse

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import detached  # noqa: E402  (beside this file; sys.path is set just above)
import migrate  # noqa: E402
import session  # noqa: E402
import session_bridge  # noqa: E402
import tunnel  # noqa: E402
from session import DomainError  # noqa: E402

NAME = "shared"  # names the session files and the token header; matches session-bridge.conf
SECRETS = ".shared-secrets.json"
PORTS = ".shared-ports.json"
OWNER_LINK = ".owner-link"
STATE = "state.json"
DEFAULTS = "defaults.json"
WEB = HERE / "web"
STATIC = {
    "/": ("index.html", "text/html"),
    "/core.js": ("core.js", "text/javascript"),
    "/app.js": ("app.js", "text/javascript"),
    "/core.css": ("core.css", "text/css"),
    "/app.css": ("app.css", "text/css"),
    "/proto.js": ("proto.js", "text/javascript"),
}
PAGE_CSP = "default-src 'self'; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
ASSET_CSP = "sandbox"
HTML_ASSET_CSP = "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; font-src data:; connect-src 'none'"
SECURITY_HEADERS = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer"}
ERROR_CODES = {400: "bad-request", 408: "body-timeout", 414: "uri-too-long", 431: "headers-too-large", 501: "not-implemented", 505: "bad-version"}
ASSET = re.compile(r"/assets/([0-9a-f]{16}\.(png|jpg|webp|svg|html))")
ASSET_TYPES = {"png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "svg": "image/svg+xml", "html": "text/html"}
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f-\x9f\\]")


def loggable(text, limit=80):
    """Request-derived text for one log line: cut to `limit`, control characters and backslashes as \\xNN."""
    return CONTROL_CHARS.sub(lambda m: f"\\x{ord(m.group(0)):02x}", str(text)[:limit])

LOG_BYTES = 1024 * 1024
LOG_KEEP = 3
TUNNEL_POLL = 1.0  # seconds between tunnel checks
TUNNEL_BACKOFF_MAX = 60.0
PRESENCE_TICK = 5  # the snapshot ETag moves at least this often, so expired presence shows

# The guest routes: path -> (auth class, session method). Classes (Contracts, "Auth classes"):
# public needs no identity; person needs a secret or the owner token; moderator is a person whose
# role session.py checks; owner needs the X-Owner-Token header itself. Uploads, /proto/<qid> and
# the prototype page arrive in later phases, so they answer 404.
ROUTES = {
    "/api/join": ("public", "join"),
    "/api/heartbeat": ("person", "heartbeat"),
    "/api/prefs": ("person", "set_prefs"),
    "/api/notifications/read": ("person", "read_notifications"),
    "/api/rename": ("person", "rename"),
    "/api/color": ("person", "set_color"),
    "/api/about-you": ("person", "set_about_you"),
    "/api/answer": ("person", "answer"),
    "/api/pick": ("person", "pick"),
    "/api/vote": ("person", "vote"),
    "/api/react": ("person", "react"),
    "/api/go-with": ("person", "go_with"),
    "/api/lock": ("moderator", "lock"),
    "/api/unlock": ("moderator", "unlock"),
    "/api/suggest": ("person", "suggest"),
    "/api/suggestion/act": ("moderator", "act_on_suggestion"),
    "/api/lock/edit": ("moderator", "edit_lock"),
    "/api/review/clear": ("moderator", "clear_review"),
    "/api/propose": ("person", "propose"),
    "/api/proposal/act": ("moderator", "act_on_proposal"),
    "/api/chat": ("person", "chat"),
    "/api/chat/propose": ("moderator", "propose_from_chat"),
    "/api/annotate": ("person", "annotate"),
    "/api/request": ("person", "request"),
    "/api/request/act": ("owner", "act_on_request"),
    "/api/round/ready": ("moderator", "ready_round"),
    "/api/round/send": ("owner", "send_round"),
    "/api/round/cancel": ("owner", "cancel_round"),
    "/api/round/reset": ("owner", "reset_round"),
    "/api/question/purpose": ("owner", "set_purpose"),
    "/api/question/reference": ("owner", "edit_reference"),
    "/api/person/role": ("owner", "set_role"),
    "/api/person/trust": ("owner", "set_trust"),
    "/api/person/remove": ("owner", "set_removed"),
    "/api/person/merge": ("owner", "merge_people"),
    "/api/merge-request": ("person", "request_merge"),
    "/api/merge-request/act": ("owner", "act_on_merge_request"),
    "/api/session/settings": ("owner", "update_settings"),
    "/api/session/title": ("owner", "set_title"),
    "/api/session/goal": ("owner", "set_goal"),
    "/api/session/end": ("owner", "end_session"),
    "/api/link/guest": ("owner", "rotate_guest_link"),
    "/api/link/owner": ("owner", "rotate_owner_link"),
    "/api/mine/requests/claim": ("person", "claim_my_request"),
    "/api/mine/requests/result": ("person", "post_my_result"),
    "/api/mine/requests/fail": ("person", "fail_my_request"),
}
GET_ROUTES = {"/api/mine/requests": ("person", "my_requests")}
BODY_CAPS = {}  # path -> bytes, where a route allows more than session.BODY_MAX


class StartRefused(Exception):
    """The session cannot start: a newer schema, a failed migration, an invalid file (exit 1)."""


def plugin_version():
    try:
        return json.loads((HERE.parent / ".claude-plugin" / "plugin.json").read_text(encoding="utf-8")).get("version") or ""
    except (OSError, ValueError):
        return ""


def build_hash():
    """Changes whenever a served web file does, so an open page can tell it must reload."""
    h = hashlib.sha256()
    for path, (name, _) in sorted(STATIC.items()):
        f = WEB / name
        h.update(path.encode())
        h.update(f.read_bytes() if f.is_file() else b"-")
    return h.hexdigest()[:12]


def read_json(path):
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def ensure_secrets(d):
    """The control and owner tokens from the 0600 secrets file, making any that is missing, plus
    `ownerAt`, when the owner token was issued: None for a new token or a file that does not say,
    which settle_owner_token decides once the session is open."""
    have = read_json(d / SECRETS) or {}
    out = {k: have[k] if isinstance(have.get(k), str) and len(have[k]) >= 32 else secrets.token_urlsafe(32) for k in ("control", "owner")}
    at = have.get("ownerAt")
    dated = out["owner"] == have.get("owner") and isinstance(at, (int, float)) and not isinstance(at, bool)
    out["ownerAt"] = at if dated else None
    return out


def settle_owner_token(d, s, creds, log):
    """Set a rotation time ahead of the clock to now, date an undated owner token, and write the
    secrets file. An undated token the file held that is not the session's current one may predate
    a rotation (a restored backup), so it is replaced by a fresh one."""
    ahead = s.clamp_owner_rotation()
    if ahead is not None:
        log.warning("the owner-link rotation time %.0f was ahead of the clock; set it to now", ahead)
    if creds["ownerAt"] is None:
        held = (read_json(d / SECRETS) or {}).get("owner") == creds["owner"]
        if held and s.owner_rotated_at() is not None and not s.is_owner_token(creds["owner"]):
            creds["owner"] = secrets.token_urlsafe(32)
            log.warning("the secrets file's owner token had no issue time and is not the current one; issued a fresh owner link")
        creds["ownerAt"] = time.time()
    if creds != read_json(d / SECRETS):
        detached.write_private(d / SECRETS, json.dumps(creds) + "\n")


def open_session(d, creds, log, *, defaults_file=None, initial_state=None):
    """The session in d/state.json: loaded and migrated, or created from defaults.json or from
    `initial_state` (a session file from elsewhere, run through migrate.py and validated as
    any load is). The owner token in `creds` (from ensure_secrets) becomes the owner's
    credential unless the session rotated the owner link after it was issued."""
    path = d / STATE
    version = plugin_version()
    try:
        if not path.exists() and initial_state is not None:
            detached.write_private(path, Path(initial_state).read_text(encoding="utf-8"))
            try:
                s = session.Session.load(path, plugin_version=version)
            except BaseException:
                path.unlink(missing_ok=True)
                raise
        elif not path.exists():
            src = Path(defaults_file) if defaults_file else d / DEFAULTS
            defaults = read_json(src) if src.exists() else {}
            if defaults is None or set(defaults) - {"settings", "title", "goal"}:
                raise StartRefused(f"{src} must be a JSON object with settings (and optionally title and goal)")
            s, _ = session.Session.create(
                path,
                title=defaults.get("title") or "Shared interview",
                goal=defaults.get("goal") or "",
                settings=defaults.get("settings") or {},
                plugin_version=version,
                owner_token=creds["owner"],
            )
        else:
            s = session.Session.load(path, plugin_version=version)
        settle_owner_token(d, s, creds, log)
        s.reset_owner_token(creds["owner"], creds["ownerAt"])
        return s
    except (migrate.MigrationError, DomainError, OSError) as exc:
        raise StartRefused(getattr(exc, "message", None) or str(exc)) from exc


class PrivateRotatingHandler(RotatingFileHandler):
    """server.log, rotated at 1 MB with 3 kept, each file created 0600 where the OS has modes."""

    def _open(self):
        fd = os.open(self.baseFilename, os.O_WRONLY | os.O_CREAT | os.O_APPEND, 0o600)
        return open(fd, self.mode, encoding=self.encoding)  # noqa: SIM115  (the handler owns and closes it)


def make_logger(d):
    log = logging.getLogger(f"shared-server.{d}")
    log.setLevel(logging.INFO)
    log.propagate = False
    for h in list(log.handlers):
        log.removeHandler(h)
        h.close()
    h = PrivateRotatingHandler(d / "server.log", maxBytes=LOG_BYTES, backupCount=LOG_KEEP, encoding="utf-8")
    h.setFormatter(logging.Formatter("%(asctime)s %(levelname)s %(message)s"))
    log.addHandler(h)
    return log


class Bucket:
    """A token bucket per client address, remembering at most `keys` addresses: the least recently
    seen is forgotten first, which costs nothing once its bucket has refilled."""

    def __init__(self, rate, burst, keys=session.RATE_KEYS):
        self.rate, self.burst, self.keys = rate, burst, keys
        self.lock = threading.Lock()
        self.tokens = collections.OrderedDict()

    def take(self, key):
        now = time.monotonic()
        with self.lock:
            level, last = self.tokens.pop(key, (self.burst, now))
            if len(self.tokens) >= self.keys:
                self.tokens.popitem(last=False)
            level = min(self.burst, level + (now - last) * self.rate)
            ok = level >= 1
            self.tokens[key] = (level - 1 if ok else level, now)
            return ok


def client_key(ip):
    """The rate and join key for an address: an IPv6 address by its /64, the block one host holds."""
    try:
        addr = ipaddress.ip_address(ip)
    except ValueError:
        return "invalid"
    if addr.version == 6 and addr.ipv4_mapped:
        addr = addr.ipv4_mapped
    return str(ipaddress.ip_network(f"{addr}/64", strict=False)) if addr.version == 6 else str(addr)


# -- control listener -------------------------------------------------------------------------


class ControlHub(session_bridge.LoopbackWatcher):
    """The session-bridge loopback adapter over the session's event log."""

    name = NAME

    def __init__(self, port, data_dir, app):
        super().__init__(port, data_dir)
        self.app = app
        self.token = app.secrets["control"]  # from the 0600 file, so a restart keeps armed watchers

    def read_log(self):
        return self.app.session.log_copy()

    def write_log(self, log):
        self.app.session.mark_delivered(log)

    def unhandled(self, log):
        handled = set(log.get("handled", []))
        return [e for e in log.get("events", []) if e["seq"] not in handled and not e.get("withdrawn")]

    def read_state(self):
        return {"rev": self.app.session.state["rev"]}, False

    def signature(self):
        return self.app.session.state["rev"]

    def identity(self):
        app = self.app
        return {
            "session": app.session.state["session"]["title"],
            "guestPort": app.guest_port,
            "publicUrl": app.public_url,
            "schemaVersion": app.session.state["schemaVersion"],
            "build": app.build,
        }


class ControlHandler(session_bridge.LoopbackHandler):
    max_body = session.OPS_MAX

    def route_get(self, url, query):
        if url.path != "/api/status":
            return self.send(404, {"error": "not found"})
        if not self.token_ok():
            return self.send(403, {"error": "token required"})
        app = self.hub.app
        rec = tunnel.read(app.dir)
        out = app.session.summary()
        out.update(
            ok=True,
            publicUrl=app.public_url,
            guestPort=app.guest_port,
            tunnel="quick" if rec and app.tunnel_up else ("down" if rec else "off"),
            lease=self.hub.lease_view(),
        )
        return self.send(200, out)

    def route_post(self, path, msg):
        if path != "/api/ops":
            return self.send(404, {"error": "not found"})
        app = self.hub.app
        try:
            out = app.session.apply(msg)
        except DomainError as exc:
            app.log.info("ops refused: %s %s", exc.code, loggable(exc.details.get("op")))
            return self.send(exc.http, exc.body())
        app.changed()
        app.log.info("ops applied: %d", len(msg.get("ops", [])))
        return self.send(200, {"ok": True, **out})


# -- guest listener ---------------------------------------------------------------------------


def raw_answer(code, reason, body):
    """A whole HTTP/1.1 answer, security headers included, for a connection no handler serves."""
    raw = json.dumps(body).encode("utf-8")
    head = [f"HTTP/1.1 {code} {reason}", "Content-Type: application/json; charset=utf-8", f"Content-Length: {len(raw)}", "Connection: close"]
    head += [f"{k}: {v}" for k, v in SECURITY_HEADERS.items()]
    return ("\r\n".join(head) + "\r\n\r\n").encode("ascii") + raw


class GuestServer(ThreadingHTTPServer):
    """At most session.MAX_HANDLERS connections are served at once; one more is answered 503."""

    daemon_threads = True
    request_queue_size = 128
    allow_reuse_address = not detached.WINDOWS  # on Windows the option lets another bind steal the port
    BUSY = raw_answer(503, "Service Unavailable", {"error": "busy", "message": "The session is busy; try again in a moment."})

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(session.MAX_HANDLERS)
        super().__init__(*args, **kwargs)

    def server_bind(self):
        if detached.WINDOWS and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            with contextlib.suppress(OSError):
                request.settimeout(1.0)
                request.sendall(self.BUSY)
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            self.slots.release()
            raise

    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()


class GuestHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "shared-session"
    sys_version = ""
    timeout = 30  # an idle or trickling connection is dropped

    def version_string(self):
        return self.server_version

    @property
    def app(self):
        return self.server.app

    def log_message(self, format, *args):  # noqa: A002  # matches the base signature
        pass

    def send(self, code, body, ctype="application/json", extra=None):
        """The session-bridge headers on every answer, the page CSP on HTML, plus `extra`."""
        raw = body if isinstance(body, bytes) else json.dumps(body, ensure_ascii=False).encode("utf-8")
        if code >= 400:
            self.close_connection = True  # an unread body must not become the next request
        self.send_response(code)
        text = ctype.startswith("text/") or ctype == "application/json"
        self.send_header("Content-Type", ctype + "; charset=utf-8" if text else ctype)
        if code != 304:
            self.send_header("Content-Length", str(len(raw)))
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, v)
        self.send_header("X-Shared-Build", self.app.build)
        extra = dict(extra or {})
        if ctype == "text/html" and "Content-Security-Policy" not in extra:
            extra["Content-Security-Policy"] = PAGE_CSP
        for k, v in extra.items():
            self.send_header(k, v)
        self.end_headers()
        if code != 304:
            with contextlib.suppress(*session_bridge.DISCONNECTS):
                self.wfile.write(raw)
        path = loggable(urlparse(getattr(self, "path", "") or "").path)
        took = (time.monotonic() - getattr(self, "t0", time.monotonic())) * 1000
        self.app.log.info("%s %s %d %.1fms", loggable(self.command or "-", 16), path or "-", code, took)

    def send_error(self, code, message=None, explain=None):
        """http.server's own refusals (a request line too long, an unknown method): JSON, same headers."""
        self.send(code, {"error": ERROR_CODES.get(code, "bad-request"), "message": message or self.responses.get(code, ("Refused.",))[0]})

    def fail(self, exc):
        return self.send(exc.http, exc.body())

    def address(self):
        """The client key for limits, from Cloudflare's CF-Connecting-IP only (never X-Forwarded-For)."""
        ip = (self.headers.get("CF-Connecting-IP") or "").strip()
        return client_key(ip[:64]) if ip else "local"

    def refused(self):
        """Host, Origin, body and rate checks shared by every method: True once it has answered an error."""
        self.t0 = time.monotonic()
        if not self.app.host_ok(self.headers.get("Host", ""), self.headers.get("Origin")):
            error = DomainError(403, "bad-host", "This address does not serve the session.")
        elif self.command != "POST" and (self.headers.get("Transfer-Encoding") or self.headers.get("Content-Length", "0").strip() not in ("", "0")):
            error = DomainError(400, "bad-request", "Only a POST carries a body.")
        elif not self.app.bucket.take(self.address()):
            error = DomainError(429, "slow-down", "Too many requests; wait a moment.")
        else:
            return False
        self.fail(error)
        return True

    def read_body(self, length):
        """Exactly `length` body bytes, all within session.BODY_SECONDS (TimeoutError otherwise), or
        None when the client closed first."""
        deadline = time.monotonic() + session.BODY_SECONDS
        chunks, left = [], length
        try:
            while left:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("the body did not arrive in time")
                self.connection.settimeout(remaining)
                chunk = self.rfile.read1(min(left, 65536))
                if not chunk:
                    self.close_connection = True
                    return None
                chunks.append(chunk)
                left -= len(chunk)
        finally:
            self.connection.settimeout(self.timeout)
        return b"".join(chunks)

    def identity(self):
        """The pid the request acts as, None without identity; DomainError for a stale credential."""
        owner = self.headers.get("X-Owner-Token")
        secret = self.headers.get("X-Session-Secret")
        if not owner and not secret:
            return None
        return self.app.session.resolve(secret=secret, owner_token=owner)

    def authorize(self, auth):
        if auth == "public":
            return self.identity() if self.headers.get("X-Owner-Token") else None
        if auth == "owner" and not self.headers.get("X-Owner-Token"):
            raise DomainError(403, "owner-only", "Only the owner can do that.")
        pid = self.identity()
        if pid is None:
            raise DomainError(401, "unknown-session", "Join the session first.")
        return pid

    def do_GET(self):
        if self.refused():
            return None
        url = urlparse(self.path)
        try:
            if url.path in STATIC:
                return self.static(*STATIC[url.path])
            m = ASSET.fullmatch(url.path)
            if m:
                return self.asset(m.group(1), m.group(2))
            if url.path == "/api/state":
                return self.state()
            if url.path in GET_ROUTES:
                auth, method = GET_ROUTES[url.path]
                pid = self.authorize(auth)
                query = {k: v[0] for k, v in parse_qs(url.query).items()}
                return self.send(200, {"ok": True, **getattr(self.app.session, method)(pid, query)})
        except DomainError as exc:
            return self.fail(exc)
        return self.fail(DomainError(404, "not-found", "Nothing here."))

    def static(self, name, ctype):
        f = WEB / name
        if not f.is_file():
            return self.fail(DomainError(404, "not-found", "Nothing here."))
        return self.send(200, f.read_bytes(), ctype)

    def asset(self, aid, ext):
        f = self.app.dir / "assets" / aid
        if not f.is_file():
            return self.fail(DomainError(404, "not-found", "No such asset."))
        csp = HTML_ASSET_CSP if ext == "html" else ASSET_CSP
        return self.send(200, f.read_bytes(), ASSET_TYPES[ext], {"Content-Security-Policy": csp, "Content-Disposition": "inline"})

    def state(self):
        app = self.app
        pid = self.identity()
        if pid is None:
            return self.send(200, app.session.anonymous_view())
        tag = app.etag(pid)
        if self.headers.get("If-None-Match") == tag:
            app.session.snapshot(pid)  # a removed person still reads nothing
            return self.send(304, b"", extra={"ETag": tag})
        snap = app.session.snapshot(pid)
        snap["build"] = app.build
        if snap["me"]["role"] in ("owner", "leader"):
            share = dict(app.session.state["session"]["share"])
            share["tunnel"] = "quick" if app.tunnel_up else "down"
            snap["share"] = share
        return self.send(200, snap, extra={"ETag": tag})

    def do_POST(self):
        if self.refused():
            return None
        path = urlparse(self.path).path
        if path not in ROUTES:
            return self.fail(DomainError(404, "not-found", "Nothing here."))
        if not self.headers.get("Content-Type", "").lower().startswith("application/json"):
            return self.fail(DomainError(415, "json-required", "Send JSON with Content-Type: application/json."))
        cap = BODY_CAPS.get(path, session.BODY_MAX)
        try:
            length = int(self.headers.get("Content-Length") or "-1")
        except ValueError:
            length = -1
        if length < 0:
            return self.fail(DomainError(400, "bad-json", "The request needs a Content-Length."))
        if length > cap:
            return self.fail(DomainError(413, "body-too-large", f"The body allows at most {cap} bytes.", max=cap))
        try:
            raw = self.read_body(length)
        except TimeoutError:
            return self.fail(DomainError(408, "body-timeout", f"The body must arrive within {session.BODY_SECONDS:.0f} s."))
        if raw is None:
            return None
        try:
            body = json.loads(raw or b"{}")
        except (ValueError, RecursionError):
            return self.fail(DomainError(400, "bad-json", "The body is not JSON."))
        if not isinstance(body, dict):
            return self.fail(DomainError(400, "bad-json", "The body must be a JSON object."))
        auth, method = ROUTES[path]
        app = self.app
        try:
            pid = self.authorize(auth)
            fn = getattr(app.session, method)
            out = fn(pid, body, address=self.address()) if method == "join" else fn(pid, body)
        except DomainError as exc:
            return self.fail(exc)
        except Exception:  # a bug: the transaction rolled back, so nothing was written
            app.log.error("%s failed:\n%s", path, traceback.format_exc())
            return self.fail(DomainError(500, "state-invalid", "The server could not do that; nothing was written."))
        if method == "rotate_owner_link":
            app.write_owner_link()
        app.changed()
        return self.send(200, {"ok": True, **out})

    def refuse_method(self):
        if not self.refused():
            self.fail(DomainError(404, "not-found", "Nothing here."))

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = refuse_method  # no CORS preflight is ever answered


# -- the process ------------------------------------------------------------------------------


class App:
    """Both listeners, the session and the tunnel watch for one data dir."""

    def __init__(self, data_dir, *, guest_port=0, control_port=0, nonce="", defaults_file=None, initial_state=None, watch_tunnel=True):
        self.dir = Path(data_dir).resolve()
        problem = detached.data_dir_problem(self.dir)
        if problem:
            raise StartRefused(problem)
        self.dir.mkdir(parents=True, exist_ok=True)
        detached.make_private_dir(self.dir / session.STAGING)
        self.log = make_logger(self.dir)
        self.secrets = ensure_secrets(self.dir)
        self.session = open_session(self.dir, self.secrets, self.log, defaults_file=defaults_file, initial_state=initial_state)
        self.session.on_owner_token = self.owner_rotated
        self.build = build_hash()
        self.bucket = Bucket(session.RATE_PER_SECOND, session.RATE_BURST)
        self.watch_tunnel = watch_tunnel
        self.public_url = ""
        self.tunnel_host = ""
        self.tunnel_up = False
        self._next_tunnel_try = 0.0
        self._backoff = 2.0
        self._last_sync = 0.0
        self._stop = threading.Event()
        self.guest = GuestServer(("127.0.0.1", guest_port), GuestHandler)
        self.guest.app = self
        self.guest_port = self.guest.server_address[1]
        self.local_hosts = {f"127.0.0.1:{self.guest_port}", f"localhost:{self.guest_port}"}
        handler = type("SharedControlHandler", (ControlHandler,), {})  # its own class: start() sets hub on it
        self.control, self.hub = session_bridge.start(handler, lambda port: ControlHub(port, self.dir, self), control_port, nonce)
        self.control_port = self.hub.port
        detached.write_private(self.dir / PORTS, json.dumps({"guest": self.guest_port, "control": self.control_port}) + "\n")
        self.write_owner_link()
        self.sync_tunnel()
        self.log.info("started: guest %d, control %d, build %s", self.guest_port, self.control_port, self.build)

    @property
    def local_url(self):
        return f"http://127.0.0.1:{self.guest_port}/"

    def write_owner_link(self):
        detached.write_private(self.dir / OWNER_LINK, f"{self.local_url}#owner={self.secrets['owner']}\n")

    def owner_rotated(self, token, at):
        """Called inside the rotation, before its hash commits: a crash after this keeps the new token."""
        self.secrets.update(owner=token, ownerAt=at)
        detached.write_private(self.dir / SECRETS, json.dumps(self.secrets) + "\n")

    def host_ok(self, host, origin):
        if not host:
            return False
        if host not in self.local_hosts and host != self.tunnel_host:
            now = time.monotonic()
            if now - self._last_sync > 1.0:  # a tunnel share.py just started may not be seen yet
                self._last_sync = now
                self.sync_tunnel(restart=False)
            if host != self.tunnel_host or not host:
                return False
        if origin is None:
            return True
        return origin in {f"http://{h}" for h in self.local_hosts} or (bool(self.tunnel_host) and origin == f"https://{self.tunnel_host}")

    def etag(self, pid):
        tick = int(time.time() // PRESENCE_TICK)
        who = hashlib.sha256(pid.encode()).hexdigest()[:8]
        st = self.session.state
        return f'"{st["rev"]}.{self.session.presence_rev()}.{tick}.{who}.{self.build}.{int(self.tunnel_up)}"'

    def changed(self):
        with self.hub.cond:
            self.hub.cond.notify_all()

    def sync_tunnel(self, restart=True):
        """Follow the tunnel record: allow its host, record its link, restart it when it exited."""
        rec = tunnel.read(self.dir)
        if rec is None:
            self.tunnel_up = False
            return
        live = tunnel.alive(self.dir)
        if (live is None or live.get("port") != self.guest_port) and restart and self.watch_tunnel:
            if time.monotonic() < self._next_tunnel_try:
                self.tunnel_up = False
                return
            try:
                live = tunnel.ensure(self.dir, self.guest_port)
                self._backoff = 2.0
                self.log.info("tunnel started: %s", live["url"])
            except (tunnel.TunnelDown, TimeoutError) as exc:
                self._next_tunnel_try = time.monotonic() + self._backoff
                self._backoff = min(TUNNEL_BACKOFF_MAX, self._backoff * 2)
                self.log.warning("tunnel down: %s", exc)
                self.tunnel_up = False
                return
        self.tunnel_up = live is not None
        url = (live or rec)["url"]
        if url != self.public_url:
            self.public_url = url
            self.tunnel_host = tunnel.host(url)
            if self.session.set_share(url):
                self.changed()

    def watch(self):
        while not self._stop.wait(TUNNEL_POLL):
            try:
                self.sync_tunnel()
            except Exception:  # the watch must outlive any one bad pass
                self.log.error("tunnel watch:\n%s", traceback.format_exc())

    def serve(self):
        """Serve both listeners and watch the tunnel in threads; returns at once."""
        loops = (lambda: self.guest.serve_forever(poll_interval=0.1), lambda: self.control.serve_forever(poll_interval=0.1), self.watch)
        self.threads = [threading.Thread(target=t, daemon=True) for t in loops]
        for t in self.threads:
            t.start()

    def shutdown(self):
        self._stop.set()
        if getattr(self, "threads", None):  # shutdown() waits for serve_forever, so only once serving
            self.guest.shutdown()
            self.control.shutdown()
        self.guest.server_close()
        self.control.server_close()
        for h in list(self.log.handlers):
            self.log.removeHandler(h)
            h.close()


def main(argv=None):
    p = argparse.ArgumentParser(description="The shared interview session server (127.0.0.1 only).")
    p.add_argument("--dir", required=True, help="the session's data dir")
    p.add_argument("--guest-port", type=int, default=0, help="guest listener port; 0 picks a free one")
    p.add_argument("--control-port", type=int, default=0, help="control listener port; 0 picks a free one")
    p.add_argument("--nonce", default="", help="echoed into the session files so share.py knows its own start")
    p.add_argument("--defaults-file", help="settings for a new session (default <dir>/defaults.json)")
    p.add_argument("--initial-state", help="a session file to start a new session from (run through migrate.py, then validated)")
    a = p.parse_args(argv)
    try:
        app = App(a.dir, guest_port=a.guest_port, control_port=a.control_port, nonce=a.nonce, defaults_file=a.defaults_file, initial_state=a.initial_state)
    except StartRefused as exc:
        print(f"refused: {exc}", file=sys.stderr)
        return 1
    except OSError as exc:
        print(f"cannot start: {exc}", file=sys.stderr)
        return 2
    app.serve()
    done = threading.Event()
    with contextlib.suppress(ValueError):  # signals only reach the main thread
        signal.signal(signal.SIGTERM, lambda *_: done.set())
    try:
        while not done.wait(1.0):
            pass
    except KeyboardInterrupt:
        pass
    app.shutdown()
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""The shared interview session's server: one process, two 127.0.0.1 listeners. Python 3 stdlib.

Usage: python server.py --dir DATA_DIR [--guest-port P] [--control-port P] [--nonce N]
                        [--defaults-file F]

Start it through `share.sh ensure-running`, which starts it detached and reuses a running one.
No secret travels on this command line: the control token and the owner token come from
`<data_dir>/.shared-secrets.json` (0600), made on the first start.

- Guest listener (`--guest-port`): the page, `/assets/*` and the `/api/*` routes in ROUTES. The
  tunnel's only target. Its own handler: Host and Origin checks, JSON-only POSTs with the body cap
  checked before reading, security headers on every answer, a per-address rate limit, and the
  auth class of each route. Identity is the `X-Owner-Token` or `X-Session-Secret` header, never a
  body field; `/assets/*` also takes the signed cookie each `/api/state` answer sets, since an
  `<img>` or a frame sends no header.
- Control listener (`--control-port`): session_bridge's `LoopbackHandler` with NAME `shared`
  (token header `X-Shared-Token`), for `share.sh`, `watch.sh` and `wake.sh` only, never tunneled.
  It adds `POST /api/ops` (Claude's ops) and `GET /api/status`.

The domain rules live in session.py; this file routes, authenticates, caps and renders. It also
watches the tunnel (tunnel.py): when its process exits it starts a new one, allows the new host and
records the new link, so the owner's view says to share it again (a named tunnel comes back at the
same address). After a switch to another address it still allows the retired tunnel's host while
that tunnel runs, and answers a page there with the new address only, so the page can move there
with its identity (core.js). A switch happens only once the new address proves it reaches this
server: share.py asks the control route `POST /api/tunnel-check`, and the server fetches
`<address>/api/tunnel-probe/<nonce>` and expects the answer only it knows.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import hashlib
import hmac
import http.client
import ipaddress
import json
import logging
import os
import re
import secrets
import signal
import socket
import ssl
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
IMPORT_DEFAULTS = ("guestPort", "adoptTunnel")  # defaults.json keys share.py reads; the server ignores them
MIN_OWNER_TOKEN = 16  # an owner token as short as the prototype's (token_urlsafe(12)) is kept: its owner link survives a restart
WEB = HERE / "web"
STATIC = {
    "/": ("index.html", "text/html"),
    "/core.js": ("core.js", "text/javascript"),
    "/app.js": ("app.js", "text/javascript"),
    "/connect.js": ("connect.js", "text/javascript"),
    "/core.css": ("core.css", "text/css"),
    "/app.css": ("app.css", "text/css"),
    "/proto.js": ("proto.js", "text/javascript"),
    "/web-vitals.attribution.iife.js": ("web-vitals.attribution.iife.js", "text/javascript"),  # vendored, unedited (web/web-vitals.LICENSE)
}
PAGE_CSP = "default-src 'self'; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'none'"
ASSET_CSP = "sandbox"
# An html variant runs scripts in a sandbox with no same origin (no cookies, storage or session access), and only
# the session's own pages may frame it: the prototype page does (Q98).
HTML_ASSET_CSP = (
    "sandbox allow-scripts; default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; img-src 'self' data:; font-src data:; "
    "connect-src 'none'; frame-ancestors 'self'"
)
PROTO = re.compile(r"/proto/(Q[1-9][0-9]{0,5})")
# The pin helper (web/proto-pin.js) the prototype page asks for with /assets/<id>.html?pin=1: appended to the
# variant as an inline script, the only kind its CSP runs. It talks to the page by postMessage alone.
def pin_helper(text):
    """The pin helper's text, refused when it holds `</script`, `<script` or `<!--`: inside a script element any of
    them could end it early or hide its end from the parser."""
    low = text.lower()
    if any(s in low for s in ("</script", "<script", "<!--")):
        raise RuntimeError("web/proto-pin.js must not contain </script, <script or <!--")
    return text


PIN_HELPER = pin_helper((WEB / "proto-pin.js").read_text(encoding="utf-8"))
SECURITY_HEADERS = {"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "X-Frame-Options": "DENY", "Referrer-Policy": "no-referrer"}
ERROR_CODES = {400: "bad-request", 408: "body-timeout", 414: "uri-too-long", 431: "headers-too-large", 501: "not-implemented", 505: "bad-version"}
ASSET = re.compile(r"/assets/([0-9a-f]{16}\.(png|jpg|webp|svg|html))")
ASSET_TYPES = {"png": "image/png", "jpg": "image/jpeg", "webp": "image/webp", "svg": "image/svg+xml", "html": "text/html"}
# Control characters, a backslash, and U+2028 and U+2029, which str.splitlines() also ends a line on.
CONTROL_CHARS = re.compile(r"[\x00-\x1f\x7f-\x9f\\\u2028\u2029]")


def loggable(text, limit=80):
    """Request-derived text for one log line: cut to `limit`, each CONTROL_CHARS character as \\xNN or \\uNNNN."""
    return CONTROL_CHARS.sub(lambda m: f"\\x{ord(m.group(0)):02x}" if ord(m.group(0)) < 256 else f"\\u{ord(m.group(0)):04x}", str(text)[:limit])


def trace():
    """The exception being handled: its last TRACE_LIMIT characters (the exception is at the end)."""
    return traceback.format_exc()[-TRACE_LIMIT:]


def entry(what, /, **fields):
    """One log entry, for requests and client entries alike: `what`, then key=value for each field given (None
    dropped). Each value is cut to its FIELD_LIMITS length and escaped like loggable, a double quote as \\x22 too,
    and quoted when it holds a space, so the entry stays on one line and its leading fields split on spaces."""
    out = [what]
    for k, v in fields.items():
        if v is None:
            continue
        v = loggable(v, FIELD_LIMITS.get(k, 80)).replace('"', "\\x22").encode("utf-8", "backslashreplace").decode("utf-8")  # a lone surrogate too
        out.append(f'{k}="{v}"' if " " in v else f"{k}={v}")
    return " ".join(out)


TRACE_LIMIT = 8000  # judgment: a traceback's characters kept on its one log line, enough for a deep stack
CLIENT_MESSAGE_MAX = 500
FIELD_LIMITS = {"method": 16, "message": CLIENT_MESSAGE_MAX, "trace": TRACE_LIMIT, "route": 200, "source": 200}
LOG_BYTES = 1024 * 1024
LOG_KEEP = 3
# POST /api/client-log: what a joined person's page reports (web/core.js telemetry): faults under the person's pid,
# and a usage summary, which names no one, when the page hides. Summaries reach server.log only in a summary-batch
# entry every SUMMARY_BATCH_SECONDS and at shutdown, never with a time or a request entry of their own: the page
# sends its summary as it sends a heartbeat, whose request entry names the person.
CLIENT_LOG = "/api/client-log"
CLIENT_LOG_MAX = 4096  # bytes: a 500-character message in any script, plus the other fields
CLIENT_FIELDS = {"kind": 20, "message": CLIENT_MESSAGE_MAX, "source": 200, "route": 200, "code": 60, "ua": 60, "fp": 16}
CLIENT_KINDS = ("error", "rejection", "api", "layout", "summary")
USAGE_KINDS = ("summary",)  # held for the next summary batch, on their own rate bucket
IMAGE_PER_MINUTE = 120  # judgment: pictures one person's pages read back a minute; a page holds at most a few dozen tiles
CLIENT_PER_MINUTE = 20  # judgment: entries one person's page may log a minute; a page in an error loop stops there
SUMMARY_PER_MINUTE = 6  # judgment: a page sends one summary each time it hides; tab switching rarely passes this
SUMMARY_BATCH_SECONDS = 600  # judgment: summaries held per batch; long enough that many people's summaries share one
SUMMARY_BATCH_BYTES = 100_000  # judgment: the most one batch entry holds; a summary past it is counted as dropped
TUNNEL_POLL = 1.0  # seconds between tunnel checks
TUNNEL_BACKOFF_MAX = 60.0
PRESENCE_TICK = 5  # the snapshot ETag moves at least this often, so expired presence shows
ASSET_COOKIE_SECONDS = 900  # judgment: an asset cookie's life; every /api/state answer renews it, so an open page keeps it

# The guest routes: path -> (auth class, session method). Classes (Contracts, "Auth classes"):
# public needs no identity; person needs a secret or the owner token; moderator is a person whose
# role session.py checks; owner needs the X-Owner-Token header itself, the owner link's token or a signed-in device's
# credential; host needs the owner link's token, never a device's. The upload chunk route takes raw bytes,
# not JSON, so GuestHandler.upload_chunk serves it (UPLOAD_CHUNK).
ROUTES = {
    "/api/join": ("public", "join"),
    "/api/heartbeat": ("person", "heartbeat"),
    "/api/prefs": ("person", "set_prefs"),
    "/api/notifications/read": ("person", "read_notifications"),
    "/api/inbox/read": ("person", "read_inbox"),
    "/api/rename": ("person", "rename"),
    "/api/color": ("person", "set_color"),
    "/api/about-you": ("person", "set_about_you"),
    "/api/answer": ("person", "answer"),
    "/api/pick": ("person", "pick"),
    "/api/vote": ("person", "vote"),
    "/api/react": ("person", "react"),
    "/api/disagree": ("person", "disagree"),
    "/api/pass": ("person", "pass_"),
    "/api/go-with": ("person", "go_with"),
    "/api/lock": ("moderator", "lock"),
    "/api/unlock": ("moderator", "unlock"),
    "/api/suggest": ("person", "suggest"),
    "/api/suggestion/act": ("moderator", "act_on_suggestion"),
    "/api/lock/edit": ("moderator", "edit_lock"),
    "/api/review/clear": ("moderator", "clear_review"),
    "/api/decision/keep": ("owner", "keep_decision"),
    "/api/propose": ("person", "propose"),
    "/api/proposal/act": ("moderator", "act_on_proposal"),
    "/api/proposal/all": ("owner", "approve_proposals"),
    "/api/chat": ("person", "chat"),
    "/api/chat/propose": ("moderator", "propose_from_chat"),
    "/api/chat/react": ("person", "react_chat"),
    "/api/discussion": ("person", "comment"),
    "/api/discussion/edit": ("person", "edit_comment"),
    "/api/discussion/delete": ("person", "delete_comment"),
    "/api/discussion/hide": ("owner", "hide_comment"),
    "/api/discussion/react": ("person", "react_comment"),
    "/api/discussion/read": ("person", "read_discussion"),
    "/api/card/hide": ("owner", "hide_card"),
    "/api/card/edit": ("owner", "edit_card"),
    "/api/join/act": ("owner", "act_on_join"),
    "/api/session/intro": ("owner", "set_intro"),
    "/api/annotate": ("person", "annotate"),
    "/api/request": ("person", "request"),
    "/api/request/act": ("person", "act_on_request"),  # session.py: move is the asker's or the owner's, the rest the owner's
    "/api/result/share": ("person", "share_result"),
    "/api/round/ready": ("moderator", "ready_round"),
    "/api/round/send": ("owner", "send_round"),
    "/api/round/cancel": ("owner", "cancel_round"),
    "/api/round/reset": ("owner", "reset_round"),
    "/api/question/purpose": ("owner", "set_purpose"),
    "/api/question/for": ("owner", "set_for"),
    "/api/question/reference": ("owner", "edit_reference"),
    "/api/person/role": ("owner", "set_role"),
    "/api/person/trust": ("owner", "set_trust"),
    "/api/person/remove": ("owner", "set_removed"),
    "/api/person/merge": ("owner", "merge_people"),
    "/api/merge-request": ("person", "request_merge"),
    "/api/merge-request/act": ("owner", "act_on_merge_request"),
    "/api/claude-proposal/act": ("owner", "act_on_claude_proposal"),
    "/api/session/settings": ("owner", "update_settings"),
    "/api/session/title": ("owner", "set_title"),
    "/api/session/goal": ("owner", "set_goal"),
    "/api/session/end": ("owner", "end_session"),
    "/api/link/guest": ("owner", "rotate_guest_link"),
    "/api/link/owner": ("host", "rotate_owner_link"),  # it answers the new owner token, which no other device holds
    "/api/owner/pair": ("host", "pair_device"),
    "/api/owner/pair/redeem": ("public", "redeem_pairing"),
    "/api/owner/devices/revoke": ("owner", "revoke_device"),
    "/api/mine/requests/claim": ("person", "claim_my_request"),
    "/api/mine/requests/result": ("person", "post_my_result"),
    "/api/mine/requests/fail": ("person", "fail_my_request"),
    "/api/watcher": ("person", "issue_watcher"),
    "/api/watcher/revoke": ("person", "revoke_watcher"),
    "/api/upload/offer": ("person", "offer_upload"),
    "/api/upload/act": ("person", "act_on_upload"),  # session.py: accept and decline the owner's, withdraw the uploader's
    "/api/report": ("person", "report"),
    "/api/report/act": ("owner", "act_on_report"),
    "/api/report/add": ("person", "add_to_report"),
}
UPLOAD_CHUNK = "/api/upload/chunk"
UPLOAD_IMAGE = "/api/upload/image"
CHUNK_HEADERS = {"id": "X-Upload-Id", "index": "X-Chunk-Index", "total": "X-Chunk-Total", "sha256": "X-Chunk-Sha256", "fileSha256": "X-File-Sha256"}
GET_ROUTES = {"/api/chat": ("person", "chat_page"), "/api/mine/requests": ("person", "my_requests"), "/api/card/history": ("owner", "card_history"), "/api/report/image": ("owner", "report_image"),
              "/api/upload/image": ("person", "upload_image")}
# The only routes a watcher key (X-Watcher-Key) works on: a guest's own Claude reads and answers their own self
# requests. Anywhere else the header answers 401, so the key never acts as the person's session secret.
WATCHER_ROUTES = {"/api/mine/requests", "/api/mine/requests/claim", "/api/mine/requests/result", "/api/mine/requests/fail"}
BODY_CAPS = {"/api/upload/offer": session.OFFER_MAX, "/api/report": session.REPORT_SEND_MAX, "/api/report/add": session.REPORT_MAX, CLIENT_LOG: CLIENT_LOG_MAX}  # path -> bytes, where not session.BODY_MAX
SERVER_ERROR = ("state-invalid", "The server could not do that; nothing was written.")


def batch_json(items):
    """A summary batch's [message, ua] pairs as one line of ASCII with no space, so it is the last field of its entry."""
    return json.dumps(items, separators=(",", ":")).replace(" ", "\\u0020")


def client_fields(body):
    """A client-log body checked against CLIENT_FIELDS: strings within their limits, a known kind, a message; each
    string with its hidden characters dropped (session._visible), as every text field a guest sends."""
    extra = sorted(set(body) - set(CLIENT_FIELDS))
    if extra:
        raise DomainError(400, "bad-field", f"{extra[0][:40]} is not a client-log field.", field=extra[0][:40])
    for k, limit in CLIENT_FIELDS.items():
        v = body.get(k)
        if v is not None and not isinstance(v, str):
            raise DomainError(400, "bad-field", f"{k} must be a string.", field=k)
        if v is not None and len(v) > limit:
            raise DomainError(400, "too-long", f"{k} allows at most {limit} characters.", field=k, max=limit)
    out = {k: None if body.get(k) is None else session._visible(body[k]) for k in CLIENT_FIELDS}  # what a guest's text may hold
    if out["kind"] not in CLIENT_KINDS:
        raise DomainError(400, "bad-field", f"kind must be one of {', '.join(CLIENT_KINDS)}.", field="kind")
    if not out["message"]:
        raise DomainError(400, "empty", "message is empty.", field="message")
    return out


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
    for path, name in [*sorted((p, n) for p, (n, _) in STATIC.items()), ("/proto/", "proto.html"), ("?pin=1", "proto-pin.js")]:
        f = WEB / name
        h.update(path.encode())
        h.update(f.read_bytes() if f.is_file() else b"-")
    return h.hexdigest()[:12]


PROBE_PATH = re.compile(r"/api/tunnel-probe/([0-9a-f]{32})")
PROBE_SECONDS = 30.0  # judgment: how long a new tunnel address may take to start reaching this server


def probe_target(url):
    """(connection, Host header) for fetching through `url`, an https address. SHARED_PROBE_ORIGIN (tests) sends the
    request to a loopback http origin instead, with the same Host."""
    host = urlparse(url).hostname or ""
    origin = urlparse(os.environ.get("SHARED_PROBE_ORIGIN") or "")
    if origin.scheme == "http" and origin.hostname in ("127.0.0.1", "localhost"):
        return http.client.HTTPConnection(origin.hostname, origin.port or 80, timeout=5), host
    return http.client.HTTPSConnection(host, 443, timeout=5, context=ssl.create_default_context()), host


def tunnel_kind(rec, up):
    """What a status says of the tunnel: named or quick while it runs, down when it does not, off with no record."""
    if not rec:
        return "off"
    return ("named" if tunnel.config(rec)[0] else "quick") if up else "down"


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
    least = {"control": 32, "owner": MIN_OWNER_TOKEN}
    out = {k: have[k] if isinstance(have.get(k), str) and len(have[k]) >= n else secrets.token_urlsafe(32) for k, n in least.items()}
    at = have.get("ownerAt")
    dated = out["owner"] == have.get("owner") and isinstance(at, (int, float)) and not isinstance(at, bool)
    out["ownerAt"] = at if dated else None
    return out


def settle_owner_token(d, s, creds, log):
    """Set a rotation time ahead of the clock to now, date an undated owner token, and write the
    secrets file. A token the file held that is not the session's current one may predate a
    rotation (a restored backup), so it is replaced by a fresh one when its issue time cannot be
    trusted: it has none, the clock was rolled back (the rotation time was ahead of it), which
    makes a dated token's time as doubtful as the rotation's, or its issue time is ahead of the
    clock, which a start that died between the clamp's write and this file's leaves behind."""
    ahead = s.clamp_owner_rotation()
    if ahead is not None:
        log.warning("the owner-link rotation time %.0f was ahead of the clock; set it to now", ahead)
    held = (read_json(d / SECRETS) or {}).get("owner") == creds["owner"]
    future = creds["ownerAt"] is not None and creds["ownerAt"] > time.time()
    if held and (creds["ownerAt"] is None or ahead is not None or future) and not s.is_owner_token(creds["owner"]):
        creds["owner"], creds["ownerAt"] = secrets.token_urlsafe(32), None
        why = "the clock was rolled back" if ahead is not None or future else "it had no issue time"
        log.warning("the secrets file's owner token is not the current one and %s; issued a fresh owner link", why)
    if creds["ownerAt"] is None:
        creds["ownerAt"] = time.time()
    if creds != read_json(d / SECRETS):
        detached.write_private(d / SECRETS, json.dumps(creds) + "\n")


def open_session(d, creds, log, *, defaults_file=None):
    """The session in d/state.json: loaded, or created from defaults.json. The owner token in `creds` (from
    ensure_secrets) becomes the owner's credential unless the session rotated the owner link after it was issued."""
    path = d / STATE
    version = plugin_version()
    try:
        if not path.exists():
            src = Path(defaults_file) if defaults_file else d / DEFAULTS
            defaults = read_json(src) if src.exists() else {}
            if defaults is None or set(defaults) - {"settings", "title", "goal", *IMPORT_DEFAULTS}:
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
    except (DomainError, OSError) as exc:
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
            tunnel=tunnel_kind(rec, app.tunnel_up),
            lease=self.hub.lease_view(),
        )
        return self.send(200, out)

    def route_post(self, path, msg):
        app = self.hub.app
        if path == "/api/tunnel-check":
            url = msg.get("url")
            problem = app.probe_tunnel(url) if isinstance(url, str) else "url must be a string"
            return self.send(200, {"ok": problem is None, **({"error": problem} if problem else {})})
        if path != "/api/ops":
            return self.send(404, {"error": "not found"})
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
    BUSY_MESSAGE = "The session is busy; try again in a moment."
    BUSY = raw_answer(503, "Service Unavailable", {"error": "busy", "message": BUSY_MESSAGE})
    # judgment: how long, how much and how many refused clients are read after their 503, so a flood costs little.
    DRAIN_SECONDS = 2.0
    DRAIN_BYTES = 64 * 1024
    DRAINS = 8

    def __init__(self, *args, **kwargs):
        self.slots = threading.BoundedSemaphore(session.MAX_HANDLERS)
        self.drains = threading.BoundedSemaphore(self.DRAINS)
        super().__init__(*args, **kwargs)

    def server_bind(self):
        if detached.WINDOWS and hasattr(socket, "SO_EXCLUSIVEADDRUSE"):
            self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_EXCLUSIVEADDRUSE, 1)
        super().server_bind()

    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            # No request was read, so the entry has no method, route or pid, and no traceback: nothing failed.
            self.app.log.error("%s", entry("request", method="-", route="-", status=503, ms="0.0", code="busy", message=self.BUSY_MESSAGE))
            if self.drains.acquire(blocking=False):
                threading.Thread(target=self.refuse, args=(request,), daemon=True).start()
            else:
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

    def refuse(self, request):
        """Answer 503, then read what the client sends until it closes, DRAIN_BYTES or DRAIN_SECONDS. A socket closed
        with unread data resets the connection, and a Windows client then drops the 503 it already received."""
        try:
            with contextlib.suppress(OSError):
                request.settimeout(1.0)
                request.sendall(self.BUSY)
                request.shutdown(socket.SHUT_WR)
                deadline, left = time.monotonic() + self.DRAIN_SECONDS, self.DRAIN_BYTES
                while left > 0 and (wait := deadline - time.monotonic()) > 0:
                    request.settimeout(wait)
                    got = request.recv(min(left, 4096))
                    if not got:
                        break
                    left -= len(got)
        finally:
            self.close_request(request)
            self.drains.release()


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
        extra = dict(extra or {})
        for k, v in SECURITY_HEADERS.items():
            self.send_header(k, extra.pop(k, v))
        self.send_header("X-Shared-Build", self.app.build)
        if ctype == "text/html" and "Content-Security-Policy" not in extra:
            extra["Content-Security-Policy"] = PAGE_CSP
        for k, v in extra.items():
            self.send_header(k, v)
        self.end_headers()
        self.log_request_entry(code)  # before the body goes out, so a client that has its answer finds the entry
        if code != 304:
            with contextlib.suppress(*session_bridge.DISCONNECTS):
                self.wfile.write(raw)

    # The acting pid, the refusal and the traceback of the request being answered, and whether the answer goes
    # unlogged (a usage summary taken); send() logs and clears them, since one handler serves every request on a
    # kept-alive connection.
    pid = refusal = failure = None
    unlogged = False

    def log_request_entry(self, code):
        """One entry per answer (README "Logs"): INFO for a success, WARNING for a refusal, ERROR with the traceback
        for a server error. Never a header or body value: no credential, request body or upload reaches the log."""
        exc, took = self.refusal, (time.monotonic() - getattr(self, "t0", time.monotonic())) * 1000
        if not self.unlogged:
            line = entry(
                "request",
                method=self.command or "-",
                route=urlparse(getattr(self, "path", "") or "").path or "-",
                status=code,
                ms=f"{took:.1f}",
                pid=self.pid,
                code=exc and exc.code,
                field=exc and exc.details.get("field"),
                message=exc and exc.message,
                trace=self.failure,
            )
            self.app.log.log(logging.ERROR if code >= 500 else logging.WARNING if code >= 400 else logging.INFO, "%s", line)
        self.pid = self.refusal = self.failure = None
        self.unlogged = False

    def send_error(self, code, message=None, explain=None):
        """http.server's own refusals (a request line too long, an unknown method): JSON, same headers."""
        self.fail(DomainError(code, ERROR_CODES.get(code, "bad-request"), message or self.responses.get(code, ("Refused.",))[0]))

    def fail(self, exc, failure=None):
        """Answer a refusal; `failure`, the traceback of a server error, goes to the log only. A 5xx DomainError with
        none logs its own traceback, from where the session raised it."""
        if exc.http >= 500 and failure is None:
            failure = "".join(traceback.format_exception(exc))[-TRACE_LIMIT:]
        self.refusal, self.failure = exc, failure
        return self.send(exc.http, exc.body())

    def crash(self):
        """Answer the exception being handled as a server error, its traceback logged."""
        return self.fail(DomainError(500, *SERVER_ERROR), trace())

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

    def read_body(self, length, seconds=None):
        """Exactly `length` body bytes, all within `seconds` (session.BODY_SECONDS by default; TimeoutError
        otherwise), or None when the client closed first."""
        deadline = time.monotonic() + (session.BODY_SECONDS if seconds is None else seconds)
        chunks, left = [], length
        try:
            while left:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError("the body did not arrive in time")
                self.connection.settimeout(min(remaining, self.timeout))  # a stalled sender is dropped after self.timeout
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
        """The pid the request acts as, None without identity; DomainError for a stale credential. do_GET and do_POST
        have already refused a watcher key off WATCHER_ROUTES."""
        owner = self.headers.get("X-Owner-Token")
        secret = self.headers.get("X-Session-Secret")
        watcher = self.headers.get("X-Watcher-Key")
        if watcher is not None:
            self.pid = self.app.session.resolve(watcher=watcher)
        elif owner or secret:
            self.pid = self.app.session.resolve(secret=secret, owner_token=owner)
        return self.pid

    def watcher_misplaced(self):
        """A watcher key on any other route, or beside another credential: answered 401 before anything else runs."""
        h = self.headers
        return h.get("X-Watcher-Key") is not None and (urlparse(self.path).path not in WATCHER_ROUTES or bool(h.get("X-Owner-Token") or h.get("X-Session-Secret")))

    def authorize(self, auth):
        if auth == "public":
            return self.identity() if self.headers.get("X-Owner-Token") else None
        if auth in ("owner", "host") and not self.headers.get("X-Owner-Token"):
            raise DomainError(403, "owner-only", "Only the owner can do that.")
        if auth == "host" and not self.app.session.is_owner_token(self.headers["X-Owner-Token"]):
            self.identity()  # a stale credential answers 401 as anywhere else
            raise DomainError(403, "host-device-only", "Do that on the device that opened your owner link.")
        pid = self.identity()
        if pid is None:
            raise DomainError(401, "unknown-session", "Join the session first.")
        return pid

    def do_GET(self):
        probe = PROBE_PATH.fullmatch(urlparse(self.path).path)
        if probe:  # before the Host check: the probe arrives on an address not yet allowed; it answers a pending nonce only
            answer = self.app.answer_probe(probe.group(1))
            return self.send(200, {"probe": answer}) if answer else self.send(404, {"error": "not-found"})
        if self.refused():
            return None
        url = urlparse(self.path)
        try:
            if self.watcher_misplaced():
                raise DomainError(401, "unknown-session", "A watcher key works only on /api/mine/requests.")
            if url.path in STATIC:
                return self.static(*STATIC[url.path])
            m = ASSET.fullmatch(url.path)
            if m:
                return self.asset(m.group(1), m.group(2), pin=url.query == "pin=1")
            m = PROTO.fullmatch(url.path)
            if m and self.app.session.is_prototype(m.group(1)):
                return self.static("proto.html", "text/html")
            if url.path == "/api/state":
                return self.state()
            if url.path in GET_ROUTES:
                auth, method = GET_ROUTES[url.path]
                pid = self.authorize(auth)
                if url.path == UPLOAD_IMAGE and not self.app.image_bucket.take(pid):
                    raise DomainError(429, "slow-down", f"At most {IMAGE_PER_MINUTE} pictures a minute.")
                query = {k: v[0] for k, v in parse_qs(url.query).items()}
                return self.send(200, {"ok": True, **getattr(self.app.session, method)(pid, query)})
        except DomainError as exc:
            return self.fail(exc)
        except Exception:  # a bug: a read writes nothing
            return self.crash()
        return self.fail(DomainError(404, "not-found", "Nothing here."))

    def static(self, name, ctype):
        f = WEB / name
        if not f.is_file():
            return self.fail(DomainError(404, "not-found", "Nothing here."))
        return self.send(200, f.read_bytes(), ctype)

    def asset_cookie(self, pid):
        """The Set-Cookie that lets this browser's <img> and frame requests read /assets/ as `pid` for a while."""
        exp = int(time.time()) + ASSET_COOKIE_SECONDS
        secure = "; Secure" if self.headers.get("Host") in {h for h in (self.app.tunnel_host, self.app.retired_host) if h} else ""
        value = f"{pid}.{exp}.{self.app.asset_sign(pid, exp)}"
        return f"{self.app.asset_cookie}={value}; Path=/assets/; Max-Age={ASSET_COOKIE_SECONDS}; HttpOnly; SameSite=Strict{secure}"

    def asset_reader(self):
        """The pid an asset request reads as: a credential header, else an unexpired asset cookie whose person may
        still read (a removed person's cookie reads nothing). DomainError 401 without either."""
        pid = self.identity()
        if pid is None:
            for part in (self.headers.get("Cookie") or "").split(";"):
                name, _, value = part.strip().partition("=")
                who, _, rest = value.partition(".")
                exp, _, sig = rest.partition(".")
                ok_exp = exp.isascii() and exp.isdigit() and len(exp) <= 12
                if name == self.app.asset_cookie and ok_exp and int(exp) >= time.time() and hmac.compare_digest(sig.encode(), self.app.asset_sign(who, int(exp)).encode()):
                    pid = self.app.session.check(who)
                    break
        if pid is None:
            raise DomainError(401, "unknown-session", "Join the session first.")
        return pid

    def asset(self, aid, ext, *, pin=False):
        self.asset_reader()
        f = self.app.dir / "assets" / aid
        if not f.is_file():
            return self.fail(DomainError(404, "not-found", "No such asset."))
        if ext != "html":
            return self.send(200, f.read_bytes(), ASSET_TYPES[ext], {"Content-Security-Policy": ASSET_CSP, "Content-Disposition": "inline"})
        body = f.read_bytes() + (f"\n<script>{PIN_HELPER}</script>\n".encode() if pin else b"")
        return self.send(200, body, "text/html", {"Content-Security-Policy": HTML_ASSET_CSP, "Content-Disposition": "inline", "X-Frame-Options": "SAMEORIGIN"})

    def state(self):
        app = self.app
        if app.moved(self.headers.get("Host", "")):  # the old address after a switch: only where the session went
            return self.send(200, {"moved": app.public_url})
        pid = self.identity()
        if pid is None:
            return self.send(200, app.session.anonymous_view())
        tag, sent = app.etag(pid), self.headers.get("If-None-Match") or ""
        extra = {"ETag": tag, "Set-Cookie": self.asset_cookie(pid)}
        if sent == tag:  # identity() already refused a removed or waiting person
            return self.send(304, b"", extra=extra)
        if sent.rsplit(".", 2)[0] == tag.rsplit(".", 2)[0]:  # only presence or the clock moved: send just that part
            return self.send(200, {"rev": app.session.state["rev"], "presenceOnly": True, **app.session.presence_view(pid)}, extra=extra)
        snap = app.session.snapshot(pid)
        snap["build"] = app.build
        if snap["me"]["role"] in ("owner", "leader"):
            share = dict(app.session.state["session"]["share"])
            share["tunnel"] = tunnel_kind(tunnel.read(app.dir), True) if app.tunnel_up else "down"
            snap["share"] = share
        return self.send(200, snap, extra=extra)

    def do_POST(self):
        if self.refused():
            return None
        path = urlparse(self.path).path
        if self.watcher_misplaced():
            return self.fail(DomainError(401, "unknown-session", "A watcher key works only on /api/mine/requests."))
        if path == UPLOAD_CHUNK:
            return self.upload_chunk()
        if path not in ROUTES and path != CLIENT_LOG:
            return self.fail(DomainError(404, "not-found", "Nothing here."))
        if path != CLIENT_LOG:  # who sends it is settled from headers before any of the body is read
            auth, method = ROUTES[path]
            try:
                pid = self.authorize(auth)
            except DomainError as exc:
                return self.fail(exc)
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
        seconds = session.REPORT_SECONDS if path == "/api/report" else session.BODY_SECONDS  # up to four pictures take longer
        try:
            raw = self.read_body(length, seconds)
        except TimeoutError:
            return self.fail(DomainError(408, "body-timeout", f"The body must arrive within {seconds:.0f} s."))
        if raw is None:
            return None
        try:
            body = json.loads(raw or b"{}")
        except (ValueError, RecursionError):
            return self.fail(DomainError(400, "bad-json", "The body is not JSON."))
        if not isinstance(body, dict):
            return self.fail(DomainError(400, "bad-json", "The body must be a JSON object."))
        if path == CLIENT_LOG:
            return self.client_log(body)
        app = self.app
        try:
            fn = getattr(app.session, method)
            out = fn(pid, body, address=self.address()) if method in ("join", "redeem_pairing") else fn(pid, body)
        except DomainError as exc:
            return self.fail(exc)
        except Exception:  # a bug: the transaction rolled back, so nothing was written
            return self.crash()
        if method == "rotate_owner_link":
            app.write_owner_link()
        if method in ("rotate_owner_link", "revoke_device", "end_session"):
            app._asset_key = secrets.token_bytes(32)  # an asset cookie names the host, not the device: every one ends
        app.changed()
        return self.send(200, {"ok": True, **out})

    def upload_chunk(self):
        """POST /api/upload/chunk: raw bytes of one chunk (application/octet-stream) with its X-Upload-Id,
        X-Chunk-Index, X-Chunk-Total, X-Chunk-Sha256 and, on the last, X-File-Sha256. Who sends it, which chunk is
        next and its exact length are settled before any of the body is read; a chunk the server holds already is
        answered {received} unread. session.py checks the bytes and writes them under the data folder."""
        app = self.app
        try:
            pid = self.authorize("person")
            if not self.headers.get("Content-Type", "").lower().startswith("application/octet-stream"):
                raise DomainError(415, "bytes-required", "Send the piece as application/octet-stream.")
            if self.headers.get("Transfer-Encoding"):
                raise DomainError(400, "bad-request", "Send the piece with a Content-Length.")
            try:
                length = int(self.headers.get("Content-Length") or "-1")
            except ValueError:
                length = -1
            if length < 0:
                raise DomainError(400, "bad-request", "Send the piece with a Content-Length.")
            if length > session.CHUNK_SIZE:
                raise DomainError(413, "body-too-large", f"A piece holds at most {session.CHUNK_SIZE} bytes.", max=session.CHUNK_SIZE)
            meta = {k: self.headers.get(h) for k, h in CHUNK_HEADERS.items()}
            plan = app.session.chunk_plan(pid, meta)
            if "received" in plan:
                self.close_connection = True  # its body stays unread
                return self.send(200, {"ok": True, "received": plan["received"], "repeat": True})
            if length != plan["length"]:
                code = 413 if length > plan["length"] else 400
                raise DomainError(code, "body-too-large" if code == 413 else "bad-field", f"This piece is {plan['length']} bytes.", field="Content-Length", max=plan["length"])
            with app.reading_chunk(pid):
                try:
                    raw = self.read_body(length, session.CHUNK_SECONDS)
                except TimeoutError:
                    raise DomainError(408, "body-timeout", f"A piece must arrive within {session.CHUNK_SECONDS:.0f} s.") from None
                except OSError:
                    raw = None
                if raw is None:
                    self.close_connection = True
                    return None
                out = app.session.upload_chunk(pid, meta, raw)
        except DomainError as exc:
            return self.fail(exc)
        except Exception:  # a bug: the transaction rolled back, so nothing was written
            return self.crash()
        app.changed()
        return self.send(200, {"ok": True, **out})

    def client_log(self, body):
        """POST /api/client-log (README "Logs"): one fault a joined person's page saw, appended to server.log as a
        client entry under their pid, or a usage summary, held for the next summary batch with no request entry.
        At most CLIENT_PER_MINUTE faults and SUMMARY_PER_MINUTE summaries a minute per person; it changes no state."""
        try:
            pid = self.authorize("person")
            usage = body.get("kind") in USAGE_KINDS
            if usage:
                self.pid = None  # before any refusal, so a refused summary's request entry names no one either
            fields = client_fields(body)
            if not (self.app.summary_bucket if usage else self.app.client_bucket).take(pid):
                n, what = (SUMMARY_PER_MINUTE, "summaries") if usage else (CLIENT_PER_MINUTE, "error reports")
                raise DomainError(429, "slow-down", f"At most {n} {what} a minute.")
        except DomainError as exc:
            return self.fail(exc)
        if usage:
            self.app.hold_summary(fields["message"], fields["ua"])
            self.unlogged = True
        else:
            self.app.log.warning("%s", entry("client", pid=pid, **fields))
        return self.send(200, {"ok": True})

    def refuse_method(self):
        if not self.refused():
            self.fail(DomainError(404, "not-found", "Nothing here."))

    do_PUT = do_DELETE = do_PATCH = do_OPTIONS = do_HEAD = refuse_method  # no CORS preflight is ever answered


# -- the process ------------------------------------------------------------------------------


class App:
    """Both listeners, the session and the tunnel watch for one data dir."""

    def __init__(self, data_dir, *, guest_port=0, control_port=0, nonce="", defaults_file=None, watch_tunnel=True):
        self.dir = Path(data_dir).resolve()
        problem = detached.data_dir_problem(self.dir)
        if problem:
            raise StartRefused(problem)
        self.dir.mkdir(parents=True, exist_ok=True)
        detached.make_private_dir(self.dir / session.STAGING)
        self.log = make_logger(self.dir)
        self.secrets = ensure_secrets(self.dir)
        self.session = open_session(self.dir, self.secrets, self.log, defaults_file=defaults_file)
        self.session.on_owner_token = self.owner_rotated
        swept = self.session.recover_uploads()
        if swept:
            self.log.info("uploads: deleted %d partial or unclaimed files", swept)
        self.build = build_hash()
        self._asset_key = secrets.token_bytes(32)  # signs asset cookies; a restart ends them, and the next poll renews them
        self.bucket = Bucket(session.RATE_PER_SECOND, session.RATE_BURST)
        self.client_bucket = Bucket(CLIENT_PER_MINUTE / 60, CLIENT_PER_MINUTE)  # keyed by pid
        self.image_bucket = Bucket(IMAGE_PER_MINUTE / 60, IMAGE_PER_MINUTE)  # GET /api/upload/image, keyed by pid
        self.summary_bucket = Bucket(SUMMARY_PER_MINUTE / 60, SUMMARY_PER_MINUTE)  # keyed by pid, kept in memory only
        self._summary_lock, self._summaries, self._summary_bytes, self._dropped = threading.Lock(), [], 0, 0
        self._batch_at = time.monotonic() + SUMMARY_BATCH_SECONDS
        self.watch_tunnel = watch_tunnel
        self.public_url = ""
        self.tunnel_host = ""
        self.retired_host = ""  # the address before a switch, while its tunnel still runs
        self.tunnel_up = False
        self._next_tunnel_try = 0.0
        self._backoff = 2.0
        self._last_sync = 0.0
        self._stop = threading.Event()
        self._chunk_lock, self._chunk_readers = threading.Lock(), set()
        self._probe_lock, self._probes = threading.Lock(), {}  # nonce asked -> (answer, expiry)
        self.guest = GuestServer(("127.0.0.1", guest_port), GuestHandler)
        self.guest.app = self
        self.guest_port = self.guest.server_address[1]
        self.local_hosts = {f"127.0.0.1:{self.guest_port}", f"localhost:{self.guest_port}"}
        self.asset_cookie = f"shared-assets-{self.guest_port}"  # cookies ignore the port: two local sessions keep their own
        handler = type("SharedControlHandler", (ControlHandler,), {})  # its own class: start() sets hub on it
        self.control, self.hub = session_bridge.start(handler, lambda port: ControlHub(port, self.dir, self), control_port, nonce)
        self.control_port = self.hub.port
        detached.write_private(self.dir / PORTS, json.dumps({"guest": self.guest_port, "control": self.control_port}) + "\n")
        self.write_owner_link()
        self.sync_tunnel(restart=False)  # a tunnel start can outlast share.py's wait for this one: share.py or the watch starts it
        self.log.info("started: guest %d, control %d, build %s", self.guest_port, self.control_port, self.build)

    @contextlib.contextmanager
    def reading_chunk(self, pid):
        """One upload piece in flight per person, so slow senders hold at most one connection each."""
        with self._chunk_lock:
            if pid in self._chunk_readers:
                raise DomainError(409, "wrong-status", "A piece of your file is on its way already.", status="sending")
            self._chunk_readers.add(pid)
        try:
            yield
        finally:
            with self._chunk_lock:
                self._chunk_readers.discard(pid)

    def hold_summary(self, message, ua):
        """Keep a usage summary for the next batch; one past SUMMARY_BATCH_BYTES is only counted, as dropped."""
        item = [message, ua or ""]
        size = len(batch_json([item]))
        with self._summary_lock:
            if self._summary_bytes + size > SUMMARY_BATCH_BYTES:
                self._dropped += 1
            else:
                self._summaries.append(item)
                self._summary_bytes += size

    def flush_summaries(self):
        """One summary-batch entry (README "Logs") for the summaries held since the last, sorted so their arrival order
        is gone too; none when there were none."""
        with self._summary_lock:
            items, dropped = sorted(self._summaries), self._dropped
            self._summaries, self._summary_bytes, self._dropped = [], 0, 0
            self._batch_at = time.monotonic() + SUMMARY_BATCH_SECONDS
        if items or dropped:
            self.log.info("summary-batch summaries=%d dropped=%d data=%s", len(items), dropped, batch_json(items))

    def asset_sign(self, pid, exp):
        return hmac.new(self._asset_key, f"{pid}.{exp}".encode(), hashlib.sha256).hexdigest()

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
        public = {h for h in (self.tunnel_host, self.retired_host) if h}
        if host not in self.local_hosts and host not in public:
            now = time.monotonic()
            if now - self._last_sync > 1.0:  # a tunnel share.py just started may not be seen yet
                self._last_sync = now
                self.sync_tunnel(restart=False)
            public = {h for h in (self.tunnel_host, self.retired_host) if h}
            if host not in public:
                return False
        if origin is None:
            return True
        return origin in {f"http://{h}" for h in self.local_hosts} or origin in {f"https://{h}" for h in public}

    def answer_probe(self, nonce):
        """The answer to a pending probe nonce, once, else None."""
        with self._probe_lock:
            now = time.monotonic()
            self._probes = {k: v for k, v in self._probes.items() if v[1] > now}
            hit = self._probes.pop(nonce, None)
        return hit[0] if hit else None

    def probe_tunnel(self, url):
        """None once `url` (an https address) reaches this server: a fetch of <url>/api/tunnel-probe/<nonce> gets back the
        answer only this process knows. Else why not, after PROBE_SECONDS of tries."""
        if urlparse(url).scheme != "https" or not urlparse(url).hostname:
            return f"{url!r} is not an https address"
        nonce, answer = secrets.token_hex(16), secrets.token_hex(16)
        seconds = float(os.environ.get("SHARED_PROBE_SECONDS") or PROBE_SECONDS)
        with self._probe_lock:
            self._probes[nonce] = (answer, time.monotonic() + seconds + 5)
        deadline, why = time.monotonic() + seconds, "no answer"
        while True:
            conn, host = probe_target(url)
            try:
                conn.request("GET", f"/api/tunnel-probe/{nonce}", headers={"Host": host})
                resp = conn.getresponse()
                body = resp.read(4096)
                try:
                    got = json.loads(body).get("probe") if resp.status == 200 else None
                except (ValueError, AttributeError):
                    got = None
                if got == answer:
                    return None
                why = f"HTTP {resp.status}" + (", and not this server's answer" if resp.status == 200 else "")
            except (OSError, http.client.HTTPException) as exc:
                why = str(exc) or type(exc).__name__
            finally:
                conn.close()
            if time.monotonic() >= deadline:
                with self._probe_lock:
                    self._probes.pop(nonce, None)
                self.log.warning("tunnel check: %s does not reach this server (%s)", url, loggable(why))
                return f"{url} does not reach this server ({why})"
            time.sleep(1.0)

    def moved(self, host):
        """True when `host` is the retired tunnel's: the session now answers at public_url."""
        return bool(self.retired_host) and host == self.retired_host and host != self.tunnel_host and bool(self.public_url)

    def etag(self, pid):
        tick = int(time.time() // PRESENCE_TICK)
        who = hashlib.sha256(pid.encode()).hexdigest()[:8]
        st = self.session.state
        return f'"{st["rev"]}.{who}.{self.build}.{int(self.tunnel_up)}.{self.session.presence_rev()}.{tick}"'

    def changed(self):
        with self.hub.cond:
            self.hub.cond.notify_all()

    def sync_tunnel(self, restart=True):
        """Follow the tunnel record: allow its host, record its link, restart it when it exited."""
        rec = tunnel.read(self.dir)
        if rec is None:
            self.tunnel_up = False
            self.retired_host = ""
            return
        old = tunnel.retired(self.dir)
        self.retired_host = tunnel.host(old["url"]) if old else ""
        live = tunnel.alive(self.dir)
        if (live is None or live.get("port") != self.guest_port) and restart and self.watch_tunnel:
            if time.monotonic() < self._next_tunnel_try:
                self.tunnel_up = False
                return
            try:
                live = tunnel.ensure(self.dir, self.guest_port, *tunnel.config(rec))  # a named tunnel comes back at its address
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
                tunnel.sweep(self.dir)
                self.sync_tunnel()
                if time.monotonic() >= self._batch_at:
                    self.flush_summaries()
            except Exception:  # the watch must outlive any one bad pass
                self.log.error("%s", entry("tunnel-watch", trace=trace()))

    def serve(self):
        """Serve both listeners and watch the tunnel in threads; returns at once."""
        loops = (lambda: self.guest.serve_forever(poll_interval=0.1), lambda: self.control.serve_forever(poll_interval=0.1), self.watch)
        self.threads = [threading.Thread(target=t, daemon=True) for t in loops]
        for t in self.threads:
            t.start()

    def shutdown(self):
        self._stop.set()
        serving = getattr(self, "threads", None)  # shutdown() waits for serve_forever, so only once serving
        if serving:
            self.guest.shutdown()
        self.flush_summaries()  # before the control listener goes, so `share.sh stop` returns after it
        if serving:
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
    a = p.parse_args(argv)
    try:
        app = App(a.dir, guest_port=a.guest_port, control_port=a.control_port, nonce=a.nonce, defaults_file=a.defaults_file)
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

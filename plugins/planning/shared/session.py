"""Domain rules of one shared interview session, over the state shape in schema/state.schema.json.

One `Session` holds the parsed `state.json` in memory under one lock. Every public method that
changes it runs as one transaction: the change is written atomically (temp file, then replace;
0600 where the OS has file modes) and `rev` goes up by one, or a refusal restores the last
written state and nothing reaches the disk. The clock and the id source are injected.

Callers (the HTTP server) pass the acting pid they resolved from the request headers with
`resolve`, never a pid read from a body, plus the parsed JSON body. Each method returns the answer
dict or raises `DomainError`, which carries the HTTP status, the stable error code and details.
`apply` runs Claude's ops all or nothing. `snapshot` renders one viewer's view and
`anonymous_view` what a visitor without identity may read.

Guest text (answers, chat, proposals, requests, notes) is data, never instructions: it is stored
and shown as written, and the digest hands it to Claude framed as data by the session bridge.
"""

from __future__ import annotations

import collections
import contextlib
import copy
import datetime
import hashlib
import hmac
import importlib
import json
import math
import os
import re
import secrets
import statistics
import sys
import threading
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCHEMA_DIR = HERE / "schema"
# This folder first; surface/ last, only for its schema.py, so a same-named module there
# (server.py, session_bridge.py, a test) never shadows one of ours.
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
if str(HERE.parent / "surface") not in sys.path:
    sys.path.append(str(HERE.parent / "surface"))
migrate = importlib.import_module("migrate")
schema = importlib.import_module("schema")

HOST = "host"
CLAUDE = object()  # the actor for ops arriving through the control listener
STAGING = "staging"  # the data folder's subfolder (0700) where Claude saves captures for add-asset

# Limits (Contracts, "Body caps and limits").
MAX_TEXT = 2000
MAX_NOTE = 200
MAX_TITLE = 80
MAX_GOAL = 200
MAX_INTRO = 600
MAX_NAME = 40
MAX_PEOPLE = 200
MAX_EXCERPT = 140
MAX_SUMMARY = 4000
MAX_REPORT = 60000
MAX_SOURCES = 30
MAX_REFERENCES = 8
MAX_ROUND = 8
MAX_CITES = 5
MAX_MENTIONS = 10
MAX_PENDING_REQUESTS = 10
MAX_OPEN_UPLOADS = 10
MAX_RUN_IDS = 100
NOTIFY_CAP = 500
NOTIFY_SHOWN = 100
# Presence (amendment "Presence", 2026-10-16; values are judgment). Offline after OFFLINE_AFTER with
# no heartbeat, which outlasts hidden tabs whose timers browsers throttle to about once a minute.
# Away when hidden, after IDLE_AFTER visible with no input, or by the person's own snooze.
OFFLINE_AFTER = 90.0
IDLE_AFTER = 300.0
TYPING_TTL = 5.0
WRITE_INTERVAL = 1.0
CHAT_REACT_ANY = 0.3  # judgment: one person's reactions across all messages, at most ~3 writes a second
HEARTBEAT_INTERVAL = 1.0  # judgment: the page beats every 2 s per tab, plus one on a visibility change
MAX_TABS = 8  # judgment: tabs and devices tracked per person; a ninth forgets the least recent
TAB_ID = re.compile(r"[A-Za-z0-9_-]{1,32}")  # the page sends 24 hex characters
JOIN_WINDOW = 60.0
JOINS_PER_WINDOW = 30
JOIN_KEY_WINDOW = 600.0
JOINS_PER_KEY = 60  # judgment: per guest key across all addresses, above JOINS_PER_WINDOW so one office NAT joins at once
MAX_CHAT = 2000  # the newest messages kept, so chat cannot grow state.json without bound
MAX_ANNOTATIONS = 2000  # judgment: notes kept across all prototype questions, oldest dropped first
MAX_SUGGESTIONS = 200  # judgment: suggestions kept per question, oldest dropped first
MAX_HISTORY = 50  # judgment: earlier versions kept per answer the owner hid or edited; the original stays, the oldest after it go first
MAX_CHAT_EMOJI = 20  # distinct emoji on one chat message (Phase 4c item 6)
MAX_MY_CHAT_EMOJI = 6  # judgment: emoji one person puts on one chat message
MAX_WAITING = 20  # judgment: joins waiting under Approve new joins; the owner lets them in before more can wait
RATE_PER_SECOND = 100.0  # requests per address on the guest listener: 20 people behind one NAT fit
RATE_BURST = 200.0
RATE_KEYS = 10000  # judgment: addresses the rate limit remembers; the least recently seen is forgotten first
BODY_SECONDS = 10.0  # judgment: a whole 32 KB body arrives well within this on a slow phone link
MAX_HANDLERS = 64  # judgment: concurrent guest connections; 20 people and the tunnel's pool fit well under it
VOTE_ROLLUP_WINDOW = 3600.0
BODY_MAX = 32 * 1024
OFFER_MAX = 96 * 1024
OPS_MAX = 1024 * 1024
CHUNK_SIZE = 8 * 1024 * 1024
GUEST_UPLOAD_MAX = 100 * 1024 * 1024
SESSION_UPLOAD_MAX = 5 * 1024 * 1024 * 1024
ASSET_MAX = 10 * 1024 * 1024

COLORS = tuple(f"c{i}" for i in range(1, 11))
ROLES = ("owner", "leader", "guest")
PURPOSES = ("decide", "gather", "poll")
FORMATS = ("text", "choice", "multi", "scale", "rank", "confirm", "prototype")
# Options Claude writes per format (amendment "Reactions and formats"); the server adds Something else.
OPTION_COUNTS = {"choice": (2, 4), "multi": (2, 8), "rank": (3, 6)}
OTHER_OPTION = migrate.OTHER_OPTION
OTHER = OTHER_OPTION["id"]
VIEWS = ("focus", "compare", "tree", "host", "prototype")
DEVICES = ("phone", "tablet", "computer")
BROWSERS = ("chrome", "safari", "firefox", "edge", "samsung", "in-app", "other")
REACTIONS = ("thumbs", "down", "heart", "idea")
REQUEST_KINDS = ("ask", "research", "explore", "design", "prototype")
USED_TYPES = ("skill", "workflow", "mcp", "cli")
TECH_COMFORT = ("low", "ok", "high")
NOTIFY_KINDS = ("mention", "reply", "request", "proposal", "round", "merge", "role", "queue", "ready", "votes", "reaction")
# Chat reactions (Phase 4c item 6): the quick row first, then the picker's general set. web/app.js holds the
# same list (CHAT_EMOJI there); test_session.py checks that the two match.
CHAT_EMOJI = (
    "👍", "👎", "😂", "❤️", "🎉", "😮",
    "😀", "😃", "😄", "😁", "😆", "😅", "🤣", "🙂", "🙃", "😉", "😊", "😇", "🥰", "😍",
    "🤩", "😘", "😋", "😛", "😜", "🤪", "🤗", "🤭", "🤫", "🤔", "🤐", "🤨", "😐", "😑",
    "😶", "😏", "😒", "🙄", "😬", "😌", "😔", "😪", "😴", "😷", "🤒", "🤯", "🥳", "😎",
    "🤓", "🧐", "😕", "😟", "🙁", "😯", "😲", "😳", "🥺", "😢", "😭", "😱", "😤", "😡",
    "👏", "🙌", "👀", "🙏", "💪", "👋", "🤝", "✅", "❌", "💯", "🔥", "✨", "⭐", "💡",
    "🚀", "🎯", "📌", "⚠️",
)
SEQ_KEYS = ("P", "S", "R", "X", "M", "G", "U", "N", "A")

QID = re.compile(r"Q[1-9][0-9]{0,5}")
ASSET = re.compile(r"[0-9a-f]{16}\.(png|jpg|webp|svg|html)")
IMAGE_ASSET = migrate.IMAGE_ASSET
SVG_ASSET = re.compile(r"[0-9a-f]{16}\.svg")
VARIANT = re.compile(r"v-[1-9][0-9]?")
URL = migrate.URL
PREF_ROUND = re.compile(r"all|[1-9][0-9]{0,3}")

DEFAULT_SETTINGS = {
    "voting": True,
    "signoff": False,
    "chat": True,
    "follow": True,
    "names": "full",
    "digestNames": False,
    "uploads": False,
    "claudeTake": "answerFirst",
    "theme": {"mode": "system", "accent": "teal"},
}
# Settings a session gains only once the owner sets one, so a state file written before them stays as
# it was (and still loads in the build before them) until then.
OPTIONAL_SETTINGS = {"approveJoins": False}
SETTING_VALUES = {
    "names": ("full", "initials", "someone"),
    "claudeTake": ("answerFirst", "always"),
}
THEME_VALUES = {"mode": ("system", "light", "dark"), "accent": ("teal", "indigo", "violet", "amber")}


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


PREFS = {
    "claudeTake": lambda v: v in ("answerFirst", "always"),
    "sort": lambda v: v in ("new", "votes", "unanswered"),
    "filter": lambda v: v in ("all", "open", "locked", "review", "mine", "research"),
    "round": lambda v: isinstance(v, str) and PREF_ROUND.fullmatch(v) is not None,
    "expandedRounds": lambda v: isinstance(v, list) and len(v) <= 100 and all(_is_int(n) and 1 <= n <= 9999 for n in v),
    "theme": lambda v: v in THEME_VALUES["mode"],
    "accent": lambda v: v in THEME_VALUES["accent"],
    "follow": lambda v: isinstance(v, bool),
    "mute": lambda v: isinstance(v, list) and len(v) <= len(NOTIFY_KINDS) and all(k in NOTIFY_KINDS for k in v),
    "tour": lambda v: v in ("done", "skipped"),
    "toolbar": lambda v: v in ("simple", "full"),
}

# Round state machine (Contracts, "Round state machine"): (from status, action) -> (who, to status).
# Opening round 1, or the round after a closed one, needs no active round and is checked in `_op_open_round`.
ROUND_TRANSITIONS = {
    ("open", "ready"): ("moderator", "open"),
    ("open", "send"): ("owner", "sent"),
    ("sent", "cancel"): ("owner", "open"),
    ("sent", "ack"): ("claude", "working"),
    ("working", "open-round"): ("claude", "closed"),
    ("working", "close-round"): ("claude", "closed"),
    ("working", "reset"): ("owner", "open"),
}

# Moderator proposal actions: action -> statuses it applies to.
PROPOSAL_ACTIONS = {
    "question": ("new", "parked", "not-placed", "later"),
    "park": ("new", "not-placed"),
    "restore": ("parked", "not-placed", "later"),
    "later": ("new", "parked", "not-placed"),
}


class DomainError(Exception):
    """A refusal: HTTP status, stable error code (Contracts, "Errors"), one-sentence message, details."""

    def __init__(self, http, code, message, **details):
        super().__init__(message)
        self.http = http
        self.code = code
        self.message = message
        self.details = details

    def body(self):
        return {"error": self.code, "message": self.message, **self.details}


class Ids:
    """The production id source; tests inject a deterministic one with the same two methods."""

    def token(self, nbytes):
        return secrets.token_urlsafe(nbytes)

    def hex(self, nbytes):
        return secrets.token_hex(nbytes)


def state_error(doc):
    """The first schema error in a session document, or None."""
    return schema.first_error(doc, schema.load("state", SCHEMA_DIR))


def ops_error(doc):
    """The first schema error in an ops document, or None."""
    return schema.first_error(doc, schema.load("ops", SCHEMA_DIR))


def wire_error(body, shape):
    """The first error in an in-memory wire body (`heartbeat`, `presence` in wire.schema.json), or None."""
    wire = schema.load("wire", SCHEMA_DIR)
    return schema.first_error(body, wire["$defs"][shape], "$", wire)


def cross_field_errors(doc):
    """The session rules the schema cannot express, each broken one as a sentence: dependsOn names
    only earlier questions, no two review flags share because and why, a round holds at most 8, a
    question holds at most one Something else option, the one with id `other` and `other: true`, no
    session secret names the owner (only the owner link does), and every link and asset name is
    one a write route takes (the schema's url and assetId patterns, which schema.py does not check)."""
    errors, seen, per_round = [], set(), {}
    if HOST in doc["credentials"]["secrets"].values():
        errors.append("A session secret names the owner; only the owner link may.")
    if any(m["status"]["kind"] == "pending" and HOST in (m["from"], m["to"]) for m in doc["mergeRequests"]):
        errors.append("A pending merge request names the owner; the owner cannot be merged.")
    errors += [f"{where} is not a link or asset name a write route takes." for where in _bad_links_and_assets(doc)]
    for q in doc["questions"]:
        later = [d for d in q["dependsOn"] if d not in seen]
        if later:
            errors.append(f"{q['id']} depends on {', '.join(later)}, not an earlier question.")
        flags = [(f["because"], json.dumps(f["why"], sort_keys=True)) for f in q["needsReview"]]
        if len(set(flags)) != len(flags):
            errors.append(f"{q['id']} holds two review flags with the same because and why.")
        others = [o for o in q["format"].get("options", []) if o.get("other") or o["id"] == OTHER]
        if len(others) > 1 or any(not (o.get("other") and o["id"] == OTHER) for o in others):
            errors.append(f"{q['id']} holds more than one Something else option, or one without both its id and its flag.")
        seen.add(q["id"])
        per_round[q["round"]] = per_round.get(q["round"], 0) + 1
    errors += [f"Round {n} holds {k} questions; the most is {MAX_ROUND}." for n, k in sorted(per_round.items()) if k > MAX_ROUND]
    return errors


def _bad_links_and_assets(doc):
    """Where the document holds a link that is not http(s) or an asset name write routes refuse."""
    bad = []
    share = doc["session"]["share"]["url"]
    if share and not URL.fullmatch(share):
        bad.append("session.share.url")
    for q in doc["questions"]:
        fmt, at = q["format"], f"questions[{q['id']}]"
        checks = [(IMAGE_ASSET, o["image"], f"{at}.format.options.image") for o in fmt.get("options", []) if "image" in o]
        checks += [(ASSET, v["asset"], f"{at}.format.variants.asset") for v in fmt.get("variants", [])]
        if fmt["kind"] == "confirm":
            checks.append((IMAGE_ASSET, fmt["image"], f"{at}.format.image"))
        for r in q["references"]:
            if r["kind"] == "image":
                checks.append((IMAGE_ASSET, r["asset"], f"{at}.references.asset"))
            elif r["kind"] == "diagram":
                checks.append((SVG_ASSET, r["asset"], f"{at}.references.asset"))
            elif "url" in r:
                checks.append((URL, r["url"], f"{at}.references.url"))
        bad += [where for pattern, v, where in checks if not pattern.fullmatch(v)]
    for qid, results in doc["results"].items():
        bad += [f"results[{qid}].sources.url" for r in results for s in r["sources"] if not URL.fullmatch(s["url"])]
    return list(dict.fromkeys(bad))


def document_error(doc):
    """The first schema or cross-field error in a session document, or None."""
    return state_error(doc) or next(iter(cross_field_errors(doc)), None)


def sha256(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def iso(ts):
    return datetime.datetime.fromtimestamp(ts, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def one_line(text):
    return " ".join(str(text).split())


def initials(name):
    return " ".join(w[0] for w in str(name or "?").split()[:2]).upper() or "?"


def replace_into(tmp, path):
    """os.replace with retry: Windows refuses while a reader holds the target open."""
    for _ in range(20):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.05)
    os.unlink(tmp)
    raise OSError(f"could not replace {path}")


def write_private(path, text):
    """Atomic write of a file only its owner may read: created 0600 (advisory on Windows)."""
    path = Path(path)
    tmp = path.with_name(f"{path.name}.{secrets.token_hex(4)}.tmp")
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
            f.write(text)
            f.flush()
            os.fsync(f.fileno())
        replace_into(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def _edited(card):
    """The digest's mark on an answer the owner edited: it carries the current text."""
    return {"edited": True} if "edited" in card else {}


def card_ref(card):
    if card["kind"] == "person":
        return f"p:{card['pid']}" + (f":{card['device']}" if card.get("device") else "")
    if card["kind"] == "claude":
        return f"c:{card['key']}"
    return f"o:{card['option']}"


def _moderated(card):
    """Whether the owner hid or edited this person card (or a cleared one): only then are its versions kept."""
    return any(k in card for k in ("hidden", "edited", "history"))


def _answer_where(qid):
    return f"in an answer on question {qid}"


def ref_author(ref):
    """The pid that wrote a person card, from its ref, or None for Claude and option cards."""
    return ref.split(":")[1] if ref.startswith("p:") else None


# -- input parsing: every route and op body goes through these before any state changes ------


def _bad(field, message):
    return DomainError(400, "bad-field", message, field=field)


def _body(body):
    if not isinstance(body, dict):
        raise _bad("body", "The request body must be a JSON object.")
    return body


def _text(body, field, *, limit=MAX_TEXT, empty_ok=False, optional=False):
    """A trimmed string of 1..limit characters (0.. with empty_ok); refused when longer, never cut."""
    v = _body(body).get(field)
    if v is None:
        if optional:
            return None
        if empty_ok:
            return ""
        raise DomainError(400, "empty", f"{field} is empty.", field=field)
    if not isinstance(v, str):
        raise _bad(field, f"{field} must be a string.")
    v = v.strip()
    if not v and not empty_ok:
        raise DomainError(400, "empty", f"{field} is empty.", field=field)
    if len(v) > limit:
        raise DomainError(400, "too-long", f"{field} allows at most {limit} characters.", field=field, max=limit)
    return v


def _choice(body, field, allowed, *, optional=False):
    v = _body(body).get(field)
    if v is None and optional:
        return None
    if v not in allowed:
        raise _bad(field, f"{field} must be one of {', '.join(map(str, allowed))}.")
    return v


def _bool(body, field, *, default=False):
    v = _body(body).get(field, default)
    if not isinstance(v, bool):
        raise _bad(field, f"{field} must be true or false.")
    return v


def _ident(body, field, *, optional=False):
    v = _body(body).get(field)
    if v is None and optional:
        return None
    if not isinstance(v, str) or not v or len(v) > 100:
        raise _bad(field, f"{field} must name an id.")
    return v


def _url(v, field):
    if not isinstance(v, str) or len(v) > MAX_TEXT or not URL.fullmatch(v.strip()):
        raise _bad(field, f"{field} must be a link starting with http:// or https://.")
    return v.strip()


def _device_info(v):
    """{kind, browser, screen: {w, h}} with the screen rounded to 10 CSS px; nothing else is kept."""
    if v is None:
        return None
    if not isinstance(v, dict):
        raise _bad("deviceInfo", "deviceInfo must be an object.")
    kind = _choice(v, "kind", DEVICES)
    browser = v.get("browser") if v.get("browser") in BROWSERS else "other"
    screen = v.get("screen")
    if not isinstance(screen, dict) or not all(_is_int(screen.get(k)) and 0 <= screen[k] < 100000 for k in ("w", "h")):
        raise _bad("deviceInfo", "deviceInfo.screen must be {w, h} in CSS pixels.")
    return {"kind": kind, "browser": browser, "screen": {k: int(round(screen[k], -1)) for k in ("w", "h")}}


def _rect(v, field):
    if not isinstance(v, dict) or set(v) - {"x", "y", "w", "h"}:
        raise _bad(field, f"{field} must be {{x, y, w, h}}.")
    out = {}
    for k in ("x", "y", "w", "h"):
        n = v.get(k)
        if isinstance(n, bool) or not isinstance(n, (int, float)) or not math.isfinite(n) or n < 0 or (k in ("w", "h") and n <= 0):
            raise _bad(field, f"{field}.{k} must be a finite number at least 0 (w and h above 0).")
        out[k] = n
    # Checked on writes only: a state.json written before the unit was enforced keeps its rects and loads.
    if out["x"] + out["w"] > 100 or out["y"] + out["h"] > 100:
        raise _bad(field, f"{field} is in percent (0-100) of the image or page: x + w and y + h must each be at most 100.")
    return out


def _sources(v):
    if v is None:
        return []
    if not isinstance(v, list) or len(v) > MAX_SOURCES:
        raise DomainError(400, "too-long", f"sources allows at most {MAX_SOURCES} entries.", field="sources", max=MAX_SOURCES)
    out = []
    for i, src in enumerate(v):
        if not isinstance(src, dict):
            raise _bad(f"sources[{i}]", "Each source is {title, url}.")
        url = _url(src.get("url"), f"sources[{i}].url")
        title = src.get("title") if isinstance(src.get("title"), str) else ""
        out.append({"title": one_line(title)[:MAX_NOTE] or url, "url": url})
    return out


def _used(v):
    if not isinstance(v, list) or len(v) > 20:
        raise _bad("used", "used must list what ran, as {name, type}.")
    out = []
    for i, u in enumerate(v):
        if not isinstance(u, dict) or not isinstance(u.get("name"), str) or not u["name"].strip():
            raise _bad(f"used[{i}]", "Each entry of used needs a name.")
        out.append({"name": u["name"].strip()[:MAX_NOTE], "type": _choice(u, "type", USED_TYPES)})
    return out


ASSET_KINDS = {"png": "image", "jpg": "image", "webp": "image", "svg": "svg", "html": "html"}
ASSET_MAGIC = ((b"\x89PNG\r\n\x1a\n", "png"), (b"\xff\xd8\xff", "jpg"))


def _asset_source(path, root):
    """An existing regular file under `root` with no hidden part below it; refused otherwise."""
    if not isinstance(path, str) or not os.path.isabs(path):
        raise _bad("path", "path must be an absolute path to a local file.")
    try:
        real = Path(path).resolve(strict=True)
        base = Path(root).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise _bad("path", f"No file at {path}.") from exc
    if not real.is_relative_to(base):
        raise _bad("path", f"add-asset reads files only from the session's data folder; save captures in {base / STAGING}.")
    if not real.is_file() or any(part.startswith(".") for part in real.relative_to(base).parts):
        raise _bad("path", "path must name a regular file with no hidden folder or name.")
    return real


def _asset_type(data, wanted):
    """The extension the bytes prove: png, jpg and webp by magic number, svg and html by their opening markup."""
    found = next((ext for magic, ext in ASSET_MAGIC if data.startswith(magic)), None)
    if found is None and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        found = "webp"
    if found is None:
        head = data[:2048].decode("utf-8", "replace").lstrip("﻿ \t\r\n").lower()
        if head.startswith(("<!doctype html", "<html")):
            found = "html"
        elif head.startswith(("<svg", "<?xml")) and "<svg" in head:
            found = "svg"
    if found is None:
        raise _bad("path", "The file is not a PNG, JPEG, WebP, SVG or HTML file.")
    want = {"jpeg": "jpg"}.get(wanted, wanted)
    if want is not None and want != found:
        raise _bad("as", f"as says {wanted}, but the file is {found}.")
    return found


class Session:
    """One shared interview session: the parsed state under one lock, with an injected clock and ids."""

    def __init__(self, path, state, *, clock=time.time, ids=None, validate_writes=False, assets_dir=None, plugin_version=""):
        self.path = Path(path)
        self.state = state
        self.clock = clock
        self.ids = ids or Ids()
        self.validate_writes = validate_writes
        self.assets_dir = Path(assets_dir) if assets_dir else self.path.parent / "assets"
        self.plugin_version = plugin_version
        self._lock = threading.RLock()
        self._saved = json.dumps(state, ensure_ascii=False)
        self._presence = {}  # pid -> {"at": join time, "device"?, "tabs": tab -> beat, least recent first}; never persisted
        self._presence_rev = 0
        self._last_write = collections.OrderedDict()  # (pid, route) -> time of the last accepted write, oldest first
        self._joins = collections.OrderedDict()  # (guest key, address) -> times of recent joins, least recent first
        self._key_joins = {}  # guest key -> times of recent joins from any address
        self._base_cache = None
        self._undo = []  # (file, bytes before or None) an apply wrote, put back when the apply is refused
        self.on_owner_token = None  # called with (token, rotatedAt) inside the rotation, before it commits

    # -- construction and persistence ---------------------------------------------------------

    @classmethod
    def create(
        cls,
        path,
        *,
        title,
        goal="",
        settings=None,
        owner_name="Host",
        plugin_version="",
        clock=time.time,
        ids=None,
        validate_writes=False,
        assets_dir=None,
        owner_token=None,
    ):
        """A new session file at `path` (refused when one exists) -> (Session, owner token).

        `owner_token` is a token the caller already holds (the server reads it from a 0600 file);
        without one a new token is made."""
        path = Path(path)
        if path.exists():
            raise FileExistsError(f"{path} already exists")
        ids = ids or Ids()
        now = float(clock())
        title = _text({"title": title}, "title", limit=MAX_TITLE)
        goal = _text({"goal": goal}, "goal", limit=MAX_GOAL, empty_ok=True)
        name = _text({"name": owner_name}, "name", limit=MAX_NAME)
        token = owner_token or ids.token(32)
        state = {
            "schemaVersion": migrate.CURRENT,
            "pluginVersion": plugin_version,
            "writtenBy": plugin_version,
            "rev": 0,
            "session": {
                "title": title,
                "goal": goal,
                "createdAt": now,
                "phase": {"kind": "live"},
                "share": {"url": ""},
                "guestKey": "",
                "settings": _settings_patch(copy.deepcopy(DEFAULT_SETTINGS), settings or {}),
                "seq": {k: 0 for k in SEQ_KEYS},
            },
            "people": {
                HOST: {
                    "pid": HOST,
                    "name": name,
                    "joinedAt": now,
                    "role": "owner",
                    "trusted": True,
                    "color": COLORS[0],
                    "status": {"kind": "active"},
                }
            },
            "credentials": {"owner": {"tokenHash": sha256(token), "rotatedAt": now}, "secrets": {}},
            "rounds": [],
            "questions": [],
            "cards": {},
            "votes": {},
            "reactions": {},
            "locks": {},
            "suggestions": {},
            "suggestionVotes": {},
            "proposals": [],
            "chat": [],
            "requests": [],
            "results": {},
            "uploads": [],
            "annotations": [],
            "prefs": {},
            "notifications": {},
            "mergeRequests": [],
            "aboutYou": {},
            "disagreements": {},
            "log": {"seq": 0, "events": [], "handled": []},
        }
        s = cls(path, state, clock=clock, ids=ids, validate_writes=validate_writes, assets_dir=assets_dir, plugin_version=plugin_version)
        s._write_current()
        return s, token

    @classmethod
    def load(cls, path, *, plugin_version="", clock=time.time, ids=None, validate_writes=False, assets_dir=None, notes=None):
        """Parse state.json once, migrating an older schemaVersion (old file kept as state.v<N>.json;
        the prototype's file, which has none, as state.v0.json). `notes` collects migration notes."""
        path = Path(path)
        raw = path.read_text(encoding="utf-8")
        try:
            doc = json.loads(raw)
        except ValueError as exc:
            raise DomainError(500, "state-invalid", f"{path.name} is not JSON: {exc}") from exc
        if not isinstance(doc, dict):
            raise DomainError(500, "state-invalid", f"{path.name} is not a JSON object.")
        old = migrate.version_of(doc)
        doc = migrate.migrate(doc, notes, float(clock()))
        err = document_error(doc)
        if err:
            raise DomainError(500, "state-invalid", f"{path.name}: {err}")
        s = cls(path, doc, clock=clock, ids=ids, validate_writes=validate_writes, assets_dir=assets_dir, plugin_version=plugin_version)
        if doc["schemaVersion"] != old:
            backup = path.with_name(f"{path.stem}.v{old}{path.suffix}")
            if not backup.exists():
                write_private(backup, raw)
            s._write_current()
        return s

    def _write_current(self):
        text = json.dumps(self.state, ensure_ascii=False, allow_nan=False)
        write_private(self.path, text + "\n")
        self._saved = text

    @contextlib.contextmanager
    def _tx(self):
        """One write: commit on success; on any refusal restore the last written state."""
        with self._lock:
            try:
                yield self.state
                self._commit()
            except BaseException:
                self.state = json.loads(self._saved)
                raise

    def _mutate(self, change):
        """Apply `change(state)` as one write. The seam the state-invalid guarantee is tested through."""
        with self._tx() as st:
            change(st)

    def _commit(self):
        st = self.state
        st["rev"] += 1
        if self.plugin_version:
            st["writtenBy"] = self.plugin_version
        try:
            text = json.dumps(st, ensure_ascii=False, allow_nan=False)
        except (TypeError, ValueError) as exc:
            raise DomainError(500, "state-invalid", f"Nothing was written: {exc}") from exc
        if self.validate_writes:
            err = document_error(st)
            if err:
                raise DomainError(500, "state-invalid", f"Nothing was written: {err}")
        elif HOST in st["credentials"]["secrets"].values():
            raise DomainError(500, "state-invalid", "Nothing was written: a session secret would name the owner.")
        write_private(self.path, text + "\n")
        self._saved = text

    def now(self):
        return float(self.clock())

    def _next(self, key):
        seq = self.state["session"]["seq"]
        seq[key] += 1
        return f"{key}{seq[key]}"

    # -- identity -----------------------------------------------------------------------------

    def resolve(self, *, secret=None, owner_token=None):
        """The pid a request acts as, from its X-Owner-Token or X-Session-Secret header value."""
        with self._lock:
            creds = self.state["credentials"]
            if owner_token:
                if hmac.compare_digest(sha256(owner_token), creds["owner"]["tokenHash"]):
                    return HOST
                raise DomainError(401, "unknown-session", "This owner link is no longer valid.")
            if secret:
                pid = creds["secrets"].get(sha256(secret))
                if pid:
                    self._person(pid)
                    return pid
            raise DomainError(401, "unknown-session", "Join the session again.")

    def _person(self, pid):
        person = self.state["people"].get(pid) if isinstance(pid, str) else None
        if person is None:
            raise DomainError(401, "unknown-session", "Join the session again.")
        if person["status"]["kind"] == "removed":
            raise DomainError(403, "removed", "The owner removed you from this session.")
        if person["status"]["kind"] == "waiting":
            raise DomainError(403, "waiting", "The host has not let you in yet.")
        return person

    def _ended(self):
        return self.state["session"]["phase"]["kind"] == "ended"

    def _writer(self, pid):
        """A person who may write now: active, and the owner while the session is ended."""
        person = self._person(pid)
        if self._ended() and pid != HOST:
            raise DomainError(403, "ended", "This session has ended.")
        return person

    def _moderator(self, pid):
        person = self._writer(pid)
        if person["role"] not in ("owner", "leader"):
            raise DomainError(403, "moderator-only", "Only the owner or a leader can do that.")
        return person

    def _owner(self, pid):
        person = self._writer(pid)
        if pid != HOST:
            raise DomainError(403, "owner-only", "Only the owner can do that.")
        return person

    def _active(self, pid):
        p = self.state["people"].get(pid)
        return p is not None and p["status"]["kind"] == "active"

    def _throttle(self, pid, route, now, interval=WRITE_INTERVAL):
        if now - self._last_write.get((pid, route), float("-inf")) < interval:
            raise DomainError(429, "slow-down", "Wait a moment before sending again.")

    def _wrote(self, pid, route, now):
        """Record an accepted write, dropping records too old to throttle anything (oldest first)."""
        key = (pid, route)
        keep = max(WRITE_INTERVAL, HEARTBEAT_INTERVAL)
        with self._lock:
            self._last_write.pop(key, None)
            self._last_write[key] = now
            while self._last_write:
                first = next(iter(self._last_write.values()))
                if now - first < keep:
                    break
                self._last_write.popitem(last=False)

    @contextlib.contextmanager
    def _write_as(self, pid, route, *, check=None):
        """One throttled write by pid on route: `check(pid)` (default `_writer`), then the 1 s limit."""
        now = self.now()
        with self._tx() as st:
            (check or self._writer)(pid)
            self._throttle(pid, route, now)
            yield st
        self._wrote(pid, route, now)

    @staticmethod
    def _seen(v):
        """When a person last showed: their latest beat from any tab, else their join."""
        return next(reversed(v["tabs"].values()))["seen"] if v["tabs"] else v["at"]

    def _present(self):
        now = self.now()
        return {p for p, v in self._presence.items() if now - self._seen(v) < OFFLINE_AFTER and self._active(p)}

    @staticmethod
    def _away_since(v, now):
        """When a present person went Away, or None while active: visible, input within IDLE_AFTER, no snooze."""
        since = []
        if v.get("awayAt") is not None:
            since.append(v["awayAt"])
        if not v.get("visible", True):
            since.append(v.get("hiddenAt", v["seen"]))
        input_at = v.get("inputAt", v["seen"])
        if now - input_at >= IDLE_AFTER:
            since.append(input_at + IDLE_AFTER)
        return min(since) if since else None

    # -- people ------------------------------------------------------------------------------

    def join(self, pid, body, *, address=""):
        """POST /api/join: `pid` is HOST when the request carried a valid owner token, else None."""
        body = _body(body)
        name = _text(body, "name", limit=MAX_NAME, empty_ok=True)
        key = body.get("key") if isinstance(body.get("key"), str) else ""
        device = _choice(body, "device", DEVICES, optional=True)
        browser = body.get("browser")
        browser = None if browser is None else browser if browser in BROWSERS else "other"
        now = self.now()
        if pid == HOST:
            with self._tx() as st:
                host = st["people"][HOST]
                if name and name != host["name"]:
                    host["name"] = self._unique_name(name, HOST)
                return {"pid": HOST, "name": host["name"]}
        with self._tx() as st:
            if self._ended():
                raise DomainError(403, "ended", "This session has ended.")
            guest_key = st["session"]["guestKey"]
            if guest_key and not hmac.compare_digest(key.encode(), guest_key.encode()):
                raise DomainError(403, "bad-guest-key", "This invite link is no longer valid; ask the host for the new one.")
            self._prune_joins(now)
            window = (guest_key, address)
            recent = [t for t in self._joins.get(window, []) if now - t < JOIN_WINDOW]
            if len(recent) >= JOINS_PER_WINDOW:
                raise DomainError(429, "join-rate", "Too many joins from here; wait a minute.")
            by_key = [t for t in self._key_joins.get(guest_key, []) if now - t < JOIN_KEY_WINDOW]
            if len(by_key) >= JOINS_PER_KEY:
                raise DomainError(429, "join-rate", "Too many people joined through this link just now; wait a few minutes, or ask the host for a new link.")
            waiting = st["session"]["settings"].get("approveJoins", False)
            if waiting and sum(1 for p in st["people"].values() if p["status"]["kind"] == "waiting") >= MAX_WAITING:
                raise DomainError(503, "waiting-full", f"{MAX_WAITING} people are already waiting to join. Ask the host to let them in, then try again.")
            self._make_room()
            new = self.ids.token(9)
            while new in st["people"] or new == HOST:
                new = self.ids.token(9)
            secret = self.ids.token(32)
            here = self._present()
            was = None
            if name and st["session"]["settings"]["names"] == "full":  # otherwise the answer would reveal a hidden name
                was = next(
                    (
                        {"pid": p, "name": v["name"]}
                        for p, v in st["people"].items()
                        if p != HOST and p not in here and v["status"]["kind"] == "active" and v["name"].casefold() == name.casefold()
                    ),
                    None,
                )
            final = self._unique_name(name or self._guest_name(), new)
            hint = {k: v for k, v in (("device", device), ("browser", browser)) if v}
            st["people"][new] = {
                "pid": new,
                "name": final,
                "joinedAt": now,
                "role": "guest",
                "trusted": False,
                "color": self._free_color(),
                "status": {"kind": "waiting", "at": now, **hint} if waiting else {"kind": "active"},
            }
            st["credentials"]["secrets"][sha256(secret)] = new
            if waiting:
                self._queue_note([HOST], new)
                was = None
        with self._lock:
            self._joins.pop(window, None)
            self._joins[window] = recent + [now]
            self._key_joins[guest_key] = by_key + [now]
            if device:
                self._presence[new] = {"at": now, "device": device, "tabs": collections.OrderedDict()}
                self._presence_rev += 1
        return {"pid": new, "secret": secret, "name": final, **({"was": was} if was else {}), **({"waiting": True} if waiting else {})}

    def act_on_join(self, pid, body):
        """POST /api/join/act: the owner admits or declines one join waiting under Approve new joins.
        Declining removes the person, so their secret reads nothing until the owner restores them."""
        action = _choice(body, "action", ("admit", "decline"))
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if person["status"]["kind"] != "waiting":
                raise DomainError(409, "wrong-status", "This person is not waiting to join.", status=person["status"]["kind"])
            if action == "admit":
                person["status"] = {"kind": "active"}
            else:
                person["status"] = {"kind": "removed", "at": self.now(), "by": HOST}
            self._presence_rev += 1
            return {"pid": target, "status": person["status"]["kind"]}

    def _prune_joins(self, now):
        """Forget join records whose windows have passed, least recently joined first."""
        while self._joins:
            if now - next(iter(self._joins.values()))[-1] < JOIN_WINDOW:
                break
            self._joins.popitem(last=False)
        for key in [k for k, times in self._key_joins.items() if now - times[-1] >= JOIN_KEY_WINDOW]:
            self._key_joins.pop(key)

    def _unique_name(self, name, pid):
        taken = {v["name"].casefold() for p, v in self.state["people"].items() if p != pid}
        out, n = name, 2
        while out.casefold() in taken:
            suffix = f" {n}"
            out, n = name[: MAX_NAME - len(suffix)] + suffix, n + 1
        return out

    def _guest_name(self):
        taken = {v["name"].casefold() for v in self.state["people"].values()}
        n = sum(1 for p in self.state["people"] if p != HOST) + 1
        while f"guest {n}" in taken:
            n += 1
        return f"Guest {n}"

    def _free_color(self):
        used = [v["color"] for v in self.state["people"].values() if v["status"]["kind"] == "active"]
        free = [c for c in COLORS if c not in used]
        return free[0] if free else min(COLORS, key=used.count)

    def _holds_content(self, pid):
        st = self.state
        p = st["people"][pid]
        if pid == HOST or p["role"] != "guest" or p["trusted"] or p["status"]["kind"] == "waiting" or pid in self._present():
            return True  # a waiting person is never evicted; MAX_WAITING bounds them
        if any(c["kind"] == "person" and c["pid"] == pid for cards in st["cards"].values() for c in cards):
            return True
        if any(pid in by for by in [*st["votes"].values(), *st.get("backs", {}).values()]):
            return True
        records = [*st["proposals"], *st["chat"], *st["requests"], *st["annotations"], *st["uploads"]]
        records += [s for lst in st["suggestions"].values() for s in lst]
        records += [d for lst in st.get("disagreements", {}).values() for d in lst]
        records += [t for lst in st.get("cleared", {}).values() for t in lst]
        return any(r["pid"] == pid for r in records)

    def _make_room(self):
        st = self.state
        if len(st["people"]) < MAX_PEOPLE:
            return
        idle = [p for p in st["people"] if not self._holds_content(p)]
        if not idle:
            raise DomainError(503, "full", "This session is full.")
        gone = min(idle, key=lambda p: (self._seen(self._presence[p]) if p in self._presence else st["people"][p]["joinedAt"], p))
        self._forget(gone)

    def _forget(self, pid):
        st = self.state
        st["people"].pop(pid)
        for key in (st["prefs"], st["notifications"], st["aboutYou"]):
            key.pop(pid, None)
        for h in [h for h, p in st["credentials"]["secrets"].items() if p == pid]:
            st["credentials"]["secrets"].pop(h)
        self._presence.pop(pid, None)
        for key in [k for k in self._last_write if k[0] == pid]:
            self._last_write.pop(key)

    def heartbeat(self, pid, body):
        """POST /api/heartbeat (wire.schema.json `heartbeat`): memory only; allowed while the session
        is ended. Each `tab` (a page sends its own id; none is the tab "") keeps its own beat and its
        own limits, so one person's tabs and devices never refuse each other. A beat that changes
        `visible` or `away` is taken at once, outside the tab's one-a-second limit, since the page
        sends one the moment its visibility changes; such changes have their own one-a-second limit,
        so flipping visibility cannot flood. A person keeps MAX_TABS tabs, the least recent dropped."""
        body = _body(body)
        err = wire_error(body, "heartbeat")
        if err:
            m = re.match(r"\$\.(\w+)", err)
            raise _bad(m.group(1) if m else "body", err)
        if not math.isfinite(body.get("lastInput", 0)):  # json.loads takes Infinity and NaN
            raise _bad("lastInput", "lastInput must be a finite number of seconds.")
        tab = body.get("tab", "")
        if "tab" in body and not TAB_ID.fullmatch(tab):
            raise _bad("tab", "tab must name the tab: 1 to 32 letters, digits, - or _.")
        visible = body.get("visible", True)
        away = body.get("away") is True
        with self._lock:
            person = self._person(pid)
            now = self.now()
            rec = self._presence.setdefault(pid, {"at": now, "tabs": collections.OrderedDict()})
            old = rec["tabs"].get(tab)
            changed = old is not None and (old["visible"] != visible or (old.get("awayAt") is not None) != away)
            route = f"heartbeat-change:{tab}" if changed else f"heartbeat:{tab}"
            self._throttle(pid, route, now, HEARTBEAT_INTERVAL)
            recent = rec.setdefault("recent", collections.deque(maxlen=MAX_TABS))
            if len(recent) == MAX_TABS and now - recent[0] < HEARTBEAT_INTERVAL:
                raise DomainError(429, "slow-down", "Wait a moment before sending again.")
            old = old or {}
            beat = {
                "q": (body.get("q") or "")[:16],
                "typing": body.get("typing") is True,
                "chatTyping": body.get("chatTyping") is True,
                "seen": now,
                "visible": visible,
                "inputAt": now - body.get("lastInput", 0),
            }
            if not visible:
                beat["hiddenAt"] = old.get("hiddenAt", now) if not old.get("visible", True) else now
            if away:
                beat["awayAt"] = old.get("awayAt", now)
            tabs = rec["tabs"]
            tabs.pop(tab, None)
            for t in [t for t, b in tabs.items() if now - b["seen"] >= OFFLINE_AFTER]:
                tabs.pop(t)
            while len(tabs) >= MAX_TABS:
                tabs.popitem(last=False)
            tabs[tab] = beat
            self._presence_rev += 1
            self._wrote(pid, route, now)
            recent.append(now)
            if changed:
                self._wrote(pid, f"heartbeat:{tab}", now)
            return {"pid": pid, "name": person["name"], "role": person["role"], "trusted": person["trusted"]}

    def rename(self, pid, body):
        name = _text(body, "name", limit=MAX_NAME)
        with self._write_as(pid, "rename") as st:
            st["people"][pid]["name"] = self._unique_name(name, pid)
            return {"name": st["people"][pid]["name"]}

    def set_color(self, pid, body):
        color = _choice(body, "color", COLORS)
        with self._write_as(pid, "color") as st:
            st["people"][pid]["color"] = color
            return {"color": color}

    def set_about_you(self, pid, body):
        comfort = _choice(body, "techComfort", TECH_COMFORT)
        note = _text(body, "note", limit=MAX_NOTE, optional=True)
        with self._write_as(pid, "about-you") as st:
            st["aboutYou"][pid] = {"techComfort": comfort, **({"note": note} if note else {}), "at": self.now()}
            return {"techComfort": comfort}

    def _target_person(self, body, field="pid"):
        target = _ident(body, field)
        if target not in self.state["people"]:
            raise DomainError(404, "not-found", "No such person.", field=field)
        if target == HOST:
            raise _bad(field, "The owner's own role, trust and presence cannot change.")
        return target

    def set_role(self, pid, body):
        role = _choice(body, "role", ("leader", "guest"))
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if person["status"]["kind"] != "active":
                raise DomainError(409, "wrong-status", "Restore or admit this person first.", status=person["status"]["kind"])
            if person["role"] != role:
                person["role"] = role
                if role == "leader":
                    self._notify(target, "role", "You are now a leader: you can lock answers, mark rounds ready and place proposals.", actor=pid)
                else:
                    self._notify(target, "role", "You are no longer a leader.", actor=pid)
            return {"role": role}

    def set_trust(self, pid, body):
        on = _bool(body, "on")
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if person["status"]["kind"] != "active" and on:
                raise DomainError(409, "wrong-status", "Restore or admit this person first.", status=person["status"]["kind"])
            if person["trusted"] != on:
                person["trusted"] = on
                if on:
                    self._notify(target, "role", "The owner trusted you.", actor=pid)
            return {"trusted": on}

    def set_removed(self, pid, body):
        """POST /api/person/remove: removing clears leader and trust; the secret stops working until restored."""
        on = _bool(body, "on")
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if on:
                person.update(role="guest", trusted=False, status={"kind": "removed", "at": self.now(), "by": HOST})
                self._presence.pop(target, None)
            else:
                person["status"] = {"kind": "active"}
            self._presence_rev += 1
            return {"removed": on}

    def merge_people(self, pid, body):
        """POST /api/person/merge: everything `from` holds moves to `to`, then `from` is forgotten."""
        with self._tx():
            self._owner(pid)
            src = self._target_person(body, "from")
            dst = self._target_person(body, "to")
            if src == dst:
                raise _bad("to", "Pick two different people.")
            if "waiting" in (self.state["people"][src]["status"]["kind"], self.state["people"][dst]["status"]["kind"]):
                raise DomainError(409, "wrong-status", "Admit or decline the waiting join first.", status="waiting")
            self._merge(src, dst)
            return {"pid": dst}

    def request_merge(self, pid, body):
        """POST /api/merge-request: "Were you here before as <name>?"; the owner approves."""
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "merge-request", now)
            to = _ident(body, "to")
            if pid == HOST or to == HOST or to == pid:
                raise _bad("to", "Pick someone else who was here before.")
            if not self._active(to):
                raise DomainError(404, "not-found", "No such person.", field="to")
            if any(m["from"] == pid and m["status"]["kind"] == "pending" for m in st["mergeRequests"]):
                raise DomainError(409, "wrong-status", "You already asked; the owner has not answered yet.", status="pending")
            mid = self._next("G")
            st["mergeRequests"].append({"id": mid, "from": pid, "to": to, "at": now, "status": {"kind": "pending"}})
            self._queue_note([HOST], pid)
        self._wrote(pid, "merge-request", now)
        return {"id": mid}

    def act_on_merge_request(self, pid, body):
        action = _choice(body, "action", ("approve", "decline"))
        mid = _ident(body, "id")
        now = self.now()
        with self._tx() as st:
            self._owner(pid)
            m = next((m for m in st["mergeRequests"] if m["id"] == mid), None)
            if m is None:
                raise DomainError(404, "not-found", "No such merge request.")
            if m["status"]["kind"] != "pending":
                raise DomainError(409, "wrong-status", "This merge request was already answered.", status=m["status"]["kind"])
            if action == "decline" or HOST in (m["from"], m["to"]):
                m["status"] = {"kind": "declined", "at": now, "why": "host"}
            elif not (self._active(m["from"]) and self._active(m["to"])):
                m["status"] = {"kind": "declined", "at": now, "why": "gone"}
            else:
                self._merge(m["from"], m["to"])
                m["status"] = {"kind": "approved", "at": now}
                self._notify(m["to"], "merge", "The owner joined your two identities: your earlier answers are yours again.", actor=pid)
            return {"status": m["status"]["kind"]}

    def _merge(self, src, dst):
        if HOST in (src, dst):
            raise _bad("from", "The owner cannot be merged.")
        st = self.state
        moved = {}  # (qid, old ref) -> new ref

        def swap(p):
            return dst if p == src else p

        def own(voter, ref):
            return ref_author(ref) == voter

        for qid, cards in st["cards"].items():
            for card in [c for c in cards if c["kind"] == "person" and c["pid"] == src]:
                old = card_ref(card)
                twin = next((c for c in cards if c["kind"] == "person" and c["pid"] == dst and c.get("device") == card.get("device")), None)
                if twin is None:
                    card["pid"] = dst
                elif twin["at"] >= card["at"]:
                    cards.remove(card)
                else:
                    cards.remove(twin)
                    card["pid"] = dst
                moved[(qid, old)] = card_ref({**card, "pid": dst})
        for qid, by in st["votes"].items():
            fixed = {}
            for voter, ref in by.items():
                ref = moved.get((qid, ref), ref)
                if voter == src and dst in by:
                    continue
                fixed[swap(voter)] = ref
            st["votes"][qid] = {v: r for v, r in fixed.items() if not own(v, r)}
        for qid, by in st.get("backs", {}).items():
            union = {}
            for voter, refs in by.items():
                kept = union.setdefault(swap(voter), [])
                kept += [r for r in (moved.get((qid, r), r) for r in refs) if r not in kept and not own(swap(voter), r)]
            st["backs"][qid] = {v: refs for v, refs in union.items() if refs}
        for qid, lst in st.get("cleared", {}).items():  # one tombstone per answer slot: the newest wins
            newest = {}
            for t in sorted(lst, key=lambda t: t["clearedAt"]):
                t["pid"] = swap(t["pid"])
                newest[self._cleared_ref(t)] = t
            lst[:] = list(newest.values())
        for c in [*(c for cards in st["cards"].values() for c in cards), *(t for lst in st.get("cleared", {}).values() for t in lst)]:
            for version in [c.get("edited"), *c.get("history", ())]:
                if version:
                    version["by"] = swap(version["by"])
        for m in st["chat"]:
            for pids in m.get("reactions", {}).values():
                pids[:] = list(dict.fromkeys(map(swap, pids)))
        for qid, by_card in st["reactions"].items():
            fixed = {}
            for ref, by in by_card.items():
                ref = moved.get((qid, ref), ref)
                into = fixed.setdefault(ref, {})
                for voter, reaction in by.items():
                    if voter == src and dst in by:
                        continue
                    into.setdefault(swap(voter), reaction)
            st["reactions"][qid] = {r: {v: x for v, x in by.items() if not own(v, r)} for r, by in fixed.items()}
        for qid, lst in st.get("disagreements", {}).items():
            kept = {}
            for d in sorted(lst, key=lambda d: d["pid"] == src):  # the kept person's own reason wins
                d = {**d, "pid": swap(d["pid"]), "card": moved.get((qid, d["card"]), d["card"])}
                if not own(d["pid"], d["card"]):
                    kept.setdefault((d["pid"], d["card"]), d)
            lst[:] = sorted(kept.values(), key=lambda d: d["at"])
        for qid in [q for q, lst in st.get("disagreements", {}).items() if not lst]:
            st["disagreements"].pop(qid)
        for qid, lk in st["locks"].items():
            lk["by"] = swap(lk["by"])
            src_kind = lk["source"]["kind"]
            if src_kind == "card":
                lk["source"]["card"] = moved.get((qid, lk["source"]["card"]), lk["source"]["card"])
            elif src_kind == "edited" and lk["source"]["from"]:
                lk["source"]["from"] = moved.get((qid, lk["source"]["from"]), lk["source"]["from"])
        for qid, lst in st["suggestions"].items():
            for s in lst:
                s["pid"] = swap(s["pid"])
            authors = {s["id"]: s["pid"] for s in lst}
            by = st["suggestionVotes"].get(qid, {})
            fixed = {}
            for voter, sid in by.items():
                if voter == src and dst in by:
                    continue
                fixed[swap(voter)] = sid
            if qid in st["suggestionVotes"]:
                st["suggestionVotes"][qid] = {v: s for v, s in fixed.items() if authors.get(s) != v}
        for rec in [*st["proposals"], *st["chat"], *st["requests"], *st["uploads"], *st["annotations"]]:
            rec["pid"] = swap(rec["pid"])
        for p in st["proposals"]:
            if p["via"]["kind"] == "chat":
                p["via"]["by"] = swap(p["via"]["by"])
            if p["status"]["kind"] == "parked":
                p["status"]["by"] = swap(p["status"]["by"])
        for m in st["chat"]:
            if "replyTo" in m:
                m["replyTo"]["pid"] = swap(m["replyTo"]["pid"])
        for lst in st["results"].values():
            for r in lst:
                if r["by"]["kind"] == "guest-claude":
                    r["by"]["pid"] = swap(r["by"]["pid"])
        for r in st["rounds"]:
            ready = r["status"].get("ready")
            if ready:
                ready["by"] = swap(ready["by"])
        for q in st["questions"]:
            if q["origin"]["kind"] == "host":
                q["origin"]["by"] = swap(q["origin"]["by"])
        for lst in st["notifications"].values():
            for n in lst:
                if n.get("by") == src:
                    n["by"] = dst
        notes = st["notifications"].pop(src, [])
        if notes:
            st["notifications"][dst] = sorted(notes + st["notifications"].get(dst, []), key=lambda n: n["at"])[-NOTIFY_CAP:]
        src_prefs = st["prefs"].pop(src, {})
        if src_prefs:
            st["prefs"][dst] = {**src_prefs, **st["prefs"].get(dst, {})}
        about = st["aboutYou"].pop(src, None)
        if about and dst not in st["aboutYou"]:
            st["aboutYou"][dst] = about
        now = self.now()
        for m in st["mergeRequests"]:
            if m["status"]["kind"] == "pending" and src in (m["from"], m["to"]):
                m["status"] = {"kind": "declined", "at": now, "why": "gone"}
        for h, p in list(st["credentials"]["secrets"].items()):
            if p == src:
                st["credentials"]["secrets"][h] = dst
        st["people"].pop(src)
        self._presence.pop(src, None)
        self._presence_rev += 1

    # -- rounds ------------------------------------------------------------------------------

    def _current_round(self):
        rounds = self.state["rounds"]
        return rounds[-1] if rounds else None

    def _round(self, n):
        rounds = self.state["rounds"]
        return rounds[n - 1] if 1 <= n <= len(rounds) else None

    def _step(self, action, actor):
        """The current round after checking `action` against ROUND_TRANSITIONS and its actor class."""
        r = self._current_round()
        status = r["status"]["kind"] if r else "none"
        if (status, action) not in ROUND_TRANSITIONS:
            raise DomainError(409, "wrong-status", f"The round is {status}; {action} does not apply.", status=status)
        who, _ = ROUND_TRANSITIONS[(status, action)]
        if who == "claude" and actor is not CLAUDE or who != "claude" and actor is CLAUDE:
            raise DomainError(403, "owner-only", f"{action} is not available here.")
        if who == "owner":
            self._owner(actor)
        elif who == "moderator":
            self._moderator(actor)
        return r

    def ready_round(self, pid, body):
        on = _bool(body, "on")
        with self._tx():
            r = self._step("ready", pid)
            if on:
                r["status"]["ready"] = {"by": pid, "at": self.now()}
                for p in self._moderator_pids():
                    self._notify(p, "ready", f"Round {r['n']} is marked ready.", actor=pid)
            else:
                r["status"].pop("ready", None)
            return {"round": r["n"], "ready": on}

    def send_round(self, pid, body):
        """POST /api/round/send: owner only; writes `round-sent` with the digest."""
        _body(body)
        with self._tx():
            r = self._step("send", pid)
            digest = self._digest(r["n"])
            ev = self._event("round-sent", round=r["n"], digest=digest)
            r["status"] = {"kind": "sent", "sentAt": self.now(), "eventSeq": ev["seq"]}
            return {"round": r["n"]}

    def cancel_round(self, pid, body):
        _body(body)
        with self._tx():
            r = self._step("cancel", pid)
            self._event("round-cancelled", round=r["n"], sentSeq=r["status"]["eventSeq"])
            r["status"] = {"kind": "open"}
            return {"round": r["n"]}

    def reset_round(self, pid, body):
        """POST /api/round/reset: `working` back to `open`, the only exit when Claude's session died."""
        _body(body)
        with self._tx():
            r = self._step("reset", pid)
            r["status"] = {"kind": "open"}
            return {"round": r["n"]}

    def _next_round_n(self):
        return len(self.state["rounds"]) + 1

    def _round_size(self, n):
        return sum(1 for q in self.state["questions"] if q["round"] == n)

    # -- questions ---------------------------------------------------------------------------

    def _question(self, qid, field="qid"):
        if not isinstance(qid, str):
            raise _bad(field, f"{field} must name a question.")
        q = next((q for q in self.state["questions"] if q["id"] == qid), None)
        if q is None:
            raise DomainError(404, "no-such-question", f"No question {qid}.")
        return q

    def _answerable(self, q):
        """Refuse unless people may answer, vote, pick or react on q; returns `late` for a closed round."""
        if q["id"] in self.state["locks"]:
            raise DomainError(409, "locked", f"Question {q['id']} is locked; suggest a change instead.")
        r = self._round(q["round"])
        if r is None:
            raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
        kind = r["status"]["kind"]
        if kind in ("sent", "working"):
            raise DomainError(409, "round-sent", "This round went to Claude, so it is read-only; suggest a change instead.")
        return {"round": q["round"]} if kind == "closed" else None

    def _asset(self, v, field, *, image=False, pattern=None):
        pattern = pattern or (IMAGE_ASSET if image else ASSET)
        if not isinstance(v, str) or not pattern.fullmatch(v) or not (self.assets_dir / v).is_file():
            raise _bad(field, f"{field} must name an asset added earlier with add-asset.")
        return v

    def _reference(self, r, field):
        kind = _choice(r, "kind", ("image", "quote", "link", "diagram")) if isinstance(r, dict) else None
        if kind is None:
            raise _bad(field, f"{field} must be an image, quote, link or diagram reference.")
        if kind == "diagram":
            out = {"kind": "diagram", "asset": self._asset(r.get("asset"), f"{field}.asset", pattern=SVG_ASSET), "alt": _text(r, "alt")}
            caption = _text(r, "caption", optional=True)
            return {**out, **({"caption": caption} if caption else {})}
        if kind == "image":
            out = {"kind": "image", "asset": self._asset(r.get("asset"), f"{field}.asset", image=True)}
            if r.get("rect") is not None:
                out["rect"] = _rect(r["rect"], f"{field}.rect")
            caption = _text(r, "caption", optional=True)
            return {**out, **({"caption": caption} if caption else {})}
        if kind == "quote":
            out = {"kind": "quote", "text": _text(r, "text"), "source": _text(r, "source", limit=MAX_NOTE)}
            if r.get("url") is not None:
                out["url"] = _url(r["url"], f"{field}.url")
            return out
        out = {"kind": "link", "url": _url(r.get("url"), f"{field}.url")}
        title = _text(r, "title", limit=MAX_NOTE, optional=True)
        return {**out, **({"title": title} if title else {})}

    def _parse_question(self, qi, *, round_n, origin, known, field):
        """A QuestionInput (already schema-valid) checked for the rules the schema cannot express."""
        qid = qi["id"]
        if not QID.fullmatch(qid):
            raise _bad(f"{field}.id", f"{qid} is not a question id like Q12.")
        if qid in known:
            raise _bad(f"{field}.id", f"Question id {qid} is already used.")
        fmt = qi["format"]
        purpose = qi["purpose"]
        q = {"id": qid, "text": _text(qi, "text")}
        for key, limit in (("short", 80), ("scope", MAX_NOTE), ("context", 4000), ("basis", 4000)):
            v = _text(qi, key, limit=limit, optional=True)
            if v:
                q[key] = v
        alts = qi["alternatives"]
        rec = _text(qi, "recommendation", optional=True)
        may_have_cards = fmt["kind"] == "text" and origin["kind"] != "host"
        if (rec or alts) and not may_have_cards:
            raise _bad(f"{field}.recommendation", "A recommendation and alternatives go only on a text question Claude wrote.")
        if bool(rec) != bool(alts):
            raise _bad(f"{field}.alternatives", "A recommendation comes with 2 or 3 alternatives, and alternatives with a recommendation.")
        if alts and not 2 <= len(alts) <= 3:
            raise _bad(f"{field}.alternatives", "The shared session takes 2 or 3 alternatives.")
        if len({a["key"] for a in alts}) != len(alts):
            raise _bad(f"{field}.alternatives", "Each alternative needs its own key.")
        q["alternatives"] = []
        for i, a in enumerate(alts):
            alt = {"key": a["key"], "text": _text(a, "text")}
            tradeoff = _text(a, "tradeoff", optional=True)
            if tradeoff:
                alt["tradeoff"] = tradeoff
            q["alternatives"].append(alt)
        if rec:
            q["recommendation"] = rec
        deps = qi["dependsOn"]
        for d in deps:
            if d == qid or d not in known:
                raise _bad(f"{field}.dependsOn", f"{qid} may depend only on earlier questions; {d} is not one.")
        if len(set(deps)) != len(deps):
            raise _bad(f"{field}.dependsOn", "dependsOn names a question twice.")
        q["dependsOn"] = list(deps)
        q["round"] = round_n
        q["purpose"] = purpose
        if purpose == "poll" and fmt["kind"] == "text":
            raise _bad(f"{field}.purpose", "A poll needs options: use a choice, confirm or prototype format.")
        q["format"] = self._parse_format(fmt, f"{field}.format")
        q["answerScope"] = qi.get("answerScope", "person")
        refs = qi.get("references", [])
        if len(refs) > MAX_REFERENCES:
            raise DomainError(400, "too-long", f"A question holds at most {MAX_REFERENCES} references.", field=f"{field}.references", max=MAX_REFERENCES)
        q["references"] = [self._reference(r, f"{field}.references[{i}]") for i, r in enumerate(refs)]
        q["origin"] = origin
        q["needsReview"] = []
        return q

    def _parse_format(self, fmt, field):
        kind = fmt["kind"]
        if kind == "text":
            return {"kind": "text"}
        if kind in OPTION_COUNTS:
            ids = [o["id"] for o in fmt["options"]]
            if any(o["id"] == OTHER or "other" in o for o in fmt["options"]):
                raise _bad(f"{field}.options", "The server adds the Something else option itself; leave it out.")
            least, most = OPTION_COUNTS[kind]
            if not least <= len(ids) <= most:
                raise _bad(f"{field}.options", f"A {kind} question takes {least} to {most} options.")
            if len(set(ids)) != len(ids):
                raise _bad(f"{field}.options", "Each option needs its own id.")
            options = []
            for i, o in enumerate(fmt["options"]):
                opt = {"id": o["id"], "label": _text(o, "label")}
                if o.get("image") is not None:
                    opt["image"] = self._asset(o["image"], f"{field}.options[{i}].image", image=True)
                options.append(opt)
            return {"kind": kind, "options": [*options, dict(OTHER_OPTION)]}
        if kind == "scale":
            labels = {k: _text(fmt["labels"], k, limit=80) for k in ("min", "max")}
            mid = _text(fmt["labels"], "mid", limit=80, optional=True)
            return {"kind": "scale", "min": 1, "max": fmt["max"], "labels": {**labels, **({"mid": mid} if mid else {})}}
        if kind == "confirm":
            return {"kind": "confirm", "image": self._asset(fmt["image"], f"{field}.image", image=True), "rect": _rect(fmt["rect"], f"{field}.rect")}
        variants = []
        for i, v in enumerate(fmt["variants"]):
            if not VARIANT.fullmatch(v["id"]):
                raise _bad(f"{field}.variants[{i}].id", "A variant id looks like v-1.")
            variants.append({"id": v["id"], "label": _text(v, "label"), "asset": self._asset(v["asset"], f"{field}.variants[{i}].asset")})
        if len({v["id"] for v in variants}) != len(variants):
            raise _bad(f"{field}.variants", "Each variant needs its own id.")
        return {"kind": "prototype", "variants": variants}

    def _options(self, q):
        """Option id -> label for the option cards a non-text question offers; Something else has no
        card, since each person who picks it writes their own (`_has_other`)."""
        fmt = q["format"]
        if fmt["kind"] in OPTION_COUNTS:
            return {o["id"]: o["label"] for o in fmt["options"] if not o.get("other")}
        if fmt["kind"] == "scale":
            labels = fmt["labels"]
            mid = (fmt["min"] + fmt["max"]) // 2 if (fmt["min"] + fmt["max"]) % 2 == 0 and "mid" in labels else None
            named = {fmt["min"]: labels["min"], fmt["max"]: labels["max"], **({mid: labels["mid"]} if mid else {})}
            return {str(v): f"{v} ({named[v]})" if v in named else str(v) for v in range(fmt["min"], fmt["max"] + 1)}
        if fmt["kind"] == "confirm":
            return {"yes": "Yes", "no": "No"}
        if fmt["kind"] == "prototype":
            return {v["id"]: v["label"] for v in fmt["variants"]}
        return {}

    @staticmethod
    def _has_other(q):
        return any(o.get("other") for o in q["format"].get("options", []))

    @staticmethod
    def _is_other(card):
        """Whether a person card holds that person's own Something else option."""
        return card["kind"] == "person" and OTHER in (card.get("pick"), *card.get("picks", ()), *card.get("order", ()))

    def _add_question(self, q):
        st = self.state
        st["questions"].append(q)
        now = self.now()
        if q["format"]["kind"] == "text":
            cards = []
            if q.get("recommendation"):
                cards.append({"kind": "claude", "key": "rec", "at": now})
                cards += [{"kind": "claude", "key": a["key"], "at": now} for a in q["alternatives"]]
        else:
            cards = [{"kind": "option", "option": o} for o in self._options(q)]
        st["cards"][q["id"]] = cards

    def _next_qid(self, taken=()):
        nums = [int(i[1:]) for i in [*(q["id"] for q in self.state["questions"]), *taken] if QID.fullmatch(i)]
        return f"Q{max(nums, default=0) + 1}"

    def set_purpose(self, pid, body):
        """POST /api/question/purpose: the owner overrides the purpose Claude inferred."""
        purpose = _choice(body, "purpose", PURPOSES)
        with self._tx() as st:
            self._owner(pid)
            q = self._question(body.get("qid"))
            if purpose == "poll" and q["format"]["kind"] == "text":
                raise _bad("purpose", "A poll needs options; this is a text question.")
            if purpose == "gather" and q["id"] in st["locks"]:
                raise DomainError(409, "locked", "Unlock the question before making it a gather question.")
            q["purpose"] = purpose
            return {"purpose": purpose}

    def edit_reference(self, pid, body):
        """POST /api/question/reference: `{qid, reference}` adds one, `{qid, remove: i}` removes one."""
        with self._tx():
            self._owner(pid)
            return self._edit_reference(body)

    def _edit_reference(self, body):
        q = self._question(_body(body).get("qid"))
        refs = q["references"]
        if "remove" in body or "index" in body:
            i = body.get("remove", body.get("index"))
            if not _is_int(i) or not 0 <= i < len(refs):
                raise DomainError(404, "not-found", "No such reference.")
            refs.pop(i)
        else:
            if len(refs) >= MAX_REFERENCES:
                raise DomainError(400, "too-long", f"A question holds at most {MAX_REFERENCES} references.", field="references", max=MAX_REFERENCES)
            refs.append(self._reference(body.get("reference"), "reference"))
        return {"references": copy.deepcopy(refs)}

    # -- cards, votes, reactions -------------------------------------------------------------

    def _cards(self, qid):
        return self.state["cards"].setdefault(qid, [])

    def _shown(self, c):
        """Whether everyone sees card c: not a person card, or one whose author is active and that the owner has not hidden."""
        return c["kind"] != "person" or (self._active(c["pid"]) and "hidden" not in c)

    def _card(self, qid, ref):
        """The card `ref` on question qid, if everyone sees it (`_shown`)."""
        for c in self.state["cards"].get(qid, []):
            if card_ref(c) == ref:
                if not self._shown(c):
                    break
                return c
        raise DomainError(404, "no-such-card", "No such answer on this question.")

    def _person_card(self, body):
        """(question, card) for the owner's Hide and Edit: a person card of an active author, hidden or not."""
        q = self._question(_body(body).get("qid"))
        ref = _ident(body, "card")
        card = next((c for c in self.state["cards"].get(q["id"], []) if card_ref(c) == ref), None)
        if card is None or card["kind"] != "person" or not self._active(card["pid"]):
            raise DomainError(404, "no-such-card", "No such answer on this question.")
        return q, card

    @staticmethod
    def _keep_version(card, new_text):
        """Before a card's text changes: its current version joins `history` (who wrote it and when).
        The original always stays; past MAX_HISTORY the oldest later versions go first."""
        if card["text"] == new_text or not card["text"]:
            return
        by = card["edited"] if "edited" in card else {"by": card["pid"], "at": card["at"]}
        history = card.setdefault("history", [])
        history.append({"text": card["text"], "by": by["by"], "at": by["at"]})
        del history[1 : max(1, len(history) - MAX_HISTORY + 1)]

    def hide_card(self, pid, body):
        """POST /api/card/hide: `{qid, card, on, reason?}`, owner only. A hidden answer leaves every
        other person's view, the tally (its picks too) and the digest; its author still sees it,
        marked. It stays hidden through its author's new versions until the owner shows it. The
        locked answer cannot be hidden: unlock first. Hiding drops the answer's text from the
        mention notifications it sent."""
        on = _bool(body, "on")
        reason = _text(body, "reason", limit=MAX_NOTE, optional=True)
        with self._tx():
            self._owner(pid)
            q, card = self._person_card(body)
            src = self.state["locks"].get(q["id"], {}).get("source", {})
            if on and card_ref(card) in (src.get("card"), src.get("from")):
                raise DomainError(409, "locked", "This is the locked answer. Unlock the question first, then hide it.")
            if on:
                card["hidden"] = {"by": pid, "at": self.now(), **({"reason": reason} if reason else {})}
                self._drop_excerpts(q["id"], card["pid"])
            else:
                card.pop("hidden", None)
            return {"card": card_ref(card), "hidden": on}

    def edit_card(self, pid, body):
        """POST /api/card/edit: `{qid, card, text}`, owner only. The text is replaced and marked
        edited by the owner; the version it replaces goes to `history`, which only the owner reads
        (`card_history`). As with its author's own edit, an edit after votes records how many it
        had, and an edited own option (Something else) loses its backers."""
        text = _text(body, "text")
        with self._tx():
            self._owner(pid)
            q, card = self._person_card(body)
            if text != card["text"]:
                ref = card_ref(card)
                votes = len(self._votes_on(q["id"], ref))
                if votes:
                    card["editedAfterVotes"] = votes
                if self._is_other(card):
                    self._unback(q["id"], ref)
                self._keep_version(card, text)
                card["text"] = text
                card["edited"] = {"by": pid, "at": self.now()}
                self._drop_excerpts(q["id"], card["pid"])
            return {"card": card_ref(card), "text": card["text"]}

    def _drop_excerpts(self, qid, author):
        """Take the text out of the mention notifications author's answers on qid sent."""
        title = f"mentioned you {_answer_where(qid)}."
        for lst in self.state["notifications"].values():
            for n in lst:
                if n["kind"] == "mention" and n.get("by") == author and n.get("qid") == qid and n["title"] == title:
                    n.pop("body", None)

    def card_history(self, pid, body):
        """GET /api/card/history?qid=&card=: owner only. One answer's earlier versions, oldest first,
        each with who wrote it and when; for an answer its author cleared after the owner hid or
        edited it, also its last text and when it was cleared."""
        with self._lock:
            self._owner(pid)
            q = self._question(_body(body).get("qid"))
            ref = _ident(body, "card")
            card = next((c for c in self.state["cards"].get(q["id"], []) if c["kind"] == "person" and card_ref(c) == ref and self._active(c["pid"])), None)
            if card is not None:
                return {"card": ref, "history": copy.deepcopy(card.get("history", []))}
            t = next((t for t in self.state.get("cleared", {}).get(q["id"], []) if self._cleared_ref(t) == ref and self._active(t["pid"])), None)
            if t is None:
                raise DomainError(404, "no-such-card", "No such answer on this question.")
            return {"card": ref, "cleared": True, "clearedAt": t["clearedAt"], "text": t["text"], "history": copy.deepcopy(t.get("history", []))}

    @staticmethod
    def _cleared_ref(t):
        return card_ref({"kind": "person", **t})

    def _carry(self, prior, card):
        """A person's new version of their card (prior: their card or the tombstone of one they cleared).
        Once the owner hid or edited it, the replaced version joins `history`; before that no version
        is kept. Hidden holds until the owner shows it; the owner's edit mark stays only while nothing changed."""
        if prior is None:
            return
        if _moderated(prior):
            old = {**prior, "history": copy.deepcopy(prior.get("history", []))}
            self._keep_version(old, card["text"])
            if old["history"]:
                card["history"] = old["history"]
        if "hidden" in prior:
            card["hidden"] = copy.deepcopy(prior["hidden"])
        if "edited" in prior and all(prior.get(k) == card.get(k) for k in ("text", "pick", "picks", "value", "order")):
            card["edited"] = copy.deepcopy(prior["edited"])

    def _clear_card(self, qid, card):
        """Its author takes their card back. One the owner hid or edited leaves an owner-only tombstone
        in `cleared` (its last text, marks and history); the author's next answer there takes it up."""
        if _moderated(card):
            t = {k: copy.deepcopy(card[k]) for k in ("pid", "device", "text", "at", "hidden", "edited", "history") if k in card}
            t["clearedAt"] = self.now()
            lst = self.state.setdefault("cleared", {}).setdefault(qid, [])
            lst[:] = [x for x in lst if self._cleared_ref(x) != card_ref(card)] + [t]
        self._drop_card(qid, card)

    def _keep_hidden_across_devices(self, qid, pid, card):
        """A person whose answer on qid the owner hid stays hidden on every device slot of qid, so a
        repost from another slot is hidden too, until the owner shows it."""
        if "hidden" in card:
            return
        held = [c for c in self._cards(qid) if c["kind"] == "person" and c["pid"] == pid]
        held += [t for t in self.state.get("cleared", {}).get(qid, []) if t["pid"] == pid]
        sib = next((c for c in held if c is not card and c.get("hidden")), None)
        if sib:
            card["hidden"] = copy.deepcopy(sib["hidden"])

    def _take_cleared(self, qid, pid, device):
        """The tombstone of pid's cleared answer on qid (for device), removed from `cleared`, or None."""
        by_q = self.state.get("cleared", {})
        lst = by_q.get(qid, [])
        t = next((t for t in lst if t["pid"] == pid and t.get("device") == device), None)
        if t is not None:
            lst.remove(t)
            if not lst:
                by_q.pop(qid)
            if not by_q:
                self.state.pop("cleared")
        return t

    def _drop_card(self, qid, card):
        ref = card_ref(card)
        self.state["cards"][qid].remove(card)
        votes = self.state["votes"].get(qid, {})
        for voter in [v for v, r in votes.items() if r == ref]:
            votes.pop(voter)
        self._unback(qid, ref)
        self.state["reactions"].get(qid, {}).pop(ref, None)
        by_q = self.state.get("disagreements", {})
        if qid in by_q:
            by_q[qid] = [d for d in by_q[qid] if d["card"] != ref]
            if not by_q[qid]:
                by_q.pop(qid)

    def _device_for(self, q, body):
        device = _choice(body, "device", DEVICES, optional=True)
        if q["answerScope"] == "device":
            if device is None:
                raise _bad("device", "This question takes one answer per device: name the device.")
            return device
        return None

    def _votes_on(self, qid, ref):
        """Active people who vote for card `ref` on qid, or back it as one of several (`backs`, multi)."""
        voters = [v for v, r in self.state["votes"].get(qid, {}).items() if r == ref]
        voters += [v for v, refs in self.state.get("backs", {}).get(qid, {}).items() if ref in refs and v not in voters]
        return [v for v in voters if self._active(v)]

    def answer(self, pid, body):
        """POST /api/answer: write, edit or (with empty text) clear one's own answer card."""
        text = _text(body, "text", empty_ok=True)
        view = _choice(body, "view", VIEWS)
        info = _device_info(body.get("deviceInfo"))
        cites = body.get("cites")
        if cites is not None and (not isinstance(cites, list) or not all(isinstance(c, str) for c in cites)):
            raise _bad("cites", "cites must list result ids.")
        if cites is not None and len(cites) > MAX_CITES:
            raise DomainError(400, "too-long", f"An answer cites at most {MAX_CITES} results.", field="cites", max=MAX_CITES)
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "answer", now)
            q = self._question(body.get("qid"))
            if q["purpose"] == "poll":
                raise DomainError(409, "wrong-purpose", "A poll takes a pick, not a written answer.")
            if q["format"]["kind"] in ("multi", "scale", "rank"):
                raise DomainError(400, "bad-action", "This question takes a pick; a comment goes with the pick.")
            late = self._answerable(q)
            device = self._device_for(q, body)
            qid = q["id"]
            cards = self._cards(qid)
            mine = next((c for c in cards if c["kind"] == "person" and c["pid"] == pid and c.get("device") == device), None)
            if cites is not None:
                published = {r["id"] for r in st["results"].get(qid, []) if r["published"]}
                if any(c not in published for c in cites):
                    raise _bad("cites", "cites must name results shown on this question.")
            if not text:
                if mine:
                    self._clear_card(qid, mine)
                ref = None
            else:
                old_text = mine["text"] if mine else ""
                card = {"kind": "person", "pid": pid, **({"device": device} if device else {}), "text": text, "at": now}
                card["cites"] = list(cites) if cites is not None else (mine["cites"] if mine else [])
                if mine:
                    votes = len(self._votes_on(qid, card_ref(mine)))
                    if mine.get("editedAfterVotes"):
                        card["editedAfterVotes"] = mine["editedAfterVotes"]
                    if votes and old_text != text:
                        card["editedAfterVotes"] = votes
                if info or (mine and mine.get("deviceInfo")):
                    card["deviceInfo"] = info or mine["deviceInfo"]
                card["view"] = view
                if late:
                    card["late"] = late
                self._carry(mine or self._take_cleared(qid, pid, device), card)
                self._keep_hidden_across_devices(qid, pid, card)
                if mine:
                    cards[cards.index(mine)] = card
                    if self._is_other(mine):
                        self._unback(qid, card_ref(card))
                else:
                    cards.append(card)
                if q["format"]["kind"] != "text":
                    st["votes"].get(qid, {}).pop(pid, None)  # off a text question the vote is the pick
                ref = card_ref(card)
                if "hidden" not in card:
                    self._notify_mentions(text, pid, _answer_where(qid), before=old_text, qid=qid)
        self._wrote(pid, "answer", now)
        return {"card": ref}

    def pick(self, pid, body):
        """POST /api/pick: the person's pick, in the field the format takes (`_parse_pick`), with an
        optional `comment`. On choice, confirm and prototype questions the pick is the vote. Picking
        Something else needs `other`, the person's own option, which becomes their card's text and
        a card others can back (`vote`); scale and confirm questions take a comment instead."""
        body = _body(body)
        comment = _text(body, "comment", empty_ok=True)
        other = _text(body, "other", optional=True)
        view = _choice(body, "view", VIEWS)
        info = _device_info(body.get("deviceInfo"))
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "pick", now)
            q = self._question(body.get("qid"))
            key, fields = self._parse_pick(q, body)
            chose_other = self._is_other({"kind": "person", **fields})
            if chose_other and not other:
                raise DomainError(400, "empty", "Something else needs your own option, in other.", field="other")
            if other and not chose_other:
                raise _bad("other", "other goes only with picking Something else.")
            if other and comment:
                raise _bad("comment", "Your own option is your card's text; send it in other, without a comment.")
            late = self._answerable(q)
            device = self._device_for(q, body)
            qid = q["id"]
            cards = self._cards(qid)
            mine = next((c for c in cards if c["kind"] == "person" and c["pid"] == pid and c.get("device") == device), None)
            was_other = mine is not None and self._is_other(mine)
            if key == "pick":
                votes = st["votes"].setdefault(qid, {})
                if fields and not chose_other:
                    votes[pid] = f"o:{fields['pick']}"
                elif q["format"]["kind"] != "text" or votes.get(pid, "").startswith("o:"):
                    votes.pop(pid, None)  # off a text question every vote is the pick
            text = other or comment
            if not fields and not text:
                if mine:
                    self._clear_card(qid, mine)
            else:
                card = {"kind": "person", "pid": pid, **({"device": device} if device else {}), "text": text, "at": now, **fields}
                card["cites"] = mine["cites"] if mine else []
                backers = len(self._votes_on(qid, card_ref(card))) if was_other else 0
                if was_other and chose_other and mine.get("editedAfterVotes"):
                    card["editedAfterVotes"] = mine["editedAfterVotes"]
                if backers and chose_other and mine["text"] != text:
                    card["editedAfterVotes"] = backers
                if info or (mine and mine.get("deviceInfo")):
                    card["deviceInfo"] = info or mine["deviceInfo"]
                card["view"] = view
                if late:
                    card["late"] = late
                self._carry(mine or self._take_cleared(qid, pid, device), card)
                self._keep_hidden_across_devices(qid, pid, card)
                if mine:
                    cards[cards.index(mine)] = card
                else:
                    cards.append(card)
                if was_other and not chose_other:
                    self._unback(qid, card_ref(card))
                if text and "hidden" not in card:
                    self._notify_mentions(text, pid, _answer_where(qid), before=mine["text"] if mine else "", qid=qid)
        self._wrote(pid, "pick", now)
        return {key: fields.get(key)}

    def _parse_pick(self, q, body):
        """(the field the format takes, the card fields it sets: {} for no pick). choice, confirm and
        prototype take `option` ("" for none); multi takes `options`, a subset of at least one; scale
        takes `value`, a whole number in its range; rank takes `order`, every option once (Something
        else may join it). Something else is `other` where the question has one."""
        kind = q["format"]["kind"]
        known = set(self._options(q)) | ({OTHER} if self._has_other(q) else set())
        if kind == "scale":
            v = body.get("value")
            fmt = q["format"]
            if v is not None and not (_is_int(v) and fmt["min"] <= v <= fmt["max"]):
                raise _bad("value", f"value must be a whole number from {fmt['min']} to {fmt['max']}.")
            return "value", ({} if v is None else {"value": v})
        if kind in ("multi", "rank"):
            key = "options" if kind == "multi" else "order"
            ids = body.get(key)
            if ids is None or ids == []:
                return ("picks" if kind == "multi" else "order"), {}
            if not isinstance(ids, list) or not all(isinstance(i, str) for i in ids):
                raise _bad(key, f"{key} must list option ids.")
            if len(set(ids)) != len(ids):
                raise _bad(key, f"{key} names an option twice.")
            if any(i not in known for i in ids):
                raise DomainError(400, "no-such-option", "No such option on this question.")
            if kind == "multi":
                return "picks", {"picks": [i for i in [*self._options(q), OTHER] if i in ids]}
            if {i for i in ids if i != OTHER} != set(self._options(q)):
                raise _bad("order", "A rank needs a full order: every option once.")
            return "order", {"order": list(ids)}
        option = body.get("option")
        if not isinstance(option, str):
            raise _bad("option", "option must name one of the question's options.")
        if option and option not in known:
            raise DomainError(400, "no-such-option", "No such option on this question.")
        return "pick", ({"pick": option} if option else {})

    def _unback(self, qid, ref):
        """Drop every vote for, and every backing of, a card that no longer holds its author's Something else option."""
        votes = self.state["votes"].get(qid, {})
        for voter in [v for v, r in votes.items() if r == ref]:
            votes.pop(voter)
        backs = self.state.get("backs", {})
        by = backs.get(qid, {})
        for voter in [v for v, refs in by.items() if ref in refs]:
            by[voter].remove(ref)
            if not by[voter]:
                by.pop(voter)
        if qid in backs and not by:
            backs.pop(qid)
        if "backs" in self.state and not backs:
            self.state.pop("backs")

    def vote(self, pid, body):
        """POST /api/vote: `{qid, card, on}` votes for an answer card, `{qid, suggestion, on}` for a suggestion."""
        on = _bool(body, "on")
        if _body(body).get("suggestion") is not None:
            return self._vote_suggestion(pid, body, on)
        ref = _ident(body, "card")
        with self._write_as(pid, "vote") as st:
            q, card = self._card_vote_question(body, ref, backing=True)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot vote for your own answer.")
            qid = q["id"]
            if q["format"]["kind"] == "multi":  # any subset: a person backs as many others' own options as they like
                return self._back(qid, pid, card, on)
            votes = st["votes"].setdefault(qid, {})
            moved = False
            if on:
                moved = votes.get(pid) not in (None, ref)
                if q["format"]["kind"] == "choice":  # one pick: backing someone's own option moves it
                    for mine in [c for c in st["cards"][qid] if c["kind"] == "person" and c["pid"] == pid]:
                        if self._is_other(mine) or not mine["text"]:
                            self._clear_card(qid, mine)
                        else:
                            mine.pop("pick", None)
                if votes.get(pid) != ref:
                    votes[pid] = ref
                    self._notify_vote(qid, card, pid)
            elif votes.get(pid) == ref:
                votes.pop(pid)
            return {"moved": moved}

    def _back(self, qid, pid, card, on):
        """Back (or stop backing) another person's own option on a multi question, in `backs`, beside
        any others the person backs. A backing kept in `votes` by an earlier build is taken back too."""
        st, ref = self.state, card_ref(card)
        mine = st.setdefault("backs", {}).setdefault(qid, {}).setdefault(pid, [])
        if on and ref not in mine:
            mine.append(ref)
            self._notify_vote(qid, card, pid)
        elif not on:
            if ref in mine:
                mine.remove(ref)
            if st["votes"].get(qid, {}).get(pid) == ref:
                st["votes"][qid].pop(pid)
        if not mine:
            st["backs"][qid].pop(pid)
        if not st["backs"][qid]:
            st["backs"].pop(qid)
        if not st["backs"]:
            st.pop("backs")
        return {"moved": False}

    def _card_vote_question(self, body, ref, *, backing=False):
        """(question, card) for a vote on an answer card. Off a text question only `backing` a
        person's own Something else option is a vote; picking an option is the vote there."""
        if not self.state["session"]["settings"]["voting"]:
            raise DomainError(403, "voting-off", "Voting is off in this session.")
        q = self._question(body.get("qid"))
        if q["purpose"] == "gather":
            raise DomainError(409, "wrong-purpose", "This question gathers answers: react instead of voting.")
        if q["format"]["kind"] != "text" and not (backing and self._is_other(self._card(q["id"], ref))):
            raise DomainError(400, "bad-action", "On this question picking an option is the vote.")
        self._answerable(q)
        return q, self._card(q["id"], ref)

    def _notify_vote(self, qid, card, actor):
        if card["kind"] != "person":
            return
        ref = card_ref(card)
        n = len(self._votes_on(qid, ref))
        self._notify(
            card["pid"],
            "votes",
            f"{n} {'person agrees' if n == 1 else 'people agree'} with your answer on question {qid}.",
            actor=actor,
            rollup=f"{qid}:{ref}",
            window=VOTE_ROLLUP_WINDOW,
            qid=qid,
        )

    def _vote_suggestion(self, pid, body, on):
        sid = _ident(body, "suggestion")
        with self._write_as(pid, "vote") as st:
            if not st["session"]["settings"]["voting"]:
                raise DomainError(403, "voting-off", "Voting is off in this session.")
            q = self._question(body.get("qid"))
            s = self._suggestion(q["id"], sid)
            if s["status"]["kind"] != "open":
                raise DomainError(409, "wrong-status", "This suggestion is no longer open.", status=s["status"]["kind"])
            if s["pid"] == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot vote for your own suggestion.")
            votes = st["suggestionVotes"].setdefault(q["id"], {})
            moved = False
            if on:
                moved = votes.get(pid) not in (None, sid)
                votes[pid] = sid
            elif votes.get(pid) == sid:
                votes.pop(pid)
            return {"moved": moved}

    def go_with(self, pid, body):
        """POST /api/go-with: withdraw one's own answer and move one's vote to `card`, in one action."""
        ref = _ident(body, "card")
        with self._write_as(pid, "go-with") as st:
            q, card = self._card_vote_question(body, ref)
            qid = q["id"]
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "That is your own answer.")
            for mine in [c for c in st["cards"][qid] if c["kind"] == "person" and c["pid"] == pid]:
                self._clear_card(qid, mine)
            votes = st["votes"].setdefault(qid, {})
            moved = votes.get(pid) not in (None, ref)
            if votes.get(pid) != ref:
                votes[pid] = ref
                self._notify_vote(qid, card, pid)
            return {"moved": moved}

    def react(self, pid, body):
        """POST /api/react: thumbs, down, heart or idea on an answer of a gather question; null clears.
        Decide questions take Disagree instead (`disagree`)."""
        ref = _ident(body, "card")
        reaction = _body(body).get("reaction")
        if reaction is not None and reaction not in REACTIONS:
            raise _bad("reaction", f"reaction must be one of {', '.join(REACTIONS)}, or null.")
        with self._write_as(pid, "react") as st:
            q = self._question(body.get("qid"))
            if q["purpose"] != "gather":
                raise DomainError(409, "wrong-purpose", "Reactions are for gather questions; vote instead.")
            self._answerable(q)
            self._card(q["id"], ref)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot react to your own answer.")
            by_card = st["reactions"].setdefault(q["id"], {})
            mine = by_card.setdefault(ref, {})
            if reaction is None:
                mine.pop(pid, None)
                if not mine:
                    by_card.pop(ref)
            else:
                mine[pid] = reaction
            if not by_card:
                st["reactions"].pop(q["id"])
            return {"reaction": reaction}

    def disagree(self, pid, body):
        """POST /api/disagree: `{qid, card, reason}` records why the person disagrees with one answer
        of a decide question (one per person per answer; a new reason replaces theirs), `on: false`
        takes it back. The reason is 1..200 characters. Vote counts never change; the owner can
        still Lock this one."""
        ref = _ident(body, "card")
        on = _bool(body, "on", default=True)
        reason = _text(body, "reason", limit=MAX_NOTE) if on else None
        with self._write_as(pid, "disagree") as st:
            q = self._question(body.get("qid"))
            if q["purpose"] != "decide":
                raise DomainError(409, "wrong-purpose", "Disagree is for decide questions; react or pick instead.")
            self._answerable(q)
            self._card(q["id"], ref)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot disagree with your own answer.")
            by_q = st.setdefault("disagreements", {})
            kept = [d for d in by_q.get(q["id"], []) if not (d["pid"] == pid and d["card"] == ref)]
            if on:
                kept.append({"pid": pid, "card": ref, "reason": reason, "at": self.now()})
            if kept:
                by_q[q["id"]] = kept
            else:
                by_q.pop(q["id"], None)
            return {"disagree": on}

    # -- locks and suggestions ---------------------------------------------------------------

    def _tally(self, qid):
        """Card ref -> support, from active people on cards that still exist: votes; a person's own
        Something else option counts its author; multi counts each option a person picked, scale
        each value, rank Borda points (n options: first n-1, last 0). A rank tallies its option
        cards only, since Borda points and votes do not compare."""
        kind = self._question(qid)["format"]["kind"]
        cards = [c for c in self.state["cards"].get(qid, []) if self._shown(c)]
        tally = dict.fromkeys(map(card_ref, cards), 0)
        for ref in tally:
            tally[ref] += len(self._votes_on(qid, ref))
        for c in cards:
            if c["kind"] != "person":
                continue
            if self._is_other(c):
                tally[card_ref(c)] += 1
            if kind == "multi":
                points = {o: 1 for o in c.get("picks", ())}
            elif kind == "scale":
                points = {str(c["value"]): 1} if "value" in c else {}
            elif kind == "rank":
                ranked = [o for o in c.get("order", ()) if o != OTHER]
                points = {o: len(ranked) - 1 - i for i, o in enumerate(ranked)}
            else:
                points = {}
            for o, n in points.items():
                if f"o:{o}" in tally:
                    tally[f"o:{o}"] += n
        if kind == "rank":
            tally = {r: n for r, n in tally.items() if r.startswith("o:")}
        return tally

    def _backs(self, q, pid, ref):
        """Whether pid supports card `ref` (for sign-off): wrote it, voted for it, picked it (multi),
        chose its value (scale) or ranked it first (rank)."""
        if ref_author(ref) == pid or pid in self._votes_on(q["id"], ref):
            return True
        if not ref.startswith("o:"):
            return False
        o, kind = ref[2:], q["format"]["kind"]
        for c in self.state["cards"].get(q["id"], []):
            if c["kind"] != "person" or c["pid"] != pid:
                continue
            ranked = [x for x in c.get("order", ()) if x != OTHER]
            if (kind == "multi" and o in c.get("picks", ())) or (kind == "scale" and str(c.get("value")) == o) or (kind == "rank" and ranked[:1] == [o]):
                return True
        return False

    def _card_text(self, q, ref):
        card = self._card(q["id"], ref)
        if card["kind"] == "person":
            label = self._options(q).get(card.get("pick"), "")
            return card["text"] or label
        if card["kind"] == "claude":
            if card["key"] == "rec":
                return q["recommendation"]
            return next(a["text"] for a in q["alternatives"] if a["key"] == card["key"])
        return self._options(q)[card["option"]]

    def _flag(self, because, why):
        """Flag every question that depends on `because`; one flag per because and why, newest last."""
        flagged = []
        now = self.now()
        for d in self.state["questions"]:
            if because in d["dependsOn"]:
                d["needsReview"] = [f for f in d["needsReview"] if not (f["because"] == because and f["why"] == why)]
                d["needsReview"].append({"because": because, "at": now, "why": why})
                flagged.append(d["id"])
        return flagged

    def _lock_changed(self, q, text):
        prev = q.get("lockedText")
        q["lockedText"] = text
        if prev is not None and prev != text:
            return self._flag(q["id"], {"kind": "lock-changed"})
        return []

    def lock(self, pid, body):
        """POST /api/lock: no `card` is Lock top answer; with `card` it is Lock this one."""
        ref = _ident(body, "card", optional=True)
        now = self.now()
        with self._tx() as st:
            self._moderator(pid)
            q = self._question(body.get("qid"))
            qid = q["id"]
            if q["purpose"] == "poll" and pid != HOST:
                raise DomainError(403, "owner-only", "Only the owner closes a poll.")
            if q["purpose"] == "gather":
                raise DomainError(409, "wrong-purpose", "A gather question is not locked; its answers stand.")
            self._answerable(q)
            tally = self._tally(qid)
            most = max(tally.values(), default=0)
            if ref is not None:
                self._card(qid, ref)
            if most == 0 and not (pid == HOST and ref is not None):
                raise DomainError(409, "no-votes", "No answer has a vote yet; the owner's Lock this one still works.")
            if ref is not None:
                target = ref
            else:
                tied = [r for r, n in tally.items() if n == most]
                if len(tied) > 1:
                    raise DomainError(409, "tie", "Answers are tied; the owner picks one.", tied=tied)
                target = tied[0]
            if st["session"]["settings"]["signoff"] and not (pid == HOST and ref is not None):
                here = self._present()
                agree = {p for p in here if self._backs(q, p, target)}
                if agree != here:
                    raise DomainError(409, "not-agreed", "Not everyone here agrees yet.", agree=len(agree), total=len(here))
            text = self._card_text(q, target)
            card = self._card(qid, target)
            edited = {"editedBy": HOST} if "edited" in card else {}  # the locked text is the owner's, not its author's
            st["locks"][qid] = {"at": now, "by": pid, "source": {"kind": "card", "card": target, "text": text, **edited}}
            flagged = self._lock_changed(q, text)
            return {"text": text, "flagged": flagged}

    def unlock(self, pid, body):
        """POST /api/unlock: suggestions are closed, never deleted; dependents are flagged."""
        now = self.now()
        with self._tx() as st:
            self._moderator(pid)
            q = self._question(body.get("qid") if isinstance(body, dict) else None)
            if q["purpose"] == "poll" and pid != HOST:
                raise DomainError(403, "owner-only", "Only the owner reopens a poll.")
            if q["id"] not in st["locks"]:
                raise DomainError(409, "not-locked", "This question is not locked.")
            st["locks"].pop(q["id"])
            closed = 0
            for s in st["suggestions"].get(q["id"], []):
                if s["status"]["kind"] == "open":
                    s["status"] = {"kind": "closed", "by": "unlock", "at": now}
                    closed += 1
            flagged = self._flag(q["id"], {"kind": "unlocked"})
            return {"closed": closed, "flagged": flagged}

    def _suggestion(self, qid, sid):
        s = next((s for s in self.state["suggestions"].get(qid, []) if s["id"] == sid), None)
        if s is None or not self._active(s["pid"]):
            raise DomainError(404, "not-found", "No such suggestion.")
        return s

    def suggest(self, pid, body):
        """POST /api/suggest: on a locked question, or any question whose round is no longer open."""
        text = _text(body, "text")
        note = _text(body, "note", limit=MAX_NOTE, empty_ok=True)
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "suggest", now)
            q = self._question(body.get("qid"))
            if q["id"] not in st["locks"]:
                r = self._round(q["round"])
                if r is None:
                    raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
                if r["status"]["kind"] == "open":
                    raise DomainError(409, "not-locked", "This question is open: answer it instead.")
            sid = self._next("S")
            kept = st["suggestions"].setdefault(q["id"], [])
            kept.append({"id": sid, "pid": pid, "text": text, "note": note, "at": now, "status": {"kind": "open"}})
            dropped = {s["id"] for s in kept[:-MAX_SUGGESTIONS]}
            if dropped:
                del kept[:-MAX_SUGGESTIONS]
                votes = st["suggestionVotes"].get(q["id"], {})
                for voter in [v for v, s in votes.items() if s in dropped]:
                    votes.pop(voter)
            self._notify_mentions(f"{text} {note}", pid, f"in a suggestion on question {q['id']}", qid=q["id"])
            self._queue_note(self._moderator_pids(), pid)
        self._wrote(pid, "suggest", now)
        return {"id": sid}

    def act_on_suggestion(self, pid, body):
        """POST /api/suggestion/act: Use (locks it in) or Dismiss; the question stays locked."""
        action = _choice(body, "action", ("use", "dismiss"))
        sid = _ident(body, "id")
        now = self.now()
        with self._tx() as st:
            self._moderator(pid)
            q = self._question(body.get("qid"))
            s = self._suggestion(q["id"], sid)
            if s["status"]["kind"] != "open":
                raise DomainError(409, "wrong-status", "This suggestion is no longer open.", status=s["status"]["kind"])
            flagged = []
            if action == "use":
                if q["id"] not in st["locks"]:
                    raise DomainError(409, "not-locked", "Lock the question before using a suggestion.")
                st["locks"][q["id"]] = {"at": now, "by": pid, "source": {"kind": "suggestion", "suggestion": sid, "text": s["text"]}}
                s["status"] = {"kind": "used", "at": now}
                flagged = self._lock_changed(q, s["text"])
            else:
                s["status"] = {"kind": "dismissed", "at": now}
            return {"status": s["status"]["kind"], "flagged": flagged}

    def edit_lock(self, pid, body):
        """POST /api/lock/edit: replace the locked text; `from` names the card or suggestion it came from."""
        text = _text(body, "text")
        source = _ident(body, "from", optional=True)
        now = self.now()
        with self._tx() as st:
            self._moderator(pid)
            q = self._question(body.get("qid"))
            if q["id"] not in st["locks"]:
                raise DomainError(409, "not-locked", "This question is not locked.")
            used = None
            if source is not None:
                if source.startswith(("p:", "c:", "o:")):
                    self._card(q["id"], source)
                else:
                    used = self._suggestion(q["id"], source)
            st["locks"][q["id"]] = {"at": now, "by": pid, "source": {"kind": "edited", "text": text, "from": source}}
            if used is not None and used["status"]["kind"] == "open":
                used["status"] = {"kind": "used", "at": now}
            return {"flagged": self._lock_changed(q, text)}

    def clear_review(self, pid, body):
        """POST /api/review/clear: drop Needs review flags, all of them or those naming `because`."""
        because = _ident(body, "because", optional=True)
        with self._tx():
            self._moderator(pid)
            q = self._question(body.get("qid"))
            before = len(q["needsReview"])
            q["needsReview"] = [f for f in q["needsReview"] if because is not None and f["because"] != because]
            return {"cleared": before - len(q["needsReview"])}

    # -- proposals, chat, annotations --------------------------------------------------------

    def _proposal(self, prop_id):
        p = next((p for p in self.state["proposals"] if p["id"] == prop_id), None)
        if p is None or not self._active(p["pid"]):
            raise DomainError(404, "no-such-proposal", f"No proposal {prop_id}.")
        return p

    def propose(self, pid, body):
        text = _text(body, "text")
        now = self.now()
        with self._tx():
            self._writer(pid)
            self._throttle(pid, "propose", now)
            prop = self._new_proposal(pid, text, {"kind": "direct"})
            self._notify_mentions(text, pid, "in a proposal")
        self._wrote(pid, "propose", now)
        return {"id": prop["id"]}

    def _new_proposal(self, author, text, via):
        prop = {"id": self._next("P"), "pid": author, "text": text, "at": self.now(), "via": via, "status": {"kind": "new"}}
        self.state["proposals"].append(prop)
        self._queue_note(self._moderator_pids(), author)
        return prop

    def act_on_proposal(self, pid, body):
        """POST /api/proposal/act: question (next round), park, restore or later, by a moderator."""
        action = _choice(body, "action", tuple(PROPOSAL_ACTIONS))
        reason = _text(body, "reason", optional=True)
        with self._tx():
            self._moderator(pid)
            prop = self._proposal(_ident(body, "id"))
            kind = prop["status"]["kind"]
            if kind not in PROPOSAL_ACTIONS[action]:
                raise DomainError(409, "wrong-status", f"Proposal {prop['id']} is {kind}.", status=kind)
            out = {}
            if action == "question":
                n = self._next_round_n()
                if self._round_size(n) >= MAX_ROUND:
                    raise DomainError(409, "round-full", f"Round {n} already holds {MAX_ROUND} questions.")
                q = {
                    "id": self._next_qid(),
                    "text": prop["text"],
                    "alternatives": [],
                    "dependsOn": [],
                    "round": n,
                    "purpose": "decide",
                    "format": {"kind": "text"},
                    "answerScope": "person",
                    "references": [],
                    "origin": {"kind": "host", "proposal": prop["id"], "by": pid},
                    "needsReview": [],
                }
                self._add_question(q)
                prop["status"] = {"kind": "question", "question": q["id"]}
                self._notify(prop["pid"], "proposal", f"Your proposal became question {q['id']}, in round {n}.", actor=pid, qid=q["id"])
                out = {"question": q["id"], "round": n}
            elif action == "park":
                prop["status"] = {"kind": "parked", "by": pid}
                self._notify(prop["pid"], "proposal", "Your proposal was parked by a moderator.", actor=pid)
            elif action == "restore":
                prop["status"] = {"kind": "new"}
            else:
                prop["status"] = {"kind": "later", "reason": reason or "Off this session's goal."}
                self._notify(prop["pid"], "proposal", "Your proposal was moved to Later.", actor=pid, body=prop["status"]["reason"])
            return {"status": prop["status"]["kind"], **out}

    def chat(self, pid, body):
        """POST /api/chat: side chat, never sent to Claude."""
        text = _text(body, "text")
        reply_to = _ident(body, "replyTo", optional=True)
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            if not st["session"]["settings"]["chat"]:
                raise DomainError(403, "chat-off", "Chat is off in this session.")
            self._throttle(pid, "chat", now)
            msg = {"id": self._next("M"), "pid": pid, "text": text, "at": now}
            skip = ()
            if reply_to is not None:
                to = next((m for m in st["chat"] if m["id"] == reply_to and self._active(m["pid"])), None)
                if to is None:
                    raise DomainError(404, "not-found", "The message you replied to is gone.")
                msg["replyTo"] = {"id": to["id"], "pid": to["pid"], "excerpt": one_line(to["text"])[:MAX_EXCERPT]}
                self._notify(to["pid"], "reply", "replied to your message.", actor=pid, by=pid, body=one_line(text)[:160], msg=msg["id"])
                skip = (to["pid"],)
            st["chat"].append(msg)
            del st["chat"][:-MAX_CHAT]
            self._notify_mentions(text, pid, "in chat", skip=skip, msg=msg["id"])
        self._wrote(pid, "chat", now)
        return {"id": msg["id"]}

    def react_chat(self, pid, body):
        """POST /api/chat/react: `{id, emoji, on}` adds or takes back one's own emoji on a chat message.
        Only CHAT_EMOJI; at most MAX_CHAT_EMOJI distinct ones per message and MAX_MY_CHAT_EMOJI per
        person per message, and one reaction a second per person per message, like every write.
        A reaction tells the message's author, one rolled-up line per message."""
        emoji = _choice(body, "emoji", CHAT_EMOJI)
        on = _bool(body, "on")
        mid = _ident(body, "id")
        now = self.now()
        route = f"chat-react:{mid}"
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "chat-react", now, CHAT_REACT_ANY)
            if not st["session"]["settings"]["chat"]:
                raise DomainError(403, "chat-off", "Chat is off in this session.")
            self._throttle(pid, route, now)
            msg = next((m for m in st["chat"] if m["id"] == mid and self._active(m["pid"])), None)
            if msg is None:
                raise DomainError(404, "not-found", "No such message.")
            reactions = msg.setdefault("reactions", {})
            pids = reactions.get(emoji, [])
            if on and pid not in pids:
                if emoji not in reactions and len(reactions) >= MAX_CHAT_EMOJI:
                    raise DomainError(409, "reaction-cap", f"A message takes at most {MAX_CHAT_EMOJI} different emoji.", max=MAX_CHAT_EMOJI)
                if sum(1 for ps in reactions.values() if pid in ps) >= MAX_MY_CHAT_EMOJI:
                    raise DomainError(409, "reaction-cap", f"You can put at most {MAX_MY_CHAT_EMOJI} emoji on one message.", max=MAX_MY_CHAT_EMOJI)
                reactions[emoji] = [*pids, pid]
                n = sum(len(ps) for ps in reactions.values())
                self._notify(
                    msg["pid"],
                    "reaction",
                    f"{n} {'reaction' if n == 1 else 'reactions'} on your chat message.",
                    actor=pid,
                    rollup=f"chat:{mid}",
                    window=VOTE_ROLLUP_WINDOW,
                    msg=mid,
                )
            elif not on and pid in pids:
                pids.remove(pid)
                if not pids:
                    reactions.pop(emoji)
            if not reactions:
                msg.pop("reactions")
        self._wrote(pid, route, now)
        self._wrote(pid, "chat-react", now)
        return {"id": mid, "emoji": emoji, "on": on}

    def propose_from_chat(self, pid, body):
        """POST /api/chat/propose: a moderator turns a chat message into its author's proposal."""
        with self._tx() as st:
            self._moderator(pid)
            mid = _ident(body, "id")
            msg = next((m for m in st["chat"] if m["id"] == mid and self._active(m["pid"])), None)
            if msg is None:
                raise DomainError(404, "not-found", "No such message.")
            if msg.get("proposed"):
                raise DomainError(409, "wrong-status", "This message is already a proposal.", status="proposed")
            prop = self._new_proposal(msg["pid"], msg["text"], {"kind": "chat", "message": mid, "by": pid})
            msg["proposed"] = prop["id"]
            self._notify(msg["pid"], "proposal", "Your chat message became a proposal.", actor=pid, msg=mid)
            return {"proposal": prop["id"]}

    def annotate(self, pid, body):
        """POST /api/annotate: a note pinned to an element of one prototype variant."""
        text = _text(body, "text")
        variant = _ident(body, "variant")
        anchor = _body(body).get("anchor")
        if not isinstance(anchor, dict) or not isinstance(anchor.get("selector"), str) or not 0 < len(anchor["selector"]) <= 500:
            raise _bad("anchor", "anchor must be {selector, rect}.")
        rect = _rect(anchor.get("rect"), "anchor.rect")
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "annotate", now)
            q = self._question(body.get("qid"))
            if q["format"]["kind"] != "prototype":
                raise _bad("qid", "Notes pin to prototype questions only.")
            if variant not in self._options(q):
                raise _bad("variant", "No such variant on this question.")
            aid = self._next("A")
            st["annotations"].append(
                {"id": aid, "pid": pid, "qid": q["id"], "variant": variant, "at": now, "text": text, "anchor": {"selector": anchor["selector"], "rect": rect}}
            )
            del st["annotations"][:-MAX_ANNOTATIONS]
            self._notify_mentions(text, pid, f"in a note on question {q['id']}", qid=q["id"])
        self._wrote(pid, "annotate", now)
        return {"id": aid}

    # -- requests and results ----------------------------------------------------------------

    def _request(self, rid, *, runner=None, owner_pid=None):
        r = next((r for r in self.state["requests"] if r["id"] == rid), None)
        if r is None or (runner and r["runner"] != runner) or (owner_pid and r["pid"] != owner_pid):
            raise DomainError(404, "no-such-request", f"No request {rid}.")
        return r

    def request(self, pid, body):
        """POST /api/request: ask Claude; waits in the owner's queue (`runner: self` runs on the requester's Claude)."""
        kind = _choice(body, "kind", REQUEST_KINDS)
        text = _text(body, "text")
        runner = _choice(body, "runner", ("host", "self"), optional=True) or "host"
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "request", now)
            q = self._question(body.get("qid"))
            pending = sum(1 for r in st["requests"] if r["pid"] == pid and r["status"]["kind"] == "pending")
            if pending >= MAX_PENDING_REQUESTS:
                raise DomainError(429, "too-many-pending", f"You have {MAX_PENDING_REQUESTS} requests waiting already.")
            rid = self._next("R")
            st["requests"].append(
                {"id": rid, "pid": pid, "qid": q["id"], "at": now, "kind": kind, "text": text, "edited": False, "runner": runner, "status": {"kind": "pending"}}
            )
            if runner == "host":
                self._queue_note([HOST], pid)
            self._notify_mentions(text, pid, f"in a request on question {q['id']}", qid=q["id"])
        self._wrote(pid, "request", now)
        return {"id": rid}

    def act_on_request(self, pid, body):
        """POST /api/request/act: edit, decline, fail, rerun one request; run the ids the owner saw; publish or discard a result."""
        action = _choice(body, "action", ("edit", "decline", "fail", "rerun", "run", "publish", "discard"))
        now = self.now()
        with self._tx() as st:
            self._owner(pid)
            if action == "run":
                ids = _body(body).get("ids")
                if not isinstance(ids, list) or not ids or len(ids) > MAX_RUN_IDS or not all(isinstance(i, str) for i in ids):
                    raise _bad("ids", f"ids must list 1 to {MAX_RUN_IDS} request ids.")
                run = [r for r in st["requests"] if r["id"] in ids and r["runner"] == "host" and r["status"]["kind"] == "pending" and self._active(r["pid"])]
                if not run:
                    raise DomainError(409, "wrong-status", "None of these requests is still waiting.", status="not-pending")
                self._run(run)
                return {"ran": [r["id"] for r in run]}
            if action in ("publish", "discard"):
                return self._act_on_result(pid, _ident(body, "id"), action)
            r = self._request(_ident(body, "id"), runner="host")
            status = r["status"]["kind"]
            allowed = {"edit": ("pending",), "decline": ("pending",), "fail": ("running",), "rerun": ("running", "failed")}[action]
            if status not in allowed:
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {status}.", status=status)
            if action == "edit":
                text = _text(body, "text")
                if text != r["text"]:
                    r["text"], r["edited"] = text, True
            elif action == "decline":
                r["status"] = {"kind": "declined", "at": now}
                self._notify(r["pid"], "request", f"Your request on question {r['qid']} was declined.", actor=pid, qid=r["qid"])
            elif action == "fail":
                r["status"] = {"kind": "failed", "at": now, "reason": "Cancelled by the owner.", "cancelled": True}
                self._event("request-cancelled", request=r["id"])
                self._notify(r["pid"], "request", f"Your request on question {r['qid']} was cancelled.", actor=pid, qid=r["qid"])
            else:
                self._run([r])
            return {"id": r["id"], "status": r["status"]["kind"]}

    def _run(self, reqs):
        st = self.state
        ev = self._event(
            "request-run",
            requests=[{"id": r["id"], "qid": r["qid"], "kind": r["kind"], "text": r["text"], "question": self._question(r["qid"])["text"]} for r in reqs],
        )
        for r in reqs:
            r["status"] = {"kind": "running", "since": self.now(), "eventSeq": ev["seq"]}
        return st

    def _find_result(self, rid):
        for lst in self.state["results"].values():
            for res in lst:
                if res["id"] == rid or (res["request"] is not None and res["request"] == rid):
                    return res
        raise DomainError(404, "not-found", f"No result {rid}.")

    def _act_on_result(self, pid, rid, action):
        res = self._find_result(rid)
        if res["published"]:
            raise DomainError(409, "wrong-status", "This result is already shown.", status="published")
        req = next((r for r in self.state["requests"] if r["id"] == res["request"]), None)
        if action == "publish":
            res["published"] = True
            if req:
                self._notify(req["pid"], "request", f"Your request on question {req['qid']} is done.", actor=pid, qid=req["qid"], body=one_line(res["summary"])[:160])
        else:
            lst = self.state["results"][res["qid"]]
            lst.remove(res)
            if not lst:
                self.state["results"].pop(res["qid"])
            if req:
                req["status"] = {"kind": "failed", "at": self.now(), "reason": "The owner did not share the result.", "cancelled": False}
                self._notify(req["pid"], "request", f"Your request on question {req['qid']} was not shared.", actor=pid, qid=req["qid"])
        return {"id": res["id"], "published": action == "publish"}

    def _new_result(self, qid, req, body, by, published):
        summary = _text(body, "summary", limit=MAX_SUMMARY)
        report = _text(body, "report", limit=MAX_REPORT, empty_ok=True)
        why = _text(body, "why", limit=MAX_TEXT, empty_ok=True)
        res = {
            "id": self._next("X"),
            "qid": qid,
            "at": self.now(),
            "request": req["id"] if req else None,
            "kind": req["kind"] if req else _choice(body, "kind", REQUEST_KINDS),
            "used": _used(body.get("used")),
            "why": why,
            "summary": summary,
            "sources": _sources(body.get("sources")),
            "report": report,
            "by": by,
            "published": published,
        }
        self.state["results"].setdefault(qid, []).append(res)
        if req:
            req["status"] = {"kind": "done", "at": self.now(), "result": res["id"]}
        return res

    def my_requests(self, pid, body):
        """GET /api/mine/requests: one's own `runner: self` requests, optionally of one status."""
        status = _choice(body or {}, "status", ("pending", "running", "declined", "done", "failed"), optional=True)
        with self._lock:
            self._person(pid)
            mine = [r for r in self.state["requests"] if r["pid"] == pid and r["runner"] == "self" and (status is None or r["status"]["kind"] == status)]
            out = []
            for r in mine:
                q = self._question(r["qid"])
                out.append({**copy.deepcopy(r), "question": q["text"]})
            return {"requests": out}

    def claim_my_request(self, pid, body):
        with self._tx():
            self._writer(pid)
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] != "pending":
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            r["status"] = {"kind": "running", "since": self.now()}
            return {"id": r["id"], "status": "running"}

    def post_my_result(self, pid, body):
        """POST /api/mine/requests/result: the requester's own Claude answers; shown at once."""
        with self._tx():
            self._writer(pid)
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] != "running":
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            res = self._new_result(r["qid"], r, body, {"kind": "guest-claude", "pid": pid}, True)
            return {"id": res["id"]}

    def fail_my_request(self, pid, body):
        reason = _text(body, "reason", limit=MAX_NOTE)
        with self._tx():
            self._writer(pid)
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] not in ("pending", "running"):
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            r["status"] = {"kind": "failed", "at": self.now(), "reason": reason, "cancelled": False}
            return {"id": r["id"], "status": "failed"}

    # -- settings, prefs, notifications, session ---------------------------------------------

    def set_prefs(self, pid, body):
        """POST /api/prefs: `{set: {key: value|null}}`, one validator per key; allowed while ended."""
        patch = _body(body).get("set")
        if not isinstance(patch, dict) or not patch:
            raise _bad("set", "Send set: {key: value}.")
        bad = sorted(str(k)[:40] for k, v in patch.items() if k not in PREFS or not (v is None or PREFS[k](v)))
        if bad:
            raise _bad("set", f"Unknown key or bad value: {', '.join(bad[:10])}.")
        now = self.now()
        with self._write_as(pid, "prefs", check=self._person) as st:
            mine = st["prefs"].setdefault(pid, {})
            for k, v in patch.items():
                if v is None:
                    mine.pop(k, None)
                else:
                    mine[k] = {"value": v, "at": now}
            if not mine:
                st["prefs"].pop(pid)
            return {"prefs": {k: copy.deepcopy(v["value"]) for k, v in mine.items()}, "at": now}

    def read_notifications(self, pid, body):
        """POST /api/notifications/read: `{ids}` or `{all: true}`; allowed while ended."""
        body = _body(body)
        everything = body.get("all") is True
        ids = body.get("ids")
        if not everything and not (isinstance(ids, list) and ids and all(isinstance(i, str) for i in ids)):
            raise _bad("ids", "Send ids: [...] or all: true.")
        want = None if everything else set(ids[:NOTIFY_CAP])
        with self._write_as(pid, "notifications-read", check=self._person) as st:
            n = 0
            for note in st["notifications"].get(pid, []):
                if not note["read"] and (want is None or note["id"] in want):
                    note["read"] = True
                    n += 1
            return {"read": n}

    def update_settings(self, pid, body):
        """POST /api/session/settings: a partial Settings object."""
        _body(body)
        with self._tx() as st:
            self._owner(pid)
            _settings_patch(st["session"]["settings"], body)
            return {"settings": copy.deepcopy(st["session"]["settings"])}

    def set_title(self, pid, body):
        title = _text(body, "title", limit=MAX_TITLE)
        with self._tx() as st:
            self._owner(pid)
            st["session"]["title"] = title
            return {"title": title}

    def set_goal(self, pid, body):
        goal = _text(body, "goal", limit=MAX_GOAL, empty_ok=True)
        with self._tx() as st:
            self._owner(pid)
            st["session"]["goal"] = goal
            return {"goal": goal}

    def set_intro(self, pid, body):
        """POST /api/session/intro: the owner edits "Why you're here" (1..MAX_INTRO characters; empty clears it)."""
        intro = _text(body, "intro", limit=MAX_INTRO, empty_ok=True)
        with self._tx():
            self._owner(pid)
            return self._put_intro(intro)

    def _put_intro(self, intro):
        if intro:
            self.state["session"]["intro"] = intro
        else:
            self.state["session"].pop("intro", None)
        return {"intro": intro}

    def end_session(self, pid, body):
        """POST /api/session/end: `on` ends it and writes `session-ended` with the Later list; off reopens."""
        on = _bool(body, "on")
        with self._tx() as st:
            self._owner(pid)
            if on == self._ended():
                raise DomainError(409, "wrong-status", "The session is already " + ("ended." if on else "live."), status=st["session"]["phase"]["kind"])
            later = [
                {"id": p["id"], "text": p["text"], "reason": p["status"]["reason"]}
                for p in st["proposals"]
                if p["status"]["kind"] == "later" and self._active(p["pid"])
            ]
            if on:
                st["session"]["phase"] = {"kind": "ended", "at": self.now()}
                self._event("session-ended", later=later)
            else:
                st["session"]["phase"] = {"kind": "live"}
            return {"later": len(later)}

    def rotate_guest_link(self, pid, body):
        """POST /api/link/guest: a new guest key; the old guest link stops admitting new people."""
        _body(body)
        with self._tx() as st:
            self._owner(pid)
            st["session"]["guestKey"] = self.ids.token(9)
            return {"guestKey": st["session"]["guestKey"]}

    def rotate_owner_link(self, pid, body):
        """POST /api/link/owner: a new owner token; the old owner link stops working."""
        _body(body)
        with self._tx() as st:
            self._owner(pid)
            token = self.ids.token(32)
            at = self.now()
            if self.on_owner_token is not None:  # the secrets file holds the token before the hash commits
                self.on_owner_token(token, at)
            st["credentials"]["owner"] = {"tokenHash": sha256(token), "rotatedAt": at}
            return {"token": token}

    # -- notifications -----------------------------------------------------------------------

    def _moderator_pids(self):
        return [p for p, v in self.state["people"].items() if v["role"] in ("owner", "leader") and v["status"]["kind"] == "active"]

    def _notify(self, pid, kind, title, *, actor=None, rollup=None, window=None, **ref):
        """Add a notification for pid, or update its rolled-up line. Never to the actor, a removed person or a muted kind."""
        st = self.state
        if pid == actor or not self._active(pid):
            return None
        muted = st["prefs"].get(pid, {}).get("mute", {}).get("value", [])
        if kind in muted:
            return None
        now = self.now()
        lst = st["notifications"].setdefault(pid, [])
        extra = {k: v for k, v in ref.items() if v not in (None, "")}
        if rollup:
            old = next((n for n in reversed(lst) if n.get("rollup", {}).get("key") == rollup), None)
            if old and (now - old["rollup"]["since"] < window if window else not old["read"]):
                old.update(title=title, at=now, read=False, **extra)
                old["rollup"]["n"] += 1
                lst.remove(old)
                lst.append(old)
                return old
        note = {"id": self._next("N"), "kind": kind, "title": title, "at": now, "read": False, **extra}
        if rollup:
            note["rollup"] = {"key": rollup, "since": now, "n": 1}
        lst.append(note)
        del lst[:-NOTIFY_CAP]
        return note

    def _queue_note(self, pids, actor):
        """One unread line per moderator counting new queue items, never one line per item."""
        for p in pids:
            old = next((n for n in reversed(self.state["notifications"].get(p, [])) if n.get("rollup", {}).get("key") == "queue" and not n["read"]), None)
            k = old["rollup"]["n"] + 1 if old else 1
            self._notify(p, "queue", f"{k} new item{'' if k == 1 else 's'} in the queue.", actor=actor, rollup="queue")

    def _mentioned(self, text, actor):
        """pids named as @Name in text (longest names first, so @Sam 2 is not also @Sam), at most 10."""
        t, out = str(text or "").casefold(), []
        if "@" not in t:
            return out
        people = sorted(self.state["people"].items(), key=lambda kv: -len(kv[1]["name"]))
        for p, v in people:
            tag = "@" + v["name"].casefold()
            i = t.find(tag)
            while i >= 0:
                end = i + len(tag)
                if (i == 0 or not t[i - 1].isalnum()) and (end == len(t) or not (t[end].isalnum() or t[end] == "_")):
                    t = t[:i] + " " * len(tag) + t[end:]
                    if p != actor and self._active(p) and p not in out:
                        out.append(p)
                    break
                i = t.find(tag, i + 1)
        return out[:MAX_MENTIONS]

    def _notify_mentions(self, text, actor, where, *, before="", skip=(), **ref):
        old = set(self._mentioned(before, actor)) if before else set()
        for p in self._mentioned(text, actor):
            if p not in old and p not in skip:
                self._notify(p, "mention", f"mentioned you {where}.", actor=actor, by=actor, body=one_line(text)[:160], **ref)

    # -- event log and digest ----------------------------------------------------------------

    def _event(self, kind, **fields):
        log = self.state["log"]
        log["seq"] += 1
        ev = {"seq": log["seq"], "at": iso(self.now()), "kind": kind, **fields}
        log["events"].append(ev)
        return ev

    def _previous_send(self, n):
        """When the last digest before round n went to Claude; 0 when none did."""
        sent = [r["status"]["sentAt"] for r in self.state["rounds"] if r["n"] < n and "sentAt" in r["status"]]
        return max(sent, default=0.0)

    def _digest(self, n):
        st = self.state
        names = st["session"]["settings"]["digestNames"]

        def by(pid):
            return {"by": st["people"][pid]["name"]} if names and pid in st["people"] else {}

        prev = self._previous_send(n)
        questions = []
        for q in st["questions"]:
            if q["round"] != n:
                continue
            entry = {"id": q["id"], "text": q["text"], **({"scope": q["scope"]} if q.get("scope") else {})}
            entry.update(purpose=q["purpose"], format=q["format"]["kind"])
            disagreements = self._digest_disagreements(q, by)
            if disagreements:
                entry["disagreements"] = disagreements
            entry["outcome"] = self._outcome(q, by)
            questions.append(entry)
        late = []
        for q in st["questions"]:
            for c in st["cards"].get(q["id"], []):
                if c["kind"] == "person" and c.get("late") and c["at"] > prev and self._shown(c):
                    late.append({"id": q["id"], "round": c["late"]["round"], "text": self._said(q, c), **by(c["pid"]), **_edited(c)})
        review = []
        for q in st["questions"]:
            newest = {}
            for f in q["needsReview"]:
                newest[f["because"]] = f
            for because, f in newest.items():
                lk = st["locks"].get(because)
                now_ = {"kind": "locked", "text": lk["source"]["text"]} if lk else {"kind": "unlocked"}
                item = {"id": q["id"], "because": because, "now": now_}
                if f["why"]["kind"] == "suggested":
                    item["suggestion"] = f["why"]["suggestion"]
                review.append(item)
        results = [
            {"qid": r["qid"], "id": r["id"], "kind": r["kind"], "summary": r["summary"]}
            for lst in st["results"].values()
            for r in lst
            if r["published"] and r["at"] > prev
        ]
        proposals = [{"id": p["id"], "text": p["text"], **by(p["pid"])} for p in st["proposals"] if p["status"]["kind"] == "new" and self._active(p["pid"])]
        notes = [
            {"qid": a["qid"], "variant": a["variant"], "text": a["text"], **by(a["pid"])}
            for a in st["annotations"]
            if a["at"] > prev and self._active(a["pid"])
        ]
        digest = {
            "round": n,
            "names": names,
            "questions": questions,
            "late": late,
            "needsReview": review,
            "results": results,
            "proposals": proposals,
            "annotations": notes,
            "people": self._digest_people(n),
        }
        if names:
            digest["aboutYou"] = [
                {"name": st["people"][p]["name"], "techComfort": a["techComfort"], **({"note": a["note"]} if a.get("note") else {})}
                for p, a in st["aboutYou"].items()
                if self._active(p)
            ]
        return digest

    def _said(self, q, c):
        """One line for what a person card says: its text, else its pick, picks, value or order."""
        labels = {**self._options(q), OTHER: OTHER_OPTION["label"]}
        if c["text"]:
            return c["text"]
        if "picks" in c:
            return ", ".join(labels[o] for o in c["picks"])
        if "order" in c:
            return " > ".join(labels[o] for o in c["order"])
        if "value" in c:
            return labels[str(c["value"])]
        return labels.get(c.get("pick"), "")

    def _digest_disagreements(self, q, by):
        """Who disagreed with which answer of q and why, while that answer and its disagreer remain."""
        out = []
        for d in self.state.get("disagreements", {}).get(q["id"], []):
            if not self._active(d["pid"]):
                continue
            try:
                text = self._card_text(q, d["card"])
            except DomainError:
                continue
            out.append({"text": text, "reason": d["reason"], **by(d["pid"])})
        return out

    def _digest_people(self, n):
        st = self.state
        qids = {q["id"] for q in st["questions"] if q["round"] == n}
        answered, devices = set(), {}
        for qid in qids:
            for c in st["cards"].get(qid, []):
                if c["kind"] == "person" and self._shown(c):
                    answered.add(c["pid"])
                    kind = c.get("device") or c.get("deviceInfo", {}).get("kind")
                    if kind:
                        devices[c["pid"]] = kind
            answered.update(v for v in [*st["votes"].get(qid, {}), *st.get("backs", {}).get(qid, {})] if self._active(v))
        joined = sum(1 for p in st["people"] if p != HOST and self._active(p))
        out = {"joined": joined, "answered": len(answered)}
        if devices:
            out["devices"] = {k: sum(1 for d in devices.values() if d == k) for k in DEVICES}
        return out

    def _outcome(self, q, by):
        st = self.state
        qid = q["id"]
        lk = st["locks"].get(qid)
        if q["format"]["kind"] in ("multi", "scale", "rank") and not (lk and q["purpose"] != "poll"):
            return self._format_outcome(q, by, closed=lk is not None)
        if q["purpose"] == "poll":
            tally = self._tally(qid)
            counts = [{"option": label, "votes": tally.get(f"o:{o}", 0)} for o, label in self._options(q).items()]
            for c in self._own_options(q):
                counts.append({"option": c["text"], "votes": tally[card_ref(c)], "other": True, **by(c["pid"]), **_edited(c)})
            return {"kind": "poll", "closed": lk is not None, "counts": counts}
        if lk:
            src = lk["source"]
            out = {"kind": "locked", "text": src["text"]}
            if src["kind"] == "card":
                ref = src["card"]
                out["source"] = {"p": "person", "o": "option"}.get(ref[0]) or ("claude-rec" if ref == "c:rec" else "claude-alt")
                if ref_author(ref):
                    out.update(by(ref_author(ref)))
                if src.get("editedBy"):
                    out["edited"] = True
            elif src["kind"] == "suggestion":
                out["source"] = "suggestion"
                s = next((s for s in st["suggestions"].get(qid, []) if s["id"] == src["suggestion"]), None)
                if s:
                    out.update(by(s["pid"]))
            else:
                out["source"] = "edited"
                out.update(by(lk["by"]))
            return out
        people = [c for c in st["cards"].get(qid, []) if c["kind"] == "person" and self._shown(c)]
        if q["purpose"] == "gather":
            answers = []
            for c in people:
                if not c["text"]:
                    continue
                counts = dict.fromkeys(REACTIONS, 0)
                for voter, reaction in st["reactions"].get(qid, {}).get(card_ref(c), {}).items():
                    if self._active(voter):
                        counts[reaction] += 1
                answers.append({"text": c["text"], "reactions": counts, **by(c["pid"]), **_edited(c)})
            return {"kind": "gathered", "answers": answers} if answers else {"kind": "unanswered"}
        tally = self._tally(qid)
        ranked = []
        for i, c in enumerate(st["cards"].get(qid, [])):
            ref = card_ref(c)
            if ref not in tally or (c["kind"] != "person" and tally[ref] == 0):
                continue
            if c["kind"] == "person":
                source = "person"
            elif c["kind"] == "claude":
                source = "claude-rec" if c["key"] == "rec" else "claude-alt"
            else:
                source = "option"
            entry = {"text": self._card_text(q, ref), "votes": tally[ref], "source": source}
            if self._is_other(c):
                entry["other"] = True
            ranked.append(((-tally[ref], ref != "c:rec", c.get("at", 0.0), i), {**entry, **(by(c["pid"]) if c["kind"] == "person" else {}), **_edited(c)}))
        if not ranked:
            return {"kind": "unanswered"}
        ranked.sort(key=lambda pair: pair[0])
        keep = 3 if q["format"]["kind"] == "text" else 6
        return {"kind": "open", "top": [entry for _, entry in ranked[:keep]]}

    def _own_options(self, q):
        """Active people's own Something else options on q, as their cards."""
        return [c for c in self.state["cards"].get(q["id"], []) if self._is_other(c) and self._shown(c)]

    def _format_outcome(self, q, by, *, closed):
        """The digest outcome of a multi, scale or rank question: counts per option (multi), counts
        per value with the mean and median (scale), Borda totals and the full orders given (rank);
        each with people's own options, their backers (author included), and the comments."""
        qid, fmt = q["id"], q["format"]
        cards = [c for c in self.state["cards"].get(qid, []) if c["kind"] == "person" and self._shown(c)]
        labels = self._options(q)
        others = [{"text": c["text"], "backers": len(self._votes_on(qid, card_ref(c))) + 1, **by(c["pid"]), **_edited(c)} for c in self._own_options(q)]
        comments = [{"text": c["text"], **by(c["pid"]), **_edited(c)} for c in cards if c["text"] and not self._is_other(c)]
        if fmt["kind"] == "multi":
            picked = [c["picks"] for c in cards if c.get("picks")]
            counts = [{"option": label, "picks": sum(1 for p in picked if o in p)} for o, label in labels.items()]
            out = {"kind": "multi", "closed": closed, "people": len(picked), "counts": counts, "others": others, "comments": comments}
        elif fmt["kind"] == "scale":
            values = sorted(c["value"] for c in cards if "value" in c)
            out = {"kind": "scale", "closed": closed, "people": len(values), "min": fmt["min"], "max": fmt["max"], "labels": dict(fmt["labels"])}
            out["counts"] = [{"value": v, "people": values.count(v)} for v in range(fmt["min"], fmt["max"] + 1)]
            out["mean"] = round(statistics.fmean(values), 2) if values else None
            out["median"] = statistics.median(values) if values else None
            out["comments"] = comments
        else:
            ballots = [tuple(o for o in c["order"] if o != OTHER) for c in cards if c.get("order")]
            points = dict.fromkeys(labels, 0)
            for b in ballots:
                for i, o in enumerate(b):
                    points[o] += len(b) - 1 - i
            ids = list(labels)
            borda = [{"option": labels[o], "points": points[o]} for o in sorted(ids, key=lambda o: (-points[o], ids.index(o)))]
            given = collections.Counter(ballots)
            orders = [{"order": [labels[o] for o in b], "people": n} for b, n in sorted(given.items(), key=lambda kv: (-kv[1], [ids.index(o) for o in kv[0]]))]
            out = {"kind": "rank", "closed": closed, "people": len(ballots), "borda": borda, "orders": orders, "others": others, "comments": comments}
        if not out["people"] and not others and not comments:
            return {"kind": "unanswered"}
        return out

    # -- ops ---------------------------------------------------------------------------------

    def apply(self, doc):
        """Claude's ops (share.sh apply): parsed against ops.schema.json, then all land or none does."""
        err = ops_error(doc)
        if err:
            m = re.match(r"\$\.ops\[(\d+)\]", err)
            at = {"op": int(m.group(1))} if m else {}
            long = re.search(r"\$\.ops\[\d+\]\.([^\s:;()]+): allows at most (\d+) characters", err)
            if long:
                raise DomainError(400, "too-long", err, field=long.group(1), max=int(long.group(2)), **at)
            raise DomainError(400, "bad-field", err, field="ops", **at)
        with self._lock:
            self._undo = []
            try:
                with self._tx():
                    results = []
                    for i, op in enumerate(doc["ops"]):
                        try:
                            results.append(getattr(self, "_op_" + op["op"].replace("-", "_"))(op))
                        except DomainError as exc:
                            exc.details.setdefault("op", i)
                            raise
                    return {"results": results}
            except BaseException:
                for f, before in reversed(self._undo):
                    with contextlib.suppress(OSError):
                        if before is None:
                            f.unlink()
                        else:
                            write_private(f, before.decode("utf-8"))
                raise

    def _op_set_title(self, op):
        self.state["session"]["title"] = _text(op, "title", limit=MAX_TITLE)
        return {"title": self.state["session"]["title"]}

    def _op_set_goal(self, op):
        self.state["session"]["goal"] = _text(op, "goal", limit=MAX_GOAL, empty_ok=True)
        return {"goal": self.state["session"]["goal"]}

    def _op_set_intro(self, op):
        """Claude sets "Why you're here" once the owner said yes to its draft in the terminal."""
        return self._put_intro(_text(op, "intro", limit=MAX_INTRO, empty_ok=True))

    def _op_ack_round(self, op):
        r = self._step("ack", CLAUDE)
        if r["n"] != op["round"]:
            raise DomainError(409, "wrong-status", f"Round {op['round']} is not the round waiting for Claude.", status=r["status"]["kind"])
        r["status"] = {"kind": "working", "sentAt": r["status"]["sentAt"], "ackAt": self.now(), "eventSeq": r["status"]["eventSeq"]}
        return {"round": r["n"]}

    def _digested_proposals(self, r):
        """Ids of proposals the round's digest listed that are still new: each needs a placement."""
        seq = r["status"].get("eventSeq")
        ev = next((e for e in self.state["log"]["events"] if e["seq"] == seq), None)
        listed = {p["id"] for p in ev["digest"]["proposals"]} if ev else set()
        return {p["id"] for p in self.state["proposals"] if p["id"] in listed and p["status"]["kind"] == "new" and self._active(p["pid"])}

    def _op_open_round(self, op):
        st = self.state
        cur = self._current_round()
        if cur is not None and cur["status"]["kind"] != "closed":
            self._step("open-round", CLAUDE)
        required = self._digested_proposals(cur) if cur is not None and cur["status"]["kind"] == "working" else set()
        n = self._next_round_n()
        if len(op["questions"]) > MAX_ROUND:
            raise DomainError(400, "too-long", f"A round holds at most {MAX_ROUND} questions.", field="questions", max=MAX_ROUND)
        known = {q["id"] for q in st["questions"]}
        made = []
        for i, qi in enumerate(op["questions"]):
            q = self._parse_question(qi, round_n=n, origin={"kind": "claude"}, known=known, field=f"questions[{i}]")
            known.add(q["id"])
            made.append(q)
        effects = self._parse_placements(op.get("placements", []), required, n, known, made)
        for target in {n, n + 1}:
            size = self._round_size(target) + sum(1 for q in made if q["round"] == target)
            if size > MAX_ROUND:
                raise DomainError(409, "round-full", f"Round {target} would hold {size} questions; the most is {MAX_ROUND}.")
        now = self.now()
        if cur is not None and cur["status"]["kind"] == "working":
            s = cur["status"]
            cur["status"] = {"kind": "closed", "sentAt": s["sentAt"], "ackAt": s["ackAt"], "closedAt": now, "next": n}
        elif cur is not None:
            cur["status"]["next"] = n
        st["rounds"].append({"n": n, "openedAt": now, "status": {"kind": "open"}})
        for q in made:
            self._add_question(q)
        placed = self._place(effects)
        count = self._round_size(n)
        for p in list(st["people"]):
            self._notify(p, "round", f"Round {n} is here.", body=f"{count} question{'' if count == 1 else 's'}")
        return {"round": n, "ids": [q["id"] for q in made], "placed": placed}

    def _op_close_round(self, op):
        cur = self._step("close-round", CLAUDE)
        required = self._digested_proposals(cur)
        n = cur["n"] + 1
        known = {q["id"] for q in self.state["questions"]}
        made = []
        effects = self._parse_placements(op.get("placements", []), required, n, known, made)
        for target in {n, n + 1}:
            size = self._round_size(target) + sum(1 for q in made if q["round"] == target)
            if size > MAX_ROUND:
                raise DomainError(409, "round-full", f"Round {target} would hold {size} questions; the most is {MAX_ROUND}.")
        s = cur["status"]
        cur["status"] = {"kind": "closed", "sentAt": s["sentAt"], "ackAt": s["ackAt"], "closedAt": self.now(), "next": None}
        for q in made:
            self._add_question(q)
        return {"round": cur["n"], "placed": self._place(effects)}

    def _parse_placements(self, placements, required, n, known, made):
        """Check every placement before anything changes; returns the effects to apply."""
        seen, effects = set(), []
        for i, pl in enumerate(placements):
            field = f"placements[{i}]"
            prop = self._proposal(pl["proposal"])
            if prop["id"] in seen:
                raise _bad(field, f"Proposal {prop['id']} is placed twice.")
            seen.add(prop["id"])
            if prop["status"]["kind"] != "new":
                raise DomainError(409, "wrong-status", f"Proposal {prop['id']} is {prop['status']['kind']}.", status=prop["status"]["kind"])
            kind = pl["as"]
            if kind in ("question", "later-round"):
                round_n = n if kind == "question" else n + 1
                origin = {"kind": "proposal", "proposal": prop["id"]}
                if pl.get("question") is not None:
                    qi = dict(pl["question"])
                    if kind == "later-round":
                        for d in pl["after"]:
                            if d not in known:
                                raise _bad(f"{field}.after", f"{d} is not a question.")
                        qi["dependsOn"] = list(dict.fromkeys([*qi["dependsOn"], *pl["after"]]))
                    q = self._parse_question(qi, round_n=round_n, origin=origin, known=known, field=f"{field}.question")
                else:
                    q = {
                        "id": self._next_qid(known),
                        "text": prop["text"],
                        "alternatives": [],
                        "dependsOn": [],
                        "round": round_n,
                        "purpose": "decide",
                        "format": {"kind": "text"},
                        "answerScope": "person",
                        "references": [],
                        "origin": origin,
                        "needsReview": [],
                    }
                known.add(q["id"])
                made.append(q)
                effects.append((prop, {"kind": "question", "question": q["id"]}, None))
            elif kind == "suggestion":
                target = self._question(pl["target"], f"{field}.target")
                if target["id"] not in self.state["locks"]:
                    raise DomainError(409, "not-locked", f"A suggestion goes on a locked question; {target['id']} is not locked.")
                text = _text(pl, "text", optional=True) or prop["text"]
                note = _text(pl, "reason", limit=MAX_NOTE, optional=True) or "Claude placed this proposal here as a suggested change."
                effects.append((prop, None, (target["id"], text, note)))
            elif kind == "merge":
                target = self._question(pl["target"], f"{field}.target")
                effects.append((prop, {"kind": "merged", "question": target["id"], "reason": _text(pl, "reason")}, None))
            else:
                effects.append((prop, {"kind": kind, "reason": _text(pl, "reason")}, None))
        missing = sorted(required - seen)
        if missing:
            raise _bad("placements", f"Every proposal in the digest needs a placement; missing {', '.join(missing)}.")
        return effects

    def _place(self, effects):
        st = self.state
        placed = []
        for prop, status, suggestion in effects:
            if suggestion is not None:
                target, text, note = suggestion
                sid = self._next("S")
                st["suggestions"].setdefault(target, []).append(
                    {"id": sid, "pid": prop["pid"], "text": text, "note": note, "at": self.now(), "fromProposal": prop["id"], "status": {"kind": "open"}}
                )
                status = {"kind": "suggested", "question": target, "suggestion": sid}
                self._flag(target, {"kind": "suggested", "suggestion": sid})
            prop["status"] = status
            said = {
                "question": f"Your proposal became question {status.get('question')}.",
                "suggested": f"Your proposal became a suggested change on question {status.get('question')}.",
                "merged": f"Your proposal was merged into question {status.get('question')}.",
                "later": "Your proposal was moved to Later.",
                "not-placed": "Your proposal was not placed.",
            }[status["kind"]]
            self._notify(prop["pid"], "proposal", said, body=status.get("reason"), qid=status.get("question"))
            placed.append({"proposal": prop["id"], "as": status["kind"], **({"question": status["question"]} if "question" in status else {})})
        return placed

    def _op_result(self, op):
        q = self._question(op["qid"])
        req = None
        if op.get("request") is not None:
            req = self._request(op["request"], runner="host")
            if req["status"]["kind"] != "running":
                raise DomainError(409, "wrong-status", f"Request {req['id']} is {req['status']['kind']}.", status=req["status"]["kind"])
            if req["qid"] != q["id"]:
                raise _bad("qid", f"Request {req['id']} is on question {req['qid']}.")
        res = self._new_result(q["id"], req, op, {"kind": "host-claude"}, False)
        self._queue_note([HOST], None)
        return {"id": res["id"], "published": False}

    def _op_fail_request(self, op):
        req = self._request(op["request"], runner="host")
        if req["status"]["kind"] not in ("pending", "running"):
            raise DomainError(409, "wrong-status", f"Request {req['id']} is {req['status']['kind']}.", status=req["status"]["kind"])
        reason = _text(op, "reason", limit=MAX_NOTE)
        req["status"] = {"kind": "failed", "at": self.now(), "reason": reason, "cancelled": False}
        self._notify(req["pid"], "request", f"Your request on question {req['qid']} failed.", qid=req["qid"], body=reason)
        return {"id": req["id"], "status": "failed"}

    def _op_add_reference(self, op):
        return self._edit_reference({"qid": op["qid"], "reference": op["reference"]})

    def _op_remove_reference(self, op):
        return self._edit_reference({"qid": op["qid"], "remove": op["index"]})

    def _op_add_asset(self, op):
        """Copy a local image or HTML file into assets/ under its content id; usable from the next apply."""
        src = _asset_source(op["path"], self.path.parent)
        data = src.read_bytes()
        if len(data) > ASSET_MAX:
            raise DomainError(400, "too-long", f"An asset is at most {ASSET_MAX} bytes.", field="path", max=ASSET_MAX)
        ext = _asset_type(data, op.get("as"))
        aid = f"{hashlib.sha256(data).hexdigest()[:16]}.{ext}"
        self.assets_dir.mkdir(parents=True, exist_ok=True)
        dest = self.assets_dir / aid
        if not dest.exists():
            tmp = dest.with_name(f".{aid}.{secrets.token_hex(4)}.tmp")
            tmp.write_bytes(data)
            replace_into(tmp, dest)
            self._undo.append((dest, None))
        meta = {"id": aid, "kind": ASSET_KINDS[ext], "bytes": len(data), "at": self.now(), "scale": op.get("scale", 1)}
        meta_path = self.assets_dir / f".{aid}.json"
        self._undo.append((meta_path, meta_path.read_bytes() if meta_path.exists() else None))
        write_private(meta_path, json.dumps(meta) + "\n")
        return meta

    def _op_make_question_from(self, op):
        prop = self._proposal(op["proposal"])
        kind = prop["status"]["kind"]
        if kind not in PROPOSAL_ACTIONS["question"]:
            raise DomainError(409, "wrong-status", f"Proposal {prop['id']} is {kind}.", status=kind)
        n = self._next_round_n()
        known = {q["id"] for q in self.state["questions"]}
        q = self._parse_question(op["question"], round_n=n, origin={"kind": "host", "proposal": prop["id"], "by": HOST}, known=known, field="question")
        if self._round_size(n) >= MAX_ROUND:
            raise DomainError(409, "round-full", f"Round {n} already holds {MAX_ROUND} questions.")
        self._add_question(q)
        prop["status"] = {"kind": "question", "question": q["id"]}
        self._notify(prop["pid"], "proposal", f"Your proposal became question {q['id']}, in round {n}.", qid=q["id"])
        return {"question": q["id"], "round": n}

    def _op_handle(self, op):
        log = self.state["log"]
        for seq in op["seqs"]:
            if seq > log["seq"]:
                raise DomainError(404, "not-found", f"No event {seq}.")
        log["handled"] = sorted(set(log["handled"]) | set(op["seqs"]))
        return {"handled": list(op["seqs"])}

    # -- runtime hooks the server calls ------------------------------------------------------

    def reset_owner_token(self, token, issued_at):
        """Make `token`, issued at `issued_at`, the owner's credential (the server's 0600 secrets file
        is authoritative), refusing a token older than the last rotation recorded in the state."""
        with self._lock:
            owner = self.state["credentials"]["owner"]
            if self.is_owner_token(token):
                return False
            if owner["rotatedAt"] > issued_at:
                raise DomainError(
                    409,
                    "owner-token-stale",
                    "The owner token in the secrets file predates the session's last owner-link rotation; "
                    "delete .shared-secrets.json to issue a new owner link.",
                )
            with self._tx() as st:
                st["credentials"]["owner"] = {"tokenHash": sha256(token), "rotatedAt": issued_at}
            return True

    def is_owner_token(self, token):
        return hmac.compare_digest(sha256(token), self.state["credentials"]["owner"]["tokenHash"])

    def owner_rotated_at(self):
        """When the owner link was last rotated (the schema requires it; an import sets it)."""
        return self.state["credentials"]["owner"]["rotatedAt"]

    def clamp_owner_rotation(self):
        """Set an owner-link rotation time ahead of the clock (a clock rollback) to now, so a token
        issued now is not refused; the old time when it was ahead, else None."""
        with self._lock:
            at, now = self.owner_rotated_at(), self.now()
            if at <= now:
                return None
            with self._tx() as st:
                st["credentials"]["owner"]["rotatedAt"] = now
            return at

    def set_share(self, url):
        """Record the guest link's base; a change from an earlier link sets share.changedAt."""
        with self._lock:
            old = self.state["session"]["share"]
            if old["url"] == url:
                return False
            with self._tx() as st:
                share = {"url": url}
                if old["url"]:
                    share["changedAt"] = self.now()
                elif "changedAt" in old:
                    share["changedAt"] = old["changedAt"]
                st["session"]["share"] = share
            return True

    def log_copy(self):
        """A copy of the event log, for the session-bridge transport."""
        with self._lock:
            return copy.deepcopy(self.state["log"])

    def mark_delivered(self, log):
        """Persist the deliveredAt stamps the transport put on a copy of the log."""
        stamps = {e["seq"]: e["deliveredAt"] for e in log.get("events", []) if e.get("deliveredAt")}
        with self._lock:
            fresh = [e for e in self.state["log"]["events"] if e["seq"] in stamps and not e.get("deliveredAt")]
            if not fresh:
                return
            with self._tx():
                for e in fresh:
                    e["deliveredAt"] = stamps[e["seq"]]

    def summary(self):
        """What `share.sh status` reports: round, people, the owner's queue, unhandled events."""
        with self._lock:
            st = self.state
            cur = self._current_round()
            handled = set(st["log"]["handled"])
            active = [p for p in st["people"] if p != HOST and self._active(p)]
            return {
                "title": st["session"]["title"],
                "intro": bool(st["session"].get("intro")),
                "ended": self._ended(),
                "guestKey": st["session"]["guestKey"],
                "share": copy.deepcopy(st["session"]["share"]),
                "round": {"n": cur["n"], "status": cur["status"]["kind"]} if cur else None,
                "people": {"joined": len(active), "here": len(self._present() - {HOST})},
                "queue": {
                    "requests": sum(1 for r in st["requests"] if r["runner"] == "host" and r["status"]["kind"] == "pending" and self._active(r["pid"])),
                    "results": sum(1 for lst in st["results"].values() for r in lst if not r["published"]),
                    "uploads": sum(1 for u in st["uploads"] if u["status"]["kind"] == "offered"),
                    "merges": sum(1 for m in st["mergeRequests"] if m["status"]["kind"] == "pending"),
                    "joins": sum(1 for p in st["people"].values() if p["status"]["kind"] == "waiting"),
                    "proposals": sum(1 for p in st["proposals"] if p["status"]["kind"] == "new" and self._active(p["pid"])),
                },
                "unhandled": sum(1 for e in st["log"]["events"] if e["seq"] not in handled and not e.get("withdrawn")),
            }

    def presence_rev(self):
        """A counter that moves on every presence change, which never changes `rev`."""
        return self._presence_rev

    # -- views -------------------------------------------------------------------------------

    def anonymous_view(self):
        """GET /api/state without identity: only what the join dialog needs."""
        with self._lock:
            s = self.state["session"]
            return {"title": s["title"], "ended": self._ended(), "joinNeedsKey": bool(s["guestKey"]), "schemaVersion": self.state["schemaVersion"]}

    def _base(self):
        """The part of every person's snapshot that is the same for all of them; built once per rev."""
        st = self.state
        if self._base_cache and self._base_cache[0] == st["rev"]:
            return self._base_cache[1]
        active = {p for p in st["people"] if self._active(p)}
        cards = {qid: [self._public_card(qid, c, active) for c in lst if self._shown(c)] for qid, lst in st["cards"].items()}
        suggestions = {}
        for qid, lst in st["suggestions"].items():
            by = st["suggestionVotes"].get(qid, {})
            suggestions[qid] = [{**s, "votes": sorted(v for v, sid in by.items() if sid == s["id"] and v in active)} for s in lst if s["pid"] in active]
        cur = self._current_round()
        base = {
            "schemaVersion": st["schemaVersion"],
            "rev": st["rev"],
            "title": st["session"]["title"],
            "goal": st["session"]["goal"],
            "intro": st["session"].get("intro", ""),
            "ended": self._ended(),
            "settings": st["session"]["settings"],
            "rounds": st["rounds"],
            "round": {"n": cur["n"], "status": cur["status"]["kind"]} if cur else None,
            "questions": st["questions"],
            "cards": cards,
            "locks": st["locks"],
            "suggestions": suggestions,
            "disagreements": {q: [d for d in lst if d["pid"] in active] for q, lst in st.get("disagreements", {}).items()},
            "results": {q: [r for r in lst if r["published"]] for q, lst in st["results"].items()},
            "chat": [self._public_chat(m, active) for m in st["chat"] if m["pid"] in active],
            "annotations": [a for a in st["annotations"] if a["pid"] in active],
            "people": [
                {k: v[k] for k in ("pid", "name", "role", "trusted", "color", "joinedAt")}
                for v in st["people"].values()
                if v["pid"] in active
            ],
            "requestCounts": self._request_counts(),
        }
        base = json.loads(json.dumps(base))
        self._base_cache = (st["rev"], base)
        return base

    def _public_card(self, qid, c, active):
        """One card as people read it: never `view`, `deviceInfo` or `history`; with its ref, the
        active people who vote for or back it, and its Gather reaction counts."""
        ref = card_ref(c)
        shown = {k: v for k, v in c.items() if k not in ("view", "deviceInfo", "history")}
        shown["ref"] = ref
        shown["votes"] = sorted(self._votes_on(qid, ref))
        counts = dict.fromkeys(REACTIONS, 0)
        for voter, reaction in self.state["reactions"].get(qid, {}).get(ref, {}).items():
            if voter in active:
                counts[reaction] += 1
        shown["reactions"] = counts
        return shown

    @staticmethod
    def _public_chat(m, active):
        """A chat message with only active people's reactions."""
        if "reactions" not in m:
            return m
        reactions = {e: [p for p in pids if p in active] for e, pids in m["reactions"].items()}
        out = {k: v for k, v in m.items() if k != "reactions"}
        reactions = {e: pids for e, pids in reactions.items() if pids}
        return {**out, "reactions": reactions} if reactions else out

    def _own_view_cards(self, pid, active):
        """The questions whose cards this viewer reads differently from everyone: the owner sees hidden
        answers and how many earlier versions each has (`versions`; the versions themselves come from
        `card_history`); an author sees their own hidden answer, marked."""
        owner = pid == HOST
        out = {}
        for qid, lst in self.state["cards"].items():
            if not any(c["kind"] == "person" and c["pid"] in active and (("hidden" in c and (owner or c["pid"] == pid)) or (owner and "history" in c)) for c in lst):
                continue
            rebuilt = []
            for c in lst:
                if c["kind"] == "person" and (c["pid"] not in active or ("hidden" in c and not (owner or c["pid"] == pid))):
                    continue
                card = self._public_card(qid, c, active)
                if owner and "history" in c:
                    card["versions"] = len(c["history"])
                rebuilt.append(card)
            out[qid] = copy.deepcopy(rebuilt)
        return out

    def _request_counts(self):
        by_q = {}
        for r in self.state["requests"]:
            if r["runner"] == "host" and r["status"]["kind"] in ("pending", "running") and self._active(r["pid"]):
                by_q[r["qid"]] = by_q.get(r["qid"], 0) + 1
        return {"open": sum(by_q.values()), "byQ": by_q}

    def snapshot(self, pid):
        """GET /api/state with identity: the shared part plus this viewer's own overlay. Never sent:
        credentials, the log, another person's prefs or notifications, others' pending request text."""
        with self._lock:
            me = self._person(pid)
            st = self.state
            base = self._base()
            moderator = me["role"] in ("owner", "leader")
            owner = pid == HOST
            mode = "full" if moderator else st["session"]["settings"]["names"]
            snap = dict(base)
            own = self._own_view_cards(pid, {p["pid"] for p in base["people"]})
            if own:
                snap["cards"] = {**base["cards"], **own}
            if mode != "full":
                snap["people"] = [{**p, "name": initials(p["name"]) if mode == "initials" else "Someone"} for p in base["people"]]
                snap["cards"] = {q: [{**c, "votes": [v if v == pid else "" for v in c["votes"]]} for c in lst] for q, lst in snap["cards"].items()}
                snap["chat"] = [
                    {**m, "reactions": {e: [p if p == pid else "" for p in ps] for e, ps in m["reactions"].items()}} if "reactions" in m else m for m in base["chat"]
                ]
                snap["suggestions"] = {q: [{**s, "votes": [v if v == pid else "" for v in s["votes"]]} for s in lst] for q, lst in base["suggestions"].items()}
                snap["disagreements"] = {q: [{**d, "pid": d["pid"] if d["pid"] == pid else ""} for d in lst] for q, lst in base["disagreements"].items()}
            now = self.now()
            snap["serverTime"] = now
            here = self._present()
            snap["presence"] = [self._presence_entry(p, v, now) for p, v in self._presence.items() if p in here]
            notes = st["notifications"].get(pid, [])
            snap["me"] = {
                "pid": pid,
                "name": me["name"],
                "role": me["role"],
                "trusted": me["trusted"],
                "color": me["color"],
                "prefs": {k: copy.deepcopy(v["value"]) for k, v in st["prefs"].get(pid, {}).items()},
                "notifications": copy.deepcopy(notes[-NOTIFY_SHOWN:]),
                "unread": sum(1 for n in notes if not n["read"]),
                "votes": {q: by[pid] for q, by in st["votes"].items() if pid in by},
                "backs": {q: list(by[pid]) for q, by in st.get("backs", {}).items() if pid in by},
                "reactions": {q: {r: by[pid] for r, by in refs.items() if pid in by} for q, refs in st["reactions"].items()},
                "suggestionVotes": {q: by[pid] for q, by in st["suggestionVotes"].items() if pid in by},
                "aboutYou": copy.deepcopy(st["aboutYou"].get(pid)),
            }
            visible = [p for p in st["proposals"] if self._active(p["pid"]) and (moderator or p["pid"] == pid)]
            snap["proposals"] = copy.deepcopy(visible)
            snap["myRequests"] = copy.deepcopy([r for r in st["requests"] if r["pid"] == pid])
            snap["myMergeRequests"] = copy.deepcopy([m for m in st["mergeRequests"] if m["from"] == pid])
            if moderator:
                snap["guestKey"] = st["session"]["guestKey"]
                snap["behind"] = self._behind()
            if owner:
                snap["requests"] = copy.deepcopy([r for r in st["requests"] if r["runner"] == "host"])
                snap["results"] = copy.deepcopy(st["results"])
                snap["mergeRequests"] = copy.deepcopy([m for m in st["mergeRequests"] if m["status"]["kind"] == "pending"])
                snap["aboutYou"] = copy.deepcopy(st["aboutYou"])
                snap["removed"] = [
                    {k: v[k] for k in ("pid", "name", "role", "trusted", "color", "joinedAt")} for v in st["people"].values() if v["status"]["kind"] == "removed"
                ]
                waiting = sorted((v for v in st["people"].values() if v["status"]["kind"] == "waiting"), key=lambda v: v["status"]["at"])
                snap["joinRequests"] = [
                    {"pid": v["pid"], "name": v["name"], "at": v["status"]["at"], "n": n, **{k: v["status"][k] for k in ("device", "browser") if k in v["status"]}}
                    for n, v in enumerate(waiting, 1)
                ]
                snap["cleared"] = {
                    qid: [{"ref": self._cleared_ref(t), "pid": t["pid"], "clearedAt": t["clearedAt"], "hidden": "hidden" in t} for t in lst if self._active(t["pid"])]
                    for qid, lst in st.get("cleared", {}).items()
                }
                snap["cardDetails"] = {
                    qid: {card_ref(c): {k: copy.deepcopy(c[k]) for k in ("view", "deviceInfo") if k in c} for c in lst if c["kind"] == "person"}
                    for qid, lst in st["cards"].items()
                }
            return snap

    def _presence_entry(self, pid, v, now):
        """One wire.schema.json `presence` entry from the person's live tabs: q and typing from the latest
        beat (typing lasts TYPING_TTL after it), active while any live tab is, else away since the last
        one went away. Just joined with no beat yet is active."""
        live = [b for b in v["tabs"].values() if now - b["seen"] < OFFLINE_AFTER]
        if not live:
            return {"pid": pid, "q": "", "typing": False, "chatTyping": False, "state": "active"}
        latest = live[-1]
        fresh = now - latest["seen"] < TYPING_TTL
        entry = {"pid": pid, "q": latest["q"], "typing": latest["typing"] and fresh, "chatTyping": latest["chatTyping"] and fresh}
        sinces = [self._away_since(b, now) for b in live]
        return {**entry, "state": "active"} if None in sinces else {**entry, "state": "away", "since": max(sinces)}

    def _behind(self):
        """Moderators only: per active guest, how many open questions of the current round they have not touched."""
        st = self.state
        cur = self._current_round()
        if cur is None or cur["status"]["kind"] != "open":
            return {}
        qids = [q["id"] for q in st["questions"] if q["round"] == cur["n"] and q["id"] not in st["locks"]]
        out = {}
        for p in st["people"]:
            if p == HOST or not self._active(p):
                continue
            touched = {
                qid
                for qid in qids
                if p in st["votes"].get(qid, {})
                or p in st.get("backs", {}).get(qid, {})
                or any(c["kind"] == "person" and c["pid"] == p for c in st["cards"].get(qid, []))
            }
            out[p] = len(qids) - len(touched)
        return out


def _settings_patch(settings, patch):
    """Apply a partial Settings object in place after checking every key; returns settings."""
    if not isinstance(patch, dict):
        raise _bad("settings", "settings must be an object.")
    for k, v in patch.items():
        if k not in DEFAULT_SETTINGS and k not in OPTIONAL_SETTINGS:
            raise _bad(k, f"{k} is not a setting.")
        if k == "theme":
            if not isinstance(v, dict) or set(v) - set(THEME_VALUES) or any(v[t] not in THEME_VALUES[t] for t in v):
                raise _bad("theme", "theme takes mode (system, light, dark) and accent (teal, indigo, violet, amber).")
        elif k in SETTING_VALUES:
            if v not in SETTING_VALUES[k]:
                raise _bad(k, f"{k} must be one of {', '.join(SETTING_VALUES[k])}.")
        elif not isinstance(v, bool):
            raise _bad(k, f"{k} must be true or false.")
    for k, v in patch.items():
        if k == "theme":
            settings["theme"] = {**settings["theme"], **v}
        else:
            settings[k] = v
    return settings

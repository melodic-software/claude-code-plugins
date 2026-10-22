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

import base64
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
import struct
import sys
import threading
import time
import unicodedata
import urllib.parse
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
SCHEMA_DIR = HERE / "schema"
# This folder first; surface/ last, only for its schema.py, so a same-named module there
# (server.py, session_bridge.py, a test) never shadows one of ours.
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))
if str(HERE.parent / "surface") not in sys.path:
    sys.path.append(str(HERE.parent / "surface"))
schema = importlib.import_module("schema")
question_shape = importlib.import_module("question_shape")
detached = importlib.import_module("detached")

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
MAX_PENDING_REQUESTS = 10  # waiting, or running on the requester's own Claude
MAX_MY_RESULTS = 5  # judgment: results one person's own Claude posts on one question
MAX_MY_ROUND_RESULTS = 10  # judgment: results one person's own Claude posts across one round's questions
MAX_RESULTS = 500  # judgment: results across the session; at the cap a guest's own Claude's is refused, none dropped
MAX_DIGEST_RESULTS = 30  # judgment: results one digest lists; the rest are counted as "N more on the page"
MAX_MY_PROPOSALS = 10  # judgment: proposals one person has waiting (new) at once, as MAX_PENDING_REQUESTS
MAX_PROPOSALS = 200  # judgment: proposals across the session; at the cap a new one is refused, none dropped
MAX_DIGEST_PROPOSALS = 30  # judgment: new proposals one digest lists; the rest wait for a later digest
MAX_DIGEST_CHARS = 30000  # judgment: summary characters one digest lists, seven summaries at their longest
MAX_CLAUDE_PROPOSALS = 200  # judgment: Claude's merge and admit proposals across the session, as MAX_PROPOSALS
MAX_OPEN_UPLOADS = 10
MAX_RUN_IDS = 100
NOTIFY_CAP = 500
MAX_INBOX_READ = 100  # judgment: Inbox items one read marks; a person opens one at a time, "all" sends the unread ones
INBOX_MARKS = ("waiting", "running", "answered", "unshared", "shared", "declined", "failed", "open")  # state.schema.json inboxSeen
INBOX_STATUS = {"pending": "waiting", "running": "running", "declined": "declined", "failed": "failed"}  # a request's Inbox status; done is answered, shared or unshared
NOT_SHARED = "The owner did not share the result."  # a discarded result's request fails with this reason
MERGED_NOTE = "The owner joined your two identities: your earlier answers are yours again."  # the kept person's merge notification
NOTIFY_SHOWN = 100
# What may pop up the moment it happens (web/app.js POPUP_KINDS, GUEST_POPUPS): the owner's Inbox items and
# offered files, and a guest's answered request, mention and new round.
POPUP_KINDS = ("join", "run", "report", "share", "merge", "fail", "upload", "request", "mention", "round")
MAX_COMMENTS = 200  # judgment: Discussion comments kept on one question; at the cap a new one is refused, none dropped
MAX_ALL_COMMENTS = 2000  # judgment: comments across the session, as MAX_CHAT; at the cap a new one is refused
MAX_MY_COMMENTS = 30  # judgment: comments one person keeps on one question, as MAX_MY_NOTES; their hidden ones count too
MAX_DIGEST_COMMENTS = 50  # judgment: a question's newest comments one digest lists; the rest are counted
MAX_DIGEST_COMMENT = 500  # judgment: characters of one comment a digest lists
MAX_DIGEST_DISCUSSION_CHARS = 30000  # judgment: comment characters one digest lists, as MAX_DIGEST_CHARS for results
ASK_CLAUDE = re.compile(r"(?<![\w@])@claude(?![\w])", re.IGNORECASE)  # "@Claude" in a comment asks Claude about the question; in chat, about the session
TAKEN_DOWN = "Taken down by the host."  # what a chat quote of a taken-down answer of Claude's reads
GENERAL = "session"  # a request about the whole session has no qid: its results sit under this key, which no question id (QID) can be
COMMENT_ID = re.compile(r"D[1-9][0-9]{0,8}")
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
# Signing the owner in on another device: a code typed or scanned once. Its 8 characters from PAIR_ALPHABET (31, no
# 0/O, 1/I/L) hold about 39.6 bits; after PAIR_MISSES wrong tries an address is refused that code, while other
# addresses keep it, so a guesser gets PAIR_MISSES tries at 31**8 per address it holds.
PAIR_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
PAIR_LENGTH = 8
PAIR_SECONDS = 120.0  # judgment: long enough to pick up a phone and scan
PAIR_MISSES = 5  # judgment: a few typos; the host makes a new code after
MAX_DEVICES = 10  # judgment: the owner's other signed-in devices; one more needs one signed out first
MAX_CHAT = 2000  # the newest messages kept, so chat cannot grow state.json without bound
CHAT_WINDOW = 50  # judgment: the newest messages a snapshot carries; GET /api/chat pages through the rest
CHAT_PAGE_MAX = 100  # judgment: the most messages one GET /api/chat returns
MAX_ANNOTATIONS = 2000  # judgment: notes across all prototype questions; at the cap a new one is refused, none dropped
MAX_MY_NOTES = 30  # judgment: notes one person pins on one prototype question
MAX_SELECTOR = 1000  # judgment: characters in a note's element path; 32 levels of tag:nth-of-type(n) fit
MAX_SUGGESTIONS = 200  # judgment: suggestions kept per question, oldest dropped first
MAX_DECISIONS = 1000  # judgment: decision log entries kept, oldest dropped first; state.schema.json decisions maxItems
DISAGREE_CHURN_WINDOW = 60.0  # judgment: seconds within which a take-back and a raise again by the same person log nothing
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
CHUNK_SECONDS = 300.0  # judgment: one whole chunk arrives within this on a 0.25 MB/s phone link
CHUNK_INTERVAL = WRITE_INTERVAL  # chunks are writes: one a second per person; read at call time
MAX_ATTACHMENTS = 4  # uploads one answer, pick, message, request, suggestion, proposal or comment carries (the page's attach slot holds four)
MAX_FILE_NAME = 200  # characters of an upload's display name
MAX_THUMB = 64000  # characters of an offered picture's data: URL preview, which only the owner sees
PERSON_THUMB_MAX = 4 * MAX_THUMB  # judgment: preview characters one person's files keep in state.json
SESSION_THUMB_MAX = 1_000_000  # judgment: preview characters state.json and the owner's snapshot carry in all
REPORT_IMAGE_MAX = 512 * 1024  # bytes of a report's screenshot, which the page re-encodes to 1600 px at most
SHOWN_IMAGE_MAX = REPORT_IMAGE_MAX  # bytes of a received picture GET /api/upload/image reads back, what the page makes of a picked or pasted one; a larger one shows as a file
MAX_REPORT_IMAGES = 4  # judgment (the owner, 2026-10-21): screenshots one report takes when it is sent; an addition takes one
REPORT_MAX = BODY_MAX + -(-REPORT_IMAGE_MAX // 3) * 4 + 32  # an addition's body: one picture as a data: URL, plus its text
REPORT_SEND_MAX = BODY_MAX + MAX_REPORT_IMAGES * (-(-REPORT_IMAGE_MAX // 3) * 4 + 32)  # a report's body: up to MAX_REPORT_IMAGES of them
REPORT_SECONDS = 60.0  # judgment: a report's whole body, REPORT_SEND_MAX (about 2.8 MB), arrives within this on a 0.25 MB/s phone link (about 11 s)
REPORT_INTERVAL = 10.0  # judgment: seconds between one person's reports
MAX_OPEN_REPORTS = 5  # judgment: reports one person has waiting for the owner
MAX_REPORTS = 500  # judgment: reports across the session; at the cap a new one is refused, none dropped
MAX_REPORT_ERRORS = 5  # the page's latest client errors a report carries
MAX_REPORT_ERROR = 300  # characters of each
MAX_REPORT_ADDS = 10  # judgment: lines or screenshots a reporter adds to one report while it is open
REPORTS_DIR = "reports"  # in the private data folder: a report's picture, read only by the owner and the upload reader
ZIP_UNPACKED_MAX = 1024 * 1024 * 1024  # judgment: bytes an archive kind may unpack to in all
ZIP_RATIO_MAX = 100  # unpacked to packed, per entry past ZIP_RATIO_GRACE (Apache POI ZipSecureFile's default)
ZIP_RATIO_GRACE = 1024 * 1024
ZIP_ENTRIES_MAX = 10_000  # judgment: entries an archive kind's central directory may list
ZIP_DIRECTORY_MAX = 4 * 1024 * 1024  # judgment: bytes its central directory may take

COLORS = tuple(f"c{i}" for i in range(1, 11))
ROLES = ("owner", "leader", "guest")
PURPOSES = ("decide", "gather", "poll")
FORMATS = ("text", "choice", "multi", "scale", "rank", "confirm", "prototype")
# Options Claude writes per format (amendment "Reactions and formats"); the server adds Something else, and
# None of these on a multi question whose format sets `none: true`.
OPTION_COUNTS = {"choice": (2, 4), "multi": (2, 8), "rank": (3, 6)}
OTHER_OPTION = {"id": "other", "label": "Something else…", "other": True}
OTHER = OTHER_OPTION["id"]
NONE_OPTION = {"id": "none", "label": "None of these", "none": True}
NONE = NONE_OPTION["id"]
NONE_LABELS = ("none of these", "none of the above", "none")  # judgment: labels that mean the server's option
MENTION = re.compile(r"<@([A-Za-z0-9_-]{1,32})>")  # how state.json stores a mention: the person's pid
VIEWS = ("focus", "compare", "tree", "host", "prototype")
DEVICES = ("phone", "tablet", "computer")
BROWSERS = ("chrome", "safari", "firefox", "edge", "samsung", "in-app", "other")
REACTIONS = ("thumbs", "down", "heart", "idea")
OPPOSITE = {"thumbs": "down", "down": "thumbs"}  # one person never holds both on one answer
ENDORSING = {"thumbs", "heart"}  # the reactions the digest's endorsedBy counts; 👎 and 💡 take part without endorsing
REQUEST_KINDS = ("ask", "research", "explore", "design", "prototype")
USED_TYPES = ("skill", "workflow", "mcp", "cli")
TECH_COMFORT = ("low", "ok", "high")
NOTIFY_KINDS = ("mention", "reply", "request", "proposal", "round", "merge", "role", "queue", "ready", "votes", "reaction", "report", "discussion")
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
SEQ_KEYS = ("P", "S", "R", "X", "M", "G", "U", "N", "A")  # F, a report's, joined later: a file from before has none
REPORT_STATUS = ("open", "seen", "resolved")
SLUG = re.compile(r"[a-z0-9][a-z0-9-]{0,31}")  # a report's tab and build id

QID = re.compile(r"Q[1-9][0-9]{0,5}")
ASSET = re.compile(r"[0-9a-f]{16}\.(png|jpg|webp|svg|html)")
IMAGE_ASSET = re.compile(r"[0-9a-f]{16}\.(png|jpg|webp|svg)")  # an image asset's file name
SVG_ASSET = re.compile(r"[0-9a-f]{16}\.svg")
HTML_ASSET = re.compile(r"[0-9a-f]{16}\.html")  # a prototype variant's snapshot
# Live prototypes (`lives`): an entry's id; a live link's path on the prototype's own origin, RFC 3986 path-absolute
# (so never "//", which would name another host) with an optional query, in URL characters only: no "#" (a fragment,
# where the page's #me=, #join= and #owner= identities ride), no backslash, space or control character (the WHATWG URL
# parser reads a backslash as "/" and drops tab and newline, so "/<backslash>x" or "/<tab>/x" would become "//x"); the https origin a
# started entry is opened at, with no user, path, query or fragment; and the build folder an entry serves, relative to
# the data folder, under staging/ (never the data folder itself, which holds the session's secrets and guests' files).
LIVE_ID = re.compile(r"L[1-9][0-9]{0,5}")
LIVE_PATH = re.compile(r"/(?!/)(?:[A-Za-z0-9._~!$&'()*+,;=:@/?-]|%[0-9A-Fa-f]{2})*")
LIVE_URL = re.compile(r"https://[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?(?:\.[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?)+(?::[0-9]{1,5})?")
LIVE_FOLDER = re.compile(r"staging/[^/.][^/]*(?:/[^/.][^/]*)*")
MAX_LIVE_PATH = 500
MAX_LIVE_URL = 300
MAX_LIVES = 20  # judgment: live entries not ended at once; each is a server and a tunnel on the owner's machine
PORTS_FILE = ".shared-ports.json"  # server.py writes the session's own guest and control ports here
VARIANT = re.compile(r"v-[1-9][0-9]?")
# A note's element path (Annotation.anchor.selector), written by the prototype page's pin helper: "img" on an
# image variant, else tag names from the variant's root down, each with its place among same-tag siblings,
# joined by " > ". Data only: nothing evaluates it as script; inside the sandboxed variant the helper matches
# it with querySelector.
_SEL_STEP = r"[a-z][a-z0-9]{0,15}(?:-[a-z0-9]{1,15}){0,3}(?::nth-of-type\([1-9][0-9]{0,3}\))?"
SELECTOR = re.compile(rf"{_SEL_STEP}(?: > {_SEL_STEP}){{0,31}}")


# Uploads (Contracts, "Upload rules"). Every name on disk is the server's: a pending file is 32 hex digits under
# uploads/pending/, a received one uploads/accepted/<date>-<upload id>.<ext>. The person's file name is display
# text only. A state.json whose names stray from these patterns does not load (cross_field_errors).
REPORT_ID = re.compile(r"F[1-9][0-9]{0,8}")
UPLOAD_ID = re.compile(r"U[1-9][0-9]{0,8}-[0-9a-f]{8}")
TMP_NAME = re.compile(r"[0-9a-f]{32}")
STORED_NAME = re.compile(r"[0-9]{8}-U[1-9][0-9]{0,8}-[0-9a-f]{8}(?:\.[a-z0-9]{1,10})?")  # in uploads/accepted/
STORED_DIR = "uploads/accepted/"
# A done record's `stored`: one plain name in uploads/accepted/. The server writes STORED_NAME; the v1 design fixture
# (state-sample.json) holds an older shape that must still load, and no name here can leave the folder.
# A Windows device name (CON, NUL, COM1, ...) with any extension is refused: opening one reaches the device.
STORED_PATH = re.compile(r"uploads/accepted/(?!(?i:con|prn|aux|nul|com[0-9]|lpt[0-9])(?:\..*)?\Z)[A-Za-z0-9][A-Za-z0-9._-]{0,127}")
FILE_EXT = re.compile(r"[a-z0-9]{1,10}")
SHA256_HEX = re.compile(r"[0-9a-f]{64}")
THUMB = re.compile(r"data:image/(jpeg|png|webp);base64,([A-Za-z0-9+/]+={0,2})")
UPLOAD_LIVE = ("offered", "accepted", "uploading")
UPLOAD_ACCEPTED = ("accepted", "uploading", "done")  # the owner said yes: others may see it on an answer
UPLOAD_HELD = (*UPLOAD_LIVE, "done")  # counts against the caps


def _element(selector):
    """A note's element path for Claude's digest; a free-form selector an earlier build took is None."""
    return selector if len(selector) <= MAX_SELECTOR and SELECTOR.fullmatch(selector) else None


URL = re.compile(r"https?://\S+", re.IGNORECASE)  # a link
REPO = re.compile(r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/(?!\.\.?$)[A-Za-z0-9._-]{1,100}")  # a GitHub owner/name, never . or ..; also in state.schema.json and web/app.js
COMMIT = re.compile(r"[0-9a-f]{40}")  # a full commit SHA, which page links pin


def tokenize(text, names):
    """text with every "@Name" of `names` ((name, pid) pairs) as <@pid>, longest name first, so "@Sam 2" is not
    also "@Sam". A name stands alone: no letter or digit before its @, none (nor _) after it. Tokens stay as they
    are. A name two people share (casefolded) names nobody and stays text."""
    if "@" not in text or not names:
        return text
    holders = collections.defaultdict(set)
    for name, pid in names:
        holders[name.casefold()].add(pid)
    by = {n: next(iter(pids)) for n, pids in holders.items() if len(pids) == 1}
    if not by:
        return text
    alt = "|".join(re.escape(n) for n in sorted(by, key=len, reverse=True))
    pattern = re.compile(rf"(?<![^\W_])@({alt})(?!\w)", re.IGNORECASE)
    parts = MENTION.split(text)  # text, pid, text, pid, ...: only the text between tokens is matched
    for i in range(0, len(parts), 2):
        parts[i] = pattern.sub(lambda m: f"<@{by[m.group(1).casefold()]}>" if m.group(1).casefold() in by else m.group(0), parts[i])
    return "".join(p if i % 2 == 0 else f"<@{p}>" for i, p in enumerate(parts))


def mention_texts(doc):
    """(holder, key) of every text a person wrote that can hold a mention, as state.json keeps it."""
    out = []
    people_cards = [c for lst in doc["cards"].values() for c in lst if c.get("kind") == "person"]
    for c in [*people_cards, *(t for lst in doc.get("cleared", {}).values() for t in lst)]:
        out += [(c, "text"), *((v, "text") for v in c.get("history", []) if isinstance(v, dict))]
    out += [(lk["source"], "text") for lk in doc["locks"].values() if "text" in (lk.get("source") or {})]
    for s in (s for lst in doc["suggestions"].values() for s in lst):
        out += [(s, "text"), (s, "note")]
    out += [(q, "text") for q in doc["questions"] if (q.get("origin") or {}).get("kind") == "host"]
    out += [(r, "text") for key in ("proposals", "chat", "annotations", "requests") for r in doc[key]]
    out += [(c, "text") for lst in doc["discussions"].values() for c in lst]
    out += [(m["replyTo"], "excerpt") for m in doc["chat"] if isinstance(m.get("replyTo"), dict)]
    out += [(n, "body") for lst in doc["notifications"].values() for n in lst if n.get("kind") in ("mention", "reply")]
    return [(h, k) for h, k in out if isinstance(h, dict) and isinstance(h.get(k), str)]

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
OPTIONAL_SETTINGS = {"approveJoins": False, "reviewAnswers": True, "guestPopups": None, "prototypeTiers": None}
# guestPopups: the pop-ups a guest starts with (round 11), set by the owner; a guest's own `popups` pref wins. Absent,
# all of GUEST_POPUPS are on.
GUEST_POPUPS = ("request", "mention", "round")
# prototypeTiers: the prototype views the session offers guests. Absent, screenshots and HTML snapshots are on and live
# prototypes are off. A view switched off stays in the question; only guests' state and the html asset route drop it.
PROTOTYPE_TIERS = ("screenshot", "snapshot", "live")
DEFAULT_PROTOTYPE_TIERS = ("screenshot", "snapshot")
LAST_SCHEMA_VERSION = 7  # the last versioned build's file; an older one needs that build's migrations first
# reviewAnswers: every answer waits for the owner's Share. A new session writes it off; a state file from before it lacks
# it and so keeps that review-first behavior.
SETTING_VALUES = {
    "names": ("full", "initials", "someone"),
    "claudeTake": ("answerFirst", "always"),
}
# palette is optional: absent is "default", so a theme written before palettes loads and is written back as it was.
THEME_VALUES = {
    "mode": ("system", "light", "dark"),
    "accent": ("teal", "indigo", "violet", "amber"),
    "palette": ("default", "midnight", "slate", "paper", "contrast"),
}


def _is_int(v):
    return isinstance(v, int) and not isinstance(v, bool)


PREFS = {
    "claudeTake": lambda v: v in ("answerFirst", "always"),
    "sort": lambda v: v in ("new", "votes", "unanswered"),
    "filter": lambda v: v in ("all", "open", "locked", "review", "mine", "research", "proto"),
    "round": lambda v: isinstance(v, str) and PREF_ROUND.fullmatch(v) is not None,
    "expandedRounds": lambda v: isinstance(v, list) and len(v) <= 100 and all(_is_int(n) and 1 <= n <= 9999 for n in v),
    "theme": lambda v: v in THEME_VALUES["mode"],
    "accent": lambda v: v in THEME_VALUES["accent"],
    "palette": lambda v: v in THEME_VALUES["palette"],
    "follow": lambda v: isinstance(v, bool),
    "mute": lambda v: isinstance(v, list) and len(v) <= len(NOTIFY_KINDS) and all(k in NOTIFY_KINDS for k in v),
    "tour": lambda v: v in ("done", "skipped"),
    "toolbar": lambda v: v in ("simple", "full"),
    "autoAdvance": lambda v: isinstance(v, bool),
    "readAloud": lambda v: isinstance(v, bool),
    "dictate": lambda v: isinstance(v, bool),
    "popups": lambda v: isinstance(v, list) and all(isinstance(k, str) and k in POPUP_KINDS for k in v) and all(v.count(k) == 1 for k in v),
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


def _pair(previous):
    return previous["qid"], previous["variant"]


def _previous(previous, earlier, taken, field):
    """A new prototype version's `previous`: a variant of an earlier prototype question (one of `earlier`) that no
    other variant revises yet (`taken`, to which it is added), so one prototype's versions stay a single line."""
    qid, vid = _pair(previous)
    q = next((x for x in earlier if x["id"] == qid and x["format"]["kind"] == "prototype"), None)
    if q is None:
        raise _bad(f"{field}.qid", f"{qid[:40]} is not an earlier prototype question.")
    if vid not in {v["id"] for v in q["format"]["variants"]}:
        raise _bad(f"{field}.variant", f"{qid} has no variant {vid[:40]}.")
    if (qid, vid) in taken:
        raise _bad(field, f"{qid} {vid} already has a next version.")
    taken.add((qid, vid))
    return {"qid": qid, "variant": vid}


def cross_field_errors(doc):
    """The session rules the schema cannot express, each broken one as a sentence: dependsOn names
    only earlier questions, a prototype variant's previous names a variant of an earlier prototype question that no
    other variant also names, no two review flags share because and why, a round holds at most 8, a
    question holds at most one Something else option, the one with id `other` and `other: true`, no
    session secret names the owner (only the owner link does), only a poll holds a closed-poll lock, no person holds a
    reaction twice or both thumbs and down on one answer, a comment's id and a report's id and picture are names the server makes, and every link and asset name is one a write route takes
    (the schema's url and assetId patterns, which schema.py does not check)."""
    errors, seen, per_round = [], set(), {}
    if HOST in doc["credentials"]["secrets"].values():
        errors.append("A session secret names the owner; only the owner link may.")
    if any(m["status"]["kind"] == "pending" and HOST in (m["from"], m["to"]) for m in doc["mergeRequests"]):
        errors.append("A pending merge request names the owner; the owner cannot be merged.")
    if any(p["status"]["kind"] == "pending" and HOST in (p.get("from"), p.get("to"), p.get("pid")) for p in doc.get("claudeProposals", [])):
        errors.append("An open proposal of Claude's names the owner; the owner is never merged or admitted.")
    for p in doc.get("claudeProposals", []):
        named = ("from", "to") if p["kind"] == "merge" else ("pid",)
        if {k for k in ("from", "to", "pid") if k in p} != set(named) or any(p[k] not in p["names"] for k in named):
            errors.append(f"Proposal {p['id']} ({p['kind']}) must name {' and '.join(named)}, each in names, and no one else.")
    errors += [f"{where} is not a link or asset name a write route takes." for where in _bad_links_and_assets(doc)]
    earlier, taken = [], set()
    for q in doc["questions"]:
        for v in q["format"].get("variants", []):
            if "previous" in v:
                try:
                    _previous(v["previous"], earlier, taken, "previous")
                except DomainError as e:
                    errors.append(f"{q['id']} {v['id']} previous: {e.message}")
        earlier.append(q)
        later = [d for d in q["dependsOn"] if d not in seen]
        if later:
            errors.append(f"{q['id']} depends on {', '.join(later)}, not an earlier question.")
        flags = [(f["because"], json.dumps(f["why"], sort_keys=True)) for f in q["needsReview"]]
        if len(set(flags)) != len(flags):
            errors.append(f"{q['id']} holds two review flags with the same because and why.")
        others = [o for o in q["format"].get("options", []) if o.get("other") or o["id"] == OTHER]
        if len(others) > 1 or any(not (o.get("other") and o["id"] == OTHER) for o in others):
            errors.append(f"{q['id']} holds more than one Something else option, or one without both its id and its flag.")
        nones = [o for o in q["format"].get("options", []) if o.get("none") or o["id"] == NONE]
        if nones and (len(nones) > 1 or q["format"]["kind"] != "multi" or any(not (o.get("none") and o["id"] == NONE) for o in nones)):
            errors.append(f"{q['id']} holds a None of these option off a multi question, more than one, or one without both its id and its flag.")
        lock = doc["locks"].get(q["id"])
        if lock and lock["source"]["kind"] == "poll" and q["purpose"] != "poll":
            errors.append(f"{q['id']} holds a closed-poll lock but is not a poll.")
        seen.add(q["id"])
        per_round[q["round"]] = per_round.get(q["round"], 0) + 1
    errors += [f"Round {n} holds {k} questions; the most is {MAX_ROUND}." for n, k in sorted(per_round.items()) if k > MAX_ROUND]
    held = [(qid, rs) for qid, refs in doc["reactions"].items() for by in refs.values() for rs in by.values()]
    errors += [f"A person holds one reaction twice, or both thumbs and down, on an answer to {qid}." for qid, rs in held if len(set(rs)) < len(rs) or {"thumbs", "down"} <= set(rs)]
    errors += _upload_errors(doc)
    errors += _live_errors(doc)
    errors += [f"A Discussion comment on {qid[:40]} has an id the server never makes." for qid, lst in doc["discussions"].items() for c in lst if not COMMENT_ID.fullmatch(c["id"])]
    errors += [f"A result under {key[:40]} names another place." for key, lst in doc["results"].items() for r in lst if r.get("qid", GENERAL) != key]
    errors += [f"Report {fid[:40]} holds an id or picture name the server never makes." for fid, r in doc.get("reports", {}).items()
               if not REPORT_ID.fullmatch(fid) or not (r.get("image") is None or re.fullmatch(rf"{REPORTS_DIR}/{fid}\.(png|jpg|webp)", r["image"]))
               or ("moreImages" in r and ("image" not in r or not 0 < len(r["moreImages"]) < MAX_REPORT_IMAGES
                                         or any(not re.fullmatch(rf"{REPORTS_DIR}/{fid}-p{n}\.(png|jpg|webp)", m) for n, m in enumerate(r["moreImages"], 2))))
               or len(r.get("adds", [])) > MAX_REPORT_ADDS
               or any(not (a.get("image") is None or re.fullmatch(rf"{REPORTS_DIR}/{fid}-{n}\.(png|jpg|webp)", a["image"])) for n, a in enumerate(r.get("adds", []), 1))]
    return errors


def _upload_errors(doc):
    """No two upload records share an id, each id, extension and received file's name is one the server makes, and an
    answer carries only its author's uploads the owner accepted. A pending name that is not the server's (TMP_NAME)
    loads, but no file is ever opened or deleted by it."""
    errors, by_id = [], {}
    for u in doc["uploads"]:
        if u["id"] in by_id:
            errors.append(f"Two uploads share the id {u['id'][:40]}.")
        by_id[u["id"]] = u
        if not (UPLOAD_ID.fullmatch(u["id"]) and (u["ext"] == "" or FILE_EXT.fullmatch(u["ext"]))
                and (u["status"]["kind"] != "done" or STORED_PATH.fullmatch(u["status"]["stored"]))):
            errors.append(f"Upload {u['id'][:40]} holds an id, extension or file name the server never makes.")
    for where, rec in _attaching(doc):
        atts = rec.get("attachments", [])
        if len(atts) > MAX_ATTACHMENTS:
            errors.append(f"{where} carries more than {MAX_ATTACHMENTS} files.")
        errors += [f"{where} carries {uid[:40]} twice." for uid in sorted({x for x in atts if atts.count(x) > 1})]
        for uid in atts:
            u = by_id.get(uid)
            if u is None or u["pid"] != rec.get("pid") or u["status"]["kind"] not in UPLOAD_ACCEPTED:
                errors.append(f"{where} carries {uid[:40]}, not an accepted upload of its author.")
    return errors


def _live_errors(doc):
    """Live entries hold ids, folders and urls the server makes, each id once; a variant's live link names an entry and
    a path a write takes."""
    errors, ids = [], set()
    for e in doc.get("lives", []):
        if e["id"] in ids or not LIVE_ID.fullmatch(e["id"]):
            errors.append(f"Live prototype {e['id'][:40]} has an id the server never makes, or one another entry has.")
        ids.add(e["id"])
        if e["target"]["kind"] == "folder" and not (len(e["target"]["folder"]) <= 1000 and LIVE_FOLDER.fullmatch(e["target"]["folder"])):
            errors.append(f"Live prototype {e['id'][:40]} serves a folder outside staging/.")
        url = e["status"].get("url")
        if url is not None and not (len(url) <= MAX_LIVE_URL and LIVE_URL.fullmatch(url)):
            errors.append(f"Live prototype {e['id'][:40]} runs at an address that is not an https origin.")
        if e["status"]["kind"] in ("starting", "running") and (doc["session"]["phase"]["kind"] == "ended" or "live" not in prototype_tiers(doc["session"]["settings"])):
            errors.append(f"Live prototype {e['id'][:40]} runs while live prototypes are off or the session has ended.")
        if e["target"]["kind"] == "port" and "approvedAt" in e["status"] and not e["status"].get("attested"):
            errors.append(f"Live prototype {e['id'][:40]} on a port was approved without the owner's attestation.")
    for q in doc["questions"]:
        for v in q["format"].get("variants", []):
            link = v.get("live")
            if link and (link["id"] not in ids or _live_path_error(link["path"])):
                errors.append(f"questions[{q['id']}].format.variants.live names no live prototype, or a path a write refuses.")
    return errors


def _live_path_error(path):
    """Why `path` cannot be a live link's path (LIVE_PATH), or None."""
    if not isinstance(path, str) or len(path) > MAX_LIVE_PATH or not LIVE_PATH.fullmatch(path) or "%23" in path:
        return (f"A live link's path starts with one / (never //), is at most {MAX_LIVE_PATH} characters of URL path and query "
                "characters, and holds no fragment (# or %23), scheme, space or backslash.")
    part, _, query = path.partition("?")
    # "." and ".." segments (escaped too) collapse when a browser resolves the path, so "/.//x" would become "//x".
    if "//" in part or any(urllib.parse.unquote(seg) in (".", "..") for seg in part.split("/")):
        return "A live link's path holds no empty, . or .. segment."
    if any(k.lower() in ("me", "join", "owner") for k, _ in urllib.parse.parse_qsl(query, keep_blank_values=True)):
        return "A live link's query holds no me, join or owner key: those name the session's identities."
    return None


def _live_folder(path, root):
    """A build folder for a live entry: an existing directory under `root`/staging/ (not staging/ itself), with no
    hidden part, named by an absolute path; its path relative to `root`, as written in the entry."""
    if not isinstance(path, str) or not os.path.isabs(path):
        raise _bad("folder", "folder must be an absolute path to a build folder under the data folder's staging/.")
    try:
        real = Path(path).resolve(strict=True)
        base = Path(root).resolve(strict=True)
    except (OSError, RuntimeError) as exc:
        raise _bad("folder", f"No folder at {path}.") from exc
    staging = base / STAGING
    if not real.is_relative_to(staging) or real == staging:
        raise _bad("folder", f"add-live serves a build folder only from inside {staging}.")
    rel = real.relative_to(base)
    if not real.is_dir() or any(part.startswith(".") for part in rel.parts) or not LIVE_FOLDER.fullmatch(rel.as_posix()):
        raise _bad("folder", "folder must name a directory with no hidden folder or name.")
    return rel.as_posix()


def _answers(cards):
    """People's answers in a qid -> cards map: the only cards that carry files."""
    return [c for lst in cards.values() for c in lst if c.get("kind") == "person"]


def _flat(by_qid):
    """The records of a qid -> list map, in one list."""
    return [x for lst in by_qid.values() for x in lst]


def _pics_by_q(uploads):
    """qid -> the ids of these uploads offered on it, oldest first."""
    out = {}
    for u in sorted(uploads, key=lambda u: u["at"]):
        out.setdefault(u["qid"], []).append(u["id"])
    return out


def _shows_as_image(u):
    """A received upload of a picture kind, small enough to read back; its bytes passed its kind's check on arrival."""
    return u["status"]["kind"] == "done" and u["ext"] in IMAGE_KINDS and u["size"] <= SHOWN_IMAGE_MAX


def _approved(u):
    """A received picture others may see: the owner's own at once, a guest's once the owner approved it (`shown`)."""
    return u["pid"] == HOST or u.get("shown") is True


def _avatars(uploads):
    """pid -> that person's profile picture: their newest received upload offered as one (`avatar`)."""
    return {u["pid"]: u for u in uploads if u.get("avatar") and _shows_as_image(u)}


def _attaching(doc):
    """(where, record) for every record that may carry `attachments`: answers, chat messages, requests, suggestions,
    proposals and Discussion comments."""
    for qid, lst in doc["cards"].items():
        yield from ((f"An answer on {qid}", c) for c in lst)
    yield from (("A chat message", m) for m in doc["chat"])
    yield from (("A request", r) for r in doc["requests"])
    yield from (("A proposal", p) for p in doc["proposals"])
    for qid, lst in doc["suggestions"].items():
        yield from ((f"A suggestion on {qid}", x) for x in lst)
    for qid, lst in doc.get("discussions", {}).items():
        yield from ((f"A comment on {qid}", x) for x in lst)


def _bad_links_and_assets(doc):
    """Where the document holds a link that is not http(s) or an asset name write routes refuse."""
    bad = []
    share = doc["session"]["share"]["url"]
    if share and not URL.fullmatch(share):
        bad.append("session.share.url")
    sess = doc["session"]
    bad += [f"session.{k}" for k, pattern in (("repo", REPO), ("commit", COMMIT)) if k in sess and not pattern.fullmatch(sess[k])]
    if "commit" in sess and "repo" not in sess:
        bad.append("session.commit")
    for q in doc["questions"]:
        fmt, at = q["format"], f"questions[{q['id']}]"
        checks = [(IMAGE_ASSET, o["image"], f"{at}.format.options.image") for o in fmt.get("options", []) if "image" in o]
        for v in fmt.get("variants", []):
            checks += [(ASSET, v["asset"], f"{at}.format.variants.asset")] if "asset" in v else []
            checks += [(IMAGE_ASSET, x, f"{at}.format.variants.shots") for x in v.get("shots", [])]
            checks += [(HTML_ASSET, v["snapshot"], f"{at}.format.variants.snapshot")] if "snapshot" in v else []
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


def clip(text, n):
    """text cut to at most n characters, never inside a mention token: a token the cut would split goes whole."""
    if len(text) <= n:
        return text
    cut = next((m.start() for m in MENTION.finditer(text, max(0, n - 34), n + 34) if m.start() < n < m.end()), n)
    return text[:cut]


def _retoken(obj, old, new):
    """Every `old` mention token in the strings obj (a dict or list) holds becomes `new`, in place."""
    for k, v in list(obj.items() if isinstance(obj, dict) else enumerate(obj)):
        if isinstance(v, str):
            obj[k] = v.replace(old, new)
        elif isinstance(v, (dict, list)):
            _retoken(v, old, new)


def initials(name):
    return " ".join(w[0] for w in str(name or "?").split()[:2]).upper() or "?"


replace_into = detached.replace_into
write_private = detached.write_private


def _edited(card):
    """The digest's mark on an answer the owner edited: it carries the current text."""
    return {"edited": True} if "edited" in card else {}


def _files(card):
    """The digest's list of the uploads an answer carries, so one with no text still says what it holds."""
    return {"attachments": list(card["attachments"])} if "attachments" in card else {}


def card_ref(card):
    if card["kind"] == "person":
        return f"p:{card['pid']}" + (f":{card['device']}" if card.get("device") else "")
    if card["kind"] == "claude":
        return f"c:{card['key']}"
    return f"o:{card['option']}"


def _moderated(card):
    """Whether the owner hid or edited this person card (or a cleared one): only then are its versions kept."""
    return any(k in card for k in ("hidden", "edited", "history"))


def _on(x):
    """Where a request or result is, for a notice: "on question Q2", or "about the session" with no qid."""
    return f"on question {x['qid']}" if "qid" in x else "about the session"


def _where(x):
    """A request's or result's place for the Inbox and the digest: its qid, or `scope: session`."""
    return {"qid": x["qid"]} if "qid" in x else {"scope": GENERAL}


def _answer_where(qid):
    return f"in an answer on question {qid}"


def ref_author(ref):
    """The pid that wrote a person card, from its ref, or None for Claude and option cards."""
    return ref.split(":")[1] if ref.startswith("p:") else None


# -- input parsing: every route and op body goes through these before any state changes ------


def _question_view(q):
    """A question as the snapshot sends it: the stored one, plus the question_shape flags the page reads
    (`withheld`, `alternatives[i].restates`) on a copy, so state.json never holds them."""
    rec = q.get("recommendation")
    held = question_shape.withheld(rec)
    alts = [{**a, "restates": True} if question_shape.restates(a["text"], rec) else a for a in q["alternatives"]]
    if not held and all(x is a for x, a in zip(alts, q["alternatives"])):
        return q
    return {**q, "alternatives": alts, **({"withheld": True} if held else {})}


def _bad(field, message):
    return DomainError(400, "bad-field", message, field=field)


def _none_label(label):
    """Whether an option label means "none applies": casefolded, ellipsis, full stops and spaces trimmed."""
    return isinstance(label, str) and " ".join(label.casefold().strip(" .…").split()) in NONE_LABELS


def _body(body):
    if not isinstance(body, dict):
        raise _bad("body", "The request body must be a JSON object.")
    return body


def _person_name(body, *, empty_ok=False):
    """A person's name; "Claude" (any case) is refused, since "@Claude" asks Claude and must never name a person."""
    name = _text(body, "name", limit=MAX_NAME, empty_ok=empty_ok)
    if _looks_like_claude(name):
        raise DomainError(400, "reserved-name", "Claude is the AI's name in this session; pick another name.", field="name")
    return name


# What every text field drops: controls but tab and newline, every format character (Cf: the bidi controls of Trojan
# Source, zero-width spaces, invisible operators, the soft hyphen, tags) but ZWJ and ZWNJ, surrogates, private use,
# characters that render blank (_BLANK), and VS17-VS256. Tag characters stay only in the three RGI subdivision flags
# (_RGI_FLAGS); any other run of them can spell hidden words for Claude. ZWJ, ZWNJ and VS1-VS16 stay one at a time
# (emoji sequences and some scripts need them): a selector after a selector or a joiner, or a joiner after a joiner,
# is dropped, so no run of them hides bytes after a visible character. Unassigned (Cn) stays: the interpreter's
# Unicode tables trail new emoji, which read as unassigned until they catch up.
_RGI_FLAGS = re.compile(
    "(" + "|".join("\U0001f3f4" + "".join(chr(0xE0000 + ord(c)) for c in code) + "\U000e007f" for code in ("gbeng", "gbsct", "gbwls")) + ")"
)
_JOINERS = "\U0000200c\U0000200d"
_BLANK = frozenset(chr(c) for c in (0x034F, 0x115F, 0x1160, 0x17B4, 0x17B5, *range(0x180B, 0x1810), 0x2800, 0x3164, 0xFFA0))  # nothing shows
_DROPPED_KINDS = ("Cc", "Cf", "Co", "Cs")


def _hidden(c):
    o = ord(c)
    return (
        unicodedata.category(c) in _DROPPED_KINDS
        or c in _BLANK
        or 0xE0000 <= o <= 0xE007F  # tags, the unassigned ones too
        or 0xE0100 <= o <= 0xE01EF  # VS17-VS256
        or o >= 0xF0000  # private use planes, their noncharacters too
    )


def _visible(v):
    """v with line breaks as \\n and every hidden character dropped (see above)."""
    out, last = [], ""
    for i, part in enumerate(_RGI_FLAGS.split(v.replace("\r\n", "\n").replace("\r", "\n"))):
        if i % 2:  # one of the RGI subdivision flags, kept whole
            out.append(part)
            last = ""
            continue
        for c in part:
            if c in "\t\n":
                kind = ""
            elif c in _JOINERS:
                kind = "j"
            elif "\U0000fe00" <= c <= "\U0000fe0f":
                kind = "vs"
            elif _hidden(c):
                continue
            else:
                kind = ""
            if (kind == "vs" and last) or (kind == "j" and last == "j"):
                continue
            out.append(c)
            last = kind
    return "".join(out)


def _name_key(name):
    """What two names are compared by: the name less its joiners, selectors and blank marks (a text field keeps one of
    each after a visible character), then NFKC and casefold, so a fullwidth or compatibility form of a name is that
    name."""
    return _bare(name).casefold()


def _bare(name):
    """name less its joiners, VS1-VS16 and blank marks, in NFKC."""
    return unicodedata.normalize("NFKC", "".join(c for c in name if c not in _JOINERS and not "\U0000fe00" <= c <= "\U0000fe0f" and c not in _BLANK))


# UTS #39 confusables.txt (18.0.0): every single character whose prototype is one of the letters of "claude", either
# case. Only the reserved-name check reads this, so a name that looks like "Claude" in another script is refused.
_CLAUDE_LOOKALIKES = {
    "c": (
        "\u03f2\u03f9\u0421\u0441\u1004\u105a\u13df\u1c83\u1d04\u2102\u212d\u216d\u217d\u2ca4\u2ca5\ua4da"
        "\uabaf\uff23\uff43\U000102a2\U00010302\U00010415\U0001043d\U0001051b\U000118e9\U000118f2"
        "\U0001ccd8\U0001d134\U0001d402\U0001d41c\U0001d436\U0001d450\U0001d46a\U0001d484\U0001d49e"
        "\U0001d4b8\U0001d4d2\U0001d4ec\U0001d520\U0001d554\U0001d56e\U0001d588\U0001d5a2\U0001d5bc"
        "\U0001d5d6\U0001d5f0\U0001d60a\U0001d624\U0001d63e\U0001d658\U0001d672\U0001d68c\U0001f74c"
    ),
    "l": (
        "1I|\u0196\u01c0\u0399\u0406\u04c0\u04cf\u05c0\u05d5\u05df\u0627\u0661\u06f1\u07ca\u0964\u104a"
        "\u13de\u14aa\u16c1\u16d0\u2110\u2111\u2112\u2113\u2160\u216c\u217c\u21bf\u2223\u23fd\u2502\u2503"
        "\u2c92\u2cd0\u2d4a\u2d4f\ua4e1\ua4f2\ua56f\ua781\ua7ae\ua7fe\ua830\ua8ce\uaa5d\ufe31\ufe8d\ufe8e"
        "\uff11\uff29\uff2c\uff4c\uff5c\uffe8\U0001028a\U00010309\U00010320\U0001041b\U0001050e\U00010526"
        "\U00010926\U00010c3e\U00010ca5\U00010cfa\U00011047\U000110c0\U00011141\U000111c5\U000113d4"
        "\U0001144b\U000115c5\U00011641\U000118a3\U000118b2\U00011c41\U00011dda\U00011de1\U00016d63"
        "\U00016eaa\U00016f16\U00016f28\U0001ccde\U0001cce1\U0001ccf1\U0001d100\U0001d22a\U0001d377"
        "\U0001d408\U0001d40b\U0001d425\U0001d43c\U0001d43f\U0001d459\U0001d470\U0001d473\U0001d48d"
        "\U0001d4c1\U0001d4d8\U0001d4db\U0001d4f5\U0001d50f\U0001d529\U0001d540\U0001d543\U0001d55d"
        "\U0001d574\U0001d577\U0001d591\U0001d5a8\U0001d5ab\U0001d5c5\U0001d5dc\U0001d5df\U0001d5f9"
        "\U0001d610\U0001d613\U0001d62d\U0001d644\U0001d647\U0001d661\U0001d678\U0001d67b\U0001d695"
        "\U0001d6b0\U0001d6ea\U0001d724\U0001d75e\U0001d798\U0001d7cf\U0001d7d9\U0001d7e3\U0001d7ed"
        "\U0001d7f7\U0001e141\U0001e8c7\U0001ed01\U0001ee00\U0001ee80\U0001fbf1"
    ),
    "a": (
        "\u0251\u0391\u03b1\u0410\u0430\u13aa\u15c5\u237a\ua4ee\uab64\uff21\uff41\U000102a0\U00016f40"
        "\U0001ccd6\U0001d400\U0001d41a\U0001d434\U0001d44e\U0001d468\U0001d482\U0001d49c\U0001d4b6"
        "\U0001d4d0\U0001d4ea\U0001d504\U0001d51e\U0001d538\U0001d552\U0001d56c\U0001d586\U0001d5a0"
        "\U0001d5ba\U0001d5d4\U0001d5ee\U0001d608\U0001d622\U0001d63c\U0001d656\U0001d670\U0001d68a"
        "\U0001d6a8\U0001d6c2\U0001d6e2\U0001d6fc\U0001d71c\U0001d736\U0001d756\U0001d770\U0001d790"
        "\U0001d7aa\U0001df5a\U0001df6a"
    ),
    "u": (
        "\u028b\u03c5\u054d\u057d\u1200\u144c\u1d1c\u222a\u22c3\ua4f4\ua79f\uab4e\uab52\uff35\uff55"
        "\U000104ce\U000104f6\U000118b8\U000118d8\U00016f42\U0001ccea\U0001d414\U0001d42e\U0001d448"
        "\U0001d462\U0001d47c\U0001d496\U0001d4b0\U0001d4ca\U0001d4e4\U0001d4fe\U0001d518\U0001d532"
        "\U0001d54c\U0001d566\U0001d580\U0001d59a\U0001d5b4\U0001d5ce\U0001d5e8\U0001d602\U0001d61c"
        "\U0001d636\U0001d650\U0001d66a\U0001d684\U0001d69e\U0001d6d6\U0001d710\U0001d74a\U0001d784"
        "\U0001d7be"
    ),
    "d": (
        "\u0501\u13a0\u13e7\u146f\u15de\u15ea\u2145\u2146\u216e\u217e\ua4d2\ua4d3\uff24\uff44\U0001018b"
        "\U0001ccd9\U0001d403\U0001d41d\U0001d437\U0001d451\U0001d46b\U0001d485\U0001d49f\U0001d4b9"
        "\U0001d4d3\U0001d4ed\U0001d507\U0001d521\U0001d53b\U0001d555\U0001d56f\U0001d589\U0001d5a3"
        "\U0001d5bd\U0001d5d7\U0001d5f1\U0001d60b\U0001d625\U0001d63f\U0001d659\U0001d673\U0001d68d"
    ),
    "e": (
        "\u0395\u0415\u0435\u04bd\u13ac\u212e\u212f\u2130\u2147\u22ff\u2d39\ua4f0\ua5cb\uab32\uff25\uff45"
        "\U00010286\U000118a6\U000118ae\U0001ccda\U0001d404\U0001d41e\U0001d438\U0001d452\U0001d46c"
        "\U0001d486\U0001d4d4\U0001d4ee\U0001d508\U0001d522\U0001d53c\U0001d556\U0001d570\U0001d58a"
        "\U0001d5a4\U0001d5be\U0001d5d8\U0001d5f2\U0001d60c\U0001d626\U0001d640\U0001d65a\U0001d674"
        "\U0001d68e\U0001d6ac\U0001d6e6\U0001d720\U0001d75a\U0001d794\U0001df81"
    ),
}
_LOOKALIKE = {c: letter for letter, chars in _CLAUDE_LOOKALIKES.items() for c in chars}


def _looks_like_claude(name):
    """Whether name, keyed as _name_key and with each confusable letter read as its Latin prototype, is "claude"."""
    latin = lambda text: "".join(_LOOKALIKE.get(c, c) for c in text)  # noqa: E731
    return latin(latin(_bare(name)).casefold()) == "claude"


def _text(body, field, *, limit=MAX_TEXT, empty_ok=False, optional=False):
    """A trimmed string of 1..limit characters (0.. with empty_ok), hidden characters dropped first (_visible);
    refused when longer, never cut."""
    v = _body(body).get(field)
    if v is None:
        if optional:
            return None
        if empty_ok:
            return ""
        raise DomainError(400, "empty", f"{field} is empty.", field=field)
    if not isinstance(v, str):
        raise _bad(field, f"{field} must be a string.")
    v = _visible(v).strip()
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
        head = data[:2048].decode("utf-8", "replace").lstrip("\ufeff \t\r\n").lower()
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


def _starts(*magics):
    return lambda head: head.startswith(magics)


def _plain_text(head):
    """UTF-8 with no NUL byte; the chunk may end inside a character."""
    if b"\x00" in head:
        return False
    try:
        head.decode("utf-8")
    except UnicodeDecodeError as exc:
        return exc.reason == "unexpected end of data" and exc.start >= len(head) - 3
    return True


_ZIP, _OLE = _starts(b"PK\x03\x04"), _starts(b"\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1")
# The magic-byte allowlist: extension -> (the MIME type the server records, the check the first chunk must pass).
# Guests offer only these kinds (zip aside); the owner and trusted guests may offer any extension, and a kind
# outside this table is stored unchecked as application/octet-stream. Nothing here is ever served back.
UPLOAD_KINDS = {
    "png": ("image/png", _starts(b"\x89PNG\r\n\x1a\n")),
    "jpg": ("image/jpeg", _starts(b"\xff\xd8\xff")),
    "jpeg": ("image/jpeg", _starts(b"\xff\xd8\xff")),
    "gif": ("image/gif", _starts(b"GIF87a", b"GIF89a")),
    "webp": ("image/webp", lambda head: head[:4] == b"RIFF" and head[8:12] == b"WEBP"),
    "pdf": ("application/pdf", _starts(b"%PDF-")),
    "txt": ("text/plain", _plain_text),
    "md": ("text/markdown", _plain_text),
    "csv": ("text/csv", _plain_text),
    "tsv": ("text/tab-separated-values", _plain_text),
    "log": ("text/plain", _plain_text),
    "rtf": ("application/rtf", _starts(b"{\\rtf")),
    "doc": ("application/msword", _OLE),
    "xls": ("application/vnd.ms-excel", _OLE),
    "ppt": ("application/vnd.ms-powerpoint", _OLE),
    "docx": ("application/vnd.openxmlformats-officedocument.wordprocessingml.document", _ZIP),
    "xlsx": ("application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", _ZIP),
    "pptx": ("application/vnd.openxmlformats-officedocument.presentationml.presentation", _ZIP),
    "odt": ("application/vnd.oasis.opendocument.text", _ZIP),
    "ods": ("application/vnd.oasis.opendocument.spreadsheet", _ZIP),
    "odp": ("application/vnd.oasis.opendocument.presentation", _ZIP),
    "zip": ("application/zip", _ZIP),
}
GUEST_KINDS = frozenset(UPLOAD_KINDS) - {"zip"}
ARCHIVE_KINDS = {k for k, (_, check) in UPLOAD_KINDS.items() if check is _ZIP}
OOXML_KINDS, OPENDOC_KINDS = {"docx", "xlsx", "pptx"}, {"odt", "ods", "odp"}
_WINDOWS = os.name == "nt"
THUMB_KINDS = {"png", "jpg", "jpeg", "gif", "webp"}
IMAGE_KINDS = THUMB_KINDS  # a received upload of one of these, its bytes that kind, reads back as a picture: never SVG or HTML
AVATAR_KINDS = {"png", "jpg", "jpeg", "webp"}  # the owner's choice: a profile picture is a PNG, JPEG or WebP
AVATAR_MAX = 256 * 1024  # the owner's choice: bytes of a profile picture, which the page redraws small first


def _file_name(body):
    """An upload's display name: one line, its last path part, with control, format (bidi), private-use, surrogate
    and unassigned characters dropped; data, never a path."""
    raw = _text(body, "file", limit=MAX_FILE_NAME * 2)
    name = one_line("".join(c for c in re.split(r"[\\/]", raw)[-1] if unicodedata.category(c) not in ("Cc", "Cf", "Co", "Cs", "Cn")))
    if not name or name in (".", ".."):
        raise _bad("file", "file must name the file.")
    if len(name) > MAX_FILE_NAME:
        raise DomainError(400, "too-long", f"file allows at most {MAX_FILE_NAME} characters.", field="file", max=MAX_FILE_NAME)
    return name


def _thumb(v, ext):
    """An offered picture's preview: a data: URL of a PNG, JPEG or WebP whose bytes are that kind, or None."""
    if v is None or v == "":
        return None
    m = THUMB.fullmatch(v) if isinstance(v, str) and len(v) <= MAX_THUMB else None
    if m is None or ext not in THUMB_KINDS:
        raise _bad("thumb", "thumb must be a small PNG, JPEG or WebP data: URL, on a picture.")
    try:
        data = base64.b64decode(m.group(2), validate=True)
    except ValueError as exc:
        raise _bad("thumb", "thumb is not base64.") from exc
    kind = {"jpeg": "jpg"}.get(m.group(1), m.group(1))
    if not UPLOAD_KINDS[kind][1](data[:64]):
        raise _bad("thumb", f"thumb says {m.group(1)}, but its bytes are not.")
    return v


def _report_image(v, field="image"):
    """A report's screenshot: (bytes, extension) from a data: URL of a PNG, JPEG or WebP whose bytes are that kind,
    at most REPORT_IMAGE_MAX bytes; None for no picture."""
    if v is None or v == "":
        return None
    m = THUMB.fullmatch(v) if isinstance(v, str) else None
    if m is None:
        raise DomainError(415, "file-type", "A report's picture must be a PNG, JPEG or WebP screenshot.", field=field)
    try:
        data = base64.b64decode(m.group(2), validate=True)
    except ValueError as exc:
        raise _bad(field, f"{field} is not base64.") from exc
    if len(data) > REPORT_IMAGE_MAX:
        raise DomainError(413, "upload-too-large", "That picture is too large.", field=field, max=REPORT_IMAGE_MAX)
    kind = {"jpeg": "jpg"}.get(m.group(1), m.group(1))
    if not UPLOAD_KINDS[kind][1](data[:64]):
        raise DomainError(415, "file-type", f"The picture says {m.group(1)}, but its bytes are not.", field=field)
    return data, kind


def _report_images(body):
    """A new report's screenshots, in order: `images`, a list of at most MAX_REPORT_IMAGES data: URLs, or one `image`
    as before; never both."""
    if "images" not in body:
        one = _report_image(body.get("image"))
        return [one] if one else []
    if "image" in body:
        raise _bad("image", "Send image or images, not both.")
    v = body["images"]
    if not isinstance(v, list) or len(v) > MAX_REPORT_IMAGES:
        raise DomainError(400, "bad-field", f"images lists at most {MAX_REPORT_IMAGES} pictures.", field="images", max=MAX_REPORT_IMAGES)
    out = [_report_image(x, f"images[{i}]") for i, x in enumerate(v)]
    if None in out:
        raise _bad("images", "images lists only pictures.")
    return out


def _report_pics(r):
    """Where a report's own screenshots are saved, in order: `image`, then `moreImages` (a report from before them has
    only `image`)."""
    return ([r["image"]] if "image" in r else []) + r.get("moreImages", [])


def _dims(v, field, keys):
    """{w, h[, scale]}: positive numbers a page measured."""
    if not isinstance(v, dict) or set(v) != set(keys) or not all(isinstance(v[k], (int, float)) and not isinstance(v[k], bool) and 0 <= v[k] <= 100_000 for k in keys):
        raise _bad(field, f"{field} must be {{{', '.join(keys)}}}, each a number.")
    return {k: round(float(v[k]), 2) for k in keys}


REPORT_CTX = ("view", "tab", "qid", "round", "device", "browser", "viewport", "visualViewport", "build", "errors")


def _report_ctx(v):
    """What a report says about the page it came from: REPORT_CTX only (never an answer, chat, the address or a
    credential), each field checked."""
    if not isinstance(v, dict):
        raise _bad("ctx", "ctx must be an object.")
    extra = sorted(set(v) - set(REPORT_CTX))
    if extra:
        raise _bad("ctx", f"{extra[0][:40]} is not sent with a report.")
    out = {"view": _choice(v, "view", VIEWS), "device": _choice(v, "device", DEVICES), "browser": _choice(v, "browser", BROWSERS)}
    for k, pattern in (("tab", SLUG), ("build", SLUG), ("qid", QID)):
        if v.get(k) not in (None, ""):
            if not isinstance(v[k], str) or not pattern.fullmatch(v[k]):
                raise _bad(f"ctx.{k}", f"ctx.{k} is not one the page sends.")
            out[k] = v[k]
    if v.get("round") is not None:
        if not _is_int(v["round"]) or not 0 <= v["round"] <= 10_000:
            raise _bad("ctx.round", "ctx.round must be a round number.")
        out["round"] = v["round"]
    out["viewport"] = _dims(v.get("viewport"), "ctx.viewport", ("w", "h"))
    if v.get("visualViewport") is not None:
        out["visualViewport"] = _dims(v["visualViewport"], "ctx.visualViewport", ("w", "h", "scale"))
    errors = v.get("errors", [])
    if not isinstance(errors, list) or len(errors) > MAX_REPORT_ERRORS or not all(isinstance(e, str) and len(e) <= MAX_REPORT_ERROR for e in errors):
        raise _bad("ctx.errors", f"ctx.errors lists at most {MAX_REPORT_ERRORS} errors of {MAX_REPORT_ERROR} characters.")
    out["errors"] = [one_line(_visible(e)) for e in errors]
    return out


def _directory_small(path):
    """An archive's End of Central Directory record (and its Zip64 record, when the locator says one is there), read
    from the file's tail before zipfile builds anything: at most ZIP_ENTRIES_MAX entries in at most ZIP_DIRECTORY_MAX
    bytes. No record found is not small."""
    with open(path, "rb") as f:
        f.seek(0, os.SEEK_END)
        f.seek(max(0, f.tell() - 22 - 65535))  # the record plus the longest comment it may carry
        tail = f.read()
    at = tail.rfind(b"PK\x05\x06")
    if at < 0 or len(tail) - at < 22:
        return False
    _, _, _, _, count, size, _, _ = struct.unpack_from("<4s4H2LH", tail, at)
    if at >= 20 and tail[at - 20:at - 16] == b"PK\x06\x07":
        if at < 76 or tail[at - 76:at - 72] != b"PK\x06\x06":
            return False
        _, _, _, _, _, _, _, count64, size64, _ = struct.unpack_from("<4sQ2H2L4Q", tail, at - 76)
        count, size = max(count, count64), max(size, size64)
    return count <= ZIP_ENTRIES_MAX and size <= ZIP_DIRECTORY_MAX


def _archive_ok(path, ext):
    """An archive kind, read from its central directory: OOXML holds [Content_Types].xml; OpenDocument starts with a stored
    `mimetype` entry naming its kind; a zip may hold anything. No entry name is absolute or climbs with `..`, no entry
    is a symlink, the whole unpacks to at most ZIP_UNPACKED_MAX, and no entry past ZIP_RATIO_GRACE packs tighter than
    ZIP_RATIO_MAX to 1. The directory is sized from its end record (_directory_small) before zipfile reads it. Nothing
    is unpacked but OpenDocument's mimetype."""
    try:
        if not _directory_small(path):
            return False
        with zipfile.ZipFile(path) as z:
            infos = z.infolist()
            if any(re.match(r"[\\/]|[A-Za-z]:", i.filename) or ".." in re.split(r"[\\/]", i.filename)
                   or (i.external_attr >> 16) & 0o170000 == 0o120000 for i in infos):
                return False
            if sum(i.file_size for i in infos) > ZIP_UNPACKED_MAX:
                return False
            if any(i.file_size > ZIP_RATIO_GRACE and i.file_size > ZIP_RATIO_MAX * i.compress_size for i in infos):
                return False
            if ext in OOXML_KINDS:
                return "[Content_Types].xml" in z.namelist()
            if ext in OPENDOC_KINDS:
                first = infos[0] if infos else None
                return (first is not None and first.filename == "mimetype" and first.header_offset == 0 and first.compress_type == zipfile.ZIP_STORED
                        and first.file_size <= 100 and z.read(first) == UPLOAD_KINDS[ext][0].encode())
            return True
    except (zipfile.BadZipFile, OSError, ValueError, EOFError, NotImplementedError, RuntimeError):
        return False


def _mark_from_internet(path):
    """Windows: mark a received file as from the internet (Mark of the Web), so Office opens it in Protected View.
    Best effort; nothing elsewhere."""
    if _WINDOWS:
        with contextlib.suppress(OSError), open(f"{path}:Zone.Identifier", "w", encoding="ascii", newline="") as f:
            f.write("[ZoneTransfer]\r\nZoneId=3\r\n")


def _chunk_meta(meta):
    """The chunk route's headers, parsed: id, index, total, the chunk's sha256 and the whole file's (last chunk)."""
    uid = meta.get("id")
    if not isinstance(uid, str) or not UPLOAD_ID.fullmatch(uid):
        raise _bad("X-Upload-Id", "X-Upload-Id must name an upload.")
    out = {"id": uid}
    for key, field in (("index", "X-Chunk-Index"), ("total", "X-Chunk-Total")):
        v = meta.get(key)
        if not isinstance(v, str) or not re.fullmatch(r"0|[1-9][0-9]{0,5}", v):
            raise _bad(field, f"{field} must be a whole number.")
        out[key] = int(v)
    for key, field in (("sha256", "X-Chunk-Sha256"), ("fileSha256", "X-File-Sha256")):
        v = meta.get(key)
        if v is None and key == "fileSha256":
            continue
        if not isinstance(v, str) or not SHA256_HEX.fullmatch(v.lower()):
            raise _bad(field, f"{field} must be a sha256 in hex.")
        out[key] = v.lower()
    if out["index"] >= out["total"]:
        raise _bad("X-Chunk-Index", "X-Chunk-Index must be below X-Chunk-Total.")
    return out


def _private_dirs(folder):
    """uploads/ and its pending/ or accepted/ folder, each 0700 where the OS has file modes."""
    detached.make_private_dir(folder.parent)
    detached.make_private_dir(folder)


def _write_chunk(path, offset, data):
    """Write `data` at `offset` of a pending file (created 0600, its folder 0700), cutting off whatever lay past
    `offset` first (bytes a crash left after the last counted chunk). False when the file holds fewer than `offset`
    bytes: the chunks before went missing."""
    _private_dirs(path.parent)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0), 0o600)
    with os.fdopen(fd, "r+b") as f:
        if os.fstat(f.fileno()).st_size < offset:
            return False
        f.truncate(offset)
        f.seek(offset)
        f.write(data)
        f.flush()
        os.fsync(f.fileno())
    return True


def _file_sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1024 * 1024), b""):
            h.update(block)
    return h.hexdigest()


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
        self._merged_into_owner = set()  # sha256 of the secrets a merge into the owner dropped; never persisted
        self._last_write = collections.OrderedDict()  # (pid, route) -> time of the last accepted write, oldest first
        self._joins = collections.OrderedDict()  # (guest key, address) -> times of recent joins, least recent first
        self._key_joins = {}  # guest key -> times of recent joins from any address
        self._reported = {}  # pid -> time of their last report, which REPORT_INTERVAL spaces; never persisted
        self._base_cache = self._guest_q_cache = None
        self._chat_touch, self._chat_touches = {}, 0  # message id -> the count of reaction or forward changes at its last one; never persisted
        self._undo = []  # (file, bytes before or None) an apply wrote, put back when the apply is refused
        self.uploads_dir = self.path.parent / "uploads"  # in the private data folder; never under web/ or assets/
        self._sending = set()  # upload ids whose chunk is being written outside the lock
        self.on_owner_token = None  # called with (token, rotatedAt) inside the rotation, before it commits
        self._pairing = None  # the one live sign-in code: {"hash", "until", "misses": {address: count}}; never persisted

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
            "pluginVersion": plugin_version,
            "writtenBy": plugin_version,
            "rev": 0,
            "session": {
                "title": title,
                "goal": goal,
                "createdAt": now,
                "phase": {"kind": "live"},
                "share": {"url": ""},
                "guestKey": ids.token(9),
                "settings": _settings_patch({**copy.deepcopy(DEFAULT_SETTINGS), "reviewAnswers": False}, settings or {}),
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
            "inboxSeen": {},
            "discussions": {},
            "discussionSeen": {},
            "mergeRequests": [],
            "aboutYou": {},
            "disagreements": {},
            "log": {"seq": 0, "events": [], "handled": []},
        }
        s = cls(path, state, clock=clock, ids=ids, validate_writes=validate_writes, assets_dir=assets_dir, plugin_version=plugin_version)
        s._write_current()
        return s, token

    @classmethod
    def load(cls, path, *, plugin_version="", clock=time.time, ids=None, validate_writes=False, assets_dir=None):
        """Parse state.json once. The shape is no longer versioned: the `schemaVersion` the last versioned build wrote
        (7) is dropped and the next write leaves it out; a file below 7 needs that build's migrations, so it is refused."""
        path = Path(path)
        raw = path.read_text(encoding="utf-8")
        try:
            doc = json.loads(raw)
        except ValueError as exc:
            raise DomainError(500, "state-invalid", f"{path.name} is not JSON: {exc}") from exc
        if not isinstance(doc, dict):
            raise DomainError(500, "state-invalid", f"{path.name} is not a JSON object.")
        version = doc.pop("schemaVersion", None)
        if _is_int(version) and version < LAST_SCHEMA_VERSION:
            raise DomainError(500, "state-too-old", f"{path.name} is at schemaVersion {version}, from before this build; it reads only "
                              f"{LAST_SCHEMA_VERSION}. Start a new session, or restart it under the previous build first so it migrates to {LAST_SCHEMA_VERSION}.")
        err = document_error(doc)
        if err:
            raise DomainError(500, "state-invalid", f"{path.name}: {err}")
        return cls(path, doc, clock=clock, ids=ids, validate_writes=validate_writes, assets_dir=assets_dir, plugin_version=plugin_version)

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
        seq[key] = seq.get(key, 0) + 1
        return f"{key}{seq[key]}"

    # -- identity -----------------------------------------------------------------------------

    def resolve(self, *, secret=None, owner_token=None, watcher=None):
        """The pid a request acts as, from its X-Owner-Token, X-Session-Secret or X-Watcher-Key header value. A watcher
        key is only ever resolved alone; server.py takes it on the /api/mine/requests routes and nowhere else."""
        with self._lock:
            creds = self.state["credentials"]
            if watcher:
                pid = creds.get("watchers", {}).get(sha256(watcher))
                if not pid:
                    raise DomainError(401, "unknown-session", "This watcher key is no longer valid. Copy a new one from the session page.")
                self._person(pid)
                return pid
            if owner_token:
                h = sha256(owner_token)
                if hmac.compare_digest(h, creds["owner"]["tokenHash"]) or h in creds.get("devices", {}):
                    return HOST
                raise DomainError(401, "unknown-session", "This owner link is no longer valid.")
            if secret:
                h = sha256(secret)
                pid = creds["secrets"].get(h)
                if pid:
                    self._person(pid)
                    return pid
                if h in self._merged_into_owner:
                    raise DomainError(401, "merged-into-owner", "This browser was merged into the owner. Open your owner link here.")
            raise DomainError(401, "unknown-session", "Join the session again.")

    def check(self, pid):
        """`pid` while that person may read: DomainError once they are removed, waiting or gone (server.py's asset
        cookie names a pid, not a credential)."""
        with self._lock:
            self._person(pid)
        return pid

    def _person(self, pid):
        person = self.state["people"].get(pid) if isinstance(pid, str) else None
        if person is None:
            raise DomainError(401, "unknown-session", "Join the session again.")
        if person["status"]["kind"] == "removed":
            raise DomainError(403, "removed", "The owner removed you from this session.")
        if person["status"]["kind"] == "waiting":  # the waiting page shows the title and intro, nothing else
            sess = self.state["session"]
            raise DomainError(403, "waiting", "The host has not let you in yet.", title=sess["title"], intro=sess.get("intro", ""))
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
        name = _person_name(body, empty_ok=True)
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
            try:
                sent = key.encode()
            except UnicodeEncodeError:  # a lone surrogate (json.loads takes one): no key is that, and it is never filtered
                sent = None
            if guest_key and (sent is None or not hmac.compare_digest(sent, guest_key.encode())):
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
                        if p != HOST and p not in here and v["status"]["kind"] == "active" and _name_key(v["name"]) == _name_key(name)
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
                was = None
            same = self._same_name(name, new, here)
            if waiting or same:  # Claude may propose an admit or a merge; the owner's tap carries it out
                names = st["session"]["settings"]["digestNames"]
                self._event("person-joined", person=new, waiting=bool(waiting), **hint, **({"name": final} if names else {}),
                            sameName=[{k: v for k, v in m.items() if names or k != "name"} for m in same])
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
        doomed = []
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if person["status"]["kind"] != "waiting":
                raise DomainError(409, "wrong-status", "This person is not waiting to join.", status=person["status"]["kind"])
            if action == "admit":
                self._admit(target)
            else:
                person["status"] = {"kind": "removed", "at": self.now(), "by": HOST}
                self._drop_watcher(target)
                doomed = self._end_uploads_of(target, self.now())
                self._presence_rev += 1
        for f in doomed:
            self._discard(f)
        return {"pid": target, "status": person["status"]["kind"]}

    def _admit(self, target):
        self.state["people"][target]["status"] = {"kind": "active"}
        self._presence_rev += 1

    def _prune_joins(self, now):
        """Forget join records whose windows have passed, least recently joined first."""
        while self._joins:
            if now - next(iter(self._joins.values()))[-1] < JOIN_WINDOW:
                break
            self._joins.popitem(last=False)
        for key in [k for k, times in self._key_joins.items() if now - times[-1] >= JOIN_KEY_WINDOW]:
            self._key_joins.pop(key)

    def _same_name(self, name, new, here):
        """Who else is in under `name`, or under it with the " 2" a taken name gets, and not here now: never the owner."""
        if not name:
            return []
        key = _name_key(name)

        def same(n):
            n = _name_key(n)
            return key in (n, re.sub(r" [0-9]+\Z", "", n))

        out = []
        for p, v in self.state["people"].items():
            if p not in (HOST, new) and p not in here and self._active(p) and same(v["name"]):
                seen = self._presence.get(p)
                out.append({"pid": p, "name": v["name"], **({"device": seen["device"]} if seen and seen.get("device") else {}),
                            **({"lastSeen": iso(self._seen(seen))} if seen else {})})
        return out

    def _names_hidden_from(self, pid):
        """True when the session shows initials or "someone" and `pid` is not the owner or a leader."""
        role = self.state["people"].get(pid, {}).get("role")
        return self.state["session"]["settings"]["names"] != "full" and role not in ("owner", "leader")

    def _unique_name(self, name, pid):
        """The name, suffixed " 2", " 3" ... past a taken one; a guest's is kept as given while names are hidden, since a
        suffix would tell them the name is taken. Only the owner sees their own, so it keeps the suffix."""
        if self.state["session"]["settings"]["names"] != "full" and pid != HOST:
            return name
        taken = {_name_key(v["name"]) for p, v in self.state["people"].items() if p != pid}
        out, n = name, 2
        while _name_key(out) in taken:
            suffix = f" {n}"
            out, n = name[: MAX_NAME - len(suffix)] + suffix, n + 1
        return out

    def _guest_name(self):
        """"Guest N" for a nameless join. While names are hidden N ignores typed names, so it cannot tell the joiner
        someone typed "Guest N"; otherwise it skips a taken one."""
        n = sum(1 for p in self.state["people"] if p != HOST) + 1
        if self.state["session"]["settings"]["names"] != "full":
            return f"Guest {n}"
        taken = {_name_key(v["name"]) for v in self.state["people"].values()}
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
        if any(pid in by for by in [*st["votes"].values(), *st.get("backs", {}).values(), *st.get("passes", {}).values()]):
            return True
        if any(pid in q.get("for", ()) for q in st["questions"]):
            return True
        records = [*st["proposals"], *st["chat"], *st["requests"], *st["annotations"], *st["uploads"]]
        records += [s for lst in st["suggestions"].values() for s in lst]
        records += [c for lst in st["discussions"].values() for c in lst]
        records += [d for lst in st.get("disagreements", {}).values() for d in lst]
        records += [t for lst in st.get("cleared", {}).values() for t in lst]
        return any(r["pid"] == pid for r in records) or any(r["by"] == pid for r in st.get("reports", {}).values())

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
        for key in (st["prefs"], st["notifications"], st["aboutYou"], st["discussionSeen"]):
            key.pop(pid, None)
        for h in [h for h, p in st["credentials"]["secrets"].items() if p == pid]:
            st["credentials"]["secrets"].pop(h)
        self._drop_watcher(pid)
        self._presence.pop(pid, None)
        for key in [k for k in self._last_write if k[0] == pid]:
            self._last_write.pop(key)

    def heartbeat(self, pid, body):
        """POST /api/heartbeat (wire.schema.json `heartbeat`): memory only; allowed while the session
        is ended. Each `tab` (a page sends its own id; none is the tab "") keeps its own beat and its
        own limits, so one person's tabs and devices never refuse each other. A beat that changes
        `visible` or `away` is taken at once, outside the tab's one-a-second limit, since the page
        sends one the moment its visibility changes; such changes have their own one-a-second limit,
        so flipping visibility cannot flood. A reload keeps the tab id, so a new page's first beat can land
        inside the old page's limits: a too-soon beat that changes nothing is answered without being recorded,
        and a tab may make two changes inside one interval (the old page's hidden, the new page's visible), so
        flips still cap at about two a second. A too-soon beat that changes `q` or typing is refused as before.
        A person keeps MAX_TABS tabs, the least recent dropped."""
        body = _body(body)
        err = wire_error(body, "heartbeat")
        if err:
            m = re.match(r"\$\.(\w+)", err)
            raise _bad(m.group(1) if m else "body", err)
        for field in ("lastInput", "lastFocus"):
            if not math.isfinite(body.get(field, 0)):  # json.loads takes Infinity and NaN
                raise _bad(field, f"{field} must be a finite number of seconds.")
        tab = body.get("tab", "")
        if "tab" in body and not TAB_ID.fullmatch(tab):
            raise _bad("tab", "tab must name the tab: 1 to 32 letters, digits, - or _.")
        visible = body.get("visible", True)
        away = body.get("away") is True
        shown = {"q": _visible((body.get("q") or "")[:16]), "typing": body.get("typing") is True, "chatTyping": body.get("chatTyping") is True}
        identity = lambda p: {"pid": pid, "name": p["name"], "role": p["role"], "trusted": p["trusted"]}  # noqa: E731
        with self._lock:
            person = self._person(pid)
            now = self.now()
            rec = self._presence.get(pid)
            was = self._presence_entry(pid, rec, now) if rec and now - self._seen(rec) < OFFLINE_AFTER else None
            rec = self._presence.setdefault(pid, {"at": now, "tabs": collections.OrderedDict()})
            old = rec["tabs"].get(tab)
            changed = old is not None and (old["visible"] != visible or (old.get("awayAt") is not None) != away)
            route = f"heartbeat-change:{tab}" if changed else f"heartbeat:{tab}"
            last = self._last_write.get((pid, route), float("-inf"))
            if now - last < HEARTBEAT_INTERVAL:
                if not changed and old is not None and all(old[k] == v for k, v in shown.items()):
                    return identity(person)  # the same beat again: nothing to record
                if not changed or now - self._last_write.get((pid, f"heartbeat-prev:{tab}"), float("-inf")) < HEARTBEAT_INTERVAL:
                    raise DomainError(429, "slow-down", "Wait a moment before sending again.")
            recent = rec.setdefault("recent", collections.deque(maxlen=MAX_TABS))
            if len(recent) == MAX_TABS and now - recent[0] < HEARTBEAT_INTERVAL:
                raise DomainError(429, "slow-down", "Wait a moment before sending again.")
            old = old or {}
            beat = {
                **shown,
                "seen": now,
                "visible": visible,
                "inputAt": now - body.get("lastInput", 0),
            }
            if not visible:
                beat["hiddenAt"] = old.get("hiddenAt", now) if not old.get("visible", True) else now
            if away:
                beat["awayAt"] = old.get("awayAt", now)
            # lastFocus is an age, so never later than now: it orders only this person's own tabs. The age arrives
            # late by the beat's own delay, so the same focus (focusId) keeps its first estimate; with no focusId an
            # estimate only moves earlier.
            if "lastFocus" in body:
                at = now - body["lastFocus"]
                if "focusAt" not in old:
                    pass
                elif "focusId" not in body and "focusId" not in old:
                    at = min(old["focusAt"], at)
                elif body.get("focusId") == old.get("focusId"):
                    at = old["focusAt"]
                beat["focusAt"] = at
                if "focusId" in body:
                    beat["focusId"] = body["focusId"]
            else:
                beat.update({k: old[k] for k in ("focusAt", "focusId") if k in old})
            tabs = rec["tabs"]
            tabs.pop(tab, None)
            for t in [t for t, b in tabs.items() if now - b["seen"] >= OFFLINE_AFTER]:
                tabs.pop(t)
            while len(tabs) >= MAX_TABS:
                tabs.popitem(last=False)
            tabs[tab] = beat
            if self._presence_entry(pid, rec, now) != was:  # a beat that changes nothing anyone sees moves no ETag
                self._presence_rev += 1
            if changed and last > float("-inf"):
                self._wrote(pid, f"heartbeat-prev:{tab}", last)
            self._wrote(pid, route, now)
            recent.append(now)
            if changed:
                self._wrote(pid, f"heartbeat:{tab}", now)
            return identity(person)

    def rename(self, pid, body):
        """POST /api/rename: `{name, pid?}`. Each person renames themselves; the owner alone may name a target `pid`,
        throttled per target, so the owner can rename several people in a row."""
        name = _person_name(body)
        target = _ident(body, "pid", optional=True) or pid
        route, check = ("rename", None) if target == pid else (f"rename:{target}", self._owner)
        with self._write_as(pid, route, check=check) as st:
            if target not in st["people"]:
                raise DomainError(404, "not-found", "No such person.", field="pid")
            st["people"][target]["name"] = self._unique_name(name, target)
            return {"pid": target, "name": st["people"][target]["name"]}

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
        """POST /api/person/remove: removing clears leader and trust; the secret stops working until restored. The
        watcher key ends for good: a restored person copies a new one. Restoring drops it too, for a state an
        earlier build wrote, which kept a removed person's key. Their files still on the way are declined and what
        arrived of them is deleted."""
        on = _bool(body, "on")
        doomed = []
        with self._tx() as st:
            self._owner(pid)
            target = self._target_person(body)
            person = st["people"][target]
            if on or person["status"]["kind"] == "removed":
                self._drop_watcher(target)
            if on:
                person.update(role="guest", trusted=False, status={"kind": "removed", "at": self.now(), "by": HOST})
                self._presence.pop(target, None)
                doomed = self._end_uploads_of(target, self.now())
            else:
                person["status"] = {"kind": "active"}
            self._presence_rev += 1
        for f in doomed:
            self._discard(f)
        return {"removed": on}

    def _merge_target(self, body, field):
        """A person merge_people names: `to` may be the owner, who absorbs a second identity of their own;
        `from` never is, since the owner is never merged away."""
        target = _ident(body, field)
        if target not in self.state["people"]:
            raise DomainError(404, "not-found", "No such person.", field=field)
        if target == HOST and field == "from":
            raise _bad(field, "The owner cannot be merged into anyone; merge the other identity into the owner.")
        return target

    def merge_people(self, pid, body):
        """POST /api/person/merge: everything `from` holds moves to `to`, then `from` is forgotten."""
        with self._tx():
            self._owner(pid)
            src = self._merge_target(body, "from")
            dst = self._merge_target(body, "to")
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
                self._notify(m["to"], "merge", MERGED_NOTE, actor=pid)
            return {"status": m["status"]["kind"]}

    # -- Claude's merge and admit proposals: Claude proposes, only the owner's approve acts --------

    def _propose(self, kind, op, **people):
        st = self.state
        for field, p in people.items():
            if p == HOST:
                raise _bad(field, "The owner is never merged or let in by a proposal.")
            if p not in st["people"]:
                raise DomainError(404, "not-found", "No such person.", field=field)
        if len(set(people.values())) < len(people):
            raise _bad("to", "Pick two different people.")
        record = {"kind": kind, **people}
        if not self._proposal_live(record):
            raise DomainError(409, "wrong-status", "Only a guest who is in, or for an admit one who waits, and neither a leader nor trusted.")
        joined = [e for e in st["log"]["events"] if e["kind"] == "person-joined" and e["person"] == people.get("from", people.get("pid"))]
        if not any(e["waiting"] if kind == "admit" else people["to"] in [m["pid"] for m in e["sameName"]] for e in joined):
            raise DomainError(409, "not-reported", "Propose only the join a person-joined event reported: its person, and for a merge one of its sameName.")
        lst = st.setdefault("claudeProposals", [])
        same = [p for p in lst if {k: p.get(k) for k in record} == record]
        if any(p["status"]["kind"] == "dismissed" for p in same):
            raise DomainError(409, "dismissed", "The owner dismissed this proposal already.")
        if any(p["status"]["kind"] == "pending" and self._proposal_live(p) for p in same):
            raise DomainError(409, "wrong-status", "This proposal already waits for the owner.", status="pending")
        open_ = self._open_claude_proposals()
        if len(open_) >= MAX_CLAUDE_PROPOSALS:
            raise DomainError(409, "full", f"{MAX_CLAUDE_PROPOSALS} proposals already wait for the owner.")
        if len(lst) >= MAX_CLAUDE_PROPOSALS:  # the oldest answered or no longer live one makes room; a dismissal is kept
            old = next((p for p in lst if p not in open_ and p["status"]["kind"] != "dismissed"), None)
            if old is None:
                raise DomainError(409, "full", f"{MAX_CLAUDE_PROPOSALS} proposals are kept, each waiting or dismissed.")
            lst.remove(old)
        kid = self._next("K")
        names = {p: st["people"][p]["name"] for p in people.values()}
        note = _text(op, "note", limit=MAX_NOTE, optional=True)
        lst.append({"id": kid, **record, "names": names, "reasons": list(dict.fromkeys(op["reasons"])), **({"note": note} if note else {}),
                    "at": self.now(), "status": {"kind": "pending"}})
        return {"id": kid}

    def _op_propose_merge(self, op):
        return self._propose("merge", op, **{"from": op["from"], "to": op["to"]})

    def _op_propose_admit(self, op):
        return self._propose("admit", op, pid=op["pid"])

    def _proposal_live(self, p):
        """Still what Claude saw: guests, neither a leader nor trusted, in the status it needs (a merge's both in, as the
        owner's Merge needs; an admit's waiting), each under the name it had then."""
        people = self.state["people"]
        need = {p["pid"]: "waiting"} if p["kind"] == "admit" else {p["from"]: "active", p["to"]: "active"}
        return all(
            q in people and people[q]["status"]["kind"] == kind and people[q]["role"] == "guest" and not people[q]["trusted"]
            and people[q]["name"] == p.get("names", {}).get(q, people[q]["name"])
            for q, kind in need.items()
        )

    def _open_claude_proposals(self):
        """What waits on the owner: pending and still live; one whose people changed drops out, as the owner's tap would refuse it."""
        return [p for p in self.state.get("claudeProposals", []) if p["status"]["kind"] == "pending" and self._proposal_live(p)]

    def act_on_claude_proposal(self, pid, body):
        """POST /api/claude-proposal/act: the owner approves one of Claude's proposals, which merges or lets in as the
        owner's own Merge and Let in do, or dismisses it. One whose people changed since is marked stale, and 409."""
        action = _choice(body, "action", ("approve", "dismiss"))
        kid = _ident(body, "id")
        now = self.now()
        with self._tx() as st:
            self._owner(pid)
            p = next((p for p in st.get("claudeProposals", []) if p["id"] == kid), None)
            if p is None:
                raise DomainError(404, "not-found", "No such proposal.")
            if p["status"]["kind"] != "pending":
                raise DomainError(409, "wrong-status", "This proposal was already answered.", status=p["status"]["kind"])
            stale = action == "approve" and not self._proposal_live(p)
            if stale:
                p["status"] = {"kind": "stale", "at": now}
            elif action == "dismiss":
                p["status"] = {"kind": "dismissed", "at": now}
            else:
                p["status"] = {"kind": "approved", "at": now}
                if p["kind"] == "admit":
                    self._admit(p["pid"])
                else:
                    self._merge(p["from"], p["to"])
                    self._notify(p["to"], "merge", MERGED_NOTE, actor=pid)
        if stale:
            raise DomainError(409, "stale", "The people in this proposal changed since Claude made it. Nothing was merged or let in.")
        return {"status": p["status"]["kind"]}

    def _merge(self, src, dst):
        """Into the owner too: then `src`'s secrets end rather than move (only the owner link names the owner),
        and its open own-Claude requests wait in the owner's queue, since the owner holds no watcher key."""
        if src == HOST:
            raise _bad("from", "The owner cannot be merged.")
        st = self.state
        for k, v in st.items():  # a mention of src now names dst
            if k != "credentials" and isinstance(v, (dict, list)):
                _retoken(v, f"<@{src}>", f"<@{dst}>")
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
        for m in [*st["chat"], *(c for lst in st["discussions"].values() for c in lst)]:
            for pids in m.get("reactions", {}).values():
                pids[:] = list(dict.fromkeys(map(swap, pids)))
        for c in (c for lst in st["discussions"].values() for c in lst):
            c["pid"] = swap(c["pid"])
            if "hidden" in c:
                c["hidden"]["by"] = swap(c["hidden"]["by"])
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
        for e in st.get("decisions", ()):
            e["by"] = swap(e["by"])
            if "card" in e:
                e["card"] = moved.get((e["qid"], e["card"]), e["card"])
        for key in ("passes", "lateActs"):  # the kept person's own record wins
            for by in st.get(key, {}).values():
                rec = by.pop(src, None)
                if rec is not None:
                    by.setdefault(dst, rec)
        for q in st["questions"]:
            if "for" in q:
                q["for"] = list(dict.fromkeys(map(swap, q["for"])))
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
        for u in st["uploads"]:
            if "by" in u["status"]:
                u["status"]["by"] = swap(u["status"]["by"])
        for rep in st.get("reports", {}).values():
            rep["by"] = swap(rep["by"])
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
        for n in notes:  # a vote line keys on the answer it counts, which is now dst's
            if n["kind"] == "votes" and "rollup" in n:
                qid, _, ref = n["rollup"]["key"].partition(":")
                n["rollup"]["key"] = f"{qid}:{moved.get((qid, ref), ref)}"
        if notes:
            st["notifications"][dst] = sorted(notes + st["notifications"].get(dst, []), key=lambda n: n["at"])[-NOTIFY_CAP:]
        seen = st["inboxSeen"].pop(src, {})
        if seen:
            st["inboxSeen"][dst] = {**seen, **st["inboxSeen"].get(dst, {})}
        seen = st["discussionSeen"].pop(src, {})
        if seen:  # the later open of each question wins
            mine = st["discussionSeen"].setdefault(dst, {})
            for qid, at in seen.items():
                mine[qid] = max(at, mine.get(qid, 0.0))
        src_prefs = st["prefs"].pop(src, {})
        if src_prefs:
            st["prefs"][dst] = {**src_prefs, **st["prefs"].get(dst, {})}
        about = st["aboutYou"].pop(src, None)
        if about and dst not in st["aboutYou"]:
            st["aboutYou"][dst] = about
        now = self.now()
        kept = []
        for m in st["mergeRequests"]:
            if src in (m["from"], m["to"]):
                if m["status"]["kind"] == "pending":
                    m["status"] = {"kind": "declined", "at": now, "why": "gone"}
                m["from"], m["to"] = swap(m["from"]), swap(m["to"])
                if m["from"] == m["to"] or HOST in (m["from"], m["to"]):
                    continue  # between src and dst, or now naming the owner: it asks nothing anyone could still mean
            kept.append(m)
        st["mergeRequests"][:] = kept
        if dst == HOST:
            for r in st["requests"]:
                if r["pid"] == HOST and r["runner"] == "self" and r["status"]["kind"] in ("pending", "running"):
                    r.update(runner="host", status={"kind": "pending"})
        secrets = st["credentials"]["secrets"]
        for h, p in list(secrets.items()):
            if p == src:
                if dst == HOST:  # owner rights stay with the owner link: the device is told to open it
                    secrets.pop(h)
                    self._merged_into_owner.add(h)
                else:
                    secrets[h] = dst
        self._drop_watcher(src)  # a watcher key never gains another person's requests
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
        """POST /api/round/reset: `working` back to `open`, the only exit when Claude's session died.

        Writes `round-reset`, so a session that is still alive learns why its `open-round` is refused.
        """
        _body(body)
        with self._tx():
            r = self._step("reset", pid)
            self._event("round-reset", round=r["n"], sentSeq=r["status"]["eventSeq"])
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

    def _answerable(self, q, *, late_on_lock=False):
        """Refuse unless people may answer, vote, pick or react on q; returns `late` for a closed round. With
        `late_on_lock` (a Disagree) a locked question of a closed round is answerable too."""
        r = self._round(q["round"])
        kind = r["status"]["kind"] if r else None
        if q["id"] in self.state["locks"] and not (late_on_lock and kind == "closed"):
            raise DomainError(409, "locked", f"Question {q['id']} is locked; suggest a change instead.")
        if r is None:
            raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
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

    def _parse_question(self, qi, *, round_n, origin, known, field, made=()):
        """A QuestionInput (already schema-valid) checked for the rules the schema cannot express. `made` holds the
        questions this apply parsed before it, not yet in the session."""
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
            if question_shape.restates(alt["text"], rec):
                raise _bad(f"{field}.alternatives[{i}].text", f"Alternative ({a['key']}) repeats or contains the recommendation, or the recommendation contains it.")
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
        q["format"] = self._parse_format(fmt, f"{field}.format", made)
        q["answerScope"] = qi.get("answerScope", "person")
        refs = qi.get("references", [])
        if len(refs) > MAX_REFERENCES:
            raise DomainError(400, "too-long", f"A question holds at most {MAX_REFERENCES} references.", field=f"{field}.references", max=MAX_REFERENCES)
        q["references"] = [self._reference(r, f"{field}.references[{i}]") for i, r in enumerate(refs)]
        q["origin"] = origin
        q["needsReview"] = []
        targets = self._targets(qi["for"], f"{field}.for") if "for" in qi else []
        if targets:
            q["for"] = targets
        return q

    def _parse_format(self, fmt, field, made=()):
        kind = fmt["kind"]
        if kind == "text":
            return {"kind": "text"}
        if kind in OPTION_COUNTS:
            ids = [o["id"] for o in fmt["options"]]
            if any(o["id"] == OTHER or "other" in o for o in fmt["options"]):
                raise _bad(f"{field}.options", "The server adds the Something else option itself; leave it out.")
            if kind == "multi" and any(o["id"] == NONE or "none" in o or _none_label(o.get("label")) for o in fmt["options"]):
                raise _bad(f"{field}.options", "The server adds None of these itself: set format.none to true instead.")
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
            return {"kind": kind, "options": [*options, dict(OTHER_OPTION), *([dict(NONE_OPTION)] if fmt.get("none") else [])]}
        if kind == "scale":
            labels = {k: _text(fmt["labels"], k, limit=80) for k in ("min", "max")}
            mid = _text(fmt["labels"], "mid", limit=80, optional=True)
            return {"kind": "scale", "min": 1, "max": fmt["max"], "labels": {**labels, **({"mid": mid} if mid else {})}}
        if kind == "confirm":
            return {"kind": "confirm", "image": self._asset(fmt["image"], f"{field}.image", image=True), "rect": _rect(fmt["rect"], f"{field}.rect")}
        if fmt.get("lookAt") is None:
            raise _bad(f"{field}.lookAt", "A prototype question says where to look: the area the variants change and the step that shows it.")
        look = _text(fmt, "lookAt", limit=MAX_NOTE)
        variants, earlier = [], [*self.state["questions"], *made]
        taken = {_pair(v["previous"]) for q in earlier for v in q["format"].get("variants", []) if "previous" in v}
        for i, v in enumerate(fmt["variants"]):
            at = f"{field}.variants[{i}]"
            if not VARIANT.fullmatch(v["id"]):
                raise _bad(f"{at}.id", "A variant id looks like v-1.")
            variants.append({"id": v["id"], "label": _text(v, "label"), **self._views(v, at)})
            if "previous" in v:
                variants[-1]["previous"] = _previous(v["previous"], earlier, taken, f"{at}.previous")
            if v.get("lookAt") is not None:
                variants[-1]["lookAt"] = _text(v, "lookAt", limit=MAX_NOTE)
        if len({v["id"] for v in variants}) != len(variants):
            raise _bad(f"{field}.variants", "Each variant needs its own id.")
        return {"kind": "prototype", "lookAt": look, "variants": variants}

    def _views(self, v, at):
        """A variant's views as written: `{asset}` for one picture or one html file and nothing else, so such a variant
        keeps the shape builds before `shots` and `snapshot` read; `{shots?, snapshot?, live?}` otherwise. The schema
        has already refused a variant with no view, or with `asset` beside another view."""
        if "asset" in v:
            return {"asset": self._asset(v["asset"], f"{at}.asset")}
        shots = [self._asset(x, f"{at}.shots[{j}]", image=True) for j, x in enumerate(v.get("shots", []))]
        if len(set(shots)) != len(shots):
            raise _bad(f"{at}.shots", "Each screenshot of a variant is its own picture.")
        snap = [self._asset(v["snapshot"], f"{at}.snapshot", pattern=HTML_ASSET)] if "snapshot" in v else []
        live = [self._live_link(v["live"], f"{at}.live")] if "live" in v else []
        if len(shots) + len(snap) == 1 and not live:
            return {"asset": (shots + snap)[0]}
        return {**({"shots": shots} if shots else {}), **({"snapshot": snap[0]} if snap else {}), **({"live": live[0]} if live else {})}

    def _live_link(self, link, at):
        """A variant's live view: an entry `add-live` made that has not ended, and a path LIVE_PATH takes."""
        why = _live_path_error(link["path"])
        if why:
            raise _bad(f"{at}.path", why)
        e = next((e for e in self.state.get("lives", []) if e["id"] == link["id"]), None)
        if e is None or e["status"]["kind"] == "ended":
            raise _bad(f"{at}.id", f"{str(link['id'])[:40]} names no live prototype that is still on; add one with add-live first.")
        return {"id": e["id"], "path": link["path"]}

    def _options(self, q):
        """Option id -> label for the option cards a non-text question offers, None of these included; Something
        else has no card, since each person who picks it writes their own (`_has_other`)."""
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
            rec = q.get("recommendation")
            if rec and not question_shape.withheld(rec):  # a withheld recommendation is asked open, never on a card
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
        _choice(body, "purpose", PURPOSES)
        with self._tx():
            self._owner(pid)
            return {"purpose": self._set_purpose(body)["purpose"]}

    def _set_purpose(self, body):
        """The one purpose change behind the owner route and Claude's set-purpose op."""
        purpose = _choice(body, "purpose", PURPOSES)
        q = self._question(body.get("qid"))
        if purpose == "poll" and q["format"]["kind"] == "text":
            raise _bad("purpose", "A poll needs options; this is a text question.")
        if purpose == "gather" and q["id"] in self.state["locks"]:
            raise DomainError(409, "locked", "Unlock the question before making it a gather question.")
        if (purpose == "poll") != (q["purpose"] == "poll") and q["id"] in self.state["locks"]:
            raise DomainError(409, "locked", "Unlock the question before making it a poll or no longer a poll.")
        q["purpose"] = purpose
        return {"qid": q["id"], "purpose": purpose}

    def set_for(self, pid, body):
        """POST /api/question/for: the owner overrides who a question asks, the way it sets the purpose."""
        with self._tx():
            self._owner(pid)
            return self._set_for(body)

    def _set_for(self, body):
        """The one change of who must answer behind the owner route and Claude's set-for op; [] asks everyone."""
        q = self._question(_body(body).get("qid"))
        targets = self._targets(body.get("for"), "for")
        if targets:
            q["for"] = targets
        else:
            q.pop("for", None)
        return {"qid": q["id"], "for": targets}

    def _targets(self, v, field):
        """`for`: the people a question asks, each an active person's pid or name (casefolded, as Claude reads it
        from "@name"), each once, as pids."""
        if not isinstance(v, list) or not all(isinstance(t, str) for t in v):
            raise _bad(field, f"{field} must list people, by name or id.")
        out = []
        for t in v:
            pid = t if self._active(t) else next((p for p, w in self.state["people"].items() if self._active(p) and w["name"].casefold() == t.strip().casefold()), None)
            if pid is None:
                raise DomainError(404, "no-such-person", f"No one called {t[:40]} is in this session.", field=field)
            if pid not in out:
                out.append(pid)
        return out

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
            text = self._tokenize(card["pid"], text)  # as its author: names hidden from them stay plain in their text
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
        """Active people who vote for card `ref` on qid, or back it as one of several (`backs`, multi). A pick of
        an option (`o:`) whose picker's own answer the owner hid is left out, as the hidden answer is; the vote
        stays in state, so showing the answer again counts it."""
        voters = [v for v, r in self.state["votes"].get(qid, {}).items() if r == ref]
        voters += [v for v, refs in self.state.get("backs", {}).get(qid, {}).items() if ref in refs and v not in voters]
        if ref.startswith("o:"):
            hidden = {c["pid"] for c in self.state["cards"].get(qid, []) if c["kind"] == "person" and "hidden" in c}
            voters = [v for v in voters if v not in hidden]
        return [v for v in voters if self._active(v)]

    def _acts(self, qid, pid):
        """What pid did on qid, of: an own shown card, a vote, a back, a reaction, a Disagree, a Pass."""
        st = self.state
        held = {
            "card": any(c["kind"] == "person" and c["pid"] == pid and self._shown(c) for c in st["cards"].get(qid, [])),
            "vote": pid in st["votes"].get(qid, {}),
            "back": pid in st.get("backs", {}).get(qid, {}),
            "reaction": any(pid in by for by in st["reactions"].get(qid, {}).values()),
            "disagree": any(d["pid"] == pid for d in st.get("disagreements", {}).get(qid, [])),
            "pass": pid in st.get("passes", {}).get(qid, {}),
        }
        return {k for k, v in held.items() if v}

    def _took_part(self, q, pid):
        """The one rule for taking part, which the page mirrors (core.js `tookPart`): any of `_acts`. A person
        the question is `for` takes part only by their own card, a vote or back, or a Pass: a reaction or a
        Disagree alone leaves it open for them."""
        acts = self._acts(q["id"], pid)
        return bool(acts - {"reaction", "disagree"} if pid in q.get("for", ()) else acts)

    def _owes(self, q, pid):
        """Whether q still asks pid for an answer: they have not taken part, and it is `for` them or no one else
        has answered it. Once one other person has, it is optional for the rest, and no count includes it."""
        if self._took_part(q, pid):
            return False
        return pid in q.get("for", ()) or not any(c["kind"] == "person" and c["pid"] != pid and self._shown(c) for c in self.state["cards"].get(q["id"], []))

    def _mark_late(self, qid, pid, late):
        """A vote, back, reaction, Disagree or Pass on a closed round's question: the digest's `late` lists it."""
        if late:
            self.state.setdefault("lateActs", {}).setdefault(qid, {})[pid] = {**late, "at": self.now()}

    def _unpass(self, qid, pid):
        """An answer, pick or vote replaces the person's Pass on qid."""
        by_q = self.state.get("passes", {})
        if by_q.get(qid, {}).pop(pid, None) is not None and not by_q[qid]:
            by_q.pop(qid)
            if not by_q:
                self.state.pop("passes")

    def pass_(self, pid, body):
        """POST /api/pass: `{qid, reason?, on}` records that the person passes on q, on any purpose: they give no
        view, which is neither an answer nor agreement. `on: false` takes it back. The reason is up to 200
        characters, and required of a person the question is `for`. A Pass is not a pick, so a poll's results
        still wait for one."""
        on = _bool(body, "on", default=True)
        reason = _text(body, "reason", limit=MAX_NOTE, optional=True, empty_ok=True) if on else ""
        with self._write_as(pid, "pass") as st:
            q = self._question(body.get("qid"))
            late = self._answerable(q)
            if on and not reason and pid in q.get("for", ()):
                raise DomainError(400, "empty", "This question was asked of you: say why you pass.", field="reason")
            if on:
                st.setdefault("passes", {}).setdefault(q["id"], {})[pid] = {**({"reason": reason} if reason else {}), "ts": self.now()}
            else:
                self._unpass(q["id"], pid)
            self._mark_late(q["id"], pid, late)
            return {"pass": on}

    def answer(self, pid, body):
        """POST /api/answer: write, edit or clear one's own answer card. Empty text with `attachments` saves a
        picture-only card; empty text with `attachments` left out or empty clears the card."""
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
            text = self._tokenize(pid, text)
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
                published = {r["id"] for r in st["results"].get(qid, []) if self._result_shown(r)}
                if any(c not in published for c in cites):
                    raise _bad("cites", "cites must name results shown on this question.")
            if not text and not _body(body).get("attachments"):
                if mine:
                    self._clear_card(qid, mine)
                ref = None
            else:
                old_text = mine["text"] if mine else ""
                card = {"kind": "person", "pid": pid, **({"device": device} if device else {}), "text": text, "at": now}
                card["cites"] = list(cites) if cites is not None else (mine["cites"] if mine else [])
                self._attach(card, pid, body, mine)
                if mine:
                    votes = len(self._votes_on(qid, card_ref(mine)))
                    if mine.get("editedAfterVotes"):
                        card["editedAfterVotes"] = mine["editedAfterVotes"]
                    if votes and (old_text != text or mine.get("attachments") != card.get("attachments")):
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
                self._unpass(qid, pid)
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
            comment, other = self._tokenize(pid, comment, "comment"), self._tokenize(pid, other, "other")
            q = self._question(body.get("qid"))
            key, fields = self._parse_pick(q, body)
            late = self._answerable(q)
            device = self._device_for(q, body)
            qid = q["id"]
            cards = self._cards(qid)
            mine = next((c for c in cards if c["kind"] == "person" and c["pid"] == pid and c.get("device") == device), None)
            picks = fields.get("picks", [])
            if NONE in picks and len(picks) > 1:  # None of these excludes every other pick: the one just made wins
                fields["picks"] = [i for i in picks if i != NONE] if NONE in (mine or {}).get("picks", ()) else [NONE]
            chose_other = self._is_other({"kind": "person", **fields})
            if chose_other and not other:
                raise DomainError(400, "empty", "Something else needs your own option, in other.", field="other")
            if other and not chose_other:
                raise _bad("other", "other goes only with picking Something else.")
            if other and comment:
                raise _bad("comment", "Your own option is your card's text; send it in other, without a comment.")
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
                self._attach(card, pid, body, mine)
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
                self._unpass(qid, pid)
                if text and "hidden" not in card:
                    self._notify_mentions(text, pid, _answer_where(qid), before=mine["text"] if mine else "", qid=qid)
        self._wrote(pid, "pick", now)
        return {key: fields.get(key)}

    def _parse_pick(self, q, body):
        """(the field the format takes, the card fields it sets: {} for no pick). choice, confirm and
        prototype take `option` ("" for none); multi takes `options`, a subset of at least one; scale
        takes `value`, a whole number in its range; rank takes `order`, every option once (Something
        else may join it). Something else is `other` where the question has one; None of these is `none`,
        which `pick` keeps apart from every other pick."""
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

    def _attach(self, card, pid, body, mine):
        """C44: the uploads an answer or pick carries. `attachments`, when sent, replaces the list: ids of the
        writer's own uploads the owner accepted, at most MAX_ATTACHMENTS; when left out the card keeps its list."""
        ids = _body(body).get("attachments")
        ids = (list(mine.get("attachments", [])) if mine else []) if ids is None else self._attachment_ids(pid, ids)
        if ids:
            card["attachments"] = ids

    def _attachment_ids(self, pid, ids):
        """A list of the writer's own uploads the owner accepted, each once, at most MAX_ATTACHMENTS."""
        if not isinstance(ids, list) or not all(isinstance(i, str) for i in ids) or len(set(ids)) != len(ids):
            raise _bad("attachments", "attachments must list upload ids, each once.")
        if len(ids) > MAX_ATTACHMENTS:
            raise DomainError(400, "too-long", f"At most {MAX_ATTACHMENTS} files go with one post.", field="attachments", max=MAX_ATTACHMENTS)
        for uid in ids:
            u = self._upload(uid)
            if u["pid"] != pid:
                raise DomainError(404, "no-such-upload", f"No upload {uid[:40]}.")
            if u["status"]["kind"] not in UPLOAD_ACCEPTED:
                raise DomainError(409, "wrong-status", "Attach a file once the host has accepted it.", status=u["status"]["kind"])
            if u.get("avatar"):
                raise DomainError(409, "wrong-status", "A profile picture goes with no post.", status="avatar")
        for uid in ids:  # carried from now on: never a loose picture again (a refused write restores the state)
            u = self._upload(uid)
            u.pop("draft", None)
            u["carried"] = True
        return list(ids)

    def _attachments(self, pid, body):
        """`attachments` on a chat message, request, suggestion, proposal or comment: checked as an answer's, refused
        while Uploads is off; [] when left out or empty."""
        ids = _body(body).get("attachments")
        if ids is None or ids == []:
            return []
        if not isinstance(ids, list):
            raise _bad("attachments", "attachments must list upload ids, each once.")
        if not self.state["session"]["settings"]["uploads"]:
            raise DomainError(403, "uploads-off", "Uploads are off in this session.")
        return self._attachment_ids(pid, ids)

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
            q, card, late = self._card_vote_question(body, ref, backing=True)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot vote for your own answer.")
            qid = q["id"]
            self._mark_late(qid, pid, late)
            if on:
                self._unpass(qid, pid)
            if q["format"]["kind"] == "multi":  # any subset: a person backs as many others' own options as they like
                return self._back(qid, pid, card, on)
            votes = st["votes"].setdefault(qid, {})
            moved = False
            if on:
                moved = votes.get(pid) not in (None, ref)
                if q["format"]["kind"] == "choice":  # one pick: backing someone's own option moves it
                    for mine in [c for c in st["cards"][qid] if c["kind"] == "person" and c["pid"] == pid]:
                        if self._is_other(mine) or not (mine["text"] or "attachments" in mine):
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
        late = self._answerable(q)
        return q, self._card(q["id"], ref), late

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
            q, card, late = self._card_vote_question(body, ref)
            qid = q["id"]
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "That is your own answer.")
            self._mark_late(qid, pid, late)
            self._unpass(qid, pid)
            for mine in [c for c in st["cards"][qid] if c["kind"] == "person" and c["pid"] == pid]:
                self._clear_card(qid, mine)
            votes = st["votes"].setdefault(qid, {})
            moved = votes.get(pid) not in (None, ref)
            if votes.get(pid) != ref:
                votes[pid] = ref
                self._notify_vote(qid, card, pid)
            return {"moved": moved}

    def react(self, pid, body):
        """POST /api/react: `{qid, card, reaction, on}` turns one of thumbs, down, heart or idea on (`on`, the
        default) or off for the person on an answer of a gather question; `reaction: null` clears all of theirs. A
        person holds any of them at once, except thumbs and down: turning one on turns the other off. Decide
        questions take Disagree instead (`disagree`)."""
        ref = _ident(body, "card")
        reaction = _body(body).get("reaction")
        if reaction is not None and reaction not in REACTIONS:
            raise _bad("reaction", f"reaction must be one of {', '.join(REACTIONS)}, or null.")
        on = _bool(body, "on", default=True)
        with self._write_as(pid, "react") as st:
            q = self._question(body.get("qid"))
            if q["purpose"] != "gather":
                raise DomainError(409, "wrong-purpose", "Reactions are for gather questions; vote instead.")
            late = self._answerable(q)
            self._card(q["id"], ref)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot react to your own answer.")
            self._mark_late(q["id"], pid, late)
            by_card = st["reactions"].setdefault(q["id"], {})
            by = by_card.setdefault(ref, {})
            have = set() if reaction is None else set(by.get(pid, ())) - {reaction}
            if reaction is not None and on:
                have = (have - {OPPOSITE.get(reaction)}) | {reaction}
            mine = [r for r in REACTIONS if r in have]
            if mine:
                by[pid] = mine
            else:
                by.pop(pid, None)
            if not by:
                by_card.pop(ref)
            if not by_card:
                st["reactions"].pop(q["id"])
            return {"reactions": mine}

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
            late = self._answerable(q, late_on_lock=True)
            self._card(q["id"], ref)
            if ref_author(ref) == pid:
                raise DomainError(400, "cannot-vote-own", "You cannot disagree with your own answer.")
            self._mark_late(q["id"], pid, late)
            by_q = st.setdefault("disagreements", {})
            kept = [d for d in by_q.get(q["id"], []) if not (d["pid"] == pid and d["card"] == ref)]
            if on:
                kept.append({"pid": pid, "card": ref, "reason": reason, "at": self.now()})
            if kept:
                by_q[q["id"]] = kept
            else:
                by_q.pop(q["id"], None)
            locked = self._locked_card(q["id"])
            if locked is not None and ref == locked:  # a Disagree on a rejected alternative raises nothing
                raised = {e["by"] for _, e in self._reopened(q["id"])}
                if on and pid not in raised:
                    if not self._undo_take_back(q["id"], pid, reason):
                        self._decided(q["id"], "late-disagree", pid, card=ref, reason=reason)
                    self._flag(q["id"], {"kind": "possibly-reopened"})
                elif not on and raised and not any(d["pid"] in raised and d["card"] == locked for d in kept):
                    self._decided(q["id"], "withdrawn", pid)  # the last late Disagree on it went: it is no longer reopened
            return {"disagree": on}

    def _locked_card(self, qid):
        """The answer qid is locked on: the card it was locked on or its locked text was edited from, kept through a
        rewording; None when it is not locked, or its text came from a suggestion."""
        lk = self.state["locks"].get(qid)
        src = lk["source"] if lk else {}
        if src.get("kind") == "card":
            return src["card"]
        if src.get("kind") == "edited" and (src.get("from") or "").startswith(("p:", "c:", "o:")):
            return src["from"]
        if src.get("kind") == "edited" and src.get("from") is None:  # reworded: the log names the answer it rewords
            last = next((e for e in reversed(self.state.get("decisions", ())) if e["qid"] == qid and e["kind"] == "lock-change"), None)
            return last.get("card") if last else None
        return None

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

    def _decided(self, qid, kind, by, **fields):
        """Append one entry to the decision log (`decisions`, the owner's alone): a lock, a change to the locked
        text, an unlock, a poll closed or reopened, a late Disagree on a lock, the last such Disagree taken back
        (`withdrawn`), or the owner keeping the decision. Any
        entry but a late Disagree ends a possibly reopened decision, so the `possibly-reopened` flags it put on
        dependents go; returns how many went."""
        cleared = 0
        if kind != "late-disagree" and self._reopened(qid):
            for d in self.state["questions"]:
                kept = [f for f in d["needsReview"] if not (f["because"] == qid and f["why"] == {"kind": "possibly-reopened"})]
                cleared += len(d["needsReview"]) - len(kept)
                d["needsReview"] = kept
        log = self.state.setdefault("decisions", [])
        seq = 1 + max((e.get("seq", i) for i, e in enumerate(log)), default=-1)
        log.append({"at": self.now(), "qid": qid, "kind": kind, "by": by, "seq": seq, **fields})
        self._trim_decisions()
        return cleared

    def _undo_take_back(self, qid, pid, reason):
        """pid raises a Disagree again on qid's locked answer soon after their take-back ended its late Disagrees:
        drop that `withdrawn` entry rather than log a new pair. True when pid's own late Disagree is back in force;
        it moves to the end of the log with a new `seq`, time and reason, so the owner's Inbox row is unread again."""
        log = self.state.get("decisions", [])
        last = next((i for i in range(len(log) - 1, -1, -1) if log[i]["qid"] == qid), None)
        if last is None or log[last]["kind"] != "withdrawn" or log[last]["by"] != pid or self.now() - log[last]["at"] > DISAGREE_CHURN_WINDOW:
            return False
        del log[last]
        mine = next((i for i, e in self._reopened(qid) if e["by"] == pid), None)
        if mine is None:
            return False
        seq = 1 + max(e.get("seq", i) for i, e in enumerate(log))
        log.append({**log.pop(mine), "at": self.now(), "reason": reason, "seq": seq})
        return True

    def _trim_decisions(self):
        """Keep the log at MAX_DECISIONS, oldest first, sparing what a locked decision still reads: its late
        Disagrees in force and its last `lock-change`, which names the answer a reworded lock stands on."""
        log = self.state["decisions"]
        over = len(log) - MAX_DECISIONS
        if over <= 0:
            return
        keep = set()
        for qid in self.state["locks"]:
            keep.update(i for i, _ in self._reopened(qid))
            keep.update(i for i in [next((i for i in range(len(log) - 1, -1, -1) if log[i]["qid"] == qid and log[i]["kind"] == "lock-change"), None)] if i is not None)
        drop = set(sorted(range(len(log)), key=lambda i: (i in keep, i))[:over])
        log[:] = [e for i, e in enumerate(log) if i not in drop]

    def _reopened(self, qid):
        """(log index, entry) of each late Disagree logged on qid since its decision was last made, changed, unlocked or kept: while there
        is one, the owner's Inbox and the digest say the decision is possibly reopened."""
        out = []
        for i, e in enumerate(self.state.get("decisions", ())):
            if e["qid"] == qid:
                out = [*out, (i, e)] if e["kind"] == "late-disagree" else []
        return out

    def _lock_changed(self, q, text):
        prev = q.get("lockedText")
        q["lockedText"] = text
        if prev is not None and prev != text:
            return self._flag(q["id"], {"kind": "lock-changed"})
        return []

    def lock(self, pid, body):
        """POST /api/lock: no `card` is Lock top answer; with `card` it is Lock this one. A poll
        takes no `card`: Close poll freezes its counts and chooses no answer, tied or empty."""
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
            if q["purpose"] == "poll":
                if ref is not None:
                    raise DomainError(409, "wrong-purpose", "A poll closes as a whole; no single answer is locked.")
                self._answerable(q)
                st["locks"][qid] = {"at": now, "by": pid, "source": {"kind": "poll"}}
                self._decided(qid, "poll-close", pid)
                return {"closed": True, "flagged": []}
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
            st["locks"][qid] = {"at": now, "by": pid, "source": {"kind": "card", "card": target, "text": text, **_files(card), **edited}}
            self._decided(qid, "lock", pid, text=text)
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
            self._decided(q["id"], "poll-reopen" if q["purpose"] == "poll" else "unlock", pid)
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
            text, note = self._tokenize(pid, text), self._tokenize(pid, note, "note", MAX_NOTE)
            q = self._question(body.get("qid"))
            if q["id"] not in st["locks"]:
                r = self._round(q["round"])
                if r is None:
                    raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
                if r["status"]["kind"] == "open":
                    raise DomainError(409, "not-locked", "This question is open: answer it instead.")
            att = self._attachments(pid, body)
            sid = self._next("S")
            kept = st["suggestions"].setdefault(q["id"], [])
            kept.append({"id": sid, "pid": pid, "text": text, "note": note, "at": now, "status": {"kind": "open"}, **({"attachments": att} if att else {})})
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
                if q["purpose"] == "poll":
                    raise DomainError(409, "wrong-purpose", "A closed poll keeps its counts; no answer replaces them.")
                st["locks"][q["id"]] = {"at": now, "by": pid, "source": {"kind": "suggestion", "suggestion": sid, "text": s["text"]}}
                s["status"] = {"kind": "used", "at": now}
                self._decided(q["id"], "lock-change", pid, text=s["text"])
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
            text = self._tokenize(pid, text)
            q = self._question(body.get("qid"))
            if q["id"] not in st["locks"]:
                raise DomainError(409, "not-locked", "This question is not locked.")
            if q["purpose"] == "poll":
                raise DomainError(409, "wrong-purpose", "A closed poll keeps its counts; it has no locked text to edit.")
            used = None
            if source is not None:
                if source.startswith(("p:", "c:", "o:")):
                    self._card(q["id"], source)
                else:
                    used = self._suggestion(q["id"], source)
            reworded = self._locked_card(q["id"]) if source is None else None  # new words for the same answer
            st["locks"][q["id"]] = {"at": now, "by": pid, "source": {"kind": "edited", "text": text, "from": source}}
            if used is not None and used["status"]["kind"] == "open":
                used["status"] = {"kind": "used", "at": now}
            self._decided(q["id"], "lock-change", pid, text=text, **({"card": reworded} if reworded else {}))
            return {"flagged": self._lock_changed(q, text)}

    def keep_decision(self, pid, body):
        """POST /api/decision/keep: the owner keeps a decision a late Disagree may have reopened. The Inbox item goes,
        and so do the `possibly-reopened` flags it put on dependents; the log records it. A newer late Disagree raises
        the item again."""
        with self._tx() as st:
            self._owner(pid)
            q = self._question(_body(body).get("qid"))
            if q["id"] not in st["locks"] or not self._reopened(q["id"]):
                raise DomainError(409, "not-reopened", "No late Disagree has reopened this decision.")
            return {"cleared": self._decided(q["id"], "kept", pid)}

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
            text = self._tokenize(pid, text)
            if sum(1 for p in self.state["proposals"] if p["pid"] == pid and p["status"]["kind"] == "new") >= MAX_MY_PROPOSALS:
                raise DomainError(429, "too-many-pending", f"You have {MAX_MY_PROPOSALS} proposals waiting already.", field="text")
            prop = self._new_proposal(pid, text, {"kind": "direct"}, self._attachments(pid, body))
            self._notify_mentions(text, pid, "in a proposal")
        self._wrote(pid, "propose", now)
        return {"id": prop["id"]}

    def _new_proposal(self, author, text, via, att=()):
        if len(self.state["proposals"]) >= MAX_PROPOSALS:
            raise DomainError(429, "too-many-proposals", "This session holds no more proposals.")
        prop = {"id": self._next("P"), "pid": author, "text": text, "at": self.now(), "via": via, "status": {"kind": "new"}, **({"attachments": list(att)} if att else {})}
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
                out = self._proposal_question(pid, prop, n)
            elif action == "park":
                prop["status"] = {"kind": "parked", "by": pid}
                self._notify(prop["pid"], "proposal", "Your proposal was parked by a moderator.", actor=pid)
            elif action == "restore":
                prop["status"] = {"kind": "new"}
            else:
                prop["status"] = {"kind": "later", "reason": reason or "Off this session's goal."}
                self._notify(prop["pid"], "proposal", "Your proposal was moved to Later.", actor=pid, body=prop["status"]["reason"])
            return {"status": prop["status"]["kind"], **out}

    def _proposal_question(self, pid, prop, n):
        """Make a proposal a question in round `n`, which has room, and tell its author: Make it a question's one way."""
        q = {
            "id": self._next_qid(),
            "text": prop["text"],
            "alternatives": [],
            "dependsOn": [],
            "round": n,
            "purpose": "gather",
            "format": {"kind": "text"},
            "answerScope": "person",
            "references": [],
            "origin": {"kind": "host", "proposal": prop["id"], "by": pid},
            "needsReview": [],
        }
        self._add_question(q)
        prop["status"] = {"kind": "question", "question": q["id"]}
        self._notify(prop["pid"], "proposal", f"Your proposal became question {q['id']}, in round {n}.", actor=pid, qid=q["id"])
        return {"question": q["id"], "round": n}

    def approve_proposals(self, pid, body):
        """POST /api/proposal/all: the owner's Approve all, `{ids}`, the new proposals their confirm counted, each made a
        question in the next round as Make it a question makes one. All or none: a proposal no longer new, or more
        than the round has room for, refuses the lot, so one that arrived after the confirm is never placed unseen."""
        ids = _body(body).get("ids")
        if not isinstance(ids, list) or not 0 < len(ids) <= MAX_PROPOSALS or not all(isinstance(i, str) for i in ids) or len(set(ids)) < len(ids):
            raise _bad("ids", f"ids lists 1 to {MAX_PROPOSALS} proposals, each once.")
        with self._tx():
            self._owner(pid)
            props = [self._proposal(i) for i in ids]
            for prop in props:
                if prop["status"]["kind"] != "new":
                    raise DomainError(409, "wrong-status", f"Proposal {prop['id']} is {prop['status']['kind']}.", status=prop["status"]["kind"])
            n = self._next_round_n()
            room = MAX_ROUND - self._round_size(n)
            if len(props) > room:
                raise DomainError(409, "round-full", f"Round {n} has room for {max(room, 0)} more questions, not {len(props)}.", room=max(room, 0))
            return {"round": n, "questions": [self._proposal_question(pid, prop, n)["question"] for prop in props]}

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
            text = self._tokenize(pid, text)
            att = self._attachments(pid, body)
            msg = {"id": self._next("M"), "pid": pid, "text": text, "at": now, **({"attachments": att} if att else {})}
            skip = ()
            if reply_to is not None:
                to = next((m for m in st["chat"] if m["id"] == reply_to and self._active(m["pid"])), None)
                if to is None:
                    raise DomainError(404, "not-found", "The message you replied to is gone.")
                msg["replyTo"] = {"id": to["id"], "pid": to["pid"], "excerpt": clip(one_line(to["text"]), MAX_EXCERPT), **({"claude": True} if "claude" in to else {})}
                if "claude" not in to:  # Claude's answer is written as the host's message, but it is not the host's to hear about
                    self._notify(to["pid"], "reply", "replied to your message.", actor=pid, by=pid, body=clip(one_line(text), 160), msg=msg["id"])
                    skip = (to["pid"],)
            refused = None
            if ASK_CLAUDE.search(text):  # after tokenizing, as in a comment: a person called Claude is their mention
                try:  # a general ask: no question, owner-gated as any guest request; Claude's answer replies to this message
                    msg["request"] = self._new_request(pid, None, "ask", text, "host", now, msg=msg["id"], att=att)["id"]
                except DomainError as e:  # too soon or too many waiting: the message still posts, without a request
                    if e.code not in ("slow-down", "too-many-pending"):
                        raise
                    refused = e
            st["chat"].append(msg)
            del st["chat"][:-MAX_CHAT]
            self._notify_mentions(text, pid, "in chat", skip=skip, msg=msg["id"])
        self._wrote(pid, "chat", now)
        if "request" in msg:
            self._wrote(pid, "request", now)
        if refused:
            return {"id": msg["id"], "requestRefused": refused.code, "message": f"Posted, but not sent to Claude: {refused.message}"}
        return {"id": msg["id"], **({"request": msg["request"]} if "request" in msg else {})}

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
                    None if "claude" in msg else msg["pid"],  # Claude's answer has no author to tell
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
            self._touch_chat(mid)
        self._wrote(pid, route, now)
        self._wrote(pid, "chat-react", now)
        return {"id": mid, "emoji": emoji, "on": on}

    def _touch_chat(self, mid):
        """A message's reactions or forward changed: the snapshot's chatTouched moves when it is older than the window."""
        self._chat_touches += 1
        self._chat_touch[mid] = self._chat_touches

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
            if "claude" in msg:
                raise DomainError(409, "wrong-status", "Claude's answer is not anyone's proposal.", status="claude")
            prop = self._new_proposal(msg["pid"], msg["text"], {"kind": "chat", "message": mid, "by": pid}, msg.get("attachments", ()))
            msg["proposed"] = prop["id"]
            self._touch_chat(mid)
            self._notify(msg["pid"], "proposal", "Your chat message became a proposal.", actor=pid, msg=mid)
            return {"proposal": prop["id"]}

    def _guest_questions(self):
        """The questions every guest is sent, built once per rev (every page polls)."""
        st = self.state
        if not (self._guest_q_cache and self._guest_q_cache[0] == st["rev"]):
            self._guest_q_cache = (st["rev"], _guest_questions([_question_view(q) for q in st["questions"]], prototype_tiers(st["session"]["settings"])))
        return self._guest_q_cache[1]

    def asset_hidden(self, pid, name):
        """Whether /assets/<name> is off for `pid`: an html file, which only prototype variants hold, to anyone but the
        owner while the session's HTML snapshots are off. Pictures are never hidden here: option pictures, references
        and confirm questions share them."""
        with self._lock:
            return pid != HOST and name.endswith(".html") and "snapshot" not in prototype_tiers(self.state["session"]["settings"])

    # -- live prototypes ------------------------------------------------------------------------
    # An entry `add-live` made waits (pending) until the owner's Approve on the page. server.py starts it outside the
    # state lock: approve_live marks it starting and hands back the entry, the server's live starter starts it, and
    # live_started sets it running with the https origin the starter answered (or live_start_failed puts it back).
    # Stop, the live tier turned off and the session ended each end it, keeping no url; server.py then stops whatever
    # its starter began for an entry no longer starting or running (live_status).

    def _live_on(self):
        return "live" in prototype_tiers(self.state["session"]["settings"])

    def _live(self, lid):
        if not isinstance(lid, str) or not LIVE_ID.fullmatch(lid):
            raise _bad("id", "id names a live prototype, like L1.")
        e = next((e for e in self.state.get("lives", []) if e["id"] == lid), None)
        if e is None:
            raise DomainError(404, "not-found", f"No live prototype {lid}.")
        return e

    def _end_live(self, e, reason):
        old = e["status"]
        e["status"] = {"kind": "ended", "endedAt": self.now(), "reason": reason, **{k: old[k] for k in ("approvedAt", "attested") if k in old}}

    def _end_lives(self, reason):
        for e in self.state.get("lives", []):
            if e["status"]["kind"] != "ended":
                self._end_live(e, reason)

    def approve_live(self, pid, body):
        """POST /api/live/approve {id, attest?}: the owner lets a pending live prototype start. A port target (a server
        the owner runs) needs `attest: true`, the owner's word that it runs on sample data only, with writes stubbed and
        no credentials in its environment; the entry keeps it."""
        _body(body)
        with self._tx():
            self._owner(pid)
            if not self._live_on():
                raise DomainError(403, "live-off", "Live prototypes are off in this session.")
            if self._ended():
                raise DomainError(409, "wrong-status", "The session has ended.", status="ended")
            e = self._live(body.get("id"))
            if e["status"]["kind"] != "pending":
                raise DomainError(409, "wrong-status", f"Live prototype {e['id']} is {e['status']['kind']}.", status=e["status"]["kind"])
            port = e["target"]["kind"] == "port"
            if port:
                self._live_port(e["target"]["port"])  # the session's own ports can move on a restart: check again
            if port and body.get("attest") is not True:
                raise _bad("attest", "A server on a port starts only once you confirm it runs on sample data only, with writes stubbed and no credentials in its environment.")
            e["status"] = {"kind": "starting", "approvedAt": self.now(), **({"attested": True} if port else {})}
            return {"live": e["id"], "entry": copy.deepcopy(e)}

    def live_started(self, lid, url):
        """The server's live starter started `lid` at `url`: running, when it is still starting; False when it ended
        meanwhile (the server then stops it). A url that is not an https origin is refused, 502."""
        with self._lock:
            if self._live(lid)["status"]["kind"] != "starting":
                return False
        if not (isinstance(url, str) and len(url) <= MAX_LIVE_URL and LIVE_URL.fullmatch(url)):
            raise DomainError(502, "live-failed", "The live prototype did not start: its server answered no https address.")
        with self._tx():
            e = self._live(lid)
            if e["status"]["kind"] != "starting":
                return False
            e["status"] = {**e["status"], "kind": "running", "startedAt": self.now(), "url": url}
            return True

    def live_start_failed(self, lid):
        """The start of `lid` failed: it waits for Approve again, unless it ended meanwhile."""
        with self._lock:
            if self._live(lid)["status"]["kind"] != "starting":
                return
            with self._tx():
                self._live(lid)["status"] = {"kind": "pending"}

    def live_status(self, lid):
        """`lid`'s status kind, or None for no such entry."""
        with self._lock:
            return next((e["status"]["kind"] for e in self.state.get("lives", []) if e["id"] == lid), None)

    def stop_live(self, pid, body):
        """POST /api/live/stop {id}: the owner ends a live prototype, started or not."""
        _body(body)
        with self._tx():
            self._owner(pid)
            e = self._live(body.get("id"))
            if e["status"]["kind"] == "ended":
                raise DomainError(409, "wrong-status", f"Live prototype {e['id']} has ended.", status="ended")
            self._end_live(e, "stopped")
            return {"live": e["id"], "status": "ended"}

    def _lives_view(self, owner, questions):
        """The snapshot's `lives`, or None when the session has none. The owner gets each entry whole, with `url`: the
        running origin, or, for a pending or starting port, that port on 127.0.0.1 to look at first. Anyone else gets
        only the entries `questions` (as they see them) link, as {id, label, status: {kind}}, with `url` only while it
        runs: never a target, a note or the url of one the owner has not approved."""
        lives = self.state.get("lives")
        if not lives:
            return None
        if owner:
            def local(e):
                if e["status"]["kind"] == "running":
                    return {"url": e["status"]["url"]}
                if e["target"]["kind"] == "port" and e["status"]["kind"] in ("pending", "starting"):
                    return {"url": f"http://127.0.0.1:{e['target']['port']}"}
                return {}
            return [{**copy.deepcopy(e), **local(e)} for e in lives]
        linked = {v["live"]["id"] for q in questions if q["format"]["kind"] == "prototype" for v in q["format"]["variants"] if "live" in v}
        return [{"id": e["id"], "label": e["label"], "status": {"kind": e["status"]["kind"]}, **({"url": e["status"]["url"]} if e["status"]["kind"] == "running" else {})}
                for e in lives if e["id"] in linked]

    def is_prototype(self, qid):
        """GET /proto/<qid> serves the prototype page only for a prototype question."""
        with self._lock:
            return any(q["id"] == qid and q["format"]["kind"] == "prototype" for q in self.state["questions"])

    def annotate(self, pid, body):
        """POST /api/annotate: a note pinned to an element of one prototype variant. `anchor.selector` is the
        element's path (SELECTOR); `anchor.rect` is the element's box in percent of the variant's reference box,
        used when the element is gone: an `html` variant's whole scrollable page (documentElement scrollWidth by
        scrollHeight when the note was pinned), or an image variant's image."""
        text = _text(body, "text")
        variant = _ident(body, "variant")
        anchor = _body(body).get("anchor")
        if not isinstance(anchor, dict) or set(anchor) != {"selector", "rect"} or not isinstance(anchor["selector"], str):
            raise _bad("anchor", "anchor must be {selector, rect}.")
        if len(anchor["selector"]) > MAX_SELECTOR or not SELECTOR.fullmatch(anchor["selector"]):
            raise _bad("anchor.selector", "anchor.selector must be an element path like body > div:nth-of-type(2) > button.")
        rect = _rect(anchor["rect"], "anchor.rect")
        now = self.now()
        with self._tx() as st:
            self._writer(pid)
            self._throttle(pid, "annotate", now)
            text = self._tokenize(pid, text)
            q = self._question(body.get("qid"))
            if q["format"]["kind"] != "prototype":
                raise _bad("qid", "Notes pin to prototype questions only.")
            if variant not in self._options(q):
                raise _bad("variant", "No such variant on this question.")
            if self._round(q["round"]) is None:
                raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
            if sum(1 for a in st["annotations"] if a["pid"] == pid and a["qid"] == q["id"]) >= MAX_MY_NOTES:
                raise DomainError(400, "too-long", f"You can pin at most {MAX_MY_NOTES} notes on one prototype.", field="annotations", max=MAX_MY_NOTES)
            if len(st["annotations"]) >= MAX_ANNOTATIONS:
                raise DomainError(409, "notes-full", f"This session holds at most {MAX_ANNOTATIONS} notes.", max=MAX_ANNOTATIONS)
            aid = self._next("A")
            st["annotations"].append(
                {"id": aid, "pid": pid, "qid": q["id"], "variant": variant, "at": now, "text": text, "anchor": {"selector": anchor["selector"], "rect": rect}}
            )
            self._notify_mentions(text, pid, f"in a note on question {q['id']}", qid=q["id"])
        self._wrote(pid, "annotate", now)
        return {"id": aid}

    # -- discussions -------------------------------------------------------------------------
    # Each question's Discussion: plain-text comments anyone who may write adds; its author edits or deletes their own,
    # the owner hides any (its author still sees it, marked, as with answers). "@Claude" in a new comment also files an
    # ask request on the question, owner-gated as any guest request. discussionSeen holds when each person last opened
    # a question's Discussion; comments by others since then are new to them.

    def _comment_target(self, body):
        """(question, comment) a Discussion route names: an existing comment of an active author."""
        q = self._question(_body(body).get("qid"))
        cid = _ident(body, "id")
        c = next((c for c in self.state["discussions"].get(q["id"], []) if c["id"] == cid and self._active(c["pid"])), None)
        if c is None:
            raise DomainError(404, "not-found", "No such comment.")
        return q, c

    def _own_comment(self, pid, body):
        """A comment its author edits or deletes; another person's reads as no such comment."""
        q, c = self._comment_target(body)
        if c["pid"] != pid:
            raise DomainError(404, "not-found", "No such comment.")
        return q, c

    def _drop_comment_excerpts(self, cid):
        for lst in self.state["notifications"].values():
            for n in lst:
                if n.get("comment") == cid:
                    n.pop("body", None)

    def comment(self, pid, body):
        """POST /api/discussion: `{qid, text}` adds a comment to the question's Discussion and marks it read for its
        author. "@Claude" in it also makes an ask request with its text (the comment then names it as `request`)."""
        text = _text(body, "text")
        with self._write_as(pid, "discussion") as st:
            q = self._question(body.get("qid"))
            if self._round(q["round"]) is None:
                raise DomainError(409, "round-not-open", f"Round {q['round']} has not opened yet.")
            lst = st["discussions"].setdefault(q["id"], [])
            if sum(1 for c in lst if c["pid"] == pid) >= MAX_MY_COMMENTS:  # hiding one gives no room back
                raise DomainError(409, "too-many-comments", f"You can leave at most {MAX_MY_COMMENTS} comments on one question.", max=MAX_MY_COMMENTS)
            # Only comments everyone sees fill a Discussion, so the owner's Hide clears room.
            if sum(1 for c in lst if self._comment_shown(c)) >= MAX_COMMENTS:
                raise DomainError(409, "discussion-full", f"A question's Discussion holds at most {MAX_COMMENTS} comments.", max=MAX_COMMENTS)
            if sum(1 for x in st["discussions"].values() for c in x if self._comment_shown(c)) >= MAX_ALL_COMMENTS:
                raise DomainError(409, "discussion-full", f"This session holds at most {MAX_ALL_COMMENTS} comments.", max=MAX_ALL_COMMENTS)
            text = self._tokenize(pid, text)
            att = self._attachments(pid, body)
            asks = bool(ASK_CLAUDE.search(text))  # after tokenizing: "@Claude" naming a person called Claude is their mention
            now = self.now()
            c = {"id": self._next("D"), "pid": pid, "text": text, "at": now, **({"attachments": att} if att else {})}
            refused = None
            if asks:
                try:
                    c["request"] = self._new_request(pid, q, "ask", text, "host", now, att=att)["id"]
                except DomainError as e:  # too soon or too many waiting: the comment still posts, without a request
                    if e.code not in ("slow-down", "too-many-pending"):
                        raise
                    refused = e
            mark = st["discussionSeen"].get(pid, {}).get(q["id"], 0.0)
            if not any(x["pid"] != pid and x["at"] > mark and self._comment_visible(pid, x) for x in lst):
                st["discussionSeen"].setdefault(pid, {})[q["id"]] = now  # posting marks read nothing the author has not seen
            lst.append(c)
            mentioned = self._mentioned(text, pid)
            self._notify_mentions(text, pid, f"in the Discussion on question {q['id']}", qid=q["id"], comment=c["id"])
            for p in dict.fromkeys(x["pid"] for x in lst[:-1]):  # the people already in this Discussion hear of it
                if p not in mentioned:
                    old = next((n for n in reversed(st["notifications"].get(p, [])) if n.get("rollup", {}).get("key") == "disc:" + q["id"] and not n["read"]), None)
                    k = old["rollup"]["n"] + 1 if old else 1
                    self._notify(p, "discussion", f"{k} new comment{'' if k == 1 else 's'} in the Discussion on question {q['id']}.", actor=pid, rollup="disc:" + q["id"], qid=q["id"], comment=c["id"])
            if "request" in c:
                self._wrote(pid, "request", now)
            if refused:
                return {"id": c["id"], "requestRefused": refused.code, "message": f"Posted, but not sent to Claude: {refused.message}"}
            return {"id": c["id"], **({"request": c["request"]} if "request" in c else {})}

    def _comment_shown(self, c):
        return "hidden" not in c and self._active(c["pid"])

    def _comment_visible(self, pid, c):
        """Whether pid reads c: an active author's, and a hidden one only for the owner and its author."""
        return self._active(c["pid"]) and ("hidden" not in c or pid in (HOST, c["pid"]))

    def edit_comment(self, pid, body):
        """POST /api/discussion/edit: `{qid, id, text}`, the comment's author only; the same text writes nothing. A
        hidden comment stays hidden. Only mentions the edit adds notify; one whose "@Claude" filed a request is refused."""
        text = _text(body, "text")
        with self._lock:
            self._writer(pid)
            self._throttle(pid, "discussion-edit", self.now())
            _, c = self._own_comment(pid, body)
            if "request" in c:
                raise DomainError(409, "sent-to-claude", "This comment went to Claude as a request, so its text stays as sent. Delete it or add a new comment.")
            if self._tokenize(pid, text) == c["text"]:
                return {"id": c["id"], "edited": False}
        with self._write_as(pid, "discussion-edit"):
            q, c = self._own_comment(pid, body)
            before, c["text"] = c["text"], self._tokenize(pid, text)
            c["edited"] = self.now()
            self._drop_comment_excerpts(c["id"])
            if "hidden" not in c:  # a hidden comment's text reaches no one through a notice
                self._notify_mentions(c["text"], pid, f"in the Discussion on question {q['id']}", before=before, qid=q["id"], comment=c["id"])
            return {"id": c["id"], "edited": True}

    def delete_comment(self, pid, body):
        """POST /api/discussion/delete: `{qid, id}`, the comment's author only. A request it filed stays as it is."""
        with self._write_as(pid, "discussion-delete") as st:
            q, c = self._own_comment(pid, body)
            st["discussions"][q["id"]].remove(c)
            if not st["discussions"][q["id"]]:
                st["discussions"].pop(q["id"])
            self._drop_comment_excerpts(c["id"])
            return {"id": c["id"], "deleted": True}

    def hide_comment(self, pid, body):
        """POST /api/discussion/hide: `{qid, id, on}`, owner only. A hidden comment leaves every other person's view
        and the digest; its author still sees it, marked, and a request it filed that still waits is declined. Asking for
        the state it is in writes nothing."""
        on = _bool(body, "on")
        with self._lock:
            self._owner(pid)
            self._throttle(pid, "discussion-hide", self.now())
            _, c = self._comment_target(body)
            if ("hidden" in c) == on:
                return {"id": c["id"], "hidden": on}
        with self._write_as(pid, "discussion-hide", check=self._owner):
            _, c = self._comment_target(body)
            if on:
                c["hidden"] = {"by": pid, "at": self.now()}
                self._drop_comment_excerpts(c["id"])
                r = next((r for r in self.state["requests"] if r["id"] == c.get("request") and r["status"]["kind"] == "pending"), None)
                if r is not None:  # what the owner hid does not go on to Claude: as the owner's Decline
                    self._decline(r, pid)
            else:
                c.pop("hidden", None)
            return {"id": c["id"], "hidden": on}

    def react_comment(self, pid, body):
        """POST /api/discussion/react: `{qid, id, emoji, on}`, chat's emoji and caps on a comment everyone sees; one
        reaction a second per comment and CHAT_REACT_ANY across them, as in chat. A no-op writes nothing."""
        emoji = _choice(body, "emoji", CHAT_EMOJI)
        on = _bool(body, "on")
        cid = _ident(body, "id")
        route = f"discussion-react:{cid}"
        now = self.now()
        with self._lock:
            self._writer(pid)
            self._throttle(pid, "discussion-react", now, CHAT_REACT_ANY)
            self._throttle(pid, route, now)
            _, c = self._comment_target(body)
            if "hidden" in c:
                raise DomainError(404, "not-found", "No such comment.")
            if (pid in c.get("reactions", {}).get(emoji, [])) == on:
                return {"id": cid, "emoji": emoji, "on": on}
        with self._write_as(pid, route):
            _, c = self._comment_target(body)
            reactions = c.setdefault("reactions", {})
            pids = reactions.get(emoji, [])
            if on and pid not in pids:
                if emoji not in reactions and len(reactions) >= MAX_CHAT_EMOJI:
                    raise DomainError(409, "reaction-cap", f"A comment takes at most {MAX_CHAT_EMOJI} different emoji.", max=MAX_CHAT_EMOJI)
                if sum(1 for ps in reactions.values() if pid in ps) >= MAX_MY_CHAT_EMOJI:
                    raise DomainError(409, "reaction-cap", f"You can put at most {MAX_MY_CHAT_EMOJI} emoji on one comment.", max=MAX_MY_CHAT_EMOJI)
                reactions[emoji] = [*pids, pid]
            elif not on and pid in pids:
                pids.remove(pid)
                if not pids:
                    reactions.pop(emoji)
            if not reactions:
                c.pop("reactions")
        self._wrote(pid, "discussion-react", now)
        return {"id": cid, "emoji": emoji, "on": on}

    def read_discussion(self, pid, body):
        """POST /api/discussion/read: `{qid, at}`, this person opened the question's Discussion and saw the comments up
        to `at` (the newest the page showed; never later than the newest they can see). Allowed while ended; a read that
        moves nothing writes nothing."""
        at = _body(body).get("at")
        if not (isinstance(at, (int, float)) and not isinstance(at, bool) and math.isfinite(at) and at >= 0):
            raise _bad("at", "at is the time of the newest comment the page showed.")
        with self._lock:
            self._person(pid)
            self._throttle(pid, "discussion-read", self.now())
            q = self._question(body.get("qid"))
            newest = max((c["at"] for c in self.state["discussions"].get(q["id"], []) if self._comment_visible(pid, c)), default=0.0)
            mark = min(float(at), newest)
            if mark <= self.state["discussionSeen"].get(pid, {}).get(q["id"], 0.0):
                return {"qid": q["id"], "read": False}
        with self._write_as(pid, "discussion-read", check=self._person) as st:
            seen = st["discussionSeen"].setdefault(pid, {})
            seen[q["id"]] = max(mark, seen.get(q["id"], 0.0))
            return {"qid": q["id"], "read": True}

    def _comment_view(self, c, active):
        out = {k: v for k, v in c.items() if k != "reactions"}
        reactions = {e: [p for p in ps if p in active] for e, ps in c.get("reactions", {}).items()}
        reactions = {e: ps for e, ps in reactions.items() if ps}
        return {**out, "reactions": reactions} if reactions else out

    def _discussions_for(self, pid, active):
        """Each question's comments this viewer reads: an active author's, and hidden ones only for the owner and,
        for their own, the author (each with `hidden`)."""
        out = {}
        for qid, lst in self.state["discussions"].items():
            shown = [self._comment_view(c, active) for c in lst if self._comment_visible(pid, c)]
            if shown:
                out[qid] = shown
        return out


    # -- requests and results ----------------------------------------------------------------

    def _request(self, rid, *, runner=None, owner_pid=None):
        r = next((r for r in self.state["requests"] if r["id"] == rid), None)
        if r is None or (runner and r["runner"] != runner) or (owner_pid and r["pid"] != owner_pid):
            raise DomainError(404, "no-such-request", f"No request {rid}.")
        return r

    def request(self, pid, body):
        """POST /api/request: ask Claude; waits in the owner's queue (`runner: self` runs on the requester's Claude).
        `scope: "session"` in place of `qid` asks about the whole session, on the host's Claude only."""
        kind = _choice(body, "kind", REQUEST_KINDS)
        text = _text(body, "text")
        runner = _choice(body, "runner", ("host", "self"), optional=True) or "host"
        general = _choice(body, "scope", (GENERAL,), optional=True) is not None
        audience = _choice(body, "audience", ("everyone", "me"), optional=True) or "everyone"
        if audience == "me" and runner == "self":
            raise _bad("audience", "Your own Claude's answer already shows only to you and the host until the host shares it.")
        if general and _body(body).get("qid") is not None:
            raise _bad("qid", "A request about the whole session names no question.")
        if general and runner == "self":
            raise _bad("runner", "A request about the whole session runs on the host's Claude.")
        if runner == "self" and _body(body).get("attachments"):
            raise _bad("attachments", "Your own Claude cannot read files sent to the host.")
        now = self.now()
        with self._tx():
            self._writer(pid)
            text = self._tokenize(pid, text)
            q = None if general else self._question(body.get("qid"))
            rid = self._new_request(pid, q, kind, text, runner, now, audience=audience, att=self._attachments(pid, body))["id"]
            if runner == "host":
                self._notify_mentions(text, pid, f"in a request {'on question ' + q['id'] if q else 'about the session'}", qid=q and q["id"])
        self._wrote(pid, "request", now)
        return {"id": rid}

    def _new_request(self, pid, q, kind, text, runner, now, msg=None, audience="everyone", att=()):
        """A request pid makes on q, or about the whole session when q is None (no qid): one a second on the "request"
        route, which the caller records once it commits; past MAX_PENDING_REQUESTS refused; the host's own runs now, a
        guest's waits for Run. `msg`: the chat message whose "@Claude" filed it. `audience: me` (Just me): its answer
        shows to its asker and the owner until one of them shares it. `att`: the uploads it carries, which Claude reads."""
        st = self.state
        self._throttle(pid, "request", now)
        pending = sum(1 for r in st["requests"] if r["pid"] == pid and (r["status"]["kind"] == "pending" or (r["runner"] == "self" and r["status"]["kind"] == "running")))
        if pending >= MAX_PENDING_REQUESTS:
            raise DomainError(429, "too-many-pending", f"You have {MAX_PENDING_REQUESTS} requests waiting already.")
        rid = self._next("R")
        st["requests"].append(
            {"id": rid, "pid": pid, **({"qid": q["id"]} if q else {}), **({"msg": msg} if msg else {}), **({"audience": "me"} if audience == "me" else {}),
             "at": now, "kind": kind, "text": text, "edited": False, "runner": runner, "status": {"kind": "pending"}, **({"attachments": list(att)} if att else {})}
        )
        r = st["requests"][-1]
        if runner == "host" and pid == HOST:  # the host's own request needs no Run: it reaches Claude now
            self._run([r])
        self._seen_now(pid, rid)  # asking is not news to the asker: the Inbox item starts read
        return r

    def act_on_request(self, pid, body):
        """POST /api/request/act: edit, decline, fail, rerun one request; run the ids the owner saw; publish, discard or
        take down (`takedown`) a result. `move`, its asker's or the owner's, puts one request and its result on `qid` or
        about the whole session (`scope: session`)."""
        action = _choice(body, "action", ("edit", "decline", "fail", "rerun", "run", "publish", "discard", "takedown", "move"))
        if action == "move":
            with self._write_as(pid, "request-move"):
                return self._move_request(pid, body)
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
            if action in ("publish", "discard", "takedown"):
                return self._act_on_result(pid, _ident(body, "id"), action)
            r = self._request(_ident(body, "id"), runner="host")
            status = r["status"]["kind"]
            allowed = {"edit": ("pending",), "decline": ("pending",), "fail": ("running",), "rerun": ("running", "failed")}[action]
            if status not in allowed:
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {status}.", status=status)
            if action == "edit":
                text = self._tokenize(r["pid"], _text(body, "text"))  # as its author, as edit_card does
                if text != r["text"]:
                    r["text"], r["edited"] = text, True
            elif action == "decline":
                self._decline(r, pid)
            elif action == "fail":
                r["status"] = {"kind": "failed", "at": now, "reason": "Cancelled by the owner.", "cancelled": True}
                self._event("request-cancelled", request=r["id"])
                self._notify(r["pid"], "request", f"Your request {_on(r)} was cancelled.", actor=pid, qid=r.get("qid"))
            else:
                self._run([r])
                self._unseen(HOST, "fail:" + r["id"])  # a later failure waits on the owner again
            return {"id": r["id"], "status": r["status"]["kind"]}

    def _move_request(self, pid, body):
        """Move a request, and its result with it; another person's request reads as 404. A running one stays put: Claude's
        answer names where it was sent."""
        r = self._request(_ident(body, "id"), owner_pid=None if pid == HOST else pid)
        general = _choice(body, "scope", (GENERAL,), optional=True) is not None
        if general and _body(body).get("qid") is not None:
            raise _bad("qid", "A request about the whole session names no question.")
        if general and r["runner"] == "self":
            raise _bad("scope", "A request about the whole session runs on the host's Claude.")
        to = None if general else self._question(body.get("qid"))["id"]
        if r.get("qid") == to:
            raise DomainError(409, "same-place", f"Request {r['id']} is {_on(r)} already.")
        if r["status"]["kind"] == "running":
            raise DomainError(409, "wrong-status", f"Request {r['id']} is running.", status="running")
        if pid != HOST and r["runner"] == "host" and r["status"]["kind"] != "pending":
            raise DomainError(409, "taken-up", "The host already took up this request, so only the host can move it.", status=r["status"]["kind"])
        key, results = r.get("qid", GENERAL), self.state["results"]
        res = next((x for x in results.get(key, ()) if x["request"] == r["id"]), None)
        if res and any(res["id"] in c.get("cites", ()) for c in _answers(self.state["cards"])):
            raise DomainError(409, "cited", "This answer is cited in someone's answer, so it stays where it is.")
        if res:
            results[key].remove(res)
            if not results[key]:
                results.pop(key)
            results.setdefault(to or GENERAL, []).append(res)
        for x in (r, res) if res else (r,):
            x.pop("qid", None)
            if to:
                x["qid"] = to
        if res and res["published"]:
            if pid == HOST:
                self._claude_says(res, r)  # shared on the whole session now: Claude's chat message, as a Share posts
            else:  # the owner shared it where it was: moved by its asker, it waits on the owner's Share again
                res["published"] = False
                res.pop("publishedAt", None)
                self._unseen(HOST, "share:" + res["id"])
        if pid != HOST:
            self._unseen(HOST, "run:" + r["id"])  # the owner reads where it went before pressing Run
        if pid != r["pid"]:
            self._notify(r["pid"], "request", f"Your request moved {_on(r)}.", actor=pid, qid=to)
        return {"id": r["id"], **({"qid": to} if to else {"scope": GENERAL})}

    def _decline(self, r, by):
        r["status"] = {"kind": "declined", "at": self.now()}
        self._notify(r["pid"], "request", f"Your request {_on(r)} was declined.", actor=by, qid=r.get("qid"))

    def _run(self, reqs):
        st = self.state
        ev = self._event(
            "request-run",
            requests=[{"id": r["id"], **self._run_where(r), "kind": r["kind"], "text": r["text"], **({"attachments": list(r["attachments"])} if "attachments" in r else {})} for r in reqs],
        )
        for r in reqs:
            r["status"] = {"kind": "running", "since": self.now(), "eventSeq": ev["seq"]}
        return st

    def _run_where(self, r):
        """Where a run request was written, for Claude: its question, or `scope: session` with no qid, and `from: chat`
        when a chat message's "@Claude" filed it (its answer then replies in chat)."""
        if "qid" in r:
            return {"qid": r["qid"], "question": self._question(r["qid"])["text"]}
        return {"scope": GENERAL, **({"from": "chat"} if "msg" in r else {})}

    def _from_active(self, res):
        """A result is the host's, or its guest is still in: a removed guest's own Claude's results leave every view."""
        return res["by"]["kind"] != "guest-claude" or self._active(res["by"]["pid"])

    def _result_shown(self, res):
        """Everyone sees it: published, and not from a removed guest's own Claude."""
        return res["published"] and self._from_active(res)

    def _asker(self, res, askers=None):
        """Who asked for a result: its guest's own Claude's guest, else its request's author; None when no request asked.
        `askers`: request id -> pid, built once by a caller that looks at many results."""
        if res["by"]["kind"] == "guest-claude":
            return res["by"]["pid"]
        if res["request"] is None:
            return None
        if askers is not None:
            return askers.get(res["request"])
        return next((r["pid"] for r in self.state["requests"] if r["id"] == res["request"]), None)

    def _result_seen_by(self, res, pid, askers=None):
        """Who sees a result: everyone once it is shared; the owner always; its asker while it is `private` (a Just me
        answer, or one the owner took down) and, as before, their own Claude's answer. Never a removed guest's own Claude's."""
        if not self._from_active(res):
            return False
        if pid == HOST or res["published"]:
            return True
        return self._asker(res, askers) == pid and (res.get("private", False) or res["by"]["kind"] == "guest-claude")

    @staticmethod
    def _held(res):
        """Waiting for the owner's Share: not shared, and not yet out to its asker either."""
        return not res["published"] and not res.get("private", False)

    def _review(self):
        """The owner reviews every answer before it is shared: on unless set off (a session from before the setting lacks it)."""
        return self.state["session"]["settings"].get("reviewAnswers", True)

    def _find_result(self, rid):
        for lst in self.state["results"].values():
            for res in lst:
                if res["id"] == rid or (res["request"] is not None and res["request"] == rid):
                    return res
        raise DomainError(404, "not-found", f"No result {rid}.")

    def _act_on_result(self, pid, rid, action):
        res = self._find_result(rid)
        req = next((r for r in self.state["requests"] if r["id"] == res["request"]), None)
        if action == "takedown":
            if not res["published"]:
                raise DomainError(409, "wrong-status", "This result is not shared.", status="unpublished")
            self._take_down(res, req, pid)
            return {"id": res["id"], "published": False}
        # A guest's own Claude's result the owner already shared can still be discarded; the host's own is taken down.
        if res["published"] and not (action == "discard" and res["by"]["kind"] == "guest-claude"):
            raise DomainError(409, "wrong-status", "This result is already shown.", status="published")
        if action == "discard" and res.get("private", False):
            raise DomainError(409, "wrong-status", "Its asker already has this answer.", status="private")
        if action == "publish":
            if self._held(res) and req and req.get("audience") == "me" and res["by"]["kind"] == "host-claude":
                res["private"] = True  # a Just me answer the owner reviewed goes to its asker alone
                self._done(res, req, pid)
                return {"id": res["id"], "published": False}
            self._share(res, req, pid)
        else:
            key = res.get("qid", GENERAL)
            lst = self.state["results"][key]
            lst.remove(res)
            if not lst:
                self.state["results"].pop(key)
            if req:
                req["status"] = {"kind": "failed", "at": self.now(), "reason": NOT_SHARED, "cancelled": True}  # the owner ended it
                self._notify(req["pid"], "request", f"Your request {_on(req)} was not shared.", actor=pid, qid=req.get("qid"))
        return {"id": res["id"], "published": action == "publish"}

    def _done(self, res, req, by):
        """Tell a result's asker their request is done, once it reaches them."""
        if req:
            self._notify(req["pid"], "request", f"Your request {_on(req)} is done.", actor=by, qid=req.get("qid"), msg=res.get("msg"), body=one_line(res["summary"])[:160])

    def _share(self, res, req, by):
        """Show a result to everyone; a general one also becomes Claude's chat message."""
        reached = res.get("private", False)
        res["published"] = True
        res["publishedAt"] = self.now()
        res.pop("private", None)
        res.pop("takenDown", None)
        self._claude_says(res, req)
        if not reached:
            self._done(res, req, by)
        elif req:
            self._notify(req["pid"], "request", f"The answer to your request {_on(req)} was shared with everyone.", actor=by, qid=req.get("qid"), msg=res.get("msg"))

    def _take_down(self, res, req, by):
        """The owner unshares a result: only its asker and the owner see it again, its chat message and any chat quote
        of it read TAKEN_DOWN (kept, and touched, so every open page reads it again). Only the owner shares it again."""
        res["published"] = False
        res["private"] = True
        res["takenDown"] = {"at": self.now()}
        self._chat_text(res, TAKEN_DOWN, {"takenDown": True})
        asker = self._asker(res)
        if asker is not None:
            self._notify(asker, "request", f"The answer to your request {_on(req or res)} was taken down.", actor=by, qid=res.get("qid"))

    def share_result(self, pid, body):
        """POST /api/result/share: share an unshared answer with everyone. Its asker shares their own Just me answer;
        the owner shares any. Another person's answer, or one this person cannot see, reads as 404; one the owner took
        down, or a guest's own Claude's, only the owner shares."""
        rid = _ident(body, "id")
        with self._write_as(pid, "result-share"):
            return self._share_result(pid, rid)

    def _share_result(self, pid, rid):
        """The one share behind the result-share route and Claude's share-result op."""
        try:
            res = self._find_result(rid)
        except DomainError:
            res = None
        if res is None or (pid != HOST and self._asker(res) != pid) or not self._result_seen_by(res, pid):
            raise DomainError(404, "not-found", f"No result {rid}.")
        if res["published"]:
            raise DomainError(409, "wrong-status", "This answer is already shared.", status="published")
        if pid != HOST and ("takenDown" in res or res["by"]["kind"] == "guest-claude"):
            raise DomainError(403, "host-only", "Only the host can share this answer.")
        self._share(res, next((r for r in self.state["requests"] if r["id"] == res["request"]), None), pid)
        return {"id": res["id"], "published": True}

    def _claude_says(self, res, req):
        """A result about the whole session, once shared, is also Claude's chat message (`claude`, written as the host's
        so it stays while anyone reads chat), replying to the message whose "@Claude" asked for it when that is kept.
        With chat off it stays only under results.session, which Ask Claude lists."""
        st = self.state
        if "qid" in res or not st["session"]["settings"]["chat"]:
            return
        if self._chat_text(res, clip(res["summary"], MAX_TEXT), {"result": res["id"]}):
            return  # shared again: its taken-down message comes back in place
        msg = {"id": self._next("M"), "pid": HOST, "text": clip(res["summary"], MAX_TEXT), "at": self.now(), "claude": {"result": res["id"]}}
        asked = next((m for m in st["chat"] if req and m["id"] == req.get("msg") and self._active(m["pid"])), None)
        if asked:
            msg["replyTo"] = {"id": asked["id"], "pid": asked["pid"], "excerpt": clip(one_line(asked["text"]), MAX_EXCERPT)}
        st["chat"].append(msg)
        del st["chat"][:-MAX_CHAT]
        res["msg"] = msg["id"]

    def _chat_text(self, res, text, claude):
        """Rewrite the chat message a result posted, and the quotes of it, and touch each; False when chat no longer keeps it."""
        mid = res.get("msg")
        m = next((m for m in self.state["chat"] if m["id"] == mid), None) if mid else None
        if m is None:
            return False
        m["text"], m["claude"] = text, claude
        self._touch_chat(mid)
        for r in self.state["chat"]:
            if r.get("replyTo", {}).get("id") == mid:
                r["replyTo"]["excerpt"] = clip(one_line(text), MAX_EXCERPT)
                self._touch_chat(r["id"])
        return True

    def _new_result(self, qid, req, body, by, published):
        summary = _text(body, "summary", limit=MAX_SUMMARY)
        report = _text(body, "report", limit=MAX_REPORT, empty_ok=True)
        why = _text(body, "why", limit=MAX_TEXT, empty_ok=True)
        res = {
            "id": self._next("X"),
            **({"qid": qid} if qid else {}),
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
        self.state["results"].setdefault(qid or GENERAL, []).append(res)
        if req:
            req["status"] = {"kind": "done", "at": self.now(), "result": res["id"]}
        return res

    def my_requests(self, pid, body):
        """GET /api/mine/requests: one's own `runner: self` requests, optionally of one status."""
        status = _choice(body or {}, "status", ("pending", "running", "declined", "done", "failed"), optional=True)
        with self._lock:
            me = self._person(pid)
            # the requester's own Claude reads names as its page shows them: "@someone" where names are masked
            full = self.state["session"]["settings"]["names"] == "full" or me["role"] in ("owner", "leader")
            mine = [r for r in self.state["requests"] if r["pid"] == pid and r["runner"] == "self" and (status is None or r["status"]["kind"] == status)]
            out = []
            for r in mine:
                q = self._question(r["qid"])
                out.append(self._plain_all({**copy.deepcopy(r), "question": q["text"]}, full))
            return {"requests": out}

    def claim_my_request(self, pid, body):
        with self._write_as(pid, "mine-claim"):
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] != "pending":
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            r["status"] = {"kind": "running", "since": self.now()}
            return {"id": r["id"], "status": "running"}

    def post_my_result(self, pid, body):
        """POST /api/mine/requests/result: the requester's own Claude answers. Like every result it waits for the
        owner's Publish; until then only the requester and the owner see it."""
        with self._write_as(pid, "mine-result") as st:
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] != "running":
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            rnd = self._question(r["qid"])["round"]
            in_round = {q["id"] for q in st["questions"] if q["round"] == rnd}
            mine = [x for qid, lst in st["results"].items() if qid in in_round for x in lst if x["by"].get("pid") == pid]
            if sum(1 for x in mine if x["qid"] == r["qid"]) >= MAX_MY_RESULTS:
                raise DomainError(409, "results-full", f"Your Claude can post at most {MAX_MY_RESULTS} answers on one question.", max=MAX_MY_RESULTS)
            if len(mine) >= MAX_MY_ROUND_RESULTS:
                raise DomainError(409, "results-full", f"Your Claude can post at most {MAX_MY_ROUND_RESULTS} answers in one round.", max=MAX_MY_ROUND_RESULTS)
            if sum(len(lst) for lst in st["results"].values()) >= MAX_RESULTS:
                raise DomainError(409, "results-full", f"This session holds at most {MAX_RESULTS} results.", max=MAX_RESULTS)
            res = self._new_result(r["qid"], r, body, {"kind": "guest-claude", "pid": pid}, False)
            return {"id": res["id"]}

    def fail_my_request(self, pid, body):
        reason = _text(body, "reason", limit=MAX_NOTE)
        with self._write_as(pid, "mine-fail"):
            r = self._request(_ident(body, "id"), runner="self", owner_pid=pid)
            if r["status"]["kind"] not in ("pending", "running"):
                raise DomainError(409, "wrong-status", f"Request {r['id']} is {r['status']['kind']}.", status=r["status"]["kind"])
            r["status"] = {"kind": "failed", "at": self.now(), "reason": reason, "cancelled": False}
            return {"id": r["id"], "status": "failed"}

    def issue_watcher(self, pid, body):
        """POST /api/watcher: a new watcher key for one's own Claude, replacing any earlier one. Only its hash is kept."""
        if pid == HOST:
            raise DomainError(403, "guests-only", "Watcher keys are for a guest's own Claude; the owner's Claude already runs this session.")
        with self._write_as(pid, "watcher") as st:
            self._drop_watcher(pid)
            token = self.ids.token(32)
            st["credentials"].setdefault("watchers", {})[sha256(token)] = pid
            return {"token": token}

    def revoke_watcher(self, pid, body):
        """POST /api/watcher/revoke: one's watcher key stops working."""
        with self._write_as(pid, "watcher-revoke"):
            self._drop_watcher(pid)
            return {"watcher": False}

    def _drop_watcher(self, pid):
        watchers = self.state["credentials"].get("watchers", {})
        for h in [h for h, p in watchers.items() if p == pid]:
            watchers.pop(h)

    # -- uploads -----------------------------------------------------------------------------

    def _upload(self, uid):
        u = next((u for u in self.state["uploads"] if u["id"] == uid), None) if isinstance(uid, str) else None
        if u is None:
            raise DomainError(404, "no-such-upload", f"No upload {str(uid)[:40]}.")
        return u

    @staticmethod
    def _chunk_length(u, index):
        return min(CHUNK_SIZE, u["size"] - index * CHUNK_SIZE)

    def _detach(self, uid):
        """Take an upload off every answer, message, request, suggestion, proposal and comment that carries it. An
        answer left with no text, pick or file is cleared, as its author's empty answer would be, while its question
        still takes answers; on a locked question or a round sent to Claude it stays, as answer() would keep it."""
        emptied = set()
        for _, c in _attaching(self.state):
            if uid in c.get("attachments", []):
                c["attachments"].remove(uid)
                if not c["attachments"]:
                    c.pop("attachments")
                    emptied.add(id(c))
        for lk in self.state["locks"].values():  # a lock keeps its answer's files only while they last
            src = lk["source"]
            if uid in src.get("attachments", []):
                src["attachments"].remove(uid)
                if not src["attachments"]:
                    src.pop("attachments")
        for qid, cards in self.state["cards"].items():
            for c in [c for c in cards if id(c) in emptied and not c["text"] and not {"pick", "picks", "value", "order"} & c.keys()]:
                try:
                    self._answerable(self._question(qid))
                except DomainError:
                    continue
                self._clear_card(qid, c)

    def _touch_carriers(self, uid):
        """An upload changed how it shows: chat messages carrying it are touched, so a page holding older ones reads
        them again (chatTouched)."""
        for m in self.state["chat"]:
            if uid in m.get("attachments", ()):
                self._touch_chat(m["id"])

    def _end_upload(self, u, status):
        """Give an upload its last status: its preview goes, and unless it arrived it leaves every answer. Returns its
        pending file, for the caller to delete once the transaction holds."""
        self._touch_carriers(u["id"])
        doomed = self._pending_file(u)
        u["status"] = status
        u.pop("thumb", None)
        if status["kind"] != "done":
            self._detach(u["id"])
        return doomed

    def _end_uploads_of(self, pid, now):
        """A removed person's files still on their way are declined; their pending files, returned, are deleted."""
        live = [u for u in self.state["uploads"] if u["pid"] == pid and u["status"]["kind"] in UPLOAD_LIVE]
        return [f for u in live if (f := self._end_upload(u, {"kind": "declined", "at": now, "why": "removed"}))]

    def _pending_file(self, u):
        """An accepted upload's pending file; None without one, or for a name the server never makes (a hand-edited
        or early state.json), which then names no file to open or delete."""
        tmp = u["status"].get("tmp", "")
        return self.uploads_dir / "pending" / tmp if TMP_NAME.fullmatch(tmp) else None

    @staticmethod
    def _discard(path):
        """Delete one file of ours; a failure (Windows holds open files) leaves it on disk, unreferenced and never served."""
        with contextlib.suppress(OSError):
            Path(path).unlink(missing_ok=True)

    def offer_upload(self, pid, body):
        """POST /api/upload/offer: offer a file, which stays in the person's browser until the owner accepts it (the
        owner's own is accepted at once). Refused while uploads are off, past a cap (MAX_OPEN_UPLOADS open per
        person and GUEST_UPLOAD_MAX per guest, counting every file not declined, withdrawn or failed;
        SESSION_UPLOAD_MAX per session, counting only accepted files, so offers alone never fill it), or of a kind a
        guest may not send. The name is display text; the server names the file."""
        body = _body(body)
        name = _file_name(body)
        size = body.get("size")
        if not _is_int(size) or size < 1:
            raise _bad("size", "size must be the file's size in bytes.")
        _text(body, "type", limit=MAX_NOTE, empty_ok=True)  # the browser's guess, unused: the server records its own
        ext = name.rsplit(".", 1)[1].lower() if "." in name else ""
        ext = ext if FILE_EXT.fullmatch(ext) else ""
        thumb = _thumb(body.get("thumb"), ext)
        qid = body.get("qid") or None
        avatar = _bool(body, "avatar")
        if avatar and ext not in AVATAR_KINDS:
            raise DomainError(415, "file-type", "A profile picture must be a PNG, JPEG or WebP picture.", field="file")
        if avatar and size > AVATAR_MAX:
            raise DomainError(413, "upload-too-large", "A profile picture is 256 KB at most.", field="size", max=AVATAR_MAX)
        if avatar and qid is not None:
            raise _bad("qid", "A profile picture belongs to no question.")
        doomed = []
        with self._write_as(pid, "upload-offer") as st:
            person = st["people"][pid]
            owner = pid == HOST
            if not st["session"]["settings"]["uploads"] and not (avatar and owner):  # the owner's own picture needs no switch
                raise DomainError(403, "uploads-off", "The host has pictures off in this session." if avatar else "Uploads are off in this session.")
            if qid is not None:
                qid = self._question(qid)["id"]
            if ext not in GUEST_KINDS and not (owner or person["trusted"]):
                raise DomainError(415, "file-type", "Guests can send pictures, PDF, text, CSV and Office files.")
            held = [u for u in st["uploads"] if u["status"]["kind"] in UPLOAD_HELD]
            if sum(1 for u in held if u["pid"] == pid and u["status"]["kind"] in UPLOAD_LIVE) >= MAX_OPEN_UPLOADS:
                raise DomainError(429, "too-many-pending", f"You have {MAX_OPEN_UPLOADS} files waiting already.", field="file")
            mine = sum(u["size"] for u in held if u["pid"] == pid)
            if not owner and mine + size > GUEST_UPLOAD_MAX:
                raise DomainError(413, "upload-too-large", "That is more than a guest can send.", max=GUEST_UPLOAD_MAX, left=max(0, GUEST_UPLOAD_MAX - mine))
            total = self._session_upload_total()
            if total + size > SESSION_UPLOAD_MAX:
                raise DomainError(413, "upload-too-large", "This session holds no more files.", max=SESSION_UPLOAD_MAX, left=max(0, SESSION_UPLOAD_MAX - total))
            uid = f"{self._next('U')}-{self.ids.hex(4)}"
            mime = UPLOAD_KINDS[ext][0] if ext in UPLOAD_KINDS else "application/octet-stream"
            # a draft until something carries it: a form offers it before its post is sent
            rec = {"id": uid, "pid": pid, "at": self.now(), "qid": qid, "file": name, "ext": ext, "mime": mime, "size": size, "chunks": -(-size // CHUNK_SIZE)}
            if avatar:  # a new profile picture replaces one still on its way
                rec["avatar"] = True
                for u in held:
                    if u["pid"] == pid and u.get("avatar") and u["status"]["kind"] in UPLOAD_LIVE:
                        doomed.append(self._end_upload(u, {"kind": "withdrawn", "at": rec["at"]}))
            else:
                rec["draft"] = True
            shown = [(u["pid"], len(u["thumb"])) for u in st["uploads"] if "thumb" in u]
            if thumb and sum(n for p, n in shown if p == pid) + len(thumb) <= PERSON_THUMB_MAX and sum(n for _, n in shown) + len(thumb) <= SESSION_THUMB_MAX:
                rec["thumb"] = thumb  # past either bound the offer keeps no preview; the owner sees its icon
            # the owner's own, and a profile picture (small, and shown to others only once approved), need no accept
            rec["status"] = {"kind": "accepted", "tmp": self.ids.hex(16)} if owner or avatar else {"kind": "offered"}
            st["uploads"].append(rec)
            if not owner:
                self._queue_note([HOST], pid)
            out = {"id": uid, "status": rec["status"]["kind"], "chunks": rec["chunks"], "chunkSize": CHUNK_SIZE}
        for f in doomed:
            if f:
                self._discard(f)
        return out

    def _session_upload_total(self):
        """Bytes the session has said yes to (accepted, uploading or done): what SESSION_UPLOAD_MAX bounds."""
        return sum(u["size"] for u in self.state["uploads"] if u["status"]["kind"] in UPLOAD_ACCEPTED)

    def act_on_upload(self, pid, body):
        """POST /api/upload/act: the owner accepts or declines an offered file, and its uploader withdraws it. Accepting
        is refused past SESSION_UPLOAD_MAX. Declining or withdrawing deletes what arrived so far and takes the file off
        every answer; the browser deletes its copy. `remove`, by the owner or the uploader, ends a received file: it
        leaves everything that carries it and is deleted from the data folder. `approve`, the owner's, lets everyone who
        sees what carries a guest's received picture see the picture (`shown`). `draftOnly` (the attachment chip's x)
        refuses a withdraw or remove once something sent carries the file, so a stale page never takes it off a post."""
        action = _choice(body, "action", ("accept", "decline", "withdraw", "remove", "approve"))
        uid = _ident(body, "id")
        draft_only = _bool(body, "draftOnly")
        now = self.now()
        with self._tx():
            if action in ("withdraw", "remove") and pid != HOST:
                self._writer(pid)
                self._throttle(pid, "upload-act", now)
            else:
                self._owner(pid)
            u = self._upload(uid)
            if (action == "withdraw" or pid != HOST) and u["pid"] != pid:
                raise DomainError(404, "no-such-upload", f"No upload {uid[:40]}.")
            if draft_only and action in ("withdraw", "remove") and not u.get("draft"):
                raise DomainError(409, "wrong-status", "That file went with something you sent, so it stays there.", status="carried")
            kind = u["status"]["kind"]
            if kind not in {"accept": ("offered",), "remove": ("done",), "approve": ("done",)}.get(action, UPLOAD_LIVE):
                raise DomainError(409, "wrong-status", f"That file is {kind}.", status=kind)
            if action == "approve" and not (_shows_as_image(u) and not _approved(u)):
                raise DomainError(409, "wrong-status", "Only a guest's received picture waits for approval.", status="shown" if _approved(u) else kind)
            doomed = None
            if action == "approve":
                u["shown"] = True
                self._touch_carriers(uid)
            if action == "remove":
                stored = u["status"]["stored"]
                self._end_upload(u, {"kind": "removed", "at": now, "by": pid})
                if not u.get("avatar"):  # Claude never heard of a profile picture
                    self._event("upload-removed", upload=uid, file=u["file"])
                doomed = self.path.parent / stored if STORED_PATH.fullmatch(stored) else None
            if action == "accept":
                if not self._active(u["pid"]):
                    raise DomainError(409, "wrong-status", "Its sender is no longer in the session.", status="removed")
                total = self._session_upload_total()
                if total + u["size"] > SESSION_UPLOAD_MAX:
                    raise DomainError(
                        413, "upload-too-large", "This session holds 5 GB of files at most, and this one would pass that. Decline it, or a file still on its way.",
                        field="accept", max=SESSION_UPLOAD_MAX, left=max(0, SESSION_UPLOAD_MAX - total),
                    )
                u["status"] = {"kind": "accepted", "tmp": self.ids.hex(16)}
            elif action not in ("remove", "approve"):
                doomed = self._end_upload(u, {"kind": "declined" if action == "decline" else "withdrawn", "at": now})
        if action in ("withdraw", "remove") and pid != HOST:
            self._wrote(pid, "upload-act", now)
        if doomed:
            self._discard(doomed)
        return {"id": uid, "status": u["status"]["kind"]}

    def _chunk_target(self, pid, m):
        """The upload a chunk is for: the sender's own, accepted, with the total the offer set, no chunk in flight."""
        self._writer(pid)
        u = self._upload(m["id"])
        if u["pid"] != pid:
            raise DomainError(404, "no-such-upload", f"No upload {m['id']}.")
        kind = u["status"]["kind"]
        if kind not in ("accepted", "uploading"):
            raise DomainError(409, "wrong-status", f"That file is {kind}.", status=kind)
        if m["total"] != u["chunks"]:
            raise _bad("X-Chunk-Total", f"This file takes {u['chunks']} pieces.")
        if u["id"] in self._sending:
            raise DomainError(409, "wrong-status", "A piece of this file is on its way already.", status="sending")
        return u

    def chunk_plan(self, pid, meta):
        """Before the chunk route reads a body: {"length": the bytes chunk `index` holds}, or {"received": n} for a
        chunk the server has (a repeat after a lost answer). A chunk past the next is 409 chunk-gap with `received`."""
        m = _chunk_meta(meta)
        with self._lock:
            u = self._chunk_target(pid, m)
            received = u["status"].get("received", 0)
            if m["index"] < received:
                return {"received": received}
            if m["index"] > received:
                raise DomainError(409, "chunk-gap", f"Send piece {received + 1} next.", received=received)
            self._throttle(pid, "upload-chunk", self.now(), CHUNK_INTERVAL)
            return {"length": self._chunk_length(u, m["index"])}

    def upload_chunk(self, pid, meta, data):
        """POST /api/upload/chunk: chunk `index` of an accepted upload, in order. Its own sha256 must match; the first
        must start as its kind does (UPLOAD_KINDS) and the last must make the whole file hash to X-File-Sha256, or the
        upload fails and its bytes are deleted; an archive kind must also pass `_archive_ok`. The bytes are written
        outside the session lock, one chunk per upload at a time; a decline or withdraw meanwhile wins and the bytes
        are deleted. The last chunk moves the file to uploads/accepted/, marks it from the internet on Windows, and
        writes `upload-received` for Claude. Every piece read counts against the throttle, whatever its outcome."""
        m = _chunk_meta(meta)
        now = self.now()
        try:
            return self._take_chunk(pid, m, data, now)
        finally:
            self._wrote(pid, "upload-chunk", now)

    def _take_chunk(self, pid, m, data, now):
        with self._lock:
            u = self._chunk_target(pid, m)
            received = u["status"].get("received", 0)
            if m["index"] < received:
                return {"received": received}
            if m["index"] > received:
                raise DomainError(409, "chunk-gap", f"Send piece {received + 1} next.", received=received)
            self._throttle(pid, "upload-chunk", now, CHUNK_INTERVAL)
            if len(data) != self._chunk_length(u, m["index"]):
                raise _bad("Content-Length", f"This piece is {self._chunk_length(u, m['index'])} bytes.")
            last = m["index"] == u["chunks"] - 1
            if last and "fileSha256" not in m:
                raise _bad("X-File-Sha256", "The last piece carries the whole file's sha256.")
            uid, ext, offset = u["id"], u["ext"], m["index"] * CHUNK_SIZE
            tmp = self._pending_file(u)
            if tmp is None:
                raise DomainError(409, "wrong-status", "What arrived before was lost; offer the file again.", status="lost")
            name = f"{time.strftime('%Y%m%d', time.gmtime(now))}-{uid}{'.' + ext if ext else ''}"  # STORED_NAME: load checked uid and ext
            stored, dest = STORED_DIR + name, self.uploads_dir / "accepted" / name
            self._sending.add(uid)
        try:
            if hashlib.sha256(data).hexdigest() != m["sha256"]:
                raise DomainError(400, "hash-mismatch", "That piece arrived damaged; send it again.", field="X-Chunk-Sha256")
            failure, digest = None, None
            if m["index"] == 0 and ext in UPLOAD_KINDS and not UPLOAD_KINDS[ext][1](data[:4096]):
                failure = (DomainError(415, "file-type", f"This file is not a {ext.upper()} file.", field="file"), "Its contents are not what its name says.")
            elif not _write_chunk(tmp, offset, data):
                failure = (DomainError(409, "wrong-status", "What arrived before was lost; offer the file again.", status="failed"), "What arrived before was lost.")
            elif last:
                digest = _file_sha256(tmp)
                if digest != m["fileSha256"]:
                    failure = (DomainError(400, "hash-mismatch", "The file did not arrive intact; it was deleted.", field="X-File-Sha256"), "The file did not arrive intact.")
                elif ext in ARCHIVE_KINDS and not _archive_ok(tmp, ext):
                    failure = (DomainError(415, "file-type", f"This file is not a {ext.upper()} file.", field="file"), "Its contents are not what its name says.")
                else:
                    _private_dirs(dest.parent)
                    replace_into(tmp, dest)
                    _mark_from_internet(dest)
            if failure:
                self._discard(tmp)
                with self._tx():
                    u = self._upload(uid)
                    if u["status"]["kind"] in ("accepted", "uploading"):
                        self._end_upload(u, {"kind": "failed", "reason": failure[1]})
                raise failure[0]
            replaced = []
            try:
                with self._tx():
                    u = self._upload(uid)
                    if u["status"]["kind"] not in ("accepted", "uploading"):
                        raise DomainError(409, "wrong-status", f"That file is {u['status']['kind']}.", status=u["status"]["kind"])
                    if last:
                        self._end_upload(u, {"kind": "done", "stored": stored, "sha256": digest})
                        if u.get("avatar"):  # a profile picture is no file for Claude; it replaces the sender's last one
                            old = [x for x in self.state["uploads"] if x is not u and x["pid"] == pid and x.get("avatar") and x["status"]["kind"] == "done"]
                            for x in old:
                                replaced.append(x["status"]["stored"])
                                self._end_upload(x, {"kind": "removed", "at": now, "by": pid})
                        else:
                            self._event("upload-received", upload=uid, file=u["file"], stored=stored, qid=u["qid"])
                    else:
                        u["status"] = {"kind": "uploading", "tmp": tmp.name, "received": m["index"] + 1, "bytes": offset + len(data)}
            except BaseException:
                if last:
                    self._discard(dest)
                with self._lock:
                    if self._upload(uid)["status"]["kind"] not in ("accepted", "uploading"):
                        self._discard(tmp)
                raise
            for stored_old in replaced:
                if STORED_PATH.fullmatch(stored_old):
                    self._discard(self.path.parent / stored_old)
        finally:
            self._sending.discard(uid)
        return {"received": m["index"] + 1, "status": u["status"]["kind"]}

    def recover_uploads(self):
        """At server start: cut each upload's pending file back to the chunks its record counts, start over one whose
        bytes went missing or whose pending name is not one the server makes, and delete every pending file no record
        names (a crash, or a delete Windows refused) and every received file of ours no record names. A file still on
        its way from someone no longer in the session (an earlier build kept them) is declined first, so its bytes go
        too. Returns how many files it deleted."""
        pending, accepted = self.uploads_dir / "pending", self.uploads_dir / "accepted"
        with self._lock:
            gone = {u["pid"] for u in self.state["uploads"] if u["status"]["kind"] in UPLOAD_LIVE and not self._active(u["pid"])}
            if gone:
                with self._tx():
                    for pid in gone:
                        self._end_uploads_of(pid, self.now())
            ups = [u for u in self.state["uploads"] if u["status"]["kind"] in ("accepted", "uploading")]
            live = {f.name: u for u in ups if (f := self._pending_file(u))}
            done = {Path(u["status"]["stored"]).name for u in self.state["uploads"] if u["status"]["kind"] == "done"}
            stray = [f for f in (pending.iterdir() if pending.is_dir() else ()) if f.is_symlink() or (f.is_file() and f.name not in live)]
            stray += [f for f in (accepted.iterdir() if accepted.is_dir() else ()) if STORED_NAME.fullmatch(f.name) and f.name not in done and (f.is_file() or f.is_symlink())]
            removed = 0
            for f in stray:
                with contextlib.suppress(OSError):
                    f.unlink()
                    removed += 1
            lost = [u["id"] for u in ups if self._pending_file(u) is None]
            for name, u in live.items():
                f, want = pending / name, u["status"].get("bytes", 0)
                have = f.stat().st_size if f.is_file() and not f.is_symlink() else 0
                if have > want:
                    os.truncate(f, want)
                elif have < want:
                    lost.append(u["id"])
            if lost:
                with self._tx():
                    for uid in lost:
                        u = self._upload(uid)
                        if self._pending_file(u):
                            self._discard(self._pending_file(u))
                        u["status"] = {"kind": "accepted", "tmp": self.ids.hex(16)}
            return removed

    def _upload_view(self, u, *, owner=False):
        """An upload as the page reads it: never `tmp`, `stored` or any path; the preview to the owner only; `image` on a
        received picture GET /api/upload/image reads back."""
        out = {k: u[k] for k in ("id", "pid", "at", "qid", "file", "ext", "size", "chunks")}
        if u.get("avatar"):
            out["avatar"] = True
        if _shows_as_image(u):
            out["image"] = True
            if _approved(u):
                out["shown"] = True
        out["status"] = {k: v for k, v in u["status"].items() if k not in ("tmp", "stored")}
        out["chunkSize"] = CHUNK_SIZE
        if owner and "thumb" in u:
            out["thumb"] = u["thumb"]
        return out

    # -- problem reports --------------------------------------------------------------------

    def report(self, pid, body):
        """POST /api/report: tell the owner something is broken, with what the page says about where, and at most
        MAX_REPORT_IMAGES screenshots. Allowed while uploads are off: checked pictures the owner alone sees, saved under
        reports/ in the data folder, the first at `image` as a report from before kept it and the rest at `moreImages`.
        One report a REPORT_INTERVAL per person, MAX_OPEN_REPORTS open, MAX_REPORTS in all."""
        body = _body(body)
        text = _text(body, "text")
        ctx = _report_ctx(body.get("ctx"))
        images = _report_images(body)
        now, saved = self.now(), []
        try:
            with self._tx() as st:
                self._writer(pid)
                if now - self._reported.get(pid, float("-inf")) < REPORT_INTERVAL:
                    raise DomainError(429, "slow-down", "You sent a report a moment ago. Try again in a few seconds.")
                reports = st.setdefault("reports", {})
                if len(reports) >= MAX_REPORTS:
                    raise DomainError(429, "too-many-reports", "This session holds no more reports.")
                if sum(1 for r in reports.values() if r["by"] == pid and r["status"] == "open") >= MAX_OPEN_REPORTS:
                    raise DomainError(429, "too-many-pending", f"You have {MAX_OPEN_REPORTS} reports waiting already.")
                fid = self._next("F")
                rec = {"by": pid, "text": text, "ctx": ctx, "status": "open", "ts": now}
                for n, (data, ext) in enumerate(images, 1):
                    name = f"{REPORTS_DIR}/{fid}.{ext}" if n == 1 else f"{REPORTS_DIR}/{fid}-p{n}.{ext}"
                    if n == 1:
                        rec["image"] = name
                    else:
                        rec.setdefault("moreImages", []).append(name)
                    saved.append(self.path.parent / name)
                    _write_chunk(saved[-1], 0, data)
                reports[fid] = rec
        except BaseException:
            for f in saved:
                self._discard(f)
            raise
        with self._lock:
            self._reported[pid] = now
        return {"id": fid}

    def add_to_report(self, pid, body):
        """POST /api/report/add: the reporter adds a line, a screenshot or both to their own report while it is open or
        seen; another person's report reads as missing. A seen report goes back to open, so the owner sees it waiting
        again, unless that would pass MAX_OPEN_REPORTS. An add clears `asked`, so the owner may ask Claude again. At most
        MAX_REPORT_ADDS per report; one write a second."""
        body = _body(body)
        text = _text(body, "text", empty_ok=True)
        image = _report_image(body.get("image"))
        if not text and not image:
            raise DomainError(400, "empty", "Add a line or a screenshot.", field="text")
        now, saved = self.now(), None
        try:
            with self._write_as(pid, "report-add") as st:
                fid = _ident(body, "id")
                r = st.get("reports", {}).get(fid)
                if r is None or r["by"] != pid:
                    raise DomainError(404, "not-found", f"No report {fid[:20]}.")
                if r["status"] == "resolved":
                    raise DomainError(409, "wrong-status", f"Report {fid} is fixed.", status=r["status"])
                if r["status"] == "seen" and sum(1 for x in st["reports"].values() if x["by"] == pid and x["status"] == "open") >= MAX_OPEN_REPORTS:
                    raise DomainError(429, "too-many-pending", f"You have {MAX_OPEN_REPORTS} reports waiting already.")
                adds = r.setdefault("adds", [])
                if len(adds) >= MAX_REPORT_ADDS:
                    raise DomainError(409, "too-many", f"A report takes at most {MAX_REPORT_ADDS} additions.", max=MAX_REPORT_ADDS)
                add = {"ts": now, **({"text": text} if text else {})}
                if image:
                    add["image"] = f"{REPORTS_DIR}/{fid}-{len(adds) + 1}.{image[1]}"
                    saved = self.path.parent / add["image"]
                    _write_chunk(saved, 0, image[0])
                adds.append(add)
                r["status"] = "open"
                r.pop("asked", None)  # new words from the reporter: the owner may ask Claude again
                self._unseen(HOST, "report:" + fid)  # and it waits on the owner again, unread
        except BaseException:
            if saved:
                self._discard(saved)
            raise
        return {"id": fid, "adds": len(adds), "status": "open"}

    def _report(self, fid):
        r = self.state.get("reports", {}).get(fid) if isinstance(fid, str) else None
        if r is None:
            raise DomainError(404, "not-found", f"No report {str(fid)[:20]}.")
        return r

    def act_on_report(self, pid, body):
        """POST /api/report/act: the owner marks a report seen or resolved, which tells the reporter, or asks Claude
        about one not yet resolved, which writes `report-filed`: a guest's report alone never reaches Claude."""
        action = _choice(body, "action", ("seen", "resolved", "ask"))
        with self._tx():
            self._owner(pid)
            return self._act_on_report(pid, _ident(body, "id"), action)

    def _act_on_report(self, pid, fid, action):
        """The one report action behind the owner's report route and Claude's resolve-report op."""
        r = self._report(fid)
        if action == "ask":
            if r["status"] == "resolved" or "asked" in r:
                state = "asked" if "asked" in r else r["status"]
                raise DomainError(409, "wrong-status", f"Report {fid} is {state}.", status=state)
            r["asked"] = self.now()
            adds = r.get("adds", [])
            self._event("report-filed", report=fid, qid=r["ctx"].get("qid"), text=r["text"], images=len(_report_pics(r)),
                        adds=[a["text"] for a in adds if "text" in a], addImages=sum(1 for a in adds if "image" in a))
            return {"id": fid, "status": r["status"], "asked": True}
        if r["status"] == "resolved" or r["status"] == action:
            raise DomainError(409, "wrong-status", f"Report {fid} is {r['status']}.", status=r["status"])
        r["status"] = action
        said = "saw your problem report" if action == "seen" else "marked your problem report resolved"
        self._notify(r["by"], "report", f"The host {said}.", actor=pid)
        return {"id": fid, "status": action}

    def report_image(self, pid, body):
        """GET /api/report/image?id=[&pic=N|&add=N]: owner only. A report's first picture, its Nth one sent with it, or
        its Nth addition's, as a data: URL."""
        with self._lock:
            self._owner(pid)
            fid = _ident(_body(body), "id")
            r = self._report(fid)
            n, pic = body.get("add"), body.get("pic")
            if n is not None and not (isinstance(n, str) and re.fullmatch(r"[1-9][0-9]{0,2}", n)):
                raise _bad("add", "add must name an addition by its number.")
            if pic is not None and (n is not None or not (isinstance(pic, str) and re.fullmatch(rf"[1-{MAX_REPORT_IMAGES}]", pic))):
                raise _bad("pic", f"pic must name one of the report's pictures, 1 to {MAX_REPORT_IMAGES}, without add.")
            if n is None:
                pics = _report_pics(r)
                stored = pics[int(pic or 1) - 1] if int(pic or 1) <= len(pics) else ""
            else:
                adds = r.get("adds", [])
                stored = adds[int(n) - 1].get("image", "") if int(n) <= len(adds) else ""
        f = self.path.parent / stored
        if not stored or not f.is_file():
            raise DomainError(404, "not-found", f"Report {fid} has no picture.")
        mime = UPLOAD_KINDS[stored.rsplit(".", 1)[1]][0]
        return {"id": fid, "image": f"data:{mime};base64,{base64.b64encode(f.read_bytes()).decode()}"}

    def _report_view(self, fid, r):
        """A report as the owner's page reads it: whether it has a picture, never where it is saved."""
        return {"id": fid, **{k: copy.deepcopy(v) for k, v in r.items() if k not in ("image", "moreImages", "adds")}, "image": "image" in r,
                "images": len(_report_pics(r)), "adds": [{**{k: v for k, v in a.items() if k != "image"}, "image": "image" in a} for a in r.get("adds", [])]}

    def _my_report_view(self, fid, r):
        """A report as its reporter reads it in Your reports: their words and additions, and its status, never the
        context their page sent or where a picture is saved."""
        return {"id": fid, "text": r["text"], "status": r["status"], "ts": r["ts"], "image": "image" in r, "images": len(_report_pics(r)),
                "adds": [{**{k: v for k, v in a.items() if k != "image"}, "image": "image" in a} for a in r.get("adds", [])]}

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

    def read_inbox(self, pid, body):
        """POST /api/inbox/read: `{keys}`, Inbox items this person opened, each read at its status now; allowed while
        ended; one write a second, like notifications/read. Only keys of this person's own Inbox count, marks of items
        no longer in it are dropped, and a read that marks nothing writes nothing."""
        keys, saw = _body(body).get("keys"), body.get("saw", {})
        if not (isinstance(keys, list) and 0 < len(keys) <= MAX_INBOX_READ and all(isinstance(k, str) for k in keys)):
            raise _bad("keys", f"Send keys: 1 to {MAX_INBOX_READ} Inbox item keys.")
        # `saw`: the status the page showed for a key, so a read sent after the status moved again leaves that move unread
        if not (isinstance(saw, dict) and len(saw) <= MAX_INBOX_READ and all(v in INBOX_MARKS for v in saw.values())):
            raise _bad("saw", "saw maps an Inbox key to the status the page showed.")
        with self._lock:
            self._person(pid)
            self._throttle(pid, "inbox-read", self.now())
            items = {i["key"]: i["status"] for i in self._inbox(pid)}
            seen = self.state["inboxSeen"].get(pid, {})
            if not any(k in items and seen.get(k) != saw.get(k, items[k]) for k in keys):
                return {"read": 0}
        with self._write_as(pid, "inbox-read", check=self._person) as st:
            items = {i["key"]: i["status"] for i in self._inbox(pid)}
            seen = {k: v for k, v in st["inboxSeen"].get(pid, {}).items() if k in items}
            n = 0
            for k in keys:
                if k in items and seen.get(k) != saw.get(k, items[k]):
                    seen[k] = saw.get(k, items[k])
                    n += 1
            if seen:
                st["inboxSeen"][pid] = seen
            else:
                st["inboxSeen"].pop(pid, None)
            return {"read": n}

    def update_settings(self, pid, body):
        """POST /api/session/settings: a partial Settings object."""
        _body(body)
        with self._tx() as st:
            self._owner(pid)
            was_live = "live" in prototype_tiers(st["session"]["settings"])
            _settings_patch(st["session"]["settings"], body)
            if was_live and "live" not in prototype_tiers(st["session"]["settings"]):
                self._end_lives("tier-off")  # every live prototype ends at once; turning it on again restarts none
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
                st["credentials"].pop("devices", None)  # the owner's other devices sign out with the session; a reopen brings none back
                self._pairing = None
                self._end_lives("session-ended")  # and every live prototype ends; a reopen restarts none
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
        """POST /api/link/owner: a new owner token; the old owner link and every other signed-in device stop working."""
        _body(body)
        with self._tx() as st:
            self._owner(pid)
            token = self.ids.token(32)
            at = self.now()
            if self.on_owner_token is not None:  # the secrets file holds the token before the hash commits
                self.on_owner_token(token, at)
            st["credentials"]["owner"] = {"tokenHash": sha256(token), "rotatedAt": at}
            st["credentials"].pop("devices", None)
            self._pairing = None
            return {"token": token}

    def pair_device(self, pid, body):
        """POST /api/owner/pair: a sign-in code for another device of the owner's, replacing any earlier one. It works
        once, for PAIR_SECONDS; only its hash is kept, in memory."""
        _body(body)
        now = self.now()
        with self._lock:
            self._owner(pid)
            self._throttle(pid, "pair", now)
            if len(self.state["credentials"].get("devices", {})) >= MAX_DEVICES:
                raise DomainError(409, "devices-full", f"{MAX_DEVICES} other devices are signed in. Sign one out first.", max=MAX_DEVICES)
            code = "".join(secrets.choice(PAIR_ALPHABET) for _ in range(PAIR_LENGTH))
            self._pairing = {"hash": sha256(code), "until": now + PAIR_SECONDS, "misses": {}}
        self._wrote(pid, "pair", now)
        return {"code": code, "expiresIn": PAIR_SECONDS}

    def redeem_pairing(self, pid, body, *, address=""):
        """POST /api/owner/pair/redeem: trade the live sign-in code for this device's own owner credential. One try a
        second per address, and an address with PAIR_MISSES wrong codes is refused the live one, which stays good for
        everyone else, so a stranger cannot burn it."""
        body = _body(body)
        code = re.sub(r"[^0-9A-Z]", "", body["code"].upper()) if isinstance(body.get("code"), str) else ""
        device = _choice(body, "device", DEVICES, optional=True)
        browser = body.get("browser")
        browser = None if browser is None else browser if browser in BROWSERS else "other"
        now = self.now()
        with self._tx() as st:
            self._throttle(address, "pair-redeem", now)
            self._wrote(address, "pair-redeem", now)
            p = self._pairing
            if p is not None and now >= p["until"]:
                p = self._pairing = None
            if p is None or p["misses"].get(address, 0) >= PAIR_MISSES or not hmac.compare_digest(sha256(code), p["hash"]):
                if p is not None and p["misses"].get(address, 0) < PAIR_MISSES:
                    p["misses"][address] = p["misses"].get(address, 0) + 1
                raise DomainError(403, "bad-pair-code", "That code is wrong or has expired. Ask the host for a new one.")
            self._pairing = None
            token, did = self.ids.token(32), self.ids.token(6)
            hint = {k: v for k, v in (("device", device), ("browser", browser)) if v}
            st["credentials"].setdefault("devices", {})[sha256(token)] = {"id": did, "at": now, **hint}
            return {"token": token, "id": did}

    def revoke_device(self, pid, body):
        """POST /api/owner/devices/revoke: one of the owner's other devices is signed out at once."""
        did = _body(body).get("id")
        with self._write_as(pid, "device-revoke", check=self._owner) as st:
            devices = st["credentials"].get("devices", {})
            h = next((h for h, d in devices.items() if d["id"] == did), None)
            if h is None:
                raise DomainError(404, "not-found", "That device is not signed in.")
            devices.pop(h)
            return {"id": did}

    # -- notifications -----------------------------------------------------------------------

    def _seen_now(self, pid, key):
        item = next((i for i in self._inbox(pid) if i["key"] == key), None)
        if item:
            self.state["inboxSeen"].setdefault(pid, {})[key] = item["status"]

    def _unseen(self, pid, key):
        """Forget pid's read mark of an Inbox item that left the Inbox, so its return reads as new."""
        seen = self.state["inboxSeen"].get(pid)
        if seen and seen.pop(key, None) is not None and not seen:
            self.state["inboxSeen"].pop(pid)

    def _inbox(self, pid):
        """This person's Inbox: their own requests, each with the status they would see, and for the owner what
        waits on them: requests to run, answers to share, guests' requests Claude failed (read once opened, then only
        history), open reports not yet asked about, merges and joins. `unread`: the status moved since they last opened
        the item. Never another person's request or a result its requester cannot see."""
        st = self.state
        results = {r["id"]: r for lst in st["results"].values() for r in lst}
        seen = st["inboxSeen"].get(pid, {})
        out = []
        for r in st["requests"]:
            if r["pid"] != pid:
                continue
            kind = r["status"]["kind"]
            item = {"key": r["id"], "group": "mine", "kind": "request", "id": r["id"], **_where(r), "at": r["at"]}
            item["changed"] = r["status"].get("at", r["status"].get("since", r["at"]))
            if kind == "done":
                res = results.get(r["status"]["result"])
                visible = res is not None and self._result_seen_by(res, pid)
                status = "unshared" if not visible else "answered" if pid == HOST or not res["published"] else "shared"
                if visible:
                    item["result"] = res["id"]
            else:
                status = INBOX_STATUS[kind]
                if kind == "failed":
                    item["reason"] = r["status"]["reason"]
            out.append({**item, "status": status})
        if pid == HOST:
            waiting = [
                *({"key": "run:" + r["id"], "kind": "run", "id": r["id"], **_where(r), "by": r["pid"], "at": r["at"]}
                  for r in st["requests"] if r["runner"] == "host" and r["status"]["kind"] == "pending" and r["pid"] != HOST and self._active(r["pid"])),
                *({"key": "share:" + x["id"], "kind": "share", "id": x["id"], **_where(x), **({"by": x["by"]["pid"]} if "pid" in x["by"] else {}), "at": x["at"]}
                  for lst in st["results"].values() for x in lst if self._held(x) and self._from_active(x)),
                *({"key": "fail:" + r["id"], "kind": "fail", "id": r["id"], **_where(r), "by": r["pid"], "at": r["status"]["at"]}
                  for r in st["requests"] if r["runner"] == "host" and r["pid"] != HOST and self._active(r["pid"]) and self._claude_failed(r)),
                # an open report the owner already asked Claude about waits on Claude; the reporter's next addition brings it back
                *({"key": "report:" + f, "kind": "report", "id": f, "by": rep["by"], "at": max([rep["ts"], *(a["ts"] for a in rep.get("adds", []))])}
                  for f, rep in st.get("reports", {}).items() if rep["status"] == "open" and "asked" not in rep),
                *({"key": "merge:" + m["id"], "kind": "merge", "id": m["id"], "by": m["from"], "at": m["at"]}
                  for m in st["mergeRequests"] if m["status"]["kind"] == "pending"),
                *({"key": "join:" + v["pid"], "kind": "join", "id": v["pid"], "by": v["pid"], "at": v["status"]["at"]}
                  for v in st["people"].values() if v["status"]["kind"] == "waiting"),
                *({"key": "people:" + p["id"], "kind": "people", "id": p["id"], "by": p.get("from", p.get("pid")), "at": p["at"]}
                  for p in self._open_claude_proposals()),
                *self._reopen_items(),
            ]
            out += [{**w, "group": "waiting", "changed": w["at"], "status": "open"} for w in waiting]
        for i in out:
            i["unread"] = seen.get(i["key"]) != i["status"]
        return out

    def _reopen_items(self):
        """The owner's `reopen:` Inbox items: a locked decision someone disagreed with late. The key names the newest
        such Disagree's `seq` in the log, so each new one makes the item unread again; `n`, `by` and `at` count and
        name the late Disagrees with the locked answer people hold now, as the digest does."""
        out = []
        for qid in self.state["locks"]:
            acts = self._reopened(qid)  # a removed person's too: the flags they raised stay until Keep or Unlock
            if acts:
                card = self._locked_card(qid)
                holding = {d["pid"] for d in self.state.get("disagreements", {}).get(qid, []) if d["card"] == card}
                held = [e for _, e in acts if e["by"] in holding] or [acts[-1][1]]
                out.append({"key": f"reopen:{qid}:{acts[-1][1].get('seq', acts[-1][0])}", "kind": "reopen", "id": qid, "qid": qid, "by": held[-1]["by"], "at": held[-1]["at"],
                            "n": len(held), "card": card})
        return out

    @staticmethod
    def _claude_failed(r):
        """A request Claude failed, which only Run again moves on; not one the owner cancelled or discarded."""
        return r["status"]["kind"] == "failed" and not r["status"]["cancelled"]

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
        """One unread line per moderator counting new queue items with no Inbox item (proposals, suggestions, offers),
        never one line per item. Requests, shares, reports, merges and joins are the owner's waiting Inbox items instead."""
        for p in pids:
            old = next((n for n in reversed(self.state["notifications"].get(p, [])) if n.get("rollup", {}).get("key") == "queue" and not n["read"]), None)
            k = old["rollup"]["n"] + 1 if old else 1
            self._notify(p, "queue", f"{k} new item{'' if k == 1 else 's'} in the queue.", actor=actor, rollup="queue")

    def _tokenize(self, by, text, field="text", limit=MAX_TEXT):
        """Text `by` wrote with each "@Name" of an active person as <@pid> (tokenize), so a rename or a merge
        shows in it. A token counts toward the field's limit. While names are hidden from `by`, "@Name" stays plain
        text: a token would hand them the pid of the person the name belongs to."""
        if not text:
            return text
        names = [] if self._names_hidden_from(by) else [(v["name"], p) for p, v in self.state["people"].items() if self._active(p)]
        out = tokenize(text, names)
        if len(out) > limit:
            raise DomainError(400, "too-long", f"{field} allows at most {limit} characters; each mention takes more of them than its name.", field=field, max=limit)
        return out

    def _plain(self, text, full):
        """Text with each <@pid> as "@Name" (the last name of someone removed), or "@someone" without `full` or a person."""
        people = self.state["people"]
        return MENTION.sub(lambda m: "@" + (people[m.group(1)]["name"] if full and m.group(1) in people else "someone"), text)

    def _plain_all(self, obj, full):
        if isinstance(obj, str):
            return self._plain(obj, full)
        if isinstance(obj, dict):
            return {k: self._plain_all(v, full) for k, v in obj.items()}
        if isinstance(obj, list):
            return [self._plain_all(v, full) for v in obj]
        return obj

    def _mentioned(self, text, actor):
        """Active pids text mentions (<@pid>), in order, at most MAX_MENTIONS."""
        out = []
        for p in MENTION.findall(str(text or "")):
            if p != actor and self._active(p) and p not in out:
                out.append(p)
        return out[:MAX_MENTIONS]

    def _notify_mentions(self, text, actor, where, *, before="", skip=(), **ref):
        old = set(self._mentioned(before, actor)) if before else set()
        for p in self._mentioned(text, actor):
            if p not in old and p not in skip:
                self._notify(p, "mention", f"mentioned you {where}.", actor=actor, by=actor, body=clip(one_line(text), 160), **ref)

    # -- event log and digest ----------------------------------------------------------------

    def _event(self, kind, **fields):
        log = self.state["log"]
        log["seq"] += 1
        # Claude reads the log: a mention reaches it as "@Name", or "@someone" without digestNames, never as a token.
        ev = {"seq": log["seq"], "at": iso(self.now()), "kind": kind, **self._plain_all(fields, self.state["session"]["settings"]["digestNames"])}
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
        questions, discussion_chars = [], 0
        for q in st["questions"]:
            if q["round"] != n:
                continue
            entry = {"id": q["id"], "text": q["text"], **({"scope": q["scope"]} if q.get("scope") else {})}
            entry.update(purpose=q["purpose"], format=q["format"]["kind"])
            disagreements = self._digest_disagreements(q, by)
            if disagreements:
                entry["disagreements"] = disagreements
            entry["outcome"] = self._outcome(q, by)
            entry.update(self._digest_turns(q, by))
            comments = [c for c in st["discussions"].get(q["id"], []) if self._comment_shown(c)]
            listed = []
            for c in reversed(comments[-MAX_DIGEST_COMMENTS:]):  # newest first, until the digest's budget is spent
                text = clip(c["text"], MAX_DIGEST_COMMENT)
                if discussion_chars + len(text) > MAX_DIGEST_DISCUSSION_CHARS:
                    break
                discussion_chars += len(text)
                listed.append({"text": text, **by(c["pid"]), **({"edited": True} if "edited" in c else {}), **({"askedClaude": True} if "request" in c else {})})
            if listed:
                entry["discussion"] = listed[::-1]
            if len(comments) > len(listed):
                entry["discussionMore"] = f"{len(comments) - len(listed)} earlier comments on the page"
            questions.append(entry)
        late = []
        for q in st["questions"]:
            for c in st["cards"].get(q["id"], []):
                if c["kind"] == "person" and c.get("late") and c["at"] > prev and self._shown(c):
                    late.append({"id": q["id"], "round": c["late"]["round"], "text": self._said(q, c), **_files(c), **by(c["pid"]), **_edited(c)})
            for pid, mark in st.get("lateActs", {}).get(q["id"], {}).items():
                if mark["at"] > prev and self._active(pid):
                    late += [{"id": q["id"], "round": mark["round"], **act, **by(pid)} for act in self._late_acts(q, pid)]
        review = []
        for q in st["questions"]:
            newest = {}
            for f in q["needsReview"]:  # a change not yet reviewed outranks a later possibly-reopened on the same question
                if f["why"]["kind"] != "possibly-reopened" or newest.get(f["because"], f)["why"]["kind"] == "possibly-reopened":
                    newest[f["because"]] = f
            for because, f in newest.items():
                lk = st["locks"].get(because)
                now_ = {"kind": "locked", "text": lk["source"].get("text", "")} if lk else {"kind": "unlocked"}  # a closed poll has no text
                item = {"id": q["id"], "because": because, "now": now_}
                if f["why"]["kind"] == "suggested":
                    item["suggestion"] = f["why"]["suggestion"]
                if f["why"]["kind"] == "possibly-reopened":
                    item["possiblyReopened"] = True
                review.append(item)
        reopened = []
        for i in self._reopen_items():
            q = self._question(i["qid"])
            raised = list(dict.fromkeys(e["by"] for _, e in self._reopened(q["id"])))  # each reason as it is now; a take-back drops it
            locked = self._locked_card(q["id"])
            held = [d for p in raised if self._active(p) for d in st.get("disagreements", {}).get(q["id"], []) if d["pid"] == p and d["card"] == locked]
            lines = [{**said, "reason": d["reason"], **by(d["pid"])} for d in held if (said := self._named(q, d["card"])) is not None]  # never `n`: that is the round
            reopened.append({"id": q["id"], "locked": st["locks"][q["id"]]["source"]["text"], "disagreements": lines})
        results, more, chars = [], 0, 0
        for r in (r for lst in st["results"].values() for r in lst if self._result_shown(r) and r.get("publishedAt", r["at"]) > prev):
            chars += len(r["summary"])
            if len(results) >= MAX_DIGEST_RESULTS or chars > MAX_DIGEST_CHARS:
                more += 1
                continue
            guest = r["by"]["kind"] == "guest-claude"
            results.append({**_where(r), "id": r["id"], "kind": r["kind"], "summary": r["summary"], **({"from": "guest-claude", **by(r["by"]["pid"])} if guest else {})})
        proposals = [{"id": p["id"], "text": p["text"], **by(p["pid"])} for p in st["proposals"] if p["status"]["kind"] == "new" and self._active(p["pid"])]
        proposals_more = len(proposals) - MAX_DIGEST_PROPOSALS
        proposals = proposals[:MAX_DIGEST_PROPOSALS]
        notes = [
            {"qid": a["qid"], "variant": a["variant"], "text": a["text"], "element": _element(a["anchor"]["selector"]), **by(a["pid"])}
            for a in st["annotations"]
            if a["at"] > prev and self._active(a["pid"])
        ]
        digest = {
            "round": n,
            "names": names,
            "questions": questions,
            "late": late,
            "needsReview": review,
            "possiblyReopened": reopened,
            "results": results,
            **({"resultsMore": f"{more} more on the page"} if more else {}),
            "proposals": proposals,
            **({"proposalsMore": f"{proposals_more} more on the page"} if proposals_more > 0 else {}),
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

    def _named(self, q, ref):
        """How the digest names the answer `ref` of q: its text, and its files, so an answer of pictures alone is
        still told apart; None when that answer is gone."""
        try:
            return {"text": self._card_text(q, ref), **_files(self._card(q["id"], ref))}
        except DomainError:
            return None

    def _digest_disagreements(self, q, by):
        """Who disagreed with which answer of q and why, while that answer and its disagreer remain."""
        out = []
        for d in self.state.get("disagreements", {}).get(q["id"], []):
            if not self._active(d["pid"]):
                continue
            named = self._named(q, d["card"])
            if named is not None:
                out.append({**named, "reason": d["reason"], **by(d["pid"])})
        return out

    def _digest_turns(self, q, by):
        """Who passed on q (with their reason), how many active guests gave no signal at all, and on a question
        `for` named people, those people and the ones who have not taken part, by name: the owner named them."""
        st, qid = self.state, q["id"]
        guests = [p for p in st["people"] if p != HOST and self._active(p)]
        targets = [p for p in q.get("for", ()) if self._active(p)]

        def who(p):
            return {"by": st["people"][p]["name"]} if p in targets else by(p)

        passes = st.get("passes", {}).get(qid, {})
        out = {
            "passed": [{**who(p), **({"reason": r["reason"]} if "reason" in r else {})} for p, r in passes.items() if self._active(p)],
            "silent": sum(1 for p in guests if not self._acts(qid, p)),
        }
        if targets:
            out["for"] = [st["people"][p]["name"] for p in targets]
            out["missing"] = [st["people"][p]["name"] for p in targets if not self._took_part(q, p)]
        return out

    def _late_acts(self, q, pid):
        """What pid holds now on q besides a card: each vote, back, reaction, Disagree and Pass, for `late`. A
        pick is the person's card, listed on its own."""
        st, qid, out = self.state, q["id"], []

        def about(ref):
            return self._named(q, ref)

        ref = st["votes"].get(qid, {}).get(pid)
        if ref and not ref.startswith("o:") and about(ref) is not None:
            out.append({"act": "vote", **about(ref)})
        out += [{"act": "back", **about(r)} for r in st.get("backs", {}).get(qid, {}).get(pid, []) if about(r) is not None]
        for r, held in st["reactions"].get(qid, {}).items():
            if pid in held and about(r) is not None:
                out.append({"act": "reaction", **about(r), "reactions": list(held[pid])})
        out += [{"act": "disagree", **about(d["card"]), "reason": d["reason"]} for d in st.get("disagreements", {}).get(qid, []) if d["pid"] == pid and about(d["card"]) is not None]
        mine = st.get("passes", {}).get(qid, {}).get(pid)
        if mine is not None:
            out.append({"act": "pass", "text": "", **({"reason": mine["reason"]} if "reason" in mine else {})})
        return out

    def _digest_people(self, n):
        st = self.state
        qs = [q for q in st["questions"] if q["round"] == n]
        answered, devices = set(), {}
        for q in qs:
            for c in st["cards"].get(q["id"], []):
                if c["kind"] == "person" and self._shown(c):
                    kind = c.get("device") or c.get("deviceInfo", {}).get("kind")
                    if kind:
                        devices[c["pid"]] = kind
            answered.update(p for p in st["people"] if self._active(p) and self._took_part(q, p))
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
            out = {"kind": "locked", "text": src["text"], **_files(src)}
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
            answers, active = [], {p for p in st["people"] if self._active(p)}
            names = st["session"]["settings"]["digestNames"]
            labels = self._options(q)  # multi, scale and rank report through _format_outcome, so a pick is one option
            for c in people:
                picked = labels.get(c.get("pick"))
                if c["text"] or picked or "attachments" in c:
                    ref = card_ref(c)
                    endorsers = [st["people"][v]["name"] for v, held in st["reactions"].get(qid, {}).get(ref, {}).items() if v in active and ENDORSING & set(held)]
                    answers.append({"text": c["text"], **({"picked": picked} if picked else {}), **_files(c), "reactions": self._reaction_counts(qid, ref, active), "endorsedBy": endorsers if names else len(endorsers), **by(c["pid"]), **_edited(c)})
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
            ranked.append(((-tally[ref], ref != "c:rec", c.get("at", 0.0), i), {**entry, **_files(c), **(by(c["pid"]) if c["kind"] == "person" else {}), **_edited(c)}))
        if not ranked:
            return {"kind": "unanswered"}
        ranked.sort(key=lambda pair: pair[0])
        keep = 3 if q["format"]["kind"] == "text" else 6
        return {"kind": "open", "top": [entry for _, entry in ranked[:keep]]}

    def _own_options(self, q):
        """Active people's own Something else options on q, as their cards."""
        return [c for c in self.state["cards"].get(q["id"], []) if self._is_other(c) and self._shown(c)]

    def _format_outcome(self, q, by, *, closed):
        """The digest outcome of a multi, scale or rank question: counts per option (multi, None of these
        a row of its own, marked `none`), counts per value with the mean and median (scale), Borda totals and the full orders given (rank);
        each with people's own options, their backers (author included), and the comments."""
        qid, fmt = q["id"], q["format"]
        cards = [c for c in self.state["cards"].get(qid, []) if c["kind"] == "person" and self._shown(c)]
        labels = self._options(q)
        others = [{"text": c["text"], "backers": len(self._votes_on(qid, card_ref(c))) + 1, **by(c["pid"]), **_edited(c)} for c in self._own_options(q)]
        comments = [{"text": c["text"], **by(c["pid"]), **_edited(c)} for c in cards if c["text"] and not self._is_other(c)]
        if fmt["kind"] == "multi":
            picked = [c["picks"] for c in cards if c.get("picks")]
            counts = [{"option": label, "picks": sum(1 for p in picked if o in p), **({"none": True} if o == NONE else {})} for o, label in labels.items()]
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

    def _op_set_repo(self, op):
        """The session's GitHub repository and pinned commit, which the page links #N and repository paths against.
        Both are replaced together: no commit removes the old one, and an empty repo removes both."""
        repo, commit, sess = op["repo"], op.get("commit"), self.state["session"]
        if repo and not REPO.fullmatch(repo):
            raise _bad("repo", "repo must be a GitHub owner/name.")
        if commit is not None and not (repo and COMMIT.fullmatch(commit)):
            raise _bad("commit", "commit must be a full 40-character lowercase SHA, with a repo.")
        sess.pop("repo", None)
        sess.pop("commit", None)
        if repo:
            sess["repo"] = repo
            if commit:
                sess["commit"] = commit
        return {"repo": repo, **({"commit": commit} if commit else {})}

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
            q = self._parse_question(qi, round_n=n, origin={"kind": "claude"}, known=known, field=f"questions[{i}]", made=made)
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
                    q = self._parse_question(qi, round_n=round_n, origin=origin, known=known, field=f"{field}.question", made=made)
                else:
                    q = {
                        "id": self._next_qid(known),
                        "text": prop["text"],
                        "alternatives": [],
                        "dependsOn": [],
                        "round": round_n,
                        "purpose": "gather",
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
                    {"id": sid, "pid": prop["pid"], "text": text, "note": note, "at": self.now(), "fromProposal": prop["id"], "status": {"kind": "open"},
                     **({"attachments": list(prop["attachments"])} if "attachments" in prop else {})}
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
        """A result on a question, or with no qid the answer to a request about the whole session (`request` required)."""
        q = None if op.get("qid") is None else self._question(op["qid"])
        req = None
        if op.get("request") is not None:
            req = self._request(op["request"], runner="host")
            if req["status"]["kind"] != "running":
                raise DomainError(409, "wrong-status", f"Request {req['id']} is {req['status']['kind']}.", status=req["status"]["kind"])
            if req.get("qid") != (q and q["id"]):
                raise _bad("qid", f"Request {req['id']} is {_on(req)}.")
        elif q is None:
            raise _bad("qid", "A result names its question, or the request about the whole session it answers.")
        # The host's own request needs no review; a guest's needs the owner's Share only while the session reviews answers.
        # Asked for everyone, the answer is shared now; asked Just me, it goes to its asker (and the owner) alone.
        # Unreviewed sharing is for ask and research answers to an asker still in: explore, design and prototype read
        # the linked project, so they wait for the owner.
        out = req is not None and (req["pid"] == HOST or (not self._review() and req["kind"] in ("ask", "research") and self._active(req["pid"])))
        me = req is not None and req.get("audience") == "me"
        res = self._new_result(q and q["id"], req, op, {"kind": "host-claude"}, out and not me)
        if out and me:
            res["private"] = True
        elif out:
            res["publishedAt"] = res["at"]
            self._claude_says(res, req)
        if out and req["pid"] != HOST:
            self._done(res, req, None)
        return {"id": res["id"], "published": res["published"]}

    def _op_fail_request(self, op):
        req = self._request(op["request"], runner="host")
        if req["status"]["kind"] not in ("pending", "running"):
            raise DomainError(409, "wrong-status", f"Request {req['id']} is {req['status']['kind']}.", status=req["status"]["kind"])
        reason = _text(op, "reason", limit=MAX_NOTE)
        req["status"] = {"kind": "failed", "at": self.now(), "reason": reason, "cancelled": False}
        self._notify(req["pid"], "request", f"Your request {_on(req)} failed.", qid=req.get("qid"), body=reason)
        return {"id": req["id"], "status": "failed"}

    def _op_add_reference(self, op):
        return self._edit_reference({"qid": op["qid"], "reference": op["reference"]})

    def _op_remove_reference(self, op):
        return self._edit_reference({"qid": op["qid"], "remove": op["index"]})

    def _op_set_purpose(self, op):
        return self._set_purpose(op)

    def _op_set_for(self, op):
        return self._set_for(op)

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

    def _op_add_live(self, op):
        """Record a live prototype, pending until the owner's Approve: a build folder under staging/ or a port on
        127.0.0.1 that is not one of the session's own. Nothing starts here."""
        if not self._live_on():
            raise DomainError(403, "live-off", "Live prototypes are off in this session; the owner turns them on in Settings.")
        if self._ended():
            raise DomainError(409, "wrong-status", "The session has ended.", status="ended")
        label = _text(op, "label")
        note = _text(op, "note", limit=MAX_NOTE) if op.get("note") is not None else None
        if "port" in op:
            target = {"kind": "port", "port": self._live_port(op["port"])}
        else:
            target = {"kind": "folder", "folder": _live_folder(op["folder"], self.path.parent)}
        lives = self.state.get("lives", [])
        if sum(1 for e in lives if e["status"]["kind"] != "ended") >= MAX_LIVES:
            raise DomainError(409, "lives-full", f"A session runs at most {MAX_LIVES} live prototypes at once; stop one first.", max=MAX_LIVES)
        lid = f"L{1 + max((int(e['id'][1:]) for e in lives), default=0)}"  # entries are never removed, so an id never returns
        entry = {"id": lid, "label": label, **({"note": note} if note else {}), "target": target, "at": self.now(), "status": {"kind": "pending"}}
        self.state.setdefault("lives", []).append(entry)
        return {"id": lid, "status": "pending"}

    def _live_port(self, port):
        """A live entry's port: refused when it is the session's own guest or control port (PORTS_FILE), and when those
        cannot be read, since the check would then pass blind."""
        try:
            ports = json.loads((self.path.parent / PORTS_FILE).read_text(encoding="utf-8"))
            own = {int(ports["guest"]), int(ports["control"])}
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise DomainError(503, "live-unavailable", "The session's own ports are unknown, so no port can be checked; run share.sh ensure-running.") from exc
        if port in own:
            raise _bad("port", "A live prototype never runs on the session's own guest or control port.")
        return port

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

    def _op_resolve_report(self, op):
        """The owner asked in the terminal to mark a problem report seen or resolved, as the owner's page does."""
        return self._act_on_report(HOST, op["id"], op["action"])

    def _op_share_result(self, op):
        """The owner asked in the terminal to share an unshared answer with everyone, as the result-share route does."""
        return self._share_result(HOST, op["id"])

    def _op_take_down_result(self, op):
        """The owner asked in the terminal to take a shared answer down, as the owner's page does."""
        return self._act_on_result(HOST, op["id"], "takedown")

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
                st["credentials"].pop("devices", None)  # a new owner link, as a rotation makes
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
                    "results": sum(1 for lst in st["results"].values() for r in lst if self._held(r) and self._from_active(r)),
                    "uploads": sum(1 for u in st["uploads"] if u["status"]["kind"] == "offered"),
                    "merges": sum(1 for m in st["mergeRequests"] if m["status"]["kind"] == "pending"),
                    "joins": sum(1 for p in st["people"].values() if p["status"]["kind"] == "waiting"),
                    "proposals": sum(1 for p in st["proposals"] if p["status"]["kind"] == "new" and self._active(p["pid"])),
                    "reports": sum(1 for r in st.get("reports", {}).values() if r["status"] == "open"),
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
            return {"title": s["title"], "ended": self._ended(), "joinNeedsKey": bool(s["guestKey"])}

    def _base(self):
        """The part of every person's snapshot that is the same for all of them; built once per rev."""
        st = self.state
        if self._base_cache and self._base_cache[0] == st["rev"]:
            return self._base_cache[1]
        active = {p for p in st["people"] if self._active(p)}
        # an alternative a state saved before the refusal holds that restates the recommendation folds away, as on the 1:1
        # page, unless someone backs it: then it stays, so the page and the tally agree on the leader
        folded = {q["id"]: {a["key"] for a in q["alternatives"] if question_shape.restates(a["text"], q.get("recommendation"))} for q in st["questions"]}
        cards = {
            qid: [self._public_card(qid, c, active) for c in lst if self._shown(c) and not (c["kind"] == "claude" and c["key"] in folded.get(qid, ()) and not self._backed(qid, card_ref(c)))]
            for qid, lst in st["cards"].items()
        }
        suggestions = {}
        for qid, lst in st["suggestions"].items():
            by = st["suggestionVotes"].get(qid, {})
            suggestions[qid] = [{**s, "votes": sorted(v for v, sid in by.items() if sid == s["id"] and v in active)} for s in lst if s["pid"] in active]
        cur = self._current_round()
        chat = self._visible_chat(active)
        discussions = self._discussions_for(None, active)
        # a profile picture everyone may see: the owner's at once, a guest's once the owner approved it
        avatars = {p: u["id"] for p, u in _avatars(st["uploads"]).items() if _approved(u)}
        base = {
            "rev": st["rev"],
            "title": st["session"]["title"],
            "goal": st["session"]["goal"],
            "intro": st["session"].get("intro", ""),
            **{k: st["session"][k] for k in ("repo", "commit") if k in st["session"]},
            "ended": self._ended(),
            "settings": st["session"]["settings"],
            "rounds": st["rounds"],
            "round": {"n": cur["n"], "status": cur["status"]["kind"]} if cur else None,
            "questions": [_question_view(q) for q in st["questions"]],
            "cards": cards,
            "locks": st["locks"],
            "suggestions": suggestions,
            "disagreements": {q: [d for d in lst if d["pid"] in active] for q, lst in st.get("disagreements", {}).items()},
            "results": {q: shown for q, lst in st["results"].items() if (shown := [r for r in lst if self._result_shown(r)])},
            "chat": chat[-CHAT_WINDOW:],
            "discussions": discussions,
            "annotations": [a for a in st["annotations"] if a["pid"] in active],
            "people": [
                {**{k: v[k] for k in ("pid", "name", "role", "trusted", "color", "joinedAt")}, **({"avatar": avatars[v["pid"]]} if v["pid"] in avatars else {})}
                for v in st["people"].values()
                if v["pid"] in active
            ],
            "requestCounts": self._request_counts(),
            "files": self._files_of([*_answers(cards), *chat[-CHAT_WINDOW:], *_flat(discussions), *_flat(suggestions)]),
            # the last names of people no longer here whom a text mentions, so <@pid> still reads as them
            "mentions": {p: st["people"][p]["name"] for p in self._mentioned_anywhere() if p in st["people"] and p not in active},
        }
        # every upload what everyone reads carries, older chat included: who may read a picture back (upload_image)
        self._public_uploads = {uid for r in [*_answers(cards), *chat, *_flat(discussions), *_flat(suggestions)] for uid in r.get("attachments", [])}
        # Follow-up 32: received pictures offered on a question that no record ever carried (from before attachments) show
        # under that question; a form's draft or one a record carried, even one since cleared or deleted, never does
        # (both marks are server-set: at offer and on the first carrying write).
        # Everyone sees the approved ones, the owner and each uploader also those waiting for approval (snapshot).
        self._carried = {u["id"] for u in st["uploads"] if u.get("carried")}
        self._loose_pics = [u for u in st["uploads"] if u.get("qid") and _shows_as_image(u) and not u.get("draft") and not u.get("carried") and self._active(u["pid"])]
        approved = [u for u in self._loose_pics if _approved(u)]
        if approved:
            base["questionPics"] = _pics_by_q(approved)
            base["files"].update(self._files_of([{"attachments": [u["id"] for u in approved]}]))
            self._public_uploads |= {u["id"] for u in approved}
        if len(chat) > CHAT_WINDOW:
            base["chatBefore"] = base["chat"][0]["id"]  # older messages exist: GET /api/chat?before=<it> reads them
            touched = max((self._chat_touch.get(m["id"], 0) for m in chat[:-CHAT_WINDOW]), default=0)
            if touched:
                base["chatTouched"] = touched  # a page holding older messages reads them again when this moves
        base = json.loads(json.dumps(base))
        self._base_cache = (st["rev"], base)
        return base

    def _mentioned_anywhere(self):
        """Who a text everyone may read mentions; a hidden comment's mentions name no one here."""
        hidden = {id(c) for lst in self.state["discussions"].values() for c in lst if "hidden" in c}
        return sorted({p for h, k in mention_texts(self.state) if id(h) not in hidden for p in MENTION.findall(h[k])})

    def _files_of(self, records):
        """C44: what a viewer reads of the files the records they see carry (the owner accepted each): name, kind, size
        and where it stands, and `image` on a received picture GET /api/upload/image reads back; never where it is saved."""
        ups = {u["id"]: u for u in self.state["uploads"]}
        out = {}
        for rec in records:
            for uid in rec.get("attachments", []):
                u = ups.get(uid)
                if u is not None and u["status"]["kind"] in UPLOAD_ACCEPTED:
                    pic = _shows_as_image(u)
                    out[uid] = {"file": u["file"], "ext": u["ext"], "size": u["size"], "status": u["status"]["kind"],
                                **({"image": True} if pic and _approved(u) else {"awaitsHost": True} if pic else {})}
        return out

    def upload_image(self, pid, body):
        """GET /api/upload/image?id=: a received picture, as a data: URL whose type comes from its bytes, to its uploader,
        the owner, and whoever reads something that carries it. Any other upload, or one the viewer does not see, is 404."""
        uid = _ident(_body(body), "id")
        with self._lock:
            me = self._person(pid)
            u = next((u for u in self.state["uploads"] if u["id"] == uid), None)
            shown = u is not None and _shows_as_image(u) and self._sees_upload(pid, me, u)
            stored = u["status"]["stored"] if shown else ""
        f = self.path.parent / stored if stored and STORED_PATH.fullmatch(stored) else None
        data = f.read_bytes() if f is not None and f.is_file() and f.stat().st_size <= SHOWN_IMAGE_MAX else b""
        mime = next((UPLOAD_KINDS[k][0] for k in sorted(IMAGE_KINDS) if data and UPLOAD_KINDS[k][1](data[:64])), None)
        if mime is None:
            raise DomainError(404, "not-found", f"No picture {uid[:40]}.")
        return {"id": uid, "image": f"data:{mime};base64,{base64.b64encode(data).decode()}"}

    def _sees_upload(self, pid, me, u):
        """Whether pid reads something that carries u. A record carries only its author's uploads, so beyond what
        everyone reads (the cached _public_uploads) only the uploader, the owner, and a moderator through a proposal
        see one: a hidden answer or comment and a request reach their author and the owner alone."""
        self._base()
        if pid in (HOST, u["pid"]):
            return True
        if not _approved(u):
            return False
        if u.get("avatar"):  # what people lists show: hidden with the names, and never a picture since replaced
            names = "full" if me["role"] in ("owner", "leader") else self.state["session"]["settings"]["names"]
            return names == "full" and any(p.get("avatar") == u["id"] for p in self._base()["people"])
        if u["id"] in self._public_uploads:
            return True
        return me["role"] == "leader" and self._active(u["pid"]) and any(u["id"] in p.get("attachments", ()) for p in self.state["proposals"])

    def _backed(self, qid, ref):
        """Whether anyone stands behind card `ref`: a vote or backing, a reaction, or the question's lock."""
        st = self.state
        return (any(r == ref for r in st["votes"].get(qid, {}).values())
                or any(ref in refs for refs in st.get("backs", {}).get(qid, {}).values())
                or any(st["reactions"].get(qid, {}).get(ref, {}).values())
                or (st["locks"].get(qid) or {}).get("source", {}).get("card") == ref)

    def _public_card(self, qid, c, active):
        """One card as people read it: never `view`, `deviceInfo` or `history`; with its ref, the
        active people who vote for or back it, and its Gather reaction counts."""
        ref = card_ref(c)
        shown = {k: v for k, v in c.items() if k not in ("view", "deviceInfo", "history")}
        shown["ref"] = ref
        shown["votes"] = sorted(self._votes_on(qid, ref))
        shown["reactions"] = self._reaction_counts(qid, ref, active)
        return shown

    def _reaction_counts(self, qid, ref, active):
        """How many active people hold each reaction on one answer (a person counts once per reaction they hold)."""
        counts = dict.fromkeys(REACTIONS, 0)
        for voter, held in self.state["reactions"].get(qid, {}).get(ref, {}).items():
            if voter in active:
                for r in held:
                    counts[r] += 1
        return counts

    @staticmethod
    def _public_chat(m, active):
        """A chat message with only active people's reactions."""
        if "reactions" not in m:
            return m
        reactions = {e: [p for p in pids if p in active] for e, pids in m["reactions"].items()}
        out = {k: v for k, v in m.items() if k != "reactions"}
        reactions = {e: pids for e, pids in reactions.items() if pids}
        return {**out, "reactions": reactions} if reactions else out

    def _visible_chat(self, active):
        """Every kept message whose author is in, as people read it, oldest first."""
        return [self._public_chat(m, active) for m in self.state["chat"] if m["pid"] in active]

    def _masked_chat(self, msgs, pid):
        """Messages as this viewer reads them: where names are masked, others' reactions name nobody."""
        me = self._person(pid)
        if me["role"] in ("owner", "leader") or self.state["session"]["settings"]["names"] == "full":
            return msgs
        return [{**m, "reactions": {e: [p if p == pid else "" for p in ps] for e, ps in m["reactions"].items()}} if "reactions" in m else m for m in msgs]

    def chat_page(self, pid, query):
        """GET /api/chat?before=<id>|around=<id>[&limit=<n>]: chat beyond the snapshot's window, read as the snapshot
        reads it. `before` gives the `limit` messages just older than that one; `around` gives `limit` messages with
        that one in the middle. Each answer names `before`, its oldest message, while older ones exist."""
        before, around = query.get("before"), query.get("around")
        if (before is None) == (around is None):
            raise _bad("before", "Give before or around, a message id.")
        raw = query.get("limit", str(CHAT_WINDOW))
        if not re.fullmatch(r"[0-9]{1,3}", raw) or not 1 <= int(raw) <= CHAT_PAGE_MAX:
            raise _bad("limit", f"limit must be a whole number from 1 to {CHAT_PAGE_MAX}.")
        limit = int(raw)
        with self._lock:
            self._person(pid)
            msgs = self._visible_chat({p for p in self.state["people"] if self._active(p)})
            at = next((i for i, m in enumerate(msgs) if m["id"] == (before or around)), None)
            if at is None:
                raise DomainError(404, "not-found", "No such message.")
            end = at if before else min(len(msgs), max(0, at - limit // 2) + limit)
            start = max(0, end - limit)
            out = {"chat": copy.deepcopy(self._masked_chat(msgs[start:end], pid))}
            if files := self._files_of(msgs[start:end]):
                out["files"] = files  # what the page's messages carry, as the snapshot's files reads
            if start:
                out["before"] = msgs[start]["id"]
            return out

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
                key = r.get("qid", GENERAL)
                by_q[key] = by_q.get(key, 0) + 1
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
            if not owner:
                snap["questions"] = self._guest_questions()
            lives = self._lives_view(owner, snap["questions"])
            if lives is not None:
                snap["lives"] = lives
            if owner or any(c["pid"] == pid and "hidden" in c for lst in st["discussions"].values() for c in lst):
                snap["discussions"] = self._discussions_for(pid, {p["pid"] for p in base["people"]})
            if mode != "full":
                snap["people"] = [{**{k: v for k, v in p.items() if k != "avatar"}, "name": initials(p["name"]) if mode == "initials" else "Someone"} for p in base["people"]]
                snap["mentions"] = {p: initials(n) if mode == "initials" else "Someone" for p, n in base["mentions"].items()}
                snap["cards"] = {q: [{**c, "votes": [v if v == pid else "" for v in c["votes"]]} for c in lst] for q, lst in snap["cards"].items()}
                snap["chat"] = self._masked_chat(base["chat"], pid)
                snap["discussions"] = {q: self._masked_chat(lst, pid) for q, lst in snap["discussions"].items()}
                snap["suggestions"] = {q: [{**s, "votes": [v if v == pid else "" for v in s["votes"]]} for s in lst] for q, lst in base["suggestions"].items()}
                snap["disagreements"] = {q: [{**d, "pid": d["pid"] if d["pid"] == pid else ""} for d in lst] for q, lst in base["disagreements"].items()}
            snap.update(self._presence_view())
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
                "passes": {q: dict(by[pid]) for q, by in st.get("passes", {}).items() if pid in by},
                "discussionSeen": dict(st["discussionSeen"].get(pid, {})),
                "aboutYou": copy.deepcopy(st["aboutYou"].get(pid)),
            }
            visible = [p for p in st["proposals"] if self._active(p["pid"]) and (moderator or p["pid"] == pid)]
            snap["proposals"] = copy.deepcopy(visible)
            snap["myRequests"] = copy.deepcopy([r for r in st["requests"] if r["pid"] == pid])
            snap["myReports"] = [self._my_report_view(f, r) for f, r in st.get("reports", {}).items() if r["by"] == pid]
            snap["inbox"] = self._inbox(pid)
            snap["me"]["watcher"] = pid in st["credentials"].get("watchers", {}).values()
            askers = {r["id"]: r["pid"] for r in st["requests"]}
            for qid, lst in st["results"].items():  # unshared answers I see: my Just me ones, and my own Claude's
                held = {r["id"] for r in lst if not r["published"] and self._result_seen_by(r, pid, askers)}
                if held and not owner:
                    snap["results"] = {**snap["results"], qid: copy.deepcopy([r for r in lst if self._result_shown(r) or r["id"] in held])}
            snap["myMergeRequests"] = copy.deepcopy([m for m in st["mergeRequests"] if m["from"] == pid])
            # carried: something sent carries it (or did), so taking it off a form leaves the upload alone
            snap["myUploads"] = [{**self._upload_view(u, owner=owner), **({"carried": True} if u["id"] in self._carried else {})} for u in st["uploads"] if u["pid"] == pid]
            seen = [*(_answers(own) if own else []), *(_flat(snap["discussions"]) if snap["discussions"] is not base["discussions"] else []),
                    *visible, *snap["myRequests"], *(st["requests"] if owner else [])]
            if any("attachments" in r for r in seen):  # what only this viewer reads: hidden answers and comments, proposals, requests
                snap["files"] = {**base["files"], **self._files_of(seen)}
            waiting = [u for u in self._loose_pics if not _approved(u) and (owner or u["pid"] == pid)]
            if waiting:
                snap["questionPics"] = _pics_by_q([u for u in self._loose_pics if _approved(u) or u in waiting])
                snap["files"] = {**snap["files"], **self._files_of([{"attachments": [u["id"] for u in waiting]}])}
            if moderator:
                snap["guestKey"] = st["session"]["guestKey"]
                snap["behind"] = self._behind()
            if owner:
                snap["requests"] = copy.deepcopy([r for r in st["requests"] if r["runner"] == "host"])
                snap["results"] = {q: copy.deepcopy(kept) for q, lst in st["results"].items() if (kept := [r for r in lst if self._from_active(r)])}
                snap["mergeRequests"] = copy.deepcopy([m for m in st["mergeRequests"] if m["status"]["kind"] == "pending"])
                snap["claudeProposals"] = copy.deepcopy(self._open_claude_proposals())
                snap["uploads"] = [self._upload_view(u, owner=True) for u in st["uploads"] if self._active(u["pid"])]
                snap["reports"] = [self._report_view(f, r) for f, r in st.get("reports", {}).items() if r["status"] != "resolved"]
                snap["passes"] = {q: {p: dict(r) for p, r in by.items() if self._active(p)} for q, by in st.get("passes", {}).items()}
                snap["aboutYou"] = copy.deepcopy(st["aboutYou"])
                snap["decisions"] = copy.deepcopy(st.get("decisions", []))
                snap["ownerDevices"] = sorted((dict(d) for d in st["credentials"].get("devices", {}).values()), key=lambda d: d["at"])
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

    def _presence_view(self):
        """The snapshot's time-and-presence part, the same for every viewer: `serverTime`, `presence` and `lastSeen`.
        GET /api/state sends it alone when nothing else in the viewer's snapshot changed."""
        now = self.now()
        here = self._present()
        return {
            "serverTime": now,
            "presence": [self._presence_entry(p, v, now) for p, v in self._presence.items() if p in here],
            "lastSeen": {p: self._seen(v) for p, v in self._presence.items() if p not in here and self._active(p)},
        }

    def presence_view(self, pid):
        with self._lock:
            self._person(pid)
            return self._presence_view()

    def _presence_entry(self, pid, v, now):
        """One wire.schema.json `presence` entry from the person's live tabs: q and typing from a visible tab
        before a hidden one, and within each the tab focused or shown most recently (a locked phone used last
        loses to a desk window that kept focus), else (no live tab sends `lastFocus`) the latest beat, so a person
        with tabs on two questions shows on one; typing lasts TYPING_TTL after that tab's beat. Active while any
        live tab is, else away since the last one went away. Just joined with no beat yet is active."""
        live = [b for b in v["tabs"].values() if now - b["seen"] < OFFLINE_AFTER]
        if not live:
            return {"pid": pid, "q": "", "typing": False, "chatTyping": False, "state": "active"}
        ranked = any("focusAt" in b for b in live)
        shown = max(reversed(live), key=lambda b: (b["visible"], b.get("focusAt", float("-inf"))) if ranked else 0)  # a tie goes to the later beat
        fresh = now - shown["seen"] < TYPING_TTL
        entry = {"pid": pid, "q": shown["q"], "typing": shown["typing"] and fresh, "chatTyping": shown["chatTyping"] and fresh}
        sinces = [self._away_since(b, now) for b in live]
        return {**entry, "state": "active"} if None in sinces else {**entry, "state": "away", "since": max(sinces)}

    def _behind(self):
        """Moderators only: per active guest, how many unlocked questions of the open current round still ask
        them for an answer (`_owes`), the count the person's own page shows."""
        st = self.state
        cur = self._current_round()
        if cur is None or cur["status"]["kind"] != "open":
            return {}
        qs = [q for q in st["questions"] if q["round"] == cur["n"] and q["id"] not in st["locks"]]
        return {p: sum(1 for q in qs if self._owes(q, p)) for p in st["people"] if p != HOST and self._active(p)}


def prototype_tiers(settings):
    """The prototype views a session offers: its `prototypeTiers`, or screenshots and HTML snapshots when absent."""
    return list(settings.get("prototypeTiers", DEFAULT_PROTOTYPE_TIERS))


def _guest_questions(questions, tiers):
    """`questions` as guests see them under `tiers`: a variant's pictures (`shots`, or an `asset` picture) leave while
    screenshots are off, its html file (`snapshot`, or an `asset` html file) while snapshots are off, and its live link
    while live prototypes are off, each view on its own. A question none of that changes is shared, not copied."""
    off = {t for t in PROTOTYPE_TIERS if t not in tiers}
    if not off:
        return questions
    gone = {k for k, t in (("shots", "screenshot"), ("snapshot", "snapshot"), ("live", "live")) if t in off}

    def view(v):
        drop = gone | ({"asset"} if "asset" in v and ("snapshot" if v["asset"].endswith(".html") else "screenshot") in off else set())
        return {k: x for k, x in v.items() if k not in drop} if drop & v.keys() else v

    out = []
    for q in questions:
        if q["format"]["kind"] == "prototype":
            vs = [view(v) for v in q["format"]["variants"]]
            if any(a is not b for a, b in zip(vs, q["format"]["variants"])):
                q = {**q, "format": {**q["format"], "variants": vs}}
        out.append(q)
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
                raise _bad("theme", "theme takes mode (" + ", ".join(THEME_VALUES["mode"]) + "), accent (" + ", ".join(THEME_VALUES["accent"])
                           + ") and palette (" + ", ".join(THEME_VALUES["palette"]) + ").")
        elif k == "guestPopups":
            if not isinstance(v, list) or any(x not in GUEST_POPUPS for x in v) or len(set(v)) != len(v):
                raise _bad(k, f"guestPopups is a list of {', '.join(GUEST_POPUPS)}, each at most once.")
        elif k == "prototypeTiers":
            if not isinstance(v, list) or any(x not in PROTOTYPE_TIERS for x in v) or len(set(v)) != len(v):
                raise _bad(k, f"prototypeTiers is a list of {', '.join(PROTOTYPE_TIERS)}, each at most once.")
        elif k in SETTING_VALUES:
            if v not in SETTING_VALUES[k]:
                raise _bad(k, f"{k} must be one of {', '.join(SETTING_VALUES[k])}.")
        elif not isinstance(v, bool):
            raise _bad(k, f"{k} must be true or false.")
    for k, v in patch.items():
        if k == "theme":
            settings["theme"] = {**settings["theme"], **v}
        elif k == "guestPopups":
            settings[k] = [x for x in GUEST_POPUPS if x in v]
        elif k == "prototypeTiers":
            settings[k] = [x for x in PROTOTYPE_TIERS if x in v]
        else:
            settings[k] = v
    return settings

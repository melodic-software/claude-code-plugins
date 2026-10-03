"""Local interview surface. 127.0.0.1 only, Python 3 stdlib.

Usage: python server.py --dir DATA_DIR [--port PORT] [--nonce NONCE]
  --dir     data dir (required)
  --port    default 0: a free port; the bound port is what the session files record
  --nonce   echoed into the session files so `round.py ensure-running` knows its own start

Start it through `round.py ensure-running`, which starts it detached and reuses a running one.
questions.json is Claude's file (written by round.py). responses.json is the page's.
Answers arrive by token-guarded POST /api/answer. The transport is session_bridge's loopback
adapter: the page gets state over SSE (/events), and Claude's watcher long-polls GET /api/wait
under a one-watcher lease; responses.json is the event log it delivers.
"""

import argparse
import hashlib
import html
import json
import os
import secrets
import sys
import tempfile
import time
from pathlib import Path, PureWindowsPath
from urllib.parse import quote

from session_bridge import (
    MAX_STREAMS,  # noqa: F401  # the stream limits, read through this module by its tests
    PING_SECONDS,  # noqa: F401
    Conflict,
    LoopbackHandler,
    LoopbackWatcher,
    now_iso,
    replace_into,
    serve,
    session_files,
)

HERE = Path(__file__).resolve().parent
SCHEMA_VERSION = "1.0"
EMPTY_RESPONSES = {
    "schemaVersion": SCHEMA_VERSION,
    "seq": 0,
    "responses": {},
    "history": {},
    "events": [],
}
# One-line free-text cap; a hedged decision's condition is one.
LINE_CAP = 500
DECISIONS = {"accept", "alt", "own", "defer", "hedged", "reopen"}
# Requests to Claude that record no decision. `research` and `cancel-research` name no skill or plugin.
REQUESTS = {"ask", "rephrase", "research", "cancel-research"}
# Events not tied to a question; `confirm-understanding` answers the restatement, and
# `accept-audit` lists the questions one click accepted (each also gets its own `accept`).
FREE = {"note", "wrapup", "confirm-understanding", "accept-audit"}
# Kinds that carry `alt`; `confirm` carries a commitment index and records no decision,
# `confirm-understanding` carries `confirm` or `off`, and `accept-audit` the round id.
WITH_ALT = {"alt", "confirm", "confirm-understanding", "accept-audit"}
UNDERSTANDING = ("confirm", "off")
API = 2
MAX_BODY = 64 * 1024
# A file visual larger than this is neither served nor inlined.
MAX_VISUAL_FILE = 4 * 1024 * 1024
OCTET = "application/octet-stream"
IMAGE_TYPES = {
    ".png": "png",
    ".jpg": "jpeg",
    ".jpeg": "jpeg",
    ".gif": "gif",
    ".webp": "webp",
    ".svg": "svg+xml",
}
# A new-tab link (/api/visual-open) works once, within this many seconds of its mint.
OPEN_SECONDS = 10
PAGE_CSP = (
    "default-src 'self'; script-src 'self' 'unsafe-inline'; "
    "style-src 'self' 'unsafe-inline'; img-src 'self' data:; "
    "connect-src 'self'; frame-src 'self' about:; frame-ancestors 'none'; "
    "form-action 'none'; base-uri 'none'"
)
# A visual may never name a runtime file: the session files and their transient temp copies
# hold the token, so every dotfile path component, lock and temp file is refused.
RUNTIME_SUFFIXES = (".lock", ".tmp")


def runtime_path(rel):
    """True when any part of the data-dir-relative path is a dotfile, a lock or a temp file."""
    return any(
        p.startswith(".") or p.lower().endswith(RUNTIME_SUFFIXES) for p in rel.parts
    )


QUIET_SECONDS = 3.0  # a found event waits this long for more before the watcher wakes
BURST_SECONDS = 12.0  # never holding it longer than this in all
NAME = "interview"  # names the session files and the token header (session_bridge)
SESSION_JSON = session_files(NAME)[0]
REPO_SETTINGS = Path(".claude") / "interview-surface.json"

# Settings, lowest layer first: plugin default, repo file, user file, the data dir's settings.json.
DEFAULT_SETTINGS = {
    "port": 0,
    "openBrowser": True,
    "shortcuts": True,
    "undoSeconds": 5,
    "checkpoint": 0,
    "theme": "auto",
    "density": "compact",
    "minText": 14,
    "displayName": "You",
    "waitTimeout": 90,
    "staleDepth": "direct",
    "leaseTimeout": 600,
}
SETTING_RULES = {
    "port": ("int", 0, 65535),
    "openBrowser": ("bool",),
    "shortcuts": ("bool",),
    "undoSeconds": ("int", 0, 60),
    "checkpoint": ("int", 0, 500),
    "theme": ("enum", ("auto", "light", "dark")),
    "density": ("enum", ("compact", "comfortable")),
    "minText": ("int", 10, 32),
    "displayName": ("str",),
    "waitTimeout": ("int", 5, 110),
    "staleDepth": ("enum", ("direct",)),
    "leaseTimeout": ("int", 5, 3600),
}
REPO_KEYS = set(DEFAULT_SETTINGS) - {"displayName"}
USER_ONLY = {"browserCommand"}  # read by ensure-running, never sent to the page


def setting_error(key, value):
    """None when value is valid for key, else the reason."""
    kind, *rule = SETTING_RULES[key]
    if kind == "bool":
        ok = isinstance(value, bool)
    elif kind == "int":
        ok = (
            isinstance(value, int)
            and not isinstance(value, bool)
            and rule[0] <= value <= rule[1]
        )
    elif kind == "enum":
        ok = value in rule[0]
    else:
        ok = isinstance(value, str) and bool(value.strip())
    if ok:
        return None
    want = {
        "bool": "true or false",
        "int": f"an integer from {rule[0]} to {rule[1]}" if kind == "int" else "",
        "enum": " or ".join(rule[0]) if kind == "enum" else "",
        "str": "a non-empty string",
    }[kind]
    return f"{key} must be {want}, got {json.dumps(value)}"


def token_map(value):
    """A {light: {token: value}, dark: {...}} map with string tokens and values, or None."""
    if not isinstance(value, dict) or not set(value) <= {"light", "dark"}:
        return None
    for tokens in value.values():
        if not isinstance(tokens, dict) or not all(
            isinstance(k, str) and isinstance(v, str) for k, v in tokens.items()
        ):
            return None
    return value


def repo_root(data_dir):
    """CLAUDE_PROJECT_DIR when set, else the data dir's nearest ancestor holding .git, else None."""
    env = os.environ.get("CLAUDE_PROJECT_DIR")
    if env:
        return Path(env)
    start = Path(data_dir).resolve()
    for p in (start, *start.parents):
        if (p / ".git").exists():
            return p
    return None


class Settings:
    """Resolves each key through the layers and names the layer its value came from.

    Problems (an unreadable file, an unknown or restricted key, an invalid value) are noted on
    stderr once each; the key then keeps the value of the layer below.
    """

    def __init__(self, repo):
        self.repo_file = Path(repo) / REPO_SETTINGS if repo else None
        self._noted = set()

    def note(self, msg):
        if msg not in self._noted:
            self._noted.add(msg)
            print(f"settings: {msg}", file=sys.stderr, flush=True)

    def read(self, path, label):
        if not path:
            return {}
        try:
            data = json.loads(Path(path).read_text(encoding="utf-8"))
        except FileNotFoundError:
            return {}
        except (OSError, ValueError) as e:
            self.note(f"{label} file {path} ignored: {e}")
            return {}
        if not isinstance(data, dict):
            self.note(f"{label} file {path} ignored: not a JSON object")
            return {}
        return data

    def resolve(self, data_dir, user_file=None):
        """({key: {value, layer}}, theme token map: theme.json over user over repo tokens)."""
        out = {k: {"value": v, "layer": "default"} for k, v in DEFAULT_SETTINGS.items()}
        repo = self.read(self.repo_file, "repo settings")
        user = self.read(user_file, "user settings")
        layers = (
            ("repo", repo, REPO_KEYS | {"themeTokens"}),
            ("user", user, set(DEFAULT_SETTINGS) | USER_ONLY | {"themeTokens"}),
            (
                "session",
                self.read(Path(data_dir) / "settings.json", "session settings"),
                None,
            ),
        )
        for layer, data, allowed in layers:
            for k, v in data.items():
                if allowed is not None and k not in allowed:
                    why = (
                        "not allowed in this layer"
                        if k in DEFAULT_SETTINGS
                        else "unknown key"
                    )
                    self.note(f"{layer} layer: {k} ignored ({why})")
                    continue
                if k not in DEFAULT_SETTINGS:
                    continue
                err = setting_error(k, v)
                if err:
                    self.note(f"{layer} layer: {err}; the layer below applies")
                    continue
                out[k] = {"value": v, "layer": layer}
        tokens = []
        for layer, data in (("repo", repo), ("user", user)):
            if "themeTokens" not in data:
                continue
            got = token_map(data["themeTokens"])
            if got is None:
                self.note(
                    f"{layer} layer: themeTokens must be {{light: {{...}}, dark: {{...}}}} of strings"
                )
            else:
                tokens.append(got)
        theme = self.read(Path(data_dir) / "theme.json", "theme")
        for mode in ("light", "dark"):
            own = theme.get(mode)
            if own is not None and not isinstance(own, dict):
                self.note(f"theme file: {mode} ignored (not a JSON object)")
                theme = {k: v for k, v in theme.items() if k != mode}
                own = None
            merged = {k: v for t in tokens for k, v in t.get(mode, {}).items()}
            merged.update(own or {})
            if merged:
                theme = {**theme, mode: merged}
        return out, theme


def question_states(doc, r):
    """Per question id: (state, revising); see derive_states."""
    return derive_states(doc, r)[0]


def derive_states(doc, r):
    """(states, upstream_changed). states maps each question id to (state, revising); neither is
    written to questions.json.

    Live decision events replay in seq order, with each question's terminal decision placed by its
    updatedAt against the events' `at` (before a same-second event, as the page decision wins that
    tie in round.py's effective(); a terminal decision and a recommendation change in the same
    second fall in `rev` order). A decision on a question that is not stale marks
    its direct dependents that hold a live decision stale; a decision on a stale question clears
    it without re-staling its own dependents (that cascade is deferred). A recommendation change
    (a history line with `pageSeq`, placed after the events up to that seq) marks stale each
    question named in its `affects` and each direct dependent of the revised question that holds a
    live decision, and upstream_changed maps each such question to the revised ids that did it; a
    new decision on the question clears both. A withdrawn event never
    happened, so an undo clears what it caused. A question with a stale ancestor further up is
    upstream-pending; `archived` wins over both. `revising` marks a question with its own
    delivered, unhandled decision event; upstream effects stay in stale and upstream-pending.
    """
    qs = [q for q in doc.get("questions") or [] if isinstance(q, dict) and q.get("id")]
    deps = {q["id"]: list(q.get("dependsOn") or []) for q in qs}
    children = {}
    for qid, parents in deps.items():
        for p in parents:
            children.setdefault(p, []).append(qid)
    events = sorted(
        (
            e
            for e in r.get("events") or []
            if e.get("kind") in DECISIONS
            and e.get("id") in deps
            and not e.get("withdrawn")
        ),
        key=lambda e: e.get("seq", 0),
    )
    terminal = [
        {
            "id": q["id"],
            "kind": t["decision"],
            "at": t["updatedAt"],
            "rev": t.get("rev") or 0,
        }
        for q in qs
        if isinstance(t := q.get("terminal"), dict)
        and t.get("decision")
        and isinstance(t.get("updatedAt"), str)
    ]

    def slot(at):  # the first event at or after `at`
        return next(
            (i for i, e in enumerate(events) if (e.get("at") or "") >= at),
            len(events),
        )

    changes = [
        {
            "id": q["id"],
            "kind": "rec",
            "at": h.get("at") or "",
            "seq": h["pageSeq"],
            "rev": h.get("rev") or 0,
            "hit": [*(h.get("affects") or []), *children.get(q["id"], [])],
        }
        for q in qs
        for h in q.get("history") or []
        if isinstance(h, dict) and isinstance(h.get("pageSeq"), int)
    ]

    def after(seq):  # the first event past `seq`
        return next(
            (i for i, e in enumerate(events) if e.get("seq", 0) > seq), len(events)
        )

    replay = [(i, 1, "", 0, e) for i, e in enumerate(events)]
    replay += [(slot(t["at"]), 0, t["at"], t["rev"], t) for t in terminal]
    replay += [(after(c["seq"]), 0, c["at"], c["rev"], c) for c in changes]
    live, stale, changed = {}, set(), {}
    for *_, e in sorted(replay, key=lambda x: x[:4]):
        qid = e["id"]
        if e["kind"] == "rec":
            hit = {c for c in e["hit"] if c != qid and live.get(c)}
            stale.update(hit)
            for c in hit:
                changed.setdefault(c, [])
                if qid not in changed[c]:
                    changed[c].append(qid)
            continue
        was_stale = qid in stale
        stale.discard(qid)
        changed.pop(qid, None)
        live[qid] = e["kind"] != "reopen"
        if live[qid] and not was_stale:
            stale.update(c for c in children.get(qid, []) if live.get(c))
    archived = {q["id"] for q in qs if q.get("archived")}
    stale -= archived

    def upstream(qid):
        seen, todo = set(), list(deps.get(qid, []))
        while todo:
            p = todo.pop()
            if p in seen:
                continue
            seen.add(p)
            if p in stale:
                return True
            todo += deps.get(p, [])
        return False

    revising = {
        e["id"]
        for e in events
        if e.get("deliveredAt") and not is_handled(doc, e.get("seq", 0))
    }
    out = {}
    for qid in deps:
        if qid in archived:
            state = "archived"
        elif qid in stale:
            state = "stale"
        elif upstream(qid):
            state = "upstream-pending"
        else:
            state = "open"
        out[qid] = (state, qid in revising)
    return out, {c: ids for c, ids in changed.items() if c in stale}


def load_json(path, default):
    """Read a JSON file; retry briefly when a writer is mid-replace. Missing file gives default."""
    for _ in range(10):
        try:
            with open(path, "r", encoding="utf-8") as f:
                return json.loads(f.read())
        except FileNotFoundError:
            return json.loads(json.dumps(default))
        except (json.JSONDecodeError, PermissionError):
            time.sleep(0.05)
    raise RuntimeError(f"could not read {path}")


def find_visual(doc, vid):
    """The visual with id vid: top-level visuals first, then inline visuals inside questions."""
    inline = [
        v
        for q in doc.get("questions") or []
        if isinstance(q, dict)
        for v in q.get("visuals") or []
    ]
    for v in (doc.get("visuals") or []) + inline:
        if isinstance(v, dict) and v.get("id") == vid:
            return v
    return None


def visual_format(v):
    """The visual's format, with `kind` as its alias; the page reads a missing one as html."""
    return v.get("format") or v.get("kind") or "html"


def open_body(data_dir, v):
    """(status, body, content type) for visual v opened in a tab of its own.

    Content comes inline or through read_visual_file, under its rules. The type follows the
    format, never the file name: html is text/html, svg is image/svg+xml, and markdown, mermaid
    and chart are text/plain. An image file needs an image extension (415 otherwise); inline
    image content that is a data:image/ or http(s) URL is wrapped in an <img> page, as the panel
    shows it, and anything else is text.
    """
    f, c = visual_format(v), v.get("content")
    if c is None:
        c = read_visual_file(data_dir, v.get("file"))
        if c is None:
            return 404, {"error": "not found"}, None
        if len(c) > MAX_VISUAL_FILE:
            limit = f"file is over the {MAX_VISUAL_FILE // 2**20} MB limit"
            return 413, {"error": limit}, None
        if f == "image":
            t = IMAGE_TYPES.get(Path(v["file"]).suffix.lower())
            if not t:
                return (
                    415,
                    {"error": "not an image type (png, jpg, gif, webp or svg)"},
                    None,
                )
            return 200, c, "image/" + t
    elif f == "image" and str(c).lower().startswith(
        ("data:image/", "http://", "https://")
    ):
        return 200, f'<img alt="" src="{html.escape(c)}">'.encode("utf-8"), "text/html"
    if not isinstance(c, bytes):
        c = c if isinstance(c, str) else json.dumps(c, ensure_ascii=False)
        c = c.encode("utf-8")
    return 200, c, {"html": "text/html", "svg": "image/svg+xml"}.get(f, "text/plain")


def read_visual_file(data_dir, file):
    """Bytes of the regular file `file` names inside data_dir (at most MAX_VISUAL_FILE + 1 of them).

    None when file is not a string, or resolves outside data_dir (absolute, `..`, a symlink out),
    or is missing, not a regular file, a runtime path (see runtime_path), or has more than one
    hard link: a link's name says nothing about the file it shares, which can be a session file.
    A drive, anchor, UNC prefix, colon (an NTFS stream) or `..` part is refused before any
    filesystem call.
    """
    if (
        not isinstance(file, str)
        or not file
        or ":" in file
        # A Windows anchor covers a root on either separator and a UNC share.
        or PureWindowsPath(file).anchor
        or ".." in file.replace("\\", "/").split("/")
    ):
        return None
    root = Path(data_dir).resolve()
    try:
        path = (root / file).resolve()
        if not path.is_file() or runtime_path(path.relative_to(root)):
            return None
        with open(path, "rb") as f:
            if os.fstat(f.fileno()).st_nlink > 1:
                return None
            return f.read(MAX_VISUAL_FILE + 1)
    except (OSError, ValueError, RuntimeError):
        return None


def save_json(path, data):
    """Atomic write: unique temp file in the same folder, then os.replace with retry (Windows locks)."""
    path = Path(path)
    fd, tmp = tempfile.mkstemp(prefix=path.name + ".", suffix=".tmp", dir=path.parent)
    with os.fdopen(fd, "w", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, indent=2, ensure_ascii=False) + "\n")
    replace_into(tmp, path)


def mtime(path):
    """A change stamp for path, 0 when missing. Size and inode ride with the mtime: a coarse file
    clock gives two writes the same time, and each atomic replace is a new inode."""
    try:
        st = path.stat()
    except FileNotFoundError:
        return 0
    return (st.st_mtime_ns, st.st_size, st.st_ino)


def is_handled(doc, seq):
    """Legacy handledSeq covers every seq up to it; `handled` lists single seqs."""
    return seq <= (doc.get("handledSeq") or 0) or seq in set(doc.get("handled") or [])


def release_user_holds(doc, r):
    """Drop, in this loaded copy only, each `by: user` hold that the user has since answered: a
    live accept, alt or own on the question with a seq above the hold's setAsideSeq, or, on a hold
    with none (an imported one), an event stamped after its waitingSince. Claude's
    `wait --clear` stays valid, and an undo of that answer brings the hold back."""
    for q in doc.get("questions") or []:
        if (
            isinstance(q, dict)
            and q.get("waiting")
            and q.get("waitingBy") == "user"
            and any(
                e.get("id") == q.get("id")
                and e.get("kind") in ("accept", "alt", "own")
                and not e.get("withdrawn")
                and (
                    e.get("seq", 0) > q["setAsideSeq"]
                    if q.get("setAsideSeq") is not None
                    else (e.get("at") or "") > (q.get("waitingSince") or "9")
                )
                for e in r.get("events") or []
            )
        ):
            for key in ("waiting", "waitsOn", "waitingBy", "waitingSince"):
                q.pop(key, None)


def content_rev(q, events):
    """Bumped by round.py on wording or recommendation changes, plus one per decision or undo. Replies never bump it."""
    qid = q.get("id")
    return (q.get("contentRev") or 0) + sum(
        1
        for e in events
        if e.get("id") == qid and e.get("kind") in DECISIONS | {"undo"}
    )


def decision_view(event, prev_text=""):
    """The responses[id] entry one decision event produces; a reopen without text keeps the note."""
    kind, text = event["kind"], event.get("text") or ""
    return {
        "decision": None if kind == "reopen" else kind,
        "alt": event.get("alt") if kind == "alt" else None,
        "text": text if text.strip() or kind != "reopen" else prev_text,
        "updatedAt": event["at"],
        "seq": event["seq"],
    }


def fold_decisions(events):
    """The responses[id] entry after a run of live decision events in seq order (a reopen keeps the note)."""
    view = None
    for e in events:
        view = decision_view(e, view["text"] if view else "")
    return view


def rebuild_responses(events):
    """Derive (responses, history) from the event log alone, replaying it in seq order.

    Mirrors Hub.record and Hub._undo: an undo withdraws its target and restores the decision
    before it from that event's own text. An event flagged withdrawn with no undo naming it
    is skipped as a decision.
    """
    responses, history = {}, {}
    undone = {e.get("undoSeq") for e in events if e.get("kind") == "undo"}
    withdrawn = set()
    ordered = sorted(events, key=lambda e: e["seq"])
    for e in ordered:
        kind, qid = e.get("kind"), e.get("id")
        if kind == "undo":
            target = e.get("undoSeq")
            withdrawn.add(target)
            live = [
                x
                for x in ordered
                if x["seq"] < e["seq"]
                and x.get("id") == qid
                and x.get("kind") in DECISIONS
                and x["seq"] not in withdrawn
            ]
            if live:
                responses[qid] = fold_decisions(live)
            else:
                responses.pop(qid, None)
        elif kind in DECISIONS and qid:
            if e.get("withdrawn") and e["seq"] not in undone:
                withdrawn.add(e["seq"])
            else:
                prev = responses.get(qid, {}).get("text", "")
                responses[qid] = decision_view(e, prev)
        if qid:
            line = {
                "at": e["at"],
                "by": "user",
                "kind": kind,
                "alt": e.get("alt"),
                "text": e.get("text") or "",
                "seq": e["seq"],
            }
            if kind == "undo":
                line["undoSeq"] = e.get("undoSeq")
            history.setdefault(qid, []).append(line)
    for lines in history.values():
        for line in lines:
            if line["seq"] in withdrawn:
                line["withdrawn"] = True
    return responses, history


def check_accept_audit(msg):
    """ValueError (400) unless msg is a well-formed accept-audit: a round id in `alt` and a
    non-empty `items` list of {id, contentRev} pairs with no repeated id. Returns the items."""
    if not (isinstance(msg.get("alt"), str) and msg["alt"].strip()):
        raise ValueError("accept-audit needs alt: the round id")
    items = msg.get("items")
    if not isinstance(items, list) or not items:
        raise ValueError(
            "accept-audit needs items: a non-empty list of {id, contentRev}"
        )
    seen = set()
    for it in items:
        if not (
            isinstance(it, dict)
            and set(it) == {"id", "contentRev"}
            and isinstance(it["id"], str)
            and isinstance(it["contentRev"], int)
            and not isinstance(it["contentRev"], bool)
        ):
            raise ValueError("each item must be {id: string, contentRev: integer}")
        if it["id"] in seen:
            raise ValueError(f"items repeats {it['id']}")
        seen.add(it["id"])
    return items


def split_accept_audit(doc, r, items):
    """(accepted, skipped) of an accept-audit: the items the server accepts now, and an
    {id, reason} for each it refuses. `changed` is a contentRev that no longer matches;
    `ineligible` is an unknown, closed, held or recommendation-less question, or one whose
    prerequisite has no decision and is still on the path (an archived or superseded
    prerequisite is met)."""
    release_user_holds(doc, r)
    qs = {q.get("id"): q for q in doc.get("questions") or []}
    states = question_states(doc, r)
    seeded = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}

    def decided(qid):
        """A prerequisite that is decided, or has left the path (archived or superseded)."""
        p = qs.get(qid) or {}
        return (
            (r["responses"].get(qid) or {}).get("decision")
            or (p.get("terminal") or {}).get("decision")
            or p.get("archived")
            or p.get("supersededBy")
        )

    accepted, skipped = [], []
    for it in items:
        q = qs.get(it["id"])
        if q and it["contentRev"] != content_rev(q, r["events"]):
            reason = "changed"
        elif (
            not q
            or states.get(it["id"], ("",))[0] != "open"
            or not q.get("recommendation")
            or q.get("waiting")
            or (seeded.get(it["id"]) or {}).get("status") == "superseded-by-plan"
            or not all(decided(p) for p in q.get("dependsOn") or [])
        ):
            reason = "ineligible"
        else:
            accepted.append(it)
            continue
        skipped.append({"id": it["id"], "reason": reason})
    return accepted, skipped


def check_alt(q, kind, alt):
    """ValueError (400) unless `alt` names one of q's alternative keys (alt) or commitments (confirm)."""
    if kind == "alt":
        keys = {
            a.get("key") for a in q.get("alternatives") or [] if isinstance(a, dict)
        }
        if not (isinstance(alt, str) and alt in keys):
            raise ValueError("alt must be one of the question's alternatives[].key")
    else:
        n = len(q.get("commits") or [])
        if not (isinstance(alt, str) and alt.isdecimal() and int(alt) < n):
            raise ValueError(
                f"confirm needs alt: a commitment index, a decimal string below {n}"
            )


def check_understanding(doc, alt, text, rev):
    """ValueError (400) or Conflict (409 stale) for a confirm-understanding event."""
    if alt not in UNDERSTANDING:
        raise ValueError("confirm-understanding needs alt: confirm or off")
    if alt == "off" and not text.strip():
        raise ValueError("text required: say what is off")
    current = (doc.get("restatement") or {}).get("rev")
    if not isinstance(current, int):
        raise ValueError("there is no restatement to confirm")
    if rev is None:
        raise ValueError("confirm-understanding needs contentRev: the restatement rev")
    if rev != current:
        raise Conflict({"error": "stale", "contentRev": current})


def repeat_of(events, event, since_seq=None):
    """The event a repeated Confirm duplicates, or None; the server answers a repeat with that
    event's seq. A commitment's confirm repeats any live confirm of it after `since_seq` (the
    question's commitsSinceSeq: a commitments revise retires earlier confirms); an understanding
    Confirm repeats only when the newest answer to that restatement rev is a Confirm."""
    kind = event["kind"]
    if kind == "confirm":
        same = [
            e
            for e in events
            if not e.get("withdrawn")
            and (e.get("seq") or 0) > (since_seq or 0)
            and (e.get("kind"), e.get("id"), e.get("alt"))
            == (kind, event["id"], event["alt"])
        ]
    elif kind == "confirm-understanding" and event["alt"] == "confirm":
        same = [
            e
            for e in events
            if e.get("kind") == kind and e.get("contentRev") == event["contentRev"]
        ][-1:]
        same = [e for e in same if e.get("alt") == "confirm"]
    else:
        return None
    return same[0] if same else None


class Hub(LoopbackWatcher):
    """The interview's state on the session-bridge loopback adapter: data paths, answer
    sequencing, page state. responses.json is the event log the bridge delivers."""

    name = NAME

    def __init__(self, port, data_dir):
        super().__init__(port, data_dir)
        self.questions = self.dir / "questions.json"
        self.responses = self.dir / "responses.json"
        self.theme = self.dir / "theme.json"
        self.settings = self.dir / "settings.json"
        self.watch_seq = self.dir / ".watch-seq"
        self.session = hashlib.sha256(str(self.dir).lower().encode()).hexdigest()[:12]
        self.layers = Settings(repo_root(self.dir))
        self._last_state = None
        self.opens = {}  # new-tab nonce: (visual id, monotonic expiry)

    def read_log(self):
        return load_json(self.responses, EMPTY_RESPONSES)

    def write_log(self, log):
        log.setdefault("schemaVersion", SCHEMA_VERSION)
        save_json(self.responses, log)

    def settle_window(self):
        return QUIET_SECONDS, BURST_SECONDS

    def identity(self):
        return {"session": self.session, "api": API}

    def mint_open(self, vid):
        """A one-time nonce that opens visual vid for OPEN_SECONDS; expired ones are dropped."""
        now, nonce = time.monotonic(), secrets.token_urlsafe(16)
        with self.cond:
            self.opens = {k: o for k, o in self.opens.items() if o[1] > now}
            self.opens[nonce] = (vid, now + OPEN_SECONDS)
        return nonce

    def take_open(self, nonce, vid):
        """True when nonce was minted for vid and is still live; any use spends it."""
        with self.cond:
            got = self.opens.pop(nonce, None)
        return got is not None and got[0] == vid and time.monotonic() < got[1]

    def lease_timeout(self):
        return self.layers.resolve(self.dir, self.user_settings())[0]["leaseTimeout"][
            "value"
        ]

    def user_settings(self):
        """The user settings file `round.py ensure-running --user-settings` recorded, if any."""
        try:
            s = json.loads((self.dir / SESSION_JSON).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return s.get("userSettings") if isinstance(s, dict) else None

    def signature(self):
        user = self.user_settings()
        return (
            mtime(self.questions),
            mtime(self.responses),
            mtime(self.theme),
            mtime(self.settings),
            mtime(self.watch_seq),
            mtime(self.dir / SESSION_JSON),
            mtime(self.layers.repo_file) if self.layers.repo_file else 0,
            mtime(Path(user)) if user else 0,
            self.listener()["state"],
            self.lease_view() is not None,
        )

    def watched(self):
        """The watcher's cursor: every seq up to it was delivered (covers events from before deliveredAt)."""
        try:
            return int(
                "".join(
                    c for c in self.watch_seq.read_text(encoding="utf-8") if c.isdigit()
                )
                or 0
            )
        except OSError:
            return 0

    def state(self):
        return self.read_state()[0]

    def read_state(self):
        """(state, stale); stale means the read failed and the last good state was reused."""
        stale = False
        try:
            q = load_json(self.questions, {"questions": []})
            r = load_json(self.responses, EMPTY_RESPONSES)
            settings, theme = self.layers.resolve(self.dir, self.user_settings())
            release_user_holds(q, r)
            derived, changed = derive_states(q, r)
            # exporters imports server at module top
            from exporters import latest_decision

            for x in q.get("questions") or []:
                if isinstance(x, dict) and x.get("id") in derived:
                    x["state"], x["revising"] = derived[x["id"]]
                    if x["id"] in changed:
                        x["upstreamChanged"] = changed[x["id"]]
                    x["answered"] = bool(
                        (latest_decision(x, r.get("responses", {})) or {}).get(
                            "decision"
                        )
                    )
            self._last_state = {
                "questions": q,
                "responses": r,
                "theme": theme,
                "settings": settings,
                "watchSeq": self.watched(),
            }
        except RuntimeError:
            if self._last_state is None:
                raise
            stale = True
        return {
            **self._last_state,
            "listener": self.listener(),
            "session": self.session,
            "instance": self.instance,
            "api": API,
        }, stale

    def record(self, msg):
        """Append one page event. Returns (seq, contentRev or None, extra), where extra is the
        `accepted` and `skipped` an accept-audit adds to its response and {} for any other kind.
        Raises ValueError (400) or Conflict (409)."""
        qid, kind = msg.get("id"), msg.get("kind")
        if not isinstance(kind, str) or not isinstance(qid, (str, type(None))):
            raise ValueError("id and kind must be strings")
        if not isinstance(msg.get("text"), (str, type(None))):
            raise ValueError("text must be a string")
        for key in ("contentRev", "undoSeq"):
            v = msg.get(key)
            if v is not None and (not isinstance(v, int) or isinstance(v, bool)):
                raise ValueError(f"{key} must be an integer")
        text = msg.get("text") or ""
        alt = msg.get("alt")
        if kind not in DECISIONS | REQUESTS | FREE | WITH_ALT | {"undo"}:
            raise ValueError("unknown kind")
        doc = load_json(self.questions, {"questions": []})
        qs = {q.get("id"): q for q in doc.get("questions", [])}
        if kind in FREE:
            qid = None
        elif kind != "undo" and qid not in qs:
            raise ValueError("unknown question")
        if kind in ("own", "ask", "note", "hedged") and not text.strip():
            raise ValueError(
                "text required: say the condition"
                if kind == "hedged"
                else "text required"
            )
        if kind == "hedged" and len(text) > LINE_CAP:
            raise ValueError(f"text too long: at most {LINE_CAP} characters")
        items = check_accept_audit(msg) if kind == "accept-audit" else None
        now = now_iso()
        extra = {}
        with self.cond:
            if kind == "confirm-understanding":
                check_understanding(
                    load_json(self.questions, {}), alt, text, msg.get("contentRev")
                )
            r = load_json(self.responses, EMPTY_RESPONSES)
            for k, v in EMPTY_RESPONSES.items():
                r.setdefault(k, json.loads(json.dumps(v)))
            event = {
                "seq": r["seq"] + 1,
                "id": qid,
                "kind": kind,
                "alt": alt if kind in WITH_ALT else None,
                "text": text,
                "at": now,
            }
            if kind == "undo":
                self._undo(r, doc, msg, event)
                qid = event["id"]
            elif kind == "confirm-understanding":
                event["contentRev"] = msg["contentRev"]
            elif kind == "accept-audit":
                accepted, skipped = split_accept_audit(doc, r, items)
                if not accepted:
                    raise Conflict({"error": "nothing accepted", "skipped": skipped})
                event["items"] = accepted
                extra = {"accepted": [i["id"] for i in accepted], "skipped": skipped}
            elif (
                kind == "confirm"
                and qid in qs
                and msg.get("contentRev") is not None
                and msg["contentRev"] != (qs[qid].get("contentRev") or 0)
            ):
                # A tab holding an old commitments list would otherwise confirm the new one by index.
                raise Conflict(
                    {"error": "stale", "contentRev": qs[qid].get("contentRev") or 0}
                )
            elif kind in DECISIONS and msg.get("contentRev") is not None:
                current = content_rev(qs[qid], r["events"])
                event["contentRev"] = current
                if msg.get("contentRev") != current:
                    q = qs[qid]
                    raise Conflict(
                        {
                            "error": "changed",
                            "id": qid,
                            "contentRev": current,
                            "current": {
                                k: q.get(k)
                                for k in (
                                    "title",
                                    "short",
                                    "recommendation",
                                    "alternatives",
                                )
                            },
                            "decision": r["responses"].get(qid),
                        }
                    )
            # After the contentRev check, so a page holding old alternatives gets the 409 payload.
            if kind in WITH_ALT and qid:
                check_alt(qs[qid], kind, alt)
            dup = repeat_of(
                r["events"], event, (qs.get(qid) or {}).get("commitsSinceSeq")
            )
            if dup:
                return (
                    dup["seq"],
                    content_rev(qs[qid], r["events"]) if qid else None,
                    {},
                )
            r["seq"] = seq = event["seq"]
            prev = r["responses"].get(qid, {}) if qid else {}
            if kind in DECISIONS:
                r["responses"][qid] = {
                    "decision": None if kind == "reopen" else kind,
                    "alt": alt if kind == "alt" else None,
                    "text": text
                    if text.strip() or kind != "reopen"
                    else prev.get("text", ""),
                    "updatedAt": now,
                    "seq": seq,
                }
            r["events"].append(event)
            if qid:
                line = {
                    "at": now,
                    "by": "user",
                    "kind": kind,
                    "alt": event["alt"],
                    "text": text,
                    "seq": seq,
                }
                if kind == "undo":
                    line["undoSeq"] = event["undoSeq"]
                r["history"].setdefault(qid, []).append(line)
            for it in event["items"] if kind == "accept-audit" else []:
                r["seq"] += 1
                accept = {
                    "seq": r["seq"],
                    "id": it["id"],
                    "kind": "accept",
                    "alt": None,
                    "text": "",
                    "at": now,
                    "auditSeq": seq,
                    "contentRev": it["contentRev"],
                }
                r["events"].append(accept)
                r["responses"][it["id"]] = decision_view(accept)
                r["history"].setdefault(it["id"], []).append(
                    {
                        "at": now,
                        "by": "user",
                        "kind": "accept",
                        "alt": None,
                        "text": "",
                        "seq": accept["seq"],
                    }
                )
            save_json(self.responses, r)
            self.cond.notify_all()
            crev = content_rev(qs[qid], r["events"]) if qid in qs else None
        return seq, crev, extra

    def _undo(self, r, doc, msg, event):
        """Withdraw a decision Claude has not handled yet, restoring the decision before it."""
        try:
            target_seq = int(msg.get("undoSeq"))
        except (TypeError, ValueError):
            raise ValueError("undo needs undoSeq")
        target = next((e for e in r["events"] if e.get("seq") == target_seq), None)
        if not target or target.get("kind") not in DECISIONS:
            raise ValueError("undoSeq is not a decision")
        if target.get("withdrawn"):
            raise Conflict({"error": "already undone"})
        if is_handled(doc, target_seq):
            raise Conflict({"error": "Claude already handled it"})
        qid = target["id"]
        live = [
            e
            for e in r["events"]
            if e.get("id") == qid
            and e.get("kind") in DECISIONS
            and not e.get("withdrawn")
        ]
        if live[-1] is not target:
            raise Conflict({"error": "a newer decision exists"})
        target["withdrawn"] = True
        for h in r["history"].get(qid, []):
            if h.get("seq") == target_seq:
                h["withdrawn"] = True
        if len(live) > 1:
            r["responses"][qid] = fold_decisions(live[:-1])
        else:
            r["responses"].pop(qid, None)
        event.update(id=qid, undoSeq=target_seq)

    def unhandled(self, r):
        doc = load_json(self.questions, {})
        return [
            e
            for e in r.get("events", [])
            if not e.get("withdrawn") and not is_handled(doc, e.get("seq", 0))
        ]


class Handler(LoopbackHandler):
    """The page and its answers; session_bridge serves /events, /api/wait, /api/lease, /api/ping."""

    hub: "Hub"
    max_body = MAX_BODY
    page_csp = PAGE_CSP

    def route_get(self, url, query):
        hub = self.hub
        if url.path in ("/", "/index.html"):
            html = (
                (HERE / "index.html")
                .read_text(encoding="utf-8")
                .replace("%%TOKEN%%", hub.token)
            )
            return self.send(200, html.encode("utf-8"), "text/html")
        if url.path == "/api/state":
            return self.send(200, hub.state())
        if url.path == "/api/visual-file":
            if not self.token_ok():
                return self.send(403, {"error": "token required"})
            v = find_visual(load_json(hub.questions, {}), (query.get("id") or [""])[0])
            raw = read_visual_file(hub.dir, v.get("file")) if v else None
            if raw is None:
                return self.send(404, {"error": "not found"})
            if len(raw) > MAX_VISUAL_FILE:
                return self.send(
                    413,
                    {"error": f"file is over the {MAX_VISUAL_FILE // 2**20} MB limit"},
                )
            return self.send(200, raw, OCTET)
        if url.path == "/api/visual-open":
            # A tab navigation cannot send the token header, so a one-time nonce stands in; the
            # sandbox CSP makes the document an opaque origin that cannot reach the page's token.
            vid = (query.get("id") or [""])[0]
            if not hub.take_open((query.get("t") or [""])[0], vid):
                return self.send(403, {"error": "open link expired or already used"})
            v = find_visual(load_json(hub.questions, {}), vid)
            if not v or v.get("archived"):
                return self.send(404, {"error": "not found"})
            code, body, ctype = open_body(hub.dir, v)
            if code != 200:
                return self.send(code, body)
            flags = " allow-scripts" if visual_format(v) == "html" else ""
            return self.send(200, body, ctype, f"sandbox{flags}; {PAGE_CSP}")
        return self.send(404, {"error": "not found"})

    def route_post(self, path, msg):
        if path == "/api/answer":
            try:
                seq, crev, extra = self.hub.record(msg)
            except (ValueError, TypeError) as e:
                return self.send(400, {"error": str(e)})
            except Conflict as e:
                return self.send(409, e.payload)
            return self.send(
                200,
                {
                    "ok": True,
                    "seq": seq,
                    "contentRev": crev,
                    "listener": self.hub.listener(),
                    **extra,
                },
            )
        if path == "/api/visual-open":
            vid = msg.get("id")
            v = find_visual(load_json(self.hub.questions, {}), vid)
            if not isinstance(vid, str) or not v or v.get("archived"):
                return self.send(404, {"error": "not found"})
            t = self.hub.mint_open(vid)
            return self.send(
                200, {"url": f"/api/visual-open?id={quote(vid, safe='')}&t={t}"}
            )
        return self.send(404, {"error": "not found"})


def main(argv=None):
    p = argparse.ArgumentParser(
        description="Local interview surface server (127.0.0.1 only)."
    )
    p.add_argument(
        "--port",
        type=int,
        default=0,
        help="port to bind; 0 picks a free one (default 0)",
    )
    p.add_argument(
        "--dir",
        required=True,
        help="data dir holding questions.json and responses.json",
    )
    p.add_argument("--nonce", default="", help="written into the session files")
    a = p.parse_args(argv)
    data_dir = Path(a.dir)
    data_dir.mkdir(parents=True, exist_ok=True)

    def make_hub(port):
        hub = Hub(port, data_dir)
        if not hub.responses.exists():
            save_json(hub.responses, EMPTY_RESPONSES)
        return hub

    serve(Handler, make_hub, a.port, a.nonce, {"data": data_dir.resolve()})


if __name__ == "__main__":
    main()

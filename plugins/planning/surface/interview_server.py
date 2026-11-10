"""Local interview surface. 127.0.0.1 only, Python 3 stdlib.

Usage: python interview_server.py --dir DATA_DIR [--port PORT] [--nonce NONCE]
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
import heapq
import html
import json
import os
import re
import secrets
import subprocess
import sys
import tempfile
import time
from pathlib import Path, PureWindowsPath
from urllib.parse import quote

from question_shape import restates, withheld
from yaml_subset import parse as parse_yaml
from session_bridge import (
    MAX_STREAMS,  # noqa: F401  # the stream limits, read through this module by its tests
    NO_WINDOW,
    PING_SECONDS,  # noqa: F401
    READING_WINDOW,
    Conflict,
    LoopbackHandler,
    LoopbackWatcher,
    now_iso,
    plugin_build,
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
# Requests to Claude that record no decision. `research` and `cancel-research` name no skill or plugin;
# `confirm-reading` confirms Claude's read-back of the user's answer.
REQUESTS = {"ask", "rephrase", "research", "cancel-research", "confirm-reading"}
# Events not tied to a question; `confirm-understanding` answers the restatement, and
# `accept-audit` lists the questions one click accepted (each also gets its own `accept`).
FREE = {"note", "wrapup", "confirm-understanding", "accept-audit"}
# Kinds that carry `alt`; `confirm` carries a commitment index and records no decision,
# `confirm-understanding` carries `confirm` or `off`, `accept-audit` the round id, and
# `proposal` the user's answer to a proposed question (PROPOSAL), recording no decision.
WITH_ALT = {"alt", "confirm", "confirm-understanding", "accept-audit", "proposal"}
UNDERSTANDING = ("confirm", "off")
PROPOSAL = ("accept", "edit", "decline")
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
# The question-shape files both interview pages load (composer, viewport fit), from the shared page's web folder.
SHARED_WEB = HERE.parent / "shared" / "web"
QUESTION_SHAPE = {
    "/question-shape.js": ("question-shape.js", "text/javascript"),
    "/question-shape.css": ("question-shape.css", "text/css"),
}
# A visual may never name a runtime file: the session files and their transient temp copies
# hold the token, so every dotfile path component, lock and temp file is refused.
RUNTIME_SUFFIXES = (".lock", ".tmp")


def page_build():
    """plugin_build() of the files on disk, as attribute-safe text ("" for an unreadable part)."""
    return {k: html.escape(v or "") for k, v in plugin_build(HERE).items()}


def runtime_path(rel):
    """True when any part of the data-dir-relative path is a dotfile, a lock or a temp file."""
    return any(
        p.startswith(".") or p.lower().endswith(RUNTIME_SUFFIXES) for p in rel.parts
    )


QUIET_SECONDS = 10.0  # default settleQuiet: a found event waits this long for more before the watcher wakes
BURST_SECONDS = 30.0  # default settleBurst: never holding it longer than this in all
NAME = "interview"  # names the session files and the token header (session_bridge)
SESSION_JSON = session_files(NAME)[0]
# The ADR 0075 file layers: the interview_page mapping of planning's team and personal files in
# the convention home, which the planning copy of resolve-convention-home.sh binds.
SECTION = "interview_page"
TEAM_FILE, PERSONAL_FILE = "planning.yaml", "planning.local.yaml"
DEFAULT_HOME = "docs/conventions"
HOME_SCRIPT = HERE.parent / "lib" / "resolve-convention-home.sh"
# Retired: never read for values, only named in a one-time notice (Settings.retired_notices).
RETIRED_FILE = Path(".claude") / "interview-surface.json"
RETIRED_SEEN = ".retired-notices.json"

# Settings, lowest layer first: plugin default, team file, personal file, user file, the data
# dir's settings.json. No userConfig option carries these keys, so that layer is empty.
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
    "settleQuiet": QUIET_SECONDS,
    "settleBurst": BURST_SECONDS,
    "readingWindow": READING_WINDOW,
    "frontierLock": "confirm",
    "requireDepends": False,
    "orderThreshold": 25,
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
    "settleQuiet": ("num", 0.5, 60),
    "settleBurst": ("num", 1, 120),
    "readingWindow": ("int", 5, 600),
    "frontierLock": ("enum", ("confirm", "hard", "off")),
    "requireDepends": ("bool",),
    "orderThreshold": ("int", 0, 1000),
}
TEAM_KEYS = set(DEFAULT_SETTINGS) - {"displayName"}  # a name is one person's, never the team's
USER_ONLY = {"browserCommand"}  # read by ensure-running, never sent to the page


def setting_error(key, value):
    """None when value is valid for key, else the reason."""
    kind, *rule = SETTING_RULES[key]
    if kind == "bool":
        ok = isinstance(value, bool)
    elif kind in ("int", "num"):
        ok = (
            isinstance(value, int if kind == "int" else (int, float))
            and not isinstance(value, bool)
            and rule[0] <= value <= rule[1]
        )
    elif kind == "enum":
        ok = value in rule[0]
    else:
        ok = isinstance(value, str) and bool(value.strip())
    if ok:
        return None
    if kind in ("int", "num"):
        noun = "an integer" if kind == "int" else "a number"
        want = f"{noun} from {rule[0]} to {rule[1]}"
    elif kind == "enum":
        want = " or ".join(rule[0])
    else:
        want = {"bool": "true or false", "str": "a non-empty string"}[kind]
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


def run_quiet(cmd):
    """(exit code, stdout, stderr) of a short command with no window; None when it cannot run."""
    try:
        p = subprocess.run(
            cmd,
            capture_output=True,
            text=True,
            timeout=10,
            stdin=subprocess.DEVNULL,
            creationflags=NO_WINDOW,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    return p.returncode, p.stdout.strip(), p.stderr.strip()


def convention_home(repo):
    """(root, home, why): the git toplevel of repo and the convention home there, per ADR 0075.

    The home is what resolve-convention-home.sh prints; with no pointer bound, or a declined one,
    the default docs/conventions. home is None, so no file layer applies, outside a git work tree,
    at a root that is $HOME or above it, or when the pointer FAILs (why then names the cause).
    """
    top = run_quiet(["git", "-C", str(repo), "rev-parse", "--show-toplevel"]) if repo else None
    if not top or top[0] != 0 or not top[1]:
        return None, None, None
    root = Path(top[1])
    got = run_quiet(["bash", str(HOME_SCRIPT), "--root", str(root)])
    if got is None:
        return root, None, f"team and personal files skipped: {HOME_SCRIPT.name} did not run"
    code, out, err = got
    if code == 0 and out:
        return root, root / out, None
    if code in (1, 4):
        home = root / DEFAULT_HOME
        if home.resolve() != root.resolve() / DEFAULT_HOME:
            return root, None, f"team and personal files skipped: {DEFAULT_HOME} is reached through a symlink"
        return root, home, None
    if code == 5:
        return root, None, None
    why = err.splitlines()[-1] if err else f"exit {code}"
    return root, None, f"team and personal files skipped: {why}"


def yaml_section(path, label, note):
    """The interview_page mapping of a planning YAML file; {} when absent, noted when unusable."""
    if path is None:
        return {}
    shown = f"{label} file {path}"
    try:
        if path.is_symlink():
            note(f"{shown} ignored: a symlink; a repository layer reads only regular files")
            return {}
        doc = parse_yaml(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return {}
    except (OSError, ValueError, RecursionError) as e:
        note(f"{shown} ignored: {e}")
        return {}
    if doc is None:
        return {}
    if not isinstance(doc, dict):
        note(f"{shown} ignored: the top level must be a mapping")
        return {}
    section = doc.get(SECTION)
    if section is None:
        return {}
    if not isinstance(section, dict):
        note(f"{shown}: {SECTION} ignored (not a mapping)")
        return {}
    return section


class Settings:
    """Resolves each key through the layers and names the layer its value came from.

    Problems (an unreadable file, an unknown or restricted key, an invalid value) are noted on
    stderr once each. An invalid team or personal value drops that layer and the key resolves its
    default, never the team value (ADR 0075's invalid-value rule); an invalid user or session
    value leaves the layer below in place.
    """

    def __init__(self, repo):
        self._noted = set()
        self.retired_file = Path(repo) / RETIRED_FILE if repo else None
        root, home, why = convention_home(repo)
        if why:
            self.note(why)
        self.home_shown = home.relative_to(root).as_posix() if home else DEFAULT_HOME
        self.team_file = home / TEAM_FILE if home else None
        self.personal_file = home / PERSONAL_FILE if home else None

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
        """({key: {value, layer}}, theme token map: theme.json over user, personal, team tokens)."""
        out = {k: {"value": v, "layer": "default"} for k, v in DEFAULT_SETTINGS.items()}
        team = yaml_section(self.team_file, "team", self.note)
        personal = yaml_section(self.personal_file, "personal", self.note)
        user = self.read(user_file, "user settings")
        layers = (
            ("team", team, TEAM_KEYS | {"themeTokens"}),
            ("personal", personal, set(DEFAULT_SETTINGS) | {"themeTokens"}),
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
                    if layer in ("team", "personal"):
                        self.note(f"{layer} layer: {err}; the default applies")
                        out[k] = {"value": DEFAULT_SETTINGS[k], "layer": "default"}
                    else:
                        self.note(f"{layer} layer: {err}; the layer below applies")
                    continue
                out[k] = {"value": v, "layer": layer}
        if out["settleQuiet"]["value"] > out["settleBurst"]["value"]:
            self.note(
                "settleQuiet is greater than settleBurst; the defaults apply to both"
            )
            for k in ("settleQuiet", "settleBurst"):
                out[k] = {"value": DEFAULT_SETTINGS[k], "layer": "default"}
        tokens = []
        for layer, data in (("team", team), ("personal", personal), ("user", user)):
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

    def retired_destination(self, key):
        team = f"{self.home_shown}/{TEAM_FILE}"
        if key in TEAM_KEYS or key == "themeTokens":
            return f"{SECTION}.{key} in {team}"
        if key == "displayName":
            return f"{SECTION}.{key} in {self.home_shown}/{PERSONAL_FILE}"
        if key in USER_ONLY:
            return "a --user-settings file"
        if key == "surface":
            return "the planning plugin's surface option"
        return "nowhere: not a setting"

    def retired_notices(self, data_dir):
        """Notes that the retired repo file is not read and where each of its keys goes now; once
        per data dir while the file's bytes are unchanged. Its values never apply."""
        path = self.retired_file
        try:
            # Only a regular file: a symlink could point the notice at any file the user can read.
            regular = path is not None and not path.is_symlink() and path.is_file()
            raw = path.read_bytes() if regular else None
        except OSError:
            raw = None
        if raw is None:
            return
        shown = RETIRED_FILE.as_posix()
        record = Path(data_dir) / RETIRED_SEEN
        digest = hashlib.sha256(raw).hexdigest()
        try:
            seen = json.loads(record.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            seen = {}
        seen = seen if isinstance(seen, dict) else {}
        if seen.get(shown) == digest:
            return
        try:
            data = json.loads(raw.decode("utf-8"))
        except ValueError:
            data = None
        self.note(f"{shown} is no longer read, and none of its values apply; move each one:")
        if not isinstance(data, dict):
            self.note(f"  it is not a JSON object; its keys go to {SECTION} in {self.home_shown}/{TEAM_FILE}")
            data = {}
        for k in data:
            self.note(f"  {k} goes to {self.retired_destination(k)}")
        try:
            record.write_text(json.dumps({**seen, shown: digest}) + "\n", encoding="utf-8")
        except OSError:
            pass  # an unwritable record shows the notice again next time, the safe direction


def question_states(doc, r):
    """Per question id: (state, revising); see derive_states."""
    return derive_states(doc, r)[0]


def supersede_chains(doc):
    """Per question id that supersedes another: every earlier question of its supersede chain as
    {id, round, stage}, the chain's first question first (G6: a question re-issued twice keeps
    its history). A cycle or an unknown id ends the walk. Never written to questions.json."""
    by_id = {
        q["id"]: q
        for q in doc.get("questions") or []
        if isinstance(q, dict) and isinstance(q.get("id"), str)
    }
    out = {}
    for qid, q in by_id.items():
        chain, seen, prev = [], {qid}, q.get("supersedes")
        while isinstance(prev, str) and prev in by_id and prev not in seen:
            seen.add(prev)
            p = by_id[prev]
            link = {"id": prev, "round": p.get("round", 1)}
            if p.get("stage"):
                link["stage"] = p["stage"]
            chain.append(link)
            prev = p.get("supersedes")
        if chain:
            out[qid] = chain[::-1]
    return out


def decision_value(e, recs):
    """What a decision settles, compared to tell a changed answer from a repeated one: an alt's
    key; an accept's or hedged accept's count of recommendation changes so far (accepting a
    revised recommendation is a new answer), with a hedged condition; an own or defer text,
    whitespace folded. An accept's note is not part of it."""
    kind, text = e["kind"], " ".join((e.get("text") or "").split())
    if kind == "alt":
        return (kind, e.get("alt"))
    if kind == "accept":
        return (kind, recs)
    return (kind, recs, text) if kind == "hedged" else (kind, text)


def unchecked_constraints(doc):
    """{question id: the recorded constraints its `checkedAgainst` lacks}. A question with no
    `checkedAgainst` list predates the field and is not judged."""
    ids = [
        c["id"]
        for c in doc.get("constraints") or []
        if isinstance(c, dict) and c.get("id")
    ]
    gaps = {}
    for q in doc.get("questions") or []:
        if (
            isinstance(q, dict)
            and q.get("id")
            and isinstance(q.get("checkedAgainst"), list)
            and not q.get("archived")
            and not q.get("supersededBy")
        ):
            missing = [c for c in ids if c not in q["checkedAgainst"]]
            if missing:
                gaps[q["id"]] = missing
    return gaps


def answer_order(questions, threshold):
    """The recommended answering order of the open questions (on the path, and held or not
    answered, as frontierLock reads a prerequisite), or [] while there are `threshold` or fewer.
    Prerequisites come first (topological by dependsOn); among the questions ready next, the
    larger blast radius (the count of transitive dependents through dependsOn) goes first, then
    the lower id. A dependsOn cycle is broken by the same keys. Advisory: it changes no state and
    no frontierLock check."""
    from exporters import natural  # exporters imports this module at its top

    path = [
        q
        for q in questions
        if isinstance(q, dict)
        and isinstance(q.get("id"), str)
        and q.get("state") not in ("archived", "proposed")
        and not q.get("supersededBy")
    ]
    open_ids = [q["id"] for q in path if q.get("waiting") or not q.get("answered")]
    if len(open_ids) <= threshold:
        return []
    deps = {q["id"]: set(q.get("dependsOn") or []) - {q["id"]} for q in path}
    children = {}
    for qid, parents in deps.items():
        for p in parents:
            children.setdefault(p, set()).add(qid)

    def blast(qid):
        seen, todo = set(), [qid]
        while todo:
            fresh = children.get(todo.pop(), set()) - seen - {qid}
            seen |= fresh
            todo += fresh
        return len(seen)

    rank = {qid: (-blast(qid), natural(qid)) for qid in open_ids}
    waits = {qid: len(deps[qid] & rank.keys()) for qid in open_ids}
    ready = [(rank[qid], qid) for qid, n in waits.items() if not n]
    heapq.heapify(ready)
    order = []
    while waits:
        if not ready:  # only a cycle is left: take its best-ranked question
            best = min(waits, key=rank.__getitem__)
            ready = [(rank[best], best)]
        qid = heapq.heappop(ready)[1]
        order.append(qid)
        del waits[qid]
        for c in children.get(qid, ()):
            if c in waits:
                waits[c] -= 1
                if not waits[c]:
                    heapq.heappush(ready, (rank[c], c))
    return order


def derive_states(doc, r):
    """(states, upstream_changed, upstream_stale, changed_by). states maps each question id to
    (state, revising); none of the four is written to questions.json.

    Live decision events replay in seq order, with each question's terminal decision placed by its
    updatedAt against the events' `at` (before a same-second event, as the page decision wins that
    tie in round.py's effective(); a terminal decision and a recommendation change in the same
    second fall in `rev` order). A question's first decision marks its direct dependents that hold
    a live decision stale. A decision that changes the question's value (decision_value) or a
    reopen of a decision marks every direct dependent: stale when it holds a live decision, else
    upstream-changed, and changed_by maps it to the questions whose answer changed. That holds on
    a stale question too, so propagation moves one hop per value-changing answer; a repeated value
    marks nothing, and the automatic transitive cascade stays deferred. A decision event carrying
    `outOfOrder` (the open prerequisites the user answered it ahead of) marks its question stale
    when the first live decision on each of them replays, whatever its dependsOn says by then; a
    newer decision on the question replaces that list. A recommendation change
    (a history line with `pageSeq`, placed after the events up to that seq) marks stale each
    question named in its `affects` and each direct dependent of the revised question that holds a
    live decision, and upstream_changed maps each such question to the revised ids that did it; a
    new decision on the question clears both. upstream-changed clears when Claude revises the
    question (a recommendation change, or a history line with `reviewSeq` placed the same way:
    a revise or a reconfirm; a revise line written before reviewSeq existed goes by its `at`) or
    a live decision on it replays. A withdrawn event never
    happened, so an undo clears what it caused. A question with a stale ancestor further up is
    upstream-pending, and upstream_stale maps it to every stale ancestor, nearest first and ties
    by id; `archived` wins over all three, then stale, then upstream-changed. A question whose
    `checkedAgainst` lacks a recorded constraint (unchecked_constraints) is upstream-changed even
    with a live decision: only a revise or reconfirm that fills the list clears it, so it waits on
    Claude, never on a new pick. The constraint ids join changed_by. A question the
    propose op added is `proposed` until a live proposal event answers it, `archived` once the
    latest one declines it, and derived as any other question once it accepts or edits it
    (proposal_answer). `revising` marks a question with its own delivered, unhandled decision
    event; upstream effects stay in the states.
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
            "alt": t.get("alt"),
            "text": t.get("text") or "",
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

    # Claude revised or reconfirmed the question: a line goes by its reviewSeq, and a revise line
    # written before reviewSeq existed goes by its time, as a terminal decision does.
    reviews = [
        (
            after(h["reviewSeq"])
            if isinstance(h.get("reviewSeq"), int)
            else slot(h.get("at") or ""),
            0,
            h.get("at") or "",
            h.get("rev") or 0,
            {"id": q["id"], "kind": "review"},
        )
        for q in qs
        for h in q.get("history") or []
        if isinstance(h, dict)
        and (
            isinstance(h.get("reviewSeq"), int)
            or h.get("kind") in ("revise", "depends", "group")
        )
    ]

    replay = [(i, 1, "", 0, e) for i, e in enumerate(events)]
    replay += [(slot(t["at"]), 0, t["at"], t["rev"], t) for t in terminal]
    replay += [(after(c["seq"]), 0, c["at"], c["rev"], c) for c in changes]
    replay += reviews
    live, stale, changed, ahead = {}, set(), {}, {}
    value, pending, recs = {}, {}, {}
    for *_, e in sorted(replay, key=lambda x: x[:4]):
        qid = e["id"]
        if e["kind"] in ("rec", "review"):
            pending.pop(qid, None)  # Claude revised or reconfirmed it
        if e["kind"] == "review":
            continue
        if e["kind"] == "rec":
            recs[qid] = recs.get(qid, 0) + 1
            hit = {c for c in e["hit"] if c != qid and live.get(c)}
            stale.update(hit)
            for c in hit:
                changed.setdefault(c, [])
                if qid not in changed[c]:
                    changed[c].append(qid)
            continue
        stale.discard(qid)
        changed.pop(qid, None)
        before = value.get(qid)
        live[qid] = e["kind"] != "reopen"
        value[qid] = decision_value(e, recs.get(qid, 0)) if live[qid] else None
        ahead[qid] = set(e.get("outOfOrder") or []) if live[qid] else set()
        if live[qid]:
            pending.pop(qid, None)
        if before is not None and value[qid] != before:
            for c in children.get(qid, []):
                if c == qid:
                    continue
                if live.get(c):
                    stale.add(c)
                elif qid not in pending.setdefault(c, []):
                    pending[c].append(qid)
        elif live[qid] and before is None:
            stale.update(c for c in children.get(qid, []) if live.get(c))
        if live[qid]:
            for c, waited in ahead.items():
                if qid in waited and c != qid:
                    waited.discard(qid)
                    if live.get(c):
                        stale.add(c)
    answers = {q["id"]: proposal_answer(q, r.get("events")) for q in qs}
    archived = {q["id"] for q in qs if q.get("archived") or answers[q["id"]] == "decline"}
    proposed = {qid for qid, a in answers.items() if a == "pending"} - archived
    stale -= archived
    pending = {c: ids for c, ids in pending.items() if c not in archived}
    for qid, missing in unchecked_constraints(doc).items():
        if qid in archived or qid in proposed:
            continue
        pending[qid] = [*pending.get(qid, []), *missing]
        stale.discard(qid)

    def upstream(qid):  # stale ancestors, nearest first, ties by id
        seen, level, found = {qid}, list(deps.get(qid, [])), []
        while level:
            level = sorted(set(level) - seen)
            seen.update(level)
            found += [p for p in level if p in stale]
            level = [g for p in level for g in deps.get(p, [])]
        return found

    revising = {
        e["id"]
        for e in events
        if e.get("deliveredAt")
        and not e.get("autoHandled")
        and not is_handled(doc, e.get("seq", 0))
    }
    out, up = {}, {}
    for qid in deps:
        if qid in archived:
            state = "archived"
        elif qid in proposed:
            state = "proposed"
        elif qid in stale:
            state = "stale"
        elif qid in pending:
            state = "upstream-changed"
        elif up.setdefault(qid, upstream(qid)):
            state = "upstream-pending"
        else:
            state = "open"
        out[qid] = (state, qid in revising)
    return (
        out,
        {c: ids for c, ids in changed.items() if c in stale},
        {c: ids for c, ids in up.items() if ids},
        pending,
    )


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


def proposal_answer(q, events):
    """For a question the propose op added: the `alt` of its latest live proposal event (accept,
    edit or decline), or `pending` while none answers it. None for any other question."""
    if not (isinstance(q, dict) and q.get("proposed")):
        return None
    alts = [
        e.get("alt")
        for e in sorted(events or [], key=lambda e: e.get("seq", 0))
        if e.get("id") == q.get("id")
        and e.get("kind") == "proposal"
        and not e.get("withdrawn")
    ]
    return alts[-1] if alts else "pending"


def check_proposal(q, alt, text, events):
    """ValueError (400) or Conflict (409) for a proposal event on q: `alt` is accept, edit or
    decline, an edit carries the reworded question in `text` (one line), and q is a proposed
    question no proposal event has answered yet."""
    answer = proposal_answer(q, events)
    if answer is None:
        raise ValueError("not a proposed question")
    if alt not in PROPOSAL:
        raise ValueError("proposal needs alt: accept, edit or decline")
    if alt == "edit" and not text.strip():
        raise ValueError("text required: the question as you would ask it")
    if alt == "edit" and (len(text) > LINE_CAP or len(text.splitlines()) > 1):
        raise ValueError(f"text must be one line of at most {LINE_CAP} characters")
    if answer != "pending":
        raise Conflict({"error": "proposal answered", "proposal": answer})


def chain_end(qs, q):
    """The id q's supersededBy chain ends at: each hop goes to a known question until one with no
    supersededBy, or one already passed (a cycle). A first hop to an unknown id ends at that id."""
    seen, cur = {q.get("id")}, q
    while (nxt := cur.get("supersededBy")) in qs and nxt not in seen:
        seen.add(nxt)
        cur = qs[nxt]
    return q.get("supersededBy") if cur is q else cur.get("id")


def check_retired(qs, q):
    """Conflict (409) for a decision on a question off the path: `superseded`, with `by` naming
    the end of its supersededBy chain (chain_end), wins over `archived`."""
    if q.get("supersededBy"):
        raise Conflict({"error": "superseded", "by": chain_end(qs, q)})
    if q.get("archived"):
        raise Conflict({"error": "archived"})


def round_complete(doc, r, qid):
    """True when every live question in qid's round has a decision in r (this accept included);
    a proposed question the user has not accepted or edited is not a question yet."""
    qs = [q for q in doc.get("questions") or [] if isinstance(q, dict)]
    rnd = next((q.get("round") for q in qs if q.get("id") == qid), None)
    return not any(
        q.get("round") == rnd
        and not q.get("archived")
        and not q.get("supersededBy")
        and proposal_answer(q, r["events"]) in (None, "accept", "edit")
        and not (r["responses"].get(q.get("id")) or {}).get("decision")
        and not (q.get("terminal") or {}).get("decision")
        for q in qs
    )


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


def history_line(event):
    """The history[id] line one user event adds; an undo also names the seq it withdrew."""
    line = {
        "at": event["at"],
        "by": "user",
        "kind": event.get("kind"),
        "alt": event.get("alt"),
        "text": event.get("text") or "",
        "seq": event["seq"],
    }
    if event.get("kind") == "undo":
        line["undoSeq"] = event.get("undoSeq")
    return line


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
            history.setdefault(qid, []).append(history_line(e))
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


def open_prereqs(doc, r, q):
    """The ids in q's dependsOn still open, in dependsOn order: on the path (not archived,
    superseded or a declined proposal) and held, or with no decision that counts. Call
    release_user_holds first."""
    from exporters import latest_decision  # exporters imports server at module top

    qs = {x.get("id"): x for x in doc.get("questions") or [] if isinstance(x, dict)}
    out = []
    for p in q.get("dependsOn") or []:
        x = qs.get(p)
        if (
            not x
            or x.get("archived")
            or x.get("supersededBy")
            or p in out
            or proposal_answer(x, r.get("events")) == "decline"
        ):
            continue
        if x.get("waiting") or not (
            latest_decision(x, r.get("responses") or {}) or {}
        ).get("decision"):
            out.append(p)
    return out


def check_out_of_order(msg):
    """ValueError (400) unless msg's `outOfOrder`, when present, is a list of question ids."""
    ooo = msg.get("outOfOrder")
    if ooo is not None and not (
        isinstance(ooo, list) and all(isinstance(p, str) for p in ooo)
    ):
        raise ValueError("outOfOrder must be a list of question ids")
    return ooo


def split_accept_audit(doc, r, items):
    """(accepted, skipped) of an accept-audit: the items the server accepts now, and an
    {id, reason} for each it refuses. `changed` is a contentRev that no longer matches;
    `ineligible` is an unknown, closed, superseded, held or recommendation-less question, one
    whose state is not open (stale, upstream-changed, upstream-pending), or one with a
    prerequisite still open (open_prereqs: an archived or superseded prerequisite is met)."""
    release_user_holds(doc, r)
    qs = {q.get("id"): q for q in doc.get("questions") or []}
    states = question_states(doc, r)
    seeded = ((doc.get("meta") or {}).get("seededFrom") or {}).get("rows") or {}
    accepted, skipped = [], []
    for it in items:
        q = qs.get(it["id"])
        if q and it["contentRev"] != content_rev(q, r["events"]):
            reason = "changed"
        elif (
            not q
            or states.get(it["id"], ("",))[0] != "open"
            or q.get("supersededBy")
            or not q.get("recommendation")
            or q.get("waiting")
            or (seeded.get(it["id"]) or {}).get("status") == "superseded-by-plan"
            or open_prereqs(doc, r, q)
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


READ_BACK = re.compile(r"^\s*Understood as:", re.I)


def check_reading(q, response, answer_seq, read_rev):
    """ValueError (400) or Conflict (409 stale) for a confirm-reading event: it names the answer
    (its seq) and the read-back it confirms (readRev, the count of Claude's `Understood as:` replies
    to that answer up to the one shown), so a reading Claude replaced after the tab drew it is refused."""
    if not isinstance(answer_seq, int) or not isinstance(read_rev, int):
        raise ValueError(
            "confirm-reading needs answerSeq and readRev: the read-back it confirms"
        )
    current = (response or {}).get("seq")
    rev = sum(
        1
        for h in q.get("history") or []
        if h.get("by") == "claude"
        and h.get("replyTo") == answer_seq
        and READ_BACK.match(h.get("text") or "")
    )
    if answer_seq != current or read_rev != rev or not rev:
        raise Conflict({"error": "stale", "answerSeq": current, "readRev": rev})


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

    def _setting(self, key):
        return self.layers.resolve(self.dir, self.user_settings())[0][key]["value"]

    def settle_window(self):
        got = self.layers.resolve(self.dir, self.user_settings())[0]
        return got["settleQuiet"]["value"], got["settleBurst"]["value"]

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
        return self._setting("leaseTimeout")

    def reading_window(self):
        return self._setting("readingWindow")

    def frontier_lock(self):
        return self._setting("frontierLock")

    def user_settings(self):
        """The user settings file `round.py ensure-running --user-settings` recorded, if any."""
        try:
            s = json.loads((self.dir / SESSION_JSON).read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return None
        return s.get("userSettings") if isinstance(s, dict) else None

    def signature(self):
        user = self.user_settings()
        listener = self.listener()
        return (
            mtime(self.questions),
            mtime(self.responses),
            mtime(self.theme),
            mtime(self.settings),
            mtime(self.watch_seq),
            mtime(self.dir / SESSION_JSON),
            mtime(self.layers.team_file) if self.layers.team_file else 0,
            mtime(self.layers.personal_file) if self.layers.personal_file else 0,
            mtime(Path(user)) if user else 0,
            listener["state"],
            # The header reads Live only while a watcher waits, and a wait inside the listen
            # grace leaves state and lease unchanged.
            listener["waiters"] > 0,
            listener["lease"] is not None,
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
            derived, changed, waits, changed_by = derive_states(q, r)
            chains = supersede_chains(q)
            # exporters imports server at module top
            from exporters import latest_decision

            for x in q.get("questions") or []:
                if isinstance(x, dict) and x.get("id") in chains:
                    x["supersedesChain"] = chains[x["id"]]
                if isinstance(x, dict) and x.get("id") in derived:
                    x["state"], x["revising"] = derived[x["id"]]
                    if x["id"] in changed:
                        x["upstreamChanged"] = changed[x["id"]]
                    if x["id"] in waits:
                        x["upstreamStale"] = waits[x["id"]]
                    if x["id"] in changed_by:
                        x["changedBy"] = changed_by[x["id"]]
                    x["answered"] = bool(
                        (latest_decision(x, r.get("responses", {})) or {}).get(
                            "decision"
                        )
                    )
                if isinstance(x, dict):
                    rec = x.get("recommendation")
                    if withheld(rec):
                        x["withheld"] = True
                    for a in x.get("alternatives") or []:
                        if isinstance(a, dict) and restates(a.get("text"), rec):
                            a["restates"] = True
            order = answer_order(
                q.get("questions") or [], settings["orderThreshold"]["value"]
            )
            if order:
                q["answerOrder"] = order
            else:
                q.pop("answerOrder", None)
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
            # The build this process started from; the page compares it with the one stamped in it.
            **self.build,
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
        ahead = check_out_of_order(msg)
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
            if kind == "proposal":
                check_proposal(qs[qid], alt, text, r["events"])
            elif kind in DECISIONS and proposal_answer(qs[qid], r["events"]) in (
                "pending",
                "decline",
            ):
                raise ValueError(
                    "a proposed question takes no decision: accept or edit the proposal first"
                )
            elif (
                kind in ("accept", "hedged")
                and qs[qid].get("proposed")
                and not qs[qid].get("recommendation")
            ):
                raise ValueError(
                    "no recommendation to accept yet: Claude writes it after the proposal's "
                    "accept or edit"
                )
            if kind in DECISIONS:
                check_retired(qs, qs[qid])
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
            elif kind == "confirm-reading":
                check_reading(
                    qs[qid],
                    r["responses"].get(qid),
                    msg.get("answerSeq"),
                    msg.get("readRev"),
                )
                event["answerSeq"], event["readRev"] = msg["answerSeq"], msg["readRev"]
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
            if kind in WITH_ALT and qid and kind != "proposal":
                check_alt(qs[qid], kind, alt)
            if kind in DECISIONS - {"reopen"}:
                release_user_holds(doc, r)
                waits, lock = open_prereqs(doc, r, qs[qid]), self.frontier_lock()
                if waits and lock == "hard":
                    raise Conflict({"error": "blocked", "waitsOn": waits})
                # An upstream answer changed: the question waits on Claude's revise or reconfirm.
                by = derive_states(doc, r)[3].get(qid) if lock != "off" else None
                if by:
                    raise Conflict({"error": "upstream-changed", "changedBy": by})
                # The page's Answer anyway names the open prerequisites; keep the ones still open.
                ahead = [p for p in waits if p in (ahead or [])]
                if ahead:
                    event["outOfOrder"] = ahead
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
                r["responses"][qid] = decision_view(event, prev.get("text", ""))
            # A plain accept or confirm needs no reply, so it wakes no agent; the accept that
            # settles its round's last question stays unhandled, so the agent learns the round is done.
            if not text.strip() and (
                kind == "confirm"
                or (kind == "accept" and not round_complete(doc, r, qid))
            ):
                event["autoHandled"] = True
            r["events"].append(event)
            if qid:
                r["history"].setdefault(qid, []).append(history_line(event))
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
                r["history"].setdefault(it["id"], []).append(history_line(accept))
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
        if is_handled(doc, target_seq) or (
            target.get("autoHandled")
            and any(
                e.get("seq", 0) > target_seq and is_handled(doc, e.get("seq", 0))
                for e in r["events"]
            )
        ):
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
            if not e.get("withdrawn")
            and not e.get("autoHandled")
            and not is_handled(doc, e.get("seq", 0))
        ]


class Handler(LoopbackHandler):
    """The page and its answers; session_bridge serves /events, /api/wait, /api/lease, /api/ping."""

    hub: "Hub"
    max_body = MAX_BODY
    page_csp = PAGE_CSP

    def route_get(self, url, query):
        hub = self.hub
        if url.path in ("/", "/index.html"):
            # The page carries the build on disk now; /api/state carries the one this process
            # started from, so a page newer than its server can tell.
            build = page_build()
            html = (
                (HERE / "index.html")
                .read_text(encoding="utf-8")
                .replace("%%TOKEN%%", hub.token)
                .replace("%%PLUGIN_VERSION%%", build["pluginVersion"])
                .replace("%%SOURCE_HASH%%", build["sourceHash"])
            )
            return self.send(200, html.encode("utf-8"), "text/html")
        if url.path in QUESTION_SHAPE:
            name, ctype = QUESTION_SHAPE[url.path]
            return self.send(200, (SHARED_WEB / name).read_bytes(), ctype)
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

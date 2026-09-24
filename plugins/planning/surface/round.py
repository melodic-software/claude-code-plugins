"""Edit questions.json without hand-editing JSON. Python 3 stdlib; atomic writes.

python round.py [--dir DATA_DIR] <command> ...
  add             add a question (from --file JSON or flags)
  add-round       add several groups, questions and visuals from one JSON file, in one write
  group           add or update a question group
  reply           append a Claude line to a question's thread; optional revised recommendation
  revise          change a question's wording, recommendation or alternatives
  handle          mark page events handled with no reply (plain accepts, undo, wrapup)
  note-reply      reply in the Notes to Claude thread
  record-terminal record an answer the user gave in the terminal
  status          open and answered counts per group, plus unhandled page events
  bump            bump the file rev (and one question's rev with --id)
  ensure-running  start the page server for the data dir, or reuse the running one; prints its URL
  stop            stop the data dir's server (only the recorded PID) and clear its session files

reply --rec and revise refuse when the question has a user event newer than --seq (without --seq:
any unhandled user event on it), unless --force.
"""

import argparse
import contextlib
import http.client
import json
import os
import secrets
import shutil
import signal
import socket
import subprocess
import sys
import time
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.dont_write_bytecode = True
sys.path.insert(0, str(HERE))
from server import EMPTY_RESPONSES, is_handled, load_json, save_json  # noqa: E402

DECISIONS = ("accept", "alt", "own", "defer")
SESSION_FILES = (".interview-session.json", ".interview-session.env")
LOCK_NAME = "questions.json.lock"
LOCK_SECONDS = 10
START_SECONDS = 3

if os.name == "nt":
    import msvcrt

    def _lock(f):
        f.seek(0)
        msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)

    def _unlock(f):
        f.seek(0)
        msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
else:
    import fcntl

    def _lock(f):
        fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)

    def _unlock(f):
        fcntl.flock(f.fileno(), fcntl.LOCK_UN)


def now():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load(d):
    doc = load_json(
        d / "questions.json", {"meta": {}, "rev": 0, "groups": [], "questions": []}
    )
    for k, v in (
        ("meta", {}),
        ("rev", 0),
        ("groups", []),
        ("questions", []),
        ("visuals", []),
    ):
        doc.setdefault(k, v)
    return doc


def save(d, doc, touched=()):
    doc["rev"] = doc.get("rev", 0) + 1
    for q in touched:
        q["rev"] = doc["rev"]
    save_json(d / "questions.json", doc)


def find(doc, qid):
    for q in doc["questions"]:
        if q.get("id") == qid:
            return q
    sys.exit(f"unknown question: {qid}")


def split_alt(s):
    key, sep, text = s.partition(":")
    if not sep:
        sys.exit(f"--alt needs key:text, got {s!r}")
    return {"key": key.strip(), "text": text.strip()}


def mark_handled(doc, seqs):
    """Per-event handled set. handledSeq advances only over a gap-free run, so it never hides an unhandled event."""
    done = set(doc.get("handled") or []) | {s for s in seqs if s}
    hs = doc.get("handledSeq") or 0
    while hs + 1 in done:
        hs += 1
    doc["handledSeq"] = hs
    doc["handled"] = sorted(s for s in done if s > hs)


def guard_revision(d, doc, qid, seq, force):
    """Refuse a revision when the user acted on the question after the event being answered.
    Without --seq, only an unhandled user event on the question blocks it."""
    if force:
        return
    events = [
        e
        for e in load_json(d / "responses.json", EMPTY_RESPONSES).get("events", [])
        if e.get("id") == qid
    ]
    if seq is None:
        newer = [
            e["seq"]
            for e in events
            if not is_handled(doc, e["seq"]) and not e.get("withdrawn")
        ]
        why = "an unhandled user event"
    else:
        newer = [e["seq"] for e in events if e["seq"] > seq]
        why = f"a user event newer than --seq {seq}"
    if newer:
        sys.exit(
            f"refused: {qid} has {why} (#{max(newer)}). Read it first, or pass --force."
        )


def add_question(doc, q):
    """Validate and append one question; returns the questions whose rev must bump. Exits before any write."""
    for req in ("id", "short", "title"):
        if not q.get(req):
            sys.exit(f"missing {req}")
    if any(x.get("id") == q["id"] for x in doc["questions"]):
        sys.exit(f"duplicate id: {q['id']}")
    known = {x["id"] for x in doc["questions"]}
    for ref in [q.get("followUpOf"), q.get("supersedes"), *q.get("dependsOn", [])]:
        if ref and ref not in known:
            sys.exit(f"unknown reference in {q['id']}: {ref}")
    if q.get("group") and q["group"] not in {g["id"] for g in doc["groups"]}:
        sys.exit(
            f"unknown group in {q['id']}: {q['group']} (add it with: round.py group)"
        )
    q.setdefault("stage", "interview")
    q.setdefault(
        "round",
        max(
            [
                x.get("round", 1)
                for x in doc["questions"]
                if x.get("stage") == q["stage"]
            ]
            or [1]
        ),
    )
    q.setdefault("history", []).append({"at": now(), "by": "claude", "text": "Asked."})
    touched = [q]
    if q.get("supersedes"):
        old = find(doc, q["supersedes"])
        old["supersededBy"] = q["id"]
        old.setdefault("history", []).append(
            {"at": now(), "by": "claude", "text": f"Superseded by {q['id']}."}
        )
        touched.append(old)
    doc["questions"].append(q)
    return touched


def put_group(doc, g):
    cur = next((x for x in doc["groups"] if x["id"] == g["id"]), None)
    if cur is None:
        cur = {"id": g["id"]}
        doc["groups"].append(cur)
    cur.update({k: v for k, v in g.items() if v is not None})
    if not cur.get("title"):
        sys.exit(f"a new group needs a title: {g['id']}")
    known = {x["id"] for x in doc["groups"]}
    for ref in cur.get("dependsOn") or []:
        if ref not in known:
            sys.exit(f"unknown group in {g['id']} dependsOn: {ref}")


def cmd_add(d, a):
    doc = load(d)
    q = json.loads(Path(a.file).read_text(encoding="utf-8")) if a.file else {}
    for field in (
        "id",
        "group",
        "short",
        "title",
        "stage",
        "facts",
        "recommendation",
        "basis",
        "followUpOf",
        "supersedes",
        "waitsOn",
    ):
        val = getattr(a, field.replace("recommendation", "rec"), None)
        if val is not None:
            q[field] = val
    if a.round is not None:
        q["round"] = a.round
    if a.commit:
        q["commits"] = a.commit
    if a.alt:
        q["alternatives"] = [split_alt(s) for s in a.alt]
    if a.depends:
        q["dependsOn"] = a.depends
    if a.waiting:
        q["waiting"] = True
    touched = add_question(doc, q)
    save(d, doc, touched)
    print(f"added {q['id']} (rev {doc['rev']})")


def cmd_add_round(d, a):
    """{"groups": [...], "questions": [...], "visuals": [...]}: groups first, then questions in file order."""
    doc = load(d)
    spec = json.loads(Path(a.file).read_text(encoding="utf-8"))
    for g in spec.get("groups", []):
        if not g.get("id"):
            sys.exit("a group needs an id")
        put_group(doc, g)
    touched = []
    for q in spec.get("questions", []):
        if a.round is not None:
            q.setdefault("round", a.round)
        touched += add_question(doc, q)
    ids = {v.get("id") for v in doc["visuals"]}
    for v in spec.get("visuals", []):
        if not v.get("id") or v["id"] in ids:
            sys.exit(f"a visual needs a new id: {v.get('id')}")
        doc["visuals"].append(v)
        ids.add(v["id"])
    save(d, doc, touched)
    print(
        f"added {len(spec.get('questions', []))} questions, {len(spec.get('groups', []))} groups, "
        f"{len(spec.get('visuals', []))} visuals (rev {doc['rev']})"
    )


def cmd_group(d, a):
    doc = load(d)
    put_group(
        doc,
        {"id": a.id, "title": a.title, "summary": a.summary, "dependsOn": a.depends},
    )
    save(d, doc)
    print(f"group {a.id} saved (rev {doc['rev']})")


def cmd_reply(d, a):
    doc = load(d)
    q = find(doc, a.id)
    line = {"at": now(), "by": "claude", "text": a.text}
    if a.kind:
        line["kind"] = a.kind
    if a.seq is not None:
        line["replyTo"] = a.seq
    if a.rec:
        guard_revision(d, doc, a.id, a.seq, a.force)
        q["previousRecommendation"] = q.get("recommendation", "")
        q["recommendation"] = a.rec
        q["revised"] = a.why or "Recommendation revised."
        q["contentRev"] = (q.get("contentRev") or 0) + 1
        line["text"] = (
            (a.text + " " if a.text else "") + "Revised recommendation: " + a.rec
        )
    if a.handled:
        doc["handledSeq"] = max(doc.get("handledSeq") or 0, a.handled)
    mark_handled(doc, [a.seq])
    q.setdefault("history", []).append(line)
    save(d, doc, [q])
    print(f"replied on {a.id} (rev {doc['rev']})")


def cmd_revise(d, a):
    doc = load(d)
    q = find(doc, a.id)
    guard_revision(d, doc, a.id, a.seq, a.force)
    changed = []
    for field, val in (
        ("title", a.title),
        ("short", a.short),
        ("facts", a.facts),
        ("basis", a.basis),
    ):
        if val is not None:
            q[field] = val
            changed.append(field)
    if a.rec is not None:
        q["previousRecommendation"] = q.get("recommendation", "")
        q["recommendation"] = a.rec
        q["revised"] = a.why or "Recommendation revised."
        changed.append("recommendation")
    if a.alt:
        q["alternatives"] = [split_alt(s) for s in a.alt]
        changed.append("alternatives")
    if not changed:
        sys.exit("nothing to revise")
    q["contentRev"] = (q.get("contentRev") or 0) + 1
    line = {
        "at": now(),
        "by": "claude",
        "kind": "revise",
        "text": a.text or "Revised " + ", ".join(changed) + ".",
    }
    if a.seq is not None:
        line["replyTo"] = a.seq
    q.setdefault("history", []).append(line)
    mark_handled(doc, [a.seq])
    save(d, doc, [q])
    print(f"revised {a.id}: {', '.join(changed)} (rev {doc['rev']})")


def cmd_handle(d, a):
    doc = load(d)
    mark_handled(doc, a.seq)
    save(d, doc)
    print(
        f"handled {', '.join(map(str, a.seq))}; handledSeq {doc['handledSeq']} (rev {doc['rev']})"
    )


def cmd_note_reply(d, a):
    doc = load(d)
    line = {"at": now(), "by": "claude", "text": a.text}
    if a.seq is not None:
        line["replyTo"] = a.seq
    doc.setdefault("notes", []).append(line)
    mark_handled(doc, [a.seq])
    save(d, doc)
    print(f"note reply saved (rev {doc['rev']})")


def cmd_record_terminal(d, a):
    doc = load(d)
    q = find(doc, a.id)
    if a.decision == "alt" and not a.alt:
        sys.exit("--alt KEY required with --decision alt")
    at = now()
    q["terminal"] = {
        "decision": a.decision,
        "alt": a.alt if a.decision == "alt" else None,
        "text": a.text or "",
        "updatedAt": at,
    }
    q["contentRev"] = (q.get("contentRev") or 0) + 1
    label = {
        "accept": "Accepted",
        "alt": f"Chose ({a.alt})",
        "own": "Answered",
        "defer": "Deferred",
    }[a.decision]
    q.setdefault("history", []).append(
        {
            "at": at,
            "by": "user-terminal",
            "kind": a.decision,
            "alt": q["terminal"]["alt"],
            "text": a.text or "",
            "summary": label,
        }
    )
    save(d, doc, [q])
    print(f"recorded terminal answer on {a.id} (rev {doc['rev']})")


def effective(q, resp):
    page, term = resp.get(q["id"]), q.get("terminal")
    cands = [x for x in (page, term) if x and x.get("updatedAt")]
    latest = max(cands, key=lambda x: x["updatedAt"]) if cands else None
    return latest.get("decision") if latest else None


def cmd_status(d, a):
    doc = load(d)
    r = load_json(d / "responses.json", EMPTY_RESPONSES)
    resp = r.get("responses", {})
    groups = {g["id"]: g for g in doc["groups"]}
    order = [g["id"] for g in doc["groups"]] + [None]
    rows = {}
    for q in doc["questions"]:
        dec = effective(q, resp)
        state = dec or (
            "superseded"
            if q.get("supersededBy")
            else "waiting"
            if q.get("waiting")
            else "open"
        )
        rows.setdefault(q.get("group"), []).append((q["id"], q.get("short", ""), state))
    for gid in order:
        if gid not in rows:
            continue
        items = rows[gid]
        opened = [f"{i} {s}" for i, s, st in items if st == "open"]
        title = groups.get(gid, {}).get("title", "Ungrouped")
        print(
            f"{title}: {len(items) - len(opened)} of {len(items)} closed"
            + (f"; open: {', '.join(opened)}" if opened else "")
        )
    hs, extra = doc.get("handledSeq") or 0, set(doc.get("handled") or [])
    pending = [
        e for e in r.get("events", []) if e.get("seq", 0) > hs and e["seq"] not in extra
    ]
    print(
        f"rev {doc['rev']}; page seq {r.get('seq', 0)}; handledSeq {hs}; unhandled events {len(pending)}"
    )
    for e in pending:
        print(
            f"  #{e['seq']} {e.get('id') or '-'} {e['kind']}"
            + (f" ({e['alt']})" if e.get("alt") else "")
            + (f" of #{e['undoSeq']}" if e.get("undoSeq") else "")
            + (" [withdrawn]" if e.get("withdrawn") else "")
            + (f": {e['text']}" if e.get("text") else "")
        )


def cmd_bump(d, a):
    doc = load(d)
    touched = [find(doc, a.id)] if a.id else []
    save(d, doc, touched)
    print(f"rev {doc['rev']}")


@contextlib.contextmanager
def sidecar_lock(d, seconds=LOCK_SECONDS):
    """OS lock on questions.json.lock, a file never replaced, so os.replace on questions.json stays free."""
    path = d / LOCK_NAME
    with open(path, "a+b") as f:
        deadline = time.monotonic() + seconds
        while True:
            try:
                _lock(f)
                break
            except OSError:
                if time.monotonic() >= deadline:
                    sys.exit(
                        f"could not lock {path} within {seconds} s: another round.py holds it"
                    )
                time.sleep(0.05)
        try:
            yield
        finally:
            _unlock(f)


def ping(port, timeout=1.0):
    """GET /api/ping on 127.0.0.1 (no proxy); the parsed body on 200, else None."""
    conn = http.client.HTTPConnection("127.0.0.1", int(port), timeout=timeout)
    try:
        conn.request("GET", "/api/ping")
        resp = conn.getresponse()
        return json.loads(resp.read()) if resp.status == 200 else None
    except (OSError, ValueError, http.client.HTTPException):
        return None
    finally:
        conn.close()


def read_session(d):
    try:
        s = json.loads((d / SESSION_FILES[0]).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return s if isinstance(s, dict) and s.get("port") and s.get("pid") else None


def same_dir(a, b):
    return os.path.normcase(str(Path(a).resolve())) == os.path.normcase(
        str(Path(b).resolve())
    )


def running(d, s):
    """True only when the recorded port answers with the recorded PID for this data dir."""
    p = ping(s["port"])
    return bool(p) and p.get("pid") == s["pid"] and same_dir(p.get("dataDir") or "", d)


def port_free(port):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind(("127.0.0.1", port))
        except OSError:
            return False
    return True


def start_server(d, port, nonce):
    """Start server.py detached from this process: no inherited stdio, own session or process group."""
    cmd = [
        sys.executable,
        str(HERE / "server.py"),
        "--dir",
        str(d),
        "--port",
        str(port),
        "--nonce",
        nonce,
    ]
    kw = {
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
        "close_fds": True,
    }
    if os.name != "nt":
        return subprocess.Popen(cmd, start_new_session=True, **kw)
    flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
    try:
        return subprocess.Popen(
            cmd, creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kw
        )
    except OSError:  # the job this process runs in forbids breakaway
        return subprocess.Popen(cmd, creationflags=flags, **kw)


def wait_started(d, nonce, proc, seconds=START_SECONDS):
    """The session carrying our nonce once its /api/ping answers 200, or None."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline and proc.poll() is None:
        s = read_session(d)
        if s and s.get("nonce") == nonce and running(d, s):
            return s
        time.sleep(0.05)
    return None


def read_user_settings(path):
    if not path:
        return {}
    try:
        settings = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError) as e:
        print(f"ignored user settings {path}: {e}", file=sys.stderr)
        return {}
    return settings if isinstance(settings, dict) else {}


def open_browser(url, settings):
    """Open the page unless openBrowser is false; browserCommand (a program or an argv list) gets the URL."""
    if settings.get("openBrowser") is False:
        return
    cmd = settings.get("browserCommand")
    if cmd:
        argv = [cmd] if isinstance(cmd, str) else cmd
        if not isinstance(argv, list) or not all(
            isinstance(x, str) and x for x in argv
        ):
            sys.exit("browserCommand must be a program or a list of strings")
        subprocess.Popen(
            [*argv, url],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        return
    webbrowser.open(url)


def cmd_ensure_running(d, a):
    if not shutil.which("curl"):
        sys.exit("missing prerequisite: curl (the watcher needs it on PATH)")
    d.mkdir(parents=True, exist_ok=True)
    with sidecar_lock(d):
        s = read_session(d)
        if not (s and running(d, s)):
            port = a.port or (s or {}).get("port") or 0
            if port and not port_free(port):
                port = 0
            nonce = secrets.token_hex(8)
            proc = start_server(d, port, nonce)
            s = wait_started(d, nonce, proc)
            if s is None:
                if proc.poll() is None:
                    proc.kill()
                sys.exit(
                    f"the server did not start within {START_SECONDS} s (data dir {d})"
                )
        if a.user_settings:
            s["userSettings"] = str(Path(a.user_settings).resolve())
            save_json(d / SESSION_FILES[0], s)
    print(s["url"])
    if a.open:
        open_browser(s["url"], read_user_settings(a.user_settings))


def clear_session(d):
    for name in SESSION_FILES:
        (d / name).unlink(missing_ok=True)


def cmd_stop(d, a):
    """Kill the recorded PID only when its port answers with that PID; otherwise just clear the files."""
    if not d.is_dir():
        print("not running")
        return
    with sidecar_lock(d):
        s = read_session(d)
        if not (s and running(d, s)):
            clear_session(d)
            print("not running")
            return
        os.kill(s["pid"], signal.SIGTERM)
        deadline = time.monotonic() + START_SECONDS
        while time.monotonic() < deadline and ping(s["port"], timeout=0.5):
            time.sleep(0.05)
        clear_session(d)
    print(f"stopped {s['pid']}")


def main(argv=None):
    p = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    p.add_argument(
        "--dir",
        default=str(HERE),
        help="data dir holding questions.json (default: this folder)",
    )
    sub = p.add_subparsers(dest="cmd", required=True)

    s = sub.add_parser("add", help="add a question")
    s.add_argument("--file", help="question JSON; flags override its fields")
    for f in (
        "id",
        "group",
        "short",
        "title",
        "stage",
        "facts",
        "rec",
        "basis",
        "waits-on",
    ):
        s.add_argument(
            "--" + f, dest=f.replace("-", "_").replace("waits_on", "waitsOn")
        )
    s.add_argument("--round", type=int)
    s.add_argument("--commit", action="append", help="repeatable")
    s.add_argument("--alt", action="append", help="key:text, repeatable")
    s.add_argument("--depends", action="append", help="question id, repeatable")
    s.add_argument("--follow-up-of", dest="followUpOf")
    s.add_argument("--supersedes")
    s.add_argument("--waiting", action="store_true")
    s.set_defaults(fn=cmd_add)

    s = sub.add_parser(
        "add-round", help="groups, questions and visuals from one JSON file, one write"
    )
    s.add_argument(
        "--file",
        required=True,
        help='{"groups": [...], "questions": [...], "visuals": [...]}',
    )
    s.add_argument("--round", type=int, help="round for questions that do not set one")
    s.set_defaults(fn=cmd_add_round)

    s = sub.add_parser("group", help="add or update a group")
    s.add_argument("id")
    s.add_argument("--title")
    s.add_argument("--summary")
    s.add_argument("--depends", action="append", help="group id, repeatable")
    s.set_defaults(fn=cmd_group)

    s = sub.add_parser(
        "reply", help="append a Claude line; optional revised recommendation"
    )
    s.add_argument("id")
    s.add_argument("--text", default="")
    s.add_argument("--rec", help="revised recommendation")
    s.add_argument("--why", help="one line shown in the Revised banner")
    s.add_argument("--kind", choices=("reply", "rephrase", "note"))
    s.add_argument(
        "--seq", type=int, help="page event seq this answers; marks it handled"
    )
    s.add_argument(
        "--handled", type=int, help="also mark every page event up to this seq handled"
    )
    s.add_argument(
        "--force", action="store_true", help="revise even if a newer user event exists"
    )
    s.set_defaults(fn=cmd_reply)

    s = sub.add_parser("revise", help="change wording, recommendation or alternatives")
    s.add_argument("id")
    for f in ("title", "short", "facts", "basis", "rec", "why", "text"):
        s.add_argument("--" + f)
    s.add_argument(
        "--alt", action="append", help="key:text, repeatable; replaces all alternatives"
    )
    s.add_argument(
        "--seq", type=int, help="page event seq this answers; marks it handled"
    )
    s.add_argument(
        "--force", action="store_true", help="revise even if a newer user event exists"
    )
    s.set_defaults(fn=cmd_revise)

    s = sub.add_parser("handle", help="mark page events handled with no reply")
    s.add_argument("--seq", type=int, nargs="+", required=True)
    s.set_defaults(fn=cmd_handle)

    s = sub.add_parser("note-reply", help="reply in the Notes to Claude thread")
    s.add_argument("--text", required=True)
    s.add_argument(
        "--seq", type=int, help="note event seq this answers; marks it handled"
    )
    s.set_defaults(fn=cmd_note_reply)

    s = sub.add_parser("record-terminal", help="record the user's terminal answer")
    s.add_argument("id")
    s.add_argument("--decision", required=True, choices=DECISIONS)
    s.add_argument("--alt")
    s.add_argument("--text")
    s.set_defaults(fn=cmd_record_terminal)

    sub.add_parser("status", help="open and answered per group").set_defaults(
        fn=cmd_status
    )

    s = sub.add_parser("bump", help="bump rev")
    s.add_argument("--id")
    s.set_defaults(fn=cmd_bump)

    s = sub.add_parser(
        "ensure-running",
        help="start the server for the data dir or reuse it; prints the URL",
    )
    s.add_argument(
        "--dir",
        default=argparse.SUPPRESS,
        help="data dir (same as the top-level --dir)",
    )
    s.add_argument(
        "--port",
        type=int,
        help="port to try first (default: the recorded one, else a free one)",
    )
    s.add_argument("--open", action="store_true", help="open the page in a browser")
    s.add_argument(
        "--user-settings", dest="user_settings", help="user settings JSON file"
    )
    s.set_defaults(fn=cmd_ensure_running)

    s = sub.add_parser("stop", help="stop the data dir's server")
    s.add_argument(
        "--dir",
        default=argparse.SUPPRESS,
        help="data dir (same as the top-level --dir)",
    )
    s.set_defaults(fn=cmd_stop)

    a = p.parse_args(argv)
    d = Path(a.dir).resolve()
    if not d.is_dir() and a.fn not in (cmd_ensure_running, cmd_stop):
        sys.exit(f"no such data dir: {d}")
    a.fn(d, a)


if __name__ == "__main__":
    main()

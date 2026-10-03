# GENERATED from lib/session-bridge/view_bridge.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""view-bridge: the session-bridge app that makes a built view Claude-interactive. Python 3 stdlib.

Usage: python view_bridge.py --dir DATA_DIR <command>
  ensure-running [--port P] [--idle-seconds S]
                             start the server on the data dir (or reuse it); print its JSON
  serve --port P --nonce N [--idle-seconds S]
                             run the server in the foreground (ensure-running spawns this)
  apply --file F             merge the session's replies from F into replies.json, then remove F
  stop                       stop the server and its watcher
  lease [--release]          show (or clear) the watcher lease

The page is `<data_dir>/page.html`, built by lib/view-builder.mjs with `--connect` naming the origin
ensure-running prints. The server serves it at `/`, hands the page its token at `/api/token`, takes
page actions at `POST /api/action` into `actions.json` (the event log), and streams `state` frames
on `/events`. `replies.json` is the session's file: the seqs it handled and its reply to each.

A page action holds only builder keys, builder row ids and the reader's own notes. Anything else is
refused. Nothing here acts on an action: the watcher prints it under session_bridge.DATA_NOTE and the
session decides (rendered-views README, rule 9).

The token lives only while the session listens: the server exits once no watcher has waited for
IDLE_SECONDS, and the next ensure-running starts a server with a new token. A session that ends takes
its background watcher with it, so its token stops working within IDLE_SECONDS of its last wait.
"""

import argparse
import json
import os
import re
import secrets
import shlex
import shutil
import signal
import sys
import threading
import time
from pathlib import Path

import session_bridge as bridge

HERE = Path(__file__).resolve().parent
NAME = "view"
START_SECONDS = 10
# No watcher wait for this long ends the server, and its token with it.
IDLE_SECONDS = bridge.LEASE_TIMEOUT
KEY = re.compile(r"^[a-z0-9-]{1,32}$")
ROW_ID = re.compile(r"^[a-z0-9-]{1,128}$")
FIELDS = {"action", "picked", "choices", "notes"}
MAX_PICKED = 500
MAX_KEYED = 20
MAX_NOTE = 4000
MAX_REPLY = 4000
MAX_EVENTS = 1000


def load_json(path, default):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except FileNotFoundError:
        return default


def write_json(path, value):
    bridge.write_private(path, json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def keyed(value, field, check):
    """A {key: value} map of at most MAX_KEYED builder keys, each value passing check."""
    if not isinstance(value, dict) or len(value) > MAX_KEYED:
        raise ValueError(f"{field} must be an object of at most {MAX_KEYED} entries")
    for k, v in value.items():
        if not KEY.match(k) or not check(v):
            raise ValueError(f"{field} holds a key or value the page did not build")
    return value


def parse_action(msg):
    """The action a page sent, or ValueError. Only builder keys, row ids and the reader's notes pass."""
    extra = sorted(set(msg) - FIELDS)
    if extra:
        raise ValueError(f"unknown field: {extra[0]}")
    action = msg.get("action")
    if not isinstance(action, str) or not KEY.match(action):
        raise ValueError("action must be a builder key")
    picked = msg.get("picked", [])
    if (
        not isinstance(picked, list)
        or len(picked) > MAX_PICKED
        or not all(isinstance(p, str) and ROW_ID.match(p) for p in picked)
    ):
        raise ValueError("picked must be a list of builder row ids")
    choices = keyed(
        msg.get("choices", {}),
        "choices",
        lambda v: isinstance(v, str) and bool(KEY.match(v)),
    )
    notes = keyed(
        msg.get("notes", {}),
        "notes",
        lambda v: isinstance(v, str) and 0 < len(v) <= MAX_NOTE,
    )
    return {
        "action": action,
        "picked": list(dict.fromkeys(picked)),
        "choices": choices,
        "notes": notes,
    }


def mtime(path):
    try:
        return path.stat().st_mtime_ns
    except OSError:
        return 0


class ViewHub(bridge.LoopbackWatcher):
    name = NAME

    def __init__(self, port, data_dir, idle=IDLE_SECONDS):
        super().__init__(port, data_dir)
        self.actions = self.dir / "actions.json"
        self.replies = self.dir / "replies.json"
        self.page = self.dir / "page.html"
        self.idle = idle
        self.started = time.time()

    def expired(self):
        """True once no watcher wait is in flight and none has ended for `idle` seconds."""
        with self.cond:
            quiet = time.time() - max(self.last_wait, self.started)
            return self.waiters == 0 and quiet > self.idle

    def read_log(self):
        return load_json(self.actions, {"seq": 0, "events": []})

    def write_log(self, log):
        write_json(self.actions, log)

    def read_replies(self):
        r = load_json(self.replies, {})
        return set(r.get("handled", [])), r.get("replies", {})

    def unhandled(self, log):
        handled, _ = self.read_replies()
        return [e for e in log.get("events", []) if e["seq"] not in handled]

    def identity(self):
        return {"app": NAME}

    def signature(self):
        return mtime(self.actions), mtime(self.replies), self.listener()["state"]

    def read_state(self):
        """The page's frame: whether the session listens, and each action's progress and reply."""
        try:
            log = self.read_log()
            handled, replies = self.read_replies()
        except (OSError, ValueError):
            return None, True
        events = [
            {
                "seq": e["seq"],
                "action": e["action"],
                "delivered": bool(e.get("deliveredAt")),
                "handled": e["seq"] in handled,
                "reply": replies.get(str(e["seq"])),
            }
            for e in log.get("events", [])
        ]
        return {
            "instance": self.instance,
            "listening": self.listener()["state"],
            "events": events,
        }, False

    def record(self, msg):
        action = parse_action(msg)
        with self.cond:
            log = self.read_log()
            if len(log["events"]) >= MAX_EVENTS:
                raise ValueError(
                    f"the page has sent {MAX_EVENTS} actions; restart the view"
                )
            log["seq"] += 1
            log["events"].append({"seq": log["seq"], "at": bridge.now_iso(), **action})
            self.write_log(log)
            self.cond.notify_all()
            return log["seq"]


class ViewHandler(bridge.LoopbackHandler):
    """The built page, its token, and its actions; session_bridge serves the rest."""

    hub: ViewHub
    # The page carries its own policy (the builder's meta); this one adds what a meta cannot.
    page_csp = "frame-ancestors 'none'; base-uri 'none'; form-action 'none'"

    def route_get(self, url, query):
        if url.path in ("/", "/index.html"):
            try:
                raw = self.hub.page.read_bytes()
            except OSError:
                return self.send(404, {"error": "no page.html in the data dir yet"})
            return self.send(200, raw, "text/html")
        if url.path == "/api/token":
            # Only the page's own script gets the token: a browser sets Sec-Fetch-Site and no page
            # can forge it, and do_GET already refused a foreign Host or Origin. The token never
            # enters the page's markup, so a saved or published copy holds none.
            if self.headers.get("Sec-Fetch-Site") != "same-origin":
                return self.send(403, {"error": "same-origin page script only"})
            return self.send(200, {"token": self.hub.token})
        return self.send(404, {"error": "not found"})

    def route_post(self, path, msg):
        if path != "/api/action":
            return self.send(404, {"error": "not found"})
        try:
            seq = self.hub.record(msg)
        except ValueError as e:
            return self.send(400, {"error": str(e)})
        return self.send(
            200, {"ok": True, "seq": seq, "listening": self.hub.listener()["state"]}
        )


# Control half: what the skill and wake.sh run.


def parse_ops(raw, seqs):
    """{handled: [seq], replies: [{seq, text}]} checked against the log's seqs, or ValueError."""
    if not isinstance(raw, dict) or set(raw) - {"handled", "replies"}:
        raise ValueError("ops must be an object with handled and replies only")
    handled = raw.get("handled", [])
    replies = raw.get("replies", [])
    if not isinstance(handled, list) or not isinstance(replies, list):
        raise ValueError("handled and replies must be lists")
    if not all(type(s) is int for s in handled):
        raise ValueError("handled holds page action seqs")
    out = {}
    for r in replies:
        if not (
            isinstance(r, dict) and set(r) == {"seq", "text"} and type(r["seq"]) is int
        ):
            raise ValueError("each reply is {seq, text}")
        if not isinstance(r["text"], str) or not 0 < len(r["text"]) <= MAX_REPLY:
            raise ValueError(f"a reply's text is 1 to {MAX_REPLY} characters")
        out[r["seq"]] = r["text"]
    done = set(handled) | set(out)
    unknown = sorted(done - seqs)
    if unknown:
        raise ValueError(f"no page action has seq {unknown[0]!r}")
    return done, out


def cmd_apply(d, a):
    f = Path(a.file)
    if not f.exists():
        print("nothing to apply")
        return
    log = load_json(d / "actions.json", {"seq": 0, "events": []})
    try:
        done, out = parse_ops(
            json.loads(f.read_text(encoding="utf-8")), {e["seq"] for e in log["events"]}
        )
    except ValueError as e:
        sys.exit(f"apply: {e}")
    current = load_json(d / "replies.json", {})
    handled = set(current.get("handled", [])) | done
    replies = {**current.get("replies", {}), **{str(k): v for k, v in out.items()}}
    write_json(d / "replies.json", {"handled": sorted(handled), "replies": replies})
    f.unlink()
    print(f"applied {len(done)} action(s), {len(out)} reply(ies)")


def cmd_serve(d, a):
    httpd, hub = bridge.start(
        ViewHandler, lambda port: ViewHub(port, d, a.idle_seconds), a.port, a.nonce
    )

    def expire():
        while not hub.expired():
            time.sleep(1)
        httpd.shutdown()

    threading.Thread(target=expire, daemon=True).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        s = bridge.read_session(d, NAME)
        if s and s["pid"] == os.getpid():
            bridge.clear_session(d, NAME)


def cmd_ensure_running(d, a):
    if not shutil.which("curl"):
        sys.exit("missing prerequisite: curl (the watcher needs it on PATH)")
    d.mkdir(mode=0o700, parents=True, exist_ok=True)
    s = bridge.read_session(d, NAME)
    if not (s and bridge.running(d, s)):
        ports = [a.port, bridge.kept_port(d, NAME)]
        port = next((p for p in ports if p and bridge.port_free(p)), 0)
        nonce = secrets.token_hex(8)
        cmd = [bridge.interpreter(), str(HERE / "view_bridge.py"), "--dir", str(d)]
        idle = ["--idle-seconds", str(a.idle_seconds)]
        proc = bridge.spawn(
            [*cmd, "serve", "--port", str(port), "--nonce", nonce, *idle]
        )
        s = bridge.wait_started(d, NAME, nonce, proc, START_SECONDS)
        if s is None:
            if proc.poll() is None:
                proc.kill()
            sys.exit(
                f"the server did not start within {START_SECONDS} s (data dir {d})"
            )
    origin = f"http://127.0.0.1:{int(s['port'])}"
    print(
        json.dumps(
            {
                "url": origin + "/",
                "origin": origin,
                "page": str(d / "page.html"),
                "watch": f"bash {shlex.quote(str(HERE / 'watch.sh'))} {shlex.quote(str(d))}",
            }
        )
    )


def cmd_stop(d, a):
    s = bridge.read_session(d, NAME) if d.is_dir() else None
    if not (s and bridge.running(d, s)):
        if d.is_dir():
            bridge.clear_session(d, NAME)
        print("not running")
        return
    bridge.end_watcher(d, (bridge.watcher_lease(d, NAME) or {}).get("pid"))
    os.kill(s["pid"], signal.SIGTERM)
    deadline = time.monotonic() + START_SECONDS
    while time.monotonic() < deadline and bridge.ping(s["port"], timeout=0.5):
        time.sleep(0.05)
    bridge.clear_session(d, NAME)
    print(f"stopped {s['pid']}")


def cmd_lease(d, a):
    s = bridge.read_session(d, NAME)
    if not (s and bridge.running(d, s)):
        sys.exit("not running")
    if a.release and bridge.release_lease(s, NAME) != 200:
        sys.exit("release refused")
    lease = bridge.watcher_lease(d, NAME)
    print(f"lease held by {lease['watcher']}" if lease else "no lease")


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--dir", required=True, help="the view's data dir")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("ensure-running")
    s.add_argument("--port", type=int, default=None)
    s.add_argument("--idle-seconds", type=float, default=IDLE_SECONDS)
    s = sub.add_parser("serve")
    s.add_argument("--port", type=int, default=0)
    s.add_argument("--nonce", default="")
    s.add_argument("--idle-seconds", type=float, default=IDLE_SECONDS)
    s = sub.add_parser("apply")
    s.add_argument("--file", required=True)
    sub.add_parser("stop")
    s = sub.add_parser("lease")
    s.add_argument("--release", action="store_true")
    a = p.parse_args(argv)
    d = Path(a.dir).resolve()
    {
        "ensure-running": cmd_ensure_running,
        "serve": cmd_serve,
        "apply": cmd_apply,
        "stop": cmd_stop,
        "lease": cmd_lease,
    }[a.cmd](d, a)


if __name__ == "__main__":
    main()

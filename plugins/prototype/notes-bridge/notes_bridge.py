# GENERATED from lib/ui-feedback/notes_bridge.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
"""notes-bridge: the session-bridge app that carries in-page notes on a non-final UI. Python 3 stdlib.

Usage: python notes_bridge.py --dir DATA_DIR <command>
  ensure-running [--page NAME] [--port P] [--idle-seconds S]
                             start the server on the data dir (or reuse it, unless it started
                             from another plugin build or frames another page: then restart
                             it); print its JSON
  serve --port P --nonce N [--page NAME] [--idle-seconds S]
                             run the server in the foreground (ensure-running spawns this)
  apply --file F             merge the session's replies from F into replies.json, then remove F
  import --file F            append the notes of one copy-out block in F (Copy all notes on the
                             host page) to actions.json, every note checked against
                             note.schema.json and all or none taken, then remove F; a note
                             already in the log is skipped. Needs no server, and refuses while
                             one runs on the data dir
  stop                       stop the server and its watcher
  lease [--release]          show (or clear) the watcher lease
  status                     list the unhandled notes; needs no server or watcher

The framed page is `<data_dir>/<NAME>` (default page.html), a model-written page the session
wrote. `/` serves host.html, the checked-in host page. It fetches the page at `/api/page`, with
the mockup policy (PAGE_CSP) put first and the pin helper (proto-pin.js) appended, and frames it
through `srcdoc` with sandbox="allow-scripts" and never allow-same-origin, so the page has an
opaque origin, no storage, and no network. The host page alone holds the token and posts each
note to `POST /api/note`, which takes one note that note.schema.json accepts. Notes go into `actions.json`, the view app's event log, and the
session's replies into `replies.json`, so this app reuses the view app's hub, token route, expiry and
apply (lib/session-bridge/README.md, "The view app"). Nothing here acts on a note: the watcher
prints it under session_bridge.DATA_NOTE and the session decides (docs/contracts/ui-feedback).
"""

import argparse
import json
import math
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
import view_bridge as view

HERE = Path(__file__).resolve().parent
NAME = "notes"
START_SECONDS = view.START_SECONDS
SCHEMA = json.loads((HERE / "note.schema.json").read_text(encoding="utf-8"))
MAX_NOTES = SCHEMA["x-maxNotesPerRun"]
PAGE = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]{0,127}\.html")
# The host page's own policy; connect-src 'self' is its fetches. A srcdoc document inherits it, so
# /api/page puts PAGE_CSP first in the framed page: every policy applies, and PAGE_CSP grants no
# network and no 'self' script, whatever the page's own markup says (SKILL.md's mockup policy).
HOST_CSP = (
    "default-src 'none'; script-src 'self' 'unsafe-inline'; style-src 'unsafe-inline'; "
    "img-src data:; font-src data:; connect-src 'self'; frame-ancestors 'none'; "
    "base-uri 'none'; form-action 'none'"
)
PAGE_CSP = (
    "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; "
    "img-src data:; font-src data:; base-uri 'none'; form-action 'none'"
)
PAGE_CSP_META = (
    f'<meta http-equiv="Content-Security-Policy" content="{PAGE_CSP}">'.encode()
)
# A leading doctype stays first, so the page keeps its rendering mode; the meta goes right after it.
DOCTYPE = re.compile(rb"\A(?:\xef\xbb\xbf)?\s*<!doctype[^>]*>", re.IGNORECASE)
# The copy-out block host.html's Copy all notes makes; import takes it, or its JSON alone.
FENCE = re.compile(r"\s*```prototype-notes[ \t]*\r?\n(.*?)\r?\n```\s*", re.DOTALL)
STATIC = {
    "/note-model.mjs": ("note-model.mjs", "text/javascript"),
    "/note.schema.json": ("note.schema.json", "application/json"),
}
KNOWN = {
    "$schema",
    "$id",
    "$ref",
    "$defs",
    "title",
    "description",
    "x-version",
    "x-maxNotesPerRun",
    "type",
    "enum",
    "properties",
    "required",
    "additionalProperties",
    "items",
    "maxItems",
    "minLength",
    "maxLength",
    "pattern",
    "minimum",
    "maximum",
}


def pin_helper(text):
    """The pin helper's text, refused when it holds `</script`, `<script` or `<!--`: inside a
    script element any of them could end it early or hide its end from the parser."""
    low = text.lower()
    if any(s in low for s in ("</script", "<script", "<!--")):
        raise RuntimeError("proto-pin.js must not contain </script, <script or <!--")
    return text


PIN_HELPER = pin_helper((HERE / "proto-pin.js").read_text(encoding="utf-8"))


def is_number(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


FITS = {
    "object": lambda v: isinstance(v, dict),
    "array": lambda v: isinstance(v, list),
    "string": lambda v: isinstance(v, str),
    "boolean": lambda v: isinstance(v, bool),
    # JSON Schema counts 1.0 as an integer; a bool is never one.
    "integer": lambda v: is_number(v) and float(v).is_integer(),
    # json.loads accepts NaN and Infinity; JSON Schema numbers are finite.
    "number": lambda v: is_number(v) and math.isfinite(v),
}


def problems(value, node=None, at="note"):
    """Why `value` does not fit `node` of note.schema.json; empty when it fits.

    The same subset note-model.mjs honors, and a keyword outside it raises. Lengths count code
    points; a pattern is anchored ^...$ and matched whole.
    """
    node = SCHEMA if node is None else node
    unknown = sorted(set(node) - KNOWN)
    if unknown:
        raise RuntimeError(f"note schema keyword {unknown[0]} is not honored")
    if "$ref" in node:
        m = re.fullmatch(r"#/\$defs/([A-Za-z0-9_-]+)", node["$ref"])
        if not m or m[1] not in SCHEMA.get("$defs", {}):
            raise RuntimeError(f"unresolvable $ref {node['$ref']}")
        return problems(value, SCHEMA["$defs"][m[1]], at)
    t = node.get("type")
    if t and not FITS[t](value):
        return [f"{at}: expected {t}"]
    if "enum" in node and not (isinstance(value, str) and value in node["enum"]):
        return [f"{at}: not one of {', '.join(node['enum'])}"]
    if isinstance(value, str):
        if len(value) < node.get("minLength", 0):
            return [f"{at}: shorter than {node['minLength']}"]
        if "maxLength" in node and len(value) > node["maxLength"]:
            return [f"{at}: longer than {node['maxLength']}"]
        p = node.get("pattern")
        if p is not None:
            if not (p.startswith("^") and p.endswith("$")):
                raise RuntimeError(f"pattern {p!r} is not anchored")
            if not re.fullmatch(p[1:-1], value):
                return [f"{at}: does not match its pattern"]
    if is_number(value):
        if "minimum" in node and value < node["minimum"]:
            return [f"{at}: below {node['minimum']}"]
        if "maximum" in node and value > node["maximum"]:
            return [f"{at}: above {node['maximum']}"]
    if isinstance(value, list):
        if "maxItems" in node and len(value) > node["maxItems"]:
            return [f"{at}: more than {node['maxItems']} items"]
        items = node.get("items")
        if not isinstance(items, dict):
            return []
        return [
            p for i, v in enumerate(value) for p in problems(v, items, f"{at}[{i}]")
        ]
    if not isinstance(value, dict):
        return []
    props = node.get("properties", {})
    out = [f"{at}.{k}: required" for k in node.get("required", []) if k not in value]
    for k, v in value.items():
        if k in props:
            out += problems(v, props[k], f"{at}.{k}")
        elif node.get("additionalProperties") is False:
            out.append(f"{at}.{k}: unknown field")
    return out


class NotesHub(view.ViewHub):
    name = NAME

    def __init__(self, port, data_dir, page="page.html", idle=view.IDLE_SECONDS):
        super().__init__(port, data_dir, idle)
        self.page = self.dir / page

    def identity(self):
        return {"app": NAME, "page": self.page.name}

    def read_state(self):
        """The host page's frame: whether the session listens, and each note's progress and reply."""
        try:
            log = self.read_log()
            handled, replies = self.read_replies()
        except (OSError, ValueError):
            return None, True
        notes = [
            {
                "seq": e["seq"],
                "delivered": bool(e.get("deliveredAt")),
                "handled": e["seq"] in handled,
                "reply": replies.get(str(e["seq"])),
            }
            for e in log.get("events", [])
        ]
        return {
            "instance": self.instance,
            "listening": self.listener()["state"],
            "notes": notes,
        }, False

    def record(self, msg):
        found = problems(msg)
        if found:
            raise ValueError(found[0])
        with self.cond:
            log = self.read_log()
            if len(log["events"]) >= MAX_NOTES:
                raise ValueError(
                    f"the page has sent {MAX_NOTES} notes; restart the server"
                )
            log["seq"] += 1
            log["events"].append({"seq": log["seq"], "at": bridge.now_iso(), **msg})
            self.write_log(log)
            self.cond.notify_all()
            return log["seq"]


class NotesHandler(view.ViewHandler):
    """The host page, its two assets, the framed page and the notes; session_bridge serves the rest."""

    hub: NotesHub

    def route_get(self, url, query):
        if url.path in ("/", "/index.html"):
            return self.send(
                200, (HERE / "host.html").read_bytes(), "text/html", HOST_CSP
            )
        if url.path in STATIC:
            file, ctype = STATIC[url.path]
            return self.send(200, (HERE / file).read_bytes(), ctype)
        if url.path == "/api/page":
            # Text for the host page's script to frame, never a document at this URL: text/plain
            # under nosniff. Same-origin script only, as for the token.
            if self.headers.get("Sec-Fetch-Site") != "same-origin":
                return self.send(403, {"error": "same-origin page script only"})
            try:
                raw = self.hub.page.read_bytes()
            except OSError:
                return self.send(
                    404, {"error": f"no {self.hub.page.name} in the data dir yet"}
                )
            m = DOCTYPE.match(raw)
            at = m.end() if m else 0
            body = raw[:at] + PAGE_CSP_META + raw[at:]
            return self.send(
                200, body + f"\n<script>{PIN_HELPER}</script>\n".encode(), "text/plain"
            )
        if url.path == "/api/token":
            return super().route_get(url, query)
        return self.send(404, {"error": "not found"})

    def route_post(self, path, msg):
        if path != "/api/note":
            return self.send(404, {"error": "not found"})
        try:
            seq = self.hub.record(msg)
        except ValueError as e:
            return self.send(400, {"error": str(e)})
        return self.send(
            200, {"ok": True, "seq": seq, "listening": self.hub.listener()["state"]}
        )


# Control half: what the skill and wake.sh run, composed from session_bridge's client half.


def cmd_status(d, a):
    log = view.load_log(d / "actions.json")
    handled = set(view.load_json(d / "replies.json", {}).get("handled", []))
    events = [
        {k: v for k, v in e.items() if k != "deliveredAt"}
        for e in log.get("events", [])
        if e["seq"] not in handled
    ]
    print(bridge.dumps_line({"note": bridge.DATA_NOTE, "events": events}))


def parse_block(text):
    """The notes in one copy-out block the host page made, or ValueError.

    The text is one ```prototype-notes fence around `{"notes": [...]}`, or that object alone.
    Every note must pass note.schema.json, or nothing is taken.
    """
    m = FENCE.fullmatch(text)
    try:
        block = json.loads(m[1] if m else text)
    except ValueError:
        raise ValueError(
            "not one prototype-notes block: paste the block Copy all notes made, unchanged"
        ) from None
    if not isinstance(block, dict) or set(block) != {"notes"}:
        raise ValueError('the block must be {"notes": [...]} and nothing else')
    notes = block["notes"]
    if not isinstance(notes, list):
        raise ValueError("notes must be a list")
    for i, note in enumerate(notes, 1):
        found = problems(note)
        if found:
            raise ValueError(f"note {i}: {found[0]}")
    return notes


def cmd_import(d, a):
    view.private_dir(d)
    s = bridge.read_session(d, NAME)
    if s and bridge.running(d, s):
        sys.exit(
            "import: the notes server is running on this dir; its page sends notes itself. "
            "Run stop, then import, then ensure-running."
        )
    f = Path(a.file)
    limit = MAX_NOTES * NotesHandler.max_body
    try:
        with f.open("rb") as fh:
            raw = fh.read(limit + 1)
    except OSError as e:
        sys.exit(f"import: cannot read {f}: {e.strerror}")
    if len(raw) > limit:
        sys.exit(f"import: {f} is over {limit} bytes")
    try:
        notes = parse_block(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as e:
        sys.exit(f"import: {e}")
    log = view.load_log(d / "actions.json")
    seen = [
        {k: v for k, v in e.items() if k not in ("seq", "at", "deliveredAt")}
        for e in log["events"]
    ]
    new = []
    for note in notes:
        if note not in seen:
            seen.append(note)
            new.append(note)
    if len(log["events"]) + len(new) > MAX_NOTES:
        sys.exit(
            f"import: the run already holds {len(log['events'])} notes and stores at most "
            f"{MAX_NOTES}; nothing imported"
        )
    seqs = []
    for note in new:
        log["seq"] += 1
        log["events"].append({"seq": log["seq"], "at": bridge.now_iso(), **note})
        seqs.append(log["seq"])
    view.write_json(d / "actions.json", log)
    f.unlink()
    print(json.dumps({"imported": seqs, "skipped": len(notes) - len(new)}))


def cmd_serve(d, a):
    httpd, hub = bridge.start(
        NotesHandler,
        lambda port: NotesHub(port, d, a.page, a.idle_seconds),
        a.port,
        a.nonce,
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


def end_server(d, s):
    """End the running server `s` records and its watcher, then clear the session files."""
    bridge.end_watcher(d, (bridge.watcher_lease(d, NAME) or {}).get("pid"))
    os.kill(s["pid"], signal.SIGTERM)
    deadline = time.monotonic() + START_SECONDS
    while time.monotonic() < deadline and bridge.ping(s["port"], timeout=0.5):
        time.sleep(0.05)
    bridge.clear_session(d, NAME)


def other_page(s, page):
    """Why the running server `s` frames another page than `page`, or None when it frames `page`."""
    served = (bridge.ping(s["port"]) or {}).get("page")
    return None if served == page else f"it frames {served}, not {page}"


def cmd_ensure_running(d, a):
    if not shutil.which("curl"):
        sys.exit("missing prerequisite: curl (the watcher needs it on PATH)")
    view.private_dir(d)
    s = bridge.read_session(d, NAME)
    live = bool(s and bridge.running(d, s))
    stale = live and (bridge.stale_build(s) or other_page(s, a.page))
    if stale:
        end_server(d, s)
        print(f"restarted the {NAME} server: {stale}", file=sys.stderr)
        live = False
    if not live:
        ports = [a.port, bridge.kept_port(d, NAME)]
        port = next((p for p in ports if p and bridge.port_free(p)), 0)
        nonce = secrets.token_hex(8)
        cmd = [bridge.interpreter(), str(HERE / "notes_bridge.py"), "--dir", str(d)]
        cmd += ["serve", "--port", str(port), "--nonce", nonce, "--page", a.page]
        cmd += ["--idle-seconds", str(a.idle_seconds)]
        with bridge.open_server_log(d, NAME) as log:
            proc = bridge.spawn(cmd, stderr=log)
        s = bridge.wait_started(d, NAME, nonce, proc, START_SECONDS)
        if s is None:
            code = proc.poll()
            if code is None:
                proc.kill()
                why = f"the server did not start within {START_SECONDS} s"
            else:
                why = f"the server exited with status {code}"
            tail = bridge.log_tail(bridge.server_log(d, NAME))
            sys.exit(
                f"{why} (data dir {d})"
                + (f"\nserver stderr (last lines):\n{tail}" if tail else "")
            )
    origin = f"http://127.0.0.1:{int(s['port'])}"
    print(
        json.dumps(
            {
                "url": origin + "/",
                "origin": origin,
                "page": str(d / a.page),
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
    end_server(d, s)
    print(f"stopped {s['pid']}")


def cmd_lease(d, a):
    s = bridge.read_session(d, NAME)
    if not (s and bridge.running(d, s)):
        sys.exit("not running")
    if a.release and bridge.release_lease(s, NAME) != 200:
        sys.exit("release refused")
    lease = bridge.watcher_lease(d, NAME)
    print(f"lease held by {lease['watcher']}" if lease else "no lease")


def page_name(value):
    if not PAGE.fullmatch(value):
        raise argparse.ArgumentTypeError("a file name in the data dir ending .html")
    return value


def main(argv=None):
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--dir", required=True, help="the data dir, holding the page")
    sub = p.add_subparsers(dest="cmd", required=True)
    for name in ("ensure-running", "serve"):
        s = sub.add_parser(name)
        s.add_argument(
            "--port", type=int, default=None if name == "ensure-running" else 0
        )
        s.add_argument("--page", type=page_name, default="page.html")
        s.add_argument("--idle-seconds", type=float, default=view.IDLE_SECONDS)
        if name == "serve":
            s.add_argument("--nonce", default="")
    for name in ("apply", "import"):
        s = sub.add_parser(name)
        s.add_argument("--file", required=True)
    sub.add_parser("stop")
    s = sub.add_parser("lease")
    s.add_argument("--release", action="store_true")
    sub.add_parser("status")
    a = p.parse_args(argv)
    d = Path(a.dir).resolve()
    {
        "ensure-running": cmd_ensure_running,
        "serve": cmd_serve,
        "apply": view.cmd_apply,
        "import": cmd_import,
        "stop": cmd_stop,
        "lease": cmd_lease,
        "status": cmd_status,
    }[a.cmd](d, a)


if __name__ == "__main__":
    main()

"""The shared interview session's control script: what `share.sh` runs. Python 3 stdlib.

  share.py --dir DATA_DIR ensure-running [--open] [--defaults-file F] [--guest-port N]
                                         [--import STATE] [--adopt-tunnel PID URL]
  share.py --dir DATA_DIR stop [--keep-tunnel]
  share.py --dir DATA_DIR restart
  share.py --dir DATA_DIR status
  share.py --dir DATA_DIR url [--owner]
  share.py --dir DATA_DIR apply --file F
  share.py --dir DATA_DIR lease [--release]
  share.py --dir DATA_DIR logs [--errors] [--since MINUTES] [--summary [--json]]
  share.py list --root MEMORY_DIR

Each command prints one JSON line on stdout (`logs --summary` plain text, unless --json) and diagnostics on stderr. Exit codes: 0 done;
1 refused (bad arguments, a newer schema, a failed migration); 2 a prerequisite is missing or the
server cannot start or be reached; 3 no tunnel address in time (the server keeps running on
localUrl and the output says `tunnel: "down"`). User text never goes on a command line: it
reaches the session through `apply`. The owner link is a credential: only `url --owner` prints it.
On Windows `python share.py ...` runs without bash.
"""

from __future__ import annotations

import argparse
import collections
import contextlib
import datetime
import html
import http.client
import json
import math
import os
import re
import secrets
import shlex
import shutil
import subprocess
import sys
import time
import webbrowser
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import detached  # noqa: E402  (beside this file; sys.path is set just above)
import session_bridge as bridge  # noqa: E402
import tunnel  # noqa: E402

NAME = "shared"  # matches server.py and session-bridge.conf
SECRETS = ".shared-secrets.json"
PORTS = ".shared-ports.json"
OWNER_LINK = ".owner-link"
REPORTED = ".shared-reported"  # the guest link the last ensure-running printed
SERVER_ERR = ".shared-server.err"
LOCK = ".shared.lock"
OPS_MAX = 1024 * 1024
START_SECONDS = 15.0
SYNC_SECONDS = 5.0  # how long the server may take to pick up a new tunnel record
SERVER_MARKER = "python" if detached.WINDOWS else "server.py"
OPEN_PAGE = ".owner-open-{}.html"  # the page --open hands the browser; it holds the owner link
OPEN_SECONDS = 30.0  # judgment: a browser started cold has read the page well within this
LOG = "server.log"
LOG_TAIL = 200  # judgment: the most lines `logs` prints, the newest
FORGET_PAGE = "import contextlib, os, sys, time\ntime.sleep(float(sys.argv[2]))\nwith contextlib.suppress(OSError):\n    os.unlink(sys.argv[1])\n"


class Refused(Exception):
    def __init__(self, code, message, payload=None):
        super().__init__(message)
        self.code, self.message, self.payload = code, message, payload


def _digits(v):
    """Whether v is ASCII digits only: str.isdigit also takes "²", which int() refuses."""
    return v.isascii() and v.isdigit()


def emit(obj):
    """One JSON line; U+2028 and U+2029 escaped, since a reader splitting with str.splitlines() ends a line there."""
    print(json.dumps(obj, ensure_ascii=False).replace("\u2028", "\\u2028").replace("\u2029", "\\u2029"), flush=True)


def read_json(path):
    try:
        doc = json.loads(Path(path).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return doc if isinstance(doc, dict) else None


def live(d):
    """The running server's session record, or None."""
    s = bridge.read_session(d, NAME)
    return s if s and bridge.running(d, s) else None


def call(s, method, path, body=None, timeout=30):
    """One request to the control listener with the token; (status, parsed body)."""
    conn = http.client.HTTPConnection("127.0.0.1", int(s["port"]), timeout=timeout)
    try:
        headers = {bridge.token_header(NAME): s["token"]}
        raw = None
        if body is not None:
            raw = body if isinstance(body, bytes) else json.dumps(body).encode("utf-8")
            headers["Content-Type"] = "application/json"
        conn.request(method, path, body=raw, headers=headers)
        resp = conn.getresponse()
        data = resp.read()
        try:
            return resp.status, json.loads(data)
        except ValueError:
            return resp.status, {"error": data.decode("utf-8", "replace")[:200]}
    except OSError as exc:
        raise Refused(2, f"the server did not answer: {exc}") from exc
    finally:
        conn.close()


def status_of(s):
    code, body = call(s, "GET", "/api/status")
    if code != 200:
        raise Refused(2, f"status refused: HTTP {code} {body.get('error', '')}")
    return body


def guest_url(public, key):
    if not public:
        return ""
    return public.rstrip("/") + "/" + (f"#join={key}" if key else "")


def local_url(port):
    return f"http://127.0.0.1:{port}/"


def watch_command(d):
    return f"bash {shlex.quote(str(HERE / 'watch.sh'))} {shlex.quote(str(d))}"


def start_server(d, guest, control, *, defaults_file=None, initial_state=None):
    """Start server.py detached on the given ports (0 picks one) and wait for its ping."""
    nonce = secrets.token_hex(8)
    cmd = detached.python(str(HERE / "server.py"), "--dir", str(d), "--guest-port", str(guest), "--control-port", str(control), "--nonce", nonce)
    if defaults_file:
        cmd += ["--defaults-file", str(Path(defaults_file).resolve())]
    if initial_state:
        cmd += ["--initial-state", str(Path(initial_state).resolve())]
    proc = detached.spawn(cmd, log=d / SERVER_ERR, cwd=d)
    s = bridge.wait_started(d, NAME, nonce, proc, START_SECONDS)
    if s is not None:
        detached.release(proc)
        return s
    if proc.poll() is None:
        proc.kill()
        proc.wait()
        raise Refused(2, f"the server did not start within {START_SECONDS:.0f} s (data dir {d})")
    try:
        why = (d / SERVER_ERR).read_text(encoding="utf-8", errors="replace").strip().splitlines()[-1]
    except (OSError, IndexError):
        why = f"exit {proc.returncode}"
    raise Refused(1 if proc.returncode == 1 else 2, f"the server did not start: {why}")


def stop_server(d, s):
    """End the server process s names (only when its ping still matches); True when it stopped."""
    if not bridge.running(d, s):
        return False
    detached.stop(int(s["pid"]), SERVER_MARKER)
    deadline = time.monotonic() + START_SECONDS
    while time.monotonic() < deadline and bridge.ping(s["port"], timeout=0.5):
        time.sleep(0.05)
    return True


def wait_public(s, want, seconds=SYNC_SECONDS):
    """Until the server allows the tunnel address `want`; the last ping."""
    deadline = time.monotonic() + seconds
    p = bridge.ping(s["port"]) or {}
    while p.get("publicUrl") != want and time.monotonic() < deadline:
        time.sleep(0.1)
        p = bridge.ping(s["port"]) or {}
    return p


def open_link(d, url):
    """Open the owner's link in the default browser without putting it on a command line: the
    browser gets a 0600 page in the data folder that redirects to `url`, and a detached helper
    deletes the page after OPEN_SECONDS. SHARED_BROWSER names another opener (tests stub it)."""
    now = time.time()
    for old in d.glob(OPEN_PAGE.format("*")):
        with contextlib.suppress(OSError):
            if now - old.stat().st_mtime > OPEN_SECONDS:
                old.unlink()
    page = d / OPEN_PAGE.format(secrets.token_hex(8))
    script = json.dumps(url).replace("<", "\\u003c")
    detached.write_private(
        page,
        '<!doctype html>\n<meta charset="utf-8">\n<meta name="referrer" content="no-referrer">\n<title>Opening the shared session</title>\n'
        f'<script>location.replace({script})</script>\n<meta http-equiv="refresh" content="0;url={html.escape(url, quote=True)}">\n',
    )
    seconds = os.environ.get("SHARED_OPEN_SECONDS") or str(OPEN_SECONDS)
    detached.release(detached.spawn(detached.python("-c", FORGET_PAGE, str(page), seconds), cwd=d))
    opener = os.environ.get("SHARED_BROWSER")
    if opener:
        return subprocess.run([opener, page.as_uri()], check=False, timeout=30, stdout=subprocess.DEVNULL).returncode == 0
    return webbrowser.open(page.as_uri())


def report(d, s, rec, resumed, *, opened=None):
    """The ensure-running and restart answer."""
    st = status_of(s)
    url = guest_url(rec["url"] if rec else "", st.get("guestKey"))
    before = (d / REPORTED).read_text(encoding="utf-8").strip() if (d / REPORTED).exists() else ""
    if url:
        detached.write_private(d / REPORTED, url + "\n")
    out = {
        "ok": True,
        "guestUrl": url,
        "localUrl": local_url(st["guestPort"]),
        "ownerLinkFile": str(d / OWNER_LINK),
        "shareChanged": bool(before and url and before != url),
        "resumed": resumed,
        "tunnel": "quick" if rec else "down",
        "watch": watch_command(d),
    }
    if opened is not None:
        out["opened"] = opened
    return out


def creation(d, a, resumed):
    """(import file, guest port, (pid, url) to adopt) from the command line, else from defaults.json,
    whose keys apply only when the session is created. Refuses what cannot apply (exit 1)."""
    if resumed:
        if a.import_file:
            raise Refused(1, f"a session already exists in {d}: --import only creates one")
        if a.adopt_tunnel:
            raise Refused(1, "--adopt-tunnel applies only when a session is created")
        return None, a.guest_port, None
    src = Path(a.defaults_file) if a.defaults_file else d / "defaults.json"
    defaults = (read_json(src) or {}) if src.exists() else {}
    imp = a.import_file or defaults.get("import")
    port = a.guest_port if a.guest_port is not None else defaults.get("guestPort")
    adopt = a.adopt_tunnel or ([defaults["adoptTunnel"].get("pid"), defaults["adoptTunnel"].get("url")] if isinstance(defaults.get("adoptTunnel"), dict) else None)
    if imp is not None and (not isinstance(imp, str) or not Path(imp).is_file()):
        raise Refused(1, f"--import: no such file: {imp}")
    if port is not None and (isinstance(port, bool) or not isinstance(port, int) or not 0 < port < 65536):
        raise Refused(1, f"the guest port must be a port number, got {port!r}")
    if adopt is None:
        return imp, port, None
    try:
        pid, url = int(adopt[0]), str(adopt[1]).rstrip("/")
    except (TypeError, ValueError) as exc:
        raise Refused(1, f"--adopt-tunnel takes a process id and a URL, got {adopt!r}") from exc
    if port is None:
        raise Refused(1, "--adopt-tunnel needs --guest-port, the port that cloudflared points at")
    if not tunnel.URL.fullmatch(url):
        raise Refused(1, f"--adopt-tunnel: {url} is not a trycloudflare.com address")
    why = tunnel.adoptable(pid, port)
    if why:
        raise Refused(1, f"--adopt-tunnel: {why}")
    return imp, port, (pid, url)


def bring_up(d, a):
    """ensure-running: start or reuse the server and the tunnel."""
    problem = detached.data_dir_problem(d)
    if problem:
        raise Refused(1, f"refused: {problem}")
    if not shutil.which("curl"):
        raise Refused(2, "missing prerequisite: curl (watch.sh needs it on PATH)")
    if not tunnel.binary():
        raise Refused(2, tunnel.MISSING)
    d.mkdir(parents=True, exist_ok=True)
    with detached.locked(d / LOCK):
        resumed = (d / "state.json").exists()
        initial_state, wanted, adopt = creation(d, a, resumed)
        ports = read_json(d / PORTS) or {}
        if wanted is not None and resumed and ports.get("guest") not in (None, wanted):
            raise Refused(1, f"this session's guest port is {ports['guest']}; --guest-port applies only when a session is created")
        s = live(d)
        if s is None:
            if wanted is not None and not bridge.port_free(wanted):
                raise Refused(2, f"port {wanted} is busy: the guest listener cannot start there")
            guest = wanted if wanted is not None else ports.get("guest") or 0
            if wanted is None and guest and not bridge.port_free(guest):
                print(f"port {guest} is busy: the guest link moves to a new port", file=sys.stderr)
                guest = 0
            control = ports.get("control") or bridge.kept_port(d, NAME) or 0
            if control and not bridge.port_free(control):
                control = 0
            if adopt:
                try:
                    tunnel.adopt(d, adopt[0], adopt[1], guest)
                except tunnel.TunnelDown as exc:
                    raise Refused(1, f"--adopt-tunnel: {exc}") from exc
            try:
                s = start_server(d, guest, control, defaults_file=a.defaults_file, initial_state=initial_state)
            except BaseException:
                if adopt:  # forget the adopted tunnel, never stop it: it still serves whoever ran it
                    (d / tunnel.RECORD).unlink(missing_ok=True)
                raise
        port = (bridge.ping(s["port"]) or {}).get("guestPort")
        if type(port) is not int:  # a tunnel to no port would replace one that works
            raise Refused(2, "the server did not name its guest port; run ensure-running again")
        rec, down = None, None
        try:
            rec = tunnel.ensure(d, port)
        except (tunnel.TunnelDown, TimeoutError) as exc:
            down = str(exc)
        if rec:
            wait_public(s, rec["url"])
        bridge.set_wait_timeout(d, NAME, bridge.WAIT_DEFAULT)
        opened = None
        if a.open:
            link = (d / OWNER_LINK).read_text(encoding="utf-8").strip()
            opened = open_link(d, link)
        out = report(d, s, rec, resumed, opened=opened)
    if down:
        raise Refused(3, f"no tunnel: {down}", out)
    return out


def cmd_ensure_running(d, a):
    return bring_up(d, a)


def cmd_stop(d, a):
    stopped = []
    with detached.locked(d / LOCK):
        s = bridge.read_session(d, NAME)
        if s and bridge.running(d, s):
            watcher = (bridge.watcher_lease(d, NAME) or {}).get("pid")
            if watcher:
                bridge.end_watcher(d, watcher)
                stopped.append("watcher")
            if stop_server(d, s):
                stopped.append("server")
        bridge.clear_session(d, NAME)
        keep = read_json(d / SECRETS) or {}
        if "control" in keep:  # a stopped session's next start gets a new control token
            keep.pop("control")
            detached.write_private(d / SECRETS, json.dumps(keep) + "\n")
        adopted = (tunnel.read(d) or {}).get("adopted") and tunnel.alive(d)
        if not a.keep_tunnel and tunnel.stop(d):
            stopped.append("tunnel")
        if adopted and not a.keep_tunnel:
            print(f"the adopted cloudflared (pid {adopted['pid']}) keeps running; end that process yourself to close its link", file=sys.stderr)
    return {"ok": True, "stopped": stopped}


def cmd_restart(d, a):
    """Restart the server only, on its ports, keeping the tunnel, the state and the control token."""
    with detached.locked(d / LOCK):
        s = live(d)
        if s is None:
            raise Refused(1, "not running: run ensure-running")
        ports = read_json(d / PORTS) or {}
        stop_server(d, s)
        s = start_server(d, ports.get("guest", 0), ports.get("control", s["port"]))
        rec = tunnel.alive(d)
        if rec:
            wait_public(s, rec["url"])
        out = report(d, s, rec, True)
    out["restarted"] = True
    return out


def cmd_status(d, a):
    s = live(d)
    rec = tunnel.alive(d)
    if s is None:
        doc = read_json(d / "state.json") or {}
        rounds = doc.get("rounds") or []
        last = rounds[-1] if rounds else None
        return {
            "ok": True,
            "running": False,
            "tunnel": "quick" if rec else ("down" if tunnel.read(d) else "off"),
            "guestUrl": guest_url(rec["url"] if rec else "", (doc.get("session") or {}).get("guestKey")),
            "round": {"n": last["n"], "status": last["status"]["kind"]} if last else None,
            "intro": bool((doc.get("session") or {}).get("intro")),
            "people": None,
            "queue": None,
            "unhandled": None,
            "lease": None,
        }
    st = status_of(s)
    return {
        "ok": True,
        "running": True,
        "tunnel": st["tunnel"],
        "guestUrl": guest_url(st["publicUrl"], st["guestKey"]),
        "round": st["round"],
        "intro": st["intro"],
        "people": st["people"],
        "queue": st["queue"],
        "unhandled": st["unhandled"],
        "lease": st["lease"],
    }


def cmd_url(d, a):
    if a.owner:
        try:
            return {"ownerUrl": (d / OWNER_LINK).read_text(encoding="utf-8").strip()}
        except OSError as exc:
            raise Refused(1, "no owner link yet: run ensure-running") from exc
    return {"guestUrl": cmd_status(d, a)["guestUrl"]}


def cmd_list(root, a):
    out = []
    for state in sorted(Path(root).rglob("state.json")):
        if state.parent.parent.name != "shared":
            continue
        d = state.parent
        doc = read_json(state) or {}
        s = live(d)
        rounds = doc.get("rounds") or []
        url = ""
        if s:
            try:
                st = status_of(s)
                url = guest_url(st["publicUrl"], st["guestKey"])
            except Refused:
                pass
        out.append(
            {
                "dir": str(d),
                "title": (doc.get("session") or {}).get("title", ""),
                "running": s is not None,
                "guestUrl": url,
                "round": rounds[-1]["n"] if rounds else None,
                "ended": ((doc.get("session") or {}).get("phase") or {}).get("kind") == "ended",
            }
        )
    return {"sessions": out}


def cmd_apply(d, a):
    f = Path(a.file)
    if not f.exists():
        return {"ok": True, "results": [], "applied": False}
    s = live(d)
    if s is None:
        raise Refused(2, "not running: run ensure-running, then apply again")
    raw = f.read_bytes()
    if len(raw) > OPS_MAX:
        raise Refused(1, f"{f} is over {OPS_MAX} bytes")
    try:
        doc = json.loads(raw)
    except ValueError as exc:
        raise Refused(1, f"{f} is not JSON: {exc}") from exc
    code, body = call(s, "POST", "/api/ops", json.dumps(doc).encode("utf-8"), timeout=60)
    if code != 200:
        raise Refused(1, f"apply refused: {body.get('error')}: {body.get('message', '')}", {"ok": False, **body})
    f.unlink(missing_ok=True)
    return {"ok": True, "results": body.get("results", [])}


def cmd_lease(d, a):
    s = live(d)
    if s is None:
        raise Refused(2, "not running")
    if a.release:
        code = bridge.release_lease(s, NAME)
        if code != 200:
            raise Refused(1, f"release refused: HTTP {code}")
    return {"lease": bridge.watcher_lease(d, NAME)}


def is_error(line):
    """A request entry with a 4xx or 5xx status, or a client entry, a fault (README "Logs"). The fields before any
    free text never hold a space, so they split on spaces."""
    parts = line.split(" ", 7)
    if len(parts) > 3 and parts[3] == "client":
        return True
    return len(parts) > 6 and parts[3] == "request" and parts[6][:8] in {"status=4", "status=5"}


def logged_at(line):
    try:
        return datetime.datetime.strptime(line[:19], "%Y-%m-%d %H:%M:%S")
    except ValueError:
        return None


def cmd_logs(d, a):
    """The newest LOG_TAIL lines of server.log and its rotated files, oldest first, or with --summary what they add up
    to (summarize); it needs no running server."""
    rotated = sorted((f for f in d.glob(LOG + ".*") if _digits(f.suffix[1:])), key=lambda f: int(f.suffix[1:]), reverse=True)
    lines = []
    for f in [*rotated, d / LOG]:
        with contextlib.suppress(OSError):
            lines += [line for line in f.read_text(encoding="utf-8", errors="replace").split("\n") if line]  # not splitlines(): only a newline ends an entry
    if a.since is not None:
        cut = datetime.datetime.now() - datetime.timedelta(minutes=a.since)
        lines = [line for line in lines if (logged_at(line) or cut) >= cut]
    if a.summary:
        out = summarize(lines)
        return {"ok": True, **out} if a.json else summary_text(out)
    if a.errors:
        lines = [line for line in lines if is_error(line)]
    return {"ok": True, "lines": lines[-LOG_TAIL:]}


# ---------- logs --summary: what the pages' telemetry adds up to (README "Logs") ----------
FIELD = re.compile(r' (\w+)=(?:"([^"]*)"|(\S*))')
ESCAPE = re.compile(r"\\x([0-9a-f]{2})|\\u([0-9a-f]{4})")
LAT_EDGES = (100, 200, 300, 500, 750, 1000, 1500, 2000, 3000, 5000, 10000)  # ms; web/core.js LAT_EDGES, plus one bucket above the last
SLOW_GAP = 10000  # ms: a reconnect gap the summary counts as slow
TOP = 10  # judgment: the most error fingerprints the summary lists


def entry_of(line):
    """A log line's entry kind and its fields, unescaped; (None, {}) for a line that is not an entry."""
    parts = line.split(" ", 4)
    if len(parts) < 4:
        return None, {}
    unescape = lambda v: ESCAPE.sub(lambda m: chr(int(m[1] or m[2], 16)), v)  # noqa: E731
    return parts[3], {m[1]: unescape(m[2] if m[2] is not None else m[3]) for m in FIELD.finditer(" " + (parts[4] if len(parts) > 4 else ""))}


def tokens(message):
    """A summary or layout message's `name=value` tokens."""
    return dict(t.split("=", 1) for t in message.split(" ") if "=" in t)


def rank(values, q):
    """The nearest-rank q-quantile of `values`."""
    s = sorted(values)
    return s[max(0, math.ceil(q * len(s)) - 1)] if s else None


def bucket_rank(counts, q):
    """The upper edge in ms of the latency bucket holding the q-quantile; None for the bucket above the last edge."""
    need, seen = math.ceil(q * sum(counts)), 0
    for edge, n in zip((*LAT_EDGES, None), counts):
        seen += n
        if seen >= need:
            return edge
    return None


def device(ua):
    """The device class of a page's `ua` ("<browser> <device>", web/core.js ua())."""
    return (ua or "").split(" ")[-1] or "unknown"


def browser(ua):
    """The browser class of a page's `ua`."""
    words = (ua or "").split(" ")
    return words[0] if len(words) > 1 and words[0] else "unknown"


def summarize(lines):
    """Counts from server.log lines: error fingerprints, refusals, network failures and unanswered actions, action
    latency and rollbacks, reconnect gaps, layout anomalies, INP and LCP, and how many summaries there were (from the
    summary-batch entries). The owner's own pages are left out of the timings, which a page on the owner's machine
    would skew."""
    faults, refusals, server_ms, repeats, repeat_at = {}, collections.Counter(), collections.defaultdict(list), collections.Counter(), {}
    lat, rollbacks, gaps, vitals = collections.defaultdict(lambda: [0] * (len(LAT_EDGES) + 1)), collections.Counter(), [], {}
    sm = {"count": 0, "batches": 0, "pages": 0, "ownerPages": 0, "dropped": 0}
    pages = set()

    def fold(message, ua, at):
        """One summary from a batch written at `at`."""
        t = tokens(message)
        sm["count"] += 1
        pv = t.get("pv") or f"summary{sm['count']}"
        pages.add(pv)
        for k, v in t.items():
            if k.startswith("rep:") and _digits(v):
                repeats[k[4:]] += int(v)
                repeat_at[k[4:]] = max(repeat_at.get(k[4:], ""), at)
        if t.get("owner") == "1":
            sm["ownerPages"] += pv not in vitals
            vitals.setdefault(pv, {"owner": True})
            return
        v = vitals.setdefault(pv, {"device": device(ua)})
        for k, val in t.items():
            if k.startswith("lat:"):
                for i, n in enumerate(val.split(",")[: len(LAT_EDGES) + 1]):
                    lat[k[4:]][i] += int(n) if _digits(n) else 0
            elif k.startswith("rb:") and _digits(val):
                rollbacks[k[3:]] += int(val)
            elif k == "gap":
                gaps.extend((int(g), v["device"]) for g in val.split(",") if _digits(g))
            elif k in ("inp", "lcp", "vitals"):
                v[k] = val

    for line in lines:
        kind, f = entry_of(line)
        if kind == "request":
            status = int(f.get("status", "0") or 0)
            if 400 <= status < 500 and f.get("code"):
                refusals[(f.get("route"), f["code"])] += 1
            if f.get("method") == "POST" and f.get("pid") not in (None, "host") and status < 500:
                server_ms[f.get("route")].append(float(f.get("ms") or 0))
        elif kind == "summary-batch":
            try:
                items = json.loads(line.split(" data=", 1)[1])
            except (IndexError, ValueError):
                continue  # cut short: not a batch this can read
            sm["batches"] += 1
            sm["dropped"] += int(f.get("dropped", "0")) if _digits(f.get("dropped", "")) else 0
            for item in items if isinstance(items, list) else []:
                if isinstance(item, list) and len(item) == 2 and all(isinstance(x, str) for x in item):
                    fold(*item, line[:19])
        elif kind == "client" and f.get("kind") in ("error", "rejection", "api", "layout"):
            if f["kind"] == "layout" and not f.get("message", "").startswith("anomaly="):
                continue  # a keyboard readout, not an anomaly
            fp = f.get("fp") or "|".join((f["kind"], f.get("message", ""), f.get("source", ""), f.get("route", "") if f["kind"] == "api" else ""))
            g = faults.setdefault(fp, {"fp": f.get("fp", ""), "kind": f["kind"], "message": f.get("message", ""), "source": f.get("source", ""), "route": f.get("route", ""), "code": f.get("code", ""),
                                       "count": 0, "firstSeen": line[:19], "lastSeen": line[:19], "devices": collections.Counter(), "browsers": collections.Counter()})
            g["count"] += 1
            g["firstSeen"], g["lastSeen"] = min(g["firstSeen"], line[:19]), max(g["lastSeen"], line[:19])
            g["devices"][device(f.get("ua"))] += 1
            g["browsers"][browser(f.get("ua"))] += 1
    for g in faults.values():
        g["count"] += repeats.pop(g["fp"], 0) if g["fp"] else 0
        g["lastSeen"] = max(g["lastSeen"], repeat_at.get(g["fp"], "")) if g["fp"] else g["lastSeen"]
        g["devices"], g["browsers"] = dict(g["devices"]), dict(g["browsers"])
    group = lambda kinds: sorted((g for g in faults.values() if g["kind"] in kinds), key=lambda g: -g["count"])  # noqa: E731
    routes = {}
    for route, counts in sorted(lat.items()):
        n = sum(counts)
        ms = server_ms.get(route, [])
        routes[route] = {"actions": n, "p50Ms": bucket_rank(counts, 0.5), "p95Ms": bucket_rank(counts, 0.95), "rollbacks": rollbacks[route],
                         "rollbackRate": round(rollbacks[route] / n, 4) if n else None, "serverP50Ms": rank(ms, 0.5), "serverP95Ms": rank(ms, 0.95)}
    acts = sum(r["actions"] for r in routes.values())
    timed = [v for v in vitals.values() if not v.get("owner")]

    def vital(name):
        vals = [(int(v[name].split(":")[0]), v["device"]) for v in timed if _digits(v.get(name, "").split(":")[0])]
        by = {dev: rank([x for x, d in vals if d == dev], 0.75) for dev in sorted({d for _, d in vals})}
        return {"p75Ms": rank([x for x, _ in vals], 0.75), "pages": len(vals), "byDevice": by, "missing": sum(1 for v in timed if v.get(name) == "missing" or v.get("vitals") == "missing")}

    anomalies = collections.Counter()
    for g in group(("layout",)):
        t = tokens(g["message"])
        for dev, n in g["devices"].items():
            anomalies[(t.get("anomaly", ""), t.get("at", ""), dev)] += n
        if g["count"] > sum(g["devices"].values()):  # repeats: on the device of the first entry
            anomalies[(t.get("anomaly", ""), t.get("at", ""), next(iter(g["devices"])))] += g["count"] - sum(g["devices"].values())
    return {
        "errors": [{k: g[k] for k in ("fp", "kind", "message", "source", "count", "firstSeen", "lastSeen", "devices", "browsers")} for g in group(("error", "rejection"))][:TOP],
        "refusals": [{"route": r, "code": c, "count": n} for (r, c), n in refusals.most_common()],
        "network": [{"route": g["route"], "code": g["code"], "count": g["count"]} for g in group(("api",))],
        "latency": routes,
        "rollbacks": {"count": sum(rollbacks.values()), "actions": acts, "rate": round(sum(rollbacks.values()) / acts, 4) if acts else None},
        "reconnect": {"count": len(gaps), "over10s": sum(1 for g, _ in gaps if g > SLOW_GAP), "worstMs": max((g for g, _ in gaps), default=None),
                      "byDevice": dict(collections.Counter(d for _, d in gaps))},
        "layout": [{"anomaly": a, "at": at, "device": dev, "count": n} for (a, at, dev), n in anomalies.most_common()],
        "inp": vital("inp"),
        "lcp": vital("lcp"),
        "summaries": {**sm, "pages": len(pages)},
        "repeatsUnmatched": sum(repeats.values()),
    }


def summary_text(s):
    """summarize's counts as plain text, for a person to read."""
    ms = lambda v: "over 10 s" if v is None else f"{v} ms"  # noqa: E731
    pct = lambda r: "-" if r is None else f"{r * 100:.1f}%"  # noqa: E731
    devs = lambda d: ", ".join(f"{k} {n}" for k, n in sorted(d.items()))  # noqa: E731
    sm = s["summaries"]
    out = [f"Summaries: {sm['count']} in {sm['batches']} batches from {sm['pages']} page views ({sm['ownerPages']} of them the owner's, left out of the timings)."
           + (f" {sm['dropped']} more did not fit in their batch." if sm["dropped"] else ""), "", "Top errors:"]
    out += [f"  {g['count']}x {g['kind']}: {g['message'][:120]} {g['source']} ({devs(g['devices'])}; {devs(g['browsers'])}), first {g['firstSeen']}, last {g['lastSeen']}"
            for g in s["errors"]] or ["  none"]
    out += ["", "Refusals by route and code (the server's own entries):"]
    out += [f"  {r['route']} {r['code']}: {r['count']}" for r in s["refusals"]] or ["  none"]
    out += ["", "Network failures and unanswered actions:"]
    out += [f"  {r['route']} {r['code']}: {r['count']}" for r in s["network"]] or ["  none"]
    out += ["", "Action latency, tap to answer (p50 and p95 as the upper edge of their bucket), with the server's own time:"]
    out += [f"  {route}: {r['actions']} actions, p50 up to {ms(r['p50Ms'])}, p95 up to {ms(r['p95Ms'])}; server p50 {r['serverP50Ms']} ms, p95 {r['serverP95Ms']} ms; "
            f"rollbacks {r['rollbacks']} ({pct(r['rollbackRate'])})" for route, r in s["latency"].items()] or ["  none"]
    rb = s["rollbacks"]
    out += [f"  Rollback rate: {rb['count']} of {rb['actions']} actions ({pct(rb['rate'])})", ""]
    rc = s["reconnect"]
    out += [f"Reconnect gaps after the page shows again: {rc['count']}, {rc['over10s']} over 10 s, worst {'-' if rc['worstMs'] is None else ms(rc['worstMs'])} ({devs(rc['byDevice'])})", "", "Layout anomalies by device:"]
    out += [f"  {a['anomaly']} at {a['at']}, {a['device']}: {a['count']}" for a in s["layout"]] or ["  none"]
    out.append("")
    for name in ("inp", "lcp"):
        v = s[name]
        p75 = "-" if v["p75Ms"] is None else f"{v['p75Ms']} ms"
        out.append(f"{name.upper()} p75: {p75} over {v['pages']} page views ({devs(v['byDevice'])}); API missing on {v['missing']}")
    if s["repeatsUnmatched"]:
        out.append(f"Repeats whose first entry is no longer in the log: {s['repeatsUnmatched']}")
    return "\n".join(out)


class Parser(argparse.ArgumentParser):
    def error(self, message):  # bad arguments are a refusal: exit 1, not argparse's 2
        self.print_usage(sys.stderr)
        self.exit(1, f"{self.prog}: error: {message}\n")


def parser():
    p = Parser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--dir", help="the session's data dir (every command but list)")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("ensure-running")
    s.add_argument("--open", action="store_true", help="open the owner's link in the default browser")
    s.add_argument("--defaults-file", help="settings for a new session: {\"settings\": {...}}")
    s.add_argument("--guest-port", type=int, help="the guest listener's port, chosen when the session is created")
    s.add_argument("--import", dest="import_file", metavar="STATE", help="create the session from a prototype state file")
    s.add_argument("--adopt-tunnel", nargs=2, metavar=("PID", "URL"), help="record a running cloudflared to the guest port as the tunnel")
    s.set_defaults(fn=cmd_ensure_running)
    s = sub.add_parser("stop")
    s.add_argument("--keep-tunnel", action="store_true", help="keep the tunnel and the guest link")
    s.set_defaults(fn=cmd_stop)
    sub.add_parser("restart").set_defaults(fn=cmd_restart)
    sub.add_parser("status").set_defaults(fn=cmd_status)
    s = sub.add_parser("url")
    s.add_argument("--owner", action="store_true", help="print the owner's link (a credential)")
    s.set_defaults(fn=cmd_url)
    s = sub.add_parser("list")
    s.add_argument("--root", required=True, help="the memory dir to search")
    s.set_defaults(fn=cmd_list)
    s = sub.add_parser("apply")
    s.add_argument("--file", required=True, help="ops JSON; deleted once it applies")
    s.set_defaults(fn=cmd_apply)
    s = sub.add_parser("lease")
    s.add_argument("--release", action="store_true")
    s.set_defaults(fn=cmd_lease)
    s = sub.add_parser("logs")
    s.add_argument("--errors", action="store_true", help="only refusals (4xx), server errors (5xx) and the pages' error reports")
    s.add_argument("--since", type=float, metavar="MINUTES", help="only the last MINUTES minutes")
    s.add_argument("--summary", action="store_true", help="what the pages' telemetry adds up to, as plain text")
    s.add_argument("--json", action="store_true", help="with --summary: the counts as one JSON line")
    s.set_defaults(fn=cmd_logs)
    return p


def main(argv=None):
    p = parser()
    a = p.parse_args(argv)
    if a.cmd == "list":
        target = Path(a.root)
    elif not a.dir:
        p.print_usage(sys.stderr)
        print("share.py: --dir is required", file=sys.stderr)
        return 1
    else:
        target = Path(a.dir).resolve()
    if a.cmd != "ensure-running" and a.cmd != "list" and not target.is_dir():
        print(f"no such data dir: {target}", file=sys.stderr)
        return 1
    try:
        out = a.fn(target, a)
        if isinstance(out, str):
            print(out, flush=True)
        else:
            emit(out)
    except Refused as exc:
        if exc.payload is not None:
            emit(exc.payload)
        print(exc.message, file=sys.stderr)
        return exc.code
    except TimeoutError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""The shared interview session's control script: what `share.sh` runs. Python 3 stdlib.

  share.py --dir DATA_DIR ensure-running [--open] [--defaults-file F] [--guest-port N]
                                         [--import STATE] [--adopt-tunnel PID URL]
  share.py --dir DATA_DIR stop [--keep-tunnel]
  share.py --dir DATA_DIR restart
  share.py --dir DATA_DIR status
  share.py --dir DATA_DIR url [--owner]
  share.py --dir DATA_DIR apply --file F
  share.py --dir DATA_DIR lease [--release]
  share.py list --root MEMORY_DIR

Each command prints one JSON line on stdout and diagnostics on stderr. Exit codes: 0 done;
1 refused (bad arguments, a newer schema, a failed migration); 2 a prerequisite is missing or the
server cannot start or be reached; 3 no tunnel address in time (the server keeps running on
localUrl and the output says `tunnel: "down"`). User text never goes on a command line: it
reaches the session through `apply`. The owner link is a credential: only `url --owner` prints it.
On Windows `python share.py ...` runs without bash.
"""

from __future__ import annotations

import argparse
import contextlib
import html
import http.client
import json
import os
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
FORGET_PAGE = "import contextlib, os, sys, time\ntime.sleep(float(sys.argv[2]))\nwith contextlib.suppress(OSError):\n    os.unlink(sys.argv[1])\n"


class Refused(Exception):
    def __init__(self, code, message, payload=None):
        super().__init__(message)
        self.code, self.message, self.payload = code, message, payload


def emit(obj):
    print(json.dumps(obj, ensure_ascii=False), flush=True)


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
        emit(a.fn(target, a))
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

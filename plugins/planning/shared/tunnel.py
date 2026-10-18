"""The shared session's public link: a cloudflared quick tunnel to the guest listener. Python 3 stdlib.

The only file that names cloudflared. `share.py` and `server.py` see a record,
`{pid, url, port, startedAt, marker, processStart, adopted}` in `<data_dir>/.shared-tunnel.json` (0600), and call
`ensure`, `alive`, `adopt` and `stop`. cloudflared runs as its own detached process (detached.py),
so it outlives a server restart and the guest link stays the same; the server restarts it when it
exits, which gives a new link.

How a quick tunnel starts and where it prints its address, as of 2026-10-16:
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/
("Starting a Quick Tunnel": `cloudflared tunnel --url <local URL>` prints a trycloudflare.com address,
a new one on every start). `--no-autoupdate` is from `cloudflared tunnel --help` (2026.9.3). Recheck
when that page changes the command, the address's domain or where it is printed, or a cloudflared
release renames `--url` or `--no-autoupdate`.

  python tunnel.py adopt --dir D --pid N --url U --port P   record a cloudflared already running
  python tunnel.py status --dir D                           print the record, or null when it is down
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.parse
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import detached  # noqa: E402  (beside this file; sys.path is set just above)

RECORD = ".shared-tunnel.json"
LOG = "cloudflared.log"
LOCK = ".shared-tunnel.lock"
URL = re.compile(r"https://(?!api\.)[a-z0-9-]+\.trycloudflare\.com")  # api. is cloudflared's own endpoint, never a tunnel
BANNER = re.compile(r"\|\s+(" + URL.pattern + r")/?\s+\|")  # the address line inside the "quick Tunnel has been created" box
START_SECONDS = 30.0  # how long a new tunnel may take to print its address
EXE = "cloudflared.exe" if detached.WINDOWS else "cloudflared"  # the program file an adopted pid must run
MISSING = "missing prerequisite: cloudflared (not on PATH; see the planning plugin's prerequisites.json)"


class TunnelDown(Exception):
    """No tunnel: cloudflared is missing, exited, or printed no address in time."""


def binary():
    """The cloudflared to run: SHARED_CLOUDFLARED (a path, used by tests and the live tracer), else PATH."""
    return os.environ.get("SHARED_CLOUDFLARED") or detached.which("cloudflared")


def _command(exe, port):
    head = detached.python(exe) if exe.endswith(".py") else [exe]
    return [*head, "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"]


def read(data_dir):
    """The record, or None when no tunnel is wanted."""
    try:
        rec = json.loads((Path(data_dir) / RECORD).read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None
    return rec if isinstance(rec, dict) and isinstance(rec.get("pid"), int) and isinstance(rec.get("url"), str) else None


def _write(data_dir, rec):
    detached.write_private(Path(data_dir) / RECORD, json.dumps(rec, indent=2) + "\n")


def _identity(rec):
    """(pid, marker, start) that detached.alive and stop check. The marker is only a program name,
    which another cloudflared, a reused pid, or on POSIX any command line naming it also carries;
    processStart is what names our process, so a record without one matches nothing."""
    return rec["pid"], rec.get("marker") or "cloudflared", rec.get("processStart") or "unknown"


def _legacy_start(rec):
    """The start of the process a record written before processStart existed names, or None unless
    it is still that tunnel: not this process, alive by the old marker check, its command line a
    quick tunnel to the recorded port, and its start readable. A command line that cannot be read
    refuses it on every OS."""
    pid = rec["pid"]
    if pid == os.getpid() or not detached.alive(pid, rec.get("marker") or "cloudflared"):
        return None
    args = detached.command_line(pid)
    if args is None or "tunnel" not in args or not _points_at(args, rec.get("port")):
        return None
    return detached.started(pid)


def _ours(data_dir, rec, held):
    """True when rec's process is the recorded cloudflared. A record with no processStart is
    accepted once, when _legacy_start proves it, and gets processStart written back (under the
    tunnel lock, which `held` says the caller already has), so an update keeps the guest link."""
    if rec.get("processStart"):
        return detached.alive(*_identity(rec))
    start = _legacy_start(rec)
    if start is None:
        return False
    d = Path(data_dir)
    if held:
        _write(d, {**rec, "processStart": start})
    else:
        with detached.locked(d / LOCK):
            if read(d) == rec:
                _write(d, {**rec, "processStart": start})
    rec["processStart"] = start
    return True


def alive(data_dir, held=False):
    """The record when its cloudflared still runs, else None. `held`: the caller holds the tunnel lock."""
    rec = read(data_dir)
    return rec if rec and _ours(data_dir, rec, held) else None


def host(url):
    """The host a guest's browser sends for this tunnel URL."""
    return url.split("://", 1)[1].rstrip("/") if "://" in url else ""


def _wait_url(proc, log, seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            m = BANNER.search(log.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            m = None
        if m:
            return m.group(1)
        if proc.poll() is not None:
            return None
        time.sleep(0.1)
    return None


def _start(data_dir, port):
    exe = binary()
    if not exe:
        raise TunnelDown(MISSING)
    d = Path(data_dir)
    log = d / LOG
    try:
        proc = detached.spawn(_command(exe, port), log=log, cwd=d)
    except OSError as exc:
        raise TunnelDown(f"cloudflared did not start: {exc}") from exc
    url = _wait_url(proc, log, float(os.environ.get("SHARED_TUNNEL_SECONDS") or START_SECONDS))
    start = detached.started(proc.pid) if url else None
    if start is None:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if url is None:
            raise TunnelDown(f"cloudflared printed no trycloudflare.com address in time (log: {log})")
        raise TunnelDown(f"when cloudflared pid {proc.pid} started cannot be read, so it could not be told from a later program with its pid")
    # The word alive() looks for: the program's name in its command line, or on Windows the stem of
    # the executable the OS reports (python for the test fake).
    marker = Path((detached.describe(proc.pid) or exe) if detached.WINDOWS else exe).stem.lower()
    rec = {"pid": proc.pid, "url": url, "port": port, "startedAt": time.time(), "marker": marker, "processStart": start, "adopted": False}
    _write(d, rec)
    detached.release(proc)
    return rec


def ensure(data_dir, port):
    """The running tunnel to `port`, reattached or started (a new address); raises TunnelDown."""
    d = Path(data_dir)
    with detached.locked(d / LOCK):
        rec = alive(d, held=True)
        if rec and rec.get("port") == port:
            return rec
        if rec:
            _end(rec)
        return _start(d, port)


def _url_arg(args):
    """The value of cloudflared's one `--url` (or `-url`, with or without `=`), else None."""
    found = []
    for i, a in enumerate(args):
        flag, eq, value = a.partition("=")
        if flag in ("--url", "-url"):
            found.append(value if eq else (args[i + 1] if i + 1 < len(args) else None))
    return found[0] if len(found) == 1 else None


def _points_at(args, port):
    """True when the one `--url` in args is http://127.0.0.1:<port> or http://localhost:<port>."""
    try:
        target = urllib.parse.urlsplit(_url_arg(args) or "")
        to = (target.scheme, target.hostname, target.port)
    except ValueError:
        return False
    return isinstance(port, int) and to in (("http", "127.0.0.1", port), ("http", "localhost", port))


def adoptable(pid, port):
    """Why pid cannot be adopted as the tunnel to `port`, or None: it must run the cloudflared
    executable (by the file name the OS reports, which a process cannot set, unlike its command
    line), and its one `--url` must be http://127.0.0.1:<port> or http://localhost:<port>. A pid
    whose command line cannot be read is refused on every OS."""
    name = detached.exe_name(pid)
    if name is None or (name.lower() != EXE if detached.WINDOWS else name != EXE):
        return f"no cloudflared runs as pid {pid}" + (f" (its program is {name})" if name else "")
    args = detached.command_line(pid)
    if args is None:
        return f"the command line of cloudflared pid {pid} cannot be read, so the port it points at is unknown"
    if not _points_at(args, port):
        return f"cloudflared pid {pid} does not point at port {port} on this machine (its --url must be http://127.0.0.1:{port})"
    return None


def adopt(data_dir, pid, url, port):
    """Record a cloudflared already running as pid with address url, starting nothing."""
    if not URL.fullmatch(url.rstrip("/")):
        raise TunnelDown(f"{url} is not a trycloudflare.com address")
    why = adoptable(pid, port)
    if why:
        raise TunnelDown(why)
    start = detached.started(pid)
    if start is None:
        raise TunnelDown(f"when cloudflared pid {pid} started cannot be read, so it could not be told from a later program with its pid")
    d = Path(data_dir)
    with detached.locked(d / LOCK):
        rec = {"pid": pid, "url": url.rstrip("/"), "port": port, "startedAt": time.time(), "marker": "cloudflared", "processStart": start, "adopted": True}
        _write(d, rec)
        return rec


def _end(rec):
    """Stop the recorded cloudflared, unless it was adopted: that one is never signaled, so the
    prototype it came from can take its link back. True when one was stopped."""
    return not rec.get("adopted") and detached.stop(*_identity(rec))


def stop(data_dir):
    """Stop the recorded cloudflared (an adopted one keeps running) and drop the record; True when one was stopped."""
    d = Path(data_dir)
    with detached.locked(d / LOCK):
        rec = read(d)
        stopped = bool(rec) and _ours(d, rec, True) and _end(rec)
        (d / RECORD).unlink(missing_ok=True)
        return stopped


def main(argv=None):
    p = argparse.ArgumentParser(description="The shared session's cloudflared quick tunnel.")
    p.add_argument("cmd", choices=("adopt", "status"))
    p.add_argument("--dir", required=True)
    p.add_argument("--pid", type=int)
    p.add_argument("--url")
    p.add_argument("--port", type=int)
    a = p.parse_args(argv)
    if a.cmd == "status":
        print(json.dumps(alive(a.dir)))
        return 0
    if a.pid is None or not a.url or a.port is None:
        p.error("adopt needs --pid, --url and --port")
    try:
        print(json.dumps(adopt(a.dir, a.pid, a.url, a.port)))
    except TunnelDown as exc:
        print(str(exc), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())

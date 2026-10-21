"""The shared session's public link: a cloudflared tunnel to the guest listener. Python 3 stdlib.

The only file that runs cloudflared. `share.py` and `server.py` see a record,
`{pid, url, port, startedAt, marker, processStart, adopted[, hostname, tokenFile][, retired]}` in
`<data_dir>/.shared-tunnel.json` (0600), and call `ensure`, `alive`, `adopt`, `retired`, `sweep` and `stop`.
cloudflared runs as its own detached process (detached.py), so it outlives a server restart and the
guest link stays the same; the server restarts it when it exits.

Two kinds of tunnel. A quick tunnel (no hostname) gets a new trycloudflare.com address on every
start. A named tunnel (`hostname` and `tokenFile`, the planning plugin's `tunnel_hostname` option)
runs a remotely-managed tunnel the owner set up, so its address is `https://<hostname>` on every
start. Switching between them, or between two hostnames, keeps the old tunnel running as `retired`
for RETIRE_SECONDS, so a page still open on the old address can learn the new one (server.py).

How a quick tunnel starts and where it prints its address, as of 2026-10-16:
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/do-more-with-tunnels/trycloudflare/
("Starting a Quick Tunnel": `cloudflared tunnel --url <local URL>` prints a trycloudflare.com address,
a new one on every start). `--no-autoupdate` is from `cloudflared tunnel --help` (2026.9.3). Recheck
when that page changes the command, the address's domain or where it is printed, or a cloudflared
release renames `--url` or `--no-autoupdate`.

How a named tunnel runs, as of 2026-10-21:
https://developers.cloudflare.com/cloudflare-one/networks/connectors/cloudflare-tunnel/configure-tunnels/run-parameters/
(`token-file`: `cloudflared tunnel run --token-file <PATH>`, cloudflared 2025.4.0 or later), so the
token never reaches a command line. cloudflared's `TUNNEL_TOKEN` takes precedence over the file
(TunnelTokenFlag's usage in cmd/cloudflared/tunnel/subcommands.go), so neither token variable
reaches the child. Ready means the log names a connection: "Registered tunnel connection"
(connection/observer.go in https://github.com/cloudflare/cloudflared). Recheck when that page
renames `--token-file`, or a release changes that log line.

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
READY = re.compile(r"Registered tunnel connection")  # a named tunnel's first connection to Cloudflare
HOSTNAME = re.compile(r"(?=.{4,253}\Z)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z][a-z0-9-]{0,61}[a-z0-9]")
START_SECONDS = 30.0  # how long a new tunnel may take to print its address
RETIRE_SECONDS = 600.0  # judgment: how long the old address keeps answering after a switch, so open pages move
# cloudflared reads the first two; the last two are Cloudflare API tokens. No child of this plugin inherits any of them.
TOKEN_ENV = ("TUNNEL_TOKEN", "TUNNEL_TOKEN_FILE", "CLOUDFLARE_API_TOKEN", "CF_API_TOKEN")
EXE = "cloudflared.exe" if detached.WINDOWS else "cloudflared"  # the program file an adopted pid must run
MISSING = "missing prerequisite: cloudflared (not on PATH; see the planning plugin's prerequisites.json)"


class TunnelDown(Exception):
    """No tunnel: cloudflared is missing, exited, or printed no address in time."""


def binary():
    """The cloudflared to run: SHARED_CLOUDFLARED (a path, used by tests and the live tracer), else PATH."""
    return os.environ.get("SHARED_CLOUDFLARED") or detached.which("cloudflared")


def _command(exe, port, hostname="", token_file=""):
    head = detached.python(exe) if exe.endswith(".py") else [exe]
    if hostname:
        return [*head, "tunnel", "--no-autoupdate", "run", "--token-file", token_file]
    return [*head, "tunnel", "--no-autoupdate", "--url", f"http://127.0.0.1:{port}"]


def child_env():
    """This process's environment without TOKEN_ENV: cloudflared's token variables would override --token-file or turn a
    quick tunnel into a named one, and no child needs a Cloudflare API token."""
    return {k: v for k, v in os.environ.items() if k.upper() not in TOKEN_ENV}


def hostname_problem(hostname):
    """Why `hostname` cannot be a named tunnel's address, or None."""
    if not HOSTNAME.fullmatch(hostname or ""):
        return f"the tunnel hostname must be a DNS name such as interview.example.com, got {hostname!r}"
    if hostname == "trycloudflare.com" or hostname.endswith(".trycloudflare.com"):
        return "a trycloudflare.com address is a quick tunnel's: leave the tunnel hostname empty for one"
    return None


def token_file_problem(path):
    """Why `path` cannot be the tunnel token file, or None. Checks the file, never reads it."""
    if not path:
        return "a named tunnel needs its token file (the tunnel_token_file option)"
    p = Path(path)
    if not p.is_absolute():
        return f"the tunnel token file must be an absolute path, got {path!r}"
    try:
        st = p.stat()
    except OSError:
        return f"the tunnel token file {path} does not exist"
    if not p.is_file() or not st.st_size:
        return f"the tunnel token file {path} is not a file with a token in it"
    if not os.access(p, os.R_OK):
        return f"the tunnel token file {path} cannot be read"
    if detached.WINDOWS:
        return _acl_problem(path)
    if st.st_mode & 0o077:
        return f"the tunnel token file {path} can be read by other users: run chmod 600 on it"
    return None


WINDOWS_ALLOWED = ("S-1-5-18", "S-1-5-32-544", "S-1-3-4")  # SYSTEM, Administrators and OWNER RIGHTS, beside the user


def _acl_problem(path):
    """Why the token file's Windows DACL lets more than this user, the file's owner, SYSTEM and Administrators in, or None."""
    got = _windows_acl(path)
    if got is None:
        return f"the permissions of the tunnel token file {path} cannot be read"
    me, sids = got
    others = sorted(set(sids) - {me, *WINDOWS_ALLOWED})
    if others:
        return (
            f"the tunnel token file {path} can be read by others ({', '.join(others)}): allow only your account, SYSTEM and"
            f' Administrators (icacls "{path}" /inheritance:r /grant:r "%USERNAME%:F" SYSTEM:F *S-1-5-32-544:F)'
        )
    return None


def _windows_acl(path):
    """(this user's SID, the SIDs the file's DACL allows access) as strings, or None when either cannot be read.
    Deny and inherit-only entries are skipped; no DACL at all, which allows everyone, reads as Everyone (S-1-1-0), and
    an allow entry of another kind as "?". Win32 calls through ctypes, as the stdlib has no ACL reader:
    https://learn.microsoft.com/en-us/windows/win32/api/securitybaseapi/nf-securitybaseapi-getfilesecurityw"""
    import ctypes
    from ctypes import wintypes

    advapi = ctypes.WinDLL("advapi32", use_last_error=True)
    kernel = ctypes.WinDLL("kernel32", use_last_error=True)
    advapi.GetFileSecurityW.argtypes = [wintypes.LPCWSTR, wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    advapi.GetSecurityDescriptorDacl.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.BOOL), ctypes.POINTER(ctypes.c_void_p), ctypes.POINTER(wintypes.BOOL)]
    advapi.GetAce.argtypes = [ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(ctypes.c_void_p)]
    advapi.ConvertSidToStringSidW.argtypes = [ctypes.c_void_p, ctypes.POINTER(wintypes.LPWSTR)]
    advapi.OpenProcessToken.argtypes = [wintypes.HANDLE, wintypes.DWORD, ctypes.POINTER(wintypes.HANDLE)]
    advapi.GetTokenInformation.argtypes = [wintypes.HANDLE, ctypes.c_int, ctypes.c_void_p, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD)]
    kernel.GetCurrentProcess.restype = wintypes.HANDLE
    kernel.CloseHandle.argtypes = [wintypes.HANDLE]
    kernel.LocalFree.argtypes = [ctypes.c_void_p]

    def sid_text(sid):
        out = wintypes.LPWSTR()
        if not advapi.ConvertSidToStringSidW(sid, ctypes.byref(out)):
            return None
        try:
            return out.value
        finally:
            kernel.LocalFree(out)

    token = wintypes.HANDLE()
    if not advapi.OpenProcessToken(kernel.GetCurrentProcess(), 0x0008, ctypes.byref(token)):  # TOKEN_QUERY
        return None
    try:
        need = wintypes.DWORD()
        advapi.GetTokenInformation(token, 1, None, 0, ctypes.byref(need))  # TokenUser
        buf = ctypes.create_string_buffer(need.value or 1)
        if not advapi.GetTokenInformation(token, 1, buf, need, ctypes.byref(need)):
            return None
        me = sid_text(ctypes.c_void_p.from_buffer(buf).value)  # TOKEN_USER starts with the user's PSID
    finally:
        kernel.CloseHandle(token)
    need = wintypes.DWORD()
    advapi.GetFileSecurityW(path, 4, None, 0, ctypes.byref(need))  # DACL_SECURITY_INFORMATION
    if not me or not need.value:
        return None
    sd = ctypes.create_string_buffer(need.value)
    present, defaulted, acl = wintypes.BOOL(), wintypes.BOOL(), ctypes.c_void_p()
    if not advapi.GetFileSecurityW(path, 4, sd, need, ctypes.byref(need)) or not advapi.GetSecurityDescriptorDacl(sd, ctypes.byref(present), ctypes.byref(acl), ctypes.byref(defaulted)):
        return None
    if not present.value or not acl.value:
        return me, ["S-1-1-0"]
    sids = []
    for i in range(ctypes.c_uint16.from_address(acl.value + 4).value):  # ACL.AceCount
        ace = ctypes.c_void_p()
        if not advapi.GetAce(acl, i, ctypes.byref(ace)):
            return None
        kind, flags = ctypes.c_uint8.from_address(ace.value).value, ctypes.c_uint8.from_address(ace.value + 1).value
        if kind == 1 or flags & 0x08:  # ACCESS_DENIED_ACE_TYPE, INHERIT_ONLY_ACE
            continue
        sids.append((sid_text(ace.value + 8) or "?") if kind == 0 else "?")  # ACCESS_ALLOWED_ACE: header, mask, then the SID
    return me, sids


def config(rec):
    """(hostname, token file) a record's tunnel runs with; ("", "") for a quick tunnel."""
    rec = rec or {}
    return rec.get("hostname") or "", rec.get("tokenFile") or ""


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


def _wait_url(proc, log, seconds, pattern=BANNER):
    """The first match of `pattern` in the log (its group 1 when it has one), or None once cloudflared exits or time is up."""
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            m = pattern.search(log.read_text(encoding="utf-8", errors="replace"))
        except OSError:
            m = None
        if m:
            return m.group(1) if pattern.groups else m.group(0)
        if proc.poll() is not None:
            return None
        time.sleep(0.1)
    return None


def _start(data_dir, port, hostname="", token_file="", retired_entry=None):
    """Start cloudflared and write its record, with `retired_entry` (a tunnel left running) as its retired."""
    problem = hostname and (hostname_problem(hostname) or token_file_problem(token_file))
    if problem:
        raise TunnelDown(problem)
    exe = binary()
    if not exe:
        raise TunnelDown(MISSING)
    d = Path(data_dir)
    log = d / LOG
    try:
        proc = detached.spawn(_command(exe, port, hostname, token_file), log=log, env=child_env(), cwd=d)
    except OSError as exc:
        raise TunnelDown(f"cloudflared did not start: {exc}") from exc
    seconds = float(os.environ.get("SHARED_TUNNEL_SECONDS") or START_SECONDS)
    url = (f"https://{hostname}" if _wait_url(proc, log, seconds, READY) else None) if hostname else _wait_url(proc, log, seconds)
    start = detached.started(proc.pid) if url else None
    if start is None:
        if proc.poll() is None:
            proc.kill()
            proc.wait()
        if url is None:
            what = f"no connection for {hostname}" if hostname else "no trycloudflare.com address"
            raise TunnelDown(f"cloudflared printed {what} in time (log: {log})")
        raise TunnelDown(f"when cloudflared pid {proc.pid} started cannot be read, so it could not be told from a later program with its pid")
    # The word alive() looks for: the program's name in its command line, or on Windows the stem of
    # the executable the OS reports (python for the test fake).
    marker = Path((detached.describe(proc.pid) or exe) if detached.WINDOWS else exe).stem.lower()
    rec = {"pid": proc.pid, "url": url, "port": port, "startedAt": time.time(), "marker": marker, "processStart": start, "adopted": False}
    if hostname:
        rec.update(hostname=hostname, tokenFile=token_file)
    if retired_entry:
        rec["retired"] = retired_entry
    _write(d, rec)
    detached.release(proc)
    return rec


def _retire_seconds():
    return float(os.environ.get("SHARED_RETIRE_SECONDS") or RETIRE_SECONDS)


def ensure(data_dir, port, hostname="", token_file=""):
    """The running tunnel to `port` with this hostname and token file ("" for a quick tunnel), reattached or started;
    raises TunnelDown. A running tunnel to the same port at another address stays up as the record's `retired`."""
    d = Path(data_dir)
    with detached.locked(d / LOCK):
        rec = alive(d, held=True)
        if rec and rec.get("port") == port and config(rec) == (hostname, token_file):
            return rec
        if hostname and rec and rec.get("port") == port and rec["url"] == f"https://{hostname}":
            _end(rec)  # the same address with another token file: nothing to move to
            rec = None
        old = (rec or read(d) or {}).get("retired")
        keep = rec if rec and rec.get("port") == port else None
        if rec and not keep:
            _end(rec)
        if not keep:  # a restart at the same address: the tunnel retired before keeps its grace time
            return _start(d, port, hostname, token_file, retired_entry=old)
        if old and detached.alive(*_identity(old)):
            _end(old)  # one retired tunnel at a time
        entry = {k: keep[k] for k in ("pid", "url", "marker", "processStart", "adopted") if k in keep} | {"until": time.time() + _retire_seconds()}
        return _start(d, port, hostname, token_file, retired_entry=entry)


def retired(data_dir):
    """The retired tunnel while its grace time runs and it still runs, else None."""
    old = (read(data_dir) or {}).get("retired")
    if not isinstance(old, dict) or not isinstance(old.get("pid"), int) or time.time() >= float(old.get("until") or 0):
        return None
    return old if detached.alive(*_identity(old)) else None


def sweep(data_dir):
    """Stop a retired tunnel whose grace time is up and drop it from the record; True when one was stopped."""
    d = Path(data_dir)
    if "retired" not in (read(d) or {}) or retired(d):  # most passes: nothing to take the lock for
        return False
    with detached.locked(d / LOCK):
        rec = read(d)
        old = (rec or {}).get("retired")
        if not old or retired(d):
            return False
        rec.pop("retired")
        _write(d, rec)
        return isinstance(old, dict) and isinstance(old.get("pid"), int) and _end(old)


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
        old = (rec or {}).get("retired")
        if isinstance(old, dict) and isinstance(old.get("pid"), int):
            _end(old)
        stopped = bool(rec) and _ours(d, rec, True) and _end(rec)
        (d / RECORD).unlink(missing_ok=True)
        return stopped


def main(argv=None):
    p = argparse.ArgumentParser(description="The shared session's cloudflared tunnel.")
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

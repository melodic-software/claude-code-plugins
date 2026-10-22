"""A live prototype's static server, and the walk that copies its build folder. Python 3 stdlib.

  python liveserve.py --root DIR [--port N]   serve DIR on 127.0.0.1 (port 0 picks one); prints READY with the port

The server answers GET and HEAD with a regular file under the root (a folder answers its index.html), and nothing
else: any other method is 405, a path with a segment starting with "." is 404, and a path that resolves (symlinks
included) outside the root, or onto a hidden name inside it, is 404. No folder is ever listed. Every answer carries
CSP, Referrer-Policy and nosniff, so a prototype's script reaches only its own origin and a guest's tab sends no
referrer. It has no Host check, no other route, and runs as one process, so stopping its pid stops it on every OS.

`scan_build` and `copy_build` are the walk `add-live` and the start run over a build folder: regular files and
folders only, no symlink, junction or other reparse point, no hidden name, at most MAX_FILES files and MAX_BYTES
bytes. The server only ever serves the copy (`<data_dir>/live/<id>/`), never the folder the model wrote, which sits in
the same data folder as the session's secrets.
"""

from __future__ import annotations

import argparse
import contextlib
import os
import re
import shutil
import stat
import sys
import time
import urllib.parse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

HERE = Path(__file__).resolve().parent
if str(HERE) not in sys.path:
    sys.path.insert(0, str(HERE))

import detached  # noqa: E402  (beside this file; sys.path is set just above)

MAX_BYTES = 50 * 1024 * 1024  # judgment: a static build with sample data fits well within this
MAX_FILES = 2000  # judgment
READY = re.compile(r"liveserve: serving http://127\.0\.0\.1:([0-9]{1,5})/")
START_SECONDS = 10.0  # how long a new server may take to print READY
MARKER = "python" if detached.WINDOWS else "liveserve.py"  # what detached.alive finds in its command line or program
CSP = "default-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'"
HEADERS = {"Content-Security-Policy": CSP, "Referrer-Policy": "no-referrer", "X-Content-Type-Options": "nosniff", "Cache-Control": "no-store"}
# A fixed map, not mimetypes: on Windows mimetypes reads the registry, which can name .js text/plain and break a module.
TYPES = {
    ".html": "text/html; charset=utf-8", ".htm": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
    ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json",
    ".map": "application/json", ".txt": "text/plain; charset=utf-8", ".svg": "image/svg+xml", ".png": "image/png",
    ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".avif": "image/avif",
    ".ico": "image/x-icon", ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf",
    ".wasm": "application/wasm", ".mp4": "video/mp4", ".webm": "video/webm",
}
_REPARSE = 0x400  # FILE_ATTRIBUTE_REPARSE_POINT: a junction or symlink on Windows, which is_symlink() can miss


class BuildRefused(ValueError):
    """A build folder that cannot be served: it holds a link, a hidden name or a special file, or is too big."""


def _linked(st):
    return stat.S_ISLNK(st.st_mode) or bool(getattr(st, "st_file_attributes", 0) & _REPARSE)


def scan_build(src):
    """[(path relative to src, as a tuple of names, size)] for every file under the folder `src`, or BuildRefused
    naming the first thing that cannot be served."""
    root = Path(src)
    try:
        st = os.lstat(root)
    except OSError as exc:
        raise BuildRefused(f"no build folder at {root}") from exc
    if _linked(st) or not stat.S_ISDIR(st.st_mode):
        raise BuildRefused(f"{root} is not a folder")
    files, total, stack = [], 0, [()]
    while stack:
        rel = stack.pop()
        with os.scandir(root.joinpath(*rel)) as it:
            entries = sorted(it, key=lambda e: e.name)
        for e in entries:
            where = "/".join((*rel, e.name))
            if e.name.startswith("."):
                raise BuildRefused(f"the build folder holds a hidden name: {where}")
            st = e.stat(follow_symlinks=False)
            if e.is_symlink() or _linked(st):
                raise BuildRefused(f"the build folder holds a link: {where}")
            if stat.S_ISDIR(st.st_mode):
                stack.append((*rel, e.name))
            elif stat.S_ISREG(st.st_mode):
                files.append(((*rel, e.name), st.st_size))
                total += st.st_size
                if len(files) > MAX_FILES:
                    raise BuildRefused(f"the build folder holds more than {MAX_FILES} files")
                if total > MAX_BYTES:
                    raise BuildRefused(f"the build folder holds more than {MAX_BYTES // (1024 * 1024)} MB")
            else:
                raise BuildRefused(f"the build folder holds something that is not a file or a folder: {where}")
    return files


def copy_build(src, dest):
    """Copy the folder `src` into `dest` (replaced, made 0700) with scan_build's rules, each file opened without
    following a link and checked to be the regular file the walk saw; the number of files copied."""
    files = scan_build(src)
    dest = Path(dest)
    if dest.is_symlink():
        raise BuildRefused(f"{dest} is a link")
    shutil.rmtree(dest, ignore_errors=True)
    detached.make_private_dir(dest)
    base = Path(src).resolve()
    try:
        for rel, size in files:
            _copy_one(base, rel, size, dest)
    except BaseException:
        shutil.rmtree(dest, ignore_errors=True)
        raise
    return len(files)


def _copy_one(base, rel, size, dest):
    """Copy one file the walk saw as `size` bytes: still under `base` once its folders' links are resolved, and opened
    without following a link (nor waiting on a pipe swapped in)."""
    source = base.joinpath(*rel)
    if source.parent.resolve() != base.joinpath(*rel[:-1]):
        raise BuildRefused(f"{'/'.join(rel)} changed while it was copied")
    flags = os.O_RDONLY | getattr(os, "O_NOFOLLOW", 0) | getattr(os, "O_NONBLOCK", 0) | getattr(os, "O_BINARY", 0)
    try:
        fd = os.open(source, flags)
    except OSError as exc:
        raise BuildRefused(f"{'/'.join(rel)} cannot be read: {exc.strerror or exc}") from exc
    with os.fdopen(fd, "rb") as f:
        st = os.fstat(f.fileno())
        data = f.read(size + 1) if stat.S_ISREG(st.st_mode) else b""
        if not stat.S_ISREG(st.st_mode) or _linked(os.lstat(source)) or len(data) != size:
            raise BuildRefused(f"{'/'.join(rel)} changed while it was copied")
    detached.make_private_dir(dest.joinpath(*rel[:-1]))
    with detached.open_private(dest.joinpath(*rel), "wb") as out:
        out.write(data)


def resolve(root, target):
    """The file a request target names under `root` (already resolved), or None: no hidden segment, backslash, NUL
    or colon, and the path resolved with its links must stay under the root on a name that is not hidden either."""
    path = urllib.parse.urlsplit(target).path
    if not path.startswith("/"):
        return None
    try:
        text = urllib.parse.unquote(path, errors="strict")
    except UnicodeDecodeError:
        return None
    if any(c in text for c in "\\\0:"):
        return None
    parts = [p for p in text.split("/") if p]
    if any(p.startswith(".") for p in parts):
        return None
    try:
        real = root.joinpath(*parts).resolve(strict=True)
        if real.is_dir():
            real = (real / "index.html").resolve(strict=True)
    except (OSError, RuntimeError):
        return None
    if not real.is_relative_to(root) or any(p.startswith(".") for p in real.relative_to(root).parts):
        return None
    return real if real.is_file() else None


class Handler(BaseHTTPRequestHandler):
    server_version = "liveserve"
    sys_version = ""
    protocol_version = "HTTP/1.1"
    timeout = 30  # judgment: an idle or slow connection is closed after this many seconds

    def __getattr__(self, name):
        # BaseHTTPRequestHandler answers 501 to a method it has no do_X for; every method but GET and HEAD is 405 here.
        if name.startswith("do_"):
            return self.refuse
        raise AttributeError(name)

    def log_message(self, format, *args):  # noqa: A002  # matches the base signature; requests are not logged
        pass

    def end_headers(self):
        for k, v in HEADERS.items():
            self.send_header(k, v)
        super().end_headers()

    def answer(self, code, body, ctype, extra=None):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        if self.command != "HEAD":
            self.wfile.write(body)

    def refuse(self):
        self.close_connection = True  # the request body, if any, is never read
        self.answer(405, b"Method not allowed\n", "text/plain; charset=utf-8", {"Allow": "GET, HEAD", "Connection": "close"})

    def do_GET(self):
        f = resolve(self.server.root, self.path)
        if f is None:
            return self.answer(404, b"Not found\n", "text/plain; charset=utf-8")
        try:
            data = f.read_bytes()
        except OSError:
            return self.answer(404, b"Not found\n", "text/plain; charset=utf-8")
        self.answer(200, data, TYPES.get(f.suffix.lower(), "application/octet-stream"))

    do_HEAD = do_GET


class Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = False  # never share a port another program holds

    def __init__(self, root, port=0):
        self.root = Path(root).resolve(strict=True)
        super().__init__(("127.0.0.1", port), Handler)


def spawn(root, log, env=None):
    """Start this server detached on a free port serving `root`; (the Popen, its port), the port None when it printed
    no READY line in time (the process is then ended)."""
    proc = detached.spawn(detached.python(str(HERE / "liveserve.py"), "--root", str(root)), log=log, env=env, cwd=root)
    deadline = time.monotonic() + float(os.environ.get("SHARED_LIVESERVE_SECONDS") or START_SECONDS)
    while time.monotonic() < deadline:
        with contextlib.suppress(OSError):
            m = READY.search(Path(log).read_text(encoding="utf-8", errors="replace"))
            if m:
                return proc, int(m.group(1))
        if proc.poll() is not None:
            return proc, None
        time.sleep(0.05)
    proc.kill()
    proc.wait()
    return proc, None


def main(argv=None):
    p = argparse.ArgumentParser(description="Serve one live prototype's build folder on 127.0.0.1.")
    p.add_argument("--root", required=True)
    p.add_argument("--port", type=int, default=0)
    a = p.parse_args(argv)
    try:
        httpd = Server(a.root, a.port)
    except OSError as exc:
        print(f"liveserve: cannot serve {a.root}: {exc}", file=sys.stderr)
        return 2
    print(f"liveserve: serving http://127.0.0.1:{httpd.server_address[1]}/", flush=True)
    with contextlib.suppress(KeyboardInterrupt):
        httpd.serve_forever(poll_interval=0.5)
    return 0


if __name__ == "__main__":
    sys.exit(main())

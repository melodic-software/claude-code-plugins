#!/usr/bin/env python3
"""prune-run-roots - remove plugin-eval run roots under $HOME/.ev that no run still uses.

    prune-run-roots.py [<run-root>...]

With no argument every direct child of $HOME/.ev is a candidate; a missing
$HOME/.ev has none. A candidate is removed only when all of these hold:

- it is a directory, not a symlink, and its realpath is a direct child of the
  realpath of $HOME/.ev;
- it holds at least one claude-eval-* directory;
- nothing in it changed for 3 days: the root and every entry under it, read
  without following symlinks, has an mtime older than 3 days (a directory it
  cannot open, such as a mode-000 sealed/, counts by its own mtime);
- no process has a file open under it or its working directory there, read
  from /proc/<pid>/fd and /proc/<pid>/cwd.

Removal follows sandboxes.md, Removing a run root: chmod u+rwx on each
claude-eval-* directory, chmod 700 on its sealed/, chmod u+rwx on every
directory below the root, then the root is removed. A symlink is never opened.

One line per candidate: `removed: <path>`, `kept (<reason>): <path>`,
`refused (<reason>): <path>`, or `left behind (<error>): <path>`.

Exit: 0 every candidate was removed, kept or refused; 1 a removal failed and
left a path; 2 nothing was checked: $HOME is unset, $HOME/.ev resolves to the
root or a shared temp directory, or /proc cannot be read.
"""

import argparse
import os
import shutil
import stat
import sys
import tempfile
import time

MIN_PYTHON = (3, 8)
MAX_IDLE_SECONDS = 3 * 24 * 60 * 60
SANDBOX_PREFIX = "claude-eval-"


def shared_dirs():
    return {
        os.path.realpath(p)
        for p in ("/", "/tmp", "/var/tmp", tempfile.gettempdir())
    }


def is_under(path, root):
    return path == root or path.startswith(root + os.sep)


def held_roots(roots):
    held = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        links = [os.path.join("/proc", pid, "cwd")]
        fd_dir = os.path.join("/proc", pid, "fd")
        try:
            links.extend(os.path.join(fd_dir, fd) for fd in os.listdir(fd_dir))
        except OSError:
            pass
        for link in links:
            try:
                target = os.readlink(link)
            except OSError:
                continue
            held.update(r for r in roots if is_under(target, r))
    return held


def newest_mtime(root):
    newest = os.lstat(root).st_mtime
    for dirpath, dirnames, filenames in os.walk(root, onerror=lambda e: None):
        for name in dirnames + filenames:
            try:
                newest = max(newest, os.lstat(os.path.join(dirpath, name)).st_mtime)
            except OSError:
                continue
    return newest


def has_sandbox(root):
    with os.scandir(root) as entries:
        return any(
            e.name.startswith(SANDBOX_PREFIX) and e.is_dir(follow_symlinks=False)
            for e in entries
        )


def add_owner_rwx(path):
    mode = os.lstat(path).st_mode
    if stat.S_ISDIR(mode):
        os.chmod(path, stat.S_IMODE(mode) | stat.S_IRWXU)


def remove(root):
    add_owner_rwx(root)
    with os.scandir(root) as entries:
        sandboxes = [
            e.path
            for e in entries
            if e.name.startswith(SANDBOX_PREFIX) and e.is_dir(follow_symlinks=False)
        ]
    for sandbox in sandboxes:
        add_owner_rwx(sandbox)
        sealed = os.path.join(sandbox, "sealed")
        if os.path.isdir(sealed) and not os.path.islink(sealed):
            os.chmod(sealed, 0o700)
    for dirpath, dirnames, _ in os.walk(root):
        for name in dirnames:
            add_owner_rwx(os.path.join(dirpath, name))
    shutil.rmtree(root)


def classify(path, ev_root, now):
    path = path.rstrip(os.sep) or os.sep
    real = os.path.realpath(path)
    if os.path.islink(path):
        return "refused", "a symlink, not followed"
    if not os.path.isdir(path):
        return "refused", "not a directory"
    if os.path.dirname(real) != ev_root:
        return "refused", "not directly under %s" % ev_root
    try:
        if not has_sandbox(real):
            return "kept", "holds no %s* sandbox" % SANDBOX_PREFIX
    except OSError as err:
        return "kept", "cannot open it: %s" % err.strerror
    if now - newest_mtime(real) <= MAX_IDLE_SECONDS:
        return "kept", "changed within 3 days"
    return "candidate", real


def main(argv=None):
    if sys.version_info < MIN_PYTHON:
        sys.stderr.write("error: prune-run-roots needs Python %d.%d or newer\n" % MIN_PYTHON)
        return 2
    parser = argparse.ArgumentParser(
        prog="prune-run-roots",
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("paths", nargs="*", metavar="run-root")
    args = parser.parse_args(argv)

    home = os.environ.get("HOME")
    if not home:
        sys.stderr.write("error: HOME is unset\n")
        return 2
    ev = os.path.join(home, ".ev")
    ev_root = os.path.realpath(ev)
    if ev_root in shared_dirs():
        sys.stderr.write("error: %s resolves to %s, a shared directory\n" % (ev, ev_root))
        return 2
    if not os.path.isdir("/proc/self/fd"):
        sys.stderr.write("error: /proc cannot be read, so open files cannot be checked\n")
        return 2

    if args.paths:
        paths = args.paths
    elif os.path.isdir(ev_root):
        paths = sorted(os.path.join(ev, name) for name in os.listdir(ev_root))
    else:
        paths = []

    now = time.time()
    candidates = {}
    for path in paths:
        verdict, detail = classify(path, ev_root, now)
        if verdict == "candidate":
            candidates[detail] = path
        else:
            print("%s (%s): %s" % (verdict, detail, path))

    held = held_roots(set(candidates))
    status = 0
    for real, path in candidates.items():
        if real in held:
            print("kept (a process has a file open under it): %s" % path)
            continue
        try:
            remove(real)
        except OSError as err:
            print("left behind (%s): %s" % (err.strerror or err, path))
            status = 1
            continue
        print("removed: %s" % path)
    return status


if __name__ == "__main__":
    sys.exit(main())

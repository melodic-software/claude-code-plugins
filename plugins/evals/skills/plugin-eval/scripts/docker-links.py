#!/usr/bin/env python3
"""docker-links - swap the Docker credential store's links for real copies for one run.

    docker-links run -- <command> [<arg>...]
    docker-links swap
    docker-links restore

The store is $HOME/.docker. `swap` replaces every symbolic link the preflight's
`find "$HOME/.docker/" -mindepth 1 -type l` would list, or the store itself when
it is a link, with a dereferenced copy of its target, after writing each link's
literal value to the record $HOME/.docker-link-swap.json. `restore` puts every
recorded link back and deletes the record. `run` swaps, runs the command (no
shell), and restores when it exits, fails, or the wrapper gets SIGINT, SIGTERM
or SIGHUP, which it forwards to the command first.

The copies are throwaway: anything written into them during the run is
discarded at restore, and the link targets are only read. A run killed with
SIGKILL leaves the record behind; `restore` recovers it, and `swap` refuses
while it exists. A path that is a link again at restore time (Docker Desktop
recreates its links) is left as it is. DOCKER_CONFIG is never read or set.

Exit: `run` exits with the command's code, or 128 + the signal number; 0 for
`swap` and `restore` done; 2 refused with nothing changed (a record already
exists, a dangling link, no store, a non-POSIX host, a failed swap rolled
back); 3 a restore step failed, the record is kept and names what is left.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
from pathlib import Path

MIN_PYTHON = (3, 8)
TMP_SUFFIX = ".link-swap-tmp"
SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP) if os.name == "posix" else ()


def store_path():
    return Path.home() / ".docker"


def record_path():
    return Path.home() / ".docker-link-swap.json"


def say(message):
    print(f"docker-links: {message}", file=sys.stderr)


def find_links(store):
    """The paths the preflight's find lists, or the store itself when it is a link."""
    if store.is_symlink():
        return [store]
    links = []
    for parent, dirs, files in os.walk(store, followlinks=False):
        for name in dirs + files:
            path = Path(parent) / name
            if path.is_symlink():
                links.append(path)
    return sorted(links)


def remove(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def replace_with_copy(path):
    tmp = path.with_name(path.name + TMP_SUFFIX)
    remove(tmp)
    if path.is_dir():
        shutil.copytree(path, tmp, symlinks=False)
        path.unlink()
        os.rename(tmp, path)
    else:
        shutil.copy2(path, tmp)
        os.replace(tmp, path)


def swap():
    store, record = store_path(), record_path()
    if record.exists() or record.is_symlink():
        say(f"refused: {record} holds an earlier swap; run `restore` first")
        return 2
    if not (store.exists() or store.is_symlink()):
        say(f"refused: no store at {store}")
        return 2
    links = find_links(store)
    dangling = [str(p) for p in links if not p.exists()]
    if dangling:
        say("refused: dangling link(s), nothing changed: " + ", ".join(dangling))
        return 2
    entries = [{"path": str(p), "target": os.readlink(p)} for p in links]
    with open(record, "x", encoding="utf-8") as handle:
        json.dump({"store": str(store), "links": entries}, handle, indent=2)
        handle.write("\n")
    try:
        for path in links:
            replace_with_copy(path)
        left = find_links(store)
        if left:
            raise OSError("links remain after the swap: " + ", ".join(map(str, left)))
    except (OSError, shutil.Error) as error:
        say(f"swap failed, rolling back: {error}")
        restore()
        return 2
    for entry in entries:
        say(f"swapped {entry['path']} (link to {entry['target']}) for a copy")
    return 0


def restore():
    record = record_path()
    if not record.exists():
        say(f"nothing to restore: no {record}")
        return 0
    entries = json.loads(record.read_text(encoding="utf-8"))["links"]
    failed = []
    for entry in reversed(entries):
        path, target = Path(entry["path"]), entry["target"]
        try:
            remove(path.with_name(path.name + TMP_SUFFIX))
            if path.is_symlink():
                if os.readlink(path) != target:
                    say(f"left {path}: it is now a link to {os.readlink(path)}")
                continue
            remove(path)
            os.symlink(target, path)
        except OSError as error:
            failed.append(f"{path}: {error}")
    if failed:
        say(
            "restore incomplete, record kept at "
            + str(record)
            + ": "
            + "; ".join(failed)
        )
        return 3
    record.unlink()
    say(f"restored {len(entries)} link(s)")
    return 0


def run(command):
    if not command:
        say("usage: docker-links run -- <command> [<arg>...]")
        return 2
    received: "list[int]" = []
    children: "list[subprocess.Popen[bytes]]" = []

    def on_signal(signum, *_):
        received.append(signum)
        for child in children:
            if child.poll() is None:
                child.send_signal(signum)

    previous = {sig: signal.signal(sig, on_signal) for sig in SIGNALS}
    try:
        code = swap()
        if code != 0:
            return code
        try:
            if not received:
                children.append(subprocess.Popen(command))
                code = children[0].wait()
        except OSError as error:
            say(f"could not start {command[0]}: {error}")
            code = 127
        finally:
            restored = restore()
        if received:
            return 128 + received[0]
        if restored != 0:
            return restored
        return code if code >= 0 else 128 - code
    finally:
        for sig, handler in previous.items():
            signal.signal(sig, handler)


def main(argv):
    if sys.version_info < MIN_PYTHON:
        say("needs Python %d.%d or newer" % MIN_PYTHON)
        return 2
    if argv[:1] == ["run"]:
        rest = argv[1:]
        return run(rest[1:] if rest[:1] == ["--"] else rest)
    if argv == ["swap"]:
        return swap()
    if argv == ["restore"]:
        return restore()
    say("usage: docker-links run -- <command> [<arg>...] | swap | restore")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

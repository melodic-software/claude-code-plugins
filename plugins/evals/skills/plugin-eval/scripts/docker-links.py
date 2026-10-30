#!/usr/bin/env python3
"""docker-links - swap the Docker credential store's links for real copies for one run.

    docker-links run -- <command> [<arg>...]
    docker-links restore

The store is $HOME/.docker. `run` replaces every symbolic link the preflight's
`find "$HOME/.docker/" -mindepth 1 -type l` would list, or the store itself when
it is a link, with a dereferenced copy of its target (a dangling link is
removed for the run and recreated after), runs the command (no
shell), and puts the links back when it exits, fails, or the wrapper gets
SIGINT, SIGTERM or SIGHUP, which it forwards to the command first.

Before anything is replaced, each link's literal value is written to the
manifest $HOME/.docker-link-swap.json, which also lists the live runs holding
the copies, each by its wrapper's pid and its command's. Every change to it
happens under an exclusive lock on $HOME/.docker-link-swap.lock. Overlapping
runs share one swap: the first swaps, later ones join, and the last to leave
restores. A holder whose wrapper and command are both gone (SIGKILL, a forced
stop) is pruned, so the next run's start, or `restore`, puts back what a
killed run left. `restore` refuses while a live run holds the
copies.

The copies are throwaway: anything written into them is discarded at restore,
and the link targets are only read. A path that is a link again at restore time
(Docker Desktop recreates its links) is left as it is. DOCKER_CONFIG is never
read or set.

Exit: `run` exits with the command's code, or 128 + the signal number; 0 for a
done `restore`; 2 refused with nothing changed (no store, a live holder for
`restore`, a failed swap rolled back); 3 a restore step failed,
the manifest is kept and names what is left.
"""

import fcntl
import json
import os
import shutil
import signal
import subprocess
import sys
from contextlib import contextmanager
from pathlib import Path

MIN_PYTHON = (3, 8)
TMP_SUFFIX = ".link-swap-tmp"
SIGNALS = (signal.SIGINT, signal.SIGTERM, signal.SIGHUP)


def store_path():
    return Path.home() / ".docker"


def manifest_path():
    return Path.home() / ".docker-link-swap.json"


def say(message):
    print(f"docker-links: {message}", file=sys.stderr)


@contextmanager
def locked():
    with open(Path.home() / ".docker-link-swap.lock", "a", encoding="utf-8") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock, fcntl.LOCK_UN)


def start_time(pid):
    """The process's start time from /proc, so a reused pid is not a live holder."""
    try:
        stat = Path(f"/proc/{pid}/stat").read_text(encoding="utf-8")
    except OSError:
        return None
    return stat.rsplit(")", 1)[1].split()[19]


def process_live(process):
    try:
        os.kill(process["pid"], 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        pass
    return process.get("start") is None or start_time(process["pid"]) == process["start"]


def is_live(holder):
    """A holder is live while its wrapper or the command it started runs, so a
    wrapper killed alone does not free the copies under its command."""
    child = holder.get("child")
    return process_live(holder) or (child is not None and process_live(child))


def load():
    path = manifest_path()
    if not path.exists():
        return None
    state = json.loads(path.read_text(encoding="utf-8"))
    state["holders"] = [h for h in state.get("holders", []) if is_live(h)]
    return state


def save(state):
    path = manifest_path()
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(json.dumps(state, indent=2) + "\n", encoding="utf-8")
    os.replace(tmp, path)


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


def restore_links(state):
    """Put every recorded link back; delete the manifest only when all are back."""
    failed = []
    for entry in reversed(state["links"]):
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
        state["holders"] = []
        save(state)
        say(
            f"restore incomplete, manifest kept at {manifest_path()}: "
            + "; ".join(failed)
        )
        return 3
    manifest_path().unlink()
    say(f"restored {len(state['links'])} link(s)")
    return 0


def acquire(me):
    """Join a live swap, or restore a killed run's leftover and swap afresh."""
    state = load()
    if state is not None and state["holders"]:
        others = ", ".join(str(h["pid"]) for h in state["holders"])
        state["holders"].append(me)
        save(state)
        say(f"joined the swap held by pid {others}")
        return 0
    if state is not None:
        say("restored a killed run's swap before starting")
        code = restore_links(state)
        if code != 0:
            return code
    store = store_path()
    if not (store.exists() or store.is_symlink()):
        say(f"refused: no store at {store}")
        return 2
    links = find_links(store)
    state = {
        "links": [
            {"path": str(p), "target": os.readlink(p), "dangling": not p.exists()}
            for p in links
        ],
        "holders": [me],
    }
    save(state)
    try:
        for path in links:
            if path.exists():
                replace_with_copy(path)
            else:
                path.unlink()
        left = find_links(store)
        if left:
            raise OSError("links remain after the swap: " + ", ".join(map(str, left)))
    except (OSError, shutil.Error) as error:
        say(f"swap failed, rolling back: {error}")
        restore_links(state)
        return 2
    for entry in state["links"]:
        done = (
            "removed the dangling link" if entry["dangling"] else "swapped for a copy"
        )
        say(f"{done} {entry['path']} (link to {entry['target']})")
    return 0


def same(holder, me):
    return (holder["pid"], holder.get("start")) == (me["pid"], me["start"])


def track(me):
    """Record the started command on this run's holder entry."""
    state = load()
    if state is None:
        return
    state["holders"] = [me if same(h, me) else h for h in state["holders"]]
    save(state)


def release(me):
    state = load()
    if state is None:
        return 0
    state["holders"] = [h for h in state["holders"] if not same(h, me)]
    if state["holders"]:
        save(state)
        return 0
    return restore_links(state)


def restore():
    with locked():
        state = load()
        if state is None:
            say(f"nothing to restore: no {manifest_path()}")
            return 0
        if state["holders"]:
            pids = ", ".join(str(h["pid"]) for h in state["holders"])
            say(f"refused: live run(s) still hold the copies: pid {pids}")
            return 2
        return restore_links(state)


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
    me = {"pid": os.getpid(), "start": start_time(os.getpid())}
    try:
        with locked():
            code = acquire(me)
        if code != 0:
            return code
        try:
            if not received:
                children.append(subprocess.Popen(command))
                pid = children[0].pid
                me["child"] = {"pid": pid, "start": start_time(pid)}
                with locked():
                    track(me)
                code = children[0].wait()
        except OSError as error:
            say(f"could not start {command[0]}: {error}")
            code = 127
        finally:
            with locked():
                restored = release(me)
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
    if argv == ["restore"]:
        return restore()
    say("usage: docker-links run -- <command> [<arg>...] | restore")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

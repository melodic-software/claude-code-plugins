#!/usr/bin/env python3
"""List a process's descendant tree and flag processes waiting on stdin.

Usage: check-child-input-wait.py <root-pid>

Prints one JSON object on stdout:
  {"root": <pid>, "platform": "...", "processes": [{"pid", "ppid", "depth",
   "command", "waiting_on_input"}], "waiting": [<pid>...], "unknown": [<pid>...]}

``waiting_on_input`` is "yes", "no" or "unknown". "unknown" means the platform
gave no readable signal for that process (an elevated process the session
cannot inspect, or a platform with no signal); it is never reported as "no".

Exit codes:
  0 - tree listed, every process answered "no"
  1 - at least one process is waiting on input ("yes")
  2 - bad arguments, or the root pid is not running
  3 - the process table could not be read
  4 - none waiting, but at least one verdict is "unknown"

Signals: Linux reads /proc/<pid>/syscall and reports "yes" when the process is
blocked in read(2) on fd 0, falling back to /proc/<pid>/wchan. macOS reads the
table with ps and answers "no" for a running or zombie process, else "unknown".
Windows lists the tree through PowerShell and answers "unknown" throughout.
"""

from __future__ import annotations

import json
import os
import platform
import subprocess
import sys

READ_SYSCALL = {"x86_64": 0, "amd64": 0, "aarch64": 63, "arm64": 63}
# nanosleep, clock_nanosleep, wait4, waitid: sleeping or waiting on a child.
NO_INPUT_SYSCALLS = {
    "x86_64": (35, 230, 61, 247),
    "amd64": (35, 230, 61, 247),
    "aarch64": (101, 115, 260, 95),
    "arm64": (101, 115, 260, 95),
}
WAIT_WCHAN ={"pipe_read", "pipe_wait", "n_tty_read", "wait_woken"}


def _linux_table() -> dict[int, tuple[int, str]]:
    table = {}
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/stat", "rb") as fh:
                stat = fh.read().decode("utf-8", "replace")
            ppid = int(stat.rsplit(")", 1)[1].split()[1])
            with open(f"/proc/{name}/cmdline", "rb") as fh:
                raw = fh.read()
        except (OSError, ValueError, IndexError):
            continue
        cmd = raw.replace(b"\0", b" ").decode("utf-8", "replace").strip()
        if not cmd:
            try:
                with open(f"/proc/{name}/comm", "rb") as fh:
                    cmd = f"[{fh.read().decode('utf-8', 'replace').strip()}]"
            except OSError:
                continue
        table[int(name)] = (ppid, cmd)
    return table


def _linux_verdict(pid: int) -> str:
    try:
        with open(f"/proc/{pid}/stat", "rb") as fh:
            state = fh.read().decode("utf-8", "replace").rsplit(")", 1)[1].split()[0]
    except (OSError, IndexError):
        return "unknown"
    if state in ("Z", "X"):
        return "no"
    want = READ_SYSCALL.get(platform.machine().lower())
    try:
        with open(f"/proc/{pid}/syscall", "r") as fh:
            parts = fh.read().split()
    except OSError:
        parts = []
    if want is not None and parts:
        if parts[0] == "running":
            return "no"
        try:
            nr = int(parts[0])
            fd = int(parts[1], 16)
        except (ValueError, IndexError):
            return "unknown"
        if nr == want and fd == 0:
            return "yes"
        # Only a known non-input wait is "no": a poll, epoll or futex wait may
        # be a prompt read on another thread or through an event loop.
        return "no" if nr in NO_INPUT_SYSCALLS.get(platform.machine().lower(), ()) else "unknown"
    try:
        with open(f"/proc/{pid}/wchan", "r") as fh:
            wchan = fh.read().strip()
    except OSError:
        return "unknown"
    return "yes" if wchan in WAIT_WCHAN else "unknown"


def _ps_table() -> tuple[dict[int, tuple[int, str]], dict[int, str]]:
    out = subprocess.run(
        ["ps", "-axo", "pid=,ppid=,stat=,command="],
        capture_output=True, text=True, check=True,
    ).stdout
    table, states = {}, {}
    for line in out.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 3:
            continue
        pid, ppid = int(parts[0]), int(parts[1])
        table[pid] = (ppid, parts[3] if len(parts) > 3 else "")
        states[pid] = parts[2]
    return table, states


def _windows_table() -> dict[int, tuple[int, str]]:
    script = (
        "Get-CimInstance Win32_Process | "
        "Select-Object ProcessId,ParentProcessId,CommandLine,Name | ConvertTo-Json -Compress"
    )
    out = subprocess.run(
        ["powershell", "-NoProfile", "-Command", script],
        capture_output=True, text=True, check=True,
    ).stdout
    rows = json.loads(out)
    if isinstance(rows, dict):
        rows = [rows]
    return {
        int(r["ProcessId"]): (int(r["ParentProcessId"]), r.get("CommandLine") or r.get("Name") or "")
        for r in rows
    }


def descendants(table: dict[int, tuple[int, str]], root: int) -> list[tuple[int, int]]:
    kids: dict[int, list[int]] = {}
    for pid, (ppid, _) in table.items():
        kids.setdefault(ppid, []).append(pid)
    order, stack, seen = [], [(root, 0)], {root}
    while stack:
        pid, depth = stack.pop()
        order.append((pid, depth))
        for child in sorted(kids.get(pid, []), reverse=True):
            if child not in seen:
                seen.add(child)
                stack.append((child, depth + 1))
    return order


def main(argv: list[str]) -> int:
    if len(argv) != 2 or not argv[1].isdigit():
        print("usage: check-child-input-wait.py <root-pid>", file=sys.stderr)
        return 2
    root = int(argv[1])
    system = platform.system()
    states: dict[int, str] = {}
    try:
        if system == "Linux":
            table = _linux_table()
        elif system == "Darwin":
            table, states = _ps_table()
        elif system == "Windows":
            table = _windows_table()
        else:
            print(f"unsupported platform: {system}", file=sys.stderr)
            return 3
    except (OSError, subprocess.CalledProcessError, ValueError, KeyError) as exc:
        print(f"could not read the process table: {exc}", file=sys.stderr)
        return 3
    if root not in table:
        print(f"pid {root} is not running", file=sys.stderr)
        return 2

    procs = []
    for pid, depth in descendants(table, root):
        if system == "Linux":
            verdict = _linux_verdict(pid)
        elif system == "Darwin":
            verdict = "no" if states.get(pid, "")[:1] in ("R", "Z") else "unknown"
        else:
            verdict = "unknown"
        procs.append({
            "pid": pid, "ppid": table[pid][0], "depth": depth,
            "command": table[pid][1], "waiting_on_input": verdict,
        })
    waiting = [p["pid"] for p in procs if p["waiting_on_input"] == "yes"]
    unknown = [p["pid"] for p in procs if p["waiting_on_input"] == "unknown"]
    json.dump({"root": root, "platform": system, "processes": procs,
               "waiting": waiting, "unknown": unknown}, sys.stdout)
    print()
    return 1 if waiting else 4 if unknown else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))

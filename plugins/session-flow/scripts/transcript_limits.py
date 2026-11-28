# GENERATED from lib/transcript_limits.py by scripts/sync-shared-copies.sh. Do not edit this copy:
# edit the canonical source, then rerun the script.
# -*- coding: utf-8 -*-
"""The per-host reader locks and the resource limits a reading child enforces on itself.

`transcript_run` re-exports every name here and documents them; the reading child loads this
module before it (`transcript_run.MODULES`). Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import errno
import os
import shutil
import socket
import struct
import subprocess
import sys
import threading
import time
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from transcript_sources import PLATFORMS, HostLimits

try:
    import fcntl
except ImportError:
    fcntl = None
try:
    import resource
except ImportError:
    resource = None

LOCK_NAME = "claude-transcript-run"
IONICE_TIMEOUT_S = 10
LINUX_PLATFORMS = frozenset({"linux", "wsl"})
PROBE_TIMEOUT_S = 0.5
SANDBOX_ERRNOS = frozenset({errno.EACCES, errno.EPERM, errno.EROFS})
ENFORCEMENT: dict[str, dict[str, str]] = {
    "memory_ceiling": dict.fromkeys(PLATFORMS, "rss-check"),
    "backstop": dict.fromkeys(LINUX_PLATFORMS, "rlimit-as"),
    "cpu_priority": {"linux": "nice", "wsl": "nice", "macos": "nice"},
    "disk_priority": dict.fromkeys(LINUX_PLATFORMS, "ionice"),
}


@dataclass
class HostLock:
    """One lock a reader holds: `mechanism` is `abstract-socket`, `data-dir-flock` or `missing`.

    A lock not acquired names the gap it means in `gap` (None for `busy`) and why in `detail`.
    """

    mechanism: str
    acquired: bool
    holder_pid: int | None = None
    handle: object = None
    gap: str | None = None
    detail: str | None = None
    prober: threading.Thread | None = None

    def release(self) -> None:
        if isinstance(self.handle, socket.socket):
            try:
                self.handle.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass
            self.handle.close()
            if self.prober is not None:
                self.prober.join(timeout=PROBE_TIMEOUT_S * 4)
        elif isinstance(self.handle, int):
            os.close(self.handle)
        self.handle = None


def local_lock(name: str = LOCK_NAME, platform: str = sys.platform) -> HostLock:
    """Linux holds an abstract-namespace socket (no file, gone when the process exits).

    Elsewhere the lock is `missing`, declared in diagnostics: no file is created, so a remote read
    writes nothing, and a local read still holds `data_dir_lock`.
    """
    if platform.startswith("linux"):
        name = f"{name}.{os.getuid()}"
        holder = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        try:
            holder.bind("\0" + name)
            holder.listen(8)
        except OSError:
            holder.close()
            return HostLock("abstract-socket", False, _holder_pid(name))
        prober = threading.Thread(target=_answer_probes, args=(holder,), daemon=True)
        prober.start()
        return HostLock("abstract-socket", True, handle=holder, prober=prober)
    return HostLock("missing", True)


def data_dir_lock(path: str) -> HostLock:
    if fcntl is None:
        return HostLock("missing", True)
    try:
        fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    except OSError as exc:
        return _data_lock_refused(exc)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        os.close(fd)
        return HostLock("data-dir-flock", False, detail="another local reader holds the data-dir lock")
    except OSError as exc:
        os.close(fd)
        return _data_lock_refused(exc)
    return HostLock("data-dir-flock", True, handle=fd)


def _data_lock_refused(exc: OSError) -> HostLock:
    if exc.errno in SANDBOX_ERRNOS:
        detail = "the data-dir lock cannot be created or locked here; rerun outside the sandbox"
        return HostLock("data-dir-flock", False, gap="sandboxed", detail=detail)
    return HostLock("data-dir-flock", False, gap="unreadable", detail=f"the data-dir lock could not be opened ({type(exc).__name__})")


def _answer_probes(holder: socket.socket) -> None:
    """Accept and close each probe, so a queue of waiting readers never fills the backlog."""
    while True:
        try:
            conn, _ = holder.accept()
        except OSError:
            return
        conn.close()


def _holder_pid(name: str) -> int | None:
    peercred = getattr(socket, "SO_PEERCRED", None)
    if peercred is None:
        return None
    probe = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    probe.settimeout(PROBE_TIMEOUT_S)
    try:
        probe.connect("\0" + name)
        pid, _uid, _gid = struct.unpack("3i", probe.getsockopt(socket.SOL_SOCKET, peercred, struct.calcsize("3i")))
    except OSError:
        return None
    finally:
        probe.close()
    return pid or None


def peak_rss_bytes() -> int | None:
    """This process's peak resident memory.

    Linux's `VmHWM` comes first: `ru_maxrss` survives `execve`, so a child spawned from a large
    parent reports the parent's peak.
    """
    peak = _proc_bytes("/proc/self/status", "VmHWM")
    if peak is not None:
        return peak
    if resource is None:
        return _win_process_memory()[0]
    peak = resource.getrusage(resource.RUSAGE_SELF).ru_maxrss
    return peak if sys.platform == "darwin" else peak * 1024


def _proc_bytes(path: str, field_name: str) -> int | None:
    """A `<field>: <n> kB` line of a /proc file, in bytes."""
    try:
        text = Path(path).read_text(encoding="ascii", errors="replace")
    except OSError:
        return None
    for line in text.splitlines():
        name, _, value = line.partition(":")
        if name == field_name:
            words = value.split()
            return int(words[0]) * 1024 if words and words[0].isdigit() else None
    return None


def current_rss() -> int | None:
    """This process's resident memory; where only the peak is reported (macOS), the peak."""
    rss = _proc_bytes("/proc/self/status", "VmRSS")
    if rss is not None:
        return rss
    if sys.platform == "win32":
        return _win_process_memory()[1]
    return peak_rss_bytes()


def physical_memory() -> int | None:
    if sys.platform == "win32":
        return _win_physical_memory()
    try:
        return os.sysconf("SC_PAGE_SIZE") * os.sysconf("SC_PHYS_PAGES")
    except (ValueError, OSError):
        return None


def _win_process_memory() -> tuple[int | None, int | None]:
    """The (peak, current) working set of this process, from `K32GetProcessMemoryInfo`.

    Layout: https://learn.microsoft.com/en-us/windows/win32/api/psapi/ns-psapi-process_memory_counters
    """
    if sys.platform != "win32":
        return None, None
    import ctypes
    from ctypes import wintypes

    class Counters(ctypes.Structure):
        _fields_ = [
            ("cb", wintypes.DWORD),
            ("PageFaultCount", wintypes.DWORD),
            *((name, ctypes.c_size_t) for name in (
                "PeakWorkingSetSize", "WorkingSetSize", "QuotaPeakPagedPoolUsage", "QuotaPagedPoolUsage",
                "QuotaPeakNonPagedPoolUsage", "QuotaNonPagedPoolUsage", "PagefileUsage", "PeakPagefileUsage",
            )),
        ]

    kernel32 = ctypes.WinDLL("kernel32")
    kernel32.GetCurrentProcess.restype = wintypes.HANDLE
    kernel32.K32GetProcessMemoryInfo.argtypes = [wintypes.HANDLE, ctypes.POINTER(Counters), wintypes.DWORD]
    counters = Counters(cb=ctypes.sizeof(Counters))
    if not kernel32.K32GetProcessMemoryInfo(kernel32.GetCurrentProcess(), ctypes.byref(counters), counters.cb):
        return None, None
    return counters.PeakWorkingSetSize, counters.WorkingSetSize


def _win_physical_memory() -> int | None:
    """Total physical memory, from `GlobalMemoryStatusEx`.

    Layout: https://learn.microsoft.com/en-us/windows/win32/api/sysinfoapi/ns-sysinfoapi-memorystatusex
    """
    if sys.platform != "win32":
        return None
    import ctypes
    from ctypes import wintypes

    class Status(ctypes.Structure):
        _fields_ = [
            ("dwLength", wintypes.DWORD),
            ("dwMemoryLoad", wintypes.DWORD),
            *((name, ctypes.c_ulonglong) for name in (
                "ullTotalPhys", "ullAvailPhys", "ullTotalPageFile", "ullAvailPageFile",
                "ullTotalVirtual", "ullAvailVirtual", "ullAvailExtendedVirtual",
            )),
        ]

    kernel32 = ctypes.WinDLL("kernel32")
    kernel32.GlobalMemoryStatusEx.argtypes = [ctypes.POINTER(Status)]
    status = Status(dwLength=ctypes.sizeof(Status))
    return status.ullTotalPhys if kernel32.GlobalMemoryStatusEx(ctypes.byref(status)) else None


def memory_ceiling(platform: str, limits: HostLimits, prior_peak: int | None) -> tuple[int | None, str]:
    """The resident-memory ceiling for one read and its basis.

    The configured ceiling is `memory_bytes`, else `memory_fraction` of `MemAvailable` on Linux and
    of physical memory elsewhere; a prior peak times `peak_headroom` replaces it when lower.
    """
    if limits.memory_bytes is not None:
        configured, basis = limits.memory_bytes, "configured"
    elif limits.memory_fraction is None:
        return None, "unset"
    else:
        available = _proc_bytes("/proc/meminfo", "MemAvailable") if platform in LINUX_PLATFORMS else None
        total = available if available is not None else physical_memory()
        if total is None:
            return None, "unknown"
        configured = int(total * limits.memory_fraction)
        basis = "fraction-of-MemAvailable" if available is not None else "fraction-of-physical"
    if prior_peak is not None and int(prior_peak * limits.peak_headroom) < configured:
        return int(prior_peak * limits.peak_headroom), "prior-peak"
    return configured, basis


@dataclass(frozen=True)
class AppliedLimits:
    applied: dict
    missing: dict[str, str]
    ceiling: int | None


class _Unavailable(Exception):
    """A limit this process cannot enforce; the message says why."""


def _rss_check(limits: HostLimits, ceiling: int | None, basis: str) -> dict:
    if ceiling is None:
        raise _Unavailable(f"no memory figure to set the ceiling from ({basis})")
    if current_rss() is None:
        raise _Unavailable("this host reports no resident memory for the reader")
    return {"memory_bytes": ceiling, "memory_basis": basis, "check_every_records": limits.check_every_records}


def _rlimit_as(limits: HostLimits, ceiling: int | None, _basis: str) -> dict:
    if resource is None:
        raise _Unavailable("the resource module is missing")
    size = _proc_bytes("/proc/self/status", "VmSize")
    if ceiling is None or size is None:
        raise _Unavailable("no ceiling, or no address-space size, to set it from")
    cap = size + int(ceiling * limits.backstop_ratio)
    _soft, hard = resource.getrlimit(resource.RLIMIT_AS)
    if hard != resource.RLIM_INFINITY:
        cap = min(cap, hard)
    try:
        resource.setrlimit(resource.RLIMIT_AS, (cap, hard))
    except (OSError, ValueError) as exc:
        raise _Unavailable(f"RLIMIT_AS could not be set ({type(exc).__name__})") from None
    return {"backstop_bytes": cap}


def _nice(limits: HostLimits, _ceiling: int | None, _basis: str) -> dict:
    if not hasattr(os, "nice"):
        raise _Unavailable("os.nice is missing")
    try:
        os.nice(limits.nice)
    except OSError as exc:
        raise _Unavailable(f"nice failed ({type(exc).__name__})") from None
    return {"nice": limits.nice}


def _ionice(_limits: HostLimits, _ceiling: int | None, _basis: str) -> dict:
    exe = shutil.which("ionice")
    if exe is None:
        raise _Unavailable("ionice is not installed")
    try:
        done = subprocess.run(
            [exe, "-c", "2", "-n", "7", "-p", str(os.getpid())],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            timeout=IONICE_TIMEOUT_S,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        raise _Unavailable(f"ionice failed ({type(exc).__name__})") from None
    if done.returncode != 0:
        raise _Unavailable(f"ionice exited {done.returncode}")
    return {"ionice": "best-effort 7"}


ENFORCERS: dict[str, Callable[[HostLimits, int | None, str], dict]] = {
    "rss-check": _rss_check,
    "rlimit-as": _rlimit_as,
    "nice": _nice,
    "ionice": _ionice,
}


def apply_limits(platform: str, limits: HostLimits, *, prior_peak: int | None = None) -> AppliedLimits:
    """Process-wide and irreversible, so only the reading child calls it."""
    ceiling, basis = memory_ceiling(platform, limits, prior_peak)
    applied: dict[str, object] = {"read_timeout_s": limits.read_timeout_s, "slow_read_s": limits.slow_read_s}
    missing: dict[str, str] = {}
    for limit, mechanisms in ENFORCEMENT.items():
        mechanism = mechanisms.get(platform)
        if mechanism is None:
            missing[limit] = f"not enforceable on {platform}"
            continue
        try:
            applied.update(ENFORCERS[mechanism](limits, ceiling, basis))
        except _Unavailable as why:
            missing[limit] = str(why)
    return AppliedLimits(applied, missing, None if "memory_ceiling" in missing else ceiling)


class CeilingReached(Exception):
    def __init__(self, rss: int) -> None:
        super().__init__(rss)
        self.rss = rss


class DeadlineReached(Exception):
    pass


class _Meter:
    """Checks the deadline, then resident memory against the ceiling, at each file's start and every `every` records."""

    def __init__(self, ceiling: int | None, every: int, deadline: float | None = None) -> None:
        self.ceiling = ceiling
        self.every = max(1, every)
        self.deadline = deadline
        self.count = 0

    def check_deadline(self) -> None:
        if self.deadline is not None and time.monotonic() > self.deadline:
            raise DeadlineReached

    def check(self) -> None:
        self.check_deadline()
        if self.ceiling is None:
            return
        rss = current_rss()
        if rss is not None and rss > self.ceiling:
            raise CeilingReached(rss)

    def tick(self) -> None:
        self.count += 1
        if self.count % self.every == 0:
            self.check()

"""Processes that outlive their starter, on Windows, macOS and Linux. Python 3 stdlib.

`spawn` starts a command apart from this process (its own session on POSIX; a new process group
with no console on Windows, breaking away from the caller's job when allowed), so it survives the
shell, `share.py` or the server that started it. `alive` and `stop` take a pid plus a `marker`, a
word its command line (POSIX) or executable path (Windows) must contain, so a pid the OS has since
handed to another program is never reported alive or stopped; `exe_name` and `command_line` read
the program file a pid runs and its arguments. `locked` is an exclusive file lock
for the few steps two processes may race on. `which` finds a program on PATH but never in the
current folder, and `data_dir_problem` says when a folder cannot keep the session's files private.
Every OS branch of the runtime lives in this file.
"""

from __future__ import annotations

import contextlib
import ntpath
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
import time
from pathlib import Path

WINDOWS = os.name == "nt"

if WINDOWS:
    import ctypes
    import msvcrt
    from ctypes import wintypes

    _k32 = ctypes.WinDLL("kernel32", use_last_error=True)
    _k32.OpenProcess.restype = wintypes.HANDLE
    _k32.OpenProcess.argtypes = (wintypes.DWORD, wintypes.BOOL, wintypes.DWORD)
    _k32.GetExitCodeProcess.argtypes = (wintypes.HANDLE, ctypes.POINTER(wintypes.DWORD))
    _k32.QueryFullProcessImageNameW.argtypes = (wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD))
    _k32.CloseHandle.argtypes = (wintypes.HANDLE,)
    _QUERY = 0x1000  # PROCESS_QUERY_LIMITED_INFORMATION
    _STILL_ACTIVE = 259
else:
    import fcntl


def interpreter():
    """The real Python: on Windows outside a venv, the base one behind a launcher such as a uv trampoline."""
    base = getattr(sys, "_base_executable", "")
    if WINDOWS and sys.prefix == sys.base_prefix and os.path.isfile(base):
        return base
    return sys.executable


def python(*args):
    """A Python child's argv in isolated mode (-I): no PYTHON* variables, user site, or cwd on sys.path."""
    return [interpreter(), "-I", *args]


def open_private(path, mode="ab"):
    """Open a file created 0600 (advisory on Windows) for appending or, with mode "wb", truncating."""
    flags = os.O_WRONLY | os.O_CREAT | (os.O_APPEND if "a" in mode else os.O_TRUNC)
    return os.fdopen(os.open(path, flags | getattr(os, "O_BINARY", 0), 0o600), mode)


def replace_into(tmp, path):
    """os.replace with retry: Windows refuses while a reader holds the target open."""
    for _ in range(20):
        try:
            os.replace(tmp, path)
            return
        except PermissionError:
            time.sleep(0.05)
    os.unlink(tmp)
    raise OSError(f"could not replace {path}")


def write_private(path, text):
    """Atomic, durable write of a file only its owner may read (0600 where the OS has file modes).

    The bytes reach the disk before the rename, and a failed write leaves no temporary file behind.
    """
    path = Path(path)
    tmp = path.with_name(f"{path.name}.{os.getpid()}.{time.monotonic_ns()}.tmp")
    try:
        with open_private(tmp, "wb") as f:
            f.write(text.encode("utf-8"))
            f.flush()
            os.fsync(f.fileno())
        replace_into(tmp, path)
    except BaseException:
        with contextlib.suppress(OSError):
            os.unlink(tmp)
        raise


def make_private_dir(path):
    """Create `path` (and its parents) with the folder itself 0700 where the OS has file modes."""
    path = Path(path)
    path.mkdir(mode=0o700, parents=True, exist_ok=True)
    if not WINDOWS:
        os.chmod(path, 0o700)
    return path


def which(name):
    """`name` on PATH, never from the current folder: Windows searches it first unless told not to."""
    if not WINDOWS:
        return shutil.which(name)
    os.environ["NoDefaultCurrentDirectoryInExePath"] = "1"  # honored by shutil.which from Python 3.12
    found = shutil.which(name)
    if found and Path(found).resolve().parent == Path.cwd().resolve():  # older Pythons still look there
        return None
    return found


def _is_wsl():
    return bool(os.environ.get("WSL_DISTRO_NAME")) or "microsoft" in platform.uname().release.lower()


def _unescape_mount(field):
    """A /proc/self/mounts field with its octal escapes (\\040 for a space) decoded."""
    return re.sub(r"\\([0-7]{3})", lambda m: chr(int(m.group(1), 8)), field)


def _mount_table():
    """(mount point, file system type, options) per line of /proc/self/mounts; [] when unreadable."""
    try:
        lines = Path("/proc/self/mounts").read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return []
    return [(_unescape_mount(f[1]), f[2], f[3]) for f in (line.split() for line in lines) if len(f) >= 4]


def data_dir_problem(path):
    """Why `path` cannot hold the session's secrets on this OS, or None. Windows has no file modes
    here, so the folder must sit under the user profile; on WSL a DrvFs (`/mnt/<drive>`) folder
    ignores modes unless it is mounted with `metadata`."""
    if WINDOWS:
        profile = os.environ.get("USERPROFILE", "")
        where = ntpath.normcase(ntpath.realpath(str(path)))
        home = ntpath.normcase(ntpath.realpath(profile)) if profile else ""
        try:
            inside = bool(home) and ntpath.commonpath([where, home]) == home
        except ValueError:  # another drive
            inside = False
        if not inside:
            return f"the data folder {path} is outside your user profile ({profile or 'USERPROFILE is not set'}); Windows keeps it private only there"
        return None
    if not _is_wsl():
        return None
    where = os.path.realpath(path)
    mounts = [m for m in _mount_table() if where == m[0] or where.startswith(m[0].rstrip("/") + "/")]
    if not mounts:
        return None
    point, fstype, options = max(mounts, key=lambda m: len(m[0]))
    drvfs = fstype == "drvfs" or "aname=drvfs" in options
    if drvfs and "metadata" not in re.split(r"[,;]", options):
        return f"the data folder {path} is on a Windows drive ({point}) mounted without metadata, so its files cannot be made private; use a folder in the Linux file system"
    return None


def spawn(cmd, log=None, env=None, cwd=None):
    """Start cmd detached in `cwd`: no stdin, stdout and stderr to `log` (truncated) or nowhere. Returns the Popen."""
    out = open_private(log, "wb") if log else subprocess.DEVNULL
    kw = {"stdin": subprocess.DEVNULL, "stdout": out, "stderr": subprocess.STDOUT if log else subprocess.DEVNULL, "close_fds": True, "env": env, "cwd": cwd}
    try:
        if not WINDOWS:
            return subprocess.Popen(cmd, start_new_session=True, **kw)
        flags = subprocess.DETACHED_PROCESS | subprocess.CREATE_NEW_PROCESS_GROUP
        try:
            return subprocess.Popen(cmd, creationflags=flags | subprocess.CREATE_BREAKAWAY_FROM_JOB, **kw)
        except OSError:  # the job this process runs in forbids breakaway
            return subprocess.Popen(cmd, creationflags=flags, **kw)
    finally:
        if log:
            out.close()


def release(proc):
    """Stop tracking a spawned child that should run on: `alive` reaps it once it exits."""
    if proc.poll() is None:
        proc.returncode = 0  # Popen then neither warns about it nor waits for it at exit


def describe(pid):
    """The pid's command line (POSIX) or executable path (Windows), or None when it cannot be read."""
    if WINDOWS:
        h = _k32.OpenProcess(_QUERY, False, pid)
        if not h:
            return None
        try:
            size = wintypes.DWORD(32768)
            buf = ctypes.create_unicode_buffer(size.value)
            return buf.value if _k32.QueryFullProcessImageNameW(h, 0, buf, ctypes.byref(size)) else None
        finally:
            _k32.CloseHandle(h)
    try:
        return (Path("/proc") / str(pid) / "cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace").strip()
    except OSError:
        pass
    try:
        out = subprocess.run(["ps", "-o", "args=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return out.stdout.strip() or None


def exe_name(pid):
    """The file name of the program pid runs, as the OS reports it, or None when pid is not running
    or that cannot be read: /proc/<pid>/exe on Linux, `ps -o comm=` elsewhere on POSIX, the image
    path on Windows. Unlike a command line, the process cannot set it."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 or not _running(pid):
        return None
    if WINDOWS:
        seen = describe(pid)
        return ntpath.basename(seen) if seen else None
    try:
        return os.path.basename(os.readlink(f"/proc/{pid}/exe")).removesuffix(" (deleted)")
    except OSError:
        if Path("/proc/self/exe").exists():
            return None  # Linux, and the link cannot be read (another user's process)
    try:
        out = subprocess.run(["ps", "-o", "comm=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return None
    return os.path.basename(out.stdout.strip()) or None


def command_line(pid):
    """pid's arguments as a list, or None when they cannot be read: /proc/<pid>/cmdline on Linux,
    `ps -ww -o args=` elsewhere on POSIX (split on spaces), and on Windows the CommandLine the
    Win32_Process CIM class reports (split on spaces outside double quotes)."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1:
        return None
    if WINDOWS:
        query = f"(Get-CimInstance Win32_Process -Filter 'ProcessId={pid}').CommandLine"
        cmd = ["powershell", "-NoProfile", "-NonInteractive", "-Command", query]
    else:
        try:
            raw = (Path("/proc") / str(pid) / "cmdline").read_bytes()
            return raw.decode("utf-8", "replace").split("\0")[:-1] or None
        except OSError:
            pass
        cmd = ["ps", "-ww", "-o", "args=", "-p", str(pid)]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except (OSError, subprocess.SubprocessError):
        return None
    args = [a or b for a, b in re.findall(r'"([^"]*)"|(\S+)', out.stdout.strip())]
    return args or None


def _running(pid):
    """True while the pid names a process that has not exited (a zombie counts as exited)."""
    if WINDOWS:
        h = _k32.OpenProcess(_QUERY, False, pid)
        if not h:
            return False
        try:
            code = wintypes.DWORD()
            return bool(_k32.GetExitCodeProcess(h, ctypes.byref(code))) and code.value == _STILL_ACTIVE
        finally:
            _k32.CloseHandle(h)
    with contextlib.suppress(ChildProcessError, OSError):
        if os.waitpid(pid, os.WNOHANG)[0] == pid:  # our own child that exited: reap it
            return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    try:
        stat = (Path("/proc") / str(pid) / "stat").read_text()
        return stat.rsplit(")", 1)[1].split()[0] != "Z"
    except (OSError, IndexError):
        pass
    try:
        out = subprocess.run(["ps", "-o", "stat=", "-p", str(pid)], capture_output=True, text=True, timeout=5)
    except (OSError, subprocess.SubprocessError):
        return True
    return bool(out.stdout.strip()) and not out.stdout.strip().startswith("Z")


def alive(pid, marker):
    """True when pid runs and its command line or executable names `marker`."""
    if not isinstance(pid, int) or isinstance(pid, bool) or pid <= 1 or not _running(pid):
        return False
    seen = describe(pid)
    return seen is not None and marker.lower() in seen.lower()


def stop(pid, marker, wait=5.0):
    """End pid when `alive(pid, marker)`; True once it is gone. POSIX gets TERM, then KILL after `wait`."""
    if not alive(pid, marker):
        return False
    with contextlib.suppress(OSError):
        os.kill(pid, signal.SIGTERM)  # TerminateProcess on Windows
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        if not _running(pid):
            return True
        time.sleep(0.05)
    if not WINDOWS:
        with contextlib.suppress(OSError):
            os.kill(pid, signal.SIGKILL)
        deadline = time.monotonic() + wait
        while time.monotonic() < deadline and _running(pid):
            time.sleep(0.05)
    return not _running(pid)


@contextlib.contextmanager
def locked(path, timeout=30.0):
    """An exclusive lock on `path` (created 0600) across processes, waiting at most `timeout` seconds."""
    with open_private(path, "ab") as f:
        deadline = time.monotonic() + timeout
        while True:
            try:
                if WINDOWS:
                    f.seek(0)
                    msvcrt.locking(f.fileno(), msvcrt.LK_NBLCK, 1)
                else:
                    fcntl.flock(f.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise TimeoutError(f"{path} is locked by another process") from None
                time.sleep(0.05)
        try:
            yield
        finally:
            if WINDOWS:
                f.seek(0)
                msvcrt.locking(f.fileno(), msvcrt.LK_UNLCK, 1)
            else:
                fcntl.flock(f.fileno(), fcntl.LOCK_UN)

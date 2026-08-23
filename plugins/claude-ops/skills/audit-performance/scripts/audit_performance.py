#!/usr/bin/env python3
"""Read-only slowness-diagnostic capture for a Claude Code installation.

Run at the moment a machine or session feels slow. Captures, in one JSON
report, the evidence needed to separate the four documented suspects behind
Claude Code slowness: accumulated install-tree state, a version regression,
component (plugin/MCP) bloat, and the fan-out layer (hooks, statusline,
spawn cost, and subagent concurrency ceilings). Retention-sweep health and
environment facts come with it. Every phase is timed, and the timings are
themselves measurements: a census walk that takes minutes on the live tree
is the same cost the product's own retention sweep pays on that tree.

Hard rules, enforced in code:

- **Reports; never mutates.** No file under any scanned root is written,
  renamed, deleted, or touched. The engine writes only its stdout.
- **Content reads are allowlisted** to `settings.json`, `.last-cleanup`, and
  the non-secret hook manifests named in ALLOWLISTED_READS. Everything else,
  including `~/.claude.json` and `history.jsonl`, whose values can carry
  tokens and prompts, is stat-only: name, size, mtime.
- **Never runs a discovered hook, statusline command, or MCP server.** Those
  are third-party commands with arbitrary side effects, so timing one by
  executing it would make this engine a mutator. The fan-out probes
  enumerate configured commands and measure a no-op spawn baseline instead;
  attribution of a specific hook's cost is the operator's step, not ours.
- **Never elevates.** Windows Defender guidance is emitted as advisory text.

Python 3.11+, standard library only.
"""

from __future__ import annotations

import argparse
import json
import os
import shutil
import statistics
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

MIN_PYTHON = (3, 11)

ACTIVE_SESSION_WINDOW_S = 3600
STALE_SWEEP_DAYS = 2.0
SUBPROCESS_TIMEOUT_S = 20

#: Plugin install scopes, most specific first. A plugin installed at two scopes loads once.
SCOPE_PRECEDENCE = ("local", "project", "user")

#: Files whose CONTENT this engine may read. Everything else is stat-only.
ALLOWLISTED_READS = (
    "settings.json",  # install-root and project settings: sweep config, hooks, statusline, env
    ".last-cleanup",  # retention-sweep sentinel (mtime only, but read as a file)
    "hooks.json",  # a plugin's hook manifest: event, matcher, command
    "installed_plugins.json",  # plugins/installed_plugins.json: where each plugin is installed
)

#: Trivial no-op spawns, one per platform. Never a discovered hook or statusline command.
NOOP_SPAWN = {
    "win32": ["cmd", "/c", "exit"],
    "posix": ["/bin/sh", "-c", "exit 0"],
}
SPAWN_SAMPLES = 7
#: A no-op spawn floored above this is already contended before any hook runs.
SLOW_SPAWN_FLOOR_MS = 500.0
#: max/min at or above this across identical no-op spawns is the bimodal contention signature.
BIMODAL_SPREAD_RATIO = 3.0
#: Seconds between the two process-population samples that separate churn from accumulation.
POPULATION_GAP_S = 3.0
#: A process younger than this is not an orphan candidate however dead its parent looks.
ORPHAN_MIN_AGE_HOURS = 24.0
#: Orphan attribution is scoped to the debris the fan-out layer actually leaves behind:
#: the shells, console hosts, and runtimes that hooks, statusline renders, and subagents
#: spawn. A top-level desktop application normally outlives whatever launched it, so
#: sweeping every process would report a dead parent as a defect hundreds of times over.
ORPHAN_CANDIDATE_NAMES = frozenset(
    {
        "bash", "bash.exe", "sh", "sh.exe", "zsh", "dash",
        "pwsh", "pwsh.exe", "powershell", "powershell.exe",
        "cmd", "cmd.exe", "conhost.exe", "node", "node.exe", "bun", "bun.exe",
        "cygwin-console-helper.exe",
    }
)

#: Hook events that fire on every matching tool call. These scale with tool-call volume.
PER_TOOL_CALL_EVENTS = frozenset({"PreToolUse", "PostToolUse"})
#: Hook events that fire once per conversational turn. These are what make a long session degrade.
PER_TURN_EVENTS = frozenset({"Stop", "SubagentStop", "UserPromptSubmit", "Notification"})
#: Shell executables whose repeated appearance in one command line means nested shells.
SHELL_TOKENS = ("bash", "sh", "zsh", "pwsh", "powershell", "cmd")

#: Concurrency and fan-out env vars, with the default the official docs state.
#: A value of None means the variable is not documented at all, which is itself reportable.
CONCURRENCY_ENV_DEFAULTS = {
    "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS": 20,
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": 3,
    "CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS": None,
}
#: Vars gated by a JavaScript truthiness test on the raw string. In JavaScript the string
#: "0" is truthy, so setting one of these to "0" reads like a disable and is a silent no-op:
#: only ABSENCE disables them. Never advise setting one to 0.
TRUTHINESS_GATED_ENV = frozenset({"CLAUDE_CODE_EXPERIMENTAL_OBSERVER_AGENTS"})


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def default_root() -> Path:
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(env) if env else Path.home() / ".claude"


def timed(fn, *args, **kwargs):
    t0 = time.perf_counter()
    result = fn(*args, **kwargs)
    return result, round(time.perf_counter() - t0, 3)


def cli_version() -> dict:
    exe = shutil.which("claude")
    if not exe:
        return {"version": None, "error": "claude not on PATH"}
    try:
        t0 = time.perf_counter()
        out = subprocess.run(
            [exe, "--version"], capture_output=True, text=True, timeout=SUBPROCESS_TIMEOUT_S
        )
        elapsed = round(time.perf_counter() - t0, 3)
        return {
            "version": out.stdout.strip() or None,
            "exe": exe,
            "seconds": elapsed,
            "slow_version_probe": elapsed > 5.0,
        }
    except subprocess.TimeoutExpired:
        return {"version": None, "exe": exe, "error": f"--version timed out after {SUBPROCESS_TIMEOUT_S}s (itself a finding)"}
    except OSError as exc:
        return {"version": None, "exe": exe, "error": str(exc)}


def sweep_health(root: Path) -> dict:
    health: dict = {
        "settings_parse_ok": None,
        "cleanup_period_days": None,
        "cleanup_evidence": None,
        "last_cleanup_age_days": None,
        "findings": [],
    }
    settings = root / "settings.json"
    if settings.is_file():
        try:
            parsed = json.loads(settings.read_text(encoding="utf-8"))
            health["settings_parse_ok"] = True
            if isinstance(parsed, dict) and "cleanupPeriodDays" in parsed:
                health["cleanup_period_days"] = parsed["cleanupPeriodDays"]
                health["cleanup_evidence"] = "measured"
            else:
                health["cleanup_period_days"] = 30
                health["cleanup_evidence"] = "documented-default"
        except (json.JSONDecodeError, OSError):
            health["settings_parse_ok"] = False
            health["findings"].append("settings-unparsable-pauses-sweep")
    else:
        health["cleanup_period_days"] = 30
        health["cleanup_evidence"] = "documented-default"
    sentinel = root / ".last-cleanup"
    if sentinel.is_file():
        try:
            age = (utc_now().timestamp() - sentinel.stat().st_mtime) / 86400.0
            health["last_cleanup_age_days"] = round(age, 2)
            if age > STALE_SWEEP_DAYS:
                health["findings"].append("last-cleanup-stale")
        except OSError:
            pass
    else:
        health["findings"].append("last-cleanup-sentinel-absent")
    return health


def tree_census(root: Path) -> dict:
    """Timed stat-walk of the whole tree. The duration IS the sweep-cost proxy."""
    entries: dict[str, dict] = {}
    total_files = 0
    total_bytes = 0
    t0 = time.perf_counter()
    for top in sorted(root.iterdir(), key=lambda p: p.name):
        files = 0
        size = 0
        if top.is_dir() and not top.is_symlink():
            for dirpath, dirnames, filenames in os.walk(top, followlinks=False):
                files += len(filenames)
                for name in filenames:
                    try:
                        size += os.stat(os.path.join(dirpath, name)).st_size
                    except OSError:
                        pass
        elif top.is_file():
            files = 1
            try:
                size = top.stat().st_size
            except OSError:
                size = 0
        entries[top.name] = {"files": files, "mb": round(size / 1048576, 2)}
        total_files += files
        total_bytes += size
    walk_seconds = round(time.perf_counter() - t0, 3)
    top_by_files = sorted(entries.items(), key=lambda kv: kv[1]["files"], reverse=True)[:5]
    return {
        "walk_seconds": walk_seconds,
        "total_files": total_files,
        "total_mb": round(total_bytes / 1048576, 2),
        "files_per_second": round(total_files / walk_seconds, 0) if walk_seconds > 0 else None,
        "top_entries_by_file_count": dict(top_by_files),
        "note": "walk_seconds approximates one retention-sweep stat pass over this tree on this volume right now",
    }


def home_root_state() -> dict:
    """Stat-only. Values inside these files are never read."""
    home = Path.home()
    out: dict = {"note": "stat-only by contract; values never read"}
    for name in (".claude.json", ".claude.json.backup"):
        p = home / name
        if p.is_file():
            st = p.stat()
            out[name] = {
                "kb": round(st.st_size / 1024, 1),
                "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(timespec="seconds"),
            }
    remnants = [p.name for p in home.glob(".claude.json.tmp.*")]
    out["tmp_remnants"] = {"count": len(remnants), "sample": remnants[:5]}
    return out


def history_state(root: Path) -> dict:
    p = root / "history.jsonl"
    if not p.is_file():
        return {"present": False}
    st = p.stat()
    return {
        "present": True,
        "mb": round(st.st_size / 1048576, 2),
        "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(timespec="seconds"),
        "note": "stat-only (contains every prompt ever typed); not covered by any retention sweep",
    }


def session_census(root: Path) -> dict:
    projects = root / "projects"
    if not projects.is_dir():
        return {"projects_present": False}
    now = utc_now().timestamp()
    transcripts = 0
    total_bytes = 0
    active: list[str] = []
    largest = {"path": None, "mb": 0.0}
    project_dirs = 0
    for proj in projects.iterdir():
        if not proj.is_dir():
            continue
        project_dirs += 1
        for p in proj.rglob("*.jsonl"):
            try:
                st = p.stat()
            except OSError:
                continue
            transcripts += 1
            total_bytes += st.st_size
            mb = st.st_size / 1048576
            if mb > largest["mb"]:
                largest = {"path": p.relative_to(projects).as_posix(), "mb": round(mb, 2)}
            if now - st.st_mtime < ACTIVE_SESSION_WINDOW_S and "subagents" not in p.parts:
                active.append(p.relative_to(projects).as_posix())
    return {
        "projects_present": True,
        "project_dirs": project_dirs,
        "transcript_files": transcripts,
        "transcript_mb": round(total_bytes / 1048576, 2),
        "largest_transcript": largest,
        "active_last_hour": {"count": len(active), "sample": active[:10]},
    }


def plugin_fleet(root: Path) -> dict:
    plugins = root / "plugins"
    if not plugins.is_dir():
        return {"present": False}
    out: dict = {"present": True}
    for sub in ("cache", "marketplaces", "data"):
        d = plugins / sub
        if d.is_dir():
            out[sub + "_entries"] = sum(1 for _ in d.iterdir())
    out["note"] = "counts only; enablement and scope verdicts belong to /claude-ops:plugins audit"
    return out


def _windows_process_table() -> list[dict]:
    """Snapshot pid, ppid, name, and start time via the Win32 toolhelp API.

    `tasklist` returns neither a parent pid nor a creation time, and both are
    load-bearing here: parent liveness is what separates an orphan from a
    working child, and a start time is what says whether a session predates a
    settings change. ctypes keeps the engine standard-library-only.
    """
    import ctypes
    import ctypes.wintypes as wt

    class PROCESSENTRY32W(ctypes.Structure):
        _fields_ = [
            ("dwSize", wt.DWORD),
            ("cntUsage", wt.DWORD),
            ("th32ProcessID", wt.DWORD),
            ("th32DefaultHeapID", ctypes.POINTER(ctypes.c_ulong)),
            ("th32ModuleID", wt.DWORD),
            ("cntThreads", wt.DWORD),
            ("th32ParentProcessID", wt.DWORD),
            ("pcPriClassBase", ctypes.c_long),
            ("dwFlags", wt.DWORD),
            ("szExeFile", wt.WCHAR * 260),
        ]

    class FILETIME(ctypes.Structure):
        _fields_ = [("dwLowDateTime", wt.DWORD), ("dwHighDateTime", wt.DWORD)]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    kernel32.CreateToolhelp32Snapshot.restype = wt.HANDLE
    kernel32.OpenProcess.restype = wt.HANDLE

    th32cs_snapprocess = 0x00000002
    query_limited_information = 0x1000
    epoch_offset_seconds = 11644473600  # 1601-01-01 to 1970-01-01

    def creation_epoch(pid: int) -> float | None:
        handle = kernel32.OpenProcess(query_limited_information, False, pid)
        if not handle:
            return None
        try:
            created, exited, kernel, user = FILETIME(), FILETIME(), FILETIME(), FILETIME()
            ok = kernel32.GetProcessTimes(
                handle,
                ctypes.byref(created),
                ctypes.byref(exited),
                ctypes.byref(kernel),
                ctypes.byref(user),
            )
            if not ok:
                return None
            ticks = (created.dwHighDateTime << 32) | created.dwLowDateTime
            if ticks == 0:
                return None
            return ticks / 1e7 - epoch_offset_seconds
        finally:
            kernel32.CloseHandle(handle)

    snapshot = kernel32.CreateToolhelp32Snapshot(th32cs_snapprocess, 0)
    if snapshot == ctypes.c_void_p(-1).value:
        raise OSError(ctypes.get_last_error(), "CreateToolhelp32Snapshot failed")
    entry = PROCESSENTRY32W()
    entry.dwSize = ctypes.sizeof(PROCESSENTRY32W)
    rows: list[dict] = []
    try:
        more = kernel32.Process32FirstW(snapshot, ctypes.byref(entry))
        while more:
            pid = int(entry.th32ProcessID)
            rows.append(
                {
                    "pid": pid,
                    "ppid": int(entry.th32ParentProcessID),
                    "name": entry.szExeFile,
                    "started_epoch": creation_epoch(pid),
                }
            )
            more = kernel32.Process32NextW(snapshot, ctypes.byref(entry))
    finally:
        kernel32.CloseHandle(snapshot)
    return rows


def _posix_process_table() -> list[dict]:
    """Snapshot pid, ppid, name, and start time via `ps` elapsed time."""
    out = subprocess.run(
        ["ps", "-eo", "pid=,ppid=,etime=,comm="],
        capture_output=True,
        text=True,
        timeout=SUBPROCESS_TIMEOUT_S,
    )
    now = utc_now().timestamp()
    rows: list[dict] = []
    for line in out.stdout.splitlines():
        parts = line.split(None, 3)
        if len(parts) < 4:
            continue
        pid, ppid, etime, name = parts
        try:
            rows.append(
                {
                    "pid": int(pid),
                    "ppid": int(ppid),
                    "name": name.strip(),
                    "started_epoch": now - parse_etime(etime),
                }
            )
        except ValueError:
            continue
    return rows


def parse_etime(etime: str) -> float:
    """Parse the `ps` elapsed-time field `[[dd-]hh:]mm:ss` into seconds."""
    days = 0
    text = etime.strip()
    if "-" in text:
        head, text = text.split("-", 1)
        days = int(head)
    parts = [int(p) for p in text.split(":")]
    if len(parts) == 2:
        hours, minutes, seconds = 0, parts[0], parts[1]
    elif len(parts) == 3:
        hours, minutes, seconds = parts
    else:
        raise ValueError(f"unparsable etime: {etime!r}")
    return days * 86400 + hours * 3600 + minutes * 60 + seconds


def process_table() -> tuple[list[dict], str | None]:
    """Return (records, error). Each record carries pid, ppid, name, started_epoch."""
    try:
        rows = _windows_process_table() if sys.platform == "win32" else _posix_process_table()
    except (OSError, ValueError, subprocess.SubprocessError) as exc:
        return [], f"process table unavailable: {exc}"
    return rows, None


def is_claude_process(name: str) -> bool:
    lowered = name.lower()
    return "claude" in lowered or lowered in ("node.exe", "node", "bun.exe", "bun")


def attribute_orphans(
    records: list[dict],
    now_epoch: float,
    min_age_hours: float = ORPHAN_MIN_AGE_HOURS,
    candidate_names: frozenset[str] = ORPHAN_CANDIDATE_NAMES,
) -> dict:
    """Classify long-lived fan-out debris by PARENT LIVENESS, never by age alone.

    Age alone produces false positives: a days-old console host whose parent is
    a running device manager is working software, not debris. A process is an
    orphan only when its parent is gone. PID reuse is guarded by comparing start
    times, and a parent whose start time cannot be read yields `unknown` rather
    than a guess, because a wrong orphan verdict routes a live process to a kill.

    A parent pid of 0 means no parent was recorded rather than a parent that
    died, so those are skipped instead of convicted.
    """
    by_pid = {r["pid"]: r for r in records}
    orphans: list[dict] = []
    live_parent: list[dict] = []
    unknown: list[dict] = []
    for record in records:
        if record["name"].lower() not in candidate_names:
            continue
        if record.get("ppid", 0) <= 0:
            continue
        started = record.get("started_epoch")
        if started is None:
            continue
        age_hours = (now_epoch - started) / 3600.0
        if age_hours < min_age_hours:
            continue
        parent = by_pid.get(record["ppid"])
        summary = {
            "name": record["name"],
            "pid": record["pid"],
            "ppid": record["ppid"],
            "age_hours": round(age_hours, 1),
        }
        if parent is None:
            summary["parent_alive"] = False
            orphans.append(summary)
            continue
        parent_started = parent.get("started_epoch")
        if parent_started is None:
            summary["parent_alive"] = None
            summary["reason"] = "parent start time unreadable; PID reuse cannot be excluded"
            unknown.append(summary)
        elif parent_started > started:
            # The PID was recycled: this "parent" started after its supposed child.
            summary["parent_alive"] = False
            summary["reason"] = "parent pid recycled by a newer process"
            orphans.append(summary)
        else:
            summary["parent_alive"] = True
            summary["parent_name"] = parent["name"]
            live_parent.append(summary)
    return {
        "min_age_hours": min_age_hours,
        "candidate_names": sorted(candidate_names),
        "orphans": orphans[:20],
        "orphan_count": len(orphans),
        "live_parent_count": len(live_parent),
        "live_parent_sample": live_parent[:10],
        "unknown_count": len(unknown),
        "unknown_sample": unknown[:10],
        "note": (
            "Only a dead-parent process is an orphan. Live-parent processes of the same age "
            "are working software; killing them breaks whatever owns them. Scoped to the shells, "
            "console hosts, and runtimes the fan-out layer spawns, because a top-level "
            "application normally outlives its launcher and is not debris for having done so. "
            "This engine reports and never kills."
        ),
    }


def population_trend(sample_a: list[dict], sample_b: list[dict], gap_seconds: float) -> dict:
    """Separate accumulation from churn using two snapshots taken seconds apart.

    A rising count with nothing exiting is accumulation. A flat or falling count
    with many pids replaced is churn, which looks identical in a single sample
    and means something entirely different.
    """
    def index(sample: list[dict]) -> dict[str, set[int]]:
        grouped: dict[str, set[int]] = {}
        for record in sample:
            grouped.setdefault(record["name"], set()).add(record["pid"])
        return grouped

    first, second = index(sample_a), index(sample_b)
    rows = []
    for name in sorted(set(first) | set(second)):
        pids_a, pids_b = first.get(name, set()), second.get(name, set())
        exited, started = len(pids_a - pids_b), len(pids_b - pids_a)
        delta = len(pids_b) - len(pids_a)
        if exited == 0 and started == 0:
            verdict = "steady"
        elif exited == 0 and delta > 0:
            verdict = "accumulating"
        elif exited > 0 and started > 0:
            verdict = "churn"
        else:
            verdict = "draining" if delta < 0 else "growing"
        rows.append(
            {
                "name": name,
                "count_first": len(pids_a),
                "count_second": len(pids_b),
                "delta": delta,
                "exited": exited,
                "started": started,
                "verdict": verdict,
            }
        )
    rows.sort(key=lambda r: (r["exited"] + r["started"], r["count_second"]), reverse=True)
    return {
        "gap_seconds": gap_seconds,
        "most_active": rows[:10],
        "note": (
            "A count that rises with nothing exiting is accumulation; a count that holds while "
            "pids turn over is churn. One sample cannot tell them apart."
        ),
    }


def summarize_spawn_samples(
    durations_ms: list[float], timeouts: int, concurrent_processes: int | None
) -> dict:
    """Reduce repeated no-op spawn timings to min/median/max plus a load label.

    A single spawn number is misleading because the floor itself moves with
    machine load: the same no-op that costs ~120 ms on a drained box costs
    ~1,100 ms under contention. Every reading here is labelled with the process
    count observed at sample time so a reader cannot mistake a storm-state
    number for a baseline.
    """
    result: dict = {
        "samples": len(durations_ms),
        "timeouts": timeouts,
        "concurrent_processes_at_sample": concurrent_processes,
        "state_label": "as-sampled",
        "findings": [],
    }
    if not durations_ms:
        result["findings"].append("no-spawn-samples-captured")
        return result
    low, high = min(durations_ms), max(durations_ms)
    result["min_ms"] = round(low, 1)
    result["median_ms"] = round(statistics.median(durations_ms), 1)
    result["max_ms"] = round(high, 1)
    result["spread_ratio"] = round(high / low, 2) if low > 0 else None
    if low > SLOW_SPAWN_FLOOR_MS:
        result["findings"].append("slow-spawn-floor")
    # A wide RATIO alone is not the contention signature: on a healthy machine a cold
    # first spawn against a warm second one clears 3x while every sample is still fast.
    # The signature is a wide spread whose slow mode is itself slow, so the absolute
    # ceiling has to clear the floor threshold too.
    if (
        result["spread_ratio"] is not None
        and result["spread_ratio"] >= BIMODAL_SPREAD_RATIO
        and high >= SLOW_SPAWN_FLOOR_MS
    ):
        result["findings"].append("bimodal-spawn-latency")
    if timeouts:
        result["findings"].append("spawn-probe-timed-out")
    result["note"] = (
        "The floor moves with load, so compare these numbers only against another capture "
        "carrying a similar concurrent_processes_at_sample. A bimodal spread across identical "
        "no-op spawns IS the contention diagnosis."
    )
    return result


def spawn_probe(samples: int = SPAWN_SAMPLES, timeout_s: float = SUBPROCESS_TIMEOUT_S,
                load_probe=None) -> dict:
    """Time a trivial no-op spawn repeatedly. Never runs a discovered hook.

    This is the baseline every hook, statusline render, and subagent pays before
    it does any work of its own. Timing an actual hook would mean executing a
    third-party command with arbitrary side effects, which this engine will not do.
    """
    command = NOOP_SPAWN["win32"] if sys.platform == "win32" else NOOP_SPAWN["posix"]
    durations: list[float] = []
    timeouts = 0
    for _ in range(samples):
        started = time.perf_counter()
        try:
            subprocess.run(command, capture_output=True, timeout=timeout_s)
        except subprocess.TimeoutExpired:
            timeouts += 1
            durations.append(timeout_s * 1000.0)
            continue
        except OSError:
            break
        durations.append((time.perf_counter() - started) * 1000.0)
    load = load_probe() if load_probe else None
    summary = summarize_spawn_samples(durations, timeouts, load)
    summary["command"] = " ".join(command)
    return summary


def process_census(records: list[dict] | None = None, error: str | None = None) -> dict:
    """Counts plus orphan attribution by parent liveness and a churn-vs-growth read."""
    if records is None:
        records, error = process_table()
    if error:
        return {"error": error}
    claude = [r for r in records if "claude" in r["name"].lower()]
    runtime = [r for r in records if is_claude_process(r["name"]) and r not in claude]
    census: dict = {
        "total_processes": len(records),
        "claude_processes": len(claude),
        "claude_sample": [
            {"name": r["name"], "pid": r["pid"], "ppid": r["ppid"]} for r in claude[:10]
        ],
        "node_or_bun": len(runtime),
    }
    census["orphan_attribution"] = attribute_orphans(records, utc_now().timestamp())
    return census


def read_json(path: Path) -> tuple[dict | None, str | None]:
    """Read one allowlisted JSON config file. Returns (parsed, error)."""
    if path.name not in ALLOWLISTED_READS:
        raise AssertionError(f"content read outside the allowlist: {path.name}")
    if not path.is_file():
        return None, None
    try:
        parsed = json.loads(path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError, UnicodeDecodeError) as exc:
        return None, f"{path.name}: {exc}"
    return parsed if isinstance(parsed, dict) else None, None


def flatten_hook_block(hooks_block: dict, source: str) -> list[dict]:
    """Flatten a settings-shaped `hooks` object into one record per configured command."""
    entries: list[dict] = []
    if not isinstance(hooks_block, dict):
        return entries
    for event, groups in hooks_block.items():
        if not isinstance(groups, list):
            continue
        for group in groups:
            if not isinstance(group, dict):
                continue
            matcher = group.get("matcher")
            for hook in group.get("hooks") or []:
                if not isinstance(hook, dict):
                    continue
                command = hook.get("command") or ""
                args = hook.get("args") or []
                entries.append(
                    {
                        "event": event,
                        "matcher": matcher,
                        "command": command,
                        "args": [str(a) for a in args] if isinstance(args, list) else [],
                        "timeout": hook.get("timeout"),
                        "source": source,
                    }
                )
    return entries


def invocation_shape(entry: dict) -> list[str]:
    """Name the per-spawn overhead a hook's invocation shape carries.

    Two shapes cost extra process creations before the hook's own work starts,
    and on a contended machine each spawn is the dominant cost.
    """
    findings: list[str] = []
    full = " ".join([str(entry.get("command") or "")] + list(entry.get("args") or []))
    lowered = full.replace("\\", "/").lower()
    if "/git/bin/bash" in lowered or lowered.startswith("git/bin/bash"):
        findings.append("git-bin-bash-wrapper-costs-an-extra-spawn")
    # Match the BASENAME of each token against the shell list. A suffix match would
    # count `entrypoint.sh` as a shell because it ends in "sh", which turns every
    # ordinary script invocation into a false nested-shell report.
    shell_hits = 0
    for token in lowered.replace('"', " ").replace("'", " ").split():
        basename = token.rsplit("/", 1)[-1]
        if basename.endswith(".exe"):
            basename = basename[: -len(".exe")]
        if basename in SHELL_TOKENS:
            shell_hits += 1
    if shell_hits >= 2:
        findings.append("nested-shell-invocation")
    return findings


def classify_hooks(entries: list[dict]) -> dict:
    """Bucket configured hooks by how often each event fires, never by executing one.

    Per-tool-call hooks scale with tool-call volume; per-turn hooks are what make
    a long conversation degrade, and they are the bucket a fleet audit most often
    overlooks. Hooks registered on the same event run in PARALLEL, so their
    wall-clock cost is roughly the slowest hook plus contention. Presenting hook
    cost as a sum overstates it, sometimes by several multiples.
    """
    buckets: dict[str, list[dict]] = {"per_tool_call": [], "per_turn": [], "other": []}
    by_event: dict[str, int] = {}
    shape_findings: list[dict] = []
    for entry in entries:
        event = entry.get("event") or "unknown"
        by_event[event] = by_event.get(event, 0) + 1
        if event in PER_TOOL_CALL_EVENTS:
            buckets["per_tool_call"].append(entry)
        elif event in PER_TURN_EVENTS:
            buckets["per_turn"].append(entry)
        else:
            buckets["other"].append(entry)
        findings = invocation_shape(entry)
        if findings:
            shape_findings.append(
                {
                    "event": event,
                    "matcher": entry.get("matcher"),
                    "source": entry.get("source"),
                    "findings": findings,
                }
            )

    def summarize(name: str) -> dict:
        rows = buckets[name]
        return {
            "count": len(rows),
            "matchers": sorted({str(r.get("matcher")) for r in rows if r.get("matcher")}),
            "sources": sorted({str(r.get("source")) for r in rows}),
        }

    return {
        "total": len(entries),
        "by_event": dict(sorted(by_event.items())),
        "per_tool_call": summarize("per_tool_call"),
        "per_turn": summarize("per_turn"),
        "other": summarize("other"),
        "invocation_shape_findings": shape_findings,
        "note": (
            "Hooks on one event run in parallel, so wall-clock cost is roughly the slowest hook "
            "plus contention, NOT the sum of their timings. This engine enumerates configured "
            "hooks and never executes one; a hook is third-party code with arbitrary side "
            "effects, and running it would make this capture a mutation."
        ),
    }


def winning_install_path(installs: object) -> str | None:
    """Pick the install record that actually loads, by documented scope precedence.

    `installed_plugins.json` carries one record per (plugin, scope), so counting
    every record would double-count a plugin installed at two scopes and inflate
    the hook total. Local beats project beats user, matching how the product
    resolves a plugin it finds more than once.
    """
    if not isinstance(installs, list):
        return None
    ranked = sorted(
        (i for i in installs if isinstance(i, dict) and i.get("installPath")),
        key=lambda i: SCOPE_PRECEDENCE.index(i.get("scope"))
        if i.get("scope") in SCOPE_PRECEDENCE
        else len(SCOPE_PRECEDENCE),
    )
    return str(ranked[0]["installPath"]) if ranked else None


def hook_inventory(root: Path, project_dir: Path | None = None) -> dict:
    """Resolve every hook that will fire, across settings and enabled plugins.

    Enumeration only. Reading a hook manifest is a content read, so `hooks.json`
    and `installed_plugins.json` are named in ALLOWLISTED_READS; both hold event,
    matcher, and command strings, and no credential material.
    """
    entries: list[dict] = []
    errors: list[str] = []
    settings, error = read_json(root / "settings.json")
    if error:
        errors.append(error)
    if settings:
        entries += flatten_hook_block(settings.get("hooks") or {}, "settings.json")
    if project_dir:
        project_settings, error = read_json(project_dir / ".claude" / "settings.json")
        if error:
            errors.append(error)
        if project_settings:
            entries += flatten_hook_block(
                project_settings.get("hooks") or {}, "project settings.json"
            )

    enabled = (settings or {}).get("enabledPlugins") or {}
    installed, error = read_json(root / "plugins" / "installed_plugins.json")
    if error:
        errors.append(error)
    plugins_scanned = 0
    for key, installs in ((installed or {}).get("plugins") or {}).items():
        if enabled.get(key) is not True:
            continue
        install_path = winning_install_path(installs)
        if not install_path:
            continue
        manifest, error = read_json(Path(install_path) / "hooks" / "hooks.json")
        if error:
            errors.append(error)
        if manifest:
            plugins_scanned += 1
            entries += flatten_hook_block(manifest.get("hooks") or {}, key)

    inventory = classify_hooks(entries)
    inventory["enabled_plugins"] = sum(1 for v in enabled.values() if v is True)
    inventory["plugins_contributing_hooks"] = plugins_scanned
    if errors:
        inventory["errors"] = errors
    return inventory


def statusline_config(root: Path) -> dict:
    """Report the configured statusline. Never renders it.

    The statusline is the fan-out surface that fires most often, and a render
    that is cheap on a drained machine can cost tens of seconds under contention.
    Running the command to time it would execute operator-supplied code, so this
    reports the configuration and leaves timing to the operator.
    """
    settings, error = read_json(root / "settings.json")
    if error:
        return {"error": error}
    config = (settings or {}).get("statusLine")
    if not isinstance(config, dict):
        return {"configured": False}
    command = str(config.get("command") or "")
    return {
        "configured": True,
        "type": config.get("type"),
        "command": command,
        "refresh_interval_seconds": config.get("refreshInterval"),
        "padding": config.get("padding"),
        "invocation_shape_findings": invocation_shape({"command": command, "args": []}),
        "note": (
            "refreshInterval is in SECONDS with a documented minimum of 1; renders are debounced "
            "300 ms and an in-flight render is cancelled when a new trigger arrives. Not executed "
            "by this engine: time it yourself against the spawn baseline in fan_out.spawn_cost."
        ),
    }


def concurrency_ceilings(root: Path, process_env: dict | None = None) -> dict:
    """Report fan-out ceilings against their documented defaults.

    Spawn depth MULTIPLIES against the per-session concurrency limit, so two
    settings that each look modest can license a very large subagent population.
    An undocumented variable that is nonetheless live is reported as such rather
    than silently dropped.
    """
    env = os.environ if process_env is None else process_env
    settings, error = read_json(root / "settings.json")
    settings_env = (settings or {}).get("env") or {}
    ceilings: dict = {"variables": {}, "findings": []}
    if error:
        ceilings["error"] = error
    for name, documented_default in CONCURRENCY_ENV_DEFAULTS.items():
        if name in settings_env:
            value, source = str(settings_env[name]), "settings.json env"
        elif name in env:
            value, source = str(env[name]), "engine process environment"
        else:
            value, source = None, None
        record: dict = {
            "value": value,
            "source": source,
            "documented_default": documented_default,
            "documented": documented_default is not None,
            "truthiness_gated": name in TRUTHINESS_GATED_ENV,
        }
        if value is not None and documented_default is not None:
            try:
                record["above_documented_default"] = int(value) > documented_default
            except ValueError:
                record["above_documented_default"] = None
            if record.get("above_documented_default"):
                ceilings["findings"].append(f"{name}: above the documented default")
        if value is not None and documented_default is None:
            ceilings["findings"].append(f"{name}: set but undocumented upstream")
        if value == "0" and name in TRUTHINESS_GATED_ENV:
            record["zero_is_not_a_disable"] = True
            ceilings["findings"].append(
                f"{name}: set to \"0\", which is TRUTHY in JavaScript and does not disable it"
            )
        ceilings["variables"][name] = record
    def effective(name: str) -> int | str | None:
        record = ceilings["variables"][name]
        value = record["value"]
        if value is None:
            return record["documented_default"]
        try:
            return int(value)
        except ValueError:
            return value

    ceilings["effective"] = {
        "max_concurrent_subagents_per_session": effective("CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"),
        "max_subagent_spawn_depth": effective("CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"),
        "note": (
            "Depth multiplies against the per-session concurrency limit, and every subagent "
            "carries the same statusline and hook fan-out as its parent."
        ),
    }
    ceilings["trap"] = (
        "These flags are read through a JavaScript truthiness test on the raw string, and the "
        "string \"0\" is truthy. Setting one to 0 reads like a disable in a settings file and is "
        "a silent no-op; only removing the variable disables it. Never advise setting one to 0."
    )
    return ceilings


def config_liveness(root: Path, records: list[dict]) -> dict:
    """Compare settings mtime against running session start times.

    Claude Code reads plugin enablement at startup, so a settings change made
    after a session started has not reached that session. Reading config off disk
    and describing it as the running state is how a confident and wrong report
    gets written: a toggle that looks disabled can still have every one of its
    hooks live in older sessions.
    """
    settings = root / "settings.json"
    if not settings.is_file():
        return {"settings_present": False}
    mtime = settings.stat().st_mtime
    sessions = [
        r for r in records if is_claude_process(r["name"]) and r.get("started_epoch") is not None
    ]
    stale = [r for r in sessions if r["started_epoch"] < mtime]
    result = {
        "settings_present": True,
        "settings_mtime": datetime.fromtimestamp(mtime, timezone.utc).isoformat(timespec="seconds"),
        "candidate_sessions": len(sessions),
        "sessions_predating_settings": len(stale),
        "session_identification": "process-name heuristic (claude, node, bun); not a session id",
        "stale_sample": [
            {
                "name": r["name"],
                "pid": r["pid"],
                "started_at": datetime.fromtimestamp(
                    r["started_epoch"], timezone.utc
                ).isoformat(timespec="seconds"),
            }
            for r in sorted(stale, key=lambda r: r["started_epoch"])[:10]
        ],
    }
    if stale:
        result["advisory"] = (
            f"settings.json is newer than {len(stale)} running process(es) that match the session "
            "heuristic. Plugin enablement is read at startup, so those sessions have NOT picked "
            "up the change and any hooks it disabled are still live in them. Restart is required "
            "before this configuration describes what is actually running."
        )
    else:
        result["advisory"] = (
            "No matching running process predates settings.json, so the file on disk is "
            "consistent with what the running sessions loaded."
        )
    return result


def fan_out_layer(root: Path, records: list[dict], project_dir: Path | None,
                  spawn_samples: int, timeout_s: float) -> dict:
    """The fourth suspect: what the machine pays per spawn, per hook, and per subagent."""
    return {
        "spawn_cost": spawn_probe(
            samples=spawn_samples,
            timeout_s=timeout_s,
            load_probe=lambda: len(records) or None,
        ),
        "hooks": hook_inventory(root, project_dir),
        "statusline": statusline_config(root),
        "config_liveness": config_liveness(root, records),
        "concurrency_ceilings": concurrency_ceilings(root),
    }


def advisories(root: Path) -> list[str]:
    notes = []
    if sys.platform == "win32":
        notes.append(
            "Windows Defender real-time scanning multiplies every stat/unlink under the "
            "install tree (the retention sweep pays it per file). Check Task Manager for "
            "'Antimalware Service Executable' CPU/disk while slow. Exclusion, if policy "
            f'allows, is operator-run and elevated: Add-MpPreference -ExclusionPath "{root}". '
            "Windows 11 hides exclusions from non-elevated Get-MpPreference; an empty "
            "non-admin read proves nothing. Durable home: the provisioning/dotfiles stack."
        )
    return notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", type=Path, default=None, help="install root (else $CLAUDE_CONFIG_DIR, else ~/.claude)")
    ap.add_argument("--session-id", default=None, help="current session id, for the report's capture context")
    ap.add_argument("--skip-processes", action="store_true", help="skip the process table and census")
    ap.add_argument("--skip-fan-out", action="store_true", help="skip the fan-out layer probes")
    ap.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="project root, so project-scope hooks in .claude/settings.json are counted too",
    )
    ap.add_argument(
        "--spawn-samples",
        type=int,
        default=SPAWN_SAMPLES,
        help=f"no-op spawns to time for the spawn-cost baseline (default {SPAWN_SAMPLES})",
    )
    ap.add_argument(
        "--population-gap",
        type=float,
        default=POPULATION_GAP_S,
        help=(
            f"seconds between the two process-population samples that separate churn from "
            f"accumulation (default {POPULATION_GAP_S}; 0 disables the second sample)"
        ),
    )
    ap.add_argument(
        "--subprocess-timeout",
        type=float,
        default=SUBPROCESS_TIMEOUT_S,
        help=(
            f"per-subprocess timeout in seconds (default {SUBPROCESS_TIMEOUT_S}). Raise it on a "
            "machine so contended that the probes themselves time out; a timeout is recorded as "
            "a finding, never dropped."
        ),
    )
    args = ap.parse_args()

    root = (args.root or default_root()).expanduser().resolve()
    report: dict = {
        "generated_at": utc_now().isoformat(timespec="seconds"),
        "root": str(root),
        "platform": sys.platform,
        "session_id": args.session_id,
        "quiesced": False,
        "timings_seconds": {},
        "errors": [],
    }
    if not root.is_dir():
        report["errors"].append(f"root-not-a-directory: {root}")
        print(json.dumps(report, indent=2))
        return 2

    for key, fn, fnargs in (
        ("cli", cli_version, ()),
        ("sweep_health", sweep_health, (root,)),
        ("tree_census", tree_census, (root,)),
        ("home_root_state", home_root_state, ()),
        ("history", history_state, (root,)),
        ("sessions", session_census, (root,)),
        ("plugin_fleet", plugin_fleet, (root,)),
    ):
        try:
            report[key], report["timings_seconds"][key] = timed(fn, *fnargs)
        except OSError as exc:
            report["errors"].append(f"{key}: {exc}")

    records: list[dict] = []
    if not args.skip_processes:
        (records, table_error), report["timings_seconds"]["process_table"] = timed(process_table)
        report["processes"], report["timings_seconds"]["processes"] = timed(
            process_census, records, table_error
        )
        if records and args.population_gap > 0:
            def trend() -> dict:
                time.sleep(args.population_gap)
                second, _ = process_table()
                return population_trend(records, second, args.population_gap)

            report["processes"]["population"], report["timings_seconds"]["population"] = timed(trend)

    if not args.skip_fan_out:
        report["fan_out"], report["timings_seconds"]["fan_out"] = timed(
            fan_out_layer,
            root,
            records,
            args.project_dir,
            args.spawn_samples,
            args.subprocess_timeout,
        )

    report["advisories"] = advisories(root)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

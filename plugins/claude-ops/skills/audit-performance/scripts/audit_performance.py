#!/usr/bin/env python3
"""Read-only slowness-diagnostic capture for a Claude Code installation.

Run at the moment a machine or session feels slow. Captures, in one JSON
report, the evidence needed to separate the four documented suspects behind
Claude Code slowness: accumulated install-tree state, a version regression,
component (plugin/MCP) bloat, and the fan-out layer (hooks, statusline,
spawn cost, and subagent concurrency ceilings). On Windows a kernel
object-type census adds the host-level floor beneath all four: a Token-object
leak that makes every process creation cost seconds whatever Claude Code
does. Retention-sweep health and environment facts come with it. Every
phase is timed, and the timings are
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
import re
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

# Re-exported, not merely used: the spawn-noise names are part of this engine's
# surface (its tests and its --spawn-samples default read them from here), and
# the module they now live in is shared with the `performance` plugin so the
# bimodal threshold has exactly one home.
from spawn_noise import (  # noqa: E402  (path set above; plugin-bundled module)
    BIMODAL_SPREAD_RATIO,
    NOOP_SPAWN,
    SLOW_SPAWN_FLOOR_MS,
    SPAWN_SAMPLES,
    spawn_probe,
    summarize_spawn_samples,
)

__all__ = [
    "BIMODAL_SPREAD_RATIO",
    "NOOP_SPAWN",
    "SLOW_SPAWN_FLOOR_MS",
    "SPAWN_SAMPLES",
    "spawn_probe",
    "summarize_spawn_samples",
]

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

#: Kernel-generated `/proc/<pid>/` files whose CONTENT this engine may read on Linux, and only
#: to tell a kernel thread from a user process. Both are produced by the kernel from task state
#: and carry no user content: `status` holds the `Kthread:` line, `stat` holds the task flags
#: word. Enforced in `read_proc_text`, which raises on any other name. `cmdline` is deliberately
#: absent: it is process-supplied text, and an empty read is not evidence of a kernel thread.
PROC_TEXT_READS = frozenset({"status", "stat"})
#: Root of the proc filesystem. A parameter rather than a literal so the classifier is testable.
PROC_ROOT = Path("/proc")
#: `PF_KTHREAD` in the kernel's task flags word, stable from v2.6.32 through v6.18. proc(5)
#: disclaims stability for the flags field, so a renumbering would classify every kernel thread
#: as user-space: the failure mode is under-exclusion (an investigable false alarm), never
#: over-exclusion (a hidden user-space leak).
PF_KTHREAD = 0x00200000
#: Ceiling on how many processes one population read may classify. The shortlist is ten names
#: wide, and a machine selected for being contended must not pay an unbounded per-pid read.
KTHREAD_CLASSIFY_CAP = 50
#: How many non-kernel rows the population shortlist keeps. Ranked rows are walked until this
#: many survive, so kernel threads at the top of the ranking never crowd out user-space rows.
SHORTLIST_SIZE = 10

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
        "bash",
        "bash.exe",
        "sh",
        "sh.exe",
        "zsh",
        "dash",
        "pwsh",
        "pwsh.exe",
        "powershell",
        "powershell.exe",
        "cmd",
        "cmd.exe",
        "conhost.exe",
        "node",
        "node.exe",
        "bun",
        "bun.exe",
        "cygwin-console-helper.exe",
    }
)

#: Executable names a `claude` on PATH can carry. Windows resolves `.exe` and `.cmd` through
#: PATHEXT, so a PATH scan that looks only for the bare name under-reports there.
CLAUDE_ON_PATH_NAMES = ("claude", "claude.exe", "claude.cmd")
#: Every CLI-probe finding routes to the first-party install-diagnostics command; this engine
#: observes which binary it measured and never adjudicates an install.
DOCTOR_ROUTE = "run `claude doctor`"
#: Only the native installer has a documented binary path, so an unrecognised path is an
#: unclassified layout rather than evidence of an irregular install.
UNCLASSIFIED_LAYOUT_NOTE = (
    "official docs publish a binary path only for the native installer; Homebrew, WinGet, "
    "apt/dnf/apk, npm-global and direct-download installs land wherever they land"
)

#: Hook events that fire on every matching tool call. These scale with tool-call volume, and
#: they are also the only events on which the handler `if` field is evaluated: a hook carrying
#: an `if` on any other event never runs at all.
PER_TOOL_CALL_EVENTS = frozenset(
    {
        "PreToolUse",
        "PostToolUse",
        "PostToolUseFailure",
        "PermissionRequest",
        "PermissionDenied",
    }
)
#: Hook events that fire once per conversational turn. These are what make a long session degrade.
PER_TURN_EVENTS = frozenset(
    {"Stop", "SubagentStop", "UserPromptSubmit", "Notification"}
)

#: A matcher built only from these characters is an exact tool name, or a list of exact names
#: separated by `|` or `,`. A matcher containing anything else is an unanchored regular
#: expression instead, which is why `Edit.*` also selects `NotebookEdit`.
MATCHER_EXACT_CHARS = re.compile(r"^[A-Za-z0-9_\- ,|]+$")
#: Matcher spellings that select every tool. An absent matcher does the same.
MATCHER_MATCH_ALL = frozenset({"*", ""})

#: The file kinds the fan-out projection always runs. A fixed representative baseline, not a
#: scan of any tree: the projection answers "how many handlers fire for a write of this kind of
#: file", and a baseline that changed with the machine would make two captures incomparable.
#: Every extension a classified `if` gate names is projected as well, so a gate on a kind
#: outside this baseline gets its own row instead of matching nothing; `other` stays last and
#: means a file no gate names.
PROJECTION_FILE_KINDS = (".md", ".py", ".sh", ".ts", ".json", "other")
PROJECTION_OTHER_KIND = "other"
#: Tools whose calls carry a file path, so an `Edit(*.<ext>)` gate is decided by extension.
FILE_WRITING_TOOLS = ("Write", "Edit", "NotebookEdit")
#: Tools the projection runs. Bash carries no single file path, so it gets one tool-only row.
PROJECTION_TOOLS = FILE_WRITING_TOOLS + ("Bash",)
#: The only `if` shape this engine classifies: a bare single-extension glob on an `Edit` rule.
#: The extension is captured with its dot so it compares directly against PROJECTION_FILE_KINDS.
IF_EXTENSION_GATE = re.compile(r"^Edit\(\*(\.[A-Za-z0-9_]+)\)$")

#: Hook cost is never a sum. Named once so the block's `note` and its `notes` list cannot drift.
HOOK_PARALLEL_NOTE = (
    "Hooks on one event run in parallel, so wall-clock cost is roughly the slowest hook "
    "plus contention, NOT the sum of their timings. This engine enumerates configured "
    "hooks and never executes one; a hook is third-party code with arbitrary side "
    "effects, and running it would make this capture a mutation."
)
#: What the projection cannot see. Both are over-counts rather than hidden spawns, and both are
#: reported so a reader never mistakes a ceiling for a measurement.
HOOK_ANCHOR_NOTE = (
    "An `if` rule matches only under its anchor, so an edit to a file outside the project "
    "directory never matches one; the projection counts those rows as firing and over-counts "
    "there."
)
HOOK_DEDUP_NOTE = (
    'Cross-settings-file dedup is not modelled. Upstream: "If you define the same handler in '
    "more than one settings file, it runs once. A plugin's or skill's copy of the same handler "
    'stays separate." Rows that dedup upstream are counted twice here.'
)
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

#: Kernel object types the Windows census reports, Token first. A Token object that outlives
#: every handle to it is alive only through a kernel reference, and a reference leak in a
#: driver or service path accumulates them for the life of the boot. The host that motivated
#: this probe carried 3.81M Token objects and about 10 GB of paged pool at two days' uptime,
#: every process creation on it cost 1.4 to 4 s at 7% CPU, and a reboot restored a 14 ms floor.
KERNEL_OBJECT_TYPES = (
    "Token",
    "Process",
    "Thread",
    "Key",
    "File",
    "Section",
    "Event",
    "EtwRegistration",
)
#: Live Token objects at or above which the census reports a leak: ten times what the audited
#: host carried two hours after a clean boot, a fifteenth of what it carried when spawns cost
#: seconds. Calibrated on one host's two states; see known-performance-issues.md for the basis.
TOKEN_LEAK_OBJECTS = 250_000
#: Paged pool at or above which the census reports it as high. The leaking host sat near
#: 10 GB; the same host after reboot near 1 GB. The figure is aggregate and unattributed
#: (GetPerformanceInfo cannot say what charged it), so this finding never carries the
#: Token-leak verdict on its own; `poolmon` is what attributes pool to a tag.
PAGED_POOL_HIGH_MB = 4096

# NtQueryObject(NULL, ObjectTypesInformation) block layout on x64. The information class is
# unofficial but has been stable across Windows releases (it is what Process Explorer and
# System Informer read). A ULONG count padded to pointer alignment leads the block; each
# entry is a 0x68-byte OBJECT_TYPE_INFORMATION whose first 16 bytes are the UNICODE_STRING
# type name, followed by that name's buffer padded to 8 bytes.
_OBJECT_TYPES_INFORMATION = 3
_OBJECT_TYPES_HEADER_BYTES = 8
_OBJECT_TYPE_INFORMATION_BYTES = 0x68
_OTI_NAME_LENGTH = 0x00
_OTI_NAME_MAXIMUM_LENGTH = 0x02
_OTI_NAME_BUFFER = 0x08
_OTI_TOTAL_OBJECTS = 0x10
_OTI_TOTAL_HANDLES = 0x14
_OTI_HIGH_WATER_OBJECTS = 0x28
_OTI_HIGH_WATER_HANDLES = 0x2C


def utc_now() -> datetime:
    return datetime.now(timezone.utc)


def default_root() -> Path:
    env = os.environ.get("CLAUDE_CONFIG_DIR")
    return Path(env) if env else Path.home() / ".claude"


def timed(fn, *args, **kwargs):
    t0 = time.perf_counter()
    result = fn(*args, **kwargs)
    return result, round(time.perf_counter() - t0, 3)


def within(child: Path, base: Path) -> bool:
    """True when `child` resolves inside `base`.

    Both sides are resolved before the containment test, because a string prefix match calls
    `/srv/projects-old` a child of `/srv/projects`.
    """
    try:
        return child.resolve().is_relative_to(base.resolve())
    except (OSError, ValueError):
        return False


def claude_on_path(path_value: str | None = None) -> list[str]:
    """Every file named `claude` on the engine process PATH, in PATH order.

    More than one is the hazard the install docs name: the binary this engine probed is the
    first hit, which need not be the one the operator's shell runs.
    """
    raw = os.environ.get("PATH", os.defpath) if path_value is None else path_value
    hits: list[str] = []
    for entry in raw.split(os.pathsep):
        if not entry:
            continue
        for name in CLAUDE_ON_PATH_NAMES:
            candidate = os.path.join(entry, name)
            if os.path.isfile(candidate) and candidate not in hits:
                hits.append(candidate)
    return hits


def cli_layout(probe_path: str, resolved_path: str, home: Path | None = None) -> str:
    """Classify the probed binary against the only install paths the docs publish."""
    base = home or Path.home()
    native_bin = base / ".local" / "bin"
    if within(Path(resolved_path), base / ".local" / "share" / "claude" / "versions"):
        return "documented-native"
    if Path(probe_path) in {native_bin / "claude", native_bin / "claude.exe"}:
        return "documented-native"
    legacy = base / ".claude" / "local"
    if within(Path(resolved_path), legacy) or within(Path(probe_path), legacy):
        return "legacy-local-npm"
    return "unclassified"


def cli_probe_provenance(
    probe_path: str,
    project_dir: Path | None = None,
    home: Path | None = None,
    cwd: Path | None = None,
    path_value: str | None = None,
) -> dict:
    """Say WHICH `claude` was measured and how it was found, never which installer put it there.

    `shutil.which` searches the engine process PATH, which is not the operator's login shell
    PATH, so a report naming only a version cannot be checked against the binary the operator
    actually runs. Everything here is a path observation; the verdict on a duplicated or
    misplaced install belongs to the first-party install diagnostics.
    """
    resolved_path = os.path.realpath(probe_path)
    base = Path(project_dir) if project_dir is not None else Path(cwd or os.getcwd())
    layout = cli_layout(probe_path, resolved_path, home)
    resolved = Path(resolved_path)
    findings: list[dict] = []
    if within(resolved, base) or any(part == "node_modules" for part in resolved.parts):
        findings.append({"finding": "cli-probe-project-local", "route": DOCTOR_ROUTE})
    on_path = claude_on_path(path_value)
    if len(on_path) > 1:
        findings.append({"finding": "cli-multiple-on-path", "route": DOCTOR_ROUTE})
    block = {
        "probe_path": probe_path,
        "exe": probe_path,
        "resolved_path": resolved_path,
        "path_searched": "engine process PATH (not the operator's login shell)",
        "layout": layout,
        "containment_base": str(base),
        "containment_base_source": "project-dir" if project_dir is not None else "cwd",
        "on_path": on_path,
        "findings": findings,
    }
    if layout == "unclassified":
        block["layout_note"] = UNCLASSIFIED_LAYOUT_NOTE
    return block


def cli_version(project_dir: Path | None = None) -> dict:
    exe = shutil.which("claude")
    if not exe:
        return {"version": None, "error": "claude not on PATH"}
    provenance = cli_probe_provenance(exe, project_dir)
    try:
        t0 = time.perf_counter()
        out = subprocess.run(
            [exe, "--version"],
            capture_output=True,
            text=True,
            timeout=SUBPROCESS_TIMEOUT_S,
        )
        elapsed = round(time.perf_counter() - t0, 3)
        version = out.stdout.strip() or None
        return {
            "version": version,
            **provenance,
            "seconds": elapsed,
            "slow_version_probe": elapsed > 5.0,
            "valid_for_version": version,
            "valid_for_version_note": (
                "outside the native layout the binary path changes on update, so the resolved "
                "path is valid for this version only; re-probe rather than trusting it later"
            ),
        }
    except subprocess.TimeoutExpired:
        return {
            "version": None,
            **provenance,
            "error": f"--version timed out after {SUBPROCESS_TIMEOUT_S}s (itself a finding)",
        }
    except OSError as exc:
        return {"version": None, **provenance, "error": str(exc)}


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
    top_by_files = sorted(entries.items(), key=lambda kv: kv[1]["files"], reverse=True)[
        :5
    ]
    return {
        "walk_seconds": walk_seconds,
        "total_files": total_files,
        "total_mb": round(total_bytes / 1048576, 2),
        "files_per_second": round(total_files / walk_seconds, 0)
        if walk_seconds > 0
        else None,
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
                "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(
                    timespec="seconds"
                ),
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
        "mtime": datetime.fromtimestamp(st.st_mtime, timezone.utc).isoformat(
            timespec="seconds"
        ),
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
                largest = {
                    "path": p.relative_to(projects).as_posix(),
                    "mb": round(mb, 2),
                }
            if (
                now - st.st_mtime < ACTIVE_SESSION_WINDOW_S
                and "subagents" not in p.parts
            ):
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
    out["note"] = (
        "counts only; enablement and scope verdicts belong to /claude-ops:plugins audit"
    )
    return out


def parse_object_types(base: int) -> dict[str, dict]:
    """Walk the OBJECT_TYPES_INFORMATION block at address `base` into {type name: counters}.

    Pure memory reads against the x64 layout, so a synthetic block exercises it on any
    platform. Names are decoded as UTF-16LE bytes rather than through `wstring_at`, whose
    `wchar_t` is four bytes on Linux and would misread the same block there.
    """
    import ctypes

    def u16(address: int) -> int:
        return ctypes.c_uint16.from_address(address).value

    def u32(address: int) -> int:
        return ctypes.c_uint32.from_address(address).value

    table: dict[str, dict] = {}
    offset = _OBJECT_TYPES_HEADER_BYTES
    for _ in range(u32(base)):
        entry = base + offset
        name_length = u16(entry + _OTI_NAME_LENGTH)
        name_maximum = u16(entry + _OTI_NAME_MAXIMUM_LENGTH)
        name_buffer = ctypes.c_void_p.from_address(entry + _OTI_NAME_BUFFER).value
        name = (
            ctypes.string_at(name_buffer, name_length).decode("utf-16-le")
            if name_buffer and name_length
            else ""
        )
        table[name] = {
            "objects": u32(entry + _OTI_TOTAL_OBJECTS),
            "handles": u32(entry + _OTI_TOTAL_HANDLES),
            "high_water_objects": u32(entry + _OTI_HIGH_WATER_OBJECTS),
            "high_water_handles": u32(entry + _OTI_HIGH_WATER_HANDLES),
        }
        offset += _OBJECT_TYPE_INFORMATION_BYTES + ((name_maximum + 7) & ~7)
    return table


def _windows_object_type_table() -> dict[str, dict]:
    """Query the kernel's object-type table. Read-only, unprivileged, one syscall."""
    import ctypes

    ntdll = ctypes.WinDLL("ntdll")
    ntdll.NtQueryObject.restype = ctypes.c_long
    ntdll.NtQueryObject.argtypes = [
        ctypes.c_void_p,
        ctypes.c_int,
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.POINTER(ctypes.c_uint32),
    ]
    size = (
        1 << 20
    )  # ~75 types at ~130 bytes each; a megabyte leaves two orders of magnitude spare
    block = ctypes.create_string_buffer(size)
    needed = ctypes.c_uint32(0)
    status = ntdll.NtQueryObject(
        None, _OBJECT_TYPES_INFORMATION, block, size, ctypes.byref(needed)
    )
    if status != 0:
        raise OSError(
            f"NtQueryObject(ObjectTypesInformation) failed: NTSTATUS 0x{status & 0xFFFFFFFF:08X}"
        )
    return parse_object_types(ctypes.addressof(block))


def _windows_performance_info() -> dict:
    """Pool usage, system-wide handle/process/thread totals, and uptime via GetPerformanceInfo."""
    import ctypes

    class PERFORMANCE_INFORMATION(ctypes.Structure):
        _fields_ = [
            ("cb", ctypes.c_uint32),
            ("CommitTotal", ctypes.c_size_t),
            ("CommitLimit", ctypes.c_size_t),
            ("CommitPeak", ctypes.c_size_t),
            ("PhysicalTotal", ctypes.c_size_t),
            ("PhysicalAvailable", ctypes.c_size_t),
            ("SystemCache", ctypes.c_size_t),
            ("KernelTotal", ctypes.c_size_t),
            ("KernelPaged", ctypes.c_size_t),
            ("KernelNonpaged", ctypes.c_size_t),
            ("PageSize", ctypes.c_size_t),
            ("HandleCount", ctypes.c_uint32),
            ("ProcessCount", ctypes.c_uint32),
            ("ThreadCount", ctypes.c_uint32),
        ]

    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    get_info = getattr(kernel32, "K32GetPerformanceInfo", None)
    if get_info is None:
        get_info = ctypes.WinDLL("psapi", use_last_error=True).GetPerformanceInfo
    info = PERFORMANCE_INFORMATION()
    info.cb = ctypes.sizeof(info)
    if not get_info(ctypes.byref(info), info.cb):
        raise OSError(ctypes.get_last_error(), "GetPerformanceInfo failed")
    kernel32.GetTickCount64.restype = ctypes.c_uint64
    page = info.PageSize
    return {
        "paged_pool_mb": round(info.KernelPaged * page / 2**20),
        "nonpaged_pool_mb": round(info.KernelNonpaged * page / 2**20),
        "handles": info.HandleCount,
        "processes": info.ProcessCount,
        "threads": info.ThreadCount,
        "uptime_s": kernel32.GetTickCount64() / 1000,
    }


def summarize_kernel_objects(types: dict[str, dict], perf: dict) -> dict:
    """Turn the raw census into the report section, with its findings and label.

    The rate reported is live Token objects divided by uptime, a population ratio rather
    than a measured mint rate: it includes whatever population the boot started with (so it
    overstates the rate early in a boot, and the projection errs short) and it cannot see
    tokens created and destroyed in between. It is still the signal this engine reports
    because it needs no sleep and cannot be gamed by a quiet moment: on the audited host a
    3 s in-run window read 0/s while a 60 s window read 15/s, so any delta short enough for
    an engine pass under-reads bursty minting. The 60 s manual sample in the reference is the
    mint-rate measurement; this ratio's error shrinks as uptime grows.

    The Token-leak verdict rests on the object count alone. Paged pool is aggregate and
    unattributed, so `paged-pool-high` by itself is a separate finding with its own label.
    """
    token = types.get("Token") or {}
    objects = int(token.get("objects", 0))
    handles = int(token.get("handles", 0))
    uptime_s = float(perf.get("uptime_s") or 0)
    ratio = objects / uptime_s if uptime_s > 0 else None
    findings = []
    if objects >= TOKEN_LEAK_OBJECTS:
        findings.append("token-objects-leaked")
    if perf.get("paged_pool_mb", 0) >= PAGED_POOL_HIGH_MB:
        findings.append("paged-pool-high")
    hours_to_threshold = None
    if ratio and objects < TOKEN_LEAK_OBJECTS:
        hours_to_threshold = round((TOKEN_LEAK_OBJECTS - objects) / ratio / 3600, 1)
    if "token-objects-leaked" in findings:
        state_label = "token-leak"
    elif "paged-pool-high" in findings:
        state_label = "paged-pool-high"
    else:
        state_label = "nominal"
    return {
        "supported": True,
        "source": "NtQueryObject(ObjectTypesInformation) + GetPerformanceInfo",
        "uptime_hours": round(uptime_s / 3600, 2),
        "pool": {
            "paged_mb": perf.get("paged_pool_mb"),
            "nonpaged_mb": perf.get("nonpaged_pool_mb"),
        },
        "system": {
            "handles": perf.get("handles"),
            "processes": perf.get("processes"),
            "threads": perf.get("threads"),
        },
        "types": {name: types[name] for name in KERNEL_OBJECT_TYPES if name in types},
        "token": {
            "objects": objects,
            "handles": handles,
            "handleless_objects": objects - handles,
            "high_water_objects": token.get("high_water_objects"),
            "objects_per_uptime_second": round(ratio, 2) if ratio is not None else None,
            "hours_to_leak_threshold_at_uptime_ratio": hours_to_threshold,
            "basis": (
                "live objects / uptime: includes the boot population (overstates early in a "
                "boot, so the projection errs short) and cannot see destroyed tokens; the 60 s "
                "manual sample in known-performance-issues.md is the mint-rate measurement"
            ),
        },
        "thresholds": {
            "token_leak_objects": TOKEN_LEAK_OBJECTS,
            "paged_pool_high_mb": PAGED_POOL_HIGH_MB,
        },
        "findings": findings,
        "state_label": state_label,
    }


def kernel_objects() -> dict:
    """The host-level floor beneath the four suspects: a kernel object-type census (Windows).

    A leaking kernel reference to Token objects fills paged pool and makes every process
    creation on the host cost seconds, with CPU idle and memory free, before Claude Code
    spawns anything. No suspect the rest of this engine measures can see it, and clearing
    all four while it is present produces a confident and wrong diagnosis.
    """
    if sys.platform != "win32":
        return {
            "supported": False,
            "reason": (
                "the kernel object-type census is Windows-only (NtQueryObject); nothing "
                f"equivalent is probed on {sys.platform}"
            ),
        }
    import ctypes

    if ctypes.sizeof(ctypes.c_void_p) != 8:
        return {
            "supported": False,
            "reason": "the census reads the x64 OBJECT_TYPE_INFORMATION layout; this interpreter is 32-bit",
        }
    return summarize_kernel_objects(
        _windows_object_type_table(), _windows_performance_info()
    )


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
            created, exited, kernel, user = (
                FILETIME(),
                FILETIME(),
                FILETIME(),
                FILETIME(),
            )
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
        rows = (
            _windows_process_table()
            if sys.platform == "win32"
            else _posix_process_table()
        )
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
            summary["reason"] = (
                "parent start time unreadable; PID reuse cannot be excluded"
            )
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
        "candidate_names_note": (
            "platform-agnostic set; executable-suffixed names are inert on POSIX process "
            "tables and retained for WSL interop processes"
        ),
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


def read_proc_text(pid: int, name: str, proc_root: Path | None = None) -> str:
    """Read one allowlisted `/proc/<pid>/` text file. Raises on any other name.

    The allowlist is enforced here the way `read_json` enforces its own, so the engine's
    stated read surface and its code cannot drift apart.
    """
    if name not in PROC_TEXT_READS:
        raise AssertionError(f"proc read outside the allowlist: {name}")
    root = proc_root or PROC_ROOT
    return (root / str(pid) / name).read_text(encoding="utf-8", errors="replace")


def is_kernel_thread(pid: int, proc_root: Path | None = None) -> bool | None:
    """True for a kernel thread, False for a user process, None when unreadable.

    PF_KTHREAD is the kernel's own predicate, so it is the only classifier used here.
    `/proc/<pid>/status` carries it as a `Kthread:` line on kernels that publish one;
    otherwise it is bit 0x00200000 of the task flags word, field 9 of `/proc/<pid>/stat`.
    Field 2 of `stat` is the command in parentheses and may itself contain spaces and `)`,
    so the split runs from the LAST `)`.

    Neither a parent pid of 2 nor an empty `cmdline` is consulted. The kernel reparents
    user-space helpers onto kthreadd, so a ppid test convicts user processes, and a process
    can rewrite or relocate its own `cmdline`, so an empty read proves nothing. An
    unclassifiable process is user-space: under-exclusion surfaces as an investigable false
    alarm, over-exclusion hides a real user-space leak.
    """
    try:
        for line in read_proc_text(pid, "status", proc_root).splitlines():
            if line.startswith("Kthread:"):
                return line.split(":", 1)[1].strip() == "1"
    except OSError:
        return None
    try:
        stat = read_proc_text(pid, "stat", proc_root)
        remainder = stat[stat.rindex(")") + 1 :].split()
        return bool(int(remainder[6]) & PF_KTHREAD)
    except (OSError, ValueError, IndexError):
        return None


def population_trend(
    sample_a: list[dict],
    sample_b: list[dict],
    gap_seconds: float,
    platform: str | None = None,
    classify=is_kernel_thread,
    classify_cap: int = KTHREAD_CLASSIFY_CAP,
) -> dict:
    """Separate accumulation from churn using two snapshots taken seconds apart.

    A rising count with nothing exiting is accumulation. A flat or falling count
    with many pids replaced is churn, which looks identical in a single sample
    and means something entirely different. A name absent from the first sample
    merely appeared, which is neither.

    On Linux the shortlist is filtered against PF_KTHREAD, because `ps -e` lists the
    kernel's own threads and a kworker renames its comm across queues, so the same worker
    reads as a new name arriving every few seconds.
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
        elif len(pids_a) == 0 and started > 0:
            verdict = "appeared"
        elif exited == 0 and delta > 0 and len(pids_a) > 0:
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
    rows.sort(
        key=lambda r: (r["exited"] + r["started"], r["count_second"]), reverse=True
    )
    # The second sample is the live one, so classify its pids; a name that has since drained
    # entirely falls back to the first sample's pids rather than going unclassified. The
    # ranked rows are walked until ten non-kernel rows are kept, so kernel threads at the top
    # of the ranking never crowd user-space rows out of the shortlist.
    live = {
        row["name"]: second.get(row["name"]) or first.get(row["name"], set())
        for row in rows
    }
    kernel = exclude_kernel_threads(
        rows, live, platform, classify, classify_cap, keep=SHORTLIST_SIZE
    )
    return {
        "gap_seconds": gap_seconds,
        "most_active": kernel["rows"],
        "kernel_threads_excluded": kernel["excluded"],
        "kernel_thread_reads": kernel["reads"],
        "kernel_thread_read_cap": classify_cap,
        "kernel_thread_note": kernel["note"],
        "note": (
            "A count that rises with nothing exiting is accumulation; a count that holds while "
            "pids turn over is churn. One sample cannot tell them apart. A name with no "
            "processes in the first sample reads `appeared`, not `accumulating`: one arrival "
            "of a name nothing was running seconds earlier is not evidence of a leak."
        ),
    }


def exclude_kernel_threads(
    rows: list[dict],
    pids_by_name: dict[str, set[int]],
    platform: str | None = None,
    classify=is_kernel_thread,
    classify_cap: int = KTHREAD_CLASSIFY_CAP,
    keep: int = SHORTLIST_SIZE,
) -> dict:
    """Walk ranked rows, dropping those whose every process is a kernel thread, until
    `keep` rows survive.

    Only the kept rows' processes are read, and only up to `classify_cap` of them, because
    a per-pid read on a machine chosen for being contended must carry a stated bound. A row
    is excluded only when every one of its processes was examined and every verdict is
    True; a row the cap leaves partially or wholly unclassified is kept, so the ceiling never
    silently hides a user process. Rows past the cap are kept unclassified in rank order.
    """
    if (platform or sys.platform) != "linux":
        return {
            "rows": rows[:keep],
            "excluded": None,
            "reads": 0,
            "note": (
                "PF_KTHREAD classification is Linux-only. Other platforms have no analogue in "
                "the process table: kernel threads there belong to a single kernel process "
                "that a top-level census never enumerates separately."
            ),
        }
    kept: list[dict] = []
    reads = 0
    excluded = 0
    for row in rows:
        if len(kept) >= keep:
            break
        verdicts = []
        complete = True
        for pid in sorted(pids_by_name.get(row["name"], set())):
            if reads >= classify_cap:
                complete = False
                break
            verdicts.append(classify(pid))
            reads += 1
        if complete and verdicts and all(verdict is True for verdict in verdicts):
            excluded += 1
            continue
        kept.append(row)
    return {
        "rows": kept,
        "excluded": excluded,
        "reads": reads,
        "note": (
            "Rows whose every process, all of them examined, carries PF_KTHREAD are excluded: they are the "
            "kernel's own threads, not workload. Classification reads `/proc/<pid>/status` and "
            "`/proc/<pid>/stat` for the ranked rows walked to fill the shortlist, and an unclassifiable or partially examined row counts as "
            "user-space."
        ),
    }


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
                        "args": [str(a) for a in args]
                        if isinstance(args, list)
                        else [],
                        "timeout": hook.get("timeout"),
                        "if": hook.get("if"),
                        "source": source,
                    }
                )
    return entries


def command_key(entry: dict) -> str:
    """What a firing row actually spawns: the command plus its args.

    Counting the command alone would collapse two handlers that share a dispatcher and pass
    different arguments into one, and those are two process creations, not one.
    """
    args = entry.get("args") or []
    return " ".join([str(entry.get("command") or "")] + [str(a) for a in args])


def matcher_kind(matcher: object) -> str:
    """Classify a hook group's matcher by the documented character-class rule.

    Returns `all`, `exact`, or `regex`. The rule is a character class, not a guess: `*`, an
    empty string, or an absent matcher selects everything; a matcher built only from letters,
    digits, `_`, `-`, spaces, `,`, and `|` is an exact name or an alternation list of exact
    names; anything else is an unanchored regular expression.
    """
    if matcher is None:
        return "all"
    text = str(matcher)
    if text in MATCHER_MATCH_ALL:
        return "all"
    if MATCHER_EXACT_CHARS.match(text):
        return "exact"
    return "regex"


def matcher_compile_error(matcher: object) -> str | None:
    """The reason a regex matcher cannot be evaluated here, or None when it can.

    A JavaScript-only construct (a named group spelled `(?<name>...)`, a `\\p{...}` class, a
    lookbehind Python rejects) compiles upstream and not here. Such a matcher selects an
    unknown set of tools, so the projection counts it as selecting every tool and names it,
    the same over-count-and-report direction an unclassified `if` takes.
    """
    if matcher_kind(matcher) != "regex":
        return None
    try:
        re.compile(str(matcher))
    except re.error as exc:
        return f"matcher is not a Python-compilable regular expression ({exc})"
    return None


def matcher_matches(matcher: object, tool: str) -> bool:
    """True when a matcher selects `tool`, or when that cannot be decided here.

    Python's `re.search` stands in for JavaScript's `RegExp.prototype.test`. Both are
    unanchored, so `Edit.*` also selects `NotebookEdit`. An exact matcher is compared whole,
    which is why a bare `mcp__memory` selects nothing: the tool name is
    `mcp__memory__<tool>`, and server-wide matching needs `mcp__memory.*`. A matcher Python
    cannot compile is treated as selecting every tool, never as selecting nothing: the
    projection is a ceiling, and a spawn it cannot rule out stays counted.
    """
    kind = matcher_kind(matcher)
    if kind == "all":
        return True
    text = str(matcher)
    if kind == "exact":
        return any(part.strip() == tool for part in re.split(r"[|,]", text))
    if matcher_compile_error(matcher) is not None:
        return True
    return re.search(text, tool) is not None


def classify_if_gate(rule: object) -> dict:
    """Classify one handler `if` rule into what this projection can decide.

    Returns `{kind, extension, reason}` where kind is `absent`, `extension`, or
    `unclassified`. Exactly one shape is classifiable, `Edit(*.<ext>)`: a bare single-extension
    glob with no path separator and no `**`. Everything wider stays unclassified and is counted
    as firing, so an unmodelled rule over-counts the fan-out rather than hiding a spawn.
    """
    if rule is None or str(rule).strip() == "":
        return {"kind": "absent", "extension": None, "reason": None}
    text = str(rule).strip()
    match = IF_EXTENSION_GATE.match(text)
    if match:
        # Lower-cased so a mixed-case extension folds into its projection row and
        # over-counts at worst; kept as-is it would match no file kind and vanish.
        return {
            "kind": "extension",
            "extension": match.group(1).lower(),
            "reason": None,
        }
    if not text.startswith("Edit("):
        named = text.split("(", 1)[0] or text
        return {
            "kind": "unclassified",
            "extension": None,
            "reason": (
                f"rule names `{named}`; only `Edit(*.<ext>)` is decided by file extension here"
            ),
        }
    if "**" in text:
        reason = "multi-segment `**` glob; this engine models no directory depth"
    elif "/" in text:
        reason = (
            "directory-anchored pattern; this engine models an extension, never a path"
        )
    elif "{" in text or "," in text:
        reason = "brace or list alternation; this engine models one extension per rule"
    else:
        reason = "not a bare `*.<ext>` pattern"
    return {"kind": "unclassified", "extension": None, "reason": reason}


def hooks_by_matcher(entries: list[dict]) -> list[dict]:
    """Row count, distinct commands, and if-gated rows per (event, matcher).

    `count` alone hides the shape the issue behind this block names: a bucket of 33 rows can be
    a handful of commands replicated once per extension behind an `if`, which is a very
    different fan-out from 33 unconditional spawns.
    """
    grouped: dict[tuple[str, str | None], dict] = {}
    for entry in entries:
        event = entry.get("event") or "unknown"
        matcher = entry.get("matcher")
        key = (event, None if matcher is None else str(matcher))
        row = grouped.setdefault(
            key,
            {
                "event": event,
                "matcher": key[1],
                "rows": 0,
                "commands": set(),
                "if_gated_rows": 0,
                "source_set": set(),
            },
        )
        row["rows"] += 1
        row["commands"].add(command_key(entry))
        row["source_set"].add(str(entry.get("source")))
        if classify_if_gate(entry.get("if"))["kind"] != "absent":
            row["if_gated_rows"] += 1
    out = []
    for key in sorted(grouped, key=lambda k: (k[0], k[1] or "")):
        row = grouped[key]
        out.append(
            {
                "event": row["event"],
                "matcher": row["matcher"],
                "matcher_kind": matcher_kind(row["matcher"]),
                "rows": row["rows"],
                "distinct_commands": len(row["commands"]),
                "if_gated_rows": row["if_gated_rows"],
                "sources": sorted(row["source_set"]),
            }
        )
    return out


def project_fan_out(entries: list[dict]) -> dict:
    """Project how many handlers actually fire per (tool, file kind), from the records alone.

    Three levels decide a row, and a registered-row count collapses all three. The event key
    says whether the row is per tool call at all; the group matcher says whether the tool is
    selected; the handler `if` is the only level that sees the call's arguments. A row whose
    `if` this engine cannot classify, or whose matcher it cannot compile, counts as firing and
    is listed, so the number is a ceiling with its uncertainty named rather than a false floor.

    The file kinds projected are the fixed baseline plus every extension a classified gate
    names, so a gate on `.go` gets a `.go` row rather than silently matching no kind at all.

    Pure: it reads the flattened records and touches no filesystem and no subprocess.
    """
    gated: list[tuple[dict, dict, bool]] = []
    unclassified_rows: list[dict] = []
    if_on_non_tool_event: list[dict] = []
    gate_kinds: set[str] = set()
    for entry in entries:
        event = entry.get("event") or "unknown"
        gate = classify_if_gate(entry.get("if"))
        matcher_error = matcher_compile_error(entry.get("matcher"))
        row = {
            "event": event,
            "matcher": entry.get("matcher"),
            "source": entry.get("source"),
            "if": entry.get("if"),
        }
        if gate["kind"] != "absent" and event not in PER_TOOL_CALL_EVENTS:
            if_on_non_tool_event.append(
                {
                    **row,
                    "reason": (
                        "`if` is evaluated only on the five tool events; on any other event a "
                        "handler carrying one never runs"
                    ),
                }
            )
            continue
        if gate["kind"] == "unclassified":
            unclassified_rows.append({**row, "reason": gate["reason"]})
        elif matcher_error is not None and event in PER_TOOL_CALL_EVENTS:
            unclassified_rows.append({**row, "reason": matcher_error})
        if gate["kind"] == "extension":
            gate_kinds.add(gate["extension"])
        if event in PER_TOOL_CALL_EVENTS:
            gated.append((entry, gate, matcher_error is not None))

    file_kinds = projected_file_kinds(gate_kinds)
    rows: list[dict] = []
    for event in sorted({(e.get("event") or "unknown") for e, _, _ in gated}):
        for tool in PROJECTION_TOOLS:
            kinds: tuple = file_kinds if tool in FILE_WRITING_TOOLS else (None,)
            for file_kind in kinds:
                firing: list[dict] = []
                fire_always = 0
                for entry, gate, matcher_unknown in gated:
                    if (entry.get("event") or "unknown") != event:
                        continue
                    if not matcher_matches(entry.get("matcher"), tool):
                        continue
                    if gate["kind"] == "extension":
                        if (
                            tool not in FILE_WRITING_TOOLS
                            or gate["extension"] != file_kind
                        ):
                            continue
                    if gate["kind"] == "unclassified" or matcher_unknown:
                        fire_always += 1
                    firing.append(entry)
                rows.append(
                    {
                        "event": event,
                        "tool": tool,
                        "file_kind": file_kind,
                        "fires": len(firing),
                        "distinct_commands": len({command_key(e) for e in firing}),
                        "fire_always_unclassified": fire_always,
                    }
                )
    return {
        "file_kinds": list(file_kinds),
        "baseline_file_kinds": list(PROJECTION_FILE_KINDS),
        "discovered_file_kinds": sorted(gate_kinds - set(PROJECTION_FILE_KINDS)),
        "tools": list(PROJECTION_TOOLS),
        "rows": rows,
        "unclassified_rows": unclassified_rows,
        "if_on_non_tool_event": if_on_non_tool_event,
        "note": (
            "Matcher evaluation follows the documented character-class rule, with Python's "
            "`re.search` standing in for JavaScript's `RegExp.prototype.test`: both are "
            "unanchored, so `Edit.*` also selects `NotebookEdit`. `file_kinds` is the fixed "
            "baseline plus every extension a classified `if` gate names; `other` is a file "
            "no gate names. `file_kind` is null on a tool that carries no single file path. "
            "`fires` is a ceiling: a row whose `if` could not be classified, or whose "
            "matcher Python cannot compile, is counted as firing and appears in "
            "`fire_always_unclassified` and in `unclassified_rows`."
        ),
    }


def projected_file_kinds(gate_kinds: set[str]) -> tuple[str, ...]:
    """The baseline kinds in their stated order, then gate-named extras sorted, then `other`.

    Baseline order is kept so two captures stay comparable row for row; the extras follow it so
    a discovered kind is visibly an addition rather than a reordering.
    """
    baseline = tuple(k for k in PROJECTION_FILE_KINDS if k != PROJECTION_OTHER_KIND)
    extras = sorted(set(gate_kinds) - set(PROJECTION_FILE_KINDS))
    return baseline + tuple(extras) + (PROJECTION_OTHER_KIND,)


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

    `count` stays the REGISTERED-ROW ceiling, and `projection` is what a single
    tool call of a given shape actually spawns. Both ship, because a bucket count
    alone cannot distinguish many unconditional handlers from one handler
    replicated per extension behind an `if` gate, and those cost differently.
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
            "distinct_commands": len({command_key(r) for r in rows}),
            "if_gated_rows": sum(
                1 for r in rows if classify_if_gate(r.get("if"))["kind"] != "absent"
            ),
            "matchers": sorted(
                {str(r.get("matcher")) for r in rows if r.get("matcher")}
            ),
            "sources": sorted({str(r.get("source")) for r in rows}),
        }

    projection = project_fan_out(entries)
    return {
        "total": len(entries),
        "by_event": dict(sorted(by_event.items())),
        "by_matcher": hooks_by_matcher(entries),
        "per_tool_call": summarize("per_tool_call"),
        "per_turn": summarize("per_turn"),
        "other": summarize("other"),
        "projection": {
            key: value
            for key, value in projection.items()
            if key not in ("unclassified_rows", "if_on_non_tool_event")
        },
        "unclassified_rows": projection["unclassified_rows"],
        "if_on_non_tool_event": projection["if_on_non_tool_event"],
        "invocation_shape_findings": shape_findings,
        "notes": [HOOK_ANCHOR_NOTE, HOOK_DEDUP_NOTE, HOOK_PARALLEL_NOTE],
        "note": HOOK_PARALLEL_NOTE,
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
        key=lambda i: (
            SCOPE_PRECEDENCE.index(i.get("scope"))
            if i.get("scope") in SCOPE_PRECEDENCE
            else len(SCOPE_PRECEDENCE)
        ),
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
                f'{name}: set to "0", which is TRUTHY in JavaScript and does not disable it'
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
        "max_concurrent_subagents_per_session": effective(
            "CLAUDE_CODE_MAX_CONCURRENT_SUBAGENTS"
        ),
        "max_subagent_spawn_depth": effective("CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH"),
        "note": (
            "Depth multiplies against the per-session concurrency limit, and every subagent "
            "carries the same statusline and hook fan-out as its parent."
        ),
    }
    ceilings["trap"] = (
        "These flags are read through a JavaScript truthiness test on the raw string, and the "
        'string "0" is truthy. Setting one to 0 reads like a disable in a settings file and is '
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
        r
        for r in records
        if is_claude_process(r["name"]) and r.get("started_epoch") is not None
    ]
    stale = [r for r in sessions if r["started_epoch"] < mtime]
    result = {
        "settings_present": True,
        "settings_mtime": datetime.fromtimestamp(mtime, timezone.utc).isoformat(
            timespec="seconds"
        ),
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


def fan_out_layer(
    root: Path,
    records: list[dict],
    project_dir: Path | None,
    spawn_samples: int,
    timeout_s: float,
) -> dict:
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


def operator_context(notes: list[str] | None, source: str = "unspecified") -> dict:
    """Record what only a human at the machine can know, and record its absence as a fact.

    The engine sees the machine, never the intent: which thing felt slow, how many terminals
    were open, what the session was doing. A run with none of that is incomplete, and saying
    so in the report is what keeps the gap visible instead of letting a silent absence read
    as a clean bill of health. The declared source is taken at face value because nothing in
    a process can verify who typed a flag.
    """
    supplied = list(notes or [])
    return {
        "status": "present" if supplied else "absent",
        "notes": supplied,
        "source": source,
        "note": "supplied via --note by the invoker; the engine cannot verify origin",
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


def build_parser() -> argparse.ArgumentParser:
    """The CLI surface, built apart from `main` so the flag contract is directly testable."""
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--root",
        type=Path,
        default=None,
        help="install root (else $CLAUDE_CONFIG_DIR, else ~/.claude)",
    )
    ap.add_argument(
        "--session-id",
        default=None,
        help="current session id, for the report's capture context",
    )
    ap.add_argument(
        "--skip-processes",
        action="store_true",
        help="skip the process table and census",
    )
    ap.add_argument(
        "--skip-fan-out", action="store_true", help="skip the fan-out layer probes"
    )
    ap.add_argument(
        "--project-dir",
        type=Path,
        default=None,
        help="project root, so project-scope hooks in .claude/settings.json are counted too",
    )
    ap.add_argument(
        "--note",
        action="append",
        default=None,
        metavar="TEXT",
        help="Attach operator context; repeat for multiple notes.",
    )
    ap.add_argument(
        "--note-source",
        choices=("operator", "assistant"),
        default="unspecified",
        help="who supplied the notes; the engine cannot verify this and records it as declared",
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
    return ap


def main() -> int:
    args = build_parser().parse_args()

    root = (args.root or default_root()).expanduser().resolve()
    report: dict = {
        "generated_at": utc_now().isoformat(timespec="seconds"),
        "root": str(root),
        "platform": sys.platform,
        "session_id": args.session_id,
        "quiesced": False,
        "operator_context": operator_context(args.note, args.note_source),
        "timings_seconds": {},
        "errors": [],
    }
    if not root.is_dir():
        report["errors"].append(f"root-not-a-directory: {root}")
        print(json.dumps(report, indent=2))
        return 2

    for key, fn, fnargs in (
        ("cli", cli_version, (args.project_dir,)),
        ("sweep_health", sweep_health, (root,)),
        ("tree_census", tree_census, (root,)),
        ("home_root_state", home_root_state, ()),
        ("history", history_state, (root,)),
        ("sessions", session_census, (root,)),
        ("plugin_fleet", plugin_fleet, (root,)),
        ("kernel_objects", kernel_objects, ()),
    ):
        try:
            report[key], report["timings_seconds"][key] = timed(fn, *fnargs)
        except OSError as exc:
            report["errors"].append(f"{key}: {exc}")

    records: list[dict] = []
    if not args.skip_processes:
        (records, table_error), report["timings_seconds"]["process_table"] = timed(
            process_table
        )
        report["processes"], report["timings_seconds"]["processes"] = timed(
            process_census, records, table_error
        )
        if records and args.population_gap > 0:

            def trend() -> dict:
                time.sleep(args.population_gap)
                second, _ = process_table()
                return population_trend(records, second, args.population_gap)

            (
                report["processes"]["population"],
                report["timings_seconds"]["population"],
            ) = timed(trend)

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

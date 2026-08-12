#!/usr/bin/env python3
"""Read-only slowness-diagnostic capture for a Claude Code installation.

Run at the moment a machine or session feels slow. Captures, in one JSON
report, the evidence needed to separate the three documented suspects behind
Claude Code slowness — accumulated install-tree state, a version regression,
and component (plugin/MCP) bloat — plus retention-sweep health and
environment facts. Every phase is timed, and the timings are themselves
measurements: a census walk that takes minutes on the live tree is the same
cost the product's own retention sweep pays on that tree.

Hard rules, enforced in code:

- **Reports; never mutates.** No file under any scanned root is written,
  renamed, deleted, or touched. The engine writes only its stdout.
- **Content reads are allowlisted** to `settings.json` and `.last-cleanup`.
  Everything else — including `~/.claude.json` and `history.jsonl`, whose
  values can carry tokens and prompts — is stat-only: name, size, mtime.
- **Never elevates.** Windows Defender guidance is emitted as advisory text.

Python 3.11+, standard library only.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import os
import shutil
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

ACTIVE_SESSION_WINDOW_S = 3600
STALE_SWEEP_DAYS = 2.0
SUBPROCESS_TIMEOUT_S = 20


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


def process_census() -> dict:
    """Best-effort count of Claude-related processes. Degrades to a note."""
    try:
        if sys.platform == "win32":
            out = subprocess.run(
                ["tasklist", "/FO", "CSV"], capture_output=True, text=True, timeout=SUBPROCESS_TIMEOUT_S  # spellchecker:disable-line
            )
            rows = list(csv.reader(io.StringIO(out.stdout)))
            procs = []
            for row in rows[1:]:
                if not row:
                    continue
                name = row[0].lower()
                if "claude" in name or name in ("node.exe", "bun.exe"):
                    procs.append({"name": row[0], "pid": row[1], "mem": row[-1].strip()})
            claude = [p for p in procs if "claude" in p["name"].lower()]
            return {"claude_processes": len(claude), "claude_sample": claude[:10],
                    "node_or_bun": len(procs) - len(claude)}
        out = subprocess.run(["ps", "-eo", "comm"], capture_output=True, text=True, timeout=SUBPROCESS_TIMEOUT_S)
        names = [line.strip() for line in out.stdout.splitlines()[1:]]
        return {
            "claude_processes": sum(1 for n in names if "claude" in n.lower()),
            "node_or_bun": sum(1 for n in names if n in ("node", "bun")),
        }
    except (OSError, subprocess.TimeoutExpired) as exc:
        return {"error": f"process census unavailable: {exc}"}


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
    ap.add_argument("--skip-processes", action="store_true", help="skip the process census subprocess")
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

    if not args.skip_processes:
        report["processes"], report["timings_seconds"]["processes"] = timed(process_census)

    report["advisories"] = advisories(root)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())

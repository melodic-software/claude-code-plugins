#!/usr/bin/env python3
"""Session-start catch-up launcher for the running-retro post-session analysis.

Given the current session's transcript, picks up to two ended sibling sessions
that got no live checks and no analysis, newest first, and spawns observer.py
once for each in a process detached from every Claude Code session's process
tree, so the run outlives the session that launched it. Returns at once.

A sibling is a candidate when its transcript:
  - is not the current session's;
  - has been idle at least --idle-seconds (it counts as ended) and changed
    within the last three days;
  - has no `live-<sid>.jsonl` marker in the work dir (the mod ran live checks);
  - has grown past the byte offset its status file records, or its last
    analysis failed and may run once more (observer.retry_due);
  - has no running-retro ledger naming it, when it has no status file (an
    in-session checkpoint covered it); with a status file the offset decides.

Prints one line per launch (or why none ran) and exits 0: callers
fire-and-forget and never block on it.
"""

from __future__ import annotations

import argparse
import functools
import importlib.util
import os
import subprocess
import sys
import time
from pathlib import Path

MAX_AGE_SECONDS = 3 * 86400
MAX_LAUNCHES = 2


def spawn_detached(cmd: list[str], cwd: str) -> int:
    """Start `cmd` fully detached and return its pid without waiting."""
    kwargs: dict = {
        "cwd": cwd,
        "stdin": subprocess.DEVNULL,
        "stdout": subprocess.DEVNULL,
        "stderr": subprocess.DEVNULL,
    }
    if os.name == "nt":
        # DETACHED_PROCESS | CREATE_NEW_PROCESS_GROUP | CREATE_NO_WINDOW.
        # No CREATE_BREAKAWAY_FROM_JOB: plain detach already escapes the job here.
        kwargs["creationflags"] = 0x00000008 | 0x00000200 | 0x08000000
    else:
        kwargs["start_new_session"] = True
        kwargs["close_fds"] = True
    proc = subprocess.Popen(cmd, **kwargs)  # noqa: S603 -- args are constructed, not shell
    return proc.pid


@functools.cache
def _observer_mod():
    """Load the sibling observer.py once, to share its status and ledger readers."""
    path = Path(__file__).with_name("observer.py")
    spec = importlib.util.spec_from_file_location("observer_mod", str(path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def catch_up_candidates(
    transcript: Path,
    session_id: str,
    work_dir: Path,
    ledger_dir: Path,
    idle_seconds: float,
    now: float | None = None,
) -> list[Path]:
    """Ended sibling transcripts still owed an analysis, newest first, at most two."""
    obs = _observer_mod()
    now = time.time() if now is None else now
    found: list[tuple[float, Path]] = []
    for path in transcript.parent.glob("*.jsonl"):
        sid = path.stem
        if sid == session_id:
            continue
        try:
            st = path.stat()
        except OSError:
            continue
        if not idle_seconds <= now - st.st_mtime <= MAX_AGE_SECONDS:
            continue
        if (work_dir / f"live-{sid}.jsonl").exists():
            continue
        status = obs.read_status(work_dir, sid)
        if obs.stored_offset(status) >= st.st_size and not obs.retry_due(status):
            continue
        if not status and obs.find_session_ledger(ledger_dir, sid) is not None:
            continue
        found.append((st.st_mtime, path))
    found.sort(reverse=True)
    return [path for _, path in found[:MAX_LAUNCHES]]


def main() -> int:
    p = argparse.ArgumentParser(description="session-start catch-up for observer.py")
    p.add_argument("--transcript", required=True, help="current session's transcript")
    p.add_argument("--session-id", default="", help="defaults to transcript stem")
    p.add_argument("--work-dir", required=True)
    p.add_argument("--ledger-dir", required=True)
    p.add_argument("--plugin-root", default="")
    p.add_argument(
        "--idle-seconds",
        type=float,
        default=900.0,
        help="a transcript idle this long counts as ended",
    )
    # Empty = observer.py reads the plugin.json userConfig default.
    p.add_argument("--model", default="")
    p.add_argument("--effort", default="")
    p.add_argument("--min-lines", default="")
    p.add_argument("--analysis", action="store_true")
    p.add_argument("--bare", action="store_true")
    args = p.parse_args()

    observer_py = Path(__file__).with_name("observer.py")
    transcript = Path(args.transcript).resolve()
    work_dir = Path(args.work_dir).resolve()
    ledger_dir = Path(args.ledger_dir).resolve()
    sid = args.session_id or transcript.stem

    picked = catch_up_candidates(
        transcript, sid, work_dir, ledger_dir, args.idle_seconds
    )
    if not picked:
        print("observer: no ended session to catch up")
        return 0
    passthrough = ["--plugin-root", args.plugin_root, "--model", args.model]
    passthrough += ["--effort", args.effort, "--min-lines", args.min_lines]
    passthrough += [f"--{name}" for name in ("analysis", "bare") if getattr(args, name)]
    for path in picked:
        cmd = [
            sys.executable,
            str(observer_py),
            "--transcript",
            str(path),
            "--session-id",
            path.stem,
            "--work-dir",
            str(work_dir),
            "--ledger-dir",
            str(ledger_dir),
            *passthrough,
        ]
        try:
            pid = spawn_detached(cmd, cwd=str(observer_py.parent))
        except Exception as e:  # noqa: BLE001 -- any spawn-time failure must degrade gracefully
            print(f"observer: failed to spawn for {path.stem}: {e}")
            continue
        print(f"observer: catch-up for session {path.stem} (pid {pid})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

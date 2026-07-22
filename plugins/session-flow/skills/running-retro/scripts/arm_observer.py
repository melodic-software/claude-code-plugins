#!/usr/bin/env python3
"""Detached launcher for the running-retro observer.

Spawns observer.py in a process detached from every Claude Code session's
process tree, so it OUTLIVES the session that armed it, then exits immediately.
This is the survival primitive proven in the P16 lifecycle evidence: plain
detach flags put the child outside any Windows Job Object, and the interactive
session's job is neither kill-on-close nor traps children -- so no breakaway
flag is needed. Same primitive whether the caller is the SessionStart hook or
the running-retro `arm` action; only the trigger differs.

Prints the spawned observer PID (or a reason it declined) to stdout and exits 0
-- callers fire-and-forget and never block on it.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path


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


def main() -> int:
    p = argparse.ArgumentParser(description="detached launcher for observer.py")
    # Forwarded verbatim to observer.py:
    p.add_argument("--transcript", required=True)
    p.add_argument("--work-dir", required=True)
    p.add_argument("--ledger-dir", required=True)
    p.add_argument("--session-id", default="")
    p.add_argument("--plugin-root", default="")
    p.add_argument("--topic", default="")
    p.add_argument("--previous-running-retro", default="")
    p.add_argument("--previous-session-id", default="")
    p.add_argument("--model", default="claude-haiku-4-5")
    p.add_argument("--analysis", action="store_true")
    p.add_argument("--bare", action="store_true")
    p.add_argument("--poll-seconds", default="5")
    p.add_argument("--idle-seconds", default="900")
    p.add_argument("--max-seconds", default="86400")
    p.add_argument("--analysis-timeout-seconds", default="600")
    args = p.parse_args()

    transcript = Path(args.transcript)
    if not transcript.exists():
        print(f"observer: transcript not found, not arming: {transcript}")
        return 0

    observer = Path(__file__).with_name("observer.py")
    if not observer.exists():
        print(f"observer: observer.py missing at {observer}")
        return 0

    # Resolve to ABSOLUTE paths against THIS launcher's cwd (the caller's cwd --
    # the consumer project root for the skill entry) before handing them to the
    # detached observer, whose cwd is the scripts dir. A relative --ledger-dir
    # would otherwise land findings under the installed plugin cache instead of
    # the consumer repo. The SessionStart hook already passes absolute paths;
    # abspath is a no-op for those.
    transcript = transcript.resolve()
    work_dir = str(Path(args.work_dir).resolve())
    ledger_dir = str(Path(args.ledger_dir).resolve())

    cmd = [sys.executable, str(observer),
           "--transcript", str(transcript),
           "--work-dir", work_dir,
           "--ledger-dir", ledger_dir,
           "--session-id", args.session_id,
           "--plugin-root", args.plugin_root,
           "--topic", args.topic,
           "--previous-running-retro", args.previous_running_retro,
           "--previous-session-id", args.previous_session_id,
           "--model", args.model,
           "--poll-seconds", str(args.poll_seconds),
           "--idle-seconds", str(args.idle_seconds),
           "--max-seconds", str(args.max_seconds),
           "--analysis-timeout-seconds", str(args.analysis_timeout_seconds)]
    if args.analysis:
        cmd.append("--analysis")
    if args.bare:
        cmd.append("--bare")

    try:
        pid = spawn_detached(cmd, cwd=str(observer.parent))
    except OSError as e:
        print(f"observer: failed to spawn: {e}")
        return 0
    print(f"observer: armed for session {args.session_id or transcript.stem} (pid {pid})")
    return 0


if __name__ == "__main__":
    sys.exit(main())

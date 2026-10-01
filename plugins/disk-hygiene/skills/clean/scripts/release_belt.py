#!/usr/bin/env python3
"""Release the /disk-hygiene:clean session belt for one session.

Writes ``<data-root>/belt-release/<session-id>``. While that file exists, the
belt in ``destructive_guard.py`` stops denying deletion-shaped Bash commands in
that session: each one goes to the normal permission system instead, is
logged to the guard decision record, and shows a notice that the belt is
released. Exact engine calls stay gated either way.

The guard answers this exact invocation with ``ask``, so the user confirms
every release. Usage::

    <hook python> release_belt.py --data-root <authorized root> --session-id <id>
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
from pathlib import Path

RELEASE_DIRNAME = "belt-release"
SESSION_ID = re.compile(r"[A-Za-z0-9][A-Za-z0-9_-]{0,127}")


def valid_session_id(value: object) -> bool:
    return isinstance(value, str) and SESSION_ID.fullmatch(value) is not None


def marker_path(data_root: str, session_id: str) -> Path:
    return Path(data_root) / RELEASE_DIRNAME / session_id


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--data-root", required=True)
    parser.add_argument("--session-id", required=True)
    args = parser.parse_args(argv)
    if not valid_session_id(args.session_id):
        print(f"release_belt: invalid session id {args.session_id!r}", file=sys.stderr)
        return 2
    path = marker_path(args.data_root, args.session_id)
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    # Never write through a planted link: the release prompt must not become a
    # way to overwrite whatever file a link at the marker path points to.
    if path.parent.is_symlink() or not path.parent.is_dir() or path.is_symlink():
        print(f"release_belt: refusing a linked marker path {path}", file=sys.stderr)
        return 2
    flags = os.O_WRONLY | os.O_CREAT | os.O_TRUNC | getattr(os, "O_NOFOLLOW", 0)
    fd = os.open(path, flags, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as handle:
        json.dump({"session_id": args.session_id, "released_at": time.time()}, handle)
    print(
        f"disk-hygiene session belt released for session {args.session_id}. "
        "Deletion-shaped Bash commands now go to the normal permission system "
        f"and are logged; exact engine calls stay gated. Marker: {path}"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())

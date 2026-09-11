"""The file-list transport shared by every collector adapter's `collect` verb.

    collect <lane> <measure> [--paths-from <file>] [<file>...]

A whole repository's scope is thousands of paths, which does not fit in one
argument vector on every platform this plugin runs on (Git Bash under Windows
caps a native process's command line far below Linux). The dispatcher writes
the lane's file list to a file and passes `--paths-from`; positional paths
still work, for a hand invocation or a test, and the two combine in order.

The listing is read with `surrogateescape`, as the dispatcher's scope filter
reads it, so a filename with bytes outside UTF-8 reaches the adapter intact.
"""

from __future__ import annotations

import sys

PATHS_FROM = "--paths-from"


def files_from(args: list[str]) -> list[str]:
    """Expand `--paths-from <file>` within `args` into the paths it lists.

    Exits 2 with a message when the option has no value or the file cannot be
    read: an adapter that measured nothing because its list was missing must
    not report an empty lane as measured.
    """
    files: list[str] = []
    index = 0
    while index < len(args):
        if args[index] != PATHS_FROM:
            files.append(args[index])
            index += 1
            continue
        if index + 1 >= len(args):
            print(f"{PATHS_FROM} needs a file", file=sys.stderr)
            raise SystemExit(2)
        try:
            with open(
                args[index + 1], encoding="utf-8", errors="surrogateescape"
            ) as handle:
                files.extend(line.rstrip("\n") for line in handle if line.strip())
        except OSError as exc:
            print(f"{PATHS_FROM}: {exc}", file=sys.stderr)
            raise SystemExit(2) from exc
        index += 2
    return files

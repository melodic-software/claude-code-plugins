"""The pieces every collector adapter shares: verb dispatch, paths, versions.

Each adapter under this directory implements the same contract
(design/contracts.md section 3) and differs only in the tool it drives, so the
file-list transport, the two path normalizers, the version scrape and the verb
ladder live here once and the per-adapter wording stays in the adapter.

The file-list transport is

    collect <lane> <measure> [--paths-from <file>] [<file>...]

A whole repository's scope is thousands of paths, which does not fit in one
argument vector on every platform this plugin runs on (Git Bash under Windows
caps a native process's command line far below Linux). The dispatcher writes
the lane's file list to a file and passes `--paths-from`; positional paths
still work, for a hand invocation or a test, and the two combine in order.

The listing is read with `surrogateescape`, as the dispatcher's scope filter
reads it, so a filename with bytes outside UTF-8 reaches the adapter intact.

Two path normalizers are kept, because the adapters need both and they are not
the same function: `relative_to_cwd` turns an absolute path a tool printed back
into a working-directory-relative one, and `normalize` collapses a path
lexically without touching whether it is absolute.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from collections.abc import Callable

MIN_PYTHON = (3, 9)
PATHS_FROM = "--paths-from"
UNKNOWN_VERSION = "unknown-version"
VERSION = re.compile(r"(\d+\.\d+(?:\.\d+)?)")


def require_python(script: str) -> None:
    """Exit 2 when the interpreter is below the adapter set's floor."""
    if sys.version_info < MIN_PYTHON:
        print(
            f"{script} needs Python {MIN_PYTHON[0]}.{MIN_PYTHON[1]} or later",
            file=sys.stderr,
        )
        sys.exit(2)


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


def relative_to_cwd(path: str) -> str:
    """Forward slashes, and an absolute path made relative to the cwd.

    A path on another Windows drive has no relative form, so it is returned as
    the tool spelled it rather than raising.
    """
    path = path.replace("\\", "/")
    if os.path.isabs(path):
        try:
            path = os.path.relpath(path, os.getcwd())
        except ValueError:
            return path
    while path.startswith("./"):
        path = path[2:]
    return path.replace("\\", "/")


def normalize(path: str) -> str:
    """Forward slashes, no leading `./`, and `os.path.normpath` applied."""
    path = path.replace("\\", "/")
    while path.startswith("./"):
        path = path[2:]
    return os.path.normpath(path).replace("\\", "/")


def match_path(location: str, wanted_norm: dict[str, str]) -> str | None:
    """Map a path a tool printed back to the path the dispatcher passed.

    Tools that name files by absolute path are matched by exact normalized
    path first and then by path-segment suffix.
    """
    norm = normalize(location)
    if norm in wanted_norm:
        return wanted_norm[norm]
    for key, original in wanted_norm.items():
        if norm.endswith("/" + key):
            return original
    return None


def int_or_none(value: str | None) -> int | None:
    """The integer `value` spells, or None when it is absent or not one."""
    try:
        return int(value) if value is not None else None
    except ValueError:
        return None


def version_in(text: str) -> str | None:
    """The first dotted version number in `text`, or None."""
    match = VERSION.search(text)
    return match.group(1) if match else None


def version_or_unknown(text: str) -> str:
    """The first dotted version number in `text`, or `unknown-version`."""
    found = version_in(text)
    return found if found is not None else UNKNOWN_VERSION


def version_output(exe: str, tool: str, flag: str = "--version") -> str | None:
    """`exe <flag>` output, both streams joined, or None after saying why not.

    A tool that cannot be started is not a version this probe can read, so the
    OSError is reported in the caller's own wording and the probe fails.
    """
    try:
        out = subprocess.run([exe, flag], capture_output=True, text=True, check=False)
    except OSError as exc:
        print(f"{tool} {flag} failed: {exc}", file=sys.stderr)
        return None
    return out.stdout + out.stderr


def dispatch(
    name: str,
    argv: list[str],
    *,
    probe: Callable[[], int],
    measures: Callable[[], None],
    install_hint: str,
    collect: Callable[[str, str, list[str]], int],
    collect_min: int = 2,
) -> int:
    """Run the adapter contract's verb ladder for the adapter called `name`.

    `collect_min` is how many arguments after `collect` the adapter demands
    before it prints its usage line; the adapters do not agree on the figure
    and each keeps the one it has.
    """
    script = f"{name}.py"
    if not argv:
        print(
            f"usage: {script} probe|measures|collect <lane> <measure> <file>...|install_hint",
            file=sys.stderr,
        )
        return 2
    verb, rest = argv[0], argv[1:]
    if verb == "probe":
        return probe()
    if verb == "measures":
        measures()
        return 0
    if verb == "install_hint":
        print(install_hint)
        return 0
    if verb == "collect":
        if len(rest) < collect_min:
            print(
                f"usage: {script} collect <lane> <measure> <file>...", file=sys.stderr
            )
            return 2
        return collect(rest[0], rest[1], files_from(rest[2:]))
    print(f"{script}: unknown verb {verb}", file=sys.stderr)
    return 2

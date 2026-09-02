"""Path spelling between an MSYS shell and a native Windows interpreter.

harness-integrity.md rule 6 says a `D:/...` path handed to bash resolves
nowhere. The MIRROR of that hazard is what this file exists for, and it is just
as live on a mixed host: the `python3` on PATH here is a NATIVE Windows build,
so an MSYS `/d/worktrees/repo/x.py` handed to it is read as a path relative to
the current drive root and resolves to `D:\\d\\worktrees\\repo\\x.py`. That is
nowhere, exactly as the bash case is nowhere.

Left alone, a bash-driven harness passing MSYS paths to a Python probe reports
"target is not a file" for a file that plainly exists, and the next person edits
the harness rather than the spelling.

Worse, the hazard is INTERMITTENT in a way that reads as "it works". MSYS
rewrites POSIX-looking paths in the ARGV it hands a native Windows executable,
so `python x.py --target /d/repo/a.sh` arrives already converted and everything
looks fine. A path carried inside a CONFIG FILE gets no such treatment, so the
identical spelling fails there. A harness whose command line works and whose
config does not is exactly the shape that gets debugged in the wrong place.

Not every MSYS path has a drive letter to fold, either: `/tmp` and `/usr/bin`
are MOUNTS, and no string rule reaches them. `cygpath -w` is asked as the last
resort, because it is the only thing that knows the mount table.

So this resolves the spelling EXPLICITLY and LOUDLY: the literal path is tried
first, the converted spelling only if the literal one does not exist, and the
conversion is reported as a note rather than performed silently. When neither
spelling exists, the caller gets both spellings it tried, so the failure names
the real problem instead of a phantom missing file.

This is not a degradation under rule 2. It resolves two spellings of the SAME
file; it never substitutes a different subject, and it never converts a path
that already resolves.

As a command, for debugging a spelling by hand:

    python pathfix.py <path>
"""

from __future__ import annotations

import os
import pathlib
import re
import shutil
import subprocess
import sys

MSYS_ROOTED = re.compile(r"^/([A-Za-z])(/.*)?$")
DRIVE_LETTER = re.compile(r"^([A-Za-z]):[/\\](.*)$", re.DOTALL)

ON_WINDOWS = os.name == "nt"


def msys_to_native(value: str) -> str:
    """`/d/a/b` -> `D:\\a\\b`. Returns the input unchanged when it is not MSYS-rooted."""
    match = MSYS_ROOTED.match(value)
    if not match:
        return value
    drive = match.group(1).upper()
    rest = (match.group(2) or "/").lstrip("/")
    return f"{drive}:\\{rest.replace('/', os.sep if ON_WINDOWS else '/')}"


def native_to_msys(value: str) -> str:
    """`D:\\a\\b` -> `/d/a/b`. Returns the input unchanged when it has no drive letter."""
    match = DRIVE_LETTER.match(value)
    if not match:
        return value
    drive = match.group(1).lower()
    rest = match.group(2).replace("\\", "/")
    return f"/{drive}/{rest}"


def cygpath_native(value: str) -> str | None:
    """Ask cygpath for the native spelling, or None when it cannot help.

    This is the only branch that can resolve an MSYS MOUNT such as `/tmp` or
    `/usr/bin`, because the mount table is not derivable from the string. It is
    a last resort rather than the first move: a subprocess per path is real cost,
    and it is only ever reached once the cheaper spellings have all failed.
    """
    if not ON_WINDOWS:
        return None
    tool = shutil.which("cygpath")
    if tool is None:
        return None
    try:
        result = subprocess.run(  # noqa: S603 - argv, and the tool came from which()
            [tool, "-w", value],
            capture_output=True,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.strip() or None


def tried(value: str) -> list[str]:
    """Every spelling resolve_existing would attempt, in order, deduplicated."""
    candidates = [value]
    if ON_WINDOWS:
        candidates.append(msys_to_native(value))
        converted = cygpath_native(value)
        if converted:
            candidates.append(converted)
    else:
        candidates.append(native_to_msys(value))
    seen: set[str] = set()
    return [c for c in candidates if c and not (c in seen or seen.add(c))]


def resolve_existing(value: str) -> tuple[pathlib.Path, str | None]:
    """Return (path, note).

    The literal spelling wins whenever it exists, so a path that already works is
    never rewritten, and the expensive cygpath probe is never reached. A
    conversion is reported in the note so it appears in the harness output rather
    than happening behind the operator's back. When nothing resolves, the literal
    spelling comes back with no note and the CALLER raises its own error, which
    is where the domain-specific message belongs.
    """
    literal = pathlib.Path(value)
    if literal.exists():
        return literal, None
    for candidate in tried(value)[1:]:
        path = pathlib.Path(candidate)
        if path.exists():
            return path, (
                f"path spelling converted: {value!r} does not resolve for this "
                f"interpreter, {candidate!r} does. A native Windows interpreter cannot "
                f"read an MSYS /d/... path, which is the mirror of the rule 6 hazard."
            )
    return literal, None


def spellings_message(label: str, value: str) -> str:
    return (
        f"{label} does not exist under any spelling this harness tried: "
        f"{tried(value)}. On a mixed MSYS and native-Windows host the same file has "
        f"two spellings and only one works per interpreter; check which one you meant."
    )


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: python pathfix.py <path>", file=sys.stderr)
        return 2
    path, note = resolve_existing(argv[1])
    print(f"on_windows={ON_WINDOWS}")
    print(f"tried={tried(argv[1])}")
    print(f"resolved={path}")
    print(f"note={note}")
    if not path.exists():
        print(spellings_message("the path", argv[1]), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))

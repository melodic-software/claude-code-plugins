#!/usr/bin/env python3
"""Detect whether ``python3`` on ``PATH`` is a Windows Store App-Execution-Alias stub.

The ``clean`` skill's PreToolUse guard is launched by Claude Code as the literal
command ``python3`` (see ``skills/clean/SKILL.md``). On stock Windows,
``%LOCALAPPDATA%\\Microsoft\\WindowsApps\\python3.exe`` is an *App Execution Alias*
— a zero-length reparse-point stub that opens the Microsoft Store (or exits without
running anything) instead of launching an interpreter. When the guard's launch
resolves to that stub it never executes, so it emits neither exit code 2 nor a
``deny`` permission decision — the only two ways a PreToolUse hook blocks a tool
call — and Claude Code lets the destructive Bash/PowerShell command proceed
UNGUARDED. A naive ``python3 --version`` probe does not surface this cleanly: it
pops the Store or hangs. This probe therefore *inspects* the resolution instead of
executing it.

It classifies what the name ``python3`` resolves to — deliberately ``python3`` and
not ``python``/``py``, because that is the exact command the guard hook runs. The
portable, testable stub signal is: the resolved path has a ``WindowsApps`` path
component AND the file is zero length. A real interpreter — including the Microsoft
Store's genuine Python, which lives under a versioned
``WindowsApps\\PythonSoftwareFoundation.Python.3.x_...\\`` subdirectory — has a
non-zero size and is reported ``ok``. On Windows the stubs additionally carry the
``FILE_ATTRIBUTE_REPARSE_POINT`` attribute (tag ``IO_REPARSE_TAG_APPEXECLINK``);
that is reported as corroborating evidence but is not the cross-platform verdict.

Report-only: exit code is always 0 and the single-line JSON on stdout is the whole
contract. ``--path`` overrides resolution to inspect a specific file (used by the
test suite and available when the caller has already resolved ``python3``).
"""

from __future__ import annotations

import argparse
import json
import shutil
import stat
import sys
from pathlib import Path

_NAME = "python3"
_WINDOWSAPPS_COMPONENT = "windowsapps"
_FILE_ATTRIBUTE_REPARSE_POINT = 0x400


def _under_windowsapps(path: Path) -> bool:
    return any(part.lower() == _WINDOWSAPPS_COMPONENT for part in path.parts)


def _is_reparse_point(st: object) -> bool | None:
    attributes = getattr(st, "st_file_attributes", None)
    if attributes is None:
        return None
    return bool(attributes & _FILE_ATTRIBUTE_REPARSE_POINT)


def _report(
    verdict: str,
    resolved_path: Path | None,
    size: int | None,
    windowsapps: bool,
    reparse_point: bool | None,
    detail: str,
) -> dict[str, object]:
    return {
        "verdict": verdict,
        "name": _NAME,
        "resolved_path": str(resolved_path) if resolved_path is not None else None,
        "size": size,
        "windowsapps": windowsapps,
        "reparse_point": reparse_point,
        "detail": detail,
    }


def classify(path: Path | None) -> dict[str, object]:
    if path is None:
        return _report(
            "not-found",
            None,
            None,
            False,
            None,
            f"{_NAME} does not resolve on PATH. This is a distinct prerequisite gap "
            "from the Store alias stub; install Python and ensure a real interpreter "
            "answers to the name the guard launches.",
        )

    windowsapps = _under_windowsapps(path)
    try:
        st = path.stat()
    except OSError as exc:
        if windowsapps:
            return _report(
                "indeterminate",
                path,
                None,
                True,
                None,
                f"{_NAME} resolves under WindowsApps ({path}) but its size could not "
                f"be read ({exc}); this is consistent with a broken App Execution "
                "Alias stub. Verify manually and disable the alias if it is not a real "
                "interpreter.",
            )
        return _report(
            "indeterminate",
            path,
            None,
            False,
            None,
            f"{_NAME} resolves to {path} but its size could not be read ({exc}); "
            "assuming nothing. Verify the interpreter manually.",
        )

    size = st.st_size
    reparse_point = _is_reparse_point(st)

    if windowsapps and size == 0:
        return _report(
            "store-alias-stub",
            path,
            size,
            True,
            reparse_point,
            f"{_NAME} resolves to a zero-length WindowsApps App Execution Alias stub "
            f"({path}). It opens the Microsoft Store instead of running an interpreter, "
            "so the clean skill's destructive-action guard — launched as `python3` — "
            "never executes and cannot block. Disable the `python3` App execution "
            "alias (Settings > Apps > Advanced app settings > App execution aliases) "
            "or install real Python and ensure it precedes WindowsApps on PATH.",
        )

    return _report(
        "ok",
        path,
        size,
        windowsapps,
        reparse_point,
        f"{_NAME} resolves to a real {size}-byte executable ({path}); it is not the "
        "WindowsApps alias stub.",
    )


def resolve() -> Path | None:
    found = shutil.which(_NAME)
    return Path(found) if found else None


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--path",
        help=f"inspect this specific path instead of resolving {_NAME} on PATH",
    )
    args = parser.parse_args(argv)
    path = Path(args.path) if args.path else resolve()
    print(json.dumps(classify(path)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

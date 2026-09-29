# -*- coding: utf-8 -*-
"""Claude Code CLI version gate for the session-flow scripts.

`harness/hop_chain.py` and the running-retro observer both start `claude -p`
runs and pass `--permission-prompts none` only where the CLI knows the flag.
The gate lives here so the two cannot drift. Stdlib only; Python 3.10+.
"""

from __future__ import annotations

import re
import subprocess

_PERMISSION_PROMPTS_FLOOR = (2, 1, 259)
_CLAUDE_VERSION_CACHE: tuple[int, int, int] | None | bool = False


def parse_claude_version(text: str) -> tuple[int, int, int] | None:
    """First X.Y.Z in `claude --version` output, or None."""
    match = re.search(r"(\d+)\.(\d+)\.(\d+)", text)
    if not match:
        return None
    return tuple(int(part) for part in match.groups())


def claude_version_at_least(claude: str, floor: tuple[int, int, int]) -> bool:
    """True when `claude --version` is at least `floor`. Unknown versions are not."""
    global _CLAUDE_VERSION_CACHE
    if _CLAUDE_VERSION_CACHE is False:
        try:
            proc = subprocess.run(
                [claude, "--version"],
                capture_output=True,
                text=True,
                encoding="utf-8",
                timeout=30,
                check=False,
            )
            _CLAUDE_VERSION_CACHE = parse_claude_version(
                (proc.stdout or "") + (proc.stderr or "")
            )
        except (OSError, subprocess.TimeoutExpired):
            _CLAUDE_VERSION_CACHE = None
    cached = _CLAUDE_VERSION_CACHE
    if not isinstance(cached, tuple):
        return False
    return cached >= floor


def permission_prompts_args(claude: str) -> list[str]:
    """`--permission-prompts none` on Claude Code >= 2.1.259, else nothing.

    The flag keeps the permission mode already on the command line and denies
    only calls that would have prompted. Older CLIs reject it as an unknown option.
    """
    if claude_version_at_least(claude, _PERMISSION_PROMPTS_FLOOR):
        return ["--permission-prompts", "none"]
    return []

#!/usr/bin/env python3
"""Hand ``/disk-hygiene:clean`` the guard's interpreter and data root up front.

Registered as a ``UserPromptExpansion`` hook matching the clean command. Every
engine call must name the guard's absolute Python and its authorized
``--data-root``; without this hook the skill learns both only from a denial,
so each run opened with a deliberately failing tool call (#4215).

Both values come from the guard's own functions, run under the same launcher
and with the same ``--plugin-root`` argument the skill-frontmatter guard gets,
so they are the values that guard will accept. The guard still checks every
call; this hook only saves the discovery round trip.

Report-only: it never blocks the expansion. It always exits 0, and it prints
nothing when it cannot produce the values, which leaves the skill on the
kill-switch probe's ``hook_python`` and ``data_root`` fields.
"""

from __future__ import annotations

import json
import sys

import destructive_guard


def context_text() -> str:
    python = destructive_guard._display_python()
    data_root = destructive_guard._display_data_root(
        destructive_guard.resolve_authorized_data_root()
    )
    if data_root:
        root_line = f'data_root: "{data_root}"'
    else:
        root_line = (
            "data_root: none (the guard resolved no authorized data root, so "
            "every engine call fails closed; its denial names the fix)"
        )
    return (
        "disk-hygiene guard values for this session, resolved by the guard's "
        "own code:\n"
        f'hook_python: "{python}"\n'
        f"{root_line}\n"
        "Use hook_python as <hook-python> and data_root as every --data-root "
        "value."
    )


def main() -> int:
    try:
        sys.stdin.read()
        text = context_text()
    except Exception:  # noqa: BLE001 - a failed hint must never block the command
        return 0
    print(
        json.dumps(
            {
                "hookSpecificOutput": {
                    "hookEventName": "UserPromptExpansion",
                    "additionalContext": text,
                }
            }
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

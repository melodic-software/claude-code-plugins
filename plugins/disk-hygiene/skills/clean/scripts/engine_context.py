#!/usr/bin/env python3
"""Hand ``/disk-hygiene:clean`` the guard's interpreter and data root up front.

Registered as a ``UserPromptExpansion`` hook matching the clean command. Every
engine call must name the guard's absolute Python and its authorized
``--data-root``; without this hook the skill learns both only from a denial,
so each run opened with a deliberately failing tool call (#4215).

Both values come from the guard's own functions, run under the same launcher
and with the same ``--plugin-root`` argument the skill-frontmatter guard gets,
so they are the values that guard will accept. The note also names the
engine's absolute path, so a skill body whose ``${CLAUDE_PLUGIN_ROOT}`` arrived
unexpanded still has a route to it. The guard still checks every call; this
hook only saves the discovery round trip.

Report-only: it never blocks the expansion. It always exits 0, and it prints
nothing when it cannot produce the values, which leaves the skill on the
kill-switch probe's ``hook_python`` and ``data_root`` fields. The launcher
(``hooks/run-python-hook.sh``, context mode) blocks the expansion with a reason
when no Python interpreter resolves, so this script never runs in that case.
"""

from __future__ import annotations

import json
import sys

import destructive_guard


def context_text() -> str:
    python = destructive_guard._display_python()
    engine = destructive_guard._display_path(destructive_guard._engine_script_path())
    data_root = destructive_guard._display_data_root(
        destructive_guard.resolve_authorized_data_root()
    )
    root_line = (
        f'data_root: "{data_root}"'
        if data_root
        else f"data_root: none. {destructive_guard._NO_DATA_ROOT_REASON}"
    )
    return (
        "disk-hygiene guard values:\n"
        f'hook_python: "{python}"\n'
        f'engine: "{engine}"\n'
        f"{root_line}"
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

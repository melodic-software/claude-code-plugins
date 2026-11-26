#!/usr/bin/env python3
"""Hand ``/disk-hygiene:clean`` the guard's interpreter and data root up front.

Registered as a ``UserPromptExpansion`` hook matching the clean command. Every
engine call must name the guard's absolute Python and its authorized
``--data-root``; without this hook the skill learns both only from a denial,
so each run opened with a deliberately failing tool call (#4215).

Both values come from ``lib/install_authority.py``, run under the same launcher
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
from pathlib import Path

_PLUGIN_ROOT = Path(__file__).resolve().parents[3]
_LIB_DIR = _PLUGIN_ROOT / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import install_authority  # noqa: E402  (path set above; plugin-bundled module)


def context_text(argv: list[str] | None = None) -> str:
    args = sys.argv[1:] if argv is None else argv
    auth = install_authority.resolve_install_authority(
        plugin_root=install_authority.parse_plugin_root_arg(args),
        authorized_data_root=install_authority.parse_authorized_data_root_arg(args),
    )
    python = install_authority.display_python()
    engine = install_authority.display_path(
        install_authority.engine_script_path(_PLUGIN_ROOT)
    )
    data_root = install_authority.display_data_root(auth.data_root)
    root_line = (
        f'data_root: "{data_root}"'
        if data_root
        else f"data_root: none. {install_authority.NO_DATA_ROOT_REASON}"
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

#!/usr/bin/env python3
"""Deterministic read of the ``disk_hygiene_enabled`` kill switch (CLI wrapper).

``${user_config.*}`` body-token expansion in skill content is not reliable
enough to carry a safety report: an unexpanded token is indistinguishable from
"unset" and would present the assumed default as the configured value. This
probe reads the effective plugin option through ``lib/killswitch_config.py``
(managed settings plus ``managed-settings.d/*.json`` over user ``settings.json``,
narrowed to this install's ``plugin_id`` when present) and reports the effective
boolean with its provenance, degrading honestly when a definitive read is
impossible.

Report-only: exit code is always 0 and the single-line JSON on stdout is the
whole contract. This report is how the ``clean`` skill self-enforces audit-only
mode when a body token arrives unexpanded.

The report also carries ``hook_python`` and ``data_root``: the absolute
interpreter and the ``--data-root`` value the destructive guard admits,
computed by ``lib/install_authority.py`` for this install root.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_PLUGIN_ROOT = Path(__file__).resolve().parents[3]
_LIB_DIR = _PLUGIN_ROOT / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import install_authority  # noqa: E402  (path set above; plugin-bundled module)
import killswitch_config  # noqa: E402  (path set above; plugin-bundled module)

default_settings_path = killswitch_config.default_settings_path
probe = killswitch_config.probe


def report(settings_path: Path) -> dict[str, object]:
    plugin_root = str(_PLUGIN_ROOT)
    plugin_id = install_authority.plugin_id_from_root(plugin_root)
    return {
        **killswitch_config.probe_effective(
            settings_path,
            killswitch_config.managed_settings_path(),
            plugin_id,
        ),
        **install_authority.launch_disclosure(plugin_root),
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--settings-file",
        help="settings.json to probe (default: $CLAUDE_CONFIG_DIR/settings.json "
        "or ~/.claude/settings.json)",
    )
    args = parser.parse_args(argv)
    settings_path = (
        Path(args.settings_file) if args.settings_file else default_settings_path()
    )
    print(json.dumps(report(settings_path)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

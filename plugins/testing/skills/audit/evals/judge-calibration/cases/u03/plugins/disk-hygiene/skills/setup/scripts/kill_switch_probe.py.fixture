#!/usr/bin/env python3
"""Deterministic read of the ``disk_hygiene_enabled`` kill switch (CLI wrapper).

``${user_config.*}`` body-token expansion in skill content is not reliable
enough to carry a safety report: an unexpanded token is indistinguishable from
"unset" and would present the assumed default as the configured value. This
probe reads the merged plugin options where Claude Code stores them —
``pluginConfigs[<plugin-id>].options`` in the user ``settings.json`` — and
reports the effective boolean with its provenance, degrading honestly when a
definitive read is impossible.

The read itself lives in the plugin-level ``lib/killswitch_config.py`` module so
this report-only probe and the destructive-action guard resolve the switch the
same single way (reuse-or-replace: one reader, not two). This file is the
report-only CLI over that reader.

Report-only: exit code is always 0 and the single-line JSON on stdout is the
whole contract. This report is how the ``clean`` skill self-enforces audit-only
mode when a body token arrives unexpanded.

Scope: managed settings and a ``--settings`` flag can also carry
``pluginConfigs`` and are not visible here; the ``detail`` sentence states the
path actually probed so the reader can judge the claim.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import killswitch_config  # noqa: E402  (path set above; plugin-bundled module)

# Re-exported for the setup skill and tests: the read logic and its default
# settings location are the library's, surfaced here unchanged.
default_settings_path = killswitch_config.default_settings_path
probe = killswitch_config.probe


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
    print(json.dumps(probe(settings_path)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""Deterministic read of the ``disk_hygiene_enabled`` kill switch.

``${user_config.*}`` body-token expansion in skill content is not reliable
enough to carry a safety report: an unexpanded token is indistinguishable from
"unset" and would present the assumed default as the configured value. This
probe reads the merged plugin options where Claude Code stores them —
``pluginConfigs[<plugin-id>].options`` in the user ``settings.json`` — and
reports the effective boolean with its provenance, degrading honestly when a
definitive read is impossible.

Report-only: exit code is always 0 and the single-line JSON on stdout is the
whole contract. Enforcement stays with ``destructive_guard.py``, which receives
the runtime-substituted ``--disk-hygiene-enabled`` hook argument.

Scope: managed settings and a ``--settings`` flag can also carry
``pluginConfigs`` and are not visible here; the ``detail`` sentence states the
path actually probed so the reader can judge the claim.
"""

from __future__ import annotations

import argparse
import json
import os
import stat
import sys
from pathlib import Path

_PLUGIN_NAME = "disk-hygiene"
_OPTION_KEY = "disk_hygiene_enabled"


def default_settings_path() -> Path:
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    base = Path(config_dir) if config_dir else Path.home() / ".claude"
    return base / "settings.json"


def _matches_plugin(key: str) -> bool:
    return key == _PLUGIN_NAME or key.startswith(f"{_PLUGIN_NAME}@")


def _interpret(value: object) -> bool | None:
    """Return the boolean meaning of a stored option value, or None if invalid."""
    if isinstance(value, bool):
        return value
    if isinstance(value, str):
        lowered = value.strip().lower()
        if lowered == "true":
            return True
        if lowered == "false":
            return False
    return None


def _report(
    effective: bool,
    source: str,
    degraded: bool,
    detail: str,
    settings_path: Path,
    entries: list[dict[str, object]],
) -> dict[str, object]:
    return {
        "effective": effective,
        "source": source,
        "degraded": degraded,
        "detail": detail,
        "settings_path": str(settings_path),
        "entries": entries,
    }


def probe(settings_path: Path) -> dict[str, object]:
    try:
        settings_stat = settings_path.stat()
    except FileNotFoundError:
        return _report(
            True,
            "default",
            False,
            f"No settings file at {settings_path}; the toggle is not configured "
            "there and the plugin default (enabled) applies. Managed settings or "
            "a --settings flag could still carry a value this probe cannot see.",
            settings_path,
            [],
        )
    except OSError as exc:
        return _report(
            True,
            "indeterminate",
            True,
            f"Could not inspect {settings_path} ({exc}); assuming the default "
            "(enabled). This is an assumption, not the configured value.",
            settings_path,
            [],
        )
    if not stat.S_ISREG(settings_stat.st_mode):
        return _report(
            True,
            "indeterminate",
            True,
            f"{settings_path} exists but is not a regular file; assuming the "
            "default (enabled). This is an assumption, not the configured value.",
            settings_path,
            [],
        )
    try:
        settings = json.loads(settings_path.read_text(encoding="utf-8"))
        if not isinstance(settings, dict):
            raise ValueError("settings root is not a JSON object")
    except (OSError, UnicodeDecodeError, ValueError) as exc:
        return _report(
            True,
            "indeterminate",
            True,
            f"Could not read the configured toggle from {settings_path} ({exc}); "
            "assuming the default (enabled). This is an assumption, not the "
            "configured value.",
            settings_path,
            [],
        )

    plugin_configs = settings.get("pluginConfigs")
    entries: list[dict[str, object]] = []
    if isinstance(plugin_configs, dict):
        for key in sorted(plugin_configs):
            if not _matches_plugin(key):
                continue
            entry = plugin_configs.get(key)
            options = entry.get("options") if isinstance(entry, dict) else None
            if not isinstance(options, dict) or _OPTION_KEY not in options:
                continue
            entries.append({"key": key, "value": options[_OPTION_KEY]})

    if not entries:
        return _report(
            True,
            "default",
            False,
            f"{settings_path} carries no {_PLUGIN_NAME} {_OPTION_KEY} entry; the "
            "toggle is not configured there and the plugin default (enabled) "
            "applies. Managed settings or a --settings flag could still carry a "
            "value this probe cannot see.",
            settings_path,
            entries,
        )

    interpreted = {entry["key"]: _interpret(entry["value"]) for entry in entries}
    values = set(interpreted.values())
    if None in values:
        return _report(
            True,
            "indeterminate",
            True,
            "A configured value is not a recognizable boolean "
            f"({json.dumps({k: e['value'] for k, e in zip(interpreted, entries)})}); "
            "assuming the default (enabled). This is an assumption, not the "
            "configured value.",
            settings_path,
            entries,
        )
    if len(values) > 1:
        return _report(
            True,
            "indeterminate",
            True,
            "Multiple disk-hygiene entries disagree on the toggle "
            f"({json.dumps(interpreted)}); assuming the default (enabled). This "
            "is an assumption, not the configured value.",
            settings_path,
            entries,
        )
    effective = values.pop()
    assert effective is not None
    return _report(
        effective,
        "configured",
        False,
        f"{_OPTION_KEY} is configured {str(effective).lower()} in "
        f"{settings_path}.",
        settings_path,
        entries,
    )


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

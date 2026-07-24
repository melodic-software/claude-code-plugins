"""Single source of truth for reading the ``disk_hygiene_enabled`` kill switch.

Claude Code stores merged plugin options under
``pluginConfigs[<plugin-id>].options`` in the user ``settings.json`` and, since
v2.1.207, reads that key back from user settings, the ``--settings`` flag, and
managed settings only — entries in a project's ``.claude/settings.json`` or
``.claude/settings.local.json`` are ignored
(https://code.claude.com/docs/en/plugins-reference, "User configuration"). That
makes the user settings file the one repo-tamper-resistant channel for a
safety toggle, so both the report-only ``kill_switch_probe`` and the
destructive-action guard resolve the switch by reading it here rather than
trusting the process environment (a repo ``settings.json`` ``env`` block reaches
hook subprocesses and carries no provenance).

``probe()`` returns a full provenance report for the setup skill's honest
"configured vs assumed" reporting; ``resolve_effective()`` is the boolean the
guard needs. Every absent/indeterminate read yields ``effective=True`` — the
switch fails **closed to enabled** (safety on): the guard stays active and gates
every mutation behind a human prompt even when it cannot confirm a configured
value.
"""

from __future__ import annotations

import json
import os
import stat
import sys
from pathlib import Path

PLUGIN_NAME = "disk-hygiene"
OPTION_KEY = "disk_hygiene_enabled"


def default_settings_path() -> Path:
    """The user settings file, honoring ``CLAUDE_CONFIG_DIR`` when relocated."""
    config_dir = os.environ.get("CLAUDE_CONFIG_DIR")
    base = Path(config_dir) if config_dir else Path.home() / ".claude"
    return base / "settings.json"


def managed_settings_path() -> Path | None:
    """The enterprise/managed settings file for this platform, or ``None``.

    Managed settings are the highest-precedence scope Claude Code honors for
    ``pluginConfigs`` and **cannot be overridden** by user/project/local settings
    (settings docs, "Settings precedence"), so an organization can enforce
    audit-only mode there. The file lives at a fixed, root-owned system path per
    platform, so a repo cannot forge it:

    - macOS:      ``/Library/Application Support/ClaudeCode/managed-settings.json``
    - Linux/WSL:  ``/etc/claude-code/managed-settings.json``
    - Windows:    ``C:\\Program Files\\ClaudeCode\\managed-settings.json`` (the
      legacy ``%ProgramData%`` path is unsupported as of Claude Code v2.1.75)

    The Windows path is hard-coded, **not** ``%ProgramFiles%``-derived: a repo
    ``settings.json`` ``env`` block can set ``ProgramFiles`` for hook subprocesses,
    and because managed settings are the highest-precedence scope, an
    environment-derived base path would let a repo point this at a forged
    ``ClaudeCode/managed-settings.json`` that force-enables the switch. The docs
    give this literal absolute path, so trusting it (not the environment) preserves
    the tamper-resistance.

    Residuals not read here: the ``managed-settings.d/`` drop-in directory, and a
    session's ``--settings`` file (a runtime CLI flag a hook cannot observe). A
    value supplied only through those is not honored by the guard.
    """
    if sys.platform == "darwin":
        return Path("/Library/Application Support/ClaudeCode/managed-settings.json")
    if sys.platform == "win32":
        return Path(r"C:\Program Files\ClaudeCode\managed-settings.json")
    if sys.platform.startswith("linux"):
        return Path("/etc/claude-code/managed-settings.json")
    return None


def _matches_plugin(key: str, plugin_id: str | None = None) -> bool:
    """Match a ``pluginConfigs`` key for this plugin.

    With ``plugin_id`` (the exact ``<name>@<marketplace>`` the guard derives from
    its install root) only that key matches — so a second marketplace's
    ``disk-hygiene`` entry cannot mask this install's configured value. Without it
    (the report-only CLI, which cannot know its marketplace) any ``disk-hygiene``
    or ``disk-hygiene@*`` key matches.
    """
    if plugin_id is not None:
        return key == plugin_id
    return key == PLUGIN_NAME or key.startswith(f"{PLUGIN_NAME}@")


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


def probe(settings_path: Path, plugin_id: str | None = None) -> dict[str, object]:
    """Read the effective kill switch from ``settings_path`` with provenance.

    ``plugin_id`` narrows the matched ``pluginConfigs`` key to that exact
    ``<name>@<marketplace>`` (see ``_matches_plugin``); ``None`` matches any
    ``disk-hygiene`` marketplace entry.
    """
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
            if not _matches_plugin(key, plugin_id):
                continue
            entry = plugin_configs.get(key)
            options = entry.get("options") if isinstance(entry, dict) else None
            if not isinstance(options, dict) or OPTION_KEY not in options:
                continue
            entries.append({"key": key, "value": options[OPTION_KEY]})

    if not entries:
        return _report(
            True,
            "default",
            False,
            f"{settings_path} carries no {PLUGIN_NAME} {OPTION_KEY} entry; the "
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
        f"{OPTION_KEY} is configured {str(effective).lower()} in "
        f"{settings_path}.",
        settings_path,
        entries,
    )


def resolve_effective(
    settings_path: Path,
    managed_settings_path: Path | None = None,
    plugin_id: str | None = None,
) -> bool:
    """The boolean kill switch, honoring managed precedence, closed to enabled.

    Managed settings are the highest-precedence, non-overridable scope, so an
    explicitly *configured* value there wins over the user settings — that is how
    an organization enforces audit-only mode. A managed file that is absent, has
    no ``disk_hygiene_enabled`` entry, or is unreadable/ambiguous (any source
    other than ``configured``) yields no managed verdict and the user settings
    decide. Every read is ``probe()``'s effective value, which fails **closed to
    enabled**.
    """
    if managed_settings_path is not None:
        managed = probe(managed_settings_path, plugin_id)
        if managed["source"] == "configured":
            return bool(managed["effective"])
    return bool(probe(settings_path, plugin_id)["effective"])

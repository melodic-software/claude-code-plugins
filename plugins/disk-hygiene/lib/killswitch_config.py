"""Single source of truth for reading the ``disk_hygiene_enabled`` kill switch.

The switch is read from the ``pluginConfigs[<plugin-id>].options`` entry, and
only from the scopes Claude Code honors for that key, never from a project's
settings files. This module is the plugin's one owner of that scope decision;
prose elsewhere in the plugin points here.

- Pointer: when deciding which settings scopes Claude Code reads
  ``pluginConfigs`` from, fetch
  https://code.claude.com/docs/en/settings-reference#pluginconfigs and
  https://code.claude.com/docs/en/settings#change-a-setting-for-one-session
  live.
- As of: 2026-10-11.
- Recheck trigger: either section changes which scopes ``pluginConfigs`` is
  read from, or the settings guide stops letting ``--settings`` set
  user-scope keys.

That makes the user settings file the one repo-tamper-resistant channel for a
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

import errno
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

    The guard reads managed settings so an organization can enforce audit-only
    mode there. The file lives at a fixed system path per platform, never one a
    repo's files or environment can redirect. Whether a process running as the
    user can write that path differs by platform (pointer below): on WSL the
    ``/etc/claude-code`` directory is user-writable, so the file is not an
    admin-only channel everywhere and its presence alone proves nothing about
    who wrote it. On Linux and WSL the guard therefore honors a value that
    enables execution from a managed file only when that file is root-owned and
    not writable by the current user (see ``_is_trusted_managed_file``); a value
    that restricts is honored whoever owns the file. The paths
    below are the ones the guard reads:

    - macOS:      ``/Library/Application Support/ClaudeCode/managed-settings.json``
    - Linux/WSL:  ``/etc/claude-code/managed-settings.json``
    - Windows:    ``C:\\Program Files\\ClaudeCode\\managed-settings.json`` (the
      legacy ``%ProgramData%`` path is not read)

    - Pointer: when checking the managed-settings paths, their precedence, or
      which platform's directory a user can write, fetch
      https://code.claude.com/docs/en/managed-settings#deploy-a-managed-settings-file
      and https://code.claude.com/docs/en/managed-settings#present-admin-documents
      live.
    - As of: 2026-10-11.
    - Recheck trigger: either section moves a platform's managed-settings path,
      changes managed-settings precedence, or changes which platforms document
      the directory as user-writable.

    The Windows path is hard-coded, **not** ``%ProgramFiles%``-derived: a repo
    ``settings.json`` ``env`` block can set ``ProgramFiles`` for hook subprocesses,
    and because managed settings are the highest-precedence scope, an
    environment-derived base path would let a repo point this at a forged
    ``ClaudeCode/managed-settings.json`` that force-enables the switch. The docs
    give this literal absolute path, so trusting it (not the environment) preserves
    the tamper-resistance.

    The sibling ``managed-settings.d/`` drop-in directory is also read (see
    ``_managed_settings_files``). The one honored source a hook cannot read is a
    session's ``--settings`` file — a runtime CLI flag no hook observes — so a
    value supplied only there is not enforced by the guard.
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


# The two sentences every non-configured report ends with. Both state that the
# reported value is the plugin default rather than a configured one; the second
# marks the read itself as degraded.
_NOT_CONFIGURED_THERE = (
    "the toggle is not configured there and the plugin default (enabled) "
    "applies. Managed settings or a --settings flag could still carry a value "
    "this probe cannot see."
)
_ASSUMED_DEFAULT = (
    "assuming the default (enabled). This is an assumption, not the configured value."
)


def _unconfigured(
    cause: str, settings_path: Path, entries: list[dict[str, object]]
) -> dict[str, object]:
    """Nothing configured the toggle here, and the read itself was sound."""
    return _report(
        True,
        "default",
        False,
        f"{cause}; {_NOT_CONFIGURED_THERE}",
        settings_path,
        entries,
    )


def _indeterminate(
    cause: str, settings_path: Path, entries: list[dict[str, object]]
) -> dict[str, object]:
    """The read could not reach a configured value; report the default as assumed."""
    return _report(
        True,
        "indeterminate",
        True,
        f"{cause}; {_ASSUMED_DEFAULT}",
        settings_path,
        entries,
    )


def probe(settings_path: Path, plugin_id: str | None = None) -> dict[str, object]:
    """Read the effective kill switch from ``settings_path`` with provenance.

    ``plugin_id`` narrows the matched ``pluginConfigs`` key to that exact
    ``<name>@<marketplace>`` (see ``_matches_plugin``); ``None`` matches any
    ``disk-hygiene`` marketplace entry.
    """
    try:
        settings_stat = settings_path.stat()
    except FileNotFoundError:
        return _unconfigured(f"No settings file at {settings_path}", settings_path, [])
    except OSError as exc:
        return _indeterminate(
            f"Could not inspect {settings_path} ({exc})", settings_path, []
        )
    if not stat.S_ISREG(settings_stat.st_mode):
        return _indeterminate(
            f"{settings_path} exists but is not a regular file", settings_path, []
        )
    try:
        text = settings_path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        return _unreadable(settings_path, exc)
    return _report_from_text(text, settings_path, plugin_id)


def _unreadable(settings_path: Path, exc: Exception) -> dict[str, object]:
    return _indeterminate(
        f"Could not read the configured toggle from {settings_path} ({exc})",
        settings_path,
        [],
    )


def _report_from_text(
    text: str, settings_path: Path, plugin_id: str | None
) -> dict[str, object]:
    """Interpret already-read settings text as ``probe`` does."""
    try:
        settings = json.loads(text)
        if not isinstance(settings, dict):
            raise ValueError("settings root is not a JSON object")
    except ValueError as exc:
        return _unreadable(settings_path, exc)

    plugin_configs = settings.get("pluginConfigs")
    entries: list[dict[str, object]] = []
    if isinstance(plugin_configs, dict):
        for key in sorted(plugin_configs):
            if not _matches_plugin(key, plugin_id):
                continue
            entry = plugin_configs[key]
            options = entry.get("options") if isinstance(entry, dict) else None
            if not isinstance(options, dict) or OPTION_KEY not in options:
                continue
            entries.append({"key": key, "value": options[OPTION_KEY]})

    if not entries:
        return _unconfigured(
            f"{settings_path} carries no {PLUGIN_NAME} {OPTION_KEY} entry",
            settings_path,
            entries,
        )

    interpreted = {entry["key"]: _interpret(entry["value"]) for entry in entries}
    values = set(interpreted.values())
    if None in values:
        configured = {entry["key"]: entry["value"] for entry in entries}
        return _indeterminate(
            "A configured value is not a recognizable boolean "
            f"({json.dumps(configured)})",
            settings_path,
            entries,
        )
    if len(values) > 1:
        return _indeterminate(
            "Multiple disk-hygiene entries disagree on the toggle "
            f"({json.dumps(interpreted)})",
            settings_path,
            entries,
        )
    effective = values.pop()
    assert effective is not None
    return _report(
        effective,
        "configured",
        False,
        f"{OPTION_KEY} is configured {str(effective).lower()} in {settings_path}.",
        settings_path,
        entries,
    )


_MANAGED_DROPIN_DIRNAME = "managed-settings.d"


def _managed_settings_files(managed_settings_path: Path) -> list[Path]:
    """Managed settings files in Claude Code precedence order (later overrides).

    The primary ``managed-settings.json`` first, then every ``*.json`` in the
    sibling ``managed-settings.d/`` drop-in directory in sorted order, so later
    files override earlier ones. All live at the fixed system path, which no
    repo setting can redirect; whether a user can write it is per platform (see
    ``managed_settings_path``).

    Pointer: when checking how drop-ins merge over the primary file, fetch
    https://code.claude.com/docs/en/managed-settings#split-a-file-based-policy-across-teams
    live. As of: 2026-10-11. Recheck trigger: that section changes the merge
    order or the drop-in directory name.
    """
    files: list[Path] = []
    if managed_settings_path.is_file():
        files.append(managed_settings_path)
    dropin = managed_settings_path.parent / _MANAGED_DROPIN_DIRNAME
    if dropin.is_dir():
        files.extend(
            sorted(
                child
                for child in dropin.iterdir()
                if child.suffix == ".json" and child.is_file()
            )
        )
    return files


def _is_trusted_managed_file(path: Path, file_stat: os.stat_result) -> bool:
    """Whether a managed file may carry a value that enables execution.

    ``file_stat`` is the ``fstat`` of the descriptor the settings were read from,
    so the file judged is the file read. On Linux and WSL the managed directory
    can be user-writable (WSL), so a process running as the user could stand in
    for organization policy. A file is trusted there only when it is a regular
    file owned by uid 0 with no group or other write bit; ``os.access`` then
    rejects a file an ACL lets the current user write. The check is per file, so
    each ``managed-settings.d/`` drop-in is judged on its own. Other platforms
    keep their documented admin-only paths and are trusted as before.
    """
    if not sys.platform.startswith("linux"):
        return True
    if not stat.S_ISREG(file_stat.st_mode):
        return False
    if file_stat.st_uid != 0:
        return False
    if file_stat.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        return False
    effective_ids = os.access in os.supports_effective_ids
    if os.geteuid() != 0 and os.access(path, os.W_OK, effective_ids=effective_ids):
        return False
    return True


def _read_managed_file(
    path: Path, plugin_id: str | None
) -> tuple[dict[str, object], bool]:
    """``probe`` one managed file and judge its trust from the same descriptor.

    Reading by path and then checking ownership by path again would let a
    user-writable directory swap the file in between. On Linux the open refuses
    to follow a symlink, so a symlinked file is read through a second open and
    is never trusted to enable; a restriction from it still counts.
    ``O_NONBLOCK`` keeps a FIFO swapped in after listing from hanging the open.
    """
    linux = sys.platform.startswith("linux")
    flags = os.O_RDONLY | getattr(os, "O_NONBLOCK", 0)
    symlinked = False
    try:
        fd = os.open(path, flags | (getattr(os, "O_NOFOLLOW", 0) if linux else 0))
    except OSError as exc:
        if not linux or exc.errno != errno.ELOOP:
            return _unreadable(path, exc), False
        symlinked = True
        try:
            fd = os.open(path, flags)
        except OSError as exc2:
            return _unreadable(path, exc2), False
    with os.fdopen(fd, "rb") as handle:
        file_stat = os.fstat(handle.fileno())
        if not stat.S_ISREG(file_stat.st_mode):
            return _indeterminate(
                f"{path} exists but is not a regular file", path, []
            ), False
        try:
            text = handle.read().decode("utf-8")
        except (OSError, UnicodeDecodeError) as exc:
            return _unreadable(path, exc), False
    trusted = not symlinked and _is_trusted_managed_file(path, file_stat)
    return _report_from_text(text, path, plugin_id), trusted


def _managed_effective(
    managed_settings_path: Path, plugin_id: str | None
) -> bool | None:
    """The managed-scope verdict, or ``None`` when managed configures no value.

    Reads the primary managed file and the ``managed-settings.d/`` drop-ins in
    precedence order; the last file that *configures* ``disk_hygiene_enabled``
    wins (drop-ins override the primary, later drop-ins override earlier), mirroring
    Claude Code's merge. A file that is absent, carries no entry, or is
    unreadable/ambiguous contributes no verdict. A file that configures the
    switch to enabled but fails ``_is_trusted_managed_file`` contributes no
    verdict either, so it cannot force-enable over the user's setting; a
    configured restriction counts from any file.
    """
    verdict: bool | None = None
    for path in _managed_settings_files(managed_settings_path):
        report, trusted = _read_managed_file(path, plugin_id)
        if report["source"] != "configured":
            continue
        effective = bool(report["effective"])
        if effective and not trusted:
            continue
        verdict = effective
    return verdict


def resolve_effective(
    settings_path: Path | None,
    managed_settings_path: Path | None = None,
    plugin_id: str | None = None,
) -> bool:
    """The boolean kill switch, honoring managed precedence, closed to enabled.

    Managed settings are the highest-precedence, non-overridable scope, so an
    explicitly *configured* value there — in ``managed-settings.json`` or a
    ``managed-settings.d/`` drop-in — wins over the user settings, which is how an
    organization enforces audit-only mode. A value that enables execution counts
    only from a trusted file (``_is_trusted_managed_file``). When managed
    configures no value (all managed sources absent, entry-less, untrusted
    enabling, or unreadable/ambiguous) the user settings decide.

    ``settings_path`` is ``None`` when the caller has no *trusted* user-settings
    location (e.g. a ``--plugin-dir`` install whose root carries no ``plugins/cache``
    marker and sits in no local-directory marketplace, where the only remaining
    locator would be a repo-tamperable environment variable). In that case the
    user scope contributes no verdict and, absent a managed one, the switch
    fails **closed to enabled**. Every file read is
    ``probe()``'s effective value, itself closed to enabled.
    """
    if managed_settings_path is not None:
        managed_verdict = _managed_effective(managed_settings_path, plugin_id)
        if managed_verdict is not None:
            return managed_verdict
    if settings_path is None:
        return True
    return bool(probe(settings_path, plugin_id)["effective"])

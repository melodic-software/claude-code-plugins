"""Explicit-input install-layout and launch-disclosure authority for disk-hygiene.

Derives the authorized data root, user settings path, plugin identifier, and
launch-disclosure values from explicit inputs (never reading ambient
``sys.argv`` or trusting ``CLAUDE_PLUGIN_DATA``, ``CLAUDE_CONFIG_DIR``,
``HOME``, or ``USERPROFILE``).
"""

from __future__ import annotations

import json
import os
import re
import sys
from collections.abc import Callable, Sequence
from pathlib import Path
from typing import NamedTuple

import killswitch_config

PLUGIN_NAME = killswitch_config.PLUGIN_NAME

AUTHORIZED_DATA_ROOT_FLAG = "--authorized-data-root"
CLAUDE_PLUGIN_DATA_ENV = "CLAUDE_PLUGIN_DATA"
AUTHORIZED_DATA_ROOT_PLACEHOLDER = f"${{{CLAUDE_PLUGIN_DATA_ENV}}}"

PLUGIN_ROOT_FLAG = "--plugin-root"
PLUGIN_ROOT_PLACEHOLDER = "${CLAUDE_PLUGIN_ROOT}"

DATA_ROOT_CHANNEL_DIRECT = "--authorized-data-root argument"
DATA_ROOT_CHANNEL_CACHE = "plugin-cache layout"
DATA_ROOT_CHANNEL_DIRECTORY = "local-directory marketplace install"

NO_DATA_ROOT_REASON = (
    "No authorized data root resolved, so every engine call is denied. "
    "Recovery: run this plugin from a marketplace install, or register its "
    "checkout with claude plugin marketplace add <checkout>."
)

_PLUGIN_CACHE_DIRNAME = "cache"
_PLUGINS_DIRNAME = "plugins"
_PLUGIN_DATA_DIRNAME = "data"
_PLUGIN_ID_DISALLOWED = re.compile(r"[^A-Za-z0-9_-]")
_KNOWN_MARKETPLACES_FILENAME = "known_marketplaces.json"
_MANIFEST_DIRNAME = ".claude-plugin"
_DIRECTORY_SOURCE = "directory"
_FOLDERID_PROFILE = "5E6C858F-0E22-4760-9AFE-EA3317B67173"
_ENGINE_RELPATH = Path("skills", "clean", "scripts", "hygiene.py")
_UNSET: object = object()


class DirectoryInstall(NamedTuple):
    """What the directory-marketplace channel proves about an install."""

    config_dir: Path
    data_root: str


class InstallAuthority(NamedTuple):
    """Resolved authority facts for one invocation."""

    data_root: str | None
    channel: str | None
    user_settings_path: Path | None
    plugin_id: str | None


def argv_flag_value(argv: Sequence[str], flag: str) -> str | None:
    prefix = f"{flag}="
    for index, token in enumerate(argv):
        if token == flag and index + 1 < len(argv):
            return argv[index + 1]
        if token.startswith(prefix):
            return token[len(prefix) :]
    return None


def parse_plugin_root_arg(argv: Sequence[str]) -> str | None:
    value = argv_flag_value(argv, PLUGIN_ROOT_FLAG)
    return value if value and value != PLUGIN_ROOT_PLACEHOLDER else None


def parse_authorized_data_root_arg(argv: Sequence[str]) -> str | None:
    value = argv_flag_value(argv, AUTHORIZED_DATA_ROOT_FLAG)
    return value if value and value != AUTHORIZED_DATA_ROOT_PLACEHOLDER else None


def plugins_cache_index(parts: tuple[str, ...]) -> int | None:
    for index in range(1, len(parts)):
        if (
            parts[index].casefold() == _PLUGIN_CACHE_DIRNAME
            and parts[index - 1].casefold() == _PLUGINS_DIRNAME
        ):
            return index
    return None


def cache_install_segments(parts: tuple[str, ...]) -> tuple[int, str, str] | None:
    index = plugins_cache_index(parts)
    if index is None or index + 2 >= len(parts):
        return None
    marketplace, name = parts[index + 1], parts[index + 2]
    if not marketplace or not name:
        return None
    return index, marketplace, name


def sanitized_plugin_id(name: str, marketplace: str) -> str:
    return _PLUGIN_ID_DISALLOWED.sub("-", f"{name}@{marketplace}")


def plugin_data_root_from_root(plugin_root: str) -> str | None:
    parts = Path(plugin_root).parts
    segments = cache_install_segments(parts)
    if segments is None:
        return None
    index, marketplace, name = segments
    plugins_dir = Path(*parts[:index])
    return os.fspath(
        plugins_dir / _PLUGIN_DATA_DIRNAME / sanitized_plugin_id(name, marketplace)
    )


def user_settings_path_from_root(plugin_root: str) -> str | None:
    parts = Path(plugin_root).parts
    index = plugins_cache_index(parts)
    if index is None:
        return None
    plugins_dir = Path(*parts[:index])
    return os.fspath(plugins_dir.parent / "settings.json")


def plugin_id_from_root(plugin_root: str) -> str | None:
    segments = cache_install_segments(Path(plugin_root).parts)
    if segments is None:
        return None
    _, marketplace, name = segments
    return f"{name}@{marketplace}"


def plugin_cache_family_root(code_anchor: str | Path) -> str | None:
    parts = Path(code_anchor).resolve().parts
    segments = cache_install_segments(parts)
    if segments is None:
        return None
    return os.path.normcase(os.fspath(Path(*parts[: segments[0] + 3])))


def account_home() -> Path:
    """Resolve the OS account home directory without trusting environment vars."""
    if os.name != "nt":
        import pwd

        return Path(pwd.getpwuid(os.geteuid()).pw_dir)
    import ctypes
    import uuid

    guid = (ctypes.c_ubyte * 16).from_buffer_copy(uuid.UUID(_FOLDERID_PROFILE).bytes_le)
    shell32 = ctypes.WinDLL("shell32")
    ole32 = ctypes.WinDLL("ole32")
    known_folder_path = shell32.SHGetKnownFolderPath
    known_folder_path.argtypes = [
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.POINTER(ctypes.c_void_p),
    ]
    known_folder_path.restype = ctypes.c_long
    ole32.CoTaskMemFree.argtypes = [ctypes.c_void_p]
    ole32.CoTaskMemFree.restype = None
    buffer = ctypes.c_void_p()
    try:
        if known_folder_path(ctypes.byref(guid), 0, None, ctypes.byref(buffer)) != 0:
            raise OSError("SHGetKnownFolderPath(FOLDERID_Profile) failed")
        return Path(ctypes.wstring_at(buffer.value))
    finally:
        ole32.CoTaskMemFree(buffer)


def trusted_config_dir(
    account_home_fn: Callable[[], Path] | None = None,
) -> Path | None:
    try:
        home = (account_home_fn or account_home)()
    except Exception:  # noqa: BLE001 - any failure means no trusted anchor
        return None
    if not home.is_absolute():
        return None
    return home / ".claude"


def _read_json_object(path: Path) -> dict | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError, RecursionError):
        return None
    return value if isinstance(value, dict) else None


def _strict_resolve(path: Path) -> Path | None:
    try:
        return path.resolve(strict=True)
    except (OSError, ValueError, RuntimeError):
        return None


def _same_or_within(path: Path, directory: Path) -> bool:
    child = os.path.normcase(os.fspath(path))
    parent = os.path.normcase(os.fspath(directory))
    try:
        return os.path.commonpath([child, parent]) == parent
    except ValueError:
        return False


def _marketplace_entry_root(
    source: object, location: Path, plugin_base: object
) -> Path | None:
    if not isinstance(source, str) or not source or Path(source).anchor:
        return None
    if source.startswith("./"):
        candidate = location / source
    elif isinstance(plugin_base, str) and not Path(plugin_base).anchor:
        candidate = location / plugin_base / source
    else:
        return None
    resolved = _strict_resolve(candidate)
    if resolved is None or not _same_or_within(resolved, location):
        return None
    return resolved


def directory_marketplace_install(
    plugin_root: str, *, config_dir: Path | None
) -> DirectoryInstall | None:
    """Prove ``plugin_root`` is loaded in place from a local-directory marketplace."""
    root = _strict_resolve(Path(plugin_root))
    if config_dir is None or root is None:
        return None
    known = _read_json_object(
        config_dir / _PLUGINS_DIRNAME / _KNOWN_MARKETPLACES_FILENAME
    )
    if known is None:
        return None
    candidates: list[tuple[str, Path]] = []
    for key, entry in known.items():
        if not isinstance(entry, dict):
            continue
        source = entry.get("source")
        location = entry.get("installLocation")
        if not (
            isinstance(source, dict)
            and source.get("source") == _DIRECTORY_SOURCE
            and isinstance(location, str)
            and location
        ):
            continue
        resolved = _strict_resolve(Path(location))
        if resolved is not None and _same_or_within(root, resolved):
            candidates.append((key, resolved))
    if len(candidates) != 1:
        return None
    marketplace, location = candidates[0]
    manifest = _read_json_object(location / _MANIFEST_DIRNAME / "marketplace.json")
    if manifest is None or manifest.get("name") != marketplace:
        return None
    plugins = manifest.get("plugins")
    if not isinstance(plugins, list):
        return None
    metadata = manifest.get("metadata")
    plugin_base = metadata.get("pluginRoot") if isinstance(metadata, dict) else None
    root_key = os.path.normcase(os.fspath(root))
    names = []
    for entry in plugins:
        if not isinstance(entry, dict):
            continue
        entry_root = _marketplace_entry_root(entry.get("source"), location, plugin_base)
        if entry_root and os.path.normcase(os.fspath(entry_root)) == root_key:
            names.append(entry.get("name"))
    if names != [PLUGIN_NAME]:
        return None
    own = _read_json_object(root / _MANIFEST_DIRNAME / "plugin.json")
    if own is None or own.get("name") != PLUGIN_NAME:
        return None
    plugin_id = sanitized_plugin_id(PLUGIN_NAME, marketplace)
    data_root = config_dir / _PLUGINS_DIRNAME / _PLUGIN_DATA_DIRNAME / plugin_id
    return DirectoryInstall(config_dir, os.fspath(data_root))


def _resolve_directory_install(
    plugin_root: str,
    *,
    config_dir: object = _UNSET,
    directory_install_fn: Callable[[str], DirectoryInstall | None] | None = None,
) -> DirectoryInstall | None:
    if plugins_cache_index(Path(plugin_root).parts) is not None:
        return None
    if directory_install_fn is not None:
        return directory_install_fn(plugin_root)
    resolved_config = (
        trusted_config_dir() if config_dir is _UNSET else config_dir  # type: ignore[assignment]
    )
    return directory_marketplace_install(plugin_root, config_dir=resolved_config)


def resolve_install_authority(
    *,
    plugin_root: str | None = None,
    authorized_data_root: str | None = None,
    config_dir: object = _UNSET,
    directory_install_fn: Callable[[str], DirectoryInstall | None] | None = None,
) -> InstallAuthority:
    """Resolve data root, channel, user settings path, and plugin ID explicitly."""
    clean_root = (
        plugin_root
        if plugin_root and plugin_root != PLUGIN_ROOT_PLACEHOLDER
        else None
    )
    clean_direct = (
        authorized_data_root
        if authorized_data_root
        and authorized_data_root != AUTHORIZED_DATA_ROOT_PLACEHOLDER
        else None
    )

    plugin_id = plugin_id_from_root(clean_root) if clean_root else None
    cache_data_root = plugin_data_root_from_root(clean_root) if clean_root else None
    cache_settings = user_settings_path_from_root(clean_root) if clean_root else None
    dir_install: DirectoryInstall | None = None
    if clean_root and cache_data_root is None:
        dir_install = _resolve_directory_install(
            clean_root,
            config_dir=config_dir,
            directory_install_fn=directory_install_fn,
        )

    if clean_direct:
        data_root: str | None = clean_direct
        channel: str | None = DATA_ROOT_CHANNEL_DIRECT
    elif cache_data_root:
        data_root = cache_data_root
        channel = DATA_ROOT_CHANNEL_CACHE
    elif dir_install is not None:
        data_root = dir_install.data_root
        channel = DATA_ROOT_CHANNEL_DIRECTORY
    else:
        data_root = None
        channel = None

    if cache_settings:
        user_settings_path: Path | None = Path(cache_settings)
    elif dir_install is not None:
        user_settings_path = dir_install.config_dir / "settings.json"
    else:
        user_settings_path = None

    return InstallAuthority(
        data_root=data_root,
        channel=channel,
        user_settings_path=user_settings_path,
        plugin_id=plugin_id,
    )


def display_path(path: Path) -> str:
    return os.fspath(path).replace("\\", "/")


def display_python(python_executable: str | None = None) -> str:
    exe = sys.executable if python_executable is None else python_executable
    try:
        runtime = Path(exe).resolve(strict=True)
    except OSError:
        runtime = Path(exe).absolute()
    return display_path(runtime)


def display_data_root(authority: str | None) -> str | None:
    if not authority:
        return None
    return display_path(Path(authority).expanduser().resolve(strict=False))


def engine_script_path(plugin_root: str | Path) -> Path:
    return Path(plugin_root).resolve() / _ENGINE_RELPATH


def launch_disclosure(
    plugin_root: str | None,
    *,
    authorized_data_root: str | None = None,
    config_dir: object = _UNSET,
    python_executable: str | None = None,
    directory_install_fn: Callable[[str], DirectoryInstall | None] | None = None,
) -> dict[str, str | None]:
    """Return ``hook_python`` and ``data_root`` as explicit data."""
    auth = resolve_install_authority(
        plugin_root=plugin_root,
        authorized_data_root=authorized_data_root,
        config_dir=config_dir,
        directory_install_fn=directory_install_fn,
    )
    return {
        "hook_python": display_python(python_executable),
        "data_root": display_data_root(auth.data_root),
    }

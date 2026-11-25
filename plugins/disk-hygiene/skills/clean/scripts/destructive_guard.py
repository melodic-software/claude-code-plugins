#!/usr/bin/env python3
"""Fail-closed skill hook: allow only exact bundled hygiene-engine commands.

Exit-code contract (see ``main`` / ``_decide`` / ``_watchdog_fire``): only ``0``
(a deliberate JSON allow/ask/deny decision on stdout) and ``2`` (a blocking
deny, one-line diagnostic on stderr) are reachable. Any other exit would not
enforce the guard, so every internal failure path that could once fall through
to the interpreter's default (uncaught exception -> exit 1, no diagnostic) now
denies instead (#1423).
Pointer: when checking what a PreToolUse exit code other than 0 or 2 does,
fetch https://code.claude.com/docs/en/hooks#other-exit-codes live. As of:
2026-10-11. Recheck trigger: that section states that a PreToolUse exit code 1
blocks the action, or this plugin's registrations start setting a hook failure
option.

Investigation note for the one observed #1423 occurrence (engine-gate mode,
``exitCode: 1``, empty stderr, ``durationMs: 17054``, Windows, no reproduction):
every filesystem call already reachable from this module's own logic
(``Path.resolve(strict=True)``, ``os.path.samefile``, ``Path.stat``/
``read_text``) already caught ``OSError`` at the call site, so a stall ending
in an ``OSError`` (a plausible shape for an unreachable/slow path — e.g. a
stale network drive letter or UNC path referenced by an ordinary, unrelated
Bash command) would not by itself explain an *uncaught* exception. Two things
follow: (1) the strongest identified candidate for the 17s itself is
``_engine_gate_relevant``'s marker-free fallback, which runs on *every* Bash/
PowerShell command in *every* session (not only disk-hygiene commands) when
resolving the plugin-level engine gate. It calls ``os.path.samefile`` on each
distinct whitespace token (or literal shell word) as written — a slow or
unreachable path argument in an unrelated command is a real, user-reachable
way to stall this hook for longer than milliseconds, and the as-written probe
stays unfiltered because a bare name reaches a link in the working directory —
and on each distinct relative, non-empty word with no drive or the engine's
own, joined to the engine's own directory; (2) empty stderr is not what an
uncaught Python exception normally produces (the default handler writes a
traceback), so an
external kill (antivirus/EDR scanning the ``python3`` process, a transient OS
resource issue) remains an open, unconfirmed possibility this module cannot
fix from inside the interpreter. What IS fixable and is fixed here: the
watchdog below bounds every invocation to an internal deadline so a stall of
this shape denies fast with a diagnostic instead of running indefinitely
toward a harness-level, non-blocking kill; the exit-2 wrapper below fail-closes
any exception this process DOES get to run to completion (rather than only
those already caught by a narrower ``except OSError``).
"""

from __future__ import annotations

import contextlib
import functools
import json
import math
import os
import re
import stat
import sys
import threading
import time
from pathlib import Path
from typing import NamedTuple

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import engine_grammar  # noqa: E402  (path set above; plugin-bundled module)
import guard_decision_log  # noqa: E402  (path set above; plugin-bundled module)
import hook_telemetry  # noqa: E402  (path set above; plugin-bundled module)
import killswitch_config  # noqa: E402  (path set above; plugin-bundled module)


_SHELL_EXPANSION_OR_OPERATOR_CHARS = frozenset("{}$*?[]~`()<>;|&\r\n\t!#")
_WHOLE_WORD_QUOTED = re.compile(r"(?<![^ ])(?P<q>['\"])[^'\"]*(?P=q)(?= |$)")
_BRACES = str.maketrans("", "", "{}")


def _without_quoted_braces(command: str) -> str:
    return _WHOLE_WORD_QUOTED.sub(lambda m: m.group().translate(_BRACES), command)


def decision(value: str, reason: str) -> dict[str, object]:
    payload: dict[str, object] = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": value,
            "permissionDecisionReason": reason,
        }
    }
    notice = _unwritten_marker_notice()
    if notice:
        payload["systemMessage"] = notice
    return payload


_UNWRITTEN_MARKER_ENV_VAR = "DISK_HYGIENE_UNWRITTEN_MARKER"
_PLUGIN_ROOT_TEXT = Path(__file__).resolve().parents[3].as_posix()
_CHECKER_HINT = (
    f'diagnose with: node "{_PLUGIN_ROOT_TEXT}/lib/prerequisites.mjs" check '
    f'"{_PLUGIN_ROOT_TEXT}"'
)


def _unwritten_marker_notice() -> str | None:
    marker = os.environ.get(_UNWRITTEN_MARKER_ENV_VAR)
    if not marker:
        return None
    return (
        f"disk-hygiene: this guard launch could not be recorded in "
        f"{_display_text(marker)}, so the end-of-turn check for a guard that "
        "failed silently may skip it. Make that file writable; "
        f"{_CHECKER_HINT}"
    )


def _telemetry_status_for_permission(value: str) -> str:
    return "blocked" if value == "deny" else "ok"


def _emit_guard_telemetry(
    start: float,
    tool_name: str,
    status: str,
    *,
    decision_value: str | None = None,
) -> None:
    data: dict[str, object] = {"tool": tool_name or ""}
    if decision_value is not None:
        data["decision"] = decision_value
    hook_telemetry.emit(
        "destructive-guard",
        "PreToolUse",
        status,
        start,
        data,
        os.environ.get("CLAUDE_PROJECT_DIR"),
    )


_HOOK_ID = "destructive-guard"


def _record_decision(
    command: str,
    tool_name: str,
    decision_value: str,
    rule: str,
    reason: str | None = None,
) -> None:
    try:
        guard_decision_log.record(
            resolve_authorized_data_root(),
            hook=_HOOK_ID,
            decision=decision_value,
            rule=rule,
            tool=tool_name or "",
            mode=resolve_mode(),
            command=command,
            reason=reason,
        )
    except BaseException:  # noqa: BLE001 - an audit write never changes a verdict
        pass


def _is_current_python(value: str) -> bool:
    if not os.path.isabs(value):
        return False
    try:
        runtime = Path(sys.executable).resolve(strict=True)
        candidate = Path(value).absolute()
        return os.path.normcase(os.fspath(candidate)) == os.path.normcase(
            os.fspath(runtime)
        ) and os.path.samefile(candidate, runtime)
    except OSError:
        return False


def _display_python() -> str:
    try:
        runtime = Path(sys.executable).resolve(strict=True)
    except OSError:
        runtime = Path(sys.executable).absolute()
    return _display_path(runtime)


def _literal_shell_words(
    command: str, *, allow_backslash: bool = False
) -> list[str] | None:
    if not command or any(
        value in _SHELL_EXPANSION_OR_OPERATOR_CHARS
        for value in _without_quoted_braces(command)
    ):
        return None
    words: list[str] = []
    index = 0
    while index < len(command):
        if command[index] == " ":
            index += 1
            continue
        quote = command[index] if command[index] in {"'", '"'} else None
        if quote:
            end = command.find(quote, index + 1)
            if end < 0:
                return None
            word = command[index + 1 : end]
            if not word or "'" in word or '"' in word:
                return None
            if quote == '"' and "\\\\" in word and not allow_backslash:
                return None
            index = end + 1
            if index < len(command) and command[index] != " ":
                return None
        else:
            end = command.find(" ", index)
            if end < 0:
                end = len(command)
            word = command[index:end]
            if (
                not word
                or ("\\" in word and not allow_backslash)
                or "'" in word
                or '"' in word
                or any(value.isspace() for value in word)
            ):
                return None
            index = end
        words.append(word)
    return words


def _script_path_key(value: str) -> str | None:
    try:
        resolved = Path(value).resolve(strict=True)
    except OSError:
        return None
    return os.path.normcase(os.fspath(resolved))


def _data_root_key(value: str) -> str:
    return os.path.normcase(os.fspath(Path(value).expanduser().resolve(strict=False)))


_AUTHORIZED_DATA_ROOT_FLAG = "--authorized-data-root"
_CLAUDE_PLUGIN_DATA_ENV = "CLAUDE_PLUGIN_DATA"
_AUTHORIZED_DATA_ROOT_PLACEHOLDER = f"${{{_CLAUDE_PLUGIN_DATA_ENV}}}"

_PLUGIN_ROOT_FLAG = "--plugin-root"
_PLUGIN_ROOT_PLACEHOLDER = "${CLAUDE_PLUGIN_ROOT}"
_PLUGIN_CACHE_DIRNAME = "cache"
_PLUGINS_DIRNAME = "plugins"
_PLUGIN_DATA_DIRNAME = "data"
_PLUGIN_ID_DISALLOWED = re.compile(r"[^A-Za-z0-9_-]")


def _plugins_cache_index(parts: tuple[str, ...]) -> int | None:
    for index in range(1, len(parts)):
        if (
            parts[index].casefold() == _PLUGIN_CACHE_DIRNAME
            and parts[index - 1].casefold() == _PLUGINS_DIRNAME
        ):
            return index
    return None


def _cache_install_segments(parts: tuple[str, ...]) -> tuple[int, str, str] | None:
    index = _plugins_cache_index(parts)
    if index is None or index + 2 >= len(parts):
        return None
    marketplace, name = parts[index + 1], parts[index + 2]
    if not marketplace or not name:
        return None
    return index, marketplace, name


def _sanitized_plugin_id(name: str, marketplace: str) -> str:
    return _PLUGIN_ID_DISALLOWED.sub("-", f"{name}@{marketplace}")


def _plugin_data_root_from_root(plugin_root: str) -> str | None:
    parts = Path(plugin_root).parts
    segments = _cache_install_segments(parts)
    if segments is None:
        return None
    index, marketplace, name = segments
    plugins_dir = Path(*parts[:index])
    return os.fspath(
        plugins_dir / _PLUGIN_DATA_DIRNAME / _sanitized_plugin_id(name, marketplace)
    )


_KNOWN_MARKETPLACES_FILENAME = "known_marketplaces.json"
_MANIFEST_DIRNAME = ".claude-plugin"
_DIRECTORY_SOURCE = "directory"
_FOLDERID_PROFILE = "5E6C858F-0E22-4760-9AFE-EA3317B67173"


def _account_home() -> Path:
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


def _trusted_config_dir() -> Path | None:
    try:
        home = _account_home()
    except Exception:  # noqa: BLE001 - any failure means no trusted anchor
        return None
    if not home.is_absolute():
        return None
    return home / ".claude"


class _DirectoryInstall(NamedTuple):
    """What the directory-marketplace channel proves about this install."""

    config_dir: Path
    data_root: str


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


@functools.lru_cache(maxsize=8)
def _directory_marketplace_install(plugin_root: str) -> _DirectoryInstall | None:
    """Prove this plugin is loaded in place from a local-directory marketplace.

    Claude Code loads a relative-path plugin from a marketplace added from a
    local directory in place, so its ``${CLAUDE_PLUGIN_ROOT}`` is the source
    checkout and carries no ``plugins/cache`` marker, while
    ``${CLAUDE_PLUGIN_DATA}`` is still ``<config>/plugins/data/<id>`` (plugins
    reference, "Persistent data directory"). This recovers ``<id>`` from the
    trusted config dir's ``plugins/known_marketplaces.json`` (an undocumented
    file) and the marketplace's own manifest, and every unproven step fails
    closed to None:

    - exactly one ``directory``-source entry whose ``installLocation``
      strict-resolves to a directory containing the plugin root;
    - that marketplace's ``.claude-plugin/marketplace.json`` is named for the
      same key;
    - exactly one plugin entry whose relative string ``source`` strict-resolves
      to the plugin root, whose ``name`` is ``disk-hygiene`` and matches the
      root's own ``.claude-plugin/plugin.json``.

    The data root is built ONLY from the trusted config dir and the sanitized
    ``<name>@<marketplace>`` id, never from a path read out of either file.
    Memoized per process: the guard runs once per tool call.
    """
    config_dir = _trusted_config_dir()
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
    name = killswitch_config.PLUGIN_NAME
    if names != [name]:
        return None
    own = _read_json_object(root / _MANIFEST_DIRNAME / "plugin.json")
    if own is None or own.get("name") != name:
        return None
    plugin_id = _sanitized_plugin_id(name, marketplace)
    data_root = config_dir / _PLUGINS_DIRNAME / _PLUGIN_DATA_DIRNAME / plugin_id
    return _DirectoryInstall(config_dir, os.fspath(data_root))


def _directory_install_for(plugin_root: str) -> _DirectoryInstall | None:
    if _plugins_cache_index(Path(plugin_root).parts) is not None:
        return None
    return _directory_marketplace_install(plugin_root)


_MODE_FLAG = "--mode"
_MODE_BELT = "belt"
_MODE_ENGINE_GATE = "engine-gate"
_ENGINE_MARKER = "hygiene.py"


@functools.lru_cache(maxsize=1)
def _plugin_cache_family_root() -> str | None:
    """The tree holding EVERY cached version of THIS plugin, or None.

    Claude Code lays a marketplace plugin out at
    ``<plugins>/cache/<marketplace>/<name>/<version>`` and keeps a replaced
    version's directory on disk after an update, so the sibling of this
    install's version leaf is another *complete copy of this engine* — a
    deletion-capable script that is a genuinely different file from the bundled
    one. That is what makes the "provably a DIFFERENT file" escape wrong here:
    the escape exists so a consumer's own ``tools/hygiene.py`` is not mistaken
    for this engine (#1640, #1611), and a previous version of this plugin is
    not a consumer's tool. Handing it the escape leaves the kill switch
    unenforced against it whenever only the plugin-level gate is armed
    (before the skill-frontmatter belt registers, or in sessions that never
    invoke ``clean``), because the plugin-level gate is the only guard in
    that state (#1805).

    The prefix is derived from this module's OWN path rather than from
    ``--plugin-root``: ``__file__`` is the file actually executing, so it needs
    no argv channel and nothing outside the process can redirect it. A root
    without the ``plugins/cache`` marker (a ``--plugin-dir`` checkout install,
    a plugin loaded in place from a local-directory marketplace, or a working
    tree) yields None and no narrowing applies, which is correct: such an
    install has no cached siblings to protect against, and narrowing there
    would gate a contributor's work on their own checkout.
    """
    parts = Path(__file__).resolve().parts
    segments = _cache_install_segments(parts)
    if segments is None:
        return None
    return os.path.normcase(os.fspath(Path(*parts[: segments[0] + 3])))


def _within_plugin_cache_family(value: str) -> bool:
    family = _plugin_cache_family_root()
    if family is None:
        return False
    try:
        candidate = Path(value).resolve(strict=True)
    except OSError:
        return False
    return _same_or_within(candidate, Path(family))


_ALLOWED_ENGINE_SUBCOMMANDS = engine_grammar.SUBCOMMAND_NAMES

_READONLY_ENGINE_SUBCOMMANDS = frozenset(
    {"scan", "inventory", "preview", "handoff-verify", "catalog"}
)
_MUTATING_ENGINE_SUBCOMMANDS = frozenset({"apply", "handoff-apply"})


def _engine_script_path() -> Path:
    return Path(__file__).resolve().with_name(_ENGINE_MARKER)


def _probe_script_path() -> Path:
    return (
        Path(__file__).resolve().parents[2]
        / "setup"
        / "scripts"
        / "kill_switch_probe.py"
    )


def _display_path(path: Path) -> str:
    return os.fspath(path).replace("\\", "/")


_MARKER_TOKEN_SPLIT = re.compile(r"[^A-Za-z0-9._\-/\\:]+")
_MARKER_TOKEN = re.compile(r"[A-Za-z0-9._\-/\\:]+")
_LINE_CONTINUATION = re.compile(r"\\\r?\n")
_PATH_SEPARATOR = re.compile(r"[/\\:]")
_COARSE_TOKEN = re.compile(r"(?:'[^']*'|\"[^\"]*\"|[^\s'\"])+")
_QUOTE_STRIP = str.maketrans("", "", "'\"")


def _marker_tokens(command: str) -> list[str]:
    unfolded = _LINE_CONTINUATION.sub("", command)
    return [token for token in _MARKER_TOKEN_SPLIT.split(unfolded) if token]


def _marker_tokens_with_words(command: str) -> list[tuple[str, str]]:
    unfolded = _LINE_CONTINUATION.sub("", command)
    words = [
        (match.start(), match.end(), match.group().translate(_QUOTE_STRIP))
        for match in _COARSE_TOKEN.finditer(unfolded)
    ]
    pairs: list[tuple[str, str]] = []
    for match in _MARKER_TOKEN.finditer(unfolded):
        owner = next(
            (
                text
                for start, end, text in words
                if start <= match.start() and match.end() <= end
            ),
            match.group(),
        )
        pairs.append((match.group(), owner))
    return pairs


def _carries_marker(word: str) -> bool:
    name = _PATH_SEPARATOR.split(word.casefold().rstrip("/\\"))[-1]
    return name == _ENGINE_MARKER


def _is_interpreter(word: str) -> bool:
    base = Path(word.casefold()).name
    return base.startswith("python") or base in {"py", "py.exe"}


def _reads_as_engine_payload(word: str) -> bool:
    folded = word.casefold()
    if _carries_marker(word) or _ENGINE_MARKER not in folded:
        return False
    if " " in word:
        first_token = folded.split()[0]
        if _carries_marker(first_token) or _is_interpreter(first_token):
            return True
    return "python" in folded


_POWERSHELL_TYPOGRAPHIC_QUOTES = frozenset("‘’‚‛“”„")
_POWERSHELL_CODE_CHARS = frozenset("$`#()[]{}@&;|<>")
_POWERSHELL_HERE_STRING_OPEN = re.compile(r"@(['\"])[ \t]*\r?\n")
_POWERSHELL_EXECUTORS = frozenset(
    {
        "pwsh",
        "powershell",
        "iex",
        "invoke-expression",
        "start-process",
        "saps",
        "start",
        "cmd",
        "bash",
        "sh",
        "wsl",
        "invoke-item",
        "ii",
        "invoke-command",
        "icm",
        "start-job",
        "sajb",
    }
)
_LAUNCHER_WRAPPERS = frozenset(
    {
        "env",
        "nohup",
        "nice",
        "time",
        "timeout",
        "setsid",
        "stdbuf",
        "sudo",
        "doas",
        "exec",
        "command",
    }
)
_POWERSHELL_INTERPRETER = re.compile(
    r"(?<![\w.\-])(?:py|python[\w.\-]*)(?![\w\-])", re.IGNORECASE
)


def _powershell_without_string_data(command: str) -> str | None:
    if any(char in _POWERSHELL_TYPOGRAPHIC_QUOTES for char in command) or (
        command.lstrip(" \t")[:1] in {"'", '"'}
    ):
        return None
    out: list[str] = []
    index = 0
    while index < len(command):
        here = _POWERSHELL_HERE_STRING_OPEN.match(command, index)
        char = command[index]
        if here:
            quote = here.group(1)
            closer = re.compile(r"\r?\n" + re.escape(quote) + "@").search(
                command, here.end() - 1
            )
            if closer is None:
                return None
            body, index = command[here.end() : closer.start()], closer.end()
        elif char in {"'", '"'}:
            quote = char
            end = command.find(quote, index + 1)
            if end < 0:
                return None
            body, index = command[index + 1 : end], end + 1
        else:
            if char in _POWERSHELL_CODE_CHARS or (char.isspace() and char not in " \t"):
                return None
            out.append(char)
            index += 1
            continue
        if quote == '"' and ("$" in body or "`" in body):
            return None
        out.append("_")
    stripped = "".join(out)
    words = stripped.split()
    if not words or "--%" in words or _POWERSHELL_INTERPRETER.search(stripped):
        return None
    command_word = _PATH_SEPARATOR.split(words[0].casefold())[-1]
    if command_word.endswith(".exe"):
        command_word = command_word[: -len(".exe")]
    if command_word in _POWERSHELL_EXECUTORS or command_word in _LAUNCHER_WRAPPERS:
        return None
    return stripped


_BASH_CODE_CHARS = frozenset("$`\\#;&|<>(){}\r\n")
_BASH_READERS = frozenset({"cat", "head", "tail", "wc", "grep", "rg", "git", "gh"})
_BASH_READER_SUBCOMMANDS = {
    "git": frozenset({"show", "log", "diff", "grep"}),
    "gh": frozenset({"issue", "pr"}),
}
_BASH_QUOTE_STRIP = str.maketrans("", "", "'\"")


def _bash_without_string_data(command: str) -> str | None:
    if "\\" in command:
        return None
    out: list[str] = []
    index = 0
    while index < len(command):
        char = command[index]
        if char in {"'", '"'}:
            end = command.find(char, index + 1)
            if end < 0:
                return None
            if char == '"' and ("$" in command[index:end] or "`" in command[index:end]):
                return None
            out.append("_")
            index = end + 1
            continue
        if char in _BASH_CODE_CHARS:
            return None
        out.append(char)
        index += 1
    words = "".join(out).split()
    if not words or command.lstrip(" \t")[:1] in {"'", '"'}:
        return None
    if words[0] not in _BASH_READERS:
        return None
    subcommands = _BASH_READER_SUBCOMMANDS.get(words[0])
    if subcommands is not None and (len(words) < 2 or words[1] not in subcommands):
        return None
    if any(
        _bash_reader_option_runs_program(words[0], word)
        for word in command.translate(_BASH_QUOTE_STRIP).split()[1:]
    ):
        return None
    return "".join(out)


def _bash_reader_option_runs_program(reader: str, word: str) -> bool:
    if reader == "rg":
        return word.startswith(("--pre", "--hostname-bin"))
    if reader != "git" or not word.startswith("-"):
        return False
    if word.startswith("--"):
        name = word.split("=", 1)[0]
        return len(name) > 2 and (
            "--open-files-in-pager".startswith(name) or "--output".startswith(name)
        )
    return "c" in word or "O" in word


_BASH_QUOTED_HEREDOC = re.compile(
    r"<<-?[ \t]*(['\"])([A-Za-z0-9_]+)\1(?=[ \t\n;&|<>()]|$)"
)
_SED_PRINT_OPTIONS = re.compile(r"-[nErsuz]+")
_SED_LINE_RANGE_PRINT = re.compile(r"\d+(?:,\d+)?p")


def _bash_reads_only(command: str) -> bool:
    segments = _bash_list_segments(command)
    return bool(segments) and all(
        _bash_without_string_data(segment) is not None or _sed_prints_lines(segment)
        for segment in segments
    )


def _bash_list_segments(command: str) -> list[str] | None:
    segments: list[str] = []
    current: list[str] = []
    heredocs: list[tuple[str, bool]] = []
    index = 0
    while index < len(command):
        char = command[index]
        if char == "\\":
            return None
        if char in {"'", '"'}:
            end = command.find(char, index + 1)
            if end < 0 or "\\" in command[index:end]:
                return None
            current.append(command[index : end + 1])
            index = end + 1
            continue
        if command.startswith("<<", index):
            match = _BASH_QUOTED_HEREDOC.match(command, index)
            if match is None:
                return None
            heredocs.append((match.group(2), match.group().startswith("<<-")))
            index = match.end()
            continue
        if char == "\n":
            segments.append("".join(current))
            current = []
            index += 1
            for delimiter, strip_tabs in heredocs:
                index = _heredoc_body_end(command, index, delimiter, strip_tabs)
                if index < 0:
                    return None
            heredocs = []
            continue
        if char in {";", "|"} or command.startswith("&&", index):
            segments.append("".join(current))
            current = []
            index += 2 if command.startswith(("&&", "||"), index) else 1
            continue
        current.append(char)
        index += 1
    if heredocs:
        return None
    segments.append("".join(current))
    return [segment for segment in segments if segment.strip()]


def _heredoc_body_end(
    command: str, index: int, delimiter: str, strip_tabs: bool
) -> int:
    while True:
        newline = command.find("\n", index)
        end = len(command) if newline < 0 else newline
        line = command[index:end]
        if (line.lstrip("\t") if strip_tabs else line) == delimiter:
            return end if newline < 0 else end + 1
        if newline < 0:
            return -1
        index = newline + 1


def _sed_prints_lines(segment: str) -> bool:
    words = _literal_shell_words(segment.strip())
    if not words or words[0] != "sed":
        return False
    rest = words[1:]
    while rest and rest[0].startswith("-"):
        if _SED_PRINT_OPTIONS.fullmatch(rest[0]) is None:
            return False
        rest = rest[1:]
    return (
        len(rest) >= 2
        and _SED_LINE_RANGE_PRINT.fullmatch(rest[0]) is not None
        and not any(word.startswith("-") for word in rest[1:])
    )


def _engine_gate_relevant(command: str, tool_name: str = "Bash") -> bool:

    bundled = _engine_script_path()

    def _samefile(word: str) -> bool:
        try:
            return os.path.samefile(word, bundled)
        except (OSError, ValueError):
            return False

    def _in_engine_dir(word: str) -> bool:
        return _samefile(os.path.join(bundled.parent, word))

    def _same_file_as_bundled(word: str) -> bool:
        return _samefile(word) or (not os.path.isabs(word) and _in_engine_dir(word))

    engine_drive = os.path.splitdrive(bundled.parent)[0].casefold()

    def _names_engine(candidate: str) -> bool:
        return _samefile(candidate) or (
            bool(candidate)
            and not os.path.isabs(candidate)
            and os.path.splitdrive(candidate)[0].casefold() in {"", engine_drive}
            and _in_engine_dir(candidate)
        )

    allow_backslash = tool_name == "PowerShell"
    if not allow_backslash and _bash_reads_only(command):
        return False
    data_free = _powershell_without_string_data(command) if allow_backslash else None
    if data_free is not None:
        if any(
            _samefile(candidate)
            or (_carries_marker(token) and _within_plugin_cache_family(candidate))
            for token, word in _marker_tokens_with_words(command)
            for candidate in (token, word)
        ):
            return True
        written_words = _literal_shell_words(command, allow_backslash=allow_backslash)
        if any(
            _samefile(candidate)
            for candidate in dict.fromkeys(
                [token.strip("'\"") for token in command.split()]
                + ([] if written_words is None else list(written_words))
            )
        ):
            return True
        command = data_free
    marker_candidates = _marker_tokens(command)
    if not any(_carries_marker(token) for token in marker_candidates):
        candidates = list(marker_candidates)
        words = _literal_shell_words(command, allow_backslash=allow_backslash)
        candidates += (
            [token.strip("'\"") for token in command.split()]
            if words is None
            else list(words)
        )
        return any(_names_engine(candidate) for candidate in dict.fromkeys(candidates))
    words = _literal_shell_words(command, allow_backslash=allow_backslash)
    if words is None:
        pairs = _marker_tokens_with_words(command)
        if any(_same_file_as_bundled(token) for token, _ in pairs):
            return True

        def _provably_other_file(token: str, word: str) -> bool:
            return any(
                os.path.isabs(candidate)
                and _script_path_key(candidate) is not None
                and not _samefile(candidate)
                and not _within_plugin_cache_family(candidate)
                for candidate in (token, word)
            )

        marker_pairs = [pair for pair in pairs if _carries_marker(pair[0])]
        if marker_pairs and all(
            _provably_other_file(token, word) for token, word in marker_pairs
        ):
            return False
        return True
    if any(
        _samefile(candidate)
        or (_carries_marker(token) and _within_plugin_cache_family(candidate))
        for token, word in _marker_tokens_with_words(command)
        for candidate in (token, word)
    ):
        return True
    wrapper_indices = [
        index
        for index, word in enumerate(words)
        if Path(word.casefold()).name in _LAUNCHER_WRAPPERS
    ]
    for index, word in enumerate(words):
        if _carries_marker(word):
            if _samefile(word) or _within_plugin_cache_family(word):
                return True
            resolved_key = _script_path_key(word)
            if resolved_key is not None:
                continue
            if (
                index == 0
                or os.path.isabs(word)
                or any(_is_interpreter(w) for w in words[:index])
                or any(w_index < index for w_index in wrapper_indices)
            ):
                return True
            continue
        if _reads_as_engine_payload(word):
            return True
    return False


def resolve_mode() -> str:
    """Resolve which registration surface launched this guard.

    ``belt`` (default) is the skill-frontmatter deployment: deny-by-default Bash
    (with a small read-only supporting allowlist) and deletion-spelling PowerShell
    discipline. Claude Code registers skill-frontmatter ``PreToolUse`` hooks for
    the rest of the session after the skill is invoked (#2618), so this mode
    denies only while a clean run is open and stands down otherwise
    (``_run_open``). ``engine-gate`` is the plugin-level deployment: it cares ONLY about
    engine invocations (kill switch + data-root authority must hold in every
    session), so any command that does not reference the engine defers instantly
    — a plugin-level hook must never tax unrelated work. An unrecognized or
    absent value falls back to ``belt``, the stricter mode.
    """
    value = _argv_flag_value(sys.argv[1:], _MODE_FLAG)
    return value if value in {_MODE_BELT, _MODE_ENGINE_GATE} else _MODE_BELT


def _argv_flag_value(argv: list[str], flag: str) -> str | None:
    prefix = f"{flag}="
    for index, token in enumerate(argv):
        if token == flag and index + 1 < len(argv):
            return argv[index + 1]
        if token.startswith(prefix):
            return token[len(prefix) :]
    return None


def _argv_authorized_data_root(argv: list[str]) -> str | None:
    return _argv_flag_value(argv, _AUTHORIZED_DATA_ROOT_FLAG)


def _plugin_root_argument() -> str | None:
    value = _argv_flag_value(sys.argv[1:], _PLUGIN_ROOT_FLAG)
    return value if value and value != _PLUGIN_ROOT_PLACEHOLDER else None


def resolve_authorized_data_root() -> str | None:
    """Resolve the authoritative data root a skill-frontmatter hook can supply.

    Precedence, highest first:

    1. ``--authorized-data-root`` — a direct path, for a host that can substitute
       ``${CLAUDE_PLUGIN_DATA}`` itself (a plugin ``hooks.json`` hook can; a skill
       hook cannot).
    2. ``--plugin-root ${CLAUDE_PLUGIN_ROOT}`` — the only substitution a skill hook
       receives; the data root is derived from its ``plugins/cache`` layout. This
       is the channel the bundled ``clean`` skill uses.
    3. The same ``--plugin-root`` when it has no cache layout: a plugin loaded in
       place from a local-directory marketplace, proven against the trusted
       config dir's ``known_marketplaces.json`` (``_directory_marketplace_install``).

    The ``CLAUDE_PLUGIN_DATA`` environment variable is never a channel: a repo
    ``settings.json`` ``env`` block can set it, so it carries no provenance. A
    literal, unsubstituted placeholder is treated as absent. Absent every
    channel the guard has no authority and every engine call fails closed.
    """
    return resolve_authorized_data_root_channel()[0]


DATA_ROOT_CHANNEL_DIRECT = "--authorized-data-root argument"
DATA_ROOT_CHANNEL_CACHE = "plugin-cache layout"
DATA_ROOT_CHANNEL_DIRECTORY = "local-directory marketplace install"


def resolve_authorized_data_root_channel() -> tuple[str | None, str | None]:
    """``resolve_authorized_data_root`` plus the name of the channel that won."""
    direct = _argv_authorized_data_root(sys.argv[1:])
    if direct and direct != _AUTHORIZED_DATA_ROOT_PLACEHOLDER:
        return direct, DATA_ROOT_CHANNEL_DIRECT
    return data_root_channel_for_plugin_root(_plugin_root_argument())


def data_root_for_plugin_root(plugin_root: str | None) -> str | None:
    """Steps 2-3 of ``resolve_authorized_data_root`` for a given install root.

    The skill-frontmatter belt reaches its authority here with the substituted
    ``--plugin-root``; the kill-switch probe reaches it with its own install
    root, so the ``--data-root`` it reports is the one the belt will admit.
    """
    return data_root_channel_for_plugin_root(plugin_root)[0]


def data_root_channel_for_plugin_root(
    plugin_root: str | None,
) -> tuple[str | None, str | None]:
    """``data_root_for_plugin_root`` plus the name of the channel that won."""
    if plugin_root:
        derived = _plugin_data_root_from_root(plugin_root)
        if derived:
            return derived, DATA_ROOT_CHANNEL_CACHE
        install = _directory_install_for(plugin_root)
        if install:
            return install.data_root, DATA_ROOT_CHANNEL_DIRECTORY
    return None, None


def _user_settings_path_from_root(plugin_root: str) -> str | None:
    parts = Path(plugin_root).parts
    index = _plugins_cache_index(parts)
    if index is None:
        return None
    plugins_dir = Path(*parts[:index])
    return os.fspath(plugins_dir.parent / "settings.json")


def _plugin_id_from_root(plugin_root: str) -> str | None:
    segments = _cache_install_segments(Path(plugin_root).parts)
    if segments is None:
        return None
    _, marketplace, name = segments
    return f"{name}@{marketplace}"


def _resolve_user_settings_path() -> Path | None:
    plugin_root = _plugin_root_argument()
    if plugin_root:
        derived = _user_settings_path_from_root(plugin_root)
        if derived:
            return Path(derived)
        install = _directory_install_for(plugin_root)
        if install:
            return install.config_dir / "settings.json"
    return None


def resolve_disk_hygiene_enabled() -> bool:
    """Resolve the execution kill switch by reading user-scope ``pluginConfigs``.

    The kill switch is a safety control: ``false`` is audit-only mode and must
    prevent every deletion lane. The guard reads ``disk_hygiene_enabled`` straight
    out of the ``settings.json`` files (``lib/killswitch_config.py``, the single
    reader it shares with the report-only probe) — never the process environment.
    The key is read only from the scopes a project or local ``settings.json``
    cannot write (https://code.claude.com/docs/en/settings-reference#pluginconfigs,
    as of 2026-10-11; recheck when that section changes which scopes the key is
    read from), so a hostile repo cannot flip the switch. The guard reads managed
    settings so an organization can enforce audit-only mode there
    (https://code.claude.com/docs/en/managed-settings#deploy-a-managed-settings-file,
    as of 2026-10-11; recheck when that section moves a platform's
    managed-settings path or stops describing the file as an enforced policy). The ``--settings`` file is a session CLI flag a hook
    cannot observe, the one honored source not read here (see
    ``killswitch_config.managed_settings_path`` for the full residual list). The
    environment is rejected on purpose: a repo ``settings.json`` ``env`` block
    reaches hook subprocesses and carries no provenance a hook could check, so an
    env-borne toggle (or an env-borne user-settings path) would reopen the hole
    this closes — hence the user settings file is located from the tamper-resistant
    ``--plugin-root`` first (see ``_resolve_user_settings_path``), and the managed
    file from its fixed system path. A local-directory marketplace
    install passes no exact ``<name>@<marketplace>`` id, so both reads match
    any ``disk-hygiene`` key, as broad as before that install's user settings
    were read at all: the channel can only add a deny.

    Every absent, unreadable, or ambiguous read fails **closed to enabled**: the
    guard stays active and gates every mutation behind the final human prompt even
    when it cannot confirm a configured value. Both registration surfaces reach
    this one resolver — the plugin-level engine gate and the skill-frontmatter belt
    both run ``main()``, and both receive ``--plugin-root ${CLAUDE_PLUGIN_ROOT}`` —
    so the belt needs no environment channel it does not have.
    """
    plugin_root = _plugin_root_argument()
    plugin_id = _plugin_id_from_root(plugin_root) if plugin_root else None
    return killswitch_config.resolve_effective(
        _resolve_user_settings_path(),
        killswitch_config.managed_settings_path(),
        plugin_id,
    )


def _is_authorized_data_root(value: str, authority: str | None) -> bool:
    return bool(authority) and _data_root_key(value) == _data_root_key(authority)


def _is_authorized_data_root_file(value: str, authority: str | None) -> bool:
    if not authority or not os.path.isabs(value):
        return False
    try:
        path = os.path.normcase(os.path.realpath(value))
        root = os.path.normcase(os.path.realpath(authority))
        return os.path.commonpath(
            [path, root]
        ) == root and not engine_grammar.is_engine_owned(os.path.relpath(path, root))
    except (OSError, ValueError):
        return False


def _engine_external_checks(authority: str | None) -> dict[str, object]:
    return {
        engine_grammar.AUTHORIZED_DATA_ROOT: (
            lambda value: _is_authorized_data_root(value, authority)
        ),
        engine_grammar.AUTHORIZED_DATA_ROOT_FILE: (
            lambda value: _is_authorized_data_root_file(value, authority)
        ),
    }


def _display_data_root(authority: str | None) -> str | None:
    if not authority:
        return None
    return _display_path(Path(authority).expanduser().resolve(strict=False))


def launch_disclosure(plugin_root: str | None) -> dict[str, str | None]:
    """The interpreter and ``--data-root`` the denial guidance names, as data.

    Spelled by the same helpers ``engine_context`` uses, so the kill-switch
    probe and the guard-values note cannot disagree. ``data_root`` is ``None``
    exactly when the guard resolved no authority.
    """
    return {
        "hook_python": _display_python(),
        "data_root": _display_data_root(data_root_for_plugin_root(plugin_root)),
    }


def classify_exact_engine_command(command: str, authority: str | None) -> str | None:
    """Return the subcommand name for one canonical engine invocation, else None.

    The interpreter must be this hook's own absolute Python and the script the
    bundled engine; everything after the subcommand is matched against the
    engine's declared grammar (``lib/engine_grammar.py``), which the engine's
    own parser is built from. The values that grammar cannot judge alone are
    ``--data-root``, where only the authorized root this hook resolved is
    admitted, and the input files, which must sit inside that root. The flag is
    mandatory here although the grammar keeps it optional, so the guard does not
    depend on the engine refusing a state write without it.
    A token check proves presence: the grammar reads flag names only at flag
    positions and refuses any flag-shaped value, so a matched invocation that
    contains the token carries it as a flag.
    """
    tokens = _literal_shell_words(command)
    if tokens is None:
        return None
    if len(tokens) < 3 or not _is_current_python(tokens[0]):
        return None
    if _script_path_key(tokens[1]) != _script_path_key(str(_engine_script_path())):
        return None
    subcommand = tokens[2]
    if subcommand not in _ALLOWED_ENGINE_SUBCOMMANDS:
        return None
    words = tokens[3:]
    if engine_grammar.DATA_ROOT_FLAG in words and engine_grammar.match_invocation(
        subcommand, words, _engine_external_checks(authority)
    ):
        return subcommand
    return None


def is_exact_engine_apply(command: str, authority: str | None) -> bool:
    return classify_exact_engine_command(command, authority) == "apply"


def is_exact_kill_switch_probe(command: str) -> bool:
    """Return True only for the exact, argument-free bundled probe invocation.

    The probe (``skills/setup/scripts/kill_switch_probe.py``) is the
    deterministic, report-only read of the ``disk_hygiene_enabled`` toggle; the
    clean skill runs it when its body token arrives unexpanded. No arguments are
    permitted, so the probed settings file is always the real default location.
    """
    tokens = _literal_shell_words(command)
    if tokens is None or len(tokens) != 2 or not _is_current_python(tokens[0]):
        return False
    return _script_path_key(tokens[1]) == _script_path_key(str(_probe_script_path()))


_READONLY_SUPPORTING_BASH_HEADS = frozenset(
    {
        "ls",
        "test",
        "stat",
        "du",
        "pwd",
        "basename",
        "dirname",
        "find",
        "file",
    }
)
_FIND_SIDE_EFFECT_PRIMARIES = frozenset(
    {
        "-delete",
        "-exec",
        "-execdir",
        "-ok",
        "-okdir",
        "-fprint",
        "-fprint0",
        "-fprintf",
        "-fls",
    }
)


def _parse_bracket_test_words(command: str) -> list[str] | None:
    text = command.strip()
    if len(text) < 2 or text[0] != "[" or text[-1] != "]":
        return None
    interior = text[1:-1]
    if _SHELL_EXPANSION_OR_OPERATOR_CHARS.intersection(
        _without_quoted_braces(interior)
    ):
        return None
    stripped = interior.strip()
    if not stripped:
        return []
    return _literal_shell_words(stripped)


def _is_readonly_find(tokens: list[str]) -> bool:
    return not any(
        token.casefold() in _FIND_SIDE_EFFECT_PRIMARIES for token in tokens[1:]
    )


def _readonly_supporting_basename(head: str) -> str:
    name = _PATH_SEPARATOR.split(head.rstrip("/\\"))[-1]
    if os.name == "nt" and name.lower().endswith((".exe", ".com", ".bat", ".cmd")):
        return name[:-4]
    return name


_TRUSTED_READONLY_BIN_PREFIXES = (
    "/bin/",
    "/usr/bin/",
    "/usr/local/bin/",
    "/sbin/",
    "/usr/sbin/",
    # Ubuntu 25.10+ uutils: /usr/bin/<tool> is a symlink into /usr/lib/cargo/bin/coreutils/.
    # https://bugs.launchpad.net/bugs/2127231
    "/usr/lib/cargo/bin/coreutils/",
    "/mingw64/bin/",
)
_NT_GIT_TRUSTED_BIN_SUBDIRS = (
    ("usr", "bin"),
    ("mingw64", "bin"),
    ("mingw32", "bin"),
)
_NT_SYSTEM_TRUSTED_BIN_SUBDIRS = (
    ("System32",),
    ("SysWOW64",),
)


def _nt_known_git_installation_roots() -> tuple[Path, ...]:
    roots: list[Path] = []
    for key in ("ProgramFiles", "ProgramFiles(x86)"):
        base = os.environ.get(key)
        if not base:
            continue
        try:
            candidate = (Path(base) / "Git").resolve()
        except OSError:
            continue
        if candidate.is_dir():
            roots.append(candidate)
    return tuple(roots)


@functools.lru_cache(maxsize=1)
def _nt_trusted_readonly_bin_roots() -> tuple[Path, ...]:
    """Resolved absolute directories on Windows whose contents the belt trusts.

    Built from well-known Git installation roots (ProgramFiles /
    ProgramFiles(x86) only — not user-writable LocalAppData) and
    ``%SystemRoot%`` — because a SUBSTRING match on a path fragment such as
    ``/git/usr/bin/`` is satisfied by any repository-controlled directory that
    merely spells that fragment (``D:/anyrepo/git/usr/bin/find``), which would
    hard-``allow`` a planted binary carrying an allowlisted basename. Anchoring
    to the resolved root removes that bypass; an unresolvable root contributes
    NO trusted directories. Git roots are never taken from ``PATH``. Environment
    variables still supply the roots — they are not independently attested.
    """
    roots: list[Path] = []
    for git_root in _nt_known_git_installation_roots():
        roots.extend(git_root.joinpath(*parts) for parts in _NT_GIT_TRUSTED_BIN_SUBDIRS)
    system_root = os.environ.get("SystemRoot") or os.environ.get("SYSTEMROOT")
    if system_root:
        try:
            resolved_system = Path(system_root).resolve()
        except OSError:
            pass
        else:
            roots.extend(
                resolved_system.joinpath(*parts)
                for parts in _NT_SYSTEM_TRUSTED_BIN_SUBDIRS
            )
    return tuple(roots)


def _is_within_directory(path: Path, directory: Path) -> bool:
    base = directory.as_posix().casefold().rstrip("/")
    if not base:
        return False
    return path.as_posix().casefold().startswith(base + "/")


def _path_under_trusted_readonly_bin(path: Path) -> bool:
    if not path.is_file():
        return False
    if os.name == "nt" and any(
        _is_within_directory(path, root) for root in _nt_trusted_readonly_bin_roots()
    ):
        return True
    key = path.as_posix()
    return any(key.startswith(prefix) for prefix in _TRUSTED_READONLY_BIN_PREFIXES)


def _trusted_system_readonly_head(head: str) -> bool:
    if not head:
        return False
    if "/" not in head and "\\" not in head:
        return False
    if os.name == "nt" and head.startswith("/") and not head.startswith("//"):
        rel_parts = tuple(part for part in head.split("/") if part)
        if not rel_parts:
            return False
        for git_root in _nt_known_git_installation_roots():
            mapped = git_root.joinpath(*rel_parts)
            for variant in (
                mapped,
                mapped.with_suffix(".exe"),
                mapped.with_suffix(".EXE"),
            ):
                try:
                    resolved = variant.resolve()
                except OSError:
                    continue
                if _path_under_trusted_readonly_bin(resolved):
                    return True
        return False
    candidate = Path(head)
    if not candidate.is_absolute():
        return False
    try:
        resolved = candidate.resolve()
    except OSError:
        return False
    return _path_under_trusted_readonly_bin(resolved)


def _absolute_bracket_test_words(command: str) -> tuple[str, list[str]] | None:
    text = command.strip()
    space = text.find(" ")
    if space < 0:
        return None
    head = text[:space]
    if not head.endswith("["):
        return None
    if "/" not in head and "\\" not in head:
        return None
    rest = text[space + 1 :]
    if rest != "]" and not rest.endswith(" ]"):
        return None
    interior = "" if rest == "]" else rest[:-1].strip()
    if not interior:
        return head, []
    words = _literal_shell_words(interior)
    return None if words is None else (head, words)


def is_exact_readonly_supporting_command(command: str) -> bool:
    """Return True for one literal-form read-only supporting Bash command (#2591).

    The belt remains deny-by-default; this opens only the small inspection set
    needed after the skill-frontmatter hook stays armed for the rest of the
    session (#2618). Engine containment is still the deletion authority.
    Heads must be absolute paths under a trusted system directory — bare names
    are denied because exported shell functions shadow them.
    """
    absolute_bracket = _absolute_bracket_test_words(command)
    if absolute_bracket is not None:
        head, bracket_words = absolute_bracket
        return bool(bracket_words) and _trusted_system_readonly_head(head)
    if _parse_bracket_test_words(command) is not None:
        return False
    tokens = _literal_shell_words(command)
    if not tokens:
        return False
    head = tokens[0]
    basename = _readonly_supporting_basename(head)
    if basename not in _READONLY_SUPPORTING_BASH_HEADS:
        return False
    if not _trusted_system_readonly_head(head):
        return False
    if basename == "find":
        return _is_readonly_find(tokens)
    if basename == "test":
        return len(tokens) >= 2
    return True


_POWERSHELL_MUTATION_WORDS = re.compile(
    r"(?i)(?<![\w./\\-])("
    r"remove-item|rm|rmdir|del|erase|rd|ri|clear-content|clear-recyclebin|rimraf|unlink"
    r"|sendtorecyclebin|deletefile|deletedirectory|removedirectory"
    r"|move-item|rename-item|mv|move|ren|rename"
    r"|set-content|out-file|add-content"
    r"|format-volume|clear-disk|initialize-disk"
    r")(?![\w-])"
)
_POWERSHELL_RELIEF_HEADS = frozenset(
    {
        "write-output",
        "echo",
        "write-host",
        "get-childitem",
        "gci",
        "ls",
        "dir",
        "where-object",
        "where",
        "?",
        "select-object",
        "sort-object",
        "measure-object",
        "select-string",
        "sls",
        "format-table",
        "format-list",
        "out-string",
        "out-null",
        "get-content",
        "gc",
        "cat",
        "test-path",
        "get-item",
    }
)
_POWERSHELL_RELIEF_SUBCOMMANDS = {
    "git": frozenset({"log", "show", "status", "diff", "commit"}),
    "gh": frozenset({"issue", "pr", "search"}),
}
_POWERSHELL_RELIEF_RAW_FALLBACK = re.compile(
    r"[`\x80-\U0010ffff]|[$@]\(|@['\"]|\$\{|--%"
)
_POWERSHELL_QUOTED_LITERAL = re.compile(r"'(?:[^']|'')*'|\"(?:[^\"]|\"\")*\"")
_POWERSHELL_RELIEF_MASKED_FALLBACK = re.compile(r"#|::|\.[\w'$\s]*\(|(?<![>&])&(?!&)")
_POWERSHELL_SEGMENT_SPLIT = re.compile(r"&&|[|;\r\n{}()]")
_POWERSHELL_PIPELINE_VARIABLE = re.compile(r"(?i)\$(?:_|psitem)(?!\w)")


def _powershell_relief_head(segment: str) -> bool:
    words = segment.split()
    head = words[0].lower()
    if head in _POWERSHELL_RELIEF_SUBCOMMANDS:
        return (
            len(words) > 1 and words[1].lower() in _POWERSHELL_RELIEF_SUBCOMMANDS[head]
        )
    if _POWERSHELL_PIPELINE_VARIABLE.match(head):
        return "=" not in segment
    return head in _POWERSHELL_RELIEF_HEADS


def _powershell_mutation_word_text(command: str) -> str:
    if _POWERSHELL_RELIEF_RAW_FALLBACK.search(command):
        return command
    if re.search(r"['\"]", _POWERSHELL_QUOTED_LITERAL.sub("", command)):
        return command
    text = _POWERSHELL_QUOTED_LITERAL.sub("''", command)
    if _POWERSHELL_RELIEF_MASKED_FALLBACK.search(text):
        return command
    for segment in _POWERSHELL_SEGMENT_SPLIT.split(text):
        if segment.strip() and not _powershell_relief_head(segment):
            return command
    return text


_POWERSHELL_NEW_ITEM_FORCE = re.compile(
    r"(?i)(?<![\w./\\-])new-item(?![\w-]).*-force\b"
)
_POWERSHELL_OUTPUT_REDIRECT = re.compile(
    r"(?i)(?<![<>])>(?![=>&])(?![^\S\n]*\$null(?=[\s;|)}]|$))"
)
_POWERSHELL_APPEND_REDIRECT = re.compile(
    r"(?i)(?<![<>])>>(?![^\S\n]*\$null(?=[\s;|)}]|$))"
)
_POWERSHELL_DOTNET_DELETE = re.compile(r"(?i)(::\s*delete|\.\s*delete\s*\()")
_POWERSHELL_ROBOCOPY_PURGE = re.compile(
    r"(?i)(?<![\w-])robocopy(\.exe)?(?![\w-]).*(/mir|/purge|/mov|/move)(?![\w-])"
)
_POWERSHELL_QUALIFIED_DELETE = re.compile(
    r"(?i)[a-z][\w.]*\\(remove-item|clear-content|clear-recyclebin)(?![\w-])"
)
_POWERSHELL_VB_FILESYSTEM_DELETE = re.compile(
    r"(?i)Microsoft\.VisualBasic\.FileIO\.FileSystem\s*\]?\s*::\s*"
    r"Delete(?:File|Directory)\b"
)
_POWERSHELL_SHELL_APP_NAMESPACE_BIN = re.compile(
    r"(?i)NameSpace\s*\(\s*(?:10|0x0*a)\s*\)"
)
_POWERSHELL_SHELL_APP_BIN_ACTION = re.compile(
    r"(?i)(?<![\w])(?:MoveHere|InvokeVerb(?:Ex)?)\b"
)
_POWERSHELL_SHELL_APP_INVOKE_VERB_ARG = re.compile(
    r"(?i)(?<![\w])InvokeVerb(?:Ex)?\s*\(\s*(?P<quote>[\"'])(?P<verb>[^\"']*)(?P=quote)"
)
_SHELL_APP_DELETE_VERB_NAMES = frozenset({"delete"})


def _shell_verb_name_deletes(verb: str) -> bool:
    return verb.replace("&", "").strip().casefold() in _SHELL_APP_DELETE_VERB_NAMES


def _shell_application_recycle_bin_delete_reason(command: str) -> str | None:
    if (
        _POWERSHELL_SHELL_APP_NAMESPACE_BIN.search(command) is not None
        and _POWERSHELL_SHELL_APP_BIN_ACTION.search(command) is not None
    ):
        return (
            "disk-hygiene flagged a Shell.Application NameSpace(10) Recycle Bin "
            "MoveHere/InvokeVerb deletion."
        )
    if any(
        _shell_verb_name_deletes(match.group("verb"))
        for match in _POWERSHELL_SHELL_APP_INVOKE_VERB_ARG.finditer(command)
    ):
        return (
            "disk-hygiene flagged a COM shell delete verb "
            "(InvokeVerb sends the item to the Recycle Bin)."
        )
    return None


def powershell_decision(command: str, enabled: bool) -> tuple[str, str] | None:
    """Return a (decision, reason) pair for a PowerShell command, or None to defer.

    PowerShell stays available for read-only support work (git, gh, metadata
    inspection), so this lane gates known filesystem-mutation spellings and any
    engine invocation rather than denying unknown commands. Engine calls stay on
    the Bash lane's fail-closed deny-unknown guard. A flagged mutation spelling
    resolves against the ``disk_hygiene_enabled`` kill switch: when execution is
    enabled it returns ``permissionDecision: "ask"`` (a hook-issued ask;
    official PreToolUse docs say that value prompts the user to confirm),
    preserving the unsupported-platform manual handoff; in audit-only mode
    (``enabled`` is false) it is denied outright, so the kill switch blocks
    every deletion lane and not only the Bash engine lane.
    """
    if _engine_gate_relevant(command, "PowerShell"):
        return (
            "deny",
            "disk-hygiene engine invocations must go through the Bash tool's "
            "exact guarded command shapes, not PowerShell. To READ the engine "
            "source, use non-shell file tools.",
        )
    verdict = functools.partial(_powershell_mutation_verdict, command=command)
    if _POWERSHELL_VB_FILESYSTEM_DELETE.search(command):
        return verdict(
            enabled,
            "disk-hygiene flagged Microsoft.VisualBasic.FileIO.FileSystem "
            "DeleteFile/DeleteDirectory (Recycle Bin / FileIO deletion).",
        )
    shell_app_recycle_bin = _shell_application_recycle_bin_delete_reason(command)
    if shell_app_recycle_bin is not None:
        return verdict(enabled, shell_app_recycle_bin)
    match = _POWERSHELL_MUTATION_WORDS.search(_powershell_mutation_word_text(command))
    if match:
        return verdict(
            enabled,
            f'disk-hygiene flagged the mutation spelling "{match.group(0)}".',
        )
    if _POWERSHELL_NEW_ITEM_FORCE.search(command):
        return verdict(
            enabled,
            "disk-hygiene flagged New-Item -Force (truncates an existing file).",
        )
    if _POWERSHELL_OUTPUT_REDIRECT.search(
        command
    ) or _POWERSHELL_APPEND_REDIRECT.search(command):
        return verdict(
            enabled,
            "disk-hygiene flagged shell output redirection (may overwrite a file).",
        )
    if _POWERSHELL_DOTNET_DELETE.search(command):
        return verdict(enabled, "disk-hygiene flagged a .NET Delete call.")
    qualified = _POWERSHELL_QUALIFIED_DELETE.search(command)
    if qualified:
        return verdict(
            enabled,
            "disk-hygiene flagged the module-qualified deletion spelling "
            f'"{qualified.group(0)}".',
        )
    if _POWERSHELL_ROBOCOPY_PURGE.search(command):
        return verdict(
            enabled,
            "disk-hygiene flagged a robocopy mirror/purge/move invocation "
            "(mass deletion via mirroring).",
        )
    return None


def _display_text(value: str) -> str:
    return "".join(
        char if char.isprintable() else char.encode("unicode_escape").decode()
        for char in value
    )


_POWERSHELL_LITERAL_PATH = re.compile(
    r"""'([^']*)'|"([^"]*)"|(?<![\w'"])([A-Za-z]:[\\/][^\s'"`;|(){}]*)"""
)


def _powershell_literal_paths(command: str) -> list[str]:
    found: list[str] = []
    for match in _POWERSHELL_LITERAL_PATH.finditer(command):
        value = next(group for group in match.groups() if group is not None).strip()
        if (
            value
            and not value.startswith("-")
            and not any(char in value for char in "$`\r\n")
            and ("\\" in value or "/" in value or re.match(r"[A-Za-z]:", value))
        ):
            found.append(value)
    return list(dict.fromkeys(found))


def _powershell_mutation_verdict(
    enabled: bool, flagged: str, command: str = ""
) -> tuple[str, str]:
    """Deny a flagged PowerShell deletion in audit-only mode; otherwise prompt.

    The prompt also lists the literal paths the command names when they can be
    read from it; any failure keeps the generic text.
    """
    if not enabled:
        return (
            "deny",
            f"{flagged} Disk-hygiene execution is disabled (audit-only mode), so "
            "deletions are blocked on every lane.",
        )
    try:
        paths = _powershell_literal_paths(command)
    except Exception:  # noqa: BLE001 -- text only; the verdict stays "ask"
        paths = []
    named = (
        f" The command contains {len(paths)} path-shaped literal(s), which may not "
        "be every path it acts on: "
        + "; ".join(_display_text(path) for path in paths)
        + "."
        if paths
        else ""
    )
    return (
        "ask",
        f"{flagged}{named} Confirm only if this is the explicitly approved manual "
        "handoff and the command touches exactly the paths you approved.",
    )


_OPERATOR_LABELS = {
    char: label
    for chars, label in (
        ("|", "a pipe"),
        ("<>", "a redirect"),
        (";", "a ';'"),
        ("&", "an '&'"),
        ("$`(){}", "a substitution or expansion"),
        ("*?[]~", "a glob or tilde"),
        ("\r\n\t", "a newline or tab"),
        ("!#", "a '!' or '#'"),
    )
    for char in chars
}


def _unparsable_reason(command: str) -> str:
    for char in _without_quoted_braces(command):
        if char in _OPERATOR_LABELS:
            culprit = f"{_OPERATOR_LABELS[char]} ({char!r})"
            break
    else:
        culprit = (
            "a backslash"
            if "\\" in command
            else "a quote that does not wrap a whole word, or a non-space whitespace character"
        )
    return f"The command contains {culprit}, so it is not one plain literal invocation."


def _resolves_to_engine(word: str) -> bool:
    key = _script_path_key(word)
    return key is not None and key == _script_path_key(str(_engine_script_path()))


def _wrong_python_reason(word: str) -> str:
    return (
        f"{engine_grammar.clip_token(word)} is not this hook's Python; "
        f'the interpreter must be "{_display_python()}".'
    )


def _engine_mismatch_reason(command: str, authority: str | None) -> str:
    tokens = _literal_shell_words(command)
    if tokens is None:
        return _unparsable_reason(command)
    python_ok = _is_current_python(tokens[0])
    operand = (
        None
        if python_ok
        else next((word for word in tokens[1:] if _resolves_to_engine(word)), None)
    )
    payload = (
        None
        if python_ok or operand is not None
        else next((word for word in tokens if _reads_as_engine_payload(word)), None)
    )
    if payload is not None:
        return (
            f"{engine_grammar.clip_token(payload)} holds the engine filename with "
            "an interpreter or as its first word, so the gate reads it as an "
            "engine call."
        )
    if operand is not None:
        named = (
            "is the engine path"
            if os.path.isabs(operand)
            else "resolves to the engine from the current directory"
        )
        read = (
            ""
            if _is_interpreter(tokens[0])
            else " The Read and Grep tools can read it."
        )
        return (
            f"{engine_grammar.clip_token(operand)} {named}, and only a call "
            f'through "{_display_python()}" may name it; '
            f"{engine_grammar.clip_token(tokens[0])} is not that interpreter.{read}"
        )
    if len(tokens) < 3:
        return (
            f"The command has {len(tokens)} word(s); an engine call is "
            "<hook python> <engine script> <subcommand> <flags>."
        )
    if not python_ok:
        return _wrong_python_reason(tokens[0])
    if not _resolves_to_engine(tokens[1]):
        return (
            f"{engine_grammar.clip_token(tokens[1])} is not the bundled engine "
            f'"{_display_path(_engine_script_path())}".'
        )
    subcommand = tokens[2]
    if subcommand not in _ALLOWED_ENGINE_SUBCOMMANDS:
        return (
            f"{engine_grammar.clip_token(subcommand)} is not an engine "
            f"subcommand; use one of {', '.join(_ALLOWED_ENGINE_SUBCOMMANDS)}."
        )
    words = tokens[3:]
    if engine_grammar.DATA_ROOT_FLAG not in words:
        return (
            f"{engine_grammar.DATA_ROOT_FLAG} is missing; every engine call "
            f"passes {engine_grammar.DATA_ROOT_FLAG} with the authorized root."
        )
    return (
        engine_grammar.explain_mismatch(
            subcommand, words, _engine_external_checks(authority)
        )
        or "The arguments do not match the engine grammar."
    )


_NO_DATA_ROOT_REASON = (
    "No authorized data root resolved, so every engine call is denied. "
    "Recovery: run this plugin from a marketplace install, or register its "
    "checkout with claude plugin marketplace add <checkout>."
)


def _bash_denial_reason(command: str | None, authority: str | None) -> str:
    engine = command is not None and _engine_gate_relevant(command)
    wrong_python = False
    if command is None:
        reason = "Not an allowed shape."
    elif engine:
        reason = _engine_mismatch_reason(command, authority)
    else:
        tokens = _literal_shell_words(command)
        wrong_python = (
            bool(tokens)
            and _is_interpreter(tokens[0])
            and not _is_current_python(tokens[0])
        )
        reason = (
            _wrong_python_reason(tokens[0]) if wrong_python else "Not an allowed shape."
        )
    if authority is None and (command is None or engine or wrong_python):
        reason += " " + _NO_DATA_ROOT_REASON
    return reason


def _bash_denial_guidance(
    authority: str | None, mode: str | None = None, command: str | None = None
) -> str:
    resolved = resolve_mode() if mode is None else mode
    reason = _bash_denial_reason(command, authority)
    if resolved == _MODE_ENGINE_GATE:
        return f"disk-hygiene: denied: {reason} Allowed shapes: /disk-hygiene:clean."
    return (
        f"disk-hygiene: denied by the /disk-hygiene:clean session belt: {reason} "
        "Allowed shapes: /disk-hygiene:clean. The belt holds while a clean run is "
        "open: from an engine preview until the run's apply or handoff-apply "
        "writes its report or the preview ends in manual-handoff-lane or blocked, "
        "and from each handoff-verify, until "
        f"{_RUN_IDLE_TIMEOUT_SECONDS / 60:g} minutes pass with no engine call."
    )


_RUN_MARKER_DIRNAME = engine_grammar.RUN_MARKER_DIRNAME
_RUN_IDLE_TIMEOUT_SECONDS = engine_grammar.RUN_IDLE_TIMEOUT_SECONDS


def _run_marker_path(authority: str, session_id: str) -> Path:
    return (
        Path(authority)
        / _RUN_MARKER_DIRNAME
        / engine_grammar.run_marker_filename(session_id)
    )


def _preview_plan_file(words: list[str]) -> str | None:
    plan = _argv_flag_value(words, "--plan")
    if plan:
        return plan
    snapshot = _argv_flag_value(words, "--snapshot")
    tier = _argv_flag_value(words, "--tier")
    return engine_grammar.inline_plan_path(snapshot, tier) if snapshot and tier else None


def _record_run_step(
    command: str, command_kind: str, authority: str | None, session_id: str | None
) -> None:
    if not authority or not session_id:
        return
    try:
        marker = _run_marker_path(authority, session_id)
        words = _literal_shell_words(command) or []
        ends_with: str | None
        if command_kind == "preview" or command_kind in _MUTATING_ENGINE_SUBCOMMANDS:
            ends_with = (
                _preview_plan_file(words)
                if command_kind == "preview"
                else _argv_flag_value(words, "--report")
            )
            if not ends_with:
                return
            ends_with = os.path.abspath(os.path.expanduser(ends_with))
        elif command_kind == "handoff-verify":
            ends_with = None
        else:
            if _run_open(authority, session_id):
                os.utime(marker)
            return
        with engine_grammar.run_marker_lock(marker.parent):
            if ends_with is not None and _manual_lane_open(
                marker, authority, session_id
            ):
                os.utime(marker)
                return
            marker.write_text(
                json.dumps({"version": 1, "ends_with": ends_with}), encoding="utf-8"
            )
    except Exception:  # noqa: BLE001 - run bookkeeping never changes a verdict
        pass


def _manual_lane_open(marker: Path, authority: str, session_id: str) -> bool:
    if not _run_open(authority, session_id):
        return False
    try:
        return json.loads(marker.read_text(encoding="utf-8"))["ends_with"] is None
    except Exception:  # noqa: BLE001 - an unreadable marker keeps the run
        return True


def _run_open(authority: str | None, session_id: str | None) -> bool:
    if not authority or not session_id:
        return True
    try:
        written = _run_marker_path(authority, session_id).stat().st_mtime
    except FileNotFoundError:
        return False
    except Exception:  # noqa: BLE001 - an unreadable marker holds the belt
        return True
    return time.time() - written < _RUN_IDLE_TIMEOUT_SECONDS


def _belt_released(
    command: str, tool_name: str, session_id: str | None, enabled: bool
) -> bool:
    return (
        enabled
        and resolve_mode() != _MODE_ENGINE_GATE
        and not _engine_gate_relevant(command, tool_name)
        and not _run_open(resolve_authorized_data_root(), session_id)
    )


_WATCHDOG_ENV_VAR = "DISK_HYGIENE_GUARD_WATCHDOG_SECONDS"
_WATCHDOG_DEFAULT_SECONDS = 10.0

_EMIT_LOCK = threading.Lock()
_DECISION_EMITTED = False
_COMMAND_UNDER_DECISION: str | None = None


_EMIT_LOCK_WAIT_SECONDS = 0.5


def _emit_decision(payload: dict[str, object]) -> bool:
    global _DECISION_EMITTED
    with _EMIT_LOCK:
        if _DECISION_EMITTED:
            return False
        _DECISION_EMITTED = True
        print(json.dumps(payload))
        return True


def _emit_notice_only() -> None:
    notice = _unwritten_marker_notice()
    if notice:
        _emit_decision({"systemMessage": notice})


def _publish_command_for_watchdog(command: str) -> None:
    global _COMMAND_UNDER_DECISION
    with _EMIT_LOCK:
        _COMMAND_UNDER_DECISION = command


_INVOCATION_TOKEN: object | None = None

_MAIN_RESULT: int | None = None


def _reset_decision_state(main_result: int | None = None) -> None:
    global _DECISION_EMITTED, _COMMAND_UNDER_DECISION, _INVOCATION_TOKEN
    global _MAIN_RESULT
    with _EMIT_LOCK:
        _DECISION_EMITTED = False
        _COMMAND_UNDER_DECISION = None
        _INVOCATION_TOKEN = None
        _MAIN_RESULT = main_result


_DECLARED_HOOK_TIMEOUT_SECONDS = 60.0
_HOOK_STARTUP_HEADROOM_SECONDS = 10.0
_WATCHDOG_MAX_SECONDS = _DECLARED_HOOK_TIMEOUT_SECONDS - _HOOK_STARTUP_HEADROOM_SECONDS


def _watchdog_seconds() -> float:
    raw = os.environ.get(_WATCHDOG_ENV_VAR)
    if not raw:
        return _WATCHDOG_DEFAULT_SECONDS
    try:
        value = float(raw)
    except ValueError:
        return _WATCHDOG_DEFAULT_SECONDS
    if not math.isfinite(value) or value <= 0:
        return _WATCHDOG_DEFAULT_SECONDS
    return min(value, _WATCHDOG_MAX_SECONDS)


def _write_diagnostic(message: str) -> None:
    """Write a deny diagnostic to stderr without ever preempting the deny.

    The deny is carried by the exit code; this line only explains it. Writing
    it is therefore best-effort, and the suppression below is the fail-closed
    behavior rather than a swallowed error: if the hook host has closed or lost
    the stderr pipe, ``print`` raises (``BrokenPipeError``, or ``ValueError`` on
    an already-closed stream) from inside the very handler that is about to
    deny — the exception escapes, ``return 2`` / ``os._exit(2)`` never runs, and
    the process exits with something PreToolUse treats as non-blocking
    (https://code.claude.com/docs/en/hooks#exit-code-output, as of 2026-10-11;
    recheck when that section states that a PreToolUse exit other than 0 or 2
    blocks the action), running the destructive command ungated. Losing the message is acceptable; losing the deny is not.

    On failure fd 2 is pointed at the null device, because a write failure can
    leave data buffered and the interpreter's own shutdown flush of ``sys.stderr``
    would then raise too — that failure exits 120, likewise non-blocking. Both
    fallback steps are best-effort for the same reason as the write itself.
    """
    try:
        print(message, file=sys.stderr, flush=True)
    except BaseException:  # noqa: BLE001 -- deny must outrank the diagnostic; see docstring
        _discard_stream(sys.stderr)


def _discard_stream(stream: object) -> None:
    with contextlib.suppress(BaseException):
        target_fd = stream.fileno()
        null_fd = os.open(os.devnull, os.O_WRONLY)
        try:
            os.dup2(null_fd, target_fd)
        finally:
            if null_fd != target_fd:
                os.close(null_fd)


def _watchdog_marker_present(command: str | None) -> bool:
    if command is None:
        return True
    try:
        return any(_carries_marker(token) for token in _marker_tokens(command))
    except BaseException:  # noqa: BLE001 -- an unclassifiable command is not a safe one
        return True


def _watchdog_fire(deadline: float) -> None:
    """Watchdog callback (background timer thread): decide fast, never hang.

    ``os._exit`` — not ``sys.exit`` — is deliberate: the main thread is
    presumed stuck inside a syscall this callback cannot interrupt or join, so
    this is a hard process exit, the one way this module can still guarantee a
    delivered outcome once cooperative return is no longer an option.

    WHAT the outcome is now depends on what the guard was interrupted doing,
    because "the guard could not decide" and "the guard decided deny" are not
    the same event and must not produce the same result (#3502).

    The deadline is WALL-CLOCK, so it measures contention as readily as it
    measures a stall. On a loaded host — the concurrent-subagent case this
    hook fires under constantly — an ordinary read-only command could cross a
    10s deadline while the guard was still in ``_engine_gate_relevant``'s
    marker-free fallback, and a blanket ``exit 2`` then BLOCKED it. Denying a
    read-only command that the guard, given another moment, would have
    deferred on is a false positive, and a gate that intermittently blocks
    benign work is worse than a slow one: the observed failures all succeeded
    on an identical retry, which is the signature of contention, not of a
    command that deserved denying.

    The downgrade is available in exactly ONE situation, and every other path
    keeps the pre-change ``exit 2``:

    * ``engine-gate`` mode, with a command that provably carries no engine
      marker. Only there is the completed verdict knowably the instant
      plugin-level defer, so ``ask`` is strictly MORE protective than the
      outcome the guard would have reached (a defer emits no decision at all
      and lets the command run) and strictly less blocking than ``exit 2``;
    * ``belt`` mode denies, always. Belt is the skill-frontmatter deployment,
      where Bash is deny-by-default and ``_engine_gate_relevant`` never
      decides the verdict — a marker-free ``rm -rf`` would have been DENIED there, not
      deferred, so downgrading it to a prompt on "the host was slow" would
      convert a deny-by-default guard into one the operator is invited to
      wave through. Belt is also the DEFAULT (``resolve_mode`` falls back to
      it when no ``--mode`` is passed, which is exactly what the skill
      frontmatter does), so a mode-blind classifier fails in the unsafe
      direction;
    * a command carrying the engine marker denies, unchanged;
    * a stall before the payload parsed denies: nothing was seen, so nothing
      can be ruled out.

    EVERY OUTCOME MUST BE SELF-CARRYING OR PROVEN DELIVERED. This is the
    constraint that shapes the branch order below, and it is easy to lose:
    ``exit 2`` needs nothing on stdout (the deny rides the exit status;
    ``_write_diagnostic`` uses stderr), whereas ``exit 0`` asserts that a JSON
    object reached the host — and exit 0 carrying no JSON is read as NO
    DECISION, so the command proceeds unguarded. Adding non-deny outcomes to
    this callback therefore introduced a way to fail open that a deny-only
    callback could not have: any ``exit 0`` taken while a write is merely
    buffered, or still in progress on the main thread, discards it. Hence the
    flush under the lock, and hence the lock-acquisition failure denying rather
    than exiting 0.

    The residual is measured rather than estimated, and it is wider than a
    hard link. ``_watchdog_marker_present`` diverges from
    ``_engine_gate_relevant`` on EXACTLY one set:

        {no token's basename is the engine marker}
            INTERSECT {some candidate is samefile with the bundled engine}

    That is the whole filesystem-IDENTITY class. It includes hard links and
    symlinks under a non-marker name, and — the part worth naming, because
    ``_engine_gate_relevant``'s own docstring says identity is what closes it —
    the Win32 filename-alias spellings: ``hygiene.py.`` (Win32 discards the
    trailing dot, and ``_carries_marker``'s ``rstrip("/\\\\")`` does not),
    ``hygiene.py::$DATA`` (splitting on ``[/\\\\:]`` and taking the last part
    yields the empty string), and 8.3 short names. Each opens the bundled
    engine while none has its basename, so each reaches ``ask`` on expiry in
    engine-gate mode where a completed run would have gated it.

    This residual cannot be closed on this thread: settling identity means
    asking the filesystem, and this classifier must stay syscall-free precisely
    because the main thread is presumed wedged in a filesystem call. Closing it
    would mean resolving identity BEFORE the stall window and publishing the
    verdict alongside the command — but that resolution IS the stall, so there
    is no earlier moment at which it is cheap. It is therefore an accepted
    residual, of the same identity class ``_engine_gate_relevant`` already
    documents accepted residuals within.

    Not in the set, and verified so rather than assumed: the overbreadth
    shapes. ``./python-hygiene.py`` and a quoted ``bash -c 'python3
    test_hygiene.py'`` payload are reported irrelevant by BOTH functions,
    because the marker-free branch short-circuits before the widening rules
    that would have caught them can run. A plain byte copy is a different file
    and is relevant to neither.

    The fail-open this guard exists to prevent is the harness killing a hook
    that produced no ``permissionDecision`` at all (``docs/adr/0004-...``).

    Every branch below ends in exactly ONE ``os._exit`` and nothing follows it,
    so the call is terminal under a mock as well as in a real process — a test
    that patches ``os._exit`` observes one call, not the tail of the function
    running on.
    """
    deny_diagnostic = (
        f"destructive_guard: internal deadline of {deadline:g}s exceeded; "
        f"denying by default. Raise {_WATCHDOG_ENV_VAR} (up to "
        f"{_WATCHDOG_MAX_SECONDS:g}s) if this guard legitimately needs longer "
        "on this filesystem."
    )

    if not _EMIT_LOCK.acquire(timeout=_EMIT_LOCK_WAIT_SECONDS):
        _write_diagnostic(deny_diagnostic)
        os._exit(2)  # noqa: SLF001 -- hard exit is the point; see docstring
        return

    global _DECISION_EMITTED
    try:
        token = getattr(
            threading.current_thread(), "guard_invocation_token", _INVOCATION_TOKEN
        )
        if token is not _INVOCATION_TOKEN:
            with contextlib.suppress(BaseException):
                sys.stdout.flush()
            os._exit(  # noqa: SLF001 -- hard exit is the point; see docstring
                _MAIN_RESULT if _MAIN_RESULT is not None else 2
            )
            return

        command = _COMMAND_UNDER_DECISION

        if _DECISION_EMITTED:
            with contextlib.suppress(BaseException):
                sys.stdout.flush()
            os._exit(0)  # noqa: SLF001 -- hard exit is the point; see docstring
            return

        if resolve_mode() != _MODE_ENGINE_GATE or _watchdog_marker_present(command):
            _write_diagnostic(deny_diagnostic)
            os._exit(2)  # noqa: SLF001 -- hard exit is the point; see docstring
            return

        _DECISION_EMITTED = True
        with contextlib.suppress(BaseException):
            print(
                json.dumps(
                    decision(
                        "ask",
                        f"disk-hygiene could not finish checking this command "
                        f"within {deadline:g}s; it names no disk-hygiene engine "
                        f"script. Raise {_WATCHDOG_ENV_VAR} (up to "
                        f"{_WATCHDOG_MAX_SECONDS:g}s) if this host is slow.",
                    )
                )
            )
            sys.stdout.flush()
        os._exit(0)  # noqa: SLF001 -- hard exit is the point; see docstring
        return
    finally:
        _EMIT_LOCK.release()


def _settle(
    command: str,
    tool_name: str,
    start: float,
    decision_value: str,
    rule: str,
    reason: str,
) -> int:
    _emit_decision(decision(decision_value, reason))
    _emit_guard_telemetry(
        start,
        tool_name,
        _telemetry_status_for_permission(decision_value),
        decision_value=decision_value,
    )
    _record_decision(command, tool_name, decision_value, rule, reason)
    return 0


_APPLY_ASK_GENERIC_REASON = (
    "disk-hygiene is ready to apply one exact, previewed tier. Confirm this "
    "final mutation prompt only if it matches the tier and paths the preview just showed."
)
_APPLY_PLAN_READ_LIMIT = 1 << 20
_APPLY_SNAPSHOT_READ_LIMIT = 16 << 20


def _read_json_file(path: str, limit: int) -> object:
    try:
        if not stat.S_ISREG(os.stat(path).st_mode):
            return None
        with open(path, "rb") as handle:
            data = handle.read(limit + 1)
        return None if len(data) > limit else json.loads(data)
    except Exception:  # noqa: BLE001 -- text only; the verdict stays "ask"
        return None


def _apply_ask_reason(command: str) -> str:
    """Tier, count, and every path of the plan an apply command names.

    Text only. Any missing or malformed plan returns the generic reason, so the
    caller's ``ask`` verdict never depends on what this reads.
    """
    try:
        words = _literal_shell_words(command) or []
        flags = {
            flag: words[index + 1]
            for index, flag in enumerate(words[:-1])
            if flag in {"--plan", "--snapshot"}
        }
        plan = _read_json_file(flags["--plan"], _APPLY_PLAN_READ_LIMIT)
        candidates = plan["candidates"]  # type: ignore[index]
        tier = plan["tier"]  # type: ignore[index]
        paths = [candidate["path"] for candidate in candidates]
        if not (
            isinstance(tier, str)
            and paths
            and all(isinstance(path, str) for path in paths)
        ):
            return _APPLY_ASK_GENERIC_REASON
        return (
            f"disk-hygiene is ready to apply one exact, previewed tier: {_display_text(tier)}, "
            f"{len(paths)} path(s) {_snapshot_location(flags['--snapshot'])}:\n"
            + "\n".join(f"- {_display_text(path)}" for path in paths)
            + "\nConfirm this final mutation prompt only if it matches the tier "
            "and paths the preview just showed."
        )
    except Exception:  # noqa: BLE001 -- text only; the verdict stays "ask"
        return _APPLY_ASK_GENERIC_REASON


def _snapshot_location(snapshot_path: str) -> str:
    snapshot = _read_json_file(snapshot_path, _APPLY_SNAPSHOT_READ_LIMIT)
    target = snapshot.get("target") if isinstance(snapshot, dict) else None
    if isinstance(target, str):
        return f"under {_display_text(target)}"
    return "(snapshot-relative; the snapshot target could not be read)"


_HANDOFF_APPLY_ASK_GENERIC_REASON = (
    "disk-hygiene is ready to re-verify and remove the approved paths of one "
    "tier. Confirm this final mutation prompt only if it matches the tier and "
    "paths the report just showed."
)


def _handoff_ask_reason(command: str) -> str:
    """Tier, count, and every path a handoff-apply command names.

    Text only, like ``_apply_ask_reason``: an unreadable command returns the
    generic reason, so the caller's ``ask`` verdict never depends on this.
    """
    try:
        words = _literal_shell_words(command) or []
        values: dict[str, list[str]] = {
            flag: [] for flag in ("--snapshot", "--tier", "--path", "--vcs-evidence")
        }
        for index, word in enumerate(words[:-1]):
            if word in values:
                values[word].append(words[index + 1])
        (snapshot,) = values["--snapshot"]
        (tier,) = values["--tier"]
        paths = values["--path"]
        if not paths:
            return _HANDOFF_APPLY_ASK_GENERIC_REASON
        windows = os.name == "nt"
        removal = "send to the Recycle Bin" if windows else "delete"
        loss = (
            " That includes version-control content you acknowledged losing: "
            "unpushed commits and untracked or ignored files, which "
            + ("only the Recycle Bin can restore." if windows else "do not come back.")
            if values["--vcs-evidence"]
            else ""
        )
        return (
            f"disk-hygiene is ready to re-verify and {removal} the approved paths of "
            f"one tier: {_display_text(tier)}, {len(paths)} path(s) "
            f"{_snapshot_location(snapshot)}:\n"
            + "\n".join(f"- {_display_text(path)}" for path in paths)
            + f"\nA path that is not clear when its turn comes is skipped.{loss} "
            "Confirm this final mutation prompt only if it matches the tier and "
            "paths the report just showed."
        )
    except Exception:  # noqa: BLE001 -- text only; the verdict stays "ask"
        return _HANDOFF_APPLY_ASK_GENERIC_REASON


_MUTATION_PROMPTS = {
    "apply": _apply_ask_reason,
    "handoff-apply": _handoff_ask_reason,
}


def _stand_down(command: str, tool_name: str, start: float) -> int:
    _emit_guard_telemetry(start, tool_name, "ok")
    _record_decision(
        command, tool_name, guard_decision_log.DECISION_NONE, "belt-no-open-run"
    )
    return 0


def _decide(
    command: str, tool_name: str, start: float, session_id: str | None = None
) -> int:
    if resolve_mode() == _MODE_ENGINE_GATE and not _engine_gate_relevant(
        command, tool_name
    ):
        _emit_notice_only()
        return 0

    enabled = resolve_disk_hygiene_enabled()

    if tool_name == "PowerShell":
        verdict = powershell_decision(command, enabled)
        if verdict:
            if _belt_released(command, tool_name, session_id, enabled):
                return _stand_down(command, tool_name, start)
            _settle(
                command,
                tool_name,
                start,
                verdict[0],
                "powershell-deletion-spelling",
                verdict[1],
            )
        else:
            _emit_guard_telemetry(start, tool_name, "ok")
            _record_decision(
                command,
                tool_name,
                guard_decision_log.DECISION_NONE,
                "powershell-no-flagged-spelling",
            )
            _emit_notice_only()
        return 0

    authority = resolve_authorized_data_root()
    if is_exact_kill_switch_probe(command):
        return _settle(
            command,
            tool_name,
            start,
            "allow",
            "kill-switch-probe",
            "Exact bundled disk-hygiene kill-switch probe (read-only report).",
        )
    if is_exact_readonly_supporting_command(command):
        permission = "ask" if resolve_mode() == _MODE_ENGINE_GATE else "allow"
        return _settle(
            command,
            tool_name,
            start,
            permission,
            "readonly-supporting-allowlist",
            "Exact literal-form read-only supporting Bash command "
            "(disk-hygiene belt inspection allowlist).",
        )
    command_kind = classify_exact_engine_command(command, authority)
    admitted = command_kind in _READONLY_ENGINE_SUBCOMMANDS or (
        command_kind in _MUTATING_ENGINE_SUBCOMMANDS and enabled
    )
    if admitted and resolve_mode() != _MODE_ENGINE_GATE:
        _record_run_step(command, command_kind, authority, session_id)
    if command_kind in _READONLY_ENGINE_SUBCOMMANDS:
        return _settle(
            command,
            tool_name,
            start,
            "allow",
            f"exact-engine-{command_kind}",
            "Exact bundled disk-hygiene read-only gate invocation.",
        )
    if command_kind in _MUTATING_ENGINE_SUBCOMMANDS:
        if enabled:
            return _settle(
                command,
                tool_name,
                start,
                "ask",
                f"exact-engine-{command_kind}",
                _MUTATION_PROMPTS[command_kind](command),
            )
        readonly = [
            name
            for name in _ALLOWED_ENGINE_SUBCOMMANDS
            if name in _READONLY_ENGINE_SUBCOMMANDS
        ]
        return _settle(
            command,
            tool_name,
            start,
            "deny",
            f"kill-switch-disabled-{command_kind}",
            "Disk-hygiene execution is disabled; only exact bundled "
            f"{', '.join(readonly[:-1])}, and {readonly[-1]} invocations are "
            "permitted.",
        )
    if _belt_released(command, tool_name, session_id, enabled):
        return _stand_down(command, tool_name, start)
    return _settle(
        command,
        tool_name,
        start,
        "deny",
        "not-exact-engine-command",
        _bash_denial_guidance(authority, command=command),
    )


def main() -> int:
    start = time.perf_counter()
    _reset_decision_state()
    deadline = _watchdog_seconds()
    watchdog: threading.Timer | None = None
    result = 2
    global _INVOCATION_TOKEN
    token = object()
    with _EMIT_LOCK:
        _INVOCATION_TOKEN = token
    try:
        watchdog = threading.Timer(deadline, _watchdog_fire, args=(deadline,))
        watchdog.guard_invocation_token = token  # type: ignore[attr-defined]
        watchdog.daemon = True
        watchdog.start()
        tool_name = ""
        try:
            payload = json.load(sys.stdin)
            tool_name = payload.get("tool_name", "")
            command = payload["tool_input"]["command"]
            if not isinstance(command, str):
                raise TypeError("command is not text")
            _publish_command_for_watchdog(command)
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            reason = f"disk-hygiene guard could not validate the shell call: {exc}"
            _emit_decision(decision("deny", reason))
            _emit_guard_telemetry(
                start,
                str(tool_name),
                "blocked",
                decision_value="deny",
            )
            _record_decision("", str(tool_name), "deny", "unparsable-payload", reason)
            result = 0
            return result
        session_id = payload.get("session_id")
        result = _decide(
            command,
            tool_name,
            start,
            session_id if isinstance(session_id, str) else None,
        )
        return result
    except BaseException as exc:
        _emit_guard_telemetry(start, "", "error")
        diagnostic = (
            f"destructive_guard: internal error, denying by default "
            f"({type(exc).__name__}: {exc})"
        )
        _write_diagnostic(diagnostic)
        _record_decision("", "", "deny", "internal-error", diagnostic)
        result = 2
        return result
    finally:
        if watchdog is not None:
            watchdog.cancel()
        with contextlib.suppress(BaseException):
            sys.stdout.flush()
        _reset_decision_state(result)


if __name__ == "__main__":
    _exit_code = main()
    try:
        sys.stdout.flush()
    except BaseException:
        _write_diagnostic(
            "destructive_guard: the decision could not be written to stdout; "
            "denying by default."
        )
        _discard_stream(sys.stdout)
        _exit_code = 2
    with contextlib.suppress(BaseException):
        sys.stderr.flush()
    # os._exit, not SystemExit: a failed shutdown flush would turn a blocking 2 into 120.
    os._exit(_exit_code)  # noqa: SLF001

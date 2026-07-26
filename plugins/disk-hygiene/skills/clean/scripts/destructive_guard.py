#!/usr/bin/env python3
"""Fail-closed skill hook: allow only exact bundled hygiene-engine commands.

Exit-code contract (see ``main`` / ``_decide`` / ``_watchdog_fire``): only ``0``
(a deliberate JSON allow/ask/deny decision on stdout) and ``2`` (a blocking
deny, one-line diagnostic on stderr) are reachable. Exit ``1`` is a Claude Code
*non-blocking* status for PreToolUse
(https://code.claude.com/docs/en/hooks, fetched 2026-07-25: "Claude Code treats
exit code 1 as a non-blocking error and proceeds with the action... If your
hook is meant to enforce a policy, use exit 2") — every internal failure path
that could once fall through to the interpreter's default (uncaught exception
-> exit 1, no diagnostic) now denies instead (#1423).

Investigation note for the one observed #1423 occurrence (engine-gate mode,
``exitCode: 1``, empty stderr, ``durationMs: 17054``, Windows, no reproduction):
every filesystem call already reachable from this module's own logic
(``Path.resolve(strict=True)``, ``os.path.samefile``, ``Path.stat``/
``read_text``) already caught ``OSError`` at the call site, so a stall ending
in an ``OSError`` (a plausible shape for an unreachable/slow path — e.g. a
stale network drive letter or UNC path referenced by an ordinary, unrelated
Bash command) would not by itself explain an *uncaught* exception. Two things
follow: (1) the strongest identified candidate for the 17s itself is
``_engine_gate_relevant``'s marker-free fallback, which calls
``os.path.samefile`` on every separator-containing word of *every* Bash/
PowerShell command in *every* session (not only disk-hygiene commands) when
resolving the plugin-level engine gate — a slow or unreachable path argument
in an unrelated command is a real, user-reachable way to stall this hook for
longer than milliseconds; (2) empty stderr is not what an uncaught Python
exception normally produces (the default handler writes a traceback), so an
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

import json
import math
import os
import re
import sys
import threading
from pathlib import Path

_LIB_DIR = Path(__file__).resolve().parents[3] / "lib"
if str(_LIB_DIR) not in sys.path:
    sys.path.insert(0, str(_LIB_DIR))

import killswitch_config  # noqa: E402  (path set above; plugin-bundled module)


_SHELL_EXPANSION_OR_OPERATOR_CHARS = frozenset("{}$*?[]~`()<>;|&\r\n\t!#")


def decision(value: str, reason: str) -> dict[str, object]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": value,
            "permissionDecisionReason": reason,
        }
    }


def _is_current_python(value: str) -> bool:
    if not os.path.isabs(value):
        return False
    try:
        runtime = Path(sys.executable).resolve(strict=True)
        candidate = Path(value).absolute()
        return (
            os.path.normcase(os.fspath(candidate))
            == os.path.normcase(os.fspath(runtime))
            and os.path.samefile(candidate, runtime)
        )
    except OSError:
        return False


def _display_python() -> str:
    """Return the hook interpreter in a Bash-friendly absolute spelling."""
    try:
        runtime = Path(sys.executable).resolve(strict=True)
    except OSError:
        runtime = Path(sys.executable).absolute()
    return os.fspath(runtime).replace("\\", "/")


def _argument(value: str) -> bool:
    return bool(value) and not value.startswith("-")


def _literal_shell_words(
    command: str, *, allow_backslash: bool = False
) -> list[str] | None:
    """Parse only space-delimited literal words with optional whole-word quotes.

    ``allow_backslash`` permits ``\\`` inside words for surfaces where it is a
    path separator rather than an escape character (PowerShell commands); the
    Bash default keeps rejecting it.
    """
    if not command or any(
        value in _SHELL_EXPANSION_OR_OPERATOR_CHARS for value in command
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
    """Return a canonical local-path key with the host platform's case rules."""
    try:
        resolved = Path(value).resolve(strict=True)
    except OSError:
        return None
    return os.path.normcase(os.fspath(resolved))


def _data_root_key(value: str) -> str:
    """Canonical key for a generated-state root that may not exist yet."""
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


def _plugin_data_root_from_root(plugin_root: str) -> str | None:
    """Derive the persistent data root from the plugin's installation root.

    A skill-frontmatter hook may substitute only ``${CLAUDE_PLUGIN_ROOT}`` into
    its args — ``${CLAUDE_PLUGIN_DATA}`` is plugin-only and makes Claude Code
    refuse to launch a skill hook — so the guard reconstructs the data root from
    the installation root. Claude Code lays a marketplace plugin out at
    ``<plugins>/cache/<marketplace>/<name>/<version>`` — the install root is the
    version leaf — and persists its data at ``<plugins>/data/<id>``, where ``<id>``
    is ``<name>@<marketplace>`` with every character outside ``[A-Za-z0-9_-]``
    replaced by ``-`` (plugins reference, "Persistent data directory").

    The install root is version-specific, so this anchors on the
    ``<plugins>/cache`` marker rather than a fixed depth: the segment after
    ``cache`` is the marketplace, the next is the name, any further segments (a
    ``<version>`` leaf, absent for a directly-linked local install) are ignored,
    and ``data`` is ``cache``'s sibling. A root without that marker, or with no
    name segment after the marketplace, yields ``None`` so the caller fails closed
    instead of trusting a guessed path.
    """
    parts = Path(plugin_root).parts
    for index in range(1, len(parts)):
        if not (
            parts[index].casefold() == _PLUGIN_CACHE_DIRNAME
            and parts[index - 1].casefold() == _PLUGINS_DIRNAME
        ):
            continue
        if index + 2 >= len(parts):
            return None
        marketplace, name = parts[index + 1], parts[index + 2]
        if not marketplace or not name:
            return None
        plugin_id = _PLUGIN_ID_DISALLOWED.sub("-", f"{name}@{marketplace}")
        plugins_dir = Path(*parts[:index])
        return os.fspath(plugins_dir / _PLUGIN_DATA_DIRNAME / plugin_id)
    return None


_MODE_FLAG = "--mode"
_MODE_BELT = "belt"
_MODE_ENGINE_GATE = "engine-gate"
_ENGINE_MARKER = "hygiene.py"


def _engine_gate_relevant(command: str, tool_name: str = "Bash") -> bool:
    """Decide whether the plugin-level engine gate should act on ``command``.

    A plugin-level hook fires on every shell call in every session, so a bare
    mention of the engine's filename (``git diff -- hygiene.py``,
    ``rg hygiene.py README.md``, ``echo hygiene.py``) must defer — routing
    mentions into the belt's fail-closed parser would block ordinary work
    session-wide. The gate acts only on what parses as an INVOCATION:

    - a literal word carrying the engine's filename that is not provably a
      DIFFERENT file: a word that resolves to an existing file other than the
      bundled ``hygiene.py`` (a consumer's own ``tools/hygiene.py``) is not this
      engine and defers; the bundled script itself, or an unresolvable word,
      stays in play;
    - such a word counts as an INVOCATION when it is the command itself or ANY
      earlier word is an interpreter token (``python*``/``py``) — "immediately
      preceding" is not required, so interpreter options
      (``python3 -B .../hygiene.py``) cannot slip the gate;
    - a quoted compound word (e.g. a ``bash -c``/``pwsh -Command`` payload) that
      carries both the engine marker and an interpreter token;
    - any command carrying the marker that the literal parser cannot prove is a
      mere mention (expansions, operators, unparsable quoting) — fail closed
      into the gate; the belt's own rules then decide.

    A path-like word (containing a separator) that is the SAME FILE as the
    bundled engine — a symlink or hard link under any name — gates regardless
    of its filename. Accepted residuals, all of the copy-evasion class the gate
    can never close (a byte copy is a different file): a PATH-installed alias
    with no separator, an alias inside a command the literal parser rejects
    when the marker is absent, and a copied engine. This is a belt, not the
    authority: an invocation smuggled past it still answers to the engine's own
    preview/approval-token containment (and to the skill-scoped belt during
    active cleanup).
    """

    def _is_interpreter(word: str) -> bool:
        base = Path(word.casefold()).name
        return base.startswith("python") or base in {"py", "py.exe"}

    bundled = Path(__file__).resolve().with_name("hygiene.py")

    def _samefile(word: str) -> bool:
        try:
            return os.path.samefile(word, bundled)
        except OSError:
            return False

    def _same_file_as_bundled(word: str) -> bool:
        # Separator requirement bounds the no-marker scan to path-like words.
        if "/" not in word and "\\" not in word:
            return False
        return _samefile(word)

    allow_backslash = tool_name == "PowerShell"
    lowered = command.casefold()
    if _ENGINE_MARKER not in lowered:
        # No marker: the only relevant shape is a linked alias of the bundled
        # engine invoked by path. Unparsable marker-free commands cannot fail
        # closed (that would gate every command with an operator), so scan
        # their whitespace tokens for separator-carrying words and identity-
        # check those — a literal alias path gates even beside an operator.
        words = _literal_shell_words(command, allow_backslash=allow_backslash)
        if words is None:
            return any(
                _same_file_as_bundled(token.strip("'\""))
                for token in command.split()
            )
        return any(_same_file_as_bundled(word) for word in words)
    words = _literal_shell_words(command, allow_backslash=allow_backslash)
    if words is None:
        # Marker present but not literally parseable (operators, compounds).
        # Fail closed UNLESS every marker-carrying token is provably a
        # DIFFERENT existing file (a consumer's own hygiene.py in a compound
        # command) and no token is the bundled engine under any name.
        tokens = [token.strip("'\"") for token in command.split()]
        if any(_same_file_as_bundled(token) for token in tokens):
            return True
        marker_tokens = [
            token for token in tokens if _ENGINE_MARKER in token.casefold()
        ]
        if marker_tokens and all(
            _script_path_key(token) is not None and not _samefile(token)
            for token in marker_tokens
        ):
            return False
        return True
    # The effective command word: skip launcher wrappers, VAR=value
    # assignments, and option words — `env PATH=... hygiene.py apply` makes the
    # bare marker word the command even though it is not word 0.
    _WRAPPERS = {
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
    wrapper_indices = [
        index
        for index, word in enumerate(words)
        if Path(word.casefold()).name in _WRAPPERS
    ]
    for index, word in enumerate(words):
        folded = word.casefold()
        if Path(folded).name == _ENGINE_MARKER:
            if _samefile(word):
                # The word IS the bundled engine — gate regardless of launcher
                # (pypy3, an unknown interpreter, anything). Identity beats
                # launcher enumeration. Accepted overbreadth: a MENTION of the
                # bundled engine by a resolving path gates too; real-world
                # mentions use names that resolve to nothing (deferred below)
                # or to consumer files (deferred below).
                return True
            resolved_key = _script_path_key(word)
            if resolved_key is not None:
                # Provably a different existing file — a consumer's own
                # hygiene.py, not this engine.
                continue
            if (
                index == 0
                or os.path.isabs(word)
                or any(_is_interpreter(w) for w in words[:index])
                or any(w_index < index for w_index in wrapper_indices)
            ):
                # An absolute engine path is an invocation target whatever the
                # launcher, and a bare marker word ANYWHERE after a known
                # launcher wrapper gates conservatively (wrapper option
                # operands like `nice -n 10` defeat effective-command
                # inference, and PATH injection can make the bare name the
                # command). A deliberate overbreadth: a mere MENTION after a
                # wrapper (`sudo grep x hygiene.py`) gates too — rare, and the
                # kill-switch bypass risk outweighs it. Plain-command mentions
                # (`git diff -- hygiene.py`) still defer.
                return True
            continue
        if _ENGINE_MARKER in folded and " " in word:
            first_token = folded.split()[0]
            if Path(first_token).name == _ENGINE_MARKER or _is_interpreter(
                first_token
            ):
                # A quoted compound payload (sh -c / pwsh -Command) whose first
                # token is the engine or an interpreter is an invocation.
                return True
        if _ENGINE_MARKER in folded and "python" in folded:
            return True
    return False


def resolve_mode() -> str:
    """Resolve which registration surface launched this guard.

    ``belt`` (default) is the skill-scoped deployment: deny-by-default Bash and
    deletion-spelling PowerShell discipline, tolerable only while the clean skill
    is the active work. ``engine-gate`` is the plugin-level deployment: it cares
    ONLY about engine invocations (kill switch + data-root authority must hold in
    every session), so any command that does not reference the engine defers
    instantly — a plugin-level hook must never tax unrelated work. An
    unrecognized or absent value falls back to ``belt``, the stricter mode.
    """
    value = _argv_flag_value(sys.argv[1:], _MODE_FLAG)
    return value if value in {_MODE_BELT, _MODE_ENGINE_GATE} else _MODE_BELT


def _argv_flag_value(argv: list[str], flag: str) -> str | None:
    """Read the runtime-substituted value the frontmatter hook passed for ``flag``.

    The guard's own argv is a model-unforgeable channel for a value the harness
    substitutes at launch (e.g. ``${CLAUDE_PLUGIN_ROOT}``), reaching the guard even
    where environment injection does not. Accepts both the space-separated
    (``--flag value``) and ``--flag=value`` spellings.
    """
    for index, token in enumerate(argv):
        if token == flag and index + 1 < len(argv):
            return argv[index + 1]
        prefix = f"{flag}="
        if token.startswith(prefix):
            return token[len(prefix) :]
    return None


def _argv_authorized_data_root(argv: list[str]) -> str | None:
    """Read the authorized data root the runtime substituted into the hook argv."""
    return _argv_flag_value(argv, _AUTHORIZED_DATA_ROOT_FLAG)


def resolve_authorized_data_root() -> str | None:
    """Resolve the authoritative data root a skill-frontmatter hook can supply.

    Precedence, highest first:

    1. ``--authorized-data-root`` — a direct path, for a host that can substitute
       ``${CLAUDE_PLUGIN_DATA}`` itself (a plugin ``hooks.json`` hook can; a skill
       hook cannot).
    2. ``--plugin-root ${CLAUDE_PLUGIN_ROOT}`` — the only substitution a skill hook
       receives; the data root is derived from it. This is the channel the bundled
       ``clean`` skill uses.
    3. The ``CLAUDE_PLUGIN_DATA`` environment variable, if present.

    A literal, unsubstituted placeholder is treated as absent at each step. Absent
    every channel the guard has no authority and every ``--data-root`` engine call
    fails closed.
    """
    direct = _argv_flag_value(sys.argv[1:], _AUTHORIZED_DATA_ROOT_FLAG)
    if direct and direct != _AUTHORIZED_DATA_ROOT_PLACEHOLDER:
        return direct
    plugin_root = _argv_flag_value(sys.argv[1:], _PLUGIN_ROOT_FLAG)
    if plugin_root and plugin_root != _PLUGIN_ROOT_PLACEHOLDER:
        derived = _plugin_data_root_from_root(plugin_root)
        if derived:
            return derived
    return os.environ.get(_CLAUDE_PLUGIN_DATA_ENV)


def _user_settings_path_from_root(plugin_root: str) -> str | None:
    """Derive the user ``settings.json`` path from the plugin's install root.

    Claude Code lays a marketplace plugin out at
    ``<config>/plugins/cache/<marketplace>/<name>/<version>``, and the user
    settings file is ``<config>/settings.json`` — the sibling of the ``plugins``
    directory. This anchors on the same ``plugins/cache`` marker as
    ``_plugin_data_root_from_root`` rather than a fixed depth: the ``plugins``
    directory is the segment before ``cache``, and ``settings.json`` is its
    parent's child. A root without that marker yields ``None`` so the caller
    falls back to the environment.
    """
    parts = Path(plugin_root).parts
    for index in range(1, len(parts)):
        if (
            parts[index].casefold() == _PLUGIN_CACHE_DIRNAME
            and parts[index - 1].casefold() == _PLUGINS_DIRNAME
        ):
            plugins_dir = Path(*parts[:index])
            return os.fspath(plugins_dir.parent / "settings.json")
    return None


def _plugin_id_from_root(plugin_root: str) -> str | None:
    """Return this install's exact ``<name>@<marketplace>`` ``pluginConfigs`` key.

    Claude Code lays a marketplace plugin out at
    ``<config>/plugins/cache/<marketplace>/<name>/<version>`` and keys its options
    under ``<name>@<marketplace>``. Deriving that exact key lets the kill-switch
    read match only this install, so a second marketplace's ``disk-hygiene`` entry
    cannot mask this one's configured value. A root without the ``plugins/cache``
    marker (or missing the name/marketplace segments) yields ``None`` and the read
    falls back to matching any ``disk-hygiene`` entry.
    """
    parts = Path(plugin_root).parts
    for index in range(1, len(parts)):
        if (
            parts[index].casefold() == _PLUGIN_CACHE_DIRNAME
            and parts[index - 1].casefold() == _PLUGINS_DIRNAME
        ):
            if index + 2 >= len(parts):
                return None
            marketplace, name = parts[index + 1], parts[index + 2]
            if not marketplace or not name:
                return None
            return f"{name}@{marketplace}"
    return None


def _resolve_user_settings_path() -> Path | None:
    """Locate the user settings file that carries the kill switch, or ``None``.

    The **only** trusted locator is ``--plugin-root ${CLAUDE_PLUGIN_ROOT}``: Claude
    Code substitutes the plugin's true install path, which a hostile repo cannot
    forge, and the user settings file is derived from its ``plugins/cache`` marker.
    The guard deliberately does **not** fall back to ``CLAUDE_CONFIG_DIR`` / ``HOME``:
    those are environment values, and a repo ``.claude/settings.json`` ``env`` block
    reaches hook subprocesses, so trusting them would let a repo point the read at a
    forged settings file and flip the switch (the exact provenance hole this design
    closes). When the plugin root carries no marker — e.g. a ``--plugin-dir``
    checkout install — no trusted user-settings location exists and this returns
    ``None``; the caller then relies on managed settings (fixed system paths) and
    otherwise fails closed to enabled.
    """
    plugin_root = _argv_flag_value(sys.argv[1:], _PLUGIN_ROOT_FLAG)
    if plugin_root and plugin_root != _PLUGIN_ROOT_PLACEHOLDER:
        derived = _user_settings_path_from_root(plugin_root)
        if derived:
            return Path(derived)
    return None


def resolve_disk_hygiene_enabled() -> bool:
    """Resolve the execution kill switch by reading user-scope ``pluginConfigs``.

    The kill switch is a safety control: ``false`` is audit-only mode and must
    prevent every deletion lane. The guard reads ``disk_hygiene_enabled`` straight
    out of the ``settings.json`` files (``lib/killswitch_config.py``, the single
    reader it shares with the report-only probe) — never the process environment.
    Since Claude Code 2.1.207 that key is honored only from user, managed, and
    ``--settings`` scope, never a project or local ``settings.json``
    (plugins-reference, "User configuration"), so a hostile repo cannot flip the
    switch. Managed settings are the highest-precedence, non-overridable scope, so
    a value configured there wins over the user file — that is how an organization
    enforces audit-only mode. The ``--settings`` file is a session CLI flag a hook
    cannot observe, the one honored source not read here (see
    ``killswitch_config.managed_settings_path`` for the full residual list). The
    environment is rejected on purpose: a repo ``settings.json`` ``env`` block
    reaches hook subprocesses and carries no provenance a hook could check, so an
    env-borne toggle (or an env-borne user-settings path) would reopen the hole
    this closes — hence the user settings file is located from the tamper-resistant
    ``--plugin-root`` first (see ``_resolve_user_settings_path``), and the managed
    file from its fixed root-owned system path.

    Every absent, unreadable, or ambiguous read fails **closed to enabled**: the
    guard stays active and gates every mutation behind the final human prompt even
    when it cannot confirm a configured value. Both registration surfaces reach
    this one resolver — the plugin-level engine gate and the skill-frontmatter belt
    both run ``main()``, and both receive ``--plugin-root ${CLAUDE_PLUGIN_ROOT}`` —
    so the belt needs no environment channel it does not have.
    """
    plugin_root = _argv_flag_value(sys.argv[1:], _PLUGIN_ROOT_FLAG)
    plugin_id = (
        _plugin_id_from_root(plugin_root)
        if plugin_root and plugin_root != _PLUGIN_ROOT_PLACEHOLDER
        else None
    )
    return killswitch_config.resolve_effective(
        _resolve_user_settings_path(),
        killswitch_config.managed_settings_path(),
        plugin_id,
    )


def _is_authorized_data_root(value: str, authority: str | None) -> bool:
    """Accept only the data root the runtime told this hook to authorize."""
    if not authority:
        return False
    return _data_root_key(value) == _data_root_key(authority)


def _display_data_root(authority: str | None) -> str | None:
    if not authority:
        return None
    return os.fspath(Path(authority).expanduser().resolve(strict=False)).replace(
        "\\", "/"
    )


def _valid_optional_value(flag: str, value: str, authority: str | None) -> bool:
    if not _argument(value):
        return False
    if flag == "--max-depth":
        return re.fullmatch(r"[1-9][0-9]{0,3}", value) is not None
    if flag == "--data-root":
        return _is_authorized_data_root(value, authority)
    return True


def _consume_optional_pairs(
    tokens: list[str], allowed: frozenset[str], authority: str | None
) -> bool:
    seen: list[str] = []
    while tokens:
        flag = tokens[0]
        if (
            flag not in allowed
            or flag in seen
            or len(tokens) < 2
            or not _valid_optional_value(flag, tokens[1], authority)
        ):
            return False
        seen.append(flag)
        tokens = tokens[2:]
    return True


def classify_exact_engine_command(command: str, authority: str | None) -> str | None:
    """Return scan/preview/handoff-verify/apply for one canonical invocation."""
    tokens = _literal_shell_words(command)
    if tokens is None:
        return None
    if len(tokens) < 3 or not _is_current_python(tokens[0]):
        return None
    expected_script = str(Path(__file__).resolve().with_name("hygiene.py"))
    if _script_path_key(tokens[1]) != _script_path_key(expected_script):
        return None

    if tokens[2] == "scan":
        if (
            len(tokens) < 7
            or tokens[3] != "--target"
            or not _argument(tokens[4])
            or tokens[5] != "--output"
            or not _argument(tokens[6])
        ):
            return None
        # --confirmed-large-scan is the sole valueless scan flag; strip at most
        # one so the remainder is the pure flag/value-pair grammar every other
        # optional follows.
        optionals = list(tokens[7:])
        confirmed = optionals.count("--confirmed-large-scan")
        if confirmed > 1:
            return None
        if confirmed:
            optionals.remove("--confirmed-large-scan")
        if len(optionals) not in {0, 2, 4, 6, 8} or not _consume_optional_pairs(
            optionals,
            frozenset({"--policy", "--project-dir", "--data-root", "--max-depth"}),
            authority,
        ):
            return None
        return "scan"
    if tokens[2] == "preview":
        valid = (
            len(tokens) in {7, 9}
            and tokens[3] == "--snapshot"
            and _argument(tokens[4])
            and tokens[5] == "--plan"
            and _argument(tokens[6])
            and _consume_optional_pairs(
                tokens[7:], frozenset({"--data-root"}), authority
            )
        )
        return "preview" if valid else None
    if tokens[2] == "handoff-verify":
        valid = (
            len(tokens) in {7, 9}
            and tokens[3] == "--snapshot"
            and _argument(tokens[4])
            and tokens[5] == "--paths"
            and _argument(tokens[6])
            and _consume_optional_pairs(
                tokens[7:], frozenset({"--data-root"}), authority
            )
        )
        return "handoff-verify" if valid else None
    if tokens[2] == "apply":
        if len(tokens) not in {14, 16}:
            return None
        valid = all(
            (
                tokens[3] == "--execute",
                tokens[4] == "--snapshot",
                _argument(tokens[5]),
                tokens[6] == "--plan",
                _argument(tokens[7]),
                tokens[8] == "--confirm-tier",
                tokens[9] in {"high", "medium", "low"},
                tokens[10] == "--approval-token",
                re.fullmatch(r"[0-9a-f]{24}", tokens[11]) is not None,
                tokens[12] == "--report",
                _argument(tokens[13]),
                _consume_optional_pairs(
                    tokens[14:], frozenset({"--data-root"}), authority
                ),
            )
        )
        return "apply" if valid else None
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
    expected_script = str(
        Path(__file__).resolve().parents[2] / "setup" / "scripts" / "kill_switch_probe.py"
    )
    return _script_path_key(tokens[1]) == _script_path_key(expected_script)


_POWERSHELL_MUTATION_WORDS = re.compile(
    r"(?i)(?<![\w./\\-])("
    r"remove-item|rm|rmdir|del|erase|rd|ri|clear-content|clear-recyclebin|rimraf|unlink"
    r"|sendtorecyclebin|deletefile|deletedirectory|removedirectory"
    r")(?![\w-])"
)
_POWERSHELL_DOTNET_DELETE = re.compile(r"(?i)(::\s*delete|\.\s*delete\s*\()")
# robocopy is an executable normally invocable by full path
# (C:\Windows\System32\robocopy.exe), so unlike the cmdlet word list its
# lookbehind must permit path separators before the name.
_POWERSHELL_ROBOCOPY_PURGE = re.compile(
    r"(?i)(?<![\w-])robocopy(\.exe)?(?![\w-]).*(/mir|/purge|/mov|/move)(?![\w-])"
)
# Module-qualified cmdlet invocations (Module\Cmdlet) put a backslash before the
# cmdlet name, which the word pattern's lookbehind rejects; cover the deletion
# cmdlets explicitly (aliases like rm/del cannot be module-qualified).
_POWERSHELL_QUALIFIED_DELETE = re.compile(
    r"(?i)[a-z][\w.]*\\(remove-item|clear-content|clear-recyclebin)(?![\w-])"
)


def powershell_decision(command: str, enabled: bool) -> tuple[str, str] | None:
    """Return a (decision, reason) pair for a PowerShell command, or None to defer.

    PowerShell stays available for read-only support work (git, gh, metadata
    inspection), so this lane gates known filesystem-mutation spellings and any
    engine invocation rather than denying unknown commands. Engine calls stay on
    the Bash lane's fail-closed deny-unknown guard. A flagged mutation spelling
    resolves against the ``disk_hygiene_enabled`` kill switch: when execution is
    enabled it surfaces the final human permission prompt (``ask``), preserving
    the unsupported-platform manual handoff; in audit-only mode (``enabled`` is
    false) it is denied outright, so the kill switch blocks every deletion lane
    and not only the Bash engine lane.
    """
    if _engine_gate_relevant(command, "PowerShell"):
        # Invocation-shaped engine references only — the same classifier the
        # plugin-level engine gate uses, so read-only text processing that
        # merely NAMES the script (Select-String over a bare name, git diff)
        # defers instead of being denied by a raw substring test. A command
        # whose argument IS the bundled engine (file identity) still denies,
        # even under a read-verb spelling: PowerShell aliases and profile
        # functions shadow cmdlet names, so a verb name proves nothing about
        # what executes — inspect the engine source with non-shell tools.
        return (
            "deny",
            "disk-hygiene engine invocations must go through the Bash tool's "
            "exact guarded command shapes, not PowerShell. To READ the engine "
            "source, use non-shell file tools.",
        )
    match = _POWERSHELL_MUTATION_WORDS.search(command)
    if match:
        return _powershell_mutation_verdict(
            enabled,
            f'disk-hygiene flagged the deletion spelling "{match.group(0)}".',
        )
    if _POWERSHELL_DOTNET_DELETE.search(command):
        return _powershell_mutation_verdict(
            enabled, "disk-hygiene flagged a .NET Delete call."
        )
    qualified = _POWERSHELL_QUALIFIED_DELETE.search(command)
    if qualified:
        return _powershell_mutation_verdict(
            enabled,
            "disk-hygiene flagged the module-qualified deletion spelling "
            f'"{qualified.group(0)}".',
        )
    if _POWERSHELL_ROBOCOPY_PURGE.search(command):
        return _powershell_mutation_verdict(
            enabled,
            "disk-hygiene flagged a robocopy mirror/purge/move invocation "
            "(mass deletion via mirroring).",
        )
    return None


def _powershell_mutation_verdict(enabled: bool, flagged: str) -> tuple[str, str]:
    """Deny a flagged PowerShell deletion in audit-only mode; otherwise prompt."""
    if not enabled:
        return (
            "deny",
            f"{flagged} Disk-hygiene execution is disabled (audit-only mode), so "
            "deletions are blocked on every lane.",
        )
    return (
        "ask",
        f"{flagged} Confirm only if this is the explicitly approved manual "
        "handoff and the command touches exactly the paths you approved.",
    )


def _bash_denial_guidance(authority: str | None) -> str:
    data_root = _display_data_root(authority)
    data_sentence = (
        f' Pass --data-root "{data_root}" so generated state lands in the plugin data directory.'
        if data_root
        else (
            " The guard did not receive an authorized data root (none of the"
            f" {_PLUGIN_ROOT_FLAG} or {_AUTHORIZED_DATA_ROOT_FLAG} hook arguments"
            " nor CLAUDE_PLUGIN_DATA resolved one), so --data-root cannot be"
            " validated and engine calls fail closed."
        )
    )
    return (
        "Disk-hygiene fails closed: Bash is restricted to exact bundled scan, preview, handoff-verify, and apply invocations using the hook's absolute Python interpreter "
        f'"{_display_python()}". Bare python/python3 commands are denied because shell functions and aliases can replace them.'
        + data_sentence
        + " Use non-Bash read-only tools for supporting inspection."
    )


_WATCHDOG_ENV_VAR = "DISK_HYGIENE_GUARD_WATCHDOG_SECONDS"
_WATCHDOG_DEFAULT_SECONDS = 10.0


def _watchdog_seconds() -> float:
    """The guard's own internal deadline, in seconds (module docstring, AC 5).

    Every legitimate invocation completes in milliseconds; a finite positive
    value from ``DISK_HYGIENE_GUARD_WATCHDOG_SECONDS`` lets an operator raise
    the deadline on a known-slow filesystem, and any absent, non-numeric,
    non-finite, or non-positive override falls back to the default rather than
    disarming the watchdog or raising.

    The non-finite rejection is load-bearing, not defensive tidiness: ``inf``,
    ``nan``, and overflowing literals such as ``1e400`` all parse cleanly
    through ``float`` and ``inf`` passes a bare ``> 0`` test, but
    ``threading.Timer(inf, ...)`` accepts ``start()`` and then dies inside the
    timer thread with ``OverflowError: timestamp out of range for platform
    time_t``. Because that raises on the *background* thread it never reaches
    ``main``'s exit-2 boundary — it would silently disarm the watchdog while
    leaving the guard apparently armed, the exact fail-open shape #1423 exists
    to close.
    """
    raw = os.environ.get(_WATCHDOG_ENV_VAR)
    if not raw:
        return _WATCHDOG_DEFAULT_SECONDS
    try:
        value = float(raw)
    except ValueError:
        return _WATCHDOG_DEFAULT_SECONDS
    if not math.isfinite(value) or value <= 0:
        return _WATCHDOG_DEFAULT_SECONDS
    return value


def _watchdog_fire(deadline: float) -> None:
    """Watchdog callback (background timer thread): deny fast, never hang silently.

    ``os._exit`` — not ``sys.exit`` — is deliberate: the main thread is
    presumed stuck inside a syscall this callback cannot interrupt or join,
    so this is a hard process exit, the one way this module can still
    guarantee "deny, with a diagnostic" once cooperative return is no longer
    an option.
    """
    print(
        f"destructive_guard: internal deadline of {deadline:g}s exceeded; "
        f"denying by default. Raise {_WATCHDOG_ENV_VAR} if this guard "
        "legitimately needs longer on this filesystem.",
        file=sys.stderr,
        flush=True,
    )
    os._exit(2)  # noqa: SLF001 -- hard exit is the point; see docstring


def _decide(command: str, tool_name: str) -> int:
    """The guard's decision logic once the JSON payload has parsed cleanly.

    Every branch prints its decision (or nothing, for an instant plugin-level
    defer) and returns 0; ``main`` supplies the watchdog and the exit-2
    fail-closed boundary around this call, so nothing in here needs its own
    exception handling to keep the exit-1 contract in the module docstring.
    """
    if resolve_mode() == _MODE_ENGINE_GATE and not _engine_gate_relevant(
        command, tool_name
    ):
        # Plugin-level gate: no engine invocation in the command — defer with no
        # output so unrelated work in every consumer session is untouched.
        return 0

    enabled = resolve_disk_hygiene_enabled()

    if tool_name == "PowerShell":
        verdict = powershell_decision(command, enabled)
        if verdict:
            print(json.dumps(decision(*verdict)))
        return 0

    authority = resolve_authorized_data_root()
    if is_exact_kill_switch_probe(command):
        print(
            json.dumps(
                decision(
                    "allow",
                    "Exact bundled disk-hygiene kill-switch probe (read-only report).",
                )
            )
        )
        return 0
    command_kind = classify_exact_engine_command(command, authority)
    if command_kind in {"scan", "preview", "handoff-verify"}:
        print(
            json.dumps(
                decision(
                    "allow",
                    "Exact bundled disk-hygiene read-only gate invocation.",
                )
            )
        )
        return 0
    if command_kind == "apply" and enabled:
        print(
            json.dumps(
                decision(
                    "ask",
                    "disk-hygiene is ready to apply one exact, previewed tier. Confirm this final mutation prompt only if it matches the tier and paths you just approved.",
                )
            )
        )
        return 0
    reason = (
        "Disk-hygiene execution is disabled; only exact bundled scan, preview, and handoff-verify invocations are permitted."
        if command_kind == "apply"
        else _bash_denial_guidance(authority)
    )
    print(json.dumps(decision("deny", reason)))
    return 0


def main() -> int:
    # Fail-closed safety boundary (#1423): only 0 and 2 are reachable past this
    # point. The watchdog denies fast on an internal deadline instead of
    # letting a stalled syscall run toward a harness-level, non-blocking kill
    # (module docstring, AC 5); the broad except denies on any exception this
    # function (or anything it calls) still manages to raise, replacing the
    # interpreter's default "uncaught exception -> exit 1, proceed" behavior
    # with "exit 2, deny" (AC 1-2). BaseException is deliberate — a
    # KeyboardInterrupt reaching a security guard mid-decision is exactly the
    # kind of "not a deliberate, reasoned allow" path AC 1 requires to deny,
    # not to propagate.
    #
    # Arming the watchdog is the FIRST action inside the boundary — before the
    # stdin read, not after it. Two failure shapes this closes, both landing
    # on a killed-hook, no-decision fail-open if the watchdog is not yet armed
    # while they happen: (1) under OS thread or memory exhaustion
    # `threading.Timer(...)` / `.start()` raises `RuntimeError: can't start
    # new thread`, which from outside this boundary would reach the
    # interpreter's default handler — exit 1, non-blocking, destructive
    # command proceeds; (2) `json.load(sys.stdin)` blocks through EOF, and a
    # Windows Win32 pipe can deliver the complete JSON payload but delay the
    # EOF signal — the same late-EOF stall class the bash hook fleet bounds
    # with a read timeout (plugins/guardrails/CHANGELOG.md, "[0.8.0]" ->
    # `hook::buffer_stdin`). Python's blocking read has no partial-read risk
    # the way bash's `read -t` does, so the watchdog's existing hard
    # `os._exit(2)` on deadline is the equivalent bound here: arming it before
    # the read means a late-EOF stall denies fast instead of running past the
    # declared hook `timeout` toward the harness's own non-blocking kill.
    deadline = _watchdog_seconds()
    watchdog: threading.Timer | None = None
    try:
        watchdog = threading.Timer(deadline, _watchdog_fire, args=(deadline,))
        watchdog.daemon = True
        watchdog.start()
        try:
            payload = json.load(sys.stdin)
            tool_name = payload.get("tool_name", "")
            command = payload["tool_input"]["command"]
            if not isinstance(command, str):
                raise TypeError("command is not text")
        except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
            print(
                json.dumps(
                    decision(
                        "deny",
                        f"disk-hygiene guard could not validate the shell call: {exc}",
                    )
                )
            )
            return 0
        return _decide(command, tool_name)
    except BaseException as exc:
        print(
            f"destructive_guard: internal error, denying by default "
            f"({type(exc).__name__}: {exc})",
            file=sys.stderr,
        )
        return 2
    finally:
        # `watchdog` stays None if construction itself raised; cancelling an
        # armed-but-unstarted timer is harmless.
        if watchdog is not None:
            watchdog.cancel()


if __name__ == "__main__":
    raise SystemExit(main())

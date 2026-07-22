#!/usr/bin/env python3
"""Fail-closed skill hook: allow only exact bundled hygiene-engine commands."""

from __future__ import annotations

import json
import os
import re
import sys
from pathlib import Path


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


def _literal_shell_words(command: str) -> list[str] | None:
    """Parse only space-delimited literal words with optional whole-word quotes."""
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
            if quote == '"' and "\\\\" in word:
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
                or "\\" in word
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

_DISK_HYGIENE_ENABLED_FLAG = "--disk-hygiene-enabled"
_DISK_HYGIENE_ENABLED_ENV = "CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED"
_DISK_HYGIENE_ENABLED_PLACEHOLDER = "${user_config.disk_hygiene_enabled}"


def _argv_flag_value(argv: list[str], flag: str) -> str | None:
    """Read the runtime-substituted value the frontmatter hook passed for ``flag``.

    Inline placeholder substitution resolves in hook ``args`` even where
    environment injection does not, so the guard's own argv is the authoritative,
    model-unforgeable channel for a value the harness controls. Accepts both the
    space-separated (``--flag value``) and ``--flag=value`` spellings.
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
    """Resolve the authoritative data root from the hook argv, then the environment.

    A literal, unsubstituted placeholder is treated as absent so the environment
    fallback still applies.
    """
    from_argv = _argv_authorized_data_root(sys.argv[1:])
    if from_argv and from_argv != _AUTHORIZED_DATA_ROOT_PLACEHOLDER:
        return from_argv
    return os.environ.get(_CLAUDE_PLUGIN_DATA_ENV)


def resolve_disk_hygiene_enabled() -> bool:
    """Resolve the execution kill switch from the hook argv, then the environment.

    The kill switch is a safety control: ``false`` is audit-only mode and must
    prevent every deletion lane. The runtime does not inject
    ``CLAUDE_PLUGIN_OPTION_DISK_HYGIENE_ENABLED`` into a skill-frontmatter hook's
    process environment, so the configured value reaches the guard through the
    hook argv (``--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}``);
    the environment variable is honored only as a fallback. A literal,
    unsubstituted placeholder or an empty value is treated as absent. When no
    channel supplies a value the guard fails safe to enabled — the guard stays
    active and still gates every mutation behind the final human prompt.
    """
    from_argv = _argv_flag_value(sys.argv[1:], _DISK_HYGIENE_ENABLED_FLAG)
    if from_argv and from_argv != _DISK_HYGIENE_ENABLED_PLACEHOLDER:
        return from_argv.strip().lower() != "false"
    return os.environ.get(_DISK_HYGIENE_ENABLED_ENV, "true").strip().lower() != "false"


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
    """Return scan/preview/apply only for one complete, canonical invocation."""
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
    r"remove-item|rm|rmdir|del|erase|rd|ri|clear-content|rimraf|unlink"
    r"|sendtorecyclebin|deletefile|deletedirectory|removedirectory"
    r")(?![\w-])"
)
_POWERSHELL_DOTNET_DELETE = re.compile(r"(?i)::\s*delete")


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
    if "hygiene.py" in command.casefold():
        return (
            "deny",
            "disk-hygiene engine invocations must go through the Bash tool's "
            "exact guarded command shapes, not PowerShell.",
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
            " The guard did not receive an authorized data root (neither the"
            f" {_AUTHORIZED_DATA_ROOT_FLAG} hook argument nor CLAUDE_PLUGIN_DATA),"
            " so --data-root cannot be validated and engine calls fail closed."
        )
    )
    return (
        "Disk-hygiene fails closed: Bash is restricted to exact bundled scan, preview, and apply invocations using the hook's absolute Python interpreter "
        f'"{_display_python()}". Bare python/python3 commands are denied because shell functions and aliases can replace them.'
        + data_sentence
        + " Use non-Bash read-only tools for supporting inspection."
    )


def main() -> int:
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
    if command_kind in {"scan", "preview"}:
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
        "Disk-hygiene execution is disabled; only exact bundled scan and preview invocations are permitted."
        if command_kind == "apply"
        else _bash_denial_guidance(authority)
    )
    print(json.dumps(decision("deny", reason)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

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


def _is_authorized_data_root(value: str) -> bool:
    """Accept only the data root this hook process was told about by the runtime."""
    authority = os.environ.get("CLAUDE_PLUGIN_DATA")
    if not authority:
        return False
    return _data_root_key(value) == _data_root_key(authority)


def _display_data_root() -> str | None:
    authority = os.environ.get("CLAUDE_PLUGIN_DATA")
    if not authority:
        return None
    return os.fspath(Path(authority).expanduser().resolve(strict=False)).replace(
        "\\", "/"
    )


def _valid_optional_value(flag: str, value: str) -> bool:
    if not _argument(value):
        return False
    if flag == "--max-depth":
        return re.fullmatch(r"[1-9][0-9]{0,3}", value) is not None
    if flag == "--data-root":
        return _is_authorized_data_root(value)
    return True


def _consume_optional_pairs(tokens: list[str], allowed: frozenset[str]) -> bool:
    seen: list[str] = []
    while tokens:
        flag = tokens[0]
        if (
            flag not in allowed
            or flag in seen
            or len(tokens) < 2
            or not _valid_optional_value(flag, tokens[1])
        ):
            return False
        seen.append(flag)
        tokens = tokens[2:]
    return True


def classify_exact_engine_command(command: str) -> str | None:
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
            len(tokens) not in {7, 9, 11, 13, 15}
            or tokens[3] != "--target"
            or not _argument(tokens[4])
            or tokens[5] != "--output"
            or not _argument(tokens[6])
        ):
            return None
        if not _consume_optional_pairs(
            tokens[7:],
            frozenset({"--policy", "--project-dir", "--data-root", "--max-depth"}),
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
            and _consume_optional_pairs(tokens[7:], frozenset({"--data-root"}))
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
                _consume_optional_pairs(tokens[14:], frozenset({"--data-root"})),
            )
        )
        return "apply" if valid else None
    return None


def is_exact_engine_apply(command: str) -> bool:
    return classify_exact_engine_command(command) == "apply"


_POWERSHELL_MUTATION_WORDS = re.compile(
    r"(?i)(?<![\w./\\-])("
    r"remove-item|rm|rmdir|del|erase|rd|ri|clear-content|rimraf|unlink"
    r"|sendtorecyclebin|deletefile|deletedirectory|removedirectory"
    r")(?![\w-])"
)
_POWERSHELL_DOTNET_DELETE = re.compile(r"(?i)::\s*delete")


def powershell_decision(command: str) -> tuple[str, str] | None:
    """Return a (decision, reason) pair for a PowerShell command, or None to defer.

    PowerShell stays available for read-only support work (git, gh, metadata
    inspection), so this lane gates known filesystem-mutation spellings and any
    engine invocation rather than denying unknown commands. Engine calls stay on
    the Bash lane's fail-closed deny-unknown guard; mutation spellings surface
    the same final human permission prompt as the engine apply lane, so the
    unsupported-platform manual handoff remains possible but never silent.
    """
    if "hygiene.py" in command.casefold():
        return (
            "deny",
            "disk-hygiene engine invocations must go through the Bash tool's "
            "exact guarded command shapes, not PowerShell.",
        )
    match = _POWERSHELL_MUTATION_WORDS.search(command)
    if match:
        return (
            "ask",
            f'disk-hygiene flagged the deletion spelling "{match.group(0)}". '
            "Confirm only if this is the explicitly approved manual handoff and "
            "the command touches exactly the paths you approved.",
        )
    if _POWERSHELL_DOTNET_DELETE.search(command):
        return (
            "ask",
            "disk-hygiene flagged a .NET Delete call. Confirm only if this is "
            "the explicitly approved manual handoff and the command touches "
            "exactly the paths you approved.",
        )
    return None


def _bash_denial_guidance() -> str:
    data_root = _display_data_root()
    data_sentence = (
        f' Pass --data-root "{data_root}" so generated state lands in the plugin data directory.'
        if data_root
        else (
            " The hook process did not receive CLAUDE_PLUGIN_DATA, so --data-root"
            " cannot be validated and engine calls fail closed."
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

    if tool_name == "PowerShell":
        verdict = powershell_decision(command)
        if verdict:
            print(json.dumps(decision(*verdict)))
        return 0

    command_kind = classify_exact_engine_command(command)
    enabled = os.environ.get("HOOK_DISK_HYGIENE_ENABLED", "true").lower() != "false"
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
        else _bash_denial_guidance()
    )
    print(json.dumps(decision("deny", reason)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

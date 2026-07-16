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
            len(tokens) not in {7, 9, 11}
            or tokens[3] != "--target"
            or not _argument(tokens[4])
            or tokens[5] != "--output"
            or not _argument(tokens[6])
        ):
            return None
        optional = tokens[7:]
        seen: list[str] = []
        while optional:
            flag = optional[0]
            if (
                flag not in {"--policy", "--project-dir"}
                or flag in seen
                or len(optional) < 2
                or not _argument(optional[1])
            ):
                return None
            seen.append(flag)
            optional = optional[2:]
        return "scan"
    if tokens[2] == "preview":
        valid = (
            len(tokens) == 7
            and tokens[3] == "--snapshot"
            and _argument(tokens[4])
            and tokens[5] == "--plan"
            and _argument(tokens[6])
        )
        return "preview" if valid else None
    if tokens[2] == "apply":
        if len(tokens) != 14:
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
            )
        )
        return "apply" if valid else None
    return None


def is_exact_engine_apply(command: str) -> bool:
    return classify_exact_engine_command(command) == "apply"


def main() -> int:
    try:
        payload = json.load(sys.stdin)
        command = payload["tool_input"]["command"]
        if not isinstance(command, str):
            raise TypeError("command is not text")
    except (KeyError, TypeError, ValueError, json.JSONDecodeError) as exc:
        print(
            json.dumps(
                decision(
                    "deny",
                    f"disk-hygiene guard could not validate the Bash call: {exc}",
                )
            )
        )
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
        else "Disk-hygiene fails closed: Bash is restricted to exact bundled scan, preview, and apply invocations using the hook's absolute Python interpreter "
        f'"{_display_python()}". Bare python/python3 commands are denied because shell functions and aliases can replace them. Use non-Bash read-only tools for supporting inspection.'
    )
    print(json.dumps(decision("deny", reason)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

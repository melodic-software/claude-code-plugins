#!/usr/bin/env python3
"""Skill-scoped PreToolUse guard: route deletion only through hygiene.py."""

from __future__ import annotations

import json
import os
import re
import shlex
import sys
from pathlib import Path

DELETE_PATTERNS = [
    r"(^|[\s;&|])rm\s+",
    r"(^|[\s;&|])(rmdir|rd|unlink)\s+",
    r"(^|[\s;&|])(del|erase)\s+",
    r"\bRemove-Item\b",
    r"\bfind\b.*\s-delete(\s|$)",
    r"\b(os\.(remove|unlink|rmdir)|shutil\.rmtree)\s*\(",
    r"\.(unlink|rmdir)\s*\(",
    r"\[(System\.)?IO\.(File|Directory)\]::Delete\s*\(",
]


def decision(value: str, reason: str) -> dict[str, object]:
    return {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": value,
            "permissionDecisionReason": reason,
        }
    }


def is_exact_engine_apply(command: str) -> bool:
    expected_script = str(Path(__file__).resolve().with_name("hygiene.py"))
    if any(
        value in command for value in (";", "|", "&", "\r", "\n", "`", "$(", ">", "<")
    ):
        return False
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return False
    if len(tokens) != 14:
        return False
    normalized_script = expected_script.replace("\\", "/").casefold()
    candidate_script = tokens[1].replace("\\", "/").casefold()
    return all(
        (
            tokens[0].casefold() in {"python", "python.exe"},
            candidate_script == normalized_script,
            tokens[2:5] == ["apply", "--execute", "--snapshot"],
            tokens[5] != "",
            tokens[6] == "--plan",
            tokens[7] != "",
            tokens[8] == "--confirm-tier",
            tokens[9] in {"high", "medium", "low"},
            tokens[10] == "--approval-token",
            re.fullmatch(r"[0-9a-f]{24}", tokens[11]) is not None,
            tokens[12] == "--report",
            tokens[13] != "",
        )
    )


def main() -> int:
    if os.environ.get("HOOK_DISK_HYGIENE_ENABLED", "true").lower() == "false":
        print("{}")
        return 0
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
    if is_exact_engine_apply(command):
        print(
            json.dumps(
                decision(
                    "ask",
                    "disk-hygiene is ready to apply one exact, previewed tier. Confirm this final mutation prompt only if it matches the tier and paths you just approved.",
                )
            )
        )
        return 0
    if "hygiene.py" in command and " apply " in f" {command} ":
        print(
            json.dumps(
                decision(
                    "deny",
                    "The disk-hygiene apply command did not reference this plugin's exact bundled engine or was not a single complete command.",
                )
            )
        )
        return 0
    if any(
        re.search(pattern, command, flags=re.IGNORECASE | re.DOTALL)
        for pattern in DELETE_PATTERNS
    ):
        print(
            json.dumps(
                decision(
                    "deny",
                    "Direct deletion is blocked while /disk-hygiene:clean is active. Run hygiene.py preview, obtain explicit per-tier approval, then use its exact apply command.",
                )
            )
        )
        return 0
    print("{}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

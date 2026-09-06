#!/usr/bin/env python3
"""Write or update the consumer's team configuration file, idempotently.

  setup-apply.py [--dir <repo-root> | --file <path>] <key>=<value>...

The target is `<repo-root>/.claude/code-metrics.yaml` (or `--file`); with
neither option the root is what `git rev-parse --show-toplevel` reports from
the current directory, or the current directory outside a repository. Each
`<key>=<value>` is a dotted key from the plugin's config contract and a value
written in the YAML subset the plugin reads (`500`, `true`, `null`,
`"quoted"`, `[a, b]`). The existing file is parsed, the keys are merged per
key (unknown keys the file already carries are preserved), and the result is
written in block style. A run that changes nothing prints `already configured`
and leaves the file byte-identical, so the command is safe to repeat.

The keys are validated against the bundled defaults: a key the contract does
not declare is written (unknown keys are inert to the plugin) but reported
as a warning, so a typo does not pass silently. Exit 0 on success, 2 on a
usage error or a value outside the subset.
"""

from __future__ import annotations

import importlib.util
import json
import os
import subprocess
import sys
from typing import Any

MIN_PYTHON = (3, 9)
HERE = os.path.dirname(os.path.abspath(__file__))
PLUGIN_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
SCRIPTS = os.path.join(PLUGIN_ROOT, "scripts")

_spec = importlib.util.spec_from_file_location(
    "yaml_subset", os.path.join(SCRIPTS, "yaml_subset.py")
)
assert _spec is not None and _spec.loader is not None
yaml_subset = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(yaml_subset)

HEADER = (
    "# code-metrics configuration (team layer). Contract: the plugin's reference/config.md.\n"
    "# Layers: ~/.claude/code-metrics.yaml, this file, .claude/code-metrics.local.yaml (per-key override).\n"
)


def _needs_quotes(text: str) -> bool:
    if text == "" or text != text.strip():
        return True
    if text[0] in "-?:,[]{}#&*!|>'\"%@`":
        return True
    if ": " in text or " #" in text:
        return True
    try:
        parsed = yaml_subset.parse(f"v: {text}")["v"]
    except yaml_subset.YamlSubsetError:
        return True
    return not (isinstance(parsed, str) and parsed == text)


def _scalar(value: Any) -> str:
    if value is None:
        return "null"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, (int, float)):
        return repr(value)
    text = str(value)
    if _needs_quotes(text):
        return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return text


def dump(node: Any, indent: int = 0) -> list[str]:
    pad = " " * indent
    lines: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            key_text = _scalar(key) if _needs_quotes(str(key)) else str(key)
            if isinstance(value, dict):
                if value:
                    lines.append(f"{pad}{key_text}:")
                    lines.extend(dump(value, indent + 2))
                else:
                    lines.append(f"{pad}{key_text}: null")
            elif isinstance(value, list):
                if all(not isinstance(item, (dict, list)) for item in value):
                    lines.append(
                        f"{pad}{key_text}: ["
                        + ", ".join(_scalar(v) for v in value)
                        + "]"
                    )
                else:
                    lines.append(f"{pad}{key_text}:")
                    for item in value:
                        if isinstance(item, dict):
                            body = dump(item, indent + 4)
                            lines.append(f"{pad}  - " + body[0].strip())
                            lines.extend(body[1:])
                        else:
                            lines.append(f"{pad}  - {_scalar(item)}")
            else:
                lines.append(f"{pad}{key_text}: {_scalar(value)}")
    return lines


class ValueError_(ValueError):
    """A value outside the YAML subset; main() turns it into exit 2."""


def parse_value(text: str, key: str) -> Any:
    try:
        return yaml_subset.parse(f"v: {text}")["v"]
    except (yaml_subset.YamlSubsetError, KeyError, TypeError) as exc:
        raise ValueError_(f"{key}: value {text!r} is outside the YAML subset ({exc})")


def set_dotted(doc: dict[str, Any], dotted: str, value: Any) -> None:
    parts = dotted.split(".")
    node = doc
    for part in parts[:-1]:
        child = node.get(part)
        if not isinstance(child, dict):
            child = {}
            node[part] = child
        node = child
    node[parts[-1]] = value


def known_keys() -> set[str]:
    with open(
        os.path.join(SCRIPTS, "config-defaults.json"), encoding="utf-8"
    ) as handle:
        defaults = json.load(handle)
    keys: set[str] = set()

    def walk(node: Any, prefix: str) -> None:
        if isinstance(node, dict):
            for key, value in node.items():
                dotted = f"{prefix}.{key}" if prefix else key
                keys.add(dotted)
                walk(value, dotted)

    walk({k: v for k, v in defaults.items() if k != "thresholds"}, "")
    # Per-lane collector overrides are declared by shape, not enumerated.
    for lane in defaults.get("lanes") or {}:
        keys.add(f"lanes.{lane}.collectors")
    return keys


def main(argv: list[str]) -> int:
    target = None
    assignments: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--dir", "--file"):
            if i + 1 >= len(argv):
                print(f"setup-apply.py: {arg} needs a value", file=sys.stderr)
                return 2
            value = argv[i + 1]
            target = (
                os.path.join(value, ".claude", "code-metrics.yaml")
                if arg == "--dir"
                else value
            )
            i += 2
            continue
        if arg in ("-h", "--help"):
            print(__doc__.strip())
            return 0
        if "=" not in arg or arg.startswith("-"):
            print(
                f"setup-apply.py: expected <key>=<value>, got {arg!r}", file=sys.stderr
            )
            return 2
        assignments.append(arg)
        i += 1
    if target is None:
        # No --dir: the repository root when git resolves one, else the cwd,
        # so the skill needs no command substitution in its allowed command.
        try:
            probe = subprocess.run(
                ["git", "rev-parse", "--show-toplevel"],
                capture_output=True,
                text=True,
                check=False,
            )
            root = probe.stdout.strip() if probe.returncode == 0 else ""
        except OSError:
            root = ""
        target = os.path.join(root or os.getcwd(), ".claude", "code-metrics.yaml")
    if not assignments:
        print("setup-apply.py: at least one <key>=<value> is required", file=sys.stderr)
        return 2
    existing_text = ""
    doc: dict[str, Any] = {}
    if os.path.isfile(target):
        with open(target, encoding="utf-8") as handle:
            existing_text = handle.read()
        try:
            parsed = yaml_subset.parse(existing_text)
        except yaml_subset.YamlSubsetError as exc:
            print(
                f"setup-apply.py: {target} is outside the YAML subset ({exc}); fix it by hand first",
                file=sys.stderr,
            )
            return 2
        if parsed is None:
            parsed = {}
        if not isinstance(parsed, dict):
            print(
                f"setup-apply.py: {target}: the top level must be a mapping",
                file=sys.stderr,
            )
            return 2
        doc = parsed
    known = known_keys()
    for assignment in assignments:
        key, _, raw = assignment.partition("=")
        key = key.strip()
        if not key:
            print(f"setup-apply.py: empty key in {assignment!r}", file=sys.stderr)
            return 2
        if key not in known and not any(
            key.startswith(k + ".") for k in known if k.endswith(".collectors")
        ):
            print(
                f"setup-apply.py: warning: {key} is not a key the contract declares; written anyway (unknown keys are inert)",
                file=sys.stderr,
            )
        try:
            set_dotted(doc, key, parse_value(raw.strip(), key))
        except ValueError_ as exc:
            print(f"setup-apply.py: {exc}", file=sys.stderr)
            return 2
    body = "\n".join(dump(doc)) + "\n"
    new_text = (
        HEADER + body
        if not existing_text.startswith("#")
        else existing_text.split("\n", 2)[0]
        + "\n"
        + (
            existing_text.split("\n", 2)[1] + "\n"
            if existing_text.startswith(HEADER)
            else ""
        )
        + body
    )
    # Idempotence is judged on the parsed content, so comments the operator
    # added by hand never force a rewrite by themselves.
    if existing_text and yaml_subset.parse(existing_text) == doc:
        print(f"already configured: {target}")
        return 0
    if not existing_text.startswith(HEADER):
        new_text = HEADER + body
    os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
    with open(target, "w", encoding="utf-8", newline="\n") as handle:
        handle.write(new_text)
    print(f"written: {target}")
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "setup-apply.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

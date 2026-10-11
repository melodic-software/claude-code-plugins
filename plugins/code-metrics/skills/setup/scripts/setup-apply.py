#!/usr/bin/env python3
"""Write or update the consumer's team configuration file, idempotently.

  setup-apply.py [--dir <repo-root> | --file <path>] [<key>=<value>...]

The target is `<repo-root>/docs/conventions/code-metrics.yaml` (or `--file`);
with neither option the root is what `git rev-parse --show-toplevel` reports
from the current directory, or the current directory outside a repository.
When that file does not exist yet and the older `<repo-root>/.claude/
code-metrics.yaml` does, every key of the older file is carried into the new
one in the same write, except a key the contract does not declare, which is
dropped and named on stderr; with no `<key>=<value>` the run is that move
alone. The older file is left in place for plugin releases that read only it.
Each `<key>=<value>` is a dotted key from the plugin's config contract and a
value written in the YAML subset the plugin reads (`500`, `true`, `null`,
`"quoted"`, `[a, b]`). The existing file is parsed, the keys are merged per
key (unknown keys the file already carries are preserved), and the result is
written in block style. A run that changes nothing prints `already configured`
and leaves the file byte-identical, so the command is safe to repeat.

The keys are validated against the bundled defaults: a key the contract does
not declare is written (unknown keys are inert to the plugin) but reported
as a warning, so a typo does not pass silently.

Path safety: docs/, docs/conventions/, .claude/, the target and the older file
are refused when a symlink, the wrong file type, or (for a file) more than one
hard link, and each must resolve under the repository root. An explicit
`--file` outside that layout gets the file checks only. The write goes to a
temp file opened O_CREAT|O_EXCL|O_NOFOLLOW beside the target, then renamed
over it. Exit 0 on success, 1 on an unsafe path or a failed write, 2 on a
usage error or a value outside the subset.
"""

from __future__ import annotations

import importlib.util
import json
import os
import stat
import subprocess
import sys
from typing import Any, Callable

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
    "# code-metrics configuration (team layer). Contract: the plugin's reference/config.md;\n"
    "# schema: the plugin's schemas/code-metrics.schema.json.\n"
    "# Layers: ~/.claude/code-metrics.yaml, this file, .claude/code-metrics.local.yaml (per-key override).\n"
)
TEAM_PARTS = ["docs", "conventions"]
TEAM_FILE = os.path.join(*TEAM_PARTS, "code-metrics.yaml")
LEGACY_FILE = os.path.join(".claude", "code-metrics.yaml")
NOFOLLOW = getattr(os, "O_NOFOLLOW", 0)


class UnsafePath(Exception):
    """A path shape that could send a read or write outside the repository."""


def _under(path: str, real_root: str | None, what: str) -> None:
    if real_root is None:
        return
    resolved = os.path.realpath(path)
    if resolved != real_root and not resolved.startswith(real_root + os.sep):
        raise UnsafePath(f"{what} resolves outside the repository")


def check_dir(path: str, what: str, real_root: str | None) -> bool:
    """True when the directory exists; UnsafePath on any unsafe shape."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return False
    if stat.S_ISLNK(st.st_mode):
        raise UnsafePath(f"{what} is a symlink; refusing to go through it")
    if not stat.S_ISDIR(st.st_mode):
        raise UnsafePath(f"{what} exists and is not a directory")
    _under(path, real_root, what)
    return True


def check_file(path: str, what: str, real_root: str | None) -> bool:
    """True when the file exists; UnsafePath on any unsafe shape."""
    try:
        st = os.lstat(path)
    except FileNotFoundError:
        return False
    if stat.S_ISLNK(st.st_mode):
        raise UnsafePath(f"{what} is a symlink; refusing to read or write through it")
    if not stat.S_ISREG(st.st_mode):
        raise UnsafePath(f"{what} exists and is not a regular file")
    if st.st_nlink > 1:
        raise UnsafePath(f"{what} has {st.st_nlink} hard links; refusing to use it")
    _under(path, real_root, what)
    return True


def check_chain(root: str, real_root: str, parts: list[str], name: str) -> bool:
    """Check each directory of parts under root, then the file parts/name."""
    for i in range(1, len(parts) + 1):
        rel = os.path.join(*parts[:i])
        if not check_dir(os.path.join(root, rel), rel, real_root):
            return False
    rel = os.path.join(*parts, name)
    return check_file(os.path.join(root, rel), rel, real_root)


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


def drop_unknown(doc: dict[str, Any], known: set[str], prefix: str = "") -> list[str]:
    """Remove every key the contract does not declare; return their dotted names."""
    collectors = [k for k in known if k.endswith(".collectors")]
    dropped: list[str] = []
    for key in list(doc):
        dotted = f"{prefix}{key}"
        if any(dotted == k or dotted.startswith(k + ".") for k in collectors):
            continue
        if dotted not in known:
            del doc[key]
            dropped.append(dotted)
        elif isinstance(doc[key], dict) and any(
            k.startswith(dotted + ".") for k in known
        ):
            dropped.extend(drop_unknown(doc[key], known, dotted + "."))
    return dropped


def read_mapping(path: str) -> tuple[str, dict[str, Any]]:
    """The file's text and its top-level mapping; ValueError_ when unusable."""
    with open(os.open(path, os.O_RDONLY | NOFOLLOW), encoding="utf-8") as handle:
        text = handle.read()
    try:
        parsed = yaml_subset.parse(text)
    except yaml_subset.YamlSubsetError as exc:
        raise ValueError_(
            f"{path} is outside the YAML subset ({exc}); fix it by hand first"
        )
    if parsed is None:
        parsed = {}
    if not isinstance(parsed, dict):
        raise ValueError_(f"{path}: the top level must be a mapping")
    return text, parsed


def write_file(target: str, text: str, recheck: Callable[[], bool]) -> None:
    """Write text through an O_EXCL|O_NOFOLLOW temp file renamed over target."""
    tmp = os.path.join(
        os.path.dirname(os.path.abspath(target)),
        f".{os.path.basename(target)}.{os.getpid()}.tmp",
    )
    fd = os.open(tmp, os.O_WRONLY | os.O_CREAT | os.O_EXCL | NOFOLLOW, 0o644)
    try:
        with open(fd, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(text)
        recheck()
        os.replace(tmp, target)
    except BaseException:
        try:
            os.unlink(tmp)
        except OSError:
            pass
        raise


def main(argv: list[str]) -> int:
    target = None
    root: str | None = None
    assignments: list[str] = []
    i = 0
    while i < len(argv):
        arg = argv[i]
        if arg in ("--dir", "--file"):
            if i + 1 >= len(argv):
                print(f"setup-apply.py: {arg} needs a value", file=sys.stderr)
                return 2
            value = argv[i + 1]
            if arg == "--dir":
                root = value
                target = os.path.join(value, TEAM_FILE)
            else:
                target = value
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
            top = probe.stdout.strip() if probe.returncode == 0 else ""
        except OSError:
            top = ""
        root = top or os.getcwd()
        target = os.path.join(root, TEAM_FILE)
    real_root = os.path.realpath(root) if root is not None else ""
    # The docs/ chain and the under-root check apply to the team file; an
    # explicit --file elsewhere is the operator's own path and gets the file
    # checks only.
    team = root is not None and os.path.abspath(target) == os.path.abspath(
        os.path.join(root, TEAM_FILE)
    )

    def check_target() -> bool:
        if team:
            assert root is not None
            return check_chain(root, real_root, TEAM_PARTS, "code-metrics.yaml")
        return check_file(target, target, None)

    existing_text = ""
    doc: dict[str, Any] = {}
    carried_from = None
    try:
        if check_target():
            existing_text, doc = read_mapping(target)
        elif root is not None and check_chain(
            root, real_root, [".claude"], "code-metrics.yaml"
        ):
            carried_from = os.path.join(root, LEGACY_FILE)
            _, doc = read_mapping(carried_from)
    except (UnsafePath, OSError) as exc:
        print(f"setup-apply.py: {exc}; nothing written", file=sys.stderr)
        return 1
    except ValueError_ as exc:
        print(f"setup-apply.py: {exc}", file=sys.stderr)
        return 2
    if not assignments and carried_from is None:
        print("setup-apply.py: at least one <key>=<value> is required", file=sys.stderr)
        return 2
    known = known_keys()
    if carried_from is not None:
        for dotted in drop_unknown(doc, known):
            print(
                f"setup-apply.py: dropped {dotted} from {carried_from}: not a key the contract declares",
                file=sys.stderr,
            )
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
    # Idempotence is judged on the parsed content, so comments the operator
    # added by hand never force a rewrite by themselves.
    if existing_text and yaml_subset.parse(existing_text) == doc:
        print(f"already configured: {target}")
        return 0
    try:
        if team:
            assert root is not None
            for depth in range(1, len(TEAM_PARTS) + 1):
                rel = os.path.join(*TEAM_PARTS[:depth])
                if not check_dir(os.path.join(root, rel), rel, real_root):
                    os.mkdir(os.path.join(root, rel))
        else:
            os.makedirs(os.path.dirname(os.path.abspath(target)), exist_ok=True)
        check_target()
        write_file(target, HEADER + body, check_target)
    except (UnsafePath, OSError) as exc:
        print(f"setup-apply.py: {exc}; nothing written", file=sys.stderr)
        return 1
    if carried_from is not None:
        print(
            f"carried every declared key of {carried_from}; that file is no longer read "
            "while this one exists, and can be deleted once no older plugin release reads it"
        )
    print(f"written: {target}")
    return 0


if __name__ == "__main__":
    if sys.version_info < MIN_PYTHON:
        print(
            "setup-apply.py needs Python %d.%d or later" % MIN_PYTHON, file=sys.stderr
        )
        sys.exit(2)
    sys.exit(main(sys.argv[1:]))

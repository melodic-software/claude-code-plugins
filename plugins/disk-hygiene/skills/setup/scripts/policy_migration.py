#!/usr/bin/env python3
"""Move the old ``.claude/disk-hygiene.json`` policy files to their cascade layers.

Three steps, each one command, so the setup skill can put a preview and a yes
before any write and set the ``policy_file`` option between the write and the
delete:

  check   read-only: name each old file, the new file it moves to, and whether
          the move can run
  move    with --yes: write each new file from its old one (the user file is
          copied as it is, the project file becomes YAML), leaving the old files
  finish  with --yes: for each old file whose new file exists, check the policy
          resolves the same from the new file, then delete the old file

The user file moves to the file the ``policy_file`` option names (--user-policy,
its value), else --user-target, else ``~/.config/disk-hygiene/policy.json``. The
project file moves to ``<convention home>/disk-hygiene.yaml``. A new file that
already exists is never overwritten.

Prints one JSON document; exit 0 when every step it was asked for ran, 1 when one
was refused, 2 for a usage error.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

_CLEAN_SCRIPTS = Path(__file__).resolve().parents[2] / "clean" / "scripts"
if str(_CLEAN_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_CLEAN_SCRIPTS))

import hygiene  # noqa: E402  (path set above; the clean engine)

PATH_KEYS = ("source", "hint_sources")
COMPARED_KEYS = (
    "hints",
    "additional_protected_path_globs",
    "rules",
    "elevation",
)
PLAIN_KEY = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


class MigrationError(Exception):
    pass


def same_file(first: Path, second: Path) -> bool:
    try:
        return os.path.samefile(first, second)
    except OSError:
        return False


def default_user_target() -> Path:
    return Path.home() / ".config" / "disk-hygiene" / "policy.json"


def plan(
    project_dir: Path | None, user_policy: str | None, user_target: str | None
) -> list[dict[str, Any]]:
    old = hygiene.old_policy_paths(project_dir)
    option = hygiene.user_policy_path(user_policy, [])
    user_new = option or (
        Path(user_target).expanduser() if user_target else default_user_target()
    )
    targets = {"userConfig": user_new}
    if project_dir is not None and not is_home(project_dir, old):
        targets["team"] = (
            hygiene.convention_home(project_dir) / hygiene.TEAM_POLICY_NAME
        )
    rows = []
    for layer, new_path in targets.items():
        old_path = old[layer]
        if not old_path.is_file() or same_file(old_path, new_path):
            continue
        row = {
            "layer": layer,
            "old": str(old_path),
            "new": str(new_path),
            "new_resolved": str(new_path.resolve()),
            "new_exists": new_path.is_file(),
            "set_option": layer == "userConfig" and option is None,
        }
        if layer == "team" and project_dir is not None:
            unsafe = outside_project(old_path, new_path, project_dir)
            if unsafe:
                row["result"] = f"refused: {unsafe}"
        rows.append(row)
    return rows


def is_home(project_dir: Path, old: dict[str, Path]) -> bool:
    return (
        project_dir.resolve() == Path.home().resolve()
        or old["team"].absolute() == old["userConfig"].absolute()
        or same_file(old["team"], old["userConfig"])
    )


def outside_project(old: Path, new: Path, project_dir: Path) -> str | None:
    root = project_dir.resolve()
    if old.is_symlink():
        return f"{old} is a symlink"
    if new.is_symlink():
        return f"{new} is a symlink"
    for path in (old.resolve(), new.parent.resolve()):
        if not path.is_relative_to(root):
            return f"{path} resolves outside {root}"
    return None


def _yaml_scalar(value: Any) -> str:
    if value is None:
        return "null"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        if any(ord(ch) < 32 and ch not in "\n\t" for ch in value):
            raise MigrationError(f"a control character in {value!r}")
        escaped = (
            value.replace("\\", "\\\\")
            .replace('"', '\\"')
            .replace("\n", "\\n")
            .replace("\t", "\\t")
        )
        return f'"{escaped}"'
    raise MigrationError(f"a value YAML cannot hold here: {value!r}")


def dump_yaml(node: Any, indent: int = 0) -> list[str]:
    pad = " " * indent
    lines: list[str] = []
    if isinstance(node, dict):
        for key, value in node.items():
            if not isinstance(key, str) or not PLAIN_KEY.fullmatch(key):
                raise MigrationError(f"a key YAML cannot hold plainly: {key!r}")
            if isinstance(value, dict) and not value:
                raise MigrationError(f"an empty mapping under {key!r}")
            if isinstance(value, (dict, list)) and value:
                lines.append(f"{pad}{key}:")
                lines.extend(dump_yaml(value, indent + 2))
            elif isinstance(value, list):
                lines.append(f"{pad}{key}: []")
            else:
                lines.append(f"{pad}{key}: {_yaml_scalar(value)}")
        return lines
    for item in node:
        if isinstance(item, dict) and item:
            first, *rest = dump_yaml(item, indent + 2)
            lines.append(f"{pad}- {first.lstrip()}")
            lines.extend(rest)
        elif isinstance(item, (dict, list)):
            raise MigrationError(f"a nested empty or list item: {item!r}")
        else:
            lines.append(f"{pad}- {_yaml_scalar(item)}")
    return lines


def to_yaml(document: dict[str, Any]) -> str:
    text = "\n".join(dump_yaml(document)) + "\n"
    if hygiene.yaml_subset.parse(text) != document:
        raise MigrationError("the YAML written does not read back as the JSON")
    return text


def _without_paths(node: Any) -> Any:
    if isinstance(node, dict):
        return {
            key: _without_paths(value)
            for key, value in node.items()
            if key not in PATH_KEYS
        }
    if isinstance(node, list):
        return [_without_paths(item) for item in node]
    return node


def effective(path: Path, layer: str) -> dict[str, Any]:
    result = hygiene.baseline_policy()
    hygiene.apply_policy_overlay(result, path, project_scope=layer != "userConfig")
    return {key: _without_paths(result[key]) for key in COMPARED_KEYS}


def move(rows: list[dict[str, Any]]) -> list[dict[str, Any]]:
    done = []
    for row in rows:
        old, new = Path(row["old"]), Path(row["new"])
        outcome = dict(row)
        if "result" in row:
            pass
        elif row["new_exists"]:
            outcome["result"] = "refused: the new file exists; merge by hand"
        else:
            try:
                text = old.read_text(encoding="utf-8")
                if row["layer"] == "team":
                    text = to_yaml(hygiene.load_json(old))
                new.parent.mkdir(parents=True, exist_ok=True)
                with new.open("x", encoding="utf-8") as handle:
                    handle.write(text)
                outcome["result"] = "written"
            except (OSError, MigrationError, hygiene.HygieneError) as exc:
                outcome["result"] = f"refused: {exc}"
        done.append(outcome)
    return done


def finish(
    rows: list[dict[str, Any]], user_policy: str | None, project_dir: Path | None
) -> list[dict[str, Any]]:
    option = hygiene.user_policy_path(user_policy, [])
    done = []
    for row in rows:
        old, new = Path(row["old"]), Path(row["new"])
        outcome = dict(row)
        if "result" in row:
            pass
        elif not new.is_file():
            outcome["result"] = "refused: the new file does not exist; run move"
        elif same_file(old, new) or old.resolve() == new.resolve():
            outcome["result"] = "refused: the new file is the old file"
        elif row["layer"] == "userConfig" and (
            option is None or not same_file(option, new)
        ):
            outcome["result"] = (
                f"refused: pass --user-policy naming {new} once the "
                f"{hygiene.POLICY_FILE_OPTION} option is set to it"
            )
        else:
            try:
                same = effective(old, row["layer"]) == effective(new, row["layer"])
            except hygiene.HygieneError as exc:
                same, outcome["error"] = False, str(exc)
            if not same:
                outcome["result"] = "refused: the new file resolves differently"
            else:
                try:
                    hygiene.remove_old_policy_file(old, project_dir)
                    outcome["result"] = "old file deleted"
                except (OSError, hygiene.HygieneError) as exc:
                    outcome["result"] = f"refused: {exc}"
        done.append(outcome)
    return done


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="policy_migration.py")
    parser.add_argument("step", choices=("check", "move", "finish"))
    parser.add_argument("--project-dir")
    parser.add_argument("--user-policy")
    parser.add_argument("--user-target")
    parser.add_argument("--yes", action="store_true")
    try:
        args = parser.parse_args(argv)
    except SystemExit:
        return 2
    if args.step != "check" and not args.yes:
        print(json.dumps({"error": f"{args.step} writes files; pass --yes"}))
        return 2
    project = (
        Path(args.project_dir).expanduser().absolute() if args.project_dir else None
    )
    rows = plan(project, args.user_policy, args.user_target)
    if args.step == "move":
        rows = move(rows)
    elif args.step == "finish":
        rows = finish(rows, args.user_policy, project)
    print(json.dumps({"step": args.step, "files": rows}, indent=2))
    refused = any(str(row.get("result", "")).startswith("refused") for row in rows)
    return 1 if refused else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

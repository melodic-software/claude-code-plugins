"""Bundled owner registry for the managed-state lane.

The JSON file next to the clean skill is the inspectable list of owners. A
path match is a hint. It does not authorize the engine to delete the path, and
it does not authorize a command that is not in the registry.

Read-only argv run only when the owning tool is on PATH. Destructive argv run
only from the managed-apply lane after the engine's exact-tier approval gate.
Neither lane invokes a shell.
"""

from __future__ import annotations

import json
import os
import shlex
import shutil
import subprocess
from pathlib import Path
from typing import Any, Callable

REGISTRY_PATH = (
    Path(__file__).resolve().parents[1]
    / "skills"
    / "clean"
    / "reference"
    / "owner-registry.json"
)

PLATFORMS = frozenset({"windows", "linux", "macos"})
_FORBIDDEN_ARGV_CHARS = set(";|&$`\n<>")
Which = Callable[[str], str | None]
Runner = Callable[[list[str]], dict[str, Any]]


class OwnerRegistryError(ValueError):
    """The bundled registry is missing a required field or is not safe to run."""


def _fold(value: str) -> str:
    return value.replace("\\", "/").strip().strip("/").casefold()


def _argv_ok(argv: object) -> bool:
    if not isinstance(argv, list) or not argv:
        return False
    return all(
        isinstance(part, str)
        and part
        and not any(char in part for char in _FORBIDDEN_ARGV_CHARS)
        for part in argv
    )


def validate_registry(payload: object) -> dict[str, Any]:
    """Return the registry when it has the shipped shape, else raise."""
    if not isinstance(payload, dict):
        raise OwnerRegistryError("owner registry root must be an object")
    if payload.get("schema_version") != 1:
        raise OwnerRegistryError("owner registry schema_version must be 1")
    containers = payload.get("managed_container_suffixes")
    entries = payload.get("entries")
    if (
        not isinstance(containers, list)
        or not containers
        or not all(isinstance(item, str) and item.strip() for item in containers)
    ):
        raise OwnerRegistryError("managed_container_suffixes must be a non-empty list")
    if not isinstance(entries, list) or not entries:
        raise OwnerRegistryError("owner registry entries must be a non-empty list")
    seen: set[str] = set()
    for entry in entries:
        if not isinstance(entry, dict):
            raise OwnerRegistryError("each owner registry entry must be an object")
        identifier = entry.get("id")
        owner = entry.get("owner")
        suffixes = entry.get("path_suffixes")
        platforms = entry.get("platforms")
        if not isinstance(identifier, str) or not identifier or identifier in seen:
            raise OwnerRegistryError("each owner registry entry needs a unique id")
        seen.add(identifier)
        if not isinstance(owner, str) or not owner.strip():
            raise OwnerRegistryError(f"{identifier} needs an owner")
        if (
            not isinstance(suffixes, list)
            or not suffixes
            or not all(isinstance(item, str) and item.strip() for item in suffixes)
        ):
            raise OwnerRegistryError(f"{identifier} needs path_suffixes")
        if (
            not isinstance(platforms, list)
            or not platforms
            or not set(platforms) <= PLATFORMS
        ):
            raise OwnerRegistryError(f"{identifier} has a bad platform list")
        tool = entry.get("tool")
        if tool is not None and (not isinstance(tool, str) or not tool.strip()):
            raise OwnerRegistryError(f"{identifier} tool must be a name or null")
        for key in ("read_only_argvs", "destructive_argvs"):
            commands = entry.get(key)
            if not isinstance(commands, list) or not all(
                _argv_ok(argv) for argv in commands
            ):
                raise OwnerRegistryError(f"{identifier} {key} must be argv lists")
            if commands and not tool:
                raise OwnerRegistryError(
                    f"{identifier} names commands but no owning tool"
                )
    return payload


def load_registry(path: Path | None = None) -> dict[str, Any]:
    source = REGISTRY_PATH if path is None else path
    try:
        payload = json.loads(source.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise OwnerRegistryError(f"owner registry is unreadable: {exc}") from exc
    return validate_registry(payload)


def render_argvs(argvs: list[list[str]]) -> str:
    """Display form of registry argv. Execution never parses this string."""
    return " && ".join(shlex.join(argv) for argv in argvs)


def suffix_holds(relative: str, suffix: str) -> bool:
    """True when ``relative`` is the suffix or a path under it, as whole segments."""
    rel = _fold(relative)
    suf = _fold(suffix)
    if not rel or not suf:
        return False
    padded = f"/{rel}/"
    needle = f"/{suf}/"
    return needle in padded


def match_entry(
    relative: str, platform: str, registry: dict[str, Any]
) -> dict[str, Any] | None:
    """The longest-suffix entry for this platform, or None. A hint, not proof."""
    ranked: list[tuple[int, dict[str, Any]]] = []
    for entry in registry["entries"]:
        if platform not in entry["platforms"]:
            continue
        held = [
            len(_fold(suffix))
            for suffix in entry["path_suffixes"]
            if suffix_holds(relative, suffix)
        ]
        if held:
            ranked.append((max(held), entry))
    if not ranked:
        return None
    ranked.sort(key=lambda item: item[0], reverse=True)
    return ranked[0][1]


def is_container_child(relative: str, containers: list[str]) -> bool:
    """True when ``relative`` is exactly one segment under a known state container."""
    rel = _fold(relative)
    parent, sep, name = rel.rpartition("/")
    if not sep or not name or not parent:
        return False
    parent_parts = parent.split("/")
    for container in containers:
        con_parts = _fold(container).split("/")
        if not con_parts:
            continue
        if parent_parts[-len(con_parts) :] == con_parts:
            return True
    return False


def leads_to_container(relative: str, containers: list[str]) -> bool:
    """True when listing this directory can reach a managed-state container."""
    rel = _fold(relative)
    rel_parts = rel.split("/") if rel else []
    for container in containers:
        con = _fold(container)
        con_parts = con.split("/")
        if rel == con or con.startswith(rel + "/"):
            return True
        if len(rel_parts) < len(con_parts):
            for size in range(1, len(con_parts)):
                if rel_parts[-size:] == con_parts[:size]:
                    return True
        if rel.endswith("/" + con):
            return True
    return False


def tool_present(tool: str) -> bool:
    return shutil.which(tool) is not None


def run_argv(argv: list[str], *, timeout: float = 20) -> dict[str, Any]:
    """Run one registry argv with no shell. A non-zero exit is data, not a delete."""
    if not _argv_ok(argv):
        raise OwnerRegistryError("refusing to run an argv that is not a static list")
    try:
        completed = subprocess.run(
            list(argv),
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return {
            "argv": list(argv),
            "exit_code": None,
            "stdout": "",
            "stderr": "timeout",
        }
    except OSError as exc:
        return {
            "argv": list(argv),
            "exit_code": None,
            "stdout": "",
            "stderr": str(exc),
        }
    return {
        "argv": list(argv),
        "exit_code": completed.returncode,
        "stdout": completed.stdout[-4000:],
        "stderr": completed.stderr[-4000:],
    }


def _blank_row(path: str) -> dict[str, Any]:
    return {
        "path": path,
        "status": "coverage-gap",
        "owner": None,
        "registry_id": None,
        "authorization": False,
        "removable_by_engine": False,
        "tool": None,
        "tool_present": None,
        "offered_commands": [],
        "read_only_results": [],
        "gated_destructive_command": None,
        "operator_action": None,
        "note": None,
    }


def classify_path(
    relative: str,
    registry: dict[str, Any],
    platform: str,
    *,
    which: Which | None = None,
    runner: Runner | None = None,
    command_cache: dict[tuple[str, tuple[str, ...]], dict[str, Any]] | None = None,
) -> dict[str, Any] | None:
    """One managed-lane row, or None when the path is outside the lane."""
    lookup = tool_present if which is None else lambda name: which(name) is not None
    run = run_argv if runner is None else runner
    entry = match_entry(relative, platform, registry)
    if entry is None:
        if not is_container_child(relative, registry["managed_container_suffixes"]):
            return None
        row = _blank_row(relative)
        row["note"] = (
            "managed-looking path with no registry match; unknown stays unknown"
        )
        return row
    row = _blank_row(relative)
    row["owner"] = entry["owner"]
    row["registry_id"] = entry["id"]
    row["note"] = entry.get("note")
    tool = entry.get("tool")
    row["tool"] = tool
    if tool and not lookup(tool):
        row["status"] = "absent-tool"
        row["tool_present"] = False
        row["operator_action"] = None
        row["note"] = f"owning tool {tool} is not on PATH; no command is offered"
        return row
    row["tool_present"] = True if tool else None
    read_only = list(entry.get("read_only_argvs") or [])
    destructive = list(entry.get("destructive_argvs") or [])
    if tool and read_only:
        row["status"] = "owner"
        row["offered_commands"] = [render_argvs([argv]) for argv in read_only]
        results: list[dict[str, Any]] = []
        for argv in read_only:
            key = (str(entry["id"]), tuple(argv))
            if command_cache is not None and key in command_cache:
                results.append(command_cache[key])
                continue
            result = run(list(argv))
            if command_cache is not None:
                command_cache[key] = result
            results.append(result)
        row["read_only_results"] = results
    else:
        row["status"] = "no-cli"
        row["operator_action"] = entry.get("operator_action")
    if tool and destructive:
        row["gated_destructive_command"] = render_argvs(destructive)
        if row["status"] == "no-cli":
            row["status"] = "owner"
    return row


def _directory_names(directory: Path) -> list[str]:
    with os.scandir(directory) as iterator:
        return sorted((entry.name for entry in iterator), key=str.casefold)


def probe_container_children(
    target: Path, known_paths: set[str], containers: list[str]
) -> list[str]:
    """One bounded level at a time along known product-state containers only."""
    found: list[str] = []
    seen = set(known_paths)
    frontier = sorted(
        path for path in known_paths if leads_to_container(path, containers)
    )
    for _round in range(6):
        if not frontier:
            break
        nxt: list[str] = []
        for relative in frontier:
            directory = target.joinpath(*Path(relative).parts)
            try:
                listing = _directory_names(directory)
            except OSError:
                continue
            for name in listing:
                child = f"{relative}/{name}"
                if child in seen:
                    continue
                keep = leads_to_container(child, containers) or is_container_child(
                    child, containers
                )
                if not keep:
                    continue
                seen.add(child)
                found.append(child)
                if leads_to_container(child, containers):
                    nxt.append(child)
        frontier = nxt
    return found


def build_report(
    snapshot: dict[str, Any],
    target: Path,
    *,
    platform: str,
    registry: dict[str, Any] | None = None,
    which: Which | None = None,
    runner: Runner | None = None,
) -> dict[str, Any]:
    """Classify snapshot paths and one bounded probe under known containers."""
    book = load_registry() if registry is None else registry
    containers = list(book["managed_container_suffixes"])
    paths = [
        entry["path"]
        for entry in snapshot.get("entries", [])
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    ]
    known = set(paths)
    if target.is_dir():
        paths.extend(probe_container_children(target, known, containers))
    rows: list[dict[str, Any]] = []
    command_cache: dict[tuple[str, tuple[str, ...]], dict[str, Any]] = {}
    for relative in sorted(set(paths), key=str.casefold):
        row = classify_path(
            relative,
            book,
            platform,
            which=which,
            runner=runner,
            command_cache=command_cache,
        )
        if row is not None:
            rows.append(row)
    return {
        "schema_version": 1,
        "lane": "managed",
        "authorization": False,
        "platform": platform,
        "registry": REGISTRY_PATH.name,
        "rows": rows,
    }

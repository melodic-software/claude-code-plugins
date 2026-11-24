#!/usr/bin/env python3
"""The trust and cost settings of the merge gate, read from the operator's own settings.

Each setting names something the gate trusts or treats as free: the owners an
agent may merge for unattended, the reusable review workflows and the review
checks that count as AI review, the record whose rows clear a cost hold, the
runner labels that cost nothing, the actions that start a model leg, and the
App whose Work status values count like a person's. They come only from the
source-control `userConfig` in user or managed settings, read the way
docs/contracts/hook-config-delivery channel F reads them and as
lib/plugin-options.mjs does: `pluginConfigs["<name>@<marketplace>"].options` in
the fixed-path managed settings files and in the user `settings.json` located
from this file's own install path. Nothing here reads the environment or a file
in a checkout, so no pull request and no repository `env` block can widen a
value; an install outside the plugin cache (a checkout run by path) sees only
managed settings, matched by manifest name.

Every setting fails closed. Unset, or a source that cannot be read, gives no
owner, no review workflow, no review check, no decision record, no free runner
beyond GitHub's standard labels, no model-leg action beyond the built-in ones,
and no trusted App. A value with an entry of the wrong shape drops that whole
setting, with a note on stderr.

    babysit_merge_settings.py show   # print the resolved settings as JSON
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

MANAGED_DIRS = {
    "darwin": "/Library/Application Support/ClaudeCode",
    "linux": "/etc/claude-code",
    "win32": "C:\\Program Files\\ClaudeCode",
}

LANE_IDS = ("claude-review", "claude-security-review")
WORKFLOW_LANES = ("code-review", "security-review", "either")

KEYS = (
    "unattended_merge_owners",
    "review_lane_workflows",
    "review_lane_checks",
    "owner_decisions_record",
    "free_runner_labels",
    "model_leg_actions",
    "issue_status_app_login",
)
LIST_KEYS = frozenset(KEYS) - {"owner_decisions_record", "issue_status_app_login"}

_OWNER = re.compile(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})")
_WORKFLOW = re.compile(
    r"(code-review|security-review|either)="
    r"([A-Za-z0-9-]+/[A-Za-z0-9._-]+/\.github/workflows/[A-Za-z0-9._-]+\.ya?ml)"
)
_CHECK = re.compile(
    r"(claude-review|claude-security-review):(caller|status|merge)=(.+)"
)
_CALLER = re.compile(r"\.github/workflows/[A-Za-z0-9._-]+\.ya?ml")
_CHECK_NAME = re.compile(r"[^\x00-\x1f\x7f]{1,200}")
_RECORD = re.compile(
    r"([A-Za-z0-9-]+)/([A-Za-z0-9._-]+)/((?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+)"
)
_LABEL_GLOB = re.compile(r"[A-Za-z0-9._*-]{1,100}")
_ACTION = re.compile(r"[A-Za-z0-9._/-]{1,100}")
_APP_LOGIN = re.compile(r"[a-z0-9][a-z0-9-]*\[bot\]")


class OptionsError(Exception):
    """A settings source that could hold a value cannot be read."""


@dataclass(frozen=True)
class Install:
    plugin_id: str | None
    name: str | None
    user_settings: Path | None


@dataclass(frozen=True)
class Settings:
    unattended_merge_owners: tuple[str, ...] = ()
    review_lane_workflows: tuple[tuple[str, str], ...] = ()
    review_lane_checks: dict[str, tuple[str, tuple[str, ...], tuple[str, ...]]] = field(
        default_factory=lambda: {lane: ("", (), ()) for lane in LANE_IDS}
    )
    owner_decisions_record: str = ""
    free_runner_labels: tuple[str, ...] = ()
    model_leg_actions: tuple[str, ...] = ()
    issue_status_app_login: str = ""
    notes: tuple[str, ...] = ()


def managed_settings_files(
    platform: str = sys.platform, root: Path | None = None
) -> list[Path]:
    """The managed settings files in merge order: managed-settings.json, then each
    non-hidden *.json drop-in in managed-settings.d/ by name. [] on a platform with
    no documented path. `root` replaces the platform's directory: tests only."""
    base = MANAGED_DIRS.get("linux" if platform.startswith("linux") else platform)
    if root is None and not base:
        return []
    root = root if root is not None else Path(base)
    dropin = root / "managed-settings.d"
    try:
        names = os.listdir(dropin)
    except (FileNotFoundError, NotADirectoryError):
        names = []
    except OSError as exc:
        raise OptionsError(
            f"managed settings directory {dropin} cannot be read ({exc})"
        ) from exc
    dropins = sorted(n for n in names if n.endswith(".json") and not n.startswith("."))
    return [root / "managed-settings.json", *(dropin / n for n in dropins)]


def resolve_install(plugin_root: Path) -> Install:
    """This install's identity and, when it sits in the plugin cache, its user settings file."""
    parts = plugin_root.as_posix().split("/")
    at = len(parts) - 1 - parts[::-1].index("cache") if "cache" in parts else -1
    if (
        at > 0
        and parts[at - 1] == "plugins"
        and len(parts) - at == 4
        and all(parts[at + 1 :])
    ):
        marketplace, name = parts[at + 1], parts[at + 2]
        config_root = "/".join(parts[: at - 1]) or "/"
        return Install(
            f"{name}@{marketplace}", name, Path(config_root, "settings.json")
        )
    try:
        name = json.loads(
            (plugin_root / ".claude-plugin/plugin.json").read_text(encoding="utf-8")
        )["name"]
    except (OSError, ValueError, KeyError, TypeError):
        name = None
    return Install(None, name if isinstance(name, str) and name else None, None)


def _options_in(path: Path, install: Install) -> list[dict[str, Any]]:
    try:
        if not path.is_file():
            if path.exists():
                raise OptionsError(f"settings file {path} is not a regular file")
            return []
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        raise OptionsError(f"settings file {path} cannot be read ({exc})") from exc
    try:
        settings = json.loads(text)
    except ValueError as exc:
        raise OptionsError(f"settings file {path} is not valid JSON ({exc})") from exc
    if not isinstance(settings, dict):
        raise OptionsError(f"settings file {path} is not a JSON object")
    if "pluginConfigs" not in settings or (
        install.plugin_id is None and install.name is None
    ):
        return []
    configs = settings["pluginConfigs"]
    if not isinstance(configs, dict):
        raise OptionsError(f"pluginConfigs in {path} is not an object")

    def matches(key: str) -> bool:
        if install.plugin_id is not None:
            return key == install.plugin_id
        return key == install.name or key.startswith(f"{install.name}@")

    found = []
    for key in sorted(k for k in configs if matches(k)):
        entry = configs[key]
        if not isinstance(entry, dict):
            raise OptionsError(f'pluginConfigs["{key}"] in {path} is not an object')
        if "options" not in entry:
            continue
        if not isinstance(entry["options"], dict):
            raise OptionsError(
                f'pluginConfigs["{key}"].options in {path} is not an object'
            )
        found.append(entry["options"])
    return found


def read_operator_options(
    install: Install, managed: list[Path], keys=KEYS
) -> dict[str, Any]:
    """Each of `keys` a source sets: a string, or a list of strings for a list key.
    Managed settings win over user settings, a later managed file over an earlier one."""
    user: dict[str, Any] = {}
    chosen: dict[str, Any] = {}

    def take(path: Path, into: dict[str, Any]) -> None:
        for options in _options_in(path, install):
            for key in keys:
                if key not in options:
                    continue
                value = options[key]
                ok = isinstance(value, str) or (
                    key in LIST_KEYS
                    and isinstance(value, list)
                    and all(isinstance(v, str) for v in value)
                )
                if not ok:
                    raise OptionsError(
                        f"{key} in {path} is not a string or a list of strings"
                    )
                into[key] = value

    if install.user_settings is not None:
        take(install.user_settings, user)
    for path in managed:
        take(path, chosen)
    return {**user, **chosen}


def _entries(value: Any) -> list[str]:
    items = value if isinstance(value, list) else str(value).splitlines()
    return [item.strip() for item in items if item.strip()]


def parse(raw: dict[str, Any], notes: list[str] | None = None) -> Settings:
    """Settings from raw option values; a key with any malformed entry is dropped whole."""
    notes = [] if notes is None else notes
    out: dict[str, Any] = {}

    def bad(key: str, entry: str) -> None:
        notes.append(
            f"{key}: {entry!r} is not a valid entry, so the setting is ignored"
        )

    if "unattended_merge_owners" in raw:
        owners = _entries(raw["unattended_merge_owners"])
        if all(_OWNER.fullmatch(o) for o in owners):
            out["unattended_merge_owners"] = tuple(dict.fromkeys(owners))
        else:
            bad(
                "unattended_merge_owners",
                next(o for o in owners if not _OWNER.fullmatch(o)),
            )
    if "review_lane_workflows" in raw:
        pairs = []
        for entry in _entries(raw["review_lane_workflows"]):
            m = _WORKFLOW.fullmatch(entry)
            if not m:
                bad("review_lane_workflows", entry)
                break
            pairs.append((m[1], m[2]))
        else:
            out["review_lane_workflows"] = tuple(dict.fromkeys(pairs))
    if "review_lane_checks" in raw:
        callers: dict[str, str] = {}
        names: dict[tuple[str, str], list[str]] = {}
        for entry in _entries(raw["review_lane_checks"]):
            m = _CHECK.fullmatch(entry)
            value = m[3].strip() if m else ""
            if (
                not m
                or (
                    m[2] == "caller"
                    and (not _CALLER.fullmatch(value) or m[1] in callers)
                )
                or (m[2] != "caller" and not _CHECK_NAME.fullmatch(value))
            ):
                bad("review_lane_checks", entry)
                break
            if m[2] == "caller":
                callers[m[1]] = value
            else:
                names.setdefault((m[1], m[2]), []).append(value)
        else:
            out["review_lane_checks"] = {
                lane: (
                    callers.get(lane, ""),
                    tuple(dict.fromkeys(names.get((lane, "status"), []))),
                    tuple(dict.fromkeys(names.get((lane, "merge"), []))),
                )
                for lane in LANE_IDS
            }
    if "owner_decisions_record" in raw:
        record = str(raw["owner_decisions_record"]).strip()
        if _RECORD.fullmatch(record):
            out["owner_decisions_record"] = record
        elif record:
            bad("owner_decisions_record", record)
    if "free_runner_labels" in raw:
        labels = _entries(raw["free_runner_labels"])
        if all(_LABEL_GLOB.fullmatch(g) and g.strip("*") for g in labels):
            out["free_runner_labels"] = tuple(dict.fromkeys(labels))
        else:
            bad(
                "free_runner_labels",
                next(
                    g for g in labels if not (_LABEL_GLOB.fullmatch(g) and g.strip("*"))
                ),
            )
    if "model_leg_actions" in raw:
        actions = _entries(raw["model_leg_actions"])
        if all(_ACTION.fullmatch(a) for a in actions):
            out["model_leg_actions"] = tuple(dict.fromkeys(actions))
        else:
            bad(
                "model_leg_actions",
                next(a for a in actions if not _ACTION.fullmatch(a)),
            )
    if "issue_status_app_login" in raw:
        login = str(raw["issue_status_app_login"]).strip()
        if _APP_LOGIN.fullmatch(login):
            out["issue_status_app_login"] = login
        elif login:
            bad("issue_status_app_login", login)
    return Settings(**out, notes=tuple(notes))


_OVERRIDE: Settings | None = None
_CACHED: Settings | None = None


def set_override(settings: Settings | None) -> None:
    """Replace the resolved settings for this process: tests only."""
    global _OVERRIDE
    _OVERRIDE = settings


def load(plugin_root: Path | None = None) -> Settings:
    """The resolved settings, read once per process; unset when a source cannot be read.
    With `plugin_root`, a fresh read of that install's sources."""
    global _CACHED
    if _OVERRIDE is not None and plugin_root is None:
        return _OVERRIDE
    if _CACHED is None or plugin_root is not None:
        notes: list[str] = []
        root = plugin_root or Path(__file__).resolve().parents[3]
        try:
            raw = read_operator_options(resolve_install(root), managed_settings_files())
        except OptionsError as exc:
            notes.append(f"{exc}; every trust and cost setting reads unset")
            raw = {}
        settings = parse(raw, notes)
        for note in settings.notes:
            print(f"babysit_merge_settings: {note}", file=sys.stderr)
        if plugin_root is not None:
            return settings
        _CACHED = settings
    return _CACHED


def glob_regex(globs: tuple[str, ...], star: str) -> str:
    """One alternation of `globs`, each `*` replaced by `star` and the rest escaped."""
    return "|".join(star.join(re.escape(part) for part in g.split("*")) for g in globs)


def decision_row_pattern(record: str) -> re.Pattern[str]:
    """A line link to a row of `record` (owner/repo/path) at main or a commit, or
    a pattern that matches nothing when no record is set."""
    m = _RECORD.fullmatch(record)
    if not m:
        return re.compile(r"(?!)")
    owner, repo, path = (re.escape(p) for p in m.groups())
    return re.compile(
        rf"https://github\.com/{owner}/{repo}/blob/(?:main|[0-9a-f]{{40}})"
        rf"/{path}(?:\?plain=1)?#L[1-9][0-9]*(?:-L[1-9][0-9]*)?"
    )


def as_json(settings: Settings) -> dict[str, Any]:
    return {
        "unattended_merge_owners": list(settings.unattended_merge_owners),
        "review_lane_workflows": [
            {"lane": lane, "workflow": path}
            for lane, path in settings.review_lane_workflows
        ],
        "review_lane_checks": {
            lane: {"caller": caller, "status": list(status), "merge": list(merge)}
            for lane, (caller, status, merge) in settings.review_lane_checks.items()
        },
        "owner_decisions_record": settings.owner_decisions_record,
        "free_runner_labels": list(settings.free_runner_labels),
        "model_leg_actions": list(settings.model_leg_actions),
        "issue_status_app_login": settings.issue_status_app_login,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(
        prog="babysit_merge_settings.py",
        description="Print the resolved trust and cost settings as JSON.",
        allow_abbrev=False,
    )
    parser.add_argument("action", choices=["show"])
    parser.parse_args(argv)
    print(json.dumps(as_json(load())))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))

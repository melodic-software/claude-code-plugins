"""Cached baseline policy, ADR 0075 standing cascade, and overlay validation.

Shared by ``hygiene.py`` and ``policy_migration.py`` so policy migration never
imports the deletion engine and validation loops never re-read
``baseline-policy.json`` from disk.
"""

from __future__ import annotations

import fnmatch
import functools
import json
import os
import re
from collections.abc import Callable, Iterable
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import engine_grammar
import yaml_subset

SCHEMA_VERSION = 1
OVERLAY_VERSIONS = (1, 2)
RULE_MIN_AGE_BASES = ("mtime", "atime", "ctime")
ELEVATION_VALUES = ("never", "uac-prompt")
POLICY_FILE_NAME = "disk-hygiene.json"
TEAM_POLICY_NAME = "disk-hygiene.yaml"
PERSONAL_POLICY_NAME = "disk-hygiene.local.yaml"
POLICY_FILE_OPTION = "policy_file"
POLICY_SETUP_COMMAND = "/disk-hygiene:setup apply"
DEFAULT_CONVENTION_HOME = ("docs", "conventions")
CONVENTION_HOME_MARKERS = (
    "<!-- BEGIN GENERATED: convention-home -->",
    "<!-- END GENERATED: convention-home -->",
)
CONVENTION_HOME_SEGMENT = re.compile(r"[A-Za-z0-9._-]+")
TIERS = engine_grammar.TIERS
HINT_ENTRY_TYPES = ("file", "directory", "link", "other")
HINT_CLASSES = ("superseded-version", "backup", "empty", "temp", "crash-dump")

PLUGIN_ROOT = Path(__file__).resolve().parents[1]
BASELINE_POLICY = (
    PLUGIN_ROOT / "skills" / "clean" / "reference" / "baseline-policy.json"
)

_ABSOLUTE_GLOB = re.compile(r"^(?:[A-Za-z]:[\\/]|/|\\\\)")


class PolicyError(Exception):
    """Raised on unreadable or invalid policy/baseline data."""


@dataclass(frozen=True)
class BaselineSnapshot:
    """Immutable cached representation of ``baseline-policy.json``."""

    version: int
    protected_exact_names: frozenset[str]
    protected_exact_names_casefolded: frozenset[str]
    protected_exact_names_ordered: tuple[str, ...]
    protected_name_globs: tuple[str, ...]
    disk_image_name_globs: tuple[str, ...]
    os_temp_recommendation_threshold_bytes: int
    hints_json: str


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PolicyError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PolicyError(f"JSON root must be an object: {path}")
    return value


def load_overlay(path: Path) -> dict[str, Any]:
    if path.suffix.casefold() not in (".yaml", ".yml"):
        return load_json(path)
    try:
        value = yaml_subset.load(str(path))
    except (OSError, UnicodeError, yaml_subset.YamlSubsetError) as exc:
        raise PolicyError(f"cannot read YAML {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PolicyError(f"YAML root must be a mapping: {path}")
    return value


def glob_matches(subject: str, pattern: str) -> bool:
    """Case-insensitive glob match, identical across all platforms."""
    return fnmatch.fnmatchcase(subject.casefold(), pattern.casefold())


def protection_glob_pattern(entry: Any) -> str | None:
    if isinstance(entry, str) and entry:
        return entry
    if isinstance(entry, dict):
        pattern = entry.get("glob")
        if isinstance(pattern, str) and pattern:
            return pattern
    return None


def protection_glob_entry(entry: Any) -> dict[str, str] | None:
    pattern = protection_glob_pattern(entry)
    if pattern is None:
        return None
    reason = entry.get("reason") if isinstance(entry, dict) else None
    if isinstance(reason, str) and reason:
        return {"glob": pattern, "reason": reason}
    return {"glob": pattern}


def merge_protection_matches(
    matches: Iterable[dict[str, str]],
) -> list[dict[str, str]]:
    unique = {(match["glob"], match.get("reason", "")): match for match in matches}
    return [unique[key] for key in sorted(unique)]


def protection_matches_field(
    matches: Iterable[dict[str, str]],
) -> dict[str, list[dict[str, str]]]:
    merged = merge_protection_matches(matches)
    return {"protection_matches": merged} if merged else {}


def protection_glob_is_absolute(pattern: str) -> bool:
    return bool(_ABSOLUTE_GLOB.match(pattern))


def consumer_protection_matches(
    path: Path, target: Path, globs: Iterable[Any]
) -> list[dict[str, str]]:
    try:
        relative = path.relative_to(target).as_posix()
    except ValueError:
        relative = path.as_posix()
    absolute = path.as_posix()
    absolute_subjects = (absolute, absolute.replace("\\", "/"))
    matches: list[dict[str, str]] = []
    for entry in globs:
        match = protection_glob_entry(entry)
        if match is None:
            continue
        pattern = match["glob"]
        if protection_glob_is_absolute(pattern):
            patterns = (pattern, pattern.replace("\\", "/"))
            covered = any(
                glob_matches(subject, candidate)
                for subject in absolute_subjects
                for candidate in patterns
            )
        else:
            covered = glob_matches(relative, pattern)
        if covered:
            matches.append(match)
    return merge_protection_matches(matches)


def _validate_protection_glob_entry(entry: Any) -> None:
    if protection_glob_pattern(entry) is None:
        raise PolicyError(
            "protection globs must be non-empty strings or {glob, reason} objects"
        )
    if not isinstance(entry, dict):
        return
    if not set(entry) <= {"glob", "reason"}:
        raise PolicyError("protection glob objects may only carry glob and reason")
    if "reason" in entry and not (isinstance(entry["reason"], str) and entry["reason"]):
        raise PolicyError("protection glob reason must be a non-empty string")


@functools.lru_cache(maxsize=4)
def load_baseline_snapshot(baseline_path: Path = BASELINE_POLICY) -> BaselineSnapshot:
    """Load, validate, and cache an immutable ``BaselineSnapshot``."""
    baseline = load_json(baseline_path)
    if baseline.get("version") != SCHEMA_VERSION:
        raise PolicyError("unsupported baseline policy version")
    threshold = baseline.get("os_temp_recommendation_threshold_bytes")
    if isinstance(threshold, bool) or not isinstance(threshold, int) or threshold < 1:
        raise PolicyError(
            "baseline os_temp_recommendation_threshold_bytes must be a positive integer"
        )
    exact_ordered = tuple(baseline.get("protected_exact_names", []))
    return BaselineSnapshot(
        version=SCHEMA_VERSION,
        protected_exact_names=frozenset(exact_ordered),
        protected_exact_names_casefolded=frozenset(
            name.casefold() for name in exact_ordered
        ),
        protected_exact_names_ordered=exact_ordered,
        protected_name_globs=tuple(baseline.get("protected_name_globs", [])),
        disk_image_name_globs=tuple(baseline.get("disk_image_name_globs", [])),
        os_temp_recommendation_threshold_bytes=threshold,
        hints_json=json.dumps(baseline.get("hints", [])),
    )


def baseline_policy(baseline_path: Path = BASELINE_POLICY) -> dict[str, Any]:
    """Return a fresh mutable baseline policy dict backed by the cached snapshot."""
    snap = load_baseline_snapshot(baseline_path)
    return {
        "version": snap.version,
        "protected_exact_names": list(snap.protected_exact_names_ordered),
        "protected_name_globs": list(snap.protected_name_globs),
        "disk_image_name_globs": list(snap.disk_image_name_globs),
        "os_temp_recommendation_threshold_bytes": (
            snap.os_temp_recommendation_threshold_bytes
        ),
        "hints": json.loads(snap.hints_json),
        "additional_protected_path_globs": [],
        "hint_sources": {},
        "rules": [],
        "elevation": "never",
        "policy_sources": ["baseline"],
        "policy_warnings": [],
    }


def baseline_protected_names(baseline_path: Path = BASELINE_POLICY) -> frozenset[str]:
    return load_baseline_snapshot(baseline_path).protected_exact_names


def baseline_protected_names_casefolded(
    baseline_path: Path = BASELINE_POLICY,
) -> frozenset[str]:
    return load_baseline_snapshot(baseline_path).protected_exact_names_casefolded


def baseline_protected_name_globs(
    baseline_path: Path = BASELINE_POLICY,
) -> tuple[str, ...]:
    return load_baseline_snapshot(baseline_path).protected_name_globs


def baseline_disk_image_name_globs(
    baseline_path: Path = BASELINE_POLICY,
) -> tuple[str, ...]:
    return load_baseline_snapshot(baseline_path).disk_image_name_globs


def snapshot_protected_exact_names(
    snapshot: dict[str, Any], *, baseline_path: Path = BASELINE_POLICY
) -> frozenset[str]:
    """Union of cached baseline exact names and snapshot policy exact names."""
    snap_names = snapshot.get("policy", {}).get("protected_exact_names", [])
    extra = frozenset(name for name in snap_names if isinstance(name, str))
    return baseline_protected_names(baseline_path) | extra


def is_virtual_disk_name(
    name: str, *, baseline_path: Path = BASELINE_POLICY
) -> bool:
    return any(
        glob_matches(name, glob) for glob in baseline_disk_image_name_globs(baseline_path)
    )


def _pointer_token(text: str) -> str | None:
    begin, end = CONVENTION_HOME_MARKERS
    token = None
    in_region = False
    for line in text.splitlines():
        marker = line.strip()
        if marker == begin:
            in_region = True
        elif marker == end and in_region:
            return token or ""
        elif in_region and token is None:
            match = re.search(r"`([^`]*)`", line)
            if match:
                token = match.group(1)
    return None


def convention_home(project_dir: Path) -> Path:
    for name in ("AGENTS.md", "CLAUDE.md"):
        try:
            text = (project_dir / name).read_text(encoding="utf-8-sig")
        except (OSError, UnicodeError):
            continue
        token = _pointer_token(text)
        if token is None:
            continue
        segments = token.rstrip("/").split("/")
        if token and all(
            CONVENTION_HOME_SEGMENT.fullmatch(segment)
            and segment not in (".", "..")
            and segment.rstrip(".").casefold() != ".git"
            for segment in segments
        ):
            return project_dir.joinpath(*segments)
        break
    return project_dir.joinpath(*DEFAULT_CONVENTION_HOME)


def user_policy_path(raw: str | None, warnings: list[str]) -> Path | None:
    value = (raw or "").strip()
    if not value or value.startswith("${user_config."):
        return None
    path = Path(value).expanduser()
    if not path.is_absolute():
        warnings.append(
            f"the {POLICY_FILE_OPTION} option {value!r} is not an absolute path, "
            "so it supplies no layer"
        )
        return None
    if not path.is_file():
        warnings.append(
            f"the {POLICY_FILE_OPTION} option names {path}, which is not a file, "
            "so it supplies no layer"
        )
    return path


def same_file(first: Path, second: Path) -> bool:
    try:
        return os.path.samefile(first, second)
    except OSError:
        return False


def _dual_read(
    layer: str, new: Path | None, old: Path, destination: str, warnings: list[str]
) -> list[Path]:
    has_new = new is not None and new.is_file()
    has_old = old.is_file() and not (
        has_new and new is not None and same_file(old, new)
    )
    if has_new and has_old:
        warnings.append(
            f"{old} is the old {layer} policy and is not read because {new} "
            f"supplies that layer; move any setting it still holds to {new} and "
            f"delete it ({POLICY_SETUP_COMMAND})"
        )
    if has_new and new is not None:
        return [new]
    if has_old:
        warnings.append(
            f"{old} is the old {layer} policy, still read as that layer; move it "
            f"to {destination} ({POLICY_SETUP_COMMAND})"
        )
        return [old]
    return []


def old_policy_paths(
    project_dir: Path | None, *, home: Path | None = None
) -> dict[str, Path]:
    resolved_home = Path.home() if home is None else home
    paths = {"userConfig": resolved_home / ".claude" / POLICY_FILE_NAME}
    if project_dir is not None:
        paths["team"] = project_dir / ".claude" / POLICY_FILE_NAME
    return paths


def standing_policy_paths(
    project_dir: Path | None,
    user_policy: str | None = None,
    warnings: list[str] | None = None,
    *,
    home: Path | None = None,
) -> list[Path]:
    warnings = [] if warnings is None else warnings
    old = old_policy_paths(project_dir, home=home)
    user = user_policy_path(user_policy, warnings)
    layers = _dual_read(
        "userConfig",
        user,
        old["userConfig"],
        str(user)
        if user is not None
        else f"the file the {POLICY_FILE_OPTION} userConfig option names",
        warnings,
    )
    if project_dir is not None:
        conv_home = convention_home(project_dir)
        team = conv_home / TEAM_POLICY_NAME
        if same_file(old["team"], old["userConfig"]):
            layers.append(team)
        else:
            layers += _dual_read("team", team, old["team"], str(team), warnings)
        personal = conv_home / PERSONAL_POLICY_NAME
        if personal.is_file():
            layers.append(personal)
    unique: dict[Path, Path] = {}
    for path in layers:
        if path.is_file():
            unique.setdefault(path.resolve(), path)
    return list(unique.values())


def repository_policy_paths(project_dir: Path | None) -> set[Path]:
    if project_dir is None:
        return set()
    home = convention_home(project_dir)
    return {
        path.resolve()
        for path in (
            project_dir / ".claude" / POLICY_FILE_NAME,
            home / TEAM_POLICY_NAME,
            home / PERSONAL_POLICY_NAME,
        )
    }


def validate_hint(hint: Any) -> None:
    if not isinstance(hint, dict):
        raise PolicyError("each additional hint must be an object")
    required = {"id", "os", "kind", "pattern", "confidence_ceiling", "reason"}
    if not required <= set(hint) or set(hint) - required - {"entry_types", "class"}:
        raise PolicyError(
            "each additional hint must contain exactly id/os/kind/pattern/confidence_ceiling/reason "
            "and optionally entry_types and class"
        )
    if "class" in hint and hint["class"] not in HINT_CLASSES:
        raise PolicyError(f"hint class must be one of {', '.join(HINT_CLASSES)}")
    if "entry_types" in hint:
        entry_types = hint["entry_types"]
        if (
            not isinstance(entry_types, list)
            or not entry_types
            or not all(value in HINT_ENTRY_TYPES for value in entry_types)
        ):
            raise PolicyError(
                "hint entry_types must be a non-empty array containing file/directory/link/other"
            )
    if hint["kind"] not in {"name_glob", "path_glob"}:
        raise PolicyError(f"unsupported hint kind: {hint['kind']}")
    if hint["confidence_ceiling"] not in TIERS:
        raise PolicyError(
            f"unsupported confidence ceiling: {hint['confidence_ceiling']}"
        )
    if not isinstance(hint["os"], list) or not all(
        value in {"all", "windows", "linux", "macos"} for value in hint["os"]
    ):
        raise PolicyError(
            "hint os must be an array containing all/windows/linux/macos"
        )
    for field in ("id", "pattern", "reason"):
        if not isinstance(hint[field], str) or not hint[field]:
            raise PolicyError(f"hint {field} must be a non-empty string")


def validate_rules(
    rules: Any, hints: list[dict[str, Any]], overlay_path: Path
) -> list[dict[str, Any]]:
    hint_ids = {hint["id"] for hint in hints}
    if not isinstance(rules, list):
        raise PolicyError(f"rules must be an array: {overlay_path}")
    normalized = []
    for index, rule in enumerate(rules):
        if not isinstance(rule, dict):
            raise PolicyError(f"each rule must be an object: {overlay_path}")
        unknown = sorted(
            set(rule) - {"match", "preselect", "min_age_days", "min_age_basis"}
        )
        if unknown:
            raise PolicyError(
                f"unknown rule fields in {overlay_path}: {', '.join(unknown)}"
            )
        match = rule.get("match")
        if not isinstance(match, dict) or len(match) != 1:
            raise PolicyError(
                f"rule match must be an object with exactly one of hint_id, hint_ids or class: {overlay_path}"
            )
        match_class = match.get("class")
        if "class" in match:
            if match_class not in HINT_CLASSES:
                raise PolicyError(
                    f"rule match class must be one of {', '.join(HINT_CLASSES)}: {overlay_path}"
                )
            ids = [h["id"] for h in hints if h.get("class") == match_class]
            if not ids:
                raise PolicyError(
                    f"rule match class matches no hint ({overlay_path}): {match_class}"
                )
        elif "hint_id" in match:
            ids = [match["hint_id"]]
        elif (
            "hint_ids" in match
            and isinstance(match["hint_ids"], list)
            and match["hint_ids"]
        ):
            ids = match["hint_ids"]
        else:
            raise PolicyError(
                f"rule match must be a hint_id string, a non-empty hint_ids array or a class: {overlay_path}"
            )
        if not all(isinstance(value, str) and value for value in ids):
            raise PolicyError(
                f"rule hint IDs must be non-empty strings: {overlay_path}"
            )
        missing = sorted(set(ids) - hint_ids)
        if missing:
            raise PolicyError(
                f"rule names unknown hint ID ({overlay_path}): {', '.join(missing)}"
            )
        if not isinstance(rule.get("preselect"), bool):
            raise PolicyError(f"rule preselect must be a boolean: {overlay_path}")
        entry: dict[str, Any] = {
            "hint_ids": ids,
            "preselect": rule["preselect"],
            "source": str(overlay_path),
            "index": index,
        }
        if match_class is not None:
            entry["class"] = match_class
        if "min_age_days" in rule:
            days = rule["min_age_days"]
            if isinstance(days, bool) or not isinstance(days, int) or days < 0:
                raise PolicyError(
                    f"rule min_age_days must be a non-negative integer: {overlay_path}"
                )
            entry["min_age_days"] = days
        if "min_age_basis" in rule:
            if rule["min_age_basis"] not in RULE_MIN_AGE_BASES:
                raise PolicyError(
                    f"rule min_age_basis must be one of {', '.join(RULE_MIN_AGE_BASES)}: {overlay_path}"
                )
            entry["min_age_basis"] = rule["min_age_basis"]
        normalized.append(entry)
    return normalized


def apply_policy_overlay(
    result: dict[str, Any], overlay_path: Path, project_scope: bool = False
) -> None:
    """Layer one overlay onto ``result``; a failing layer changes nothing."""
    overlay = load_overlay(overlay_path)
    version = overlay.get("version")
    if isinstance(version, bool) or version not in OVERLAY_VERSIONS:
        raise PolicyError(f"policy version must be 1 or 2: {overlay_path}")
    allowed = {
        "version",
        "disabled_hint_ids",
        "additional_hints",
        "additional_protected_path_globs",
    }
    if version == 2:
        allowed.update({"rules", "elevation"})
    unknown = sorted(set(overlay) - allowed)
    if unknown:
        raise PolicyError(
            f"unknown policy fields in {overlay_path}: {', '.join(unknown)}"
        )
    disabled = overlay.get("disabled_hint_ids", [])
    additions = overlay.get("additional_hints", [])
    protections = overlay.get("additional_protected_path_globs", [])
    if not isinstance(disabled, list) or not isinstance(protections, list):
        raise PolicyError("disabled_hint_ids and protection globs must be arrays")
    if not all(isinstance(value, str) and value for value in disabled):
        raise PolicyError("policy IDs must be non-empty strings")
    for item in protections:
        _validate_protection_glob_entry(item)
    if not isinstance(additions, list):
        raise PolicyError("additional_hints must be an array")
    known_ids = {hint.get("id") for hint in result["hints"]}
    for hint in additions:
        validate_hint(hint)
        if hint["id"] in known_ids:
            raise PolicyError(
                f"additional hint ID already exists ({overlay_path}): {hint['id']}"
            )
        known_ids.add(hint["id"])
    disabled_set = set(disabled)
    merged_hints = [
        hint
        for hint in (*result["hints"], *additions)
        if hint["id"] not in disabled_set
    ]
    rules = validate_rules(overlay.get("rules", []), merged_hints, overlay_path)
    elevation = overlay.get("elevation", result["elevation"])
    if not isinstance(elevation, str) or elevation not in ELEVATION_VALUES:
        raise PolicyError(
            f"elevation must be one of {', '.join(ELEVATION_VALUES)}: {overlay_path}"
        )
    if project_scope and "elevation" in overlay and elevation != "never":
        raise PolicyError(
            "elevation can be opted into only from the userConfig policy file or "
            f"an explicit --policy, not a project policy: {overlay_path}"
        )
    result["hints"] = [
        hint for hint in result["hints"] if hint.get("id") not in disabled_set
    ]
    result["hints"].extend(additions)
    result["hint_sources"].update({hint["id"]: str(overlay_path) for hint in additions})
    result["additional_protected_path_globs"].extend(protections)
    result["rules"].extend(rules)
    result["elevation"] = elevation
    result["policy_sources"].append(str(overlay_path))


def load_policy(
    overlay_path: Path | None,
    project_dir: Path | None = None,
    user_policy: str | None = None,
    *,
    baseline_path: Path = BASELINE_POLICY,
    standing_paths_fn: Callable[
        [Path | None, str | None, list[str] | None], list[Path]
    ]
    | None = None,
) -> dict[str, Any]:
    result = baseline_policy(baseline_path)
    warnings: list[str] = []
    standing_fn = standing_policy_paths if standing_paths_fn is None else standing_paths_fn
    overlays = (
        [overlay_path]
        if overlay_path is not None
        else standing_fn(project_dir, user_policy, warnings)
    )
    repository = (
        repository_policy_paths(project_dir) if overlay_path is None else set()
    )
    for path in overlays:
        apply_policy_overlay(
            result, path, project_scope=path.resolve() in repository
        )
    result["policy_warnings"].extend(warnings)
    for rule in result["rules"]:
        if "class" in rule:
            rule["hint_ids"] = [
                hint["id"]
                for hint in result["hints"]
                if hint.get("class") == rule["class"]
            ]
            rule["hint_sources"] = {
                hint_id: result["hint_sources"].get(hint_id, "baseline")
                for hint_id in rule["hint_ids"]
            }
    return result

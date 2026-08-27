#!/usr/bin/env python3
"""Read-only inventory and fail-closed cleanup gate for disk-hygiene."""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import fnmatch
import functools
import hashlib
import json
import os
import platform
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from collections.abc import Iterable
from pathlib import Path, PurePosixPath
from typing import Any

MIN_PYTHON = (3, 11)
SCHEMA_VERSION = 1
MAX_SNAPSHOT_ENTRIES = 250_000
TIERS = {"high", "medium", "low"}
VCS_NAMES = {".git", ".hg", ".svn"}
GIT_METADATA_NAME = ".git"
VCS_EVIDENCE_GATE_NAMES = (
    "git-status-porcelain-empty",
    "all-local-heads-on-remote",
    "all-stashes-duplicated",
    "exact-path-operator-approval",
)
GITHUB_REMOTE_RE = re.compile(
    r"^(?:https?://|ssh://git@|git@)github\.com(?::|/)"
    r"(?P<owner>[A-Za-z0-9_.-]+)/(?P<repo>[A-Za-z0-9_.-]+)/?$",
    re.IGNORECASE,
)
FILE_ATTRIBUTE_REPARSE_POINT = 0x0400
FILE_ATTRIBUTE_HIDDEN = 0x2
FILE_ATTRIBUTE_SYSTEM = 0x4
# "The bytes are not here." Each of these marks a name whose content lives in a
# provider's cloud rather than on this disk, so its st_size is a REMOTE byte
# count while local occupancy is roughly zero — and deleting it propagates the
# delete to the cloud copy, which for an organisation's sync root is the only
# copy. FILE_ATTRIBUTE_OFFLINE is the long-standing HSM/remote-storage bit that
# iCloud and Dropbox eviction reuse; FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS is
# what the Windows Cloud Files API sets on a dehydrated placeholder.
#
# Measured against a OneDrive for Business sync root on Windows 11: a
# dehydrated placeholder reads 0x400020 through os.lstat — ARCHIVE plus
# RECALL_ON_DATA_ACCESS — with OFFLINE, SPARSE, and REPARSE_POINT all CLEAR.
# So RECALL_ON_DATA_ACCESS is the only member observed on a real placeholder,
# and a reparse-point test cannot stand in for this class (#1804). OFFLINE is
# carried for the eviction states it documents and must not be assumed to fire.
#
# FILE_ATTRIBUTE_RECALL_ON_OPEN is deliberately ABSENT. Its value, 0x00040000,
# is the same number as FILE_ATTRIBUTE_EA ("a file or directory with extended
# attributes"), and RECALL_ON_OPEN "only appears in directory enumeration
# classes" while every attribute read here comes from lstat
# (https://learn.microsoft.com/en-us/windows/win32/fileio/file-attribute-constants,
# fetched 2026-07-30). Read through lstat the bit therefore means EA, and
# including it protected ordinary local files: a sweep of two non-cloud trees on
# this host flagged .NET build output and temp .node files that are fully
# present on disk. Protecting build artifacts from cleanup would defeat the
# engine's purpose, so the ambiguous bit stays out.
FILE_ATTRIBUTE_OFFLINE = 0x00001000
FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS = 0x00400000
FILE_ATTRIBUTE_SPARSE_FILE = 0x00000200
CLOUD_PLACEHOLDER_ATTRIBUTES = (
    FILE_ATTRIBUTE_OFFLINE | FILE_ATTRIBUTE_RECALL_ON_DATA_ACCESS
)
FILE_FLAG_BACKUP_SEMANTICS = 0x02000000
FILE_ATTRIBUTE_NORMAL = 0x00000080
OPEN_EXISTING = 3
# st_blocks is documented in units of 512-byte blocks on every Unix Python
# cares about (POSIX, Linux, macOS). Multiplying here is the cheap allocated-
# size read; Windows lstat does not expose st_blocks, so allocated_size stays
# null there rather than paying for GetCompressedFileSizeW on every entry.
ST_BLOCKS_BYTES = 512
# Folders whose presence at a drive root identifies that drive as an OS/system
# drive. A user-provisioned non-OS volume (a Windows Dev Drive) carries none of
# them, so they are the discriminator for whole-volume-root classification.
WINDOWS_OS_DRIVE_MARKERS = {
    "Program Files",
    "Program Files (x86)",
    "ProgramData",
    "Recovery",
    "Windows",
}
# Per-volume filesystem metadata every Windows volume carries, OS drive or not.
# Protected from deletion on every drive, but never evidence a volume is the OS
# drive — a Dev Drive has a System Volume Information and $Recycle.Bin too.
WINDOWS_PER_VOLUME_METADATA = {
    "$Recycle.Bin",
    "System Volume Information",
}
WINDOWS_VOLUME_SYSTEM_NAMES = WINDOWS_OS_DRIVE_MARKERS | WINDOWS_PER_VOLUME_METADATA
# Well-known OS-provisioned volume-root directory names that are not always in
# WINDOWS_VOLUME_SYSTEM_NAMES / system_roots(), but are never the user-created
# residue root-children mode exists to reach. Prefer excluding when ambiguous
# (#2588).
WINDOWS_OS_ROOT_EXTRA_NAMES = {
    "Users",
    "PerfLogs",
    "inetpub",
    "XboxGames",
    "Windows.old",
}
PLUGIN_ROOT = Path(__file__).resolve().parents[3]
BASELINE_POLICY = (
    Path(__file__).resolve().parents[1] / "reference" / "baseline-policy.json"
)


class HygieneError(Exception):
    """Expected invalid input or a blocked safety precondition."""


def emit(payload: dict[str, Any], code: int = 0) -> int:
    print(json.dumps(payload, indent=2, sort_keys=True))
    return code


def load_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise HygieneError(f"cannot read JSON {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise HygieneError(f"JSON root must be an object: {path}")
    return value


def write_json(path: Path, payload: dict[str, Any]) -> None:
    path = state_output_path(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )


DATA_ROOT_OVERRIDE: str | None = None


def state_output_path(path: Path) -> Path:
    data_value = DATA_ROOT_OVERRIDE or os.environ.get("CLAUDE_PLUGIN_DATA")
    if not data_value:
        raise HygieneError(
            "a generated-state root is required: pass --data-root or set CLAUDE_PLUGIN_DATA"
        )
    data_root = Path(data_value).expanduser().resolve(strict=False)
    path = path.expanduser().resolve(strict=False)
    if is_within(path, PLUGIN_ROOT):
        raise HygieneError(
            "generated state must not be written inside the plugin install directory"
        )
    if not is_within(path, data_root):
        raise HygieneError("generated state must stay inside the data root")
    return path


def os_key() -> str:
    system = platform.system().lower()
    return {"darwin": "macos", "windows": "windows", "linux": "linux"}.get(
        system, system
    )


def glob_matches(subject: str, pattern: str) -> bool:
    """Case-insensitive glob match, on every platform.

    One matcher for every glob the engine evaluates — hints, consumer
    protection globs, the baseline protected-name globs, and the protection
    re-checks in the preview, verify, and apply lanes — so discovery and
    protection cannot disagree about what a name is.
    `fnmatch.fnmatch` is not that matcher: its case folding follows the host
    platform, so its verdict would change with where the scan runs.

    Casefolding is the safe direction for both roles. A protection glob that
    matches more can only keep more, and on Windows and macOS the filesystem is
    case-insensitive anyway, so a case-sensitive protection glob was a hole
    rather than a precision. A hint that matches more can only surface more for
    triage — hints are discovery signals, never cleanup verdicts. This also
    aligns globs with `has_protected_name`, which has always casefolded.
    """
    return fnmatch.fnmatchcase(subject.casefold(), pattern.casefold())


def is_within(path: Path, parent: Path) -> bool:
    try:
        return os.path.commonpath(
            [os.path.normcase(path), os.path.normcase(parent)]
        ) == os.path.normcase(parent)
    except ValueError:
        return False


def is_linkish_stat(info: os.stat_result) -> bool:
    """Link-like for an already-taken stat: symlink or Windows reparse point."""
    if stat.S_ISLNK(info.st_mode):
        return True
    return bool(getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT)


def is_cloud_placeholder_stat(info: os.stat_result) -> bool:
    """Whether an already-taken stat describes cloud-resident, non-local content.

    Deliberately independent of is_linkish_stat(): the placeholder class this
    identifies is precisely the one that does NOT read as a reparse point
    through this interpreter (see CLOUD_PLACEHOLDER_ATTRIBUTES), so the reparse
    test can never stand in for it.
    """
    return bool(getattr(info, "st_file_attributes", 0) & CLOUD_PLACEHOLDER_ATTRIBUTES)


def link_and_cloud_state(path: Path) -> tuple[bool, bool]:
    """Return (link-like, cloud-placeholder) for one path from a SINGLE lstat.

    Both questions are asked at every ancestor of every scanned entry and both
    are answered by the same st_file_attributes word, so reading it twice would
    double the stat load of a walk bounded at MAX_SNAPSHOT_ENTRIES entries for
    no new information. An unreadable path answers "neither" — callers treat
    protection as additive and the surrounding lanes already fail closed on an
    entry they cannot stat.
    """
    try:
        info = path.lstat()
    except OSError:
        return False, False
    return is_linkish_stat(info), is_cloud_placeholder_stat(info)


def is_linkish(path: Path) -> bool:
    """Return true for every link-like Windows reparse point, including on 3.11."""
    return link_and_cloud_state(path)[0]


def has_linkish_component(path: Path, stop: Path | None = None) -> bool:
    current = path
    while True:
        if is_linkish(current):
            return True
        if current == stop or current.parent == current:
            return False
        current = current.parent


def _decode_mountinfo_path(value: str) -> str:
    result = bytearray()
    index = 0
    encoded = os.fsencode(value)
    while index < len(encoded):
        if (
            encoded[index : index + 1] == b"\\"
            and index + 3 < len(encoded)
            and all(48 <= byte <= 55 for byte in encoded[index + 1 : index + 4])
        ):
            result.append(int(encoded[index + 1 : index + 4], 8))
            index += 4
        else:
            result.append(encoded[index])
            index += 1
    return os.fsdecode(bytes(result))


def linux_mount_points() -> tuple[set[Path], str | None]:
    if os_key() != "linux":
        return set(), None
    try:
        lines = Path("/proc/self/mountinfo").read_text(encoding="utf-8").splitlines()
        points = {
            Path(_decode_mountinfo_path(fields[4])).absolute()
            for line in lines
            if len(fields := line.split()) >= 10 and "-" in fields[6:]
        }
    except (OSError, UnicodeError, ValueError) as exc:
        return set(), f"cannot read /proc/self/mountinfo: {exc}"
    if not points:
        return set(), "no mount points were reported by /proc/self/mountinfo"
    return points, None


def mount_state(
    path: Path, known_linux_mounts: set[Path] | None = None
) -> tuple[bool, str | None]:
    if os_key() == "linux":
        points = known_linux_mounts
        error = None
        if points is None:
            points, error = linux_mount_points()
        if error:
            return False, error
        return path.absolute() in points, None
    try:
        return os.path.ismount(path), None
    except OSError as exc:
        return False, str(exc)


def windows_drive_roots() -> list[Path]:
    if os.name != "nt":
        return []
    get_logical_drives = ctypes.WinDLL("kernel32", use_last_error=True).GetLogicalDrives
    get_logical_drives.argtypes = []
    get_logical_drives.restype = ctypes.c_uint32
    mask = get_logical_drives()
    if not mask:
        raise OSError(ctypes.get_last_error(), "GetLogicalDrives failed")
    return [Path(f"{chr(65 + index)}:\\") for index in range(26) if mask & (1 << index)]


def has_protected_name(path: Path, exact_names: set[str]) -> bool:
    name = path.name.casefold()
    return (
        name in {value.casefold() for value in exact_names}
        or name.startswith("ntuser.dat")
        or any(
            glob_matches(name, pattern) for pattern in baseline_protected_name_globs()
        )
    )


def has_protected_path_component(path: Path, exact_names: set[str]) -> bool:
    return any(
        has_protected_name(candidate, exact_names)
        for candidate in (path, *path.parents)
        if candidate.parent != candidate
    )


def _windows_env_roots() -> list[Path]:
    """The OS-install roots the environment names, absolute, skipping the unset.

    Shared by system_roots(), os_drive_markers(), and
    volume_root_os_owned_names(): they disagree about the per-volume metadata
    names, never about which environment variables point at the OS install, so
    naming them once keeps that half from drifting.
    """
    return [
        Path(value).absolute()
        for value in (
            os.environ.get("SystemRoot"),
            os.environ.get("ProgramFiles"),
            os.environ.get("ProgramFiles(x86)"),
            os.environ.get("ProgramData"),
        )
        if value
    ]


def system_roots(
    platform_key: str | None = None, windows_roots: list[Path] | None = None
) -> list[Path]:
    roots: list[Path] = []
    current_platform = platform_key or os_key()
    if current_platform == "windows":
        roots.extend(_windows_env_roots())
        drive_roots = (
            windows_roots if windows_roots is not None else windows_drive_roots()
        )
        for drive_root in drive_roots:
            roots.extend(drive_root / name for name in WINDOWS_VOLUME_SYSTEM_NAMES)
    elif current_platform == "macos":
        roots.extend(
            Path(value)
            for value in ("/System", "/Library", "/Applications", "/private")
        )
    else:
        roots.extend(
            Path(value)
            for value in (
                "/bin",
                "/boot",
                "/dev",
                "/etc",
                "/lib",
                "/proc",
                "/run",
                "/sbin",
                "/sys",
                "/usr",
                "/var",
            )
        )
    return roots


def os_drive_markers(
    platform_key: str | None = None, windows_roots: list[Path] | None = None
) -> list[Path]:
    """Paths whose presence within a volume identifies it as an OS/system drive.

    Distinct from system_roots(): system_roots() lists everything to protect
    from deletion (including the per-volume metadata every Windows volume
    carries), whereas this lists only the OS-install markers that make a whole
    volume the OS drive. The difference is the whole point of the Dev Drive
    fix: counting per-volume metadata (System Volume Information, $Recycle.Bin)
    as an OS signal would misclassify every drive root — a provisioned non-OS
    volume has that metadata too. On POSIX every system root is a genuine OS
    directory, so the full set applies.
    """
    current_platform = platform_key or os_key()
    if current_platform != "windows":
        return system_roots(current_platform)
    markers: list[Path] = []
    markers.extend(_windows_env_roots())
    drive_roots = windows_roots if windows_roots is not None else windows_drive_roots()
    for drive_root in drive_roots:
        markers.extend(drive_root / name for name in WINDOWS_OS_DRIVE_MARKERS)
    return markers


def is_volume_root(path: Path) -> bool:
    """True for a filesystem or drive root — a path that is its own parent."""
    return path.parent == path


def is_os_managed_target(
    target: Path,
    roots: list[Path] | None = None,
    markers: list[Path] | None = None,
) -> bool:
    """Reasoned OS-managed classification for a whole-volume audit target.

    Two directions, each with its own root set:

    - the target sits *within* an OS-managed root (system_roots(), the full
      protect-from-deletion set) — e.g. ``C:\\Windows\\Temp`` or ``/etc/x``;
    - an OS-install *marker* actually exists *within* the target
      (os_drive_markers(), the narrow OS-drive discriminator) — e.g. ``C:\\``
      holds an existing ``C:\\Windows``, ``/`` holds ``/bin``.

    The containing direction deliberately uses the narrow marker set, not
    system_roots(): every Windows volume — a provisioned non-OS Dev Drive
    included — carries System Volume Information and $Recycle.Bin, so counting
    those as an OS signal would deny every drive root and defeat the fix. The
    existence gate matters because os_drive_markers() synthesizes per-drive
    marker paths for every drive without checking existence. Result: ``C:\\``
    (holds an existing Windows install) is denied; a Dev Drive root (holds no
    OS-install marker) is not — it is confirmation-required, never
    blanket-denied.
    """
    target_abs = target.absolute()
    for root in roots if roots is not None else system_roots():
        if is_within(target_abs, root.absolute()):
            return True
    for marker in markers if markers is not None else os_drive_markers():
        marker_abs = marker.absolute()
        if is_within(marker_abs, target_abs) and marker_abs.exists():
            return True
    return False


def hard_protection(
    path: Path,
    target: Path,
    exact_names: set[str],
    known_linux_mounts: set[Path] | None = None,
) -> list[str]:
    reasons: list[str] = []
    if path == target:
        reasons.append("target-root")
    if is_volume_root(path) and is_os_managed_target(path):
        reasons.append("os-managed-root")
    current = path
    while is_within(current, target):
        linkish, cloud_placeholder = link_and_cloud_state(current)
        if linkish:
            reasons.append("symlink-junction-or-reparse-point")
        if cloud_placeholder and (current != target or path == target):
            # Its bytes live in the provider's cloud, so deleting it here
            # propagates the delete THERE — for a tenant sync root, to the
            # organisation's only copy. Nothing local is reclaimed either way.
            #
            # The target's own iteration is exempted for every OTHER entry, on
            # the same reasoning as target-is-mount-point below: a target that
            # itself carries a recall/offline bit would otherwise mark EVERY
            # entry cloud-placeholder, and scan_tree truncates any directory
            # with protections — collapsing the whole walk with no diagnostic.
            # The target entry itself still reports the reason honestly, so the
            # condition is visible rather than silently swallowed.
            reasons.append("cloud-placeholder")
        mounted, mount_error = mount_state(current, known_linux_mounts)
        if mount_error:
            reasons.append("mount-state-unverified")
        elif mounted:
            if current != target:
                reasons.append("nested-mount-point")
            elif not is_volume_root(target):
                # A volume-root target is inherently a mount point and is
                # admitted as such by the reasoned target-level checks; flagging
                # it here would mark every descendant target-is-mount-point and
                # defeat the admitted scan. A non-volume-root target that is a
                # mount is still blocked (it should never have been admitted, or
                # became a mount after the snapshot). Nested mounts below the
                # target stay blocked regardless.
                reasons.append("target-is-mount-point")
        if current == target:
            break
        if has_protected_name(current, exact_names):
            reasons.append("baseline-protected-name")
        if current.name.casefold() in VCS_NAMES:
            reasons.append("vcs-metadata")
        current = current.parent
    for root in system_roots():
        if is_within(path.absolute(), root.absolute()):
            reasons.append("os-managed-root")
            break
    return sorted(set(reasons))


def standing_policy_paths(project_dir: Path | None) -> list[Path]:
    layers = [Path.home() / ".claude" / "disk-hygiene.json"]
    if project_dir is not None:
        layers.append(project_dir / ".claude" / "disk-hygiene.json")
    return [path for path in layers if path.is_file()]


def baseline_policy() -> dict[str, Any]:
    baseline = load_json(BASELINE_POLICY)
    if baseline.get("version") != SCHEMA_VERSION:
        raise HygieneError("unsupported baseline policy version")
    return {
        "version": SCHEMA_VERSION,
        "protected_exact_names": list(baseline.get("protected_exact_names", [])),
        "protected_name_globs": list(baseline.get("protected_name_globs", [])),
        "hints": list(baseline.get("hints", [])),
        "additional_protected_path_globs": [],
        "policy_sources": ["baseline"],
    }


def baseline_protected_names() -> set[str]:
    """Bundled protected names only — validation paths must never depend on
    ambient standing policy; an approved snapshot stays previewable even if a
    standing file is later edited or malformed."""
    return set(baseline_policy()["protected_exact_names"])


@functools.lru_cache(maxsize=1)
def baseline_protected_name_globs() -> tuple[str, ...]:
    """Bundled protected-name PATTERNS, for the names that vary per installation.

    A cloud-sync root's name embeds the tenant — Microsoft documents the
    OneDrive for Business sync root as ``OneDrive - <organization name>`` — so
    no exact name can cover it, and a consumer cannot cover it either:
    ``additional_protected_path_globs`` is matched against a path RELATIVE to
    the scan target, so a standing overlay protects such a root only when the
    target happens to be its parent. Protection that must hold for every target
    has to ship in the baseline, which is why this reads the bundled file
    directly rather than taking policy as a parameter — exactly as
    ``baseline_protected_names`` does on the validation lanes.

    Matched casefolded through ``fnmatchcase`` rather than ``fnmatch``, whose
    case folding follows the host platform; a protection whose verdict depends
    on where it runs is not a protection.

    Cached because ``has_protected_name`` runs at every ancestor of every entry
    of a walk bounded at MAX_SNAPSHOT_ENTRIES entries, and the bundled file is
    a build-time constant.
    """
    return tuple(baseline_policy()["protected_name_globs"])


def load_policy(
    overlay_path: Path | None, project_dir: Path | None = None
) -> dict[str, Any]:
    result = baseline_policy()
    # An explicit --policy is the invocation-specific choice and wins outright;
    # otherwise standing user-global and project files layer additively.
    overlays = (
        [overlay_path]
        if overlay_path is not None
        else standing_policy_paths(project_dir)
    )
    for path in overlays:
        apply_policy_overlay(result, path)
    return result


def apply_policy_overlay(result: dict[str, Any], overlay_path: Path) -> None:
    overlay = load_json(overlay_path)
    allowed = {
        "version",
        "disabled_hint_ids",
        "additional_hints",
        "additional_protected_path_globs",
    }
    unknown = sorted(set(overlay) - allowed)
    if unknown:
        raise HygieneError(
            f"unknown policy fields in {overlay_path}: {', '.join(unknown)}"
        )
    if overlay.get("version") != SCHEMA_VERSION:
        raise HygieneError(f"policy version must be 1: {overlay_path}")
    disabled = overlay.get("disabled_hint_ids", [])
    additions = overlay.get("additional_hints", [])
    protections = overlay.get("additional_protected_path_globs", [])
    if not isinstance(disabled, list) or not isinstance(protections, list):
        raise HygieneError("disabled_hint_ids and protection globs must be arrays")
    if not all(isinstance(value, str) and value for value in disabled + protections):
        raise HygieneError("policy IDs and protection globs must be non-empty strings")
    if not isinstance(additions, list):
        raise HygieneError("additional_hints must be an array")
    known_ids = {hint.get("id") for hint in result["hints"]}
    for hint in additions:
        validate_hint(hint)
        if hint["id"] in known_ids:
            raise HygieneError(
                f"additional hint ID already exists ({overlay_path}): {hint['id']}"
            )
        known_ids.add(hint["id"])
    disabled_set = set(disabled)
    result["hints"] = [
        hint for hint in result["hints"] if hint.get("id") not in disabled_set
    ]
    result["hints"].extend(additions)
    result["additional_protected_path_globs"].extend(protections)
    result["policy_sources"].append(str(overlay_path))


def validate_hint(hint: Any) -> None:
    if not isinstance(hint, dict):
        raise HygieneError("each additional hint must be an object")
    required = {"id", "os", "kind", "pattern", "confidence_ceiling", "reason"}
    if set(hint) != required:
        raise HygieneError(
            "each additional hint must contain exactly id/os/kind/pattern/confidence_ceiling/reason"
        )
    if hint["kind"] not in {"name_glob", "path_glob"}:
        raise HygieneError(f"unsupported hint kind: {hint['kind']}")
    if hint["confidence_ceiling"] not in TIERS:
        raise HygieneError(
            f"unsupported confidence ceiling: {hint['confidence_ceiling']}"
        )
    if not isinstance(hint["os"], list) or not all(
        value in {"all", "windows", "linux", "macos"} for value in hint["os"]
    ):
        raise HygieneError(
            "hint os must be an array containing all/windows/linux/macos"
        )
    for field in ("id", "pattern", "reason"):
        if not isinstance(hint[field], str) or not hint[field]:
            raise HygieneError(f"hint {field} must be a non-empty string")


def matching_hints(
    relative: str, name: str, policy: dict[str, Any]
) -> list[dict[str, str]]:
    matches = []
    current_os = os_key()
    for hint in policy["hints"]:
        validate_hint(hint)
        if "all" not in hint["os"] and current_os not in hint["os"]:
            continue
        subject = name if hint["kind"] == "name_glob" else relative
        if glob_matches(subject, hint["pattern"]):
            matches.append(
                {
                    "id": hint["id"],
                    "confidence_ceiling": hint["confidence_ceiling"],
                    "reason": hint["reason"],
                }
            )
    return matches


def allocated_size_from_stat(info: os.stat_result) -> int | None:
    """Cheap on-disk allocation when the platform exposes it; else unknown.

    Returns null rather than inventing a figure. A missing allocated size is
    itself a size signal ("we do not know") and must not collapse to zero.
    """
    blocks = getattr(info, "st_blocks", None)
    if blocks is None:
        return None
    return int(blocks) * ST_BLOCKS_BYTES


def metadata(
    path: Path,
    kind: str,
    logical_size: int | None = 0,
    *,
    walked: bool = True,
) -> dict[str, Any]:
    """Per-entry facts for the snapshot, including what QUALIFIES its byte count.

    `size_qualifiers` exists so a reader can never mistake a recorded byte
    count for bytes that deleting the entry would return to the volume. A cloud
    placeholder's `logical_size` is its REMOTE size while its local occupancy is
    roughly zero; a hard-linked file's size is shared with every other name; a
    truncated directory was never inventoried, so its size is unknown rather
    than empty. The qualifier is recorded for every entry, protected or not:
    protection stops the deletion, and this stops the misreading.

    A truncated directory's `logical_size` is null, never 0. Zero remains the
    genuine empty-directory signal; collapsing "not walked" into zero made a
    1.35 GB truncated `.cache` indistinguishable from an empty folder.

    One entry is deliberately exempt: `scan_tree` appends `not-walked` to the
    TARGET's own qualifiers while keeping its partial walked sum, because the
    root is the one number a caller reaches first and nulling it costs more than
    the imprecision. So `not-walked` implies a null `logical_size` for every
    entry this function produces, but not for the target record, which is
    assembled there rather than here.
    """
    info = path.lstat()
    attributes = int(getattr(info, "st_file_attributes", 0))
    nlink = int(info.st_nlink)
    allocated = allocated_size_from_stat(info)
    if kind == "directory":
        recorded_logical: int | None = None if not walked else logical_size
    else:
        recorded_logical = info.st_size
    qualifiers: list[str] = []
    if not walked:
        qualifiers.append("not-walked")
    if is_cloud_placeholder_stat(info):
        qualifiers.append("cloud-placeholder")
    # Directories carry st_nlink >= 2 for "." / ".." (and higher for each
    # subdirectory) on POSIX; that is not multi-name hard-linking of content.
    # Only regular files with more than one directory entry share one object.
    if kind == "file" and nlink > 1:
        qualifiers.append("hardlinked")
    if kind == "file" and (
        bool(attributes & FILE_ATTRIBUTE_SPARSE_FILE)
        or (allocated is not None and allocated < info.st_size)
    ):
        qualifiers.append("sparse")
    return {
        "kind": kind,
        "stat_size": info.st_size,
        "logical_size": recorded_logical,
        "allocated_size": allocated,
        "nlink": nlink,
        "mtime_ns": info.st_mtime_ns,
        "device": info.st_dev,
        "inode": info.st_ino,
        "mode": stat.S_IFMT(info.st_mode),
        "file_attributes": attributes,
        "size_qualifiers": sorted(qualifiers),
    }


def entry_logical_file_bytes(entry: dict[str, Any]) -> int:
    """Snapshot-recorded logical bytes for a non-directory entry; 0 if unknown."""
    if entry.get("kind") == "directory":
        return 0
    size = entry.get("logical_size")
    return int(size) if isinstance(size, int) else 0


def entry_reclaimable_local_bytes(entry: dict[str, Any]) -> int | None:
    """Bytes deleting this one name is expected to return locally, if known.

    Returns null when the entry is not a reclaimable local file or when any
    qualifier means the recorded size is not "bytes this delete frees".
    Hard links are excluded entirely: deleting one name does not free the
    shared object, and counting every name would double-count.
    """
    if entry.get("kind") != "file":
        return None
    if entry.get("size_qualifiers"):
        return None
    size = entry.get("logical_size")
    if not isinstance(size, int):
        return None
    return size


def reclaimable_local_bytes(entries: list[dict[str, Any]]) -> int:
    """Sum of per-entry reclaimable local bytes across an inventory."""
    total = 0
    for entry in entries:
        value = entry_reclaimable_local_bytes(entry)
        if value is not None:
            total += value
    return total


def entry_is_empty_directory(
    entry: dict[str, Any],
    inventory: dict[str, dict[str, Any]]
    | list[dict[str, Any]]
    | set[str]
    | None = None,
    *,
    parents_with_children: set[str] | None = None,
    unknown_paths: set[str] | None = None,
) -> bool:
    """True when a walked directory has no inventoried descendants.

    Truncated (`not-walked`) directories are unknown, not empty — their
    `logical_size` is null. A walked parent whose only children were cut off by
    `--max-depth` can still show `logical_size` 0; requiring no snapshot
    descendants keeps that case out of the empty-directory tidiness count so
    zero-byte residue stays visible without mislabeling uninventoried trees.
    Directories whose scandir failed (or that appear in ``unknown_paths``) are
    likewise unknown: a coverage gap is not empty residue.
    """
    if entry.get("kind") != "directory":
        return False
    qualifiers = entry.get("size_qualifiers") or []
    if "not-walked" in qualifiers:
        return False
    if entry.get("logical_size") != 0:
        return False
    relative = entry.get("path")
    if not isinstance(relative, str) or not relative:
        return False
    if unknown_paths and relative in unknown_paths:
        return False
    if parents_with_children is not None:
        return relative not in parents_with_children
    if inventory is None:
        paths: Iterable[str] = ()
    elif isinstance(inventory, dict):
        paths = inventory
    elif isinstance(inventory, set):
        paths = inventory
    else:
        paths = (
            item["path"]
            for item in inventory
            if isinstance(item, dict) and isinstance(item.get("path"), str)
        )
    prefix = relative + "/"
    return not any(path.startswith(prefix) for path in paths)


def child_rollup_name(relative: str) -> str:
    """The immediate-child segment a snapshot-relative path belongs to."""
    return relative.split("/", 1)[0]


def child_rollup_bytes(entry: dict[str, Any]) -> int:
    """The bytes one immediate child contributes to the target's walked total.

    Mirrors ``scan_tree``'s own accumulation exactly: a walked directory's
    ``logical_size`` is already its recursive subtotal, a file contributes its
    recorded logical size, and a link or special entry contributes nothing
    because the walk never traverses one. Keeping the two rules identical is
    what makes the roll-up sum to ``target_logical_bytes`` when every immediate
    child was walked.
    """
    if entry.get("kind") == "directory":
        size = entry.get("logical_size")
        return int(size) if isinstance(size, int) else 0
    if entry.get("kind") == "file":
        return entry_logical_file_bytes(entry)
    return 0


def empty_child_rollup_bucket() -> dict[str, Any]:
    """The per-child accumulator, in one place so its shape cannot drift."""
    return {
        "self": None,
        "descendants": 0,
        "newest": None,
        "qualifiers": set(),
        "reclaimable": 0,
    }


def children_rollup(
    entries: list[dict[str, Any]],
    *,
    unknown_paths: Iterable[str] = (),
    unwalked_reasons: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """One row per immediate child of the target: bytes, count, newest mtime, coverage.

    The bounded pass the skill recommends (``--max-depth 1``) leaves every
    non-empty immediate child uninventoried, so the per-child question the
    operator is told to reason in — how big is it, how much is in it, when was
    it last touched — has no answer anywhere in the flat entry list. This
    assembles that answer from what the walk ALREADY recorded: it opens no
    directory and stats no path, so it can never turn a bounded pass into an
    unbounded one. The cost of the roll-up is one linear pass over ``entries``.

    Precisely because nothing extra is walked, a child is credited with numbers
    only when its whole subtree was inventoried. ``walked`` is the single
    discriminator: true means every aggregate is exact, false means they are all
    ``null`` — never 0, which stays the genuine "this is empty" answer — with
    the causes in ``unwalked_reasons``. A partial sum is never presented as a
    total. Every immediate child gets a row whatever its coverage, so a gap is
    visible per child rather than only in ``truncated_paths``. (In
    ``--root-children`` mode "every child" means every SELECTED child: the walk
    never looks at an unselected sibling, so the row set follows the selection
    the payload records in ``root_children_selected``.)

    ``logical_bytes`` alone would mislead exactly where this engine refuses to:
    it is a LOGICAL total, and a cloud placeholder's remote size, a hard link's
    shared object, and a sparse file's unallocated extent all inflate it above
    what deleting the child would return. So each row carries the same two
    channels every other byte-bearing surface here does — ``size_qualifiers``,
    the union of qualifiers observed in the subtree, and
    ``reclaimable_local_bytes``, which counts only unqualified files, mirroring
    ``target_reclaimable_local_bytes``.

    ``unknown_paths`` is every relative path the walk could not fully account
    for (truncations, scan errors, ``not-walked`` records); a path marks its own
    child row when it IS the child and marks the child's row as
    ``descendant-not-walked`` when it lives below one. A path recorded as
    unknown with no more specific cause falls back to the bare ``not-walked``,
    the same qualifier the flat entry carries.
    """
    reasons = unwalked_reasons or {}
    gaps: dict[str, set[str]] = {}
    for path in unknown_paths:
        if not isinstance(path, str) or not path or path == ".":
            continue
        name = child_rollup_name(path)
        gaps.setdefault(name, set()).add(
            reasons.get(path, "not-walked") if path == name else "descendant-not-walked"
        )
    totals: dict[str, dict[str, Any]] = {}
    for entry in entries:
        relative = entry.get("path")
        # `.` is the target itself, never one of its children: `scan_tree` keeps
        # the target's record out of `entries`, and the same skip in the gap loop
        # above keeps a target-level truncation from inventing a `.` child row.
        if not isinstance(relative, str) or not relative or relative == ".":
            continue
        name = child_rollup_name(relative)
        bucket = totals.setdefault(name, empty_child_rollup_bucket())
        if relative == name:
            bucket["self"] = entry
        else:
            bucket["descendants"] = bucket["descendants"] + 1
        mtime = entry.get("mtime_ns")
        if isinstance(mtime, int):
            newest = bucket["newest"]
            bucket["newest"] = mtime if newest is None else max(newest, mtime)
        bucket["qualifiers"].update(entry.get("size_qualifiers") or ())
        local = entry_reclaimable_local_bytes(entry)
        if local is not None:
            bucket["reclaimable"] = bucket["reclaimable"] + local
    rows: list[dict[str, Any]] = []
    for name in sorted(set(totals) | set(gaps)):
        bucket = totals.get(name) or empty_child_rollup_bucket()
        child = bucket["self"]
        causes = set(gaps.get(name, ()))
        if child is None:
            # An immediate child whose own record never reached the inventory
            # (its lstat or its parent's scandir failed) is a coverage gap, not
            # a zero-byte child.
            causes.add("scan-error")
        walked = not causes
        rows.append(
            {
                "name": name,
                "kind": child.get("kind") if child is not None else None,
                "walked": walked,
                "logical_bytes": child_rollup_bytes(child)
                if walked and child is not None
                else None,
                "reclaimable_local_bytes": bucket["reclaimable"] if walked else None,
                "size_qualifiers": sorted(bucket["qualifiers"]) if walked else None,
                "entry_count": bucket["descendants"] if walked else None,
                "newest_mtime_ns": bucket["newest"] if walked else None,
                "unwalked_reasons": sorted(causes),
            }
        )
    return rows


def inventory_parent_paths(paths: Iterable[str]) -> set[str]:
    """Return every inventory path that has at least one inventoried descendant.

    Built in one linear pass over ``paths`` so empty-directory counting stays
    O(entries) rather than O(directories × entries).
    """
    parents: set[str] = set()
    for path in paths:
        if not isinstance(path, str) or "/" not in path:
            continue
        parent = path.rsplit("/", 1)[0]
        while parent:
            if parent in parents:
                break
            parents.add(parent)
            if "/" not in parent:
                break
            parent = parent.rsplit("/", 1)[0]
    return parents


def empty_directory_count(
    entries: list[dict[str, Any]],
    *,
    error_paths: Iterable[str] | None = None,
) -> int:
    """Count walked empty directories in a snapshot inventory.

    ``error_paths`` are scan-error relatives that must not count as empty even
    when they were recorded with ``logical_size`` 0 and no descendants.
    """
    by_path = {
        entry["path"]: entry
        for entry in entries
        if isinstance(entry, dict) and isinstance(entry.get("path"), str)
    }
    parents_with_children = inventory_parent_paths(by_path)
    unknown = {path for path in (error_paths or ()) if isinstance(path, str) and path}
    return sum(
        1
        for entry in by_path.values()
        if entry_is_empty_directory(
            entry,
            parents_with_children=parents_with_children,
            unknown_paths=unknown,
        )
    )


def discover_enclosing_git(target: Path) -> tuple[list[Path], list[str]]:
    marker_root = next(
        (
            ancestor
            for ancestor in (target, *target.parents)
            if is_linkish(ancestor / ".git") or (ancestor / ".git").exists()
        ),
        None,
    )
    git = shutil.which("git")
    if not git:
        if marker_root is not None:
            return [marker_root.resolve()], ["git-not-found"]
        return [], []
    run = subprocess.run(
        [git, "-C", str(target), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if run.returncode == 0 and run.stdout.strip():
        return [Path(run.stdout.strip()).resolve()], []
    if marker_root is not None:
        return [marker_root.resolve()], [f"{marker_root}: git-state-unverified"]
    return [], []


def windows_storage_sense_state() -> dict[str, Any]:
    import winreg

    key_path = (
        r"Software\Microsoft\Windows\CurrentVersion"
        r"\StorageSense\Parameters\StoragePolicy"
    )
    state: dict[str, Any] = {
        "enabled": None,
        "temporary_files_cleanup": None,
        "cadence_days": None,
    }
    try:
        with winreg.OpenKey(winreg.HKEY_CURRENT_USER, key_path) as key:
            for name, field in (
                ("01", "enabled"),
                ("04", "temporary_files_cleanup"),
            ):
                try:
                    state[field] = bool(winreg.QueryValueEx(key, name)[0])
                except OSError:
                    pass
            try:
                state["cadence_days"] = int(winreg.QueryValueEx(key, "2048")[0])
            except OSError:
                pass
    except OSError:
        pass
    return state


def os_autoclean_advisory(target: Path) -> dict[str, Any] | None:
    """Report-only: name the OS auto-clean mechanism that should own this zone.

    Mirrors the managed-state rule for products: when the OS already ships a
    garbage collector for a zone, recommend enabling/tuning it instead of
    hand-cleaning. Never authorizes or blocks anything.
    """
    try:
        temp_root = Path(tempfile.gettempdir()).resolve()
    except OSError:
        return None
    resolved = target.resolve()
    covers_target = is_within(resolved, temp_root) or is_within(temp_root, resolved)
    if not covers_target:
        return None
    if sys.platform == "win32":
        state = windows_storage_sense_state()
        effective = (
            state["enabled"] is True
            and state["temporary_files_cleanup"] is True
            # Cadence 0 = "during low free disk space", which may never fire.
            and (state["cadence_days"] or 0) > 0
        )
        return {
            "mechanism": "windows-storage-sense",
            "state": state,
            "recommendation": None
            if effective
            else (
                "This zone includes the user temp directory, which Windows "
                "Storage Sense can clean automatically. Recommend enabling "
                "temporary-file cleanup on a scheduled cadence (Settings > "
                "System > Storage) instead of hand-cleaning it here."
            ),
        }
    if sys.platform.startswith("linux"):
        configured = any(
            Path(root).is_dir()
            for root in ("/etc/tmpfiles.d", "/run/tmpfiles.d", "/usr/lib/tmpfiles.d")
        )
        return {
            "mechanism": "systemd-tmpfiles",
            "state": {"config_present": configured},
            "recommendation": None
            if configured
            else (
                "This zone includes the temp directory, which systemd-tmpfiles "
                "normally ages out. Recommend configuring tmpfiles.d instead of "
                "hand-cleaning it here."
            ),
        }
    return {
        "mechanism": "not-detected",
        "state": {},
        "recommendation": None,
    }


def user_home() -> Path | None:
    try:
        return Path.home()
    except RuntimeError:
        return None


def large_scan_reasons(target: Path) -> list[str]:
    """Name deterministically why a target is a known-large scan root.

    A known-large root is one whose unbounded recursive walk is expected to be
    expensive in time and resources. Two cases today: the user home directory,
    and a whole filesystem/volume root that is a valid non-OS target (a Windows
    Dev Drive). An OS-managed root is denied upstream before this runs, so any
    volume root reaching the gate is non-OS; the check here is nonetheless
    self-contained (is_volume_root and not OS-managed) so the reason is honest
    even called directly. The engine gates such a walk behind an explicit bound
    or confirmation, mirroring the apply lane's "ask before it is expensive"
    posture, moved earlier because the cost here is time, not data loss.

    The home match is by filesystem identity (device + inode via
    ``os.path.samefile``), not a path-string compare: ``os.path.normcase`` only
    folds case on Windows, so a string compare would let a case-variant spelling
    (``/users/alice`` vs ``/Users/alice``) bypass the gate on a case-insensitive
    macOS volume. ``target`` is validated to exist upstream; ``samefile`` raises
    only when a path is missing, so a home that cannot be stat'd is simply no match.
    The volume-root match is structural (``is_volume_root``: a self-parent path),
    inherently spelling- and case-robust.
    """
    reasons: list[str] = []
    home = user_home()
    if home is not None:
        try:
            same_home = os.path.samefile(target, home)
        except OSError:
            same_home = False
        if same_home:
            reasons.append("user-home")
    if is_volume_root(target) and not is_os_managed_target(target):
        reasons.append("non-os-volume-root")
    return sorted(set(reasons))


def top_level_entry_count(target: Path) -> tuple[int | None, str | None]:
    """Count immediate children only — a cheap probe that never recurses."""
    try:
        with os.scandir(target) as iterator:
            return sum(1 for _ in iterator), None
    except OSError as exc:
        return None, str(exc)


def directory_has_child(directory: Path) -> bool:
    """Whether a directory holds at least one entry — one read, no recursion.

    FAILS CLOSED. Emptiness has to be PROVEN, so an unreadable directory
    reports True (assume content). The caller uses this to decide whether a
    scan boundary can be reported as fully inventoried, and a directory whose
    contents could not be read is exactly the case that must keep its
    "not inventoried" marking. The read is inside the ``try`` deliberately:
    Windows surfaces an access denial on the first iteration step rather than
    on ``os.scandir`` itself.

    Deliberately not ``top_level_entry_count``: that one iterates every child
    to produce a count, and a boundary directory with hundreds of thousands of
    entries is precisely the cost ``--max-depth`` exists to avoid. Only the
    first entry is ever read here — the question is "any?", not "how many?".
    """
    try:
        with os.scandir(directory) as iterator:
            return next(iter(iterator), None) is not None
    except OSError:
        return True


def volume_root_os_owned_names(
    platform_key: str | None = None,
) -> set[str]:
    """Basenames the volume-root guard treats as OS-owned at a drive/FS root."""
    current = platform_key or os_key()
    if current == "windows":
        return {
            name.casefold()
            for name in (
                WINDOWS_VOLUME_SYSTEM_NAMES
                | WINDOWS_OS_ROOT_EXTRA_NAMES
                | {root.name for root in _windows_env_roots()}
            )
        }
    if current == "macos":
        return {
            name.casefold()
            for name in (
                "System",
                "Library",
                "Applications",
                "private",
                "Volumes",
                "cores",
                "usr",
                "bin",
                "sbin",
                "etc",
                "dev",
                "tmp",
                "var",
            )
        }
    return {
        name.casefold()
        for name in (
            "bin",
            "boot",
            "dev",
            "etc",
            "home",
            "lib",
            "lib64",
            "lost+found",
            "media",
            "mnt",
            "opt",
            "proc",
            "root",
            "run",
            "sbin",
            "srv",
            "sys",
            "tmp",
            "usr",
            "var",
        )
    }


def root_child_skip_reason(
    path: Path,
    *,
    exact_names: set[str],
    known_linux_mounts: set[Path] | None = None,
    os_owned_names: set[str] | None = None,
) -> str | None:
    """Why an immediate volume-root entry must not be offered or audited.

    Mirrors the volume-root guard's exclusion spirit (OS-owned / hidden /
    system / reparse) and fails closed on anything ambiguous (#2588). Root
    files are never candidates — only directories can be selected.
    """
    try:
        info = path.lstat()
    except OSError as exc:
        return f"unreadable:{exc}"
    if is_linkish_stat(info):
        return "symlink-junction-or-reparse-point"
    if is_cloud_placeholder_stat(info):
        return "cloud-placeholder"
    if not stat.S_ISDIR(info.st_mode):
        return "not-a-directory"
    name = path.name
    if name in {".", ".."} or not name:
        return "invalid-name"
    if name.startswith("."):
        return "hidden"
    folded = name.casefold()
    owned = (
        os_owned_names if os_owned_names is not None else volume_root_os_owned_names()
    )
    if folded in owned:
        return "os-owned"
    # Windows metadata / upgrade residue often uses a $-prefix outside the
    # static marker set ($SysReset, $WinREAgent, $WINDOWS.~BT, …).
    if name.startswith("$"):
        return "os-owned"
    attributes = int(getattr(info, "st_file_attributes", 0) or 0)
    if attributes & FILE_ATTRIBUTE_HIDDEN:
        return "hidden"
    if attributes & FILE_ATTRIBUTE_SYSTEM:
        return "system"
    if has_protected_name(path, exact_names):
        return "baseline-protected-name"
    mounted, mount_error = mount_state(path, known_linux_mounts)
    if mount_error:
        return "mount-state-unverified"
    if mounted:
        return "nested-mount-point"
    for root in system_roots():
        if path.absolute() == root.absolute() or is_within(
            path.absolute(), root.absolute()
        ):
            return "os-owned"
    return None


def enumerate_root_children(
    target: Path,
    policy: dict[str, Any],
    known_linux_mounts: set[Path] | None = None,
) -> tuple[list[dict[str, str]], list[dict[str, str]]]:
    """List immediate volume-root entries into admitted vs skipped buckets.

    Enumerates the root once and never recurses. Admitted entries are
    directories that cleared every root-children exclusion; skipped entries
    carry the reason they were withheld.
    """
    exact_names = set(policy["protected_exact_names"])
    os_owned = volume_root_os_owned_names()
    admitted: list[dict[str, str]] = []
    skipped: list[dict[str, str]] = []
    try:
        with os.scandir(target) as iterator:
            children = sorted(iterator, key=lambda entry: entry.name.casefold())
    except OSError as exc:
        raise HygieneError(f"cannot enumerate volume root: {exc}") from exc
    for child in children:
        path = Path(child.path)
        reason = root_child_skip_reason(
            path,
            exact_names=exact_names,
            known_linux_mounts=known_linux_mounts,
            os_owned_names=os_owned,
        )
        if reason is None:
            admitted.append({"name": child.name, "path": str(path)})
        else:
            skipped.append({"name": child.name, "path": str(path), "reason": reason})
    return admitted, skipped


def root_child_names_case_sensitive(platform_key: str | None = None) -> bool:
    """Whether root-child selection must preserve exact basenames.

    Linux volume roots are case-sensitive; collapsing `/Cache` and `/cache` into
    one casefolded key would let `--root-child Cache` inventory the wrong sibling
    (or both). Windows and macOS volume roots are case-insensitive, so casefold
    matching remains the operator-friendly path there.
    """
    current = platform_key or os_key()
    return current == "linux"


def normalize_root_child_selection(
    selected: list[str],
    admitted: list[dict[str, str]],
    *,
    case_sensitive: bool | None = None,
) -> list[str]:
    """Map a human selection onto admitted basenames; reject anything else."""
    if not selected:
        raise HygieneError(
            "--root-children requires an explicit --root-child selection; "
            "a general clean-everything request is not selection"
        )
    sensitive = (
        root_child_names_case_sensitive() if case_sensitive is None else case_sensitive
    )
    if sensitive:
        by_name = {item["name"]: item["name"] for item in admitted}
    else:
        by_name = {item["name"].casefold(): item["name"] for item in admitted}
    resolved: list[str] = []
    seen: set[str] = set()
    for raw in selected:
        if not raw or raw in {".", ".."} or "/" in raw or "\\" in raw:
            raise HygieneError(
                f"--root-child must be an immediate basename, not a path: {raw!r}"
            )
        key = raw if sensitive else raw.casefold()
        if key not in by_name:
            raise HygieneError(
                f"--root-child {raw!r} is not an admitted immediate child directory "
                "of the OS-managed volume root"
            )
        canonical = by_name[key]
        seen_key = canonical if sensitive else canonical.casefold()
        if seen_key in seen:
            continue
        seen.add(seen_key)
        resolved.append(canonical)
    return resolved


def scan_tree(
    target: Path,
    policy: dict[str, Any],
    max_depth: int | None = None,
    *,
    root_children: list[str] | None = None,
) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    truncated: list[str] = []
    # Why each uninventoried path is uninventoried, so the per-child roll-up can
    # name the cause instead of reporting an undifferentiated gap.
    unwalked_reasons: dict[str, str] = {}
    repositories, repo_errors = discover_enclosing_git(target)
    exact_names = set(policy["protected_exact_names"])
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        errors.append({"path": ".", "error": mount_error})
    root_children_sensitive = root_child_names_case_sensitive()
    if root_children is None:
        allowed_root_children: set[str] | None = None
    elif root_children_sensitive:
        allowed_root_children = set(root_children)
    else:
        allowed_root_children = {name.casefold() for name in root_children}

    def visit(directory: Path, depth: int = 1) -> int | None:
        total = 0
        try:
            with os.scandir(directory) as iterator:
                children = sorted(iterator, key=lambda entry: entry.name.casefold())
        except OSError as exc:
            errors.append(
                {"path": directory.relative_to(target).as_posix(), "error": str(exc)}
            )
            # Unknown coverage — not an empty directory. Caller marks not-walked.
            return None
        for child in children:
            path = Path(child.path)
            # Root-children mode never walks the volume root as a whole: only
            # explicitly selected immediate directories are entered, and the
            # root's own files / excluded siblings are never inventoried.
            child_key = child.name if root_children_sensitive else child.name.casefold()
            if (
                allowed_root_children is not None
                and depth == 1
                and directory == target
                and child_key not in allowed_root_children
            ):
                continue
            relative = path.relative_to(target).as_posix()
            protections = hard_protection(path, target, exact_names, known_mounts)
            if path.name.casefold() in VCS_NAMES:
                repositories.append(path.parent.resolve())
            if any(
                glob_matches(relative, pattern)
                for pattern in policy["additional_protected_path_globs"]
            ):
                protections.append("consumer-protected-path")
            try:
                if is_linkish(path):
                    kind = "link"
                    data = metadata(path, kind)
                elif child.is_dir(follow_symlinks=False):
                    kind = "directory"
                    walked = True
                    if path.name.casefold() in VCS_NAMES:
                        subtotal: int | None = None
                        walked = False
                        truncated.append(relative)
                        unwalked_reasons[relative] = "vcs-boundary"
                    elif protections:
                        subtotal = None
                        walked = False
                        truncated.append(relative)
                        unwalked_reasons[relative] = "protected"
                    elif max_depth is not None and depth >= max_depth:
                        # A depth cut is the one truncation reason emptiness can
                        # answer. One cheap first-child probe (no recursion, no
                        # count) decides it: an empty directory has no
                        # descendants, so nothing is left uninventoried and its
                        # size is genuinely 0 rather than unknown — record it
                        # walked, and keep it out of truncated so the four
                        # downstream consumers stop treating a vacuously complete
                        # inventory as a coverage gap. Anything with a child, or
                        # any directory the probe cannot read, keeps the old
                        # not-walked marking. Scoped to THIS branch on purpose:
                        # the VCS and protection branches above refuse to walk
                        # for reasons emptiness does not answer, so an empty
                        # protected or VCS directory must still land in
                        # truncated.
                        if directory_has_child(path):
                            subtotal = None
                            walked = False
                            truncated.append(relative)
                            unwalked_reasons[relative] = "depth-cut"
                        else:
                            subtotal = 0
                    else:
                        subtotal = visit(path, depth + 1)
                        if subtotal is None:
                            # scandir failed inside this child: unknown, not empty.
                            walked = False
                            unwalked_reasons[relative] = "scan-error"
                    data = metadata(path, kind, subtotal, walked=walked)
                    # Truncated children contribute unknown, not zero: adding
                    # null as 0 was what made a truncated subtree look empty.
                    if subtotal is not None:
                        total += subtotal
                elif child.is_file(follow_symlinks=False):
                    kind = "file"
                    data = metadata(path, kind)
                    total += entry_logical_file_bytes(data)
                else:
                    kind = "other"
                    data = metadata(path, kind)
            except OSError as exc:
                errors.append({"path": relative, "error": str(exc)})
                unwalked_reasons[relative] = "scan-error"
                continue
            if len(entries) >= MAX_SNAPSHOT_ENTRIES:
                raise HygieneError(
                    f"snapshot exceeds {MAX_SNAPSHOT_ENTRIES} entries; rerun with "
                    "--max-depth or split the audit into bounded subtrees"
                )
            entries.append(
                {
                    "path": relative,
                    **data,
                    "hints": matching_hints(relative, path.name, policy),
                    "protected_reasons": sorted(set(protections)),
                }
            )
            if len(entries) % 25_000 == 0:
                print(f"scanned {len(entries)} entries...", file=sys.stderr)
        return total

    total_size = visit(target)
    if total_size is None:
        total_size = 0
        truncated.append(".")
    repositories = sorted(set(repositories))
    annotate_tracked(entries, target, repositories, truncated, repo_errors)
    reclaimable = reclaimable_local_bytes(entries)
    target_identity = metadata(target, "directory", total_size)
    # The target itself was walked, but any truncated child means the target's
    # byte roll-up is incomplete. Keep the known walked sum in logical_size and
    # surface the gap on the qualifier rather than claiming the target is empty.
    if truncated:
        target_identity["size_qualifiers"] = sorted(
            set(target_identity["size_qualifiers"] + ["not-walked"])
        )
    error_paths = {
        item["path"]
        for item in errors
        if isinstance(item, dict) and isinstance(item.get("path"), str)
    }
    # Everything the walk could not fully account for, from all three places it
    # can be recorded: an explicit truncation, a scan error (which never adds a
    # truncation and can leave no entry at all), and a `not-walked` record.
    unknown_paths = (
        set(truncated)
        | error_paths
        | {
            entry["path"]
            for entry in entries
            if "not-walked" in (entry.get("size_qualifiers") or [])
        }
    )
    payload: dict[str, Any] = {
        "schema_version": SCHEMA_VERSION,
        "engine": "disk-hygiene-python-1",
        "session_nonce": secrets.token_hex(16),
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "platform": os_key(),
        "target": str(target),
        "target_identity": target_identity,
        "target_logical_bytes": total_size,
        "target_reclaimable_local_bytes": reclaimable,
        "empty_directory_count": empty_directory_count(
            entries, error_paths=error_paths
        ),
        "policy": policy,
        "repositories": [str(repo) for repo in repositories],
        "repository_errors": repo_errors,
        "errors": errors,
        "max_depth": max_depth,
        "truncated_paths": sorted(truncated),
        "children_rollup": children_rollup(
            entries,
            unknown_paths=unknown_paths,
            unwalked_reasons=unwalked_reasons,
        ),
        "entries": sorted(entries, key=lambda entry: entry["path"]),
    }
    if root_children is not None:
        payload["root_children_mode"] = True
        payload["root_children_selected"] = list(root_children)
    return payload


def annotate_tracked(
    entries: list[dict[str, Any]],
    target: Path,
    repositories: list[Path],
    truncated: list[str],
    errors: list[str],
) -> None:
    git = shutil.which("git")
    if repositories and not git:
        errors.append("git-not-found")
        return
    by_path = {entry["path"]: entry for entry in entries}
    for repo in repositories:
        # Scope the query to what --max-depth actually inventoried: a bare
        # `ls-files` walks the whole repository regardless of the requested
        # scan bound. `base` restricts to target's own subtree (or "." when
        # target IS the repo, or a nested repo was discovered beneath
        # target); each truncated directory is then subtracted so a
        # bounded profile/root audit never pulls an unbounded repo-wide
        # tracked-file list just to annotate a handful of scanned entries.
        try:
            base = target.relative_to(repo).as_posix()
        except ValueError:
            base = "."
        pathspecs = [base]
        for relative_truncated in truncated:
            try:
                exclude = (target / relative_truncated).relative_to(repo).as_posix()
            except ValueError:
                continue
            pathspecs.append(f":(exclude){exclude}")
        try:
            run = subprocess.run(
                [
                    git,
                    "-C",
                    str(repo),
                    "ls-files",
                    "-z",
                    "--cached",
                    "--recurse-submodules",
                    "--",
                    *pathspecs,
                ],
                capture_output=True,
                timeout=20,
                check=False,
            )
        except (OSError, subprocess.SubprocessError) as exc:
            errors.append(f"{repo}: {exc}")
            continue
        if run.returncode != 0:
            errors.append(f"{repo}: git ls-files failed")
            continue
        for raw in run.stdout.split(b"\0"):
            if not raw:
                continue
            tracked = repo / os.fsdecode(raw)
            try:
                relative = tracked.relative_to(target).as_posix()
            except ValueError:
                continue
            entry = by_path.get(relative)
            if entry is not None:
                entry["protected_reasons"] = sorted(
                    set(entry["protected_reasons"] + ["vcs-tracked"])
                )


def entry_map(snapshot: dict[str, Any]) -> dict[str, dict[str, Any]]:
    entries = snapshot.get("entries")
    if not isinstance(entries, list):
        raise HygieneError("snapshot entries must be an array")
    result: dict[str, dict[str, Any]] = {}
    for entry in entries:
        if not isinstance(entry, dict) or not isinstance(entry.get("path"), str):
            raise HygieneError("every snapshot entry must be an object with a path")
        if entry["path"] in result:
            raise HygieneError(f"duplicate snapshot entry: {entry['path']}")
        result[entry["path"]] = entry
    return result


def subtree_names(relative: str, names: Iterable[str]) -> set[str]:
    """The snapshot paths that ARE ``relative`` or sit beneath it.

    One containment rule for every lane that asks "what did the scan record for
    this candidate" — the preview's and handoff-verify's expected-path sets and
    the apply lane's removal list — so the three cannot disagree about a
    candidate's extent. Prefix matching is on the "/"-terminated name, so a
    sibling like ``cache-old`` is never read as a child of ``cache``.
    """
    return {
        name for name in names if name == relative or name.startswith(relative + "/")
    }


def overlaps_truncated(relative: str, truncated_paths: set[str]) -> bool:
    """Whether ``relative`` is, contains, or lives under a truncated scan path.

    Either direction disqualifies: a truncated ancestor means this path's own
    subtree was never inventoried, and a truncated descendant means part of it
    was not. Shared by preview and handoff-verify, which must agree on which
    candidates the snapshot cannot speak for.
    """
    return any(
        name == relative
        or name.startswith(relative + "/")
        or relative.startswith(name + "/")
        for name in truncated_paths
    )


def snapshot_protection_globs(snapshot: dict[str, Any]) -> list[str]:
    """Consumer protection globs a snapshot's policy recorded, strings only.

    Read from the snapshot rather than from live policy on purpose: an approved
    snapshot must stay previewable under the protections it was scanned with.
    Non-string members are dropped here so the three validation lanes cannot
    differ on how they tolerate a hand-edited policy block.
    """
    return [
        pattern
        for pattern in snapshot.get("policy", {}).get(
            "additional_protected_path_globs", []
        )
        if isinstance(pattern, str)
    ]


def validate_plan(
    plan: dict[str, Any], entries: dict[str, dict[str, Any]]
) -> list[dict[str, Any]]:
    if plan.get("version") != SCHEMA_VERSION:
        raise HygieneError("plan version must be 1")
    tier = plan.get("tier")
    if tier not in TIERS:
        raise HygieneError("plan tier must be high, medium, or low")
    candidates = plan.get("candidates")
    if not isinstance(candidates, list) or not candidates:
        raise HygieneError("plan candidates must be a non-empty array")
    normalized: list[dict[str, Any]] = []
    seen: list[PurePosixPath] = []
    for candidate in candidates:
        if not isinstance(candidate, dict):
            raise HygieneError("each candidate must be an object")
        required = {
            "path",
            "tier",
            "provenance",
            "reason",
            "evidence",
            "why_not_work_product",
            "risk",
            "owner",
        }
        if not required.issubset(candidate):
            raise HygieneError(
                f"candidate is missing: {', '.join(sorted(required - set(candidate)))}"
            )
        if candidate["tier"] != tier:
            raise HygieneError("one plan may contain exactly one confidence tier")
        relative = candidate["path"]
        if not isinstance(relative, str) or not relative or relative in {".", "/"}:
            raise HygieneError("candidate path must be a non-root relative path")
        pure = PurePosixPath(relative)
        if pure.is_absolute() or ".." in pure.parts or relative not in entries:
            raise HygieneError(
                f"candidate path is outside or absent from snapshot: {relative}"
            )
        if any(
            pure == prior or pure in prior.parents or prior in pure.parents
            for prior in seen
        ):
            raise HygieneError(f"candidate paths overlap: {relative}")
        seen.append(pure)
        if (
            not isinstance(candidate["provenance"], str)
            or not candidate["provenance"].strip()
        ):
            raise HygieneError(f"candidate needs provenance: {relative}")
        if not isinstance(candidate["reason"], str) or not candidate["reason"].strip():
            raise HygieneError(f"candidate needs a reason: {relative}")
        if (
            not isinstance(candidate["why_not_work_product"], str)
            or not candidate["why_not_work_product"].strip()
        ):
            raise HygieneError(f"candidate needs work-product analysis: {relative}")
        if not isinstance(candidate["risk"], str) or not candidate["risk"].strip():
            raise HygieneError(f"candidate needs a risk assessment: {relative}")
        if (
            not isinstance(candidate["evidence"], list)
            or not candidate["evidence"]
            or not all(
                isinstance(value, str) and value.strip()
                for value in candidate["evidence"]
            )
        ):
            raise HygieneError(
                f"candidate needs at least one evidence item: {relative}"
            )
        owner = candidate["owner"]
        if not isinstance(owner, str) or not owner:
            raise HygieneError(
                f"candidate owner must be named or unmanaged: {relative}"
            )
        if owner != "unmanaged":
            # Managed candidates are permanently report-only (preview and apply
            # block them unconditionally). This gate exists so the report can
            # name a proven-runnable native-GC command, and so managed state
            # whose native GC is not even eligible is never proposed at all.
            native = candidate.get("native_gc_evidence")
            if (
                not isinstance(native, dict)
                or native.get("result") != "eligible"
                or not isinstance(native.get("command"), str)
                or not native["command"].strip()
            ):
                raise HygieneError(
                    f"managed candidate lacks native-GC eligibility evidence: {relative}"
                )
        normalized.append(candidate)
    return normalized


def validate_handoff_paths(
    payload: dict[str, Any], entries: dict[str, dict[str, Any]]
) -> list[str]:
    """Structurally validate a manual-handoff approved-path list.

    Same containment rules as plan candidates (relative, non-root, no
    traversal, present in the snapshot, non-overlapping) without the plan's
    tier/evidence envelope: the handoff list is the human-approved exact path
    list, and the audit report — not this file — carries the evidence.
    """
    if payload.get("version") != SCHEMA_VERSION:
        raise HygieneError("paths file version must be 1")
    paths = payload.get("paths")
    if not isinstance(paths, list) or not paths:
        raise HygieneError("paths must be a non-empty array")
    normalized: list[str] = []
    seen: list[PurePosixPath] = []
    for relative in paths:
        if not isinstance(relative, str) or not relative or relative in {".", "/"}:
            raise HygieneError("approved path must be a non-root relative path")
        pure = PurePosixPath(relative)
        if pure.is_absolute() or ".." in pure.parts or relative not in entries:
            raise HygieneError(
                f"approved path is outside or absent from snapshot: {relative}"
            )
        if any(
            pure == prior or pure in prior.parents or prior in pure.parents
            for prior in seen
        ):
            raise HygieneError(f"approved paths overlap: {relative}")
        seen.append(pure)
        normalized.append(relative)
    return normalized


def validate_vcs_evidence(
    payload: dict[str, Any], approved: list[str]
) -> dict[str, dict[str, Any]]:
    """Validate proof-source locations; live commands establish every fact."""
    if set(payload) != {"version", "repositories"}:
        raise HygieneError("VCS evidence must contain exactly version/repositories")
    if payload.get("version") != SCHEMA_VERSION:
        raise HygieneError("VCS evidence version must be 1")
    repositories = payload.get("repositories")
    if not isinstance(repositories, list) or not repositories:
        raise HygieneError("VCS evidence repositories must be a non-empty array")
    approved_paths = [PurePosixPath(value) for value in approved]
    normalized: dict[str, dict[str, Any]] = {}
    for item in repositories:
        if not isinstance(item, dict) or set(item) != {
            "path",
            "remote",
            "stash_copies",
        }:
            raise HygieneError(
                "each VCS evidence repository must contain exactly "
                "path/remote/stash_copies"
            )
        relative = item["path"]
        pure = PurePosixPath(relative) if isinstance(relative, str) else None
        if (
            pure is None
            or not relative
            or relative in {".", "/"}
            or pure.is_absolute()
            or ".." in pure.parts
            or not any(path == pure or path in pure.parents for path in approved_paths)
        ):
            raise HygieneError(
                f"VCS evidence repository is outside approved paths: {relative}"
            )
        if relative in normalized:
            raise HygieneError(f"duplicate VCS evidence repository: {relative}")
        remote = item["remote"]
        if remote is not None and (
            not isinstance(remote, str)
            or not remote
            or remote.startswith("-")
            or any(character.isspace() for character in remote)
        ):
            raise HygieneError(
                f"VCS evidence remote must be null or a literal name: {relative}"
            )
        copies = item["stash_copies"]
        if (
            not isinstance(copies, list)
            or not all(
                isinstance(value, str)
                and value
                and Path(value).expanduser().is_absolute()
                for value in copies
            )
            or len(set(copies)) != len(copies)
        ):
            raise HygieneError(
                f"stash_copies must be unique absolute paths: {relative}"
            )
        normalized[relative] = {
            "path": relative,
            "remote": remote,
            "stash_copies": copies,
        }
    return normalized


def current_descendants(
    root: Path, candidate: Path, *, opaque_git_metadata: bool = False
) -> set[str]:
    paths: set[str] = set()
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        raise HygieneError(mount_error)

    def visit(path: Path) -> None:
        paths.add(path.relative_to(root).as_posix())
        mounted, error = mount_state(path, known_mounts)
        if error:
            raise HygieneError(error)
        if (
            is_linkish(path)
            or not path.is_dir()
            or mounted
            or (opaque_git_metadata and path.name.casefold() == GIT_METADATA_NAME)
        ):
            return
        with os.scandir(path) as iterator:
            children = [Path(entry.path) for entry in iterator]
        for child in children:
            visit(child)

    visit(candidate)
    return paths


def same_identity(path: Path, entry: dict[str, Any]) -> bool:
    try:
        info = path.lstat()
    except OSError:
        return False
    return same_stat_identity(info, entry)


def same_stat_identity(info: os.stat_result, entry: dict[str, Any]) -> bool:
    if is_linkish_stat(info):
        kind = "link"
    elif stat.S_ISDIR(info.st_mode):
        kind = "directory"
    elif stat.S_ISREG(info.st_mode):
        kind = "file"
    else:
        kind = "other"
    checks = (
        kind == entry.get("kind"),
        info.st_size == entry.get("stat_size"),
        info.st_mtime_ns == entry.get("mtime_ns"),
        info.st_dev == entry.get("device"),
        info.st_ino == entry.get("inode"),
        stat.S_IFMT(info.st_mode) == entry.get("mode"),
    )
    # File hard-link count is part of reclaimability. A new name after scan
    # leaves size/mtime/dev/ino/mode unchanged, so identity must notice nlink
    # or preview/apply would still treat the full size as reclaimable.
    if kind == "file":
        checks = (*checks, int(info.st_nlink) == entry.get("nlink"))
    return all(checks)


def same_object_identity(info: os.stat_result, entry: dict[str, Any]) -> bool:
    """Compare stable object identity without mutable directory size/timestamps."""
    return all(
        (
            stat.S_ISDIR(info.st_mode) and entry.get("kind") == "directory",
            info.st_dev == entry.get("device"),
            info.st_ino == entry.get("inode"),
            stat.S_IFMT(info.st_mode) == entry.get("mode"),
        )
    )


def same_open_object(left: os.stat_result, right: os.stat_result) -> bool:
    """Compare stable identity fields for two observations of one object."""
    return all(
        (
            left.st_dev == right.st_dev,
            left.st_ino == right.st_ino,
            stat.S_IFMT(left.st_mode) == stat.S_IFMT(right.st_mode),
        )
    )


def same_removal_identity(path: Path, entry: dict[str, Any]) -> bool:
    """Allow expected directory metadata churn while preserving object identity."""
    try:
        info = path.lstat()
    except OSError:
        return False
    if entry.get("kind") == "directory":
        return same_object_identity(info, entry)
    return same_stat_identity(info, entry)


def marker_exists(path: Path, errors: list[str]) -> bool:
    try:
        path.lstat()
        return True
    except FileNotFoundError:
        return False
    except OSError as exc:
        errors.append(f"{path}: marker state unverified: {exc}")
        return False


def discover_current_repositories(
    target: Path, candidate: Path
) -> tuple[list[Path], list[str]]:
    """Rediscover enclosing and nested repository markers from live state."""
    marker_roots: set[Path] = set()
    errors: list[str] = []
    current = candidate if candidate.is_dir() else candidate.parent
    while True:
        git_marker = current / ".git"
        if marker_exists(git_marker, errors):
            marker_roots.add(current)
        if any(marker_exists(current / name, errors) for name in (".hg", ".svn")):
            errors.append(f"{current}: non-Git VCS state is not independently verified")
        if current.parent == current:
            break
        current = current.parent

    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        errors.append(mount_error)

    def visit(directory: Path) -> None:
        try:
            with os.scandir(directory) as iterator:
                children = list(iterator)
        except OSError as exc:
            errors.append(f"{directory}: {exc}")
            return
        names = {entry.name.casefold() for entry in children}
        if names & VCS_NAMES:
            if ".git" not in names:
                errors.append(
                    f"{directory}: non-Git VCS state is not independently verified"
                )
            marker_roots.add(directory)
            return
        for entry in children:
            path = Path(entry.path)
            mounted, current_mount_error = mount_state(path, known_mounts)
            if current_mount_error:
                errors.append(current_mount_error)
                return
            if (
                entry.is_dir(follow_symlinks=False)
                and not is_linkish(path)
                and not mounted
            ):
                visit(path)

    if candidate.is_dir() and not is_linkish(candidate):
        visit(candidate)

    git = shutil.which("git")
    if not git:
        return sorted(marker_roots), (["git-not-found"] if marker_roots else errors)

    run = subprocess.run(
        [
            git,
            "-C",
            str(candidate.parent if candidate.is_file() else candidate),
            "rev-parse",
            "--show-toplevel",
        ],
        capture_output=True,
        text=True,
        timeout=10,
        check=False,
    )
    if run.returncode == 0 and run.stdout.strip():
        marker_roots.add(Path(run.stdout.strip()).resolve())
    elif marker_roots:
        errors.append("git-worktree-state-unverified")
    return sorted(marker_roots), errors


def tracked_blocker(candidate: Path, target: Path) -> str | None:
    repositories, errors = discover_current_repositories(target, candidate)
    if errors:
        return "vcs-state-unverified"
    git = shutil.which("git")
    if repositories and not git:
        return "git-not-found"
    for repo in repositories:
        if is_within(candidate, repo):
            relative = candidate.relative_to(repo).as_posix()
            pathspec = relative + "/" if candidate.is_dir() else relative
        elif is_within(repo, candidate):
            pathspec = "."
        else:
            continue
        run = subprocess.run(
            [git, "-C", str(repo), "ls-files", "-z", "--cached", "--", pathspec],
            capture_output=True,
            timeout=20,
            check=False,
        )
        if run.returncode != 0:
            return "vcs-state-unverified"
        if run.stdout:
            return "vcs-tracked-content"
    return None


def run_git(repo: Path, *arguments: str) -> subprocess.CompletedProcess[str]:
    git = shutil.which("git")
    if not git:
        raise HygieneError("git-not-found")
    environment = os.environ.copy()
    # `git status` may otherwise refresh the index and write an optional
    # lock/index update. Evidence collection is a read-only handoff operation.
    environment["GIT_OPTIONAL_LOCKS"] = "0"
    return subprocess.run(
        [git, "-C", str(repo), *arguments],
        capture_output=True,
        text=True,
        timeout=20,
        check=False,
        env=environment,
    )


def github_remote_repository(url: str) -> tuple[str, str] | None:
    match = GITHUB_REMOTE_RE.fullmatch(url.strip())
    if match is None:
        return None
    repository = match.group("repo")
    if repository.casefold().endswith(".git"):
        repository = repository[:-4]
    if not repository:
        return None
    return match.group("owner"), repository


def verify_github_remote_head(
    repo: Path, remote: str, sha: str
) -> tuple[bool, dict[str, str]]:
    """Confirm one local head through the GitHub commits API, never by ref name."""
    # Read the literal declaration rather than `git remote get-url`, which
    # expands global `insteadOf` transport rewrites and can hide github.com.
    remote_url = run_git(repo, "config", "--get", f"remote.{remote}.url")
    if remote_url.returncode != 0 or not remote_url.stdout.strip():
        return False, {"sha": sha, "error": "remote-url-unverified"}
    coordinates = github_remote_repository(remote_url.stdout.strip())
    if coordinates is None:
        return False, {"sha": sha, "error": "remote-provider-unsupported"}
    gh = shutil.which("gh")
    if not gh:
        return False, {"sha": sha, "error": "gh-not-found"}
    owner, repository = coordinates
    try:
        checked = subprocess.run(
            [
                gh,
                "api",
                "--method",
                "GET",
                f"repos/{owner}/{repository}/commits/{sha}",
                "--jq",
                ".sha",
            ],
            capture_output=True,
            text=True,
            timeout=20,
            check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        return False, {"sha": sha, "error": f"provider-query-failed: {exc}"}
    confirmed = (
        checked.returncode == 0 and checked.stdout.strip().casefold() == sha.casefold()
    )
    detail = {
        "sha": sha,
        "remote": remote,
        "repository": f"{owner}/{repository}",
    }
    if not confirmed:
        detail["error"] = "remote-head-unconfirmed"
    return confirmed, detail


def local_head_shas(repo: Path) -> tuple[list[dict[str, str]], str | None]:
    """Return every local branch head, plus a detached HEAD when present."""
    branches = run_git(
        repo, "for-each-ref", "--format=%(refname:short)%09%(objectname)", "refs/heads"
    )
    if branches.returncode != 0:
        return [], "local-heads-unverified"
    heads: list[dict[str, str]] = []
    for line in branches.stdout.splitlines():
        try:
            name, sha = line.split("\t", 1)
        except ValueError:
            return [], "local-heads-unverified"
        if not re.fullmatch(r"[0-9a-fA-F]{40,64}", sha):
            return [], "local-heads-unverified"
        heads.append({"name": name, "sha": sha.casefold()})
    symbolic = run_git(repo, "symbolic-ref", "-q", "HEAD")
    if symbolic.returncode not in {0, 1}:
        return [], "local-heads-unverified"
    if symbolic.returncode == 1:
        detached = run_git(repo, "rev-parse", "--verify", "HEAD^{commit}")
        sha = detached.stdout.strip()
        if detached.returncode != 0 or not re.fullmatch(r"[0-9a-fA-F]{40,64}", sha):
            return [], "local-heads-unverified"
        heads.append({"name": "HEAD", "sha": sha.casefold()})
    unique = {(item["name"], item["sha"]): item for item in heads}
    return sorted(unique.values(), key=lambda item: (item["name"], item["sha"])), None


def stash_shas(repo: Path) -> tuple[list[str], str | None]:
    stashes = run_git(repo, "stash", "list", "--format=%H")
    if stashes.returncode != 0:
        return [], "stashes-unverified"
    result = [value.casefold() for value in stashes.stdout.splitlines() if value]
    if not all(re.fullmatch(r"[0-9a-fA-F]{40,64}", value) for value in result):
        return [], "stashes-unverified"
    return result, None


def verify_stash_copy(
    source_candidate: Path,
    copy_value: str,
    approved_paths: list[Path],
    source_common_dir: Path,
) -> tuple[Path | None, set[str], str | None]:
    copy_input = Path(copy_value).expanduser().absolute()
    if has_linkish_component(copy_input):
        return None, set(), "stash-copy-link-or-reparse"
    try:
        copy = copy_input.resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    if (
        not copy.is_dir()
        or is_within(copy, source_candidate)
        or any(is_within(copy, approved) for approved in approved_paths)
    ):
        return None, set(), "stash-copy-not-independent"
    top = run_git(copy, "rev-parse", "--show-toplevel")
    if top.returncode != 0 or not top.stdout.strip():
        return None, set(), "stash-copy-not-a-worktree"
    try:
        top_path = Path(top.stdout.strip()).resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    if top_path != copy:
        return None, set(), "stash-copy-root-mismatch"
    common = run_git(copy, "rev-parse", "--path-format=absolute", "--git-common-dir")
    if common.returncode != 0 or not common.stdout.strip():
        return None, set(), "stash-copy-unreadable"
    try:
        copy_common = Path(common.stdout.strip()).resolve(strict=True)
    except OSError:
        return None, set(), "stash-copy-unreadable"
    # Linked worktrees share the source common dir (and therefore stash refs).
    # Reject any copy whose Git storage is the source store or lives under the
    # candidate about to be deleted.
    if (
        copy_common == source_common_dir
        or is_within(copy_common, source_common_dir)
        or is_within(source_common_dir, copy_common)
        or is_within(copy_common, source_candidate)
    ):
        return None, set(), "stash-copy-not-independent"
    stashes, error = stash_shas(copy)
    return copy, set(stashes), error


def checkout_repository_paths(current_paths: set[str], target: Path) -> set[Path]:
    repositories: set[Path] = set()
    for relative in current_paths:
        pure = PurePosixPath(relative)
        if pure.name.casefold() != GIT_METADATA_NAME:
            continue
        repository_relative = pure.parent
        if str(repository_relative) == ".":
            continue
        repositories.add(
            target.joinpath(*repository_relative.parts).resolve(strict=False)
        )
    return repositories


def verify_vcs_checkout_evidence(
    target: Path,
    candidate: Path,
    current_paths: set[str],
    configurations: dict[str, dict[str, Any]],
    approved: list[str],
) -> dict[str, Any]:
    """Verify the complete live evidence bundle before relaxing Git blockers."""
    gates: dict[str, dict[str, Any]] = {
        name: {"status": "failed"} for name in VCS_EVIDENCE_GATE_NAMES
    }
    gates["exact-path-operator-approval"] = {
        "status": "passed",
        "source": "handoff-paths",
        "path": candidate.relative_to(target).as_posix(),
    }
    blockers: set[str] = set()
    live_repositories = checkout_repository_paths(current_paths, target)
    configured_repositories = {
        target.joinpath(*PurePosixPath(relative).parts).resolve(strict=False)
        for relative in configurations
    }
    if (
        not live_repositories
        or live_repositories != configured_repositories
        or any(not is_within(repo, candidate) for repo in live_repositories)
    ):
        blockers.add("vcs-evidence-repository-set-mismatch")

    status_details: list[dict[str, Any]] = []
    head_details: list[dict[str, Any]] = []
    stash_details: list[dict[str, Any]] = []
    status_passed = not blockers
    heads_passed = not blockers
    stashes_passed = not blockers
    approved_paths = [
        target.joinpath(*PurePosixPath(value).parts).resolve(strict=False)
        for value in approved
    ]
    for repo in sorted(live_repositories & configured_repositories):
        relative = repo.relative_to(target).as_posix()
        config = configurations[relative]
        repository_detail: dict[str, Any] = {"repository": relative}

        top = run_git(repo, "rev-parse", "--show-toplevel")
        common = run_git(
            repo, "rev-parse", "--path-format=absolute", "--git-common-dir"
        )
        try:
            top_path = Path(top.stdout.strip()).resolve(strict=True)
            common_path = Path(common.stdout.strip()).resolve(strict=True)
        except OSError:
            top_path = Path()
            common_path = Path()
        if (
            top.returncode != 0
            or common.returncode != 0
            or top_path != repo
            or not is_within(common_path, candidate)
        ):
            blockers.add("vcs-evidence-git-boundary-unverified")
            status_passed = heads_passed = stashes_passed = False
            repository_detail["status"] = "git-boundary-unverified"
            status_details.append(repository_detail)
            continue

        status = run_git(
            repo,
            "status",
            "--porcelain=v1",
            "--untracked-files=all",
            "--ignored=matching",
            "--ignore-submodules=none",
        )
        clean = status.returncode == 0 and not status.stdout
        repository_detail["status"] = "clean" if clean else "not-clean-or-unverified"
        status_details.append(repository_detail)
        if not clean:
            status_passed = False
            blockers.add("vcs-evidence-status-not-clean")

        heads, head_error = local_head_shas(repo)
        if head_error:
            heads_passed = False
            blockers.add("vcs-evidence-local-heads-unverified")
        elif heads and config["remote"] is None:
            heads_passed = False
            blockers.add("vcs-evidence-remote-not-declared")
        else:
            for head in heads:
                confirmed, detail = verify_github_remote_head(
                    repo, config["remote"], head["sha"]
                )
                detail["repository_path"] = relative
                detail["local_head"] = head["name"]
                head_details.append(detail)
                if not confirmed:
                    heads_passed = False
                    blockers.add("vcs-evidence-remote-head-unconfirmed")

        stashes, stash_error = stash_shas(repo)
        if stash_error:
            stashes_passed = False
            blockers.add("vcs-evidence-stashes-unverified")
            continue
        copy_stashes: dict[str, set[str]] = {}
        for copy_value in config["stash_copies"]:
            try:
                copy, copy_values, copy_error = verify_stash_copy(
                    candidate, copy_value, approved_paths, common_path
                )
            except (OSError, subprocess.SubprocessError, HygieneError):
                copy, copy_values, copy_error = None, set(), "stash-copy-unverified"
            if copy_error:
                stashes_passed = False
                blockers.add("vcs-evidence-stash-copy-unverified")
                continue
            assert copy is not None
            copy_stashes[str(copy)] = copy_values
        for sha in stashes:
            duplicated_at = sorted(
                path for path, values in copy_stashes.items() if sha in values
            )
            stash_details.append(
                {
                    "repository_path": relative,
                    "sha": sha,
                    "duplicated_at": duplicated_at,
                }
            )
            if not duplicated_at:
                stashes_passed = False
                blockers.add("vcs-evidence-stash-not-duplicated")

    gates["git-status-porcelain-empty"] = {
        "status": "passed" if status_passed else "failed",
        "repositories": status_details,
    }
    gates["all-local-heads-on-remote"] = {
        "status": "passed" if heads_passed else "failed",
        "heads": head_details,
    }
    gates["all-stashes-duplicated"] = {
        "status": "passed" if stashes_passed else "failed",
        "stashes": stash_details,
    }
    verified = not blockers and all(
        gates[name]["status"] == "passed" for name in VCS_EVIDENCE_GATE_NAMES
    )
    return {
        "status": "verified" if verified else "failed",
        "gates": gates,
        "blockers": sorted(blockers),
        "repositories": sorted(
            repo.relative_to(target).as_posix() for repo in live_repositories
        ),
    }


def evidence_adjusted_protections(
    protections: Iterable[str],
    path: Path,
    target: Path,
    repository_paths: Iterable[Path],
    exact_names: set[str],
) -> list[str]:
    """Relax only Git-marker protections, never another protected-name class."""
    adjusted = set(protections)
    metadata_roots = [repo / GIT_METADATA_NAME for repo in repository_paths]
    if not any(is_within(path, metadata) for metadata in metadata_roots):
        return sorted(adjusted)
    adjusted.discard("vcs-metadata")
    current = path
    non_git_protected_name = False
    while is_within(current, target):
        if current.name.casefold() != GIT_METADATA_NAME and has_protected_name(
            current, exact_names
        ):
            non_git_protected_name = True
            break
        if current == target:
            break
        current = current.parent
    if not non_git_protected_name:
        adjusted.discard("baseline-protected-name")
    return sorted(adjusted)


def execution_blockers() -> list[str]:
    """Return reasons why the mutation lane cannot be proven safe on this host."""
    if os_key() != "linux":
        return ["execution-platform-unsupported"]
    required = (os.open, os.stat, os.unlink, os.rmdir)
    if not all(function in os.supports_dir_fd for function in required):
        return ["dirfd-anchoring-unavailable"]
    if os.scandir not in os.supports_fd:
        return ["dirfd-anchoring-unavailable"]
    if not hasattr(os, "O_DIRECTORY") or not hasattr(os, "O_NOFOLLOW"):
        return ["dirfd-anchoring-unavailable"]
    _, error = linux_mount_points()
    return ["mount-state-unverified"] if error else []


def windows_handle_state(path: Path) -> tuple[str, str | None]:
    kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
    create_file = kernel32.CreateFileW
    create_file.argtypes = [
        ctypes.c_wchar_p,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_void_p,
        ctypes.c_uint32,
        ctypes.c_uint32,
        ctypes.c_void_p,
    ]
    create_file.restype = ctypes.c_void_p
    flags = FILE_FLAG_BACKUP_SEMANTICS if path.is_dir() else FILE_ATTRIBUTE_NORMAL
    # Share mode 0 requests exclusive access; an already-open file fails the probe.
    handle = create_file(str(path), 0, 0, None, OPEN_EXISTING, flags, None)
    invalid = ctypes.c_void_p(-1).value
    if handle == invalid:
        error = ctypes.get_last_error()
        if error in {32, 33}:
            return "open", f"win32-error-{error}"
        if error in {5, 1314}:
            return "needs_elevation", f"win32-error-{error}"
        return "unverified", f"win32-error-{error}"
    kernel32.CloseHandle(ctypes.c_void_p(handle))
    return "clear", None


def posix_handle_state(path: Path) -> tuple[str, str | None]:
    lsof = shutil.which("lsof")
    if not lsof:
        return "unverified", "lsof-not-found"
    command = [lsof, "-Fn"] + (
        ["+D", str(path)] if path.is_dir() else ["--", str(path)]
    )
    try:
        run = subprocess.run(
            command, capture_output=True, text=True, timeout=20, check=False
        )
    except subprocess.TimeoutExpired:
        return "unverified", "lsof-timeout"
    if run.stderr.strip():
        return "unverified", f"lsof-diagnostic: {run.stderr.strip()[:200]}"
    if run.returncode == 0 and run.stdout.strip():
        return "open", "lsof-reported-open-file"
    if run.returncode == 1 and not run.stdout.strip():
        return "clear", None
    return "unverified", f"lsof-exit-{run.returncode}"


def handle_state(path: Path) -> tuple[str, str | None]:
    return windows_handle_state(path) if os.name == "nt" else posix_handle_state(path)


def candidate_handle_state(
    target: Path, path: Path, expected_paths: set[str]
) -> tuple[str, str | None]:
    if os.name != "nt":
        return handle_state(path)
    for relative in sorted(expected_paths):
        state, detail = handle_state(target.joinpath(*PurePosixPath(relative).parts))
        if state != "clear":
            return state, f"{relative}: {detail or state}"
    return "clear", None


def snapshot_digest(snapshot: dict[str, Any]) -> str:
    canonical = json.dumps(snapshot, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(canonical).hexdigest()


def approval_token(snapshot: dict[str, Any], plan: dict[str, Any]) -> str:
    material = {
        "snapshot": snapshot_digest(snapshot),
        "nonce": snapshot.get("session_nonce"),
        "tier": plan.get("tier"),
        "candidates": plan.get("candidates"),
    }
    return hashlib.sha256(
        json.dumps(material, sort_keys=True, separators=(",", ":")).encode()
    ).hexdigest()[:24]


def resolve_snapshot_target(snapshot: dict[str, Any]) -> tuple[Path, set[Path]]:
    """Re-validate the snapshot's target root against live state and return it.

    Shared by preview and handoff-verify: both must refuse a snapshot whose
    target root drifted, became a link, a mount point, an OS-managed root, or a
    protected shell folder since the scan. The root is held to the same stable
    device/inode/type identity as directory candidates, not to stat identity:
    a directory's mtime and size flip whenever any direct child is added or
    removed, so any unrelated write into a live target during the approval
    window would otherwise abort the run.

    Root-children mode is the sole exception to the OS-managed-root veto: the
    snapshot target is the volume root, but the inventory only covers explicitly
    selected immediate children — never a recursive walk of the root itself.
    """
    if (
        snapshot.get("schema_version") != SCHEMA_VERSION
        or snapshot.get("engine") != "disk-hygiene-python-1"
    ):
        raise HygieneError("unsupported snapshot version")
    target_input = Path(snapshot.get("target", "")).absolute()
    if has_linkish_component(target_input):
        raise HygieneError("snapshot target now traverses a link or reparse point")
    target = target_input.resolve(strict=True)
    known_mounts, mount_error = linux_mount_points()
    target_mounted, target_mount_error = mount_state(target, known_mounts)
    if mount_error or target_mount_error:
        raise HygieneError("snapshot target mount state is unverified")
    root_children_mode = bool(snapshot.get("root_children_mode"))
    if is_os_managed_target(target) and not root_children_mode:
        raise HygieneError("snapshot target is now an OS-managed root")
    if root_children_mode:
        if not is_volume_root(target) or not is_os_managed_target(target):
            raise HygieneError(
                "root-children snapshot target must remain an OS-managed volume root"
            )
        selected = snapshot.get("root_children_selected")
        if not isinstance(selected, list) or not selected:
            raise HygieneError("root-children snapshot is missing its selection")
        if any(not isinstance(name, str) or not name for name in selected):
            raise HygieneError("root-children snapshot selection is invalid")
    if target_mounted and not is_volume_root(target):
        raise HygieneError("snapshot target is a mount point")
    if has_protected_path_component(target, baseline_protected_names()):
        raise HygieneError(
            "snapshot target is now a protected shell-folder or profile-hive root"
        )
    identity = snapshot.get("target_identity", {})
    try:
        info = target.lstat()
    except OSError as exc:
        raise HygieneError(f"target root state is unverified: {exc}")
    if not same_object_identity(info, identity):
        raise HygieneError("target root was replaced since the snapshot")
    return target, known_mounts


def preview(snapshot: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    baseline_exact_names = baseline_protected_names()
    target, known_mounts = resolve_snapshot_target(snapshot)
    entries = entry_map(snapshot)
    candidates = validate_plan(plan, entries)
    truncated_paths = {
        value for value in snapshot.get("truncated_paths", []) if isinstance(value, str)
    }
    exact_names = baseline_exact_names | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    globs = snapshot_protection_globs(snapshot)
    root_children_sensitive = root_child_names_case_sensitive(snapshot.get("platform"))

    def root_child_key(name: str) -> str:
        return name if root_children_sensitive else name.casefold()

    selected_root_children = {
        root_child_key(name)
        for name in snapshot.get("root_children_selected", [])
        if isinstance(name, str)
    }

    results = []
    blocked = False
    for candidate in candidates:
        relative = candidate["path"]
        path = target.joinpath(*PurePosixPath(relative).parts)
        blockers = hard_protection(path, target, exact_names, known_mounts)
        blockers.extend(execution_blockers())
        if candidate["owner"] != "unmanaged":
            blockers.append("native-managed-report-only")
        if overlaps_truncated(relative, truncated_paths):
            blockers.append("truncated-not-inventoried")
        if snapshot.get("root_children_mode"):
            parts = PurePosixPath(relative).parts
            if not parts or root_child_key(parts[0]) not in selected_root_children:
                blockers.append("outside-root-children-selection")
        expected_paths = subtree_names(relative, entries)
        if "truncated-not-inventoried" in blockers:
            # A truncated candidate is already hard-blocked from planning above;
            # walking its live subtree here would be the same unbounded
            # traversal --max-depth exists to avoid, for a candidate that can
            # never become approvable anyway.
            current_paths = expected_paths
        else:
            try:
                current_paths = current_descendants(target, path)
            except PermissionError:
                current_paths = set()
                blockers.append("needs-elevation")
            except (OSError, HygieneError):
                current_paths = set()
                blockers.append("filesystem-state-unverified")
        if current_paths != expected_paths:
            blockers.append("changed-since-scan")
        for name in expected_paths:
            entry = entries[name]
            current = target.joinpath(*PurePosixPath(name).parts)
            if not same_identity(current, entry):
                blockers.append("changed-since-scan")
            blockers.extend(hard_protection(current, target, exact_names, known_mounts))
            relative_current = current.relative_to(target).as_posix()
            if any(glob_matches(relative_current, pattern) for pattern in globs):
                blockers.append("consumer-protected-path")
        if "truncated-not-inventoried" in blockers:
            # Same rationale as the current_descendants short-circuit above: a
            # truncated candidate can never leave "blocked" state, so skip the
            # live VCS-repository walk (discover_current_repositories, an
            # unbounded recursive scandir) and the live handle-state probe
            # (POSIX's `lsof +D`, also unbounded) instead of running them
            # against a subtree --max-depth was never asked to inventory.
            state, detail = "unverified", "truncated-not-inventoried"
        else:
            vcs = tracked_blocker(path, target)
            if vcs:
                blockers.append(vcs)
            state, detail = candidate_handle_state(target, path, expected_paths)
            if state != "clear":
                blockers.append(
                    {"open": "live-handle", "needs_elevation": "needs-elevation"}.get(
                        state, "handle-state-unverified"
                    )
                )
        blockers = sorted(set(blockers))
        candidate_entry = entries[relative]
        logical_bytes = sum(
            entry_logical_file_bytes(entries[name]) for name in expected_paths
        )
        reclaimable_bytes = sum(
            value
            for name in expected_paths
            if (value := entry_reclaimable_local_bytes(entries[name])) is not None
        )
        results.append(
            {
                "path": relative,
                "tier": plan["tier"],
                "provenance": candidate["provenance"],
                "reason": candidate["reason"],
                "why_not_work_product": candidate["why_not_work_product"],
                "risk": candidate["risk"],
                "empty_directory": entry_is_empty_directory(candidate_entry, entries),
                "logical_bytes": logical_bytes,
                "reclaimable_local_bytes": reclaimable_bytes,
                "handle_state": state,
                "handle_detail": detail,
                "blockers": blockers,
            }
        )
        blocked = blocked or bool(blockers)
    payload = {
        "status": "blocked" if blocked else "ready-for-explicit-approval",
        "tier": plan["tier"],
        "target": str(target),
        "candidates": results,
        "empty_directories": sum(1 for item in results if item["empty_directory"]),
        "logical_bytes": sum(item["logical_bytes"] for item in results),
        "reclaimable_local_bytes": sum(
            item["reclaimable_local_bytes"] for item in results
        ),
        "approval_token": None if blocked else approval_token(snapshot, plan),
        "warning": (
            "Safe tidiness is the primary objective; reclaimable bytes are "
            "secondary. Approval is valid only for this tier, exact plan, and "
            "snapshot. Re-preview after any change."
        ),
    }
    return payload


def handoff_verify(
    snapshot: dict[str, Any],
    approved: list[str],
    vcs_evidence: dict[str, dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Re-run per-path revalidation for the manual handoff lane, read-only.

    Deterministically reruns the engine's identity/reparse/protection/VCS/
    handle checks against live state for each approved path and emits a
    verdict — never a deletion. Platform execution blockers deliberately do
    not apply: this subcommand exists exactly for the platforms where the
    engine's own apply lane is unsupported.
    """
    target, known_mounts = resolve_snapshot_target(snapshot)
    entries = entry_map(snapshot)
    exact_names = baseline_protected_names() | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    truncated_paths = {
        value for value in snapshot.get("truncated_paths", []) if isinstance(value, str)
    }
    globs = snapshot_protection_globs(snapshot)
    verdicts: list[dict[str, Any]] = []
    for relative in approved:
        path = target.joinpath(*PurePosixPath(relative).parts)
        drifted: set[str] = set()
        contested: set[str] = set()
        evidence_result: dict[str, Any] | None = None
        candidate_pure = PurePosixPath(relative)
        candidate_evidence = {
            repository: config
            for repository, config in (vcs_evidence or {}).items()
            if (
                (repository_pure := PurePosixPath(repository)) == candidate_pure
                or candidate_pure in repository_pure.parents
            )
        }
        try:
            path.lstat()
        except FileNotFoundError:
            verdicts.append(
                {"path": relative, "verdict": "gone", "reasons": ["no-longer-present"]}
            )
            continue
        except PermissionError:
            verdicts.append(
                {
                    "path": relative,
                    "verdict": "contested",
                    "reasons": ["needs-elevation"],
                }
            )
            continue
        except OSError:
            verdicts.append(
                {
                    "path": relative,
                    "verdict": "contested",
                    "reasons": ["filesystem-state-unverified"],
                }
            )
            continue
        candidate_protections = hard_protection(path, target, exact_names, known_mounts)
        truncated = overlaps_truncated(relative, truncated_paths)
        overlapping_truncations = {
            name
            for name in truncated_paths
            if name == relative
            or name.startswith(relative + "/")
            or relative.startswith(name + "/")
        }
        configured_git_truncations = {
            (PurePosixPath(repository) / GIT_METADATA_NAME).as_posix()
            for repository in candidate_evidence
        }
        evidence_inventory_eligible = bool(candidate_evidence) and not (
            overlapping_truncations - configured_git_truncations
        )
        expected_paths = subtree_names(relative, entries)
        if truncated and not evidence_inventory_eligible:
            # A truncated path has no captured descendant set, so no live walk
            # can prove anything about it — never clear (same rationale as the
            # preview short-circuit).
            contested.add("truncated-not-inventoried")
            current_paths = expected_paths
        else:
            try:
                current_paths = current_descendants(
                    target,
                    path,
                    opaque_git_metadata=bool(candidate_evidence),
                )
            # On failure, treat the live set as unknown rather than empty
            # (preview's choice): an unreadable subtree is contested, not
            # provably drifted — "changed" cannot be claimed without a read.
            except PermissionError:
                current_paths = expected_paths
                contested.add("needs-elevation")
            except (OSError, HygieneError):
                current_paths = expected_paths
                contested.add("filesystem-state-unverified")
        if candidate_evidence and evidence_inventory_eligible:
            try:
                evidence_result = verify_vcs_checkout_evidence(
                    target,
                    path,
                    current_paths,
                    candidate_evidence,
                    approved,
                )
            except (OSError, subprocess.SubprocessError, HygieneError) as exc:
                evidence_result = {
                    "status": "failed",
                    "gates": {
                        name: {"status": "failed"} for name in VCS_EVIDENCE_GATE_NAMES
                    },
                    "blockers": ["vcs-evidence-state-unverified"],
                    "error": str(exc),
                }
            contested.update(evidence_result["blockers"])
        elif candidate_evidence:
            evidence_result = {
                "status": "failed",
                "gates": {
                    name: {"status": "failed"} for name in VCS_EVIDENCE_GATE_NAMES
                },
                "blockers": ["vcs-evidence-non-git-truncation"],
            }
            contested.update(evidence_result["blockers"])
        evidence_verified = (
            evidence_result is not None and evidence_result["status"] == "verified"
        )
        repository_paths = [
            target.joinpath(*PurePosixPath(value).parts)
            for value in (evidence_result or {}).get("repositories", [])
        ]
        if evidence_verified:
            candidate_protections = evidence_adjusted_protections(
                candidate_protections,
                path,
                target,
                repository_paths,
                exact_names,
            )
            git_metadata_truncations = {
                (repo / GIT_METADATA_NAME).relative_to(target).as_posix()
                for repo in repository_paths
            }
            truncated = bool(overlapping_truncations - git_metadata_truncations)
        if truncated:
            contested.add("truncated-not-inventoried")
        contested.update(candidate_protections)
        if current_paths != expected_paths:
            drifted.add("changed-since-scan")
        for name in expected_paths:
            entry = entries[name]
            current = target.joinpath(*PurePosixPath(name).parts)
            # Distinguish unverifiable descendant state from real drift:
            # same_identity's blanket OSError->False would report a denied
            # lstat as changed-since-scan, telling the lane to rescan when
            # the actual remedy is resolving access (review finding).
            try:
                info = current.lstat()
            except FileNotFoundError:
                drifted.add("changed-since-scan")
            except PermissionError:
                contested.add("needs-elevation")
            except OSError:
                contested.add("filesystem-state-unverified")
            else:
                metadata_entry = any(
                    current == repo / GIT_METADATA_NAME for repo in repository_paths
                )
                identity_matches = (
                    same_object_identity(info, entry)
                    if candidate_evidence
                    and metadata_entry
                    and entry.get("kind") == "directory"
                    else same_stat_identity(info, entry)
                )
                if not identity_matches:
                    drifted.add("changed-since-scan")
            current_protections = hard_protection(
                current, target, exact_names, known_mounts
            )
            if evidence_verified:
                current_protections = evidence_adjusted_protections(
                    current_protections,
                    current,
                    target,
                    repository_paths,
                    exact_names,
                )
            contested.update(current_protections)
            relative_current = current.relative_to(target).as_posix()
            if any(glob_matches(relative_current, pattern) for pattern in globs):
                contested.add("consumer-protected-path")
        if not truncated or evidence_inventory_eligible:
            # A hung git (TimeoutExpired) must degrade to this one path's
            # contested verdict, not abort the whole run with no verdicts —
            # the subcommand promises a verdict per approved path.
            try:
                vcs = tracked_blocker(path, target)
            except (OSError, subprocess.SubprocessError):
                vcs = "vcs-state-unverified"
            if vcs and not (evidence_verified and vcs == "vcs-tracked-content"):
                contested.add(vcs)
            # Same degradation rule as the VCS probe: a probe that fails to
            # LAUNCH (lsof vanishing after which(), a ctypes load error) is
            # this path's contested verdict, not a whole-run abort.
            try:
                state, detail = candidate_handle_state(target, path, expected_paths)
            except (OSError, subprocess.SubprocessError):
                state, detail = "unverified", "handle-probe-failed"
            if state == "open":
                contested.add("live-handle" + (f": {detail}" if detail else ""))
            elif state == "needs_elevation":
                contested.add("needs-elevation")
            elif state != "clear":
                contested.add(
                    "handle-state-unverified" + (f": {detail}" if detail else "")
                )
        verdict = "drifted" if drifted else "contested" if contested else "clear"
        item = {
            "path": relative,
            "verdict": verdict,
            "reasons": sorted(drifted) + sorted(contested),
        }
        if evidence_result is not None:
            item["vcs_evidence"] = evidence_result
        verdicts.append(item)
    clear = sum(1 for item in verdicts if item["verdict"] == "clear")
    return {
        "status": "handoff-verify-complete",
        "target": str(target),
        "verdicts": verdicts,
        "clear": clear,
        "not_clear": len(verdicts) - clear,
        "note": (
            "Read-only revalidation for the manual handoff lane; this "
            "subcommand has no deletion capability. A clear verdict is valid "
            "only at emission time — in a multi-path run the earliest checks "
            "age while later paths are still probed, so verify ONE path per "
            "deletion (verify one, delete that one, then the next) and "
            "re-verify after any delay. The multi-path form is for reporting."
        ),
    }


def removal_entries(relative: str, entries: dict[str, dict[str, Any]]) -> list[str]:
    return sorted(
        subtree_names(relative, entries),
        key=lambda value: (len(PurePosixPath(value).parts), value),
        reverse=True,
    )


def open_anchored_parent(
    target_fd: int, relative: str, entries: dict[str, dict[str, Any]]
) -> tuple[int, str]:
    parts = PurePosixPath(relative).parts
    parent_fd = os.dup(target_fd)
    walked: list[str] = []
    try:
        for part in parts[:-1]:
            walked.append(part)
            next_fd = os.open(
                part,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=parent_fd,
            )
            os.close(parent_fd)
            parent_fd = next_fd
            expected = entries.get(PurePosixPath(*walked).as_posix())
            if expected is None or not same_object_identity(
                os.fstat(parent_fd), expected
            ):
                raise HygieneError("anchored parent changed since the snapshot")
        return parent_fd, parts[-1]
    except BaseException:
        os.close(parent_fd)
        raise


def anchored_remove(
    target_fd: int,
    relative: str,
    entry: dict[str, Any],
    entries: dict[str, dict[str, Any]],
    target: Path,
) -> None:
    parent_fd, name = open_anchored_parent(target_fd, relative, entries)
    try:
        current = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
        expected_parent = target.joinpath(*PurePosixPath(relative).parts[:-1]).resolve(
            strict=True
        )
        actual_parent = Path(f"/proc/self/fd/{parent_fd}").resolve(strict=True)
        if actual_parent != expected_parent:
            raise HygieneError("anchored parent is no longer at its expected path")
        if entry["kind"] == "directory":
            if not same_object_identity(current, entry):
                raise HygieneError("anchored directory changed since the snapshot")
            directory_fd = os.open(
                name,
                os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW,
                dir_fd=parent_fd,
            )
            try:
                opened = os.fstat(directory_fd)
                if not same_object_identity(opened, entry) or not same_open_object(
                    current, opened
                ):
                    raise HygieneError("anchored directory changed since the snapshot")
                with os.scandir(directory_fd) as iterator:
                    if next(iterator, None) is not None:
                        raise HygieneError("anchored directory is not empty")
                named = os.stat(name, dir_fd=parent_fd, follow_symlinks=False)
                if not same_object_identity(named, entry) or not same_open_object(
                    opened, named
                ):
                    raise HygieneError("anchored directory changed since the snapshot")
                os.rmdir(name, dir_fd=parent_fd)
            finally:
                os.close(directory_fd)
        elif entry["kind"] == "file":
            if not same_stat_identity(current, entry):
                raise HygieneError("anchored entry changed since the snapshot")
            os.unlink(name, dir_fd=parent_fd)
        else:
            raise HygieneError("only regular files and directories are removable")
    finally:
        os.close(parent_fd)


def apply_nothing_removed_report(
    plan: dict[str, Any], target: Path, skipped: list[dict[str, str]]
) -> dict[str, Any]:
    """An apply report for a run that removed nothing and skipped every candidate."""
    return {
        "status": "completed-with-skips",
        "tier": plan["tier"],
        "target": str(target),
        "removed": [],
        "skipped": skipped,
        "paths_removed": 0,
        "empty_directories_removed": 0,
        "logical_bytes_removed": 0,
        "reclaimable_local_bytes_removed": 0,
        "observed_free_space_delta_bytes": 0,
    }


def apply_plan(snapshot: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    target = Path(snapshot["target"]).absolute()
    entries = entry_map(snapshot)
    candidates = validate_plan(plan, entries)
    platform_blockers = execution_blockers()
    if platform_blockers:
        return apply_nothing_removed_report(
            plan,
            target,
            [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(platform_blockers),
                }
                for item in candidates
            ],
        )
    checked = preview(snapshot, plan)
    if checked["status"] != "ready-for-explicit-approval":
        by_path = {item["path"]: item for item in checked["candidates"]}
        return apply_nothing_removed_report(
            plan,
            target,
            [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(by_path[item["path"]]["blockers"]),
                }
                for item in candidates
            ],
        )
    before = shutil.disk_usage(target).free
    removed: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    logical_removed = 0
    reclaimable_removed = 0
    target_fd = os.open(target, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    if not same_object_identity(os.fstat(target_fd), snapshot["target_identity"]):
        os.close(target_fd)
        raise HygieneError("anchored target was replaced since the snapshot")
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        os.close(target_fd)
        raise HygieneError(mount_error)
    globs = snapshot_protection_globs(snapshot)
    for candidate in candidates:
        candidate_path = target.joinpath(*PurePosixPath(candidate["path"]).parts)
        candidate_blockers = hard_protection(
            candidate_path,
            target,
            baseline_protected_names()
            | set(snapshot.get("policy", {}).get("protected_exact_names", [])),
            known_mounts,
        )
        selected = removal_entries(candidate["path"], entries)
        if candidate["owner"] != "unmanaged":
            candidate_blockers.append("native-managed-report-only")
        vcs = tracked_blocker(candidate_path, target)
        if vcs:
            candidate_blockers.append(vcs)
        if candidate_blockers:
            skipped.append(
                {
                    "path": candidate["path"],
                    "outcome": "protected",
                    "detail": ", ".join(sorted(set(candidate_blockers))),
                }
            )
            continue
        for relative in selected:
            entry = entries[relative]
            path = target.joinpath(*PurePosixPath(relative).parts)
            if not same_removal_identity(path, entry) or is_linkish(path):
                skipped.append({"path": relative, "outcome": "changed-or-link"})
                continue
            fresh_mounts, fresh_mount_error = linux_mount_points()
            if fresh_mount_error:
                skipped.append(
                    {
                        "path": relative,
                        "outcome": "protected",
                        "detail": "mount-state-unverified",
                    }
                )
                continue
            fresh_protections = hard_protection(
                path,
                target,
                baseline_protected_names(),
                fresh_mounts,
            )
            if any(glob_matches(relative, pattern) for pattern in globs):
                fresh_protections.append("consumer-protected-path")
            fresh_vcs = tracked_blocker(path, target)
            if fresh_vcs:
                fresh_protections.append(fresh_vcs)
            if fresh_protections:
                skipped.append(
                    {
                        "path": relative,
                        "outcome": "protected",
                        "detail": ", ".join(sorted(set(fresh_protections))),
                    }
                )
                continue
            state, detail = handle_state(path)
            if state != "clear":
                outcome = {"open": "locked", "needs_elevation": "needs-elevation"}.get(
                    state, "handle-state-unverified"
                )
                skipped.append(
                    {"path": relative, "outcome": outcome, "detail": detail or ""}
                )
                continue
            try:
                anchored_remove(target_fd, relative, entry, entries, target)
            except HygieneError as exc:
                skipped.append(
                    {"path": relative, "outcome": "changed-or-link", "detail": str(exc)}
                )
                continue
            except PermissionError as exc:
                skipped.append(
                    {"path": relative, "outcome": "needs-elevation", "detail": str(exc)}
                )
                continue
            except OSError as exc:
                skipped.append(
                    {"path": relative, "outcome": "delete-failed", "detail": str(exc)}
                )
                continue
            logical = entry_logical_file_bytes(entry)
            reclaimable = entry_reclaimable_local_bytes(entry) or 0
            logical_removed += logical
            reclaimable_removed += reclaimable
            removed.append(
                {
                    "path": relative,
                    "empty_directory": entry_is_empty_directory(entry, entries),
                    "logical_bytes": logical,
                    "reclaimable_local_bytes": reclaimable,
                }
            )
    os.close(target_fd)
    after = shutil.disk_usage(target).free
    return {
        "status": "completed-with-skips" if skipped else "completed",
        "tier": plan["tier"],
        "target": str(target),
        "removed": removed,
        "skipped": skipped,
        "paths_removed": len(removed),
        "empty_directories_removed": sum(
            1 for item in removed if item["empty_directory"]
        ),
        "logical_bytes_removed": logical_removed,
        "reclaimable_local_bytes_removed": reclaimable_removed,
        "observed_free_space_delta_bytes": after - before,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    scan = subparsers.add_parser("scan", help="inventory a target without mutating it")
    scan.add_argument("--target", required=True)
    scan.add_argument("--output", required=True)
    scan.add_argument("--policy")
    scan.add_argument("--project-dir")
    scan.add_argument("--data-root")
    scan.add_argument("--max-depth", type=int)
    scan.add_argument("--confirmed-large-scan", action="store_true")
    scan.add_argument(
        "--root-children",
        action="store_true",
        help=(
            "admit an OS-managed volume root only as a listing of immediate "
            "non-OS child directories; requires explicit --root-child selection "
            "before any subtree is audited"
        ),
    )
    scan.add_argument(
        "--root-child",
        action="append",
        default=[],
        metavar="NAME",
        help=(
            "immediate child directory basename to audit under --root-children; "
            "repeatable; never inferred"
        ),
    )
    for name in ("preview", "apply"):
        command = subparsers.add_parser(name)
        command.add_argument("--snapshot", required=True)
        command.add_argument("--plan", required=True)
        command.add_argument("--data-root")
        if name == "apply":
            command.add_argument("--execute", action="store_true")
            command.add_argument("--confirm-tier", required=True, choices=sorted(TIERS))
            command.add_argument("--approval-token", required=True)
            command.add_argument("--report", required=True)
    verify = subparsers.add_parser(
        "handoff-verify",
        help="re-verify approved paths for the manual handoff lane (read-only)",
    )
    verify.add_argument("--snapshot", required=True)
    verify.add_argument("--paths", required=True)
    verify.add_argument("--vcs-evidence")
    verify.add_argument("--data-root")
    return parser


def main(argv: list[str] | None = None) -> int:
    global DATA_ROOT_OVERRIDE
    args = build_parser().parse_args(argv)
    DATA_ROOT_OVERRIDE = args.data_root
    try:
        if sys.version_info < MIN_PYTHON:
            floor = ".".join(str(part) for part in MIN_PYTHON)
            raise HygieneError(f"disk-hygiene requires Python {floor} or newer")
        if args.command == "scan":
            target_input = Path(args.target).expanduser().absolute()
            if (
                not target_input.exists()
                or not target_input.is_dir()
                or has_linkish_component(target_input)
            ):
                raise HygieneError(
                    "target must be an existing directory with no link or reparse-point component"
                )
            target = target_input.resolve(strict=True)
            known_mounts, mount_error = linux_mount_points()
            mounted, target_mount_error = mount_state(target, known_mounts)
            if mount_error or target_mount_error:
                raise HygieneError("target mount state is unverified")
            root_children_mode = bool(args.root_children)
            selected_root_children = list(args.root_child or [])
            if selected_root_children and not root_children_mode:
                raise HygieneError("--root-child requires --root-children")
            if root_children_mode:
                if not is_volume_root(target):
                    raise HygieneError("--root-children requires a volume-root target")
                if not is_os_managed_target(target):
                    raise HygieneError(
                        "--root-children is only valid for an OS-managed volume root; "
                        "scan a non-OS volume root without this flag"
                    )
            elif is_os_managed_target(target):
                raise HygieneError("OS-managed roots are not valid audit targets")
            if mounted and not is_volume_root(target):
                raise HygieneError("mount points are not valid audit targets")
            policy = load_policy(
                Path(args.policy).expanduser().absolute() if args.policy else None,
                Path(args.project_dir).expanduser().absolute()
                if args.project_dir
                else None,
            )
            if has_protected_path_component(
                target, set(policy["protected_exact_names"])
            ):
                raise HygieneError(
                    "protected shell-folder and profile-hive roots are not valid audit targets"
                )
            if args.max_depth is not None and args.max_depth < 1:
                raise HygieneError("--max-depth must be a positive integer")
            output_path = state_output_path(Path(args.output))
            advisory = os_autoclean_advisory(target)
            if root_children_mode:
                admitted, skipped = enumerate_root_children(
                    target, policy, known_mounts
                )
                if not selected_root_children:
                    return emit(
                        {
                            "status": "root-children-selection-required",
                            "target": str(target),
                            "admitted_children": admitted,
                            "skipped_children": skipped,
                            "os_autoclean": advisory,
                            "note": (
                                "OS-managed volume roots are never walked as a "
                                "whole. Re-run with --root-children and one or "
                                "more explicit --root-child NAME flags naming "
                                "admitted immediate directories; a general "
                                "'clean everything' is not selection."
                            ),
                        },
                        5,
                    )
                resolved_children = normalize_root_child_selection(
                    selected_root_children, admitted
                )
                # Each selected child is its own audit target for large-scan
                # gating: a home directory selected under the volume root still
                # requires a bound or confirmation.
                child_large_reasons: list[str] = []
                for child_name in resolved_children:
                    child_path = target / child_name
                    child_large_reasons.extend(
                        f"{child_name}:{reason}"
                        for reason in large_scan_reasons(child_path)
                    )
                if (
                    child_large_reasons
                    and args.max_depth is None
                    and not args.confirmed_large_scan
                ):
                    return emit(
                        {
                            "status": "large-target-confirmation-required",
                            "target": str(target),
                            "root_children_selected": resolved_children,
                            "large_target_reasons": sorted(set(child_large_reasons)),
                            "os_autoclean": advisory,
                            "note": (
                                "A selected root child is a known-large scan "
                                "root; re-run with --max-depth N (preferred) or, "
                                "only after the human confirms a full walk, "
                                "--confirmed-large-scan."
                            ),
                        },
                        5,
                    )
                try:
                    snapshot = scan_tree(
                        target,
                        policy,
                        args.max_depth,
                        root_children=resolved_children,
                    )
                except HygieneError as exc:
                    return emit(
                        {
                            "status": "invalid-or-blocked",
                            "error": str(exc),
                            "os_autoclean": advisory,
                        },
                        2,
                    )
                snapshot["root_children_skipped"] = skipped
                write_json(output_path, snapshot)
                hinted = sum(1 for entry in snapshot["entries"] if entry["hints"])
                return emit(
                    {
                        "status": "scan-complete",
                        "target": str(target),
                        "root_children_mode": True,
                        "root_children_selected": resolved_children,
                        "snapshot": str(output_path),
                        "entries": len(snapshot["entries"]),
                        "hinted_entries": hinted,
                        "unhinted_entries": len(snapshot["entries"]) - hinted,
                        "target_logical_bytes": snapshot["target_logical_bytes"],
                        "target_reclaimable_local_bytes": snapshot[
                            "target_reclaimable_local_bytes"
                        ],
                        "truncated_paths": snapshot["truncated_paths"],
                        "children_rollup": snapshot["children_rollup"],
                        "errors": snapshot["errors"],
                        "policy_sources": policy["policy_sources"],
                        "os_autoclean": advisory,
                        "note": (
                            "Root-children mode inventoried only the selected "
                            "immediate directories; the volume root itself and "
                            "every skipped OS-owned/hidden/system/reparse entry "
                            "were never walked — so children_rollup covers the "
                            "selected children only. unhinted_entries is "
                            "entries minus hinted_entries: every inventoried "
                            "entry no hint judged, left to positional review. "
                            "Hints are discovery signals, never cleanup "
                            "verdicts."
                        ),
                    }
                )
            large_reasons = large_scan_reasons(target)
            if (
                large_reasons
                and args.max_depth is None
                and not args.confirmed_large_scan
            ):
                immediate_entries, probe_error = top_level_entry_count(target)
                return emit(
                    {
                        "status": "large-target-confirmation-required",
                        "target": str(target),
                        "large_target_reasons": large_reasons,
                        "immediate_entries": immediate_entries,
                        "probe_error": probe_error,
                        "os_autoclean": advisory,
                        "note": (
                            "This is a known-large scan root; an unbounded "
                            "recursive walk is gated at the engine. Re-run with "
                            "--max-depth N for a bounded pass (start with "
                            "--max-depth 1), or, only after the human confirms a "
                            "full walk, add --confirmed-large-scan."
                        ),
                    },
                    5,
                )
            try:
                snapshot = scan_tree(target, policy, args.max_depth)
            except HygieneError as exc:
                return emit(
                    {
                        "status": "invalid-or-blocked",
                        "error": str(exc),
                        "os_autoclean": advisory,
                    },
                    2,
                )
            write_json(output_path, snapshot)
            hinted = sum(1 for entry in snapshot["entries"] if entry["hints"])
            return emit(
                {
                    "status": "scan-complete",
                    "target": str(target),
                    "snapshot": str(output_path),
                    "entries": len(snapshot["entries"]),
                    "hinted_entries": hinted,
                    "unhinted_entries": len(snapshot["entries"]) - hinted,
                    "empty_directory_count": snapshot["empty_directory_count"],
                    "target_logical_bytes": snapshot["target_logical_bytes"],
                    "target_reclaimable_local_bytes": snapshot[
                        "target_reclaimable_local_bytes"
                    ],
                    "truncated_paths": snapshot["truncated_paths"],
                    "children_rollup": snapshot["children_rollup"],
                    "errors": snapshot["errors"],
                    "policy_sources": policy["policy_sources"],
                    "os_autoclean": advisory,
                    "note": (
                        "Safe tidiness is the primary objective; reclaimable "
                        "bytes are a secondary signal. empty_directory_count "
                        "names walked empty directories (logical_size 0, not "
                        "truncated) so zero-byte residue stays visible. "
                        "unhinted_entries is entries minus hinted_entries — "
                        "every inventoried entry no hint judged, left to "
                        "positional review — so hint coverage reads as a rate, "
                        "not a bare count. Hints are discovery signals, "
                        "never cleanup verdicts. children_rollup carries one "
                        "row per immediate child; its logical_bytes, "
                        "entry_count and newest_mtime_ns are exact where "
                        "walked is true and null where it is false, never 0. "
                        "target_reclaimable_local_bytes excludes every entry "
                        "whose size_qualifiers is non-empty (cloud-placeholder, "
                        "hardlinked, sparse, not-walked); target_logical_bytes "
                        "is the walked roll-up and may understate truncated "
                        "subtrees."
                    ),
                }
            )
        snapshot = load_json(Path(args.snapshot))
        if args.command == "handoff-verify":
            approved = validate_handoff_paths(
                load_json(Path(args.paths)), entry_map(snapshot)
            )
            vcs_evidence = (
                validate_vcs_evidence(load_json(Path(args.vcs_evidence)), approved)
                if args.vcs_evidence
                else None
            )
            result = handoff_verify(snapshot, approved, vcs_evidence)
            return emit(result, 3 if result["not_clear"] else 0)
        plan = load_json(Path(args.plan))
        checked = preview(snapshot, plan)
        if args.command == "preview":
            return emit(checked, 3 if checked["status"] == "blocked" else 0)
        if not args.execute:
            raise HygieneError("apply requires the explicit --execute flag")
        if checked["status"] != "ready-for-explicit-approval":
            return emit(checked, 3)
        if args.confirm_tier != plan.get("tier"):
            raise HygieneError("--confirm-tier must match the plan's single tier")
        if args.approval_token != checked["approval_token"]:
            raise HygieneError("approval token does not match the fresh preview")
        report_path = state_output_path(Path(args.report))
        report = apply_plan(snapshot, plan)
        write_json(report_path, report)
        return emit(report, 4 if report["skipped"] else 0)
    except HygieneError as exc:
        return emit({"status": "invalid-or-blocked", "error": str(exc)}, 2)
    except PermissionError as exc:
        return emit({"status": "needs-elevation", "error": str(exc)}, 3)
    except (OSError, subprocess.SubprocessError) as exc:
        return emit({"status": "filesystem-state-unverified", "error": str(exc)}, 3)
    finally:
        # Close the test-isolation window: a call to `main()` must never leave
        # this override live for a later `state_output_path()` call (direct,
        # or via a subsequent `main()` invocation in the same process) to
        # observe a stale --data-root after this invocation has returned.
        DATA_ROOT_OVERRIDE = None


if __name__ == "__main__":
    raise SystemExit(main())

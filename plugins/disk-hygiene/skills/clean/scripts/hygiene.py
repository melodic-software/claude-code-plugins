#!/usr/bin/env python3
"""Read-only inventory and fail-closed cleanup gate for disk-hygiene."""

from __future__ import annotations

import argparse
import ctypes
import datetime as dt
import fnmatch
import hashlib
import json
import os
import platform
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
from pathlib import Path, PurePosixPath
from typing import Any

MIN_PYTHON = (3, 11)
SCHEMA_VERSION = 1
MAX_SNAPSHOT_ENTRIES = 250_000
TIERS = {"high", "medium", "low"}
VCS_NAMES = {".git", ".hg", ".svn"}
FILE_ATTRIBUTE_REPARSE_POINT = 0x0400
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


def is_within(path: Path, parent: Path) -> bool:
    try:
        return os.path.commonpath(
            [os.path.normcase(path), os.path.normcase(parent)]
        ) == os.path.normcase(parent)
    except ValueError:
        return False


def is_linkish(path: Path) -> bool:
    """Return true for every link-like Windows reparse point, including on 3.11."""
    try:
        info = path.lstat()
    except OSError:
        return False
    if stat.S_ISLNK(info.st_mode):
        return True
    return bool(getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT)


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
    return name in {value.casefold() for value in exact_names} or name.startswith(
        "ntuser.dat"
    )


def has_protected_path_component(path: Path, exact_names: set[str]) -> bool:
    return any(
        has_protected_name(candidate, exact_names)
        for candidate in (path, *path.parents)
        if candidate.parent != candidate
    )


def system_roots(
    platform_key: str | None = None, windows_roots: list[Path] | None = None
) -> list[Path]:
    roots: list[Path] = []
    current_platform = platform_key or os_key()
    if current_platform == "windows":
        candidates = [
            os.environ.get("SystemRoot"),
            os.environ.get("ProgramFiles"),
            os.environ.get("ProgramFiles(x86)"),
            os.environ.get("ProgramData"),
        ]
        roots.extend(Path(value).absolute() for value in candidates if value)
        drive_roots = windows_roots if windows_roots is not None else windows_drive_roots()
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
    env_roots = (
        os.environ.get("SystemRoot"),
        os.environ.get("ProgramFiles"),
        os.environ.get("ProgramFiles(x86)"),
        os.environ.get("ProgramData"),
    )
    markers.extend(Path(value).absolute() for value in env_roots if value)
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
        if is_linkish(current):
            reasons.append("symlink-junction-or-reparse-point")
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
        "hints": list(baseline.get("hints", [])),
        "additional_protected_path_globs": [],
        "policy_sources": ["baseline"],
    }


def baseline_protected_names() -> set[str]:
    """Bundled protected names only — validation paths must never depend on
    ambient standing policy; an approved snapshot stays previewable even if a
    standing file is later edited or malformed."""
    return set(baseline_policy()["protected_exact_names"])


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
        if fnmatch.fnmatchcase(subject, hint["pattern"]):
            matches.append(
                {
                    "id": hint["id"],
                    "confidence_ceiling": hint["confidence_ceiling"],
                    "reason": hint["reason"],
                }
            )
    return matches


def metadata(path: Path, kind: str, logical_size: int = 0) -> dict[str, Any]:
    info = path.lstat()
    return {
        "kind": kind,
        "stat_size": info.st_size,
        "logical_size": logical_size if kind == "directory" else info.st_size,
        "mtime_ns": info.st_mtime_ns,
        "device": info.st_dev,
        "inode": info.st_ino,
        "mode": stat.S_IFMT(info.st_mode),
    }


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


def scan_tree(
    target: Path, policy: dict[str, Any], max_depth: int | None = None
) -> dict[str, Any]:
    entries: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []
    truncated: list[str] = []
    repositories, repo_errors = discover_enclosing_git(target)
    exact_names = set(policy["protected_exact_names"])
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        errors.append({"path": ".", "error": mount_error})

    def visit(directory: Path, depth: int = 1) -> int:
        total = 0
        try:
            with os.scandir(directory) as iterator:
                children = sorted(iterator, key=lambda entry: entry.name.casefold())
        except OSError as exc:
            errors.append(
                {"path": directory.relative_to(target).as_posix(), "error": str(exc)}
            )
            return 0
        for child in children:
            path = Path(child.path)
            relative = path.relative_to(target).as_posix()
            protections = hard_protection(path, target, exact_names, known_mounts)
            if path.name.casefold() in VCS_NAMES:
                repositories.append(path.parent.resolve())
            if any(
                fnmatch.fnmatchcase(relative, pattern)
                for pattern in policy["additional_protected_path_globs"]
            ):
                protections.append("consumer-protected-path")
            try:
                if is_linkish(path):
                    kind = "link"
                    data = metadata(path, kind)
                elif child.is_dir(follow_symlinks=False):
                    kind = "directory"
                    if path.name.casefold() in VCS_NAMES:
                        subtotal = 0
                        truncated.append(relative)
                    elif protections:
                        subtotal = 0
                        truncated.append(relative)
                    elif max_depth is not None and depth >= max_depth:
                        subtotal = 0
                        truncated.append(relative)
                    else:
                        subtotal = visit(path, depth + 1)
                    data = metadata(path, kind, subtotal)
                    total += subtotal
                elif child.is_file(follow_symlinks=False):
                    kind = "file"
                    data = metadata(path, kind)
                    total += data["logical_size"]
                else:
                    kind = "other"
                    data = metadata(path, kind)
            except OSError as exc:
                errors.append({"path": relative, "error": str(exc)})
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
    repositories = sorted(set(repositories))
    annotate_tracked(entries, target, repositories, truncated, repo_errors)
    return {
        "schema_version": SCHEMA_VERSION,
        "engine": "disk-hygiene-python-1",
        "session_nonce": secrets.token_hex(16),
        "created_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "platform": os_key(),
        "target": str(target),
        "target_identity": metadata(target, "directory", total_size),
        "target_logical_bytes": total_size,
        "policy": policy,
        "repositories": [str(repo) for repo in repositories],
        "repository_errors": repo_errors,
        "errors": errors,
        "max_depth": max_depth,
        "truncated_paths": sorted(truncated),
        "entries": sorted(entries, key=lambda entry: entry["path"]),
    }


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
            "reason",
            "evidence",
            "why_not_work_product",
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
        if not isinstance(candidate["reason"], str) or not candidate["reason"].strip():
            raise HygieneError(f"candidate needs a reason: {relative}")
        if (
            not isinstance(candidate["why_not_work_product"], str)
            or not candidate["why_not_work_product"].strip()
        ):
            raise HygieneError(f"candidate needs work-product analysis: {relative}")
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


def current_descendants(root: Path, candidate: Path) -> set[str]:
    paths: set[str] = set()
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        raise HygieneError(mount_error)

    def visit(path: Path) -> None:
        paths.add(path.relative_to(root).as_posix())
        mounted, error = mount_state(path, known_mounts)
        if error:
            raise HygieneError(error)
        if is_linkish(path) or not path.is_dir() or mounted:
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
    kind = (
        "link"
        if stat.S_ISLNK(info.st_mode)
        or bool(getattr(info, "st_file_attributes", 0) & FILE_ATTRIBUTE_REPARSE_POINT)
        else "directory"
        if stat.S_ISDIR(info.st_mode)
        else "file"
        if stat.S_ISREG(info.st_mode)
        else "other"
    )
    return all(
        (
            kind == entry.get("kind"),
            info.st_size == entry.get("stat_size"),
            info.st_mtime_ns == entry.get("mtime_ns"),
            info.st_dev == entry.get("device"),
            info.st_ino == entry.get("inode"),
            stat.S_IFMT(info.st_mode) == entry.get("mode"),
        )
    )


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
    flags = 0x02000000 if path.is_dir() else 0x00000080  # BACKUP_SEMANTICS / NORMAL
    handle = create_file(
        str(path), 0, 0, None, 3, flags, None
    )  # OPEN_EXISTING, exclusive share
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


def resolve_snapshot_target(
    snapshot: dict[str, Any], *, strict_root_stat: bool = True
) -> tuple[Path, set[Path]]:
    """Re-validate the snapshot's target root against live state and return it.

    Shared by preview and handoff-verify: both must refuse a snapshot whose
    target root drifted, became a link, a mount point, an OS-managed root, or a
    protected shell folder since the scan. Preview keeps the full stat identity
    (size/mtime included) because its approval token binds one immutable state.
    handoff-verify passes ``strict_root_stat=False`` to tolerate the root
    directory's own metadata churn — deleting an approved root-level item
    changes the root's mtime, and the manual lane deletes one item at a time
    with a re-verify between items — while still refusing a replaced root via
    the same stable device/inode/type identity apply uses for directories.
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
    if is_os_managed_target(target):
        raise HygieneError("snapshot target is now an OS-managed root")
    if target_mounted and not is_volume_root(target):
        raise HygieneError("snapshot target is a mount point")
    if has_protected_path_component(target, baseline_protected_names()):
        raise HygieneError(
            "snapshot target is now a protected shell-folder or profile-hive root"
        )
    identity = snapshot.get("target_identity", {})
    if strict_root_stat:
        if not same_identity(target, identity):
            raise HygieneError("target root changed since the snapshot")
    else:
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
        value
        for value in snapshot.get("truncated_paths", [])
        if isinstance(value, str)
    }
    exact_names = baseline_exact_names | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    results = []
    blocked = False
    for candidate in candidates:
        relative = candidate["path"]
        path = target.joinpath(*PurePosixPath(relative).parts)
        blockers = hard_protection(path, target, exact_names, known_mounts)
        blockers.extend(execution_blockers())
        if candidate["owner"] != "unmanaged":
            blockers.append("native-managed-report-only")
        if any(
            name == relative
            or name.startswith(relative + "/")
            or relative.startswith(name + "/")
            for name in truncated_paths
        ):
            blockers.append("truncated-not-inventoried")
        expected_paths = {
            name
            for name in entries
            if name == relative or name.startswith(relative + "/")
        }
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
            if any(
                fnmatch.fnmatchcase(relative_current, pattern)
                for pattern in snapshot.get("policy", {}).get(
                    "additional_protected_path_globs", []
                )
                if isinstance(pattern, str)
            ):
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
        logical_bytes = sum(
            entries[name].get("logical_size", 0)
            for name in expected_paths
            if entries[name].get("kind") != "directory"
        )
        results.append(
            {
                "path": relative,
                "tier": plan["tier"],
                "logical_bytes": logical_bytes,
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
        "logical_bytes": sum(item["logical_bytes"] for item in results),
        "approval_token": None if blocked else approval_token(snapshot, plan),
        "warning": "Approval is valid only for this tier, exact plan, and snapshot. Re-preview after any change.",
    }
    return payload


def handoff_verify(snapshot: dict[str, Any], approved: list[str]) -> dict[str, Any]:
    """Re-run per-path revalidation for the manual handoff lane, read-only.

    Deterministically reruns the engine's identity/reparse/protection/VCS/
    handle checks against live state for each approved path and emits a
    verdict — never a deletion. Platform execution blockers deliberately do
    not apply: this subcommand exists exactly for the platforms where the
    engine's own apply lane is unsupported.
    """
    target, known_mounts = resolve_snapshot_target(snapshot, strict_root_stat=False)
    entries = entry_map(snapshot)
    exact_names = baseline_protected_names() | set(
        snapshot.get("policy", {}).get("protected_exact_names", [])
    )
    truncated_paths = {
        value
        for value in snapshot.get("truncated_paths", [])
        if isinstance(value, str)
    }
    globs = [
        pattern
        for pattern in snapshot.get("policy", {}).get(
            "additional_protected_path_globs", []
        )
        if isinstance(pattern, str)
    ]
    verdicts: list[dict[str, Any]] = []
    for relative in approved:
        path = target.joinpath(*PurePosixPath(relative).parts)
        drifted: set[str] = set()
        contested: set[str] = set()
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
        contested.update(hard_protection(path, target, exact_names, known_mounts))
        truncated = any(
            name == relative
            or name.startswith(relative + "/")
            or relative.startswith(name + "/")
            for name in truncated_paths
        )
        expected_paths = {
            name
            for name in entries
            if name == relative or name.startswith(relative + "/")
        }
        if truncated:
            # A truncated path has no captured descendant set, so no live walk
            # can prove anything about it — never clear (same rationale as the
            # preview short-circuit).
            contested.add("truncated-not-inventoried")
            current_paths = expected_paths
        else:
            try:
                current_paths = current_descendants(target, path)
            # On failure, treat the live set as unknown rather than empty
            # (preview's choice): an unreadable subtree is contested, not
            # provably drifted — "changed" cannot be claimed without a read.
            except PermissionError:
                current_paths = expected_paths
                contested.add("needs-elevation")
            except (OSError, HygieneError):
                current_paths = expected_paths
                contested.add("filesystem-state-unverified")
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
                if not same_stat_identity(info, entry):
                    drifted.add("changed-since-scan")
            contested.update(
                hard_protection(current, target, exact_names, known_mounts)
            )
            relative_current = current.relative_to(target).as_posix()
            if any(
                fnmatch.fnmatchcase(relative_current, pattern) for pattern in globs
            ):
                contested.add("consumer-protected-path")
        if not truncated:
            # A hung git (TimeoutExpired) must degrade to this one path's
            # contested verdict, not abort the whole run with no verdicts —
            # the subcommand promises a verdict per approved path.
            try:
                vcs = tracked_blocker(path, target)
            except (OSError, subprocess.SubprocessError):
                vcs = "vcs-state-unverified"
            if vcs:
                contested.add(vcs)
            state, detail = candidate_handle_state(target, path, expected_paths)
            if state == "open":
                contested.add("live-handle" + (f": {detail}" if detail else ""))
            elif state == "needs_elevation":
                contested.add("needs-elevation")
            elif state != "clear":
                contested.add(
                    "handle-state-unverified" + (f": {detail}" if detail else "")
                )
        verdict = "drifted" if drifted else "contested" if contested else "clear"
        verdicts.append(
            {
                "path": relative,
                "verdict": verdict,
                "reasons": sorted(drifted) + sorted(contested),
            }
        )
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
    selected = [
        name for name in entries if name == relative or name.startswith(relative + "/")
    ]
    return sorted(
        selected,
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


def apply_plan(snapshot: dict[str, Any], plan: dict[str, Any]) -> dict[str, Any]:
    target = Path(snapshot["target"]).absolute()
    entries = entry_map(snapshot)
    candidates = validate_plan(plan, entries)
    platform_blockers = execution_blockers()
    if platform_blockers:
        return {
            "status": "completed-with-skips",
            "tier": plan["tier"],
            "target": str(target),
            "removed": [],
            "skipped": [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(platform_blockers),
                }
                for item in candidates
            ],
            "logical_bytes_removed": 0,
            "observed_free_space_delta_bytes": 0,
        }
    checked = preview(snapshot, plan)
    if checked["status"] != "ready-for-explicit-approval":
        by_path = {item["path"]: item for item in checked["candidates"]}
        return {
            "status": "completed-with-skips",
            "tier": plan["tier"],
            "target": str(target),
            "removed": [],
            "skipped": [
                {
                    "path": item["path"],
                    "outcome": "protected",
                    "detail": ", ".join(by_path[item["path"]]["blockers"]),
                }
                for item in candidates
            ],
            "logical_bytes_removed": 0,
            "observed_free_space_delta_bytes": 0,
        }
    before = shutil.disk_usage(target).free
    removed: list[dict[str, Any]] = []
    skipped: list[dict[str, str]] = []
    logical_removed = 0
    target_fd = os.open(target, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    if not same_stat_identity(os.fstat(target_fd), snapshot["target_identity"]):
        os.close(target_fd)
        raise HygieneError("anchored target changed since the snapshot")
    known_mounts, mount_error = linux_mount_points()
    if mount_error:
        os.close(target_fd)
        raise HygieneError(mount_error)
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
            if any(
                fnmatch.fnmatchcase(relative, pattern)
                for pattern in snapshot.get("policy", {}).get(
                    "additional_protected_path_globs", []
                )
                if isinstance(pattern, str)
            ):
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
            logical = (
                entry.get("logical_size", 0) if entry["kind"] != "directory" else 0
            )
            logical_removed += logical
            removed.append({"path": relative, "logical_bytes": logical})
    os.close(target_fd)
    after = shutil.disk_usage(target).free
    return {
        "status": "completed-with-skips" if skipped else "completed",
        "tier": plan["tier"],
        "target": str(target),
        "removed": removed,
        "skipped": skipped,
        "logical_bytes_removed": logical_removed,
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
            if is_os_managed_target(target):
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
                    "truncated_paths": snapshot["truncated_paths"],
                    "errors": snapshot["errors"],
                    "policy_sources": policy["policy_sources"],
                    "os_autoclean": advisory,
                    "note": "Hints are discovery signals, never cleanup verdicts.",
                }
            )
        snapshot = load_json(Path(args.snapshot))
        if args.command == "handoff-verify":
            approved = validate_handoff_paths(
                load_json(Path(args.paths)), entry_map(snapshot)
            )
            result = handoff_verify(snapshot, approved)
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

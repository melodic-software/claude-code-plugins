"""Send a path to the Windows Recycle Bin, or refuse it.

The only deletion call in this module is ``IFileOperation.DeleteItem`` after
``SetOperationFlags`` has been given ``FOFX_RECYCLEONDELETE``. That flag makes
the operation fail when the bin cannot accept the item. A failure is a
refusal. There is no second call, and there is no permanent-delete function.
"""

from __future__ import annotations

import ctypes
import os
import sys
from ctypes import POINTER, byref, c_int, c_long, c_void_p, c_wchar_p
from dataclasses import dataclass
from pathlib import Path
from typing import Callable

# WINFUNCTYPE exists on Windows. Linux still imports this module so the engine
# can refuse the primitive; the COM call itself never runs there.
WINFUNCTYPE = getattr(ctypes, "WINFUNCTYPE", ctypes.CFUNCTYPE)

# FILEOPERATION_FLAGS, Windows SDK shobjidl_core.h.
FOFX_RECYCLEONDELETE = 0x00080000
FOF_SILENT = 0x0004
FOF_NOCONFIRMATION = 0x0010
FOF_NOERRORUI = 0x0400
RECYCLE_FLAGS = FOFX_RECYCLEONDELETE | FOF_SILENT | FOF_NOCONFIRMATION | FOF_NOERRORUI

NETWORK_PATH = "network-path"
REMOVABLE_VOLUME = "removable-volume"
RECYCLE_BIN_DISABLED = "recycle-bin-disabled"
RECYCLE_BIN_SIZE_LIMIT = "recycle-bin-size-limit"
RECYCLE_VOLUME_UNVERIFIED = "recycle-volume-unverified"
RECYCLE_PRIMITIVE_UNAVAILABLE = "recycle-primitive-unavailable"
RECYCLE_FAILED = "recycle-failed"
# Names the apply tests and the issue's refusal set use.
REFUSAL_NETWORK = NETWORK_PATH
REFUSAL_REMOVABLE = REMOVABLE_VOLUME
REFUSAL_BIN_DISABLED = RECYCLE_BIN_DISABLED
REFUSAL_SIZE_LIMIT = RECYCLE_BIN_SIZE_LIMIT

_DRIVE_REMOVABLE = 2
_DRIVE_FIXED = 3
_DRIVE_REMOTE = 4
_DRIVE_CDROM = 5
_DRIVE_RAMDISK = 6

# IFileOperation method slots, counting IUnknown's three methods first.
# Order follows the interface declaration: Advise, Unadvise, SetOperationFlags,
# then DeleteItem, PerformOperations, GetAnyOperationsAborted.
_SLOT_RELEASE = 2
_SLOT_SET_OPERATION_FLAGS = 5
# IUnknown is three slots. DeleteItem is the 15th IFileOperation method
# (index 17), PerformOperations index 20, GetAnyOperationsAborted index 21.
_SLOT_DELETE_ITEM = 17
_SLOT_PERFORM = 20
_SLOT_ABORTED = 21

_CLSID_FileOperation = "{3ad05575-8857-4850-9277-11b85bdb8e09}"
_IID_IFileOperation = "{947aab5f-0a5c-4c13-b4d6-4bf7836fc9f8}"
_IID_IShellItem = "{43826d1e-e718-42ee-bc55-a1e261c37bfe}"

Performer = Callable[[Path, int], None]


class RecycleFailed(Exception):
    """The bin did not accept the item. The path is still on disk."""


class RecycleRefused(Exception):
    """Apply-lane refusal. ``reason`` is the enumerated cause, not a delete."""

    def __init__(self, reason: str) -> None:
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class VolumeFacts:
    """What this module could prove about the volume that holds a path."""

    kind: str
    recycle_bin_enabled: bool | None
    max_bytes: int | None


@dataclass(frozen=True)
class RecycleOutcome:
    recycled: bool
    reason: str | None


def primitive_available() -> bool:
    """True when this process can call IFileOperation. Linux and macOS cannot."""
    return os.name == "nt" and sys.platform == "win32"


def require_recycle_flag(flags: int) -> None:
    """Refuse before any delete call when the recycle-on-delete bit is absent."""
    if (flags & FOFX_RECYCLEONDELETE) == 0:
        raise RecycleFailed(
            "FOFX_RECYCLEONDELETE is not set; refusing rather than deleting"
        )


def refusal_reason(path: Path, size: int | None, facts: VolumeFacts) -> str | None:
    """Enumerated reasons the bin must not be asked to take ``path``.

    ``None`` means the pre-checks passed. A later ``IFileOperation`` failure
    is still a refusal; it is not a license to delete permanently.
    """
    text = os.fspath(path)
    if text.startswith("\\\\") or text.startswith("//"):
        return NETWORK_PATH
    if facts.kind == "network":
        return NETWORK_PATH
    if facts.kind in {"removable", "cdrom", "ramdisk"}:
        return REMOVABLE_VOLUME
    if facts.kind != "fixed":
        return RECYCLE_VOLUME_UNVERIFIED
    if facts.recycle_bin_enabled is not True:
        return RECYCLE_BIN_DISABLED
    if size is None or facts.max_bytes is None:
        return RECYCLE_VOLUME_UNVERIFIED
    if size > facts.max_bytes:
        return RECYCLE_BIN_SIZE_LIMIT
    return None


def recycle_or_refuse(
    path: Path,
    *,
    size: int | None,
    facts: VolumeFacts,
    performer: Performer,
    flags: int = RECYCLE_FLAGS,
) -> RecycleOutcome:
    """Recycle ``path`` or return a refusal. Never calls a second deleter."""
    reason = refusal_reason(path, size, facts)
    if reason is not None:
        return RecycleOutcome(False, reason)
    try:
        require_recycle_flag(flags)
        performer(path, flags)
    except RecycleFailed as exc:
        return RecycleOutcome(False, f"{RECYCLE_FAILED}: {exc}")
    return RecycleOutcome(True, None)


def probe_volume(path: Path) -> VolumeFacts:
    """Read drive type and bin policy. Unknown facts stay unknown."""
    if not primitive_available():
        return VolumeFacts("unknown", None, None)
    text = os.fspath(path)
    if text.startswith("\\\\") or text.startswith("//"):
        return VolumeFacts("network", None, None)
    root = os.path.splitdrive(text)[0]
    if not root:
        return VolumeFacts("unknown", None, None)
    drive = root if root.endswith("\\") else root + "\\"
    kind_code = int(ctypes.windll.kernel32.GetDriveTypeW(drive))
    kind = {
        _DRIVE_FIXED: "fixed",
        _DRIVE_REMOTE: "network",
        _DRIVE_REMOVABLE: "removable",
        _DRIVE_CDROM: "cdrom",
        _DRIVE_RAMDISK: "ramdisk",
    }.get(kind_code, "unknown")
    if kind != "fixed":
        return VolumeFacts(kind, None, None)
    enabled, max_bytes = _bin_policy(drive)
    return VolumeFacts("fixed", enabled, max_bytes)


def recycle_path(path: Path, size: int | None = None) -> None:
    """Recycle ``path`` or raise ``RecycleRefused``. Never deletes permanently.

    A missing ``size`` is read from a regular file. A directory with no size
    is unverified and refused: an unknown size is not small enough for the bin.
    """
    if not primitive_available():
        raise RecycleRefused(RECYCLE_PRIMITIVE_UNAVAILABLE)
    if size is None and path.is_file():
        try:
            size = path.stat().st_size
        except OSError:
            size = None
    outcome = recycle_or_refuse(
        path,
        size=size,
        facts=probe_volume(path),
        performer=ifileoperation_recycle,
    )
    if not outcome.recycled:
        raise RecycleRefused(outcome.reason or RECYCLE_FAILED)


def ifileoperation_recycle(path: Path, flags: int) -> None:
    """Move ``path`` to the Recycle Bin. Raises ``RecycleFailed`` on any miss."""
    require_recycle_flag(flags)
    if not primitive_available():
        raise RecycleFailed("IFileOperation is not available on this host")

    class GUID(ctypes.Structure):
        _fields_ = [
            ("Data1", ctypes.c_ulong),
            ("Data2", ctypes.c_ushort),
            ("Data3", ctypes.c_ushort),
            ("Data4", ctypes.c_ubyte * 8),
        ]

    def parse_guid(text: str) -> GUID:
        parsed = GUID()
        hr = ctypes.windll.ole32.CLSIDFromString(c_wchar_p(text), byref(parsed))
        if hr != 0:
            raise RecycleFailed(f"CLSIDFromString failed for {text}: {hr}")
        return parsed

    def com_method(interface: c_void_p, slot: int, restype: object, *argtypes: object):
        table = ctypes.cast(interface, POINTER(c_void_p))[0]
        address = ctypes.cast(table, POINTER(c_void_p))[slot]
        return WINFUNCTYPE(restype, c_void_p, *argtypes)(address)

    def release(interface: c_void_p) -> None:
        if interface.value:
            com_method(interface, _SLOT_RELEASE, c_long)(interface)
            interface.value = None

    ole32 = ctypes.windll.ole32
    shell32 = ctypes.windll.shell32
    need_uninit = False
    operation = c_void_p()
    item = c_void_p()
    try:
        coinit = int(ole32.CoInitializeEx(None, 0x2))  # COINIT_APARTMENTTHREADED
        if coinit in {0, 1}:
            need_uninit = coinit == 0
        elif coinit != -2147417850:  # RPC_E_CHANGED_MODE
            raise RecycleFailed(f"CoInitializeEx failed: {coinit}")
        clsid = parse_guid(_CLSID_FileOperation)
        iid = parse_guid(_IID_IFileOperation)
        hr = int(
            ole32.CoCreateInstance(byref(clsid), None, 1, byref(iid), byref(operation))
        )
        if hr != 0 or not operation.value:
            raise RecycleFailed(f"CoCreateInstance IFileOperation failed: {hr}")
        set_flags = com_method(operation, _SLOT_SET_OPERATION_FLAGS, c_long, ctypes.c_ulong)
        if int(set_flags(operation, flags)) != 0:
            raise RecycleFailed("SetOperationFlags failed")
        shell_iid = parse_guid(_IID_IShellItem)
        hr = int(
            shell32.SHCreateItemFromParsingName(
                c_wchar_p(os.fspath(path)), None, byref(shell_iid), byref(item)
            )
        )
        if hr != 0 or not item.value:
            raise RecycleFailed(f"SHCreateItemFromParsingName failed: {hr}")
        delete_item = com_method(
            operation, _SLOT_DELETE_ITEM, c_long, c_void_p, c_void_p
        )
        if int(delete_item(operation, item, None)) != 0:
            raise RecycleFailed("DeleteItem failed")
        perform = com_method(operation, _SLOT_PERFORM, c_long)
        if int(perform(operation)) != 0:
            raise RecycleFailed("PerformOperations failed")
        aborted = c_int()
        query = com_method(operation, _SLOT_ABORTED, c_long, POINTER(c_int))
        if int(query(operation, byref(aborted))) != 0 or aborted.value:
            raise RecycleFailed("GetAnyOperationsAborted reported an abort")
    finally:
        if item.value:
            release(item)
        if operation.value:
            release(operation)
        if need_uninit:
            ole32.CoUninitialize()


def _bin_policy(drive: str) -> tuple[bool | None, int | None]:
    """Return ``(enabled, max_bytes)``. ``None`` means the read did not prove it.

    ``winreg`` is Windows-only. Importing it at module load would stop the
    Linux engine from importing this primitive.
    """
    try:
        import winreg
    except ImportError:
        return None, None
    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Policies\Explorer",
        ) as key:
            value, _kind = winreg.QueryValueEx(key, "NoRecycleFiles")
            if int(value) != 0:
                return False, None
    except OSError:
        pass
    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket",
        ) as key:
            value, _kind = winreg.QueryValueEx(key, "NukeOnDelete")
            if int(value) != 0:
                return False, None
    except OSError:
        return None, None
    volume = _volume_guid(drive)
    if volume is None:
        return None, None
    try:
        with winreg.OpenKey(
            winreg.HKEY_CURRENT_USER,
            r"Software\Microsoft\Windows\CurrentVersion\Explorer\BitBucket\Volume"
            + "\\"
            + volume,
        ) as key:
            capacity, _kind = winreg.QueryValueEx(key, "MaxCapacity")
    except OSError:
        return None, None
    if not isinstance(capacity, int) or capacity <= 0:
        return None, None
    return True, capacity * 1024 * 1024


def _volume_guid(drive: str) -> str | None:
    if not primitive_available():
        return None
    import ctypes

    buffer = ctypes.create_unicode_buffer(64)
    ok = ctypes.windll.kernel32.GetVolumeNameForVolumeMountPointW(drive, buffer, 64)
    if not ok or not buffer.value:
        return None
    text = buffer.value
    start = text.find("{")
    end = text.find("}")
    if start < 0 or end < start:
        return None
    return text[start : end + 1]

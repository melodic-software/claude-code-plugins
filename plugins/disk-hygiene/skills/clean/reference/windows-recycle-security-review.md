# Windows recycle apply — review packet (#4007, #1116)

This file is the packet for the maintainer review #1116 required before a Windows
deletion lane can merge. It is not that sign-off.

## What deletes

`lib/windows_recycle.py` calls `IFileOperation.SetOperationFlags` with
`FOFX_RECYCLEONDELETE` (`0x00080000`) and then `DeleteItem` / `PerformOperations`.
The module has no `os.unlink`, `os.rmdir`, `shutil.rmtree`, `DeleteFileW`, or
`SHFileOperation` call. `require_recycle_flag` runs before the performer. A
`RecycleFailed` or a pre-check refusal becomes `RecycleRefused` and the path stays.

## What is refused before the call

- network path, including a UNC prefix
- removable, CD, or RAM volume
- bin disabled or bin policy not proven
- item larger than the proven bin max, or a size that was not proven
- volume kind not proven to be fixed

## What stays shared with Linux

`apply` still requires `--execute`, a fresh preview, `--confirm-tier`, and the
approval token in `main` before `apply_plan`. Windows is not a second ceremony.
`execution_blockers` asks for the host primitive: Linux directory descriptors and
mountinfo, or Windows `IFileOperation`. macOS remains `execution-platform-unsupported`.

## What the manual lane is for

A refused path is skipped. The manual handoff stays available for that path and
for macOS. A refused recycle is not a permanent delete.

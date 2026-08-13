"""Stdlib-only HOOK_TELEMETRY_SINK emitter for disk-hygiene Python hooks.

disk-hygiene's wired hooks invoke Python directly (not bash wrappers), so this
module is the fleet's native Python telemetry path — a deliberate parallel to
``lib/hook-utils.sh`` ``hook::emit_telemetry``, not a subprocess wrapper around
it. Contract: ``docs/conventions/hook-telemetry/README.md``.
"""

from __future__ import annotations

import json
import os
import subprocess
import time
from datetime import datetime, timezone
from typing import Any, Mapping

_SCHEMA_VERSION = "1.0"
_HOOK_TELEMETRY_SINK_ENV = "HOOK_TELEMETRY_SINK"
_PROJECT_DIR_ENV = "CLAUDE_PROJECT_DIR"


def telemetry_enabled() -> bool:
    return bool(os.environ.get(_HOOK_TELEMETRY_SINK_ENV))


def _is_absolute_sink_path(sink: str) -> bool:
    if sink.startswith("/"):
        return True
    return len(sink) >= 2 and sink[1] == ":"


def _resolve_sink(sink: str, repo_root: str | None) -> str | None:
    if _is_absolute_sink_path(sink):
        return sink
    root = repo_root or os.environ.get(_PROJECT_DIR_ENV, "")
    if not root:
        return None
    return os.path.join(root, sink)


def _utc_timestamp() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _duration_ms(start: float) -> int:
    return max(0, int((time.perf_counter() - start) * 1000))


def _build_envelope(
    hook_id: str,
    hook_event: str,
    status: str,
    start: float,
    data: Mapping[str, Any],
) -> str:
    envelope = {
        "schema_version": _SCHEMA_VERSION,
        "timestamp": _utc_timestamp(),
        "hook": hook_id,
        "hook_event": hook_event,
        "status": status,
        "duration_ms": _duration_ms(start),
        "data": dict(data),
    }
    return json.dumps(envelope, separators=(",", ":"), ensure_ascii=False)


def _dispatch_sink(sink_path: str, envelope: str) -> None:
    """Launch the sink in an independent process; never wait for it to finish.

    A daemon thread is insufficient: these hooks are short-lived Python commands
    that call ``os._exit`` or return immediately, which terminates daemon threads
    before ``subprocess.run`` completes. Mirror ``hook::emit_telemetry``'s
    background subshell instead.
    """
    try:
        proc = subprocess.Popen(
            [sink_path],
            stdin=subprocess.PIPE,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        if proc.stdin is None:
            return
        proc.stdin.write(envelope.encode("utf-8"))
        proc.stdin.close()
    except (OSError, subprocess.SubprocessError):
        pass


def emit(
    hook_id: str,
    hook_event: str,
    status: str,
    start: float,
    data: Mapping[str, Any] | None = None,
    repo_root: str | None = None,
) -> None:
    """Fire-and-forget one telemetry envelope. No-op when the sink is unset."""
    sink = os.environ.get(_HOOK_TELEMETRY_SINK_ENV, "")
    if not sink:
        return
    resolved = _resolve_sink(sink, repo_root)
    if not resolved:
        return
    envelope = _build_envelope(
        hook_id,
        hook_event,
        status,
        start,
        data or {},
    )
    _dispatch_sink(resolved, envelope)

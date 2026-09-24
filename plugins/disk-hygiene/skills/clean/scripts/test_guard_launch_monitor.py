#!/usr/bin/env python3
"""Behavioral tests for the guard-launch-visibility detector (#1416).

Fixtures below are synthetic, minimal JSONL shaped like real
``hook_non_blocking_error`` transcript attachment records (schema confirmed
against real local transcripts this session — see the module docstring of
``guard_launch_monitor.py``) but contain only the fields the detector
actually reads. No real transcript file, session id, or path is committed
here.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import sys
import tempfile
import time
import unittest
from contextlib import redirect_stdout
from pathlib import Path
from unittest import mock

SCRIPT_DIR = Path(__file__).resolve().parent


def load_module(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPT_DIR / filename)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


monitor = load_module("guard_launch_monitor", "guard_launch_monitor.py")


_GUARD_COMMAND = (
    "python3 ${CLAUDE_PLUGIN_ROOT}/skills/clean/scripts/destructive_guard.py "
    "--mode engine-gate --plugin-root ${CLAUDE_PLUGIN_ROOT} "
    "--authorized-data-root ${CLAUDE_PLUGIN_DATA} "
    "--disk-hygiene-enabled ${user_config.disk_hygiene_enabled}"
)

_OTHER_HOOK_COMMAND = "python3 /some/other/plugin/scripts/other_hook.py --mode check"


def _record(
    *,
    hook_event="PreToolUse",
    command=_GUARD_COMMAND,
    stderr="",
    stdout="",
    exit_code=1,
    duration_ms=11,
    record_session_id="unrelated-record-session",
    attachment_type="hook_non_blocking_error",
    record_type="attachment",
) -> str:
    payload = {
        "parentUuid": "54fcf5e2-dc5f-4e29-accf-7a8489af9906",
        "isSidechain": False,
        "attachment": {
            "type": attachment_type,
            "hookName": f"{hook_event}:Bash",
            "toolUseID": "toolu_01Xj2c8BgDPM7tC75ZyvJMJ4",
            "hookEvent": hook_event,
            "stderr": stderr,
            "stdout": stdout,
            "exitCode": exit_code,
            "command": command,
            "durationMs": duration_ms,
        },
        "type": record_type,
        "uuid": "c8e67437-ea97-444a-821a-e6e062e36f32",
        "timestamp": "2026-07-23T15:41:16.178Z",
        "session_id": record_session_id,
        "userType": "external",
        "entrypoint": "cli",
        "cwd": "C:\\Projects\\<org>\\claude-code-plugins",
        "sessionId": "10bcff28-b64c-490d-8848-de5d6c76a43a",
        "version": "2.1.218",
        "gitBranch": "feat/example",
    }
    return json.dumps(payload)


# A tail-window size the large-transcript fixtures straddle, so a cold scan
# capped to the tail would fail them.
_OLD_TAIL_CAP = 2_000_000


def _filler_line(nbytes: int) -> str:
    """An ignorable ASCII JSONL record occupying exactly ``nbytes`` with its newline."""
    prefix = '{"type": "other", "noise": "'
    suffix = '"}'
    padding = nbytes - 1 - len(prefix) - len(suffix)
    assert padding >= 0, "nbytes too small to hold a record"
    return prefix + "y" * padding + suffix


class GuardLaunchMonitorTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.data_root = Path(self.tmp.name) / "data-root"
        self.transcript_path = Path(self.tmp.name) / "transcript.jsonl"

        # Isolate every test from real machine state: the fallback marker
        # location is tempfile.gettempdir() and the data-root resolution
        # falls back to the real CLAUDE_PLUGIN_DATA env var when no
        # --data-root is supplied (test_unsubstituted_data_root_placeholder_
        # treated_as_absent exercises exactly that "no usable data root"
        # path). Without this isolation those tests would write a
        # once-per-session marker into this machine's real temp dir (or,
        # worse, its real plugin data directory if CLAUDE_PLUGIN_DATA
        # happens to be exported) and never clean it up, making a second
        # run of the suite on the same machine spuriously fail.
        fake_tempdir = Path(self.tmp.name) / "fake-system-tempdir"
        fake_tempdir.mkdir()
        gettempdir_patcher = mock.patch.object(
            monitor.tempfile, "gettempdir", return_value=str(fake_tempdir)
        )
        gettempdir_patcher.start()
        self.addCleanup(gettempdir_patcher.stop)

        env_patcher = mock.patch.dict(
            "os.environ", {"CLAUDE_PLUGIN_DATA": ""}, clear=False
        )
        env_patcher.start()
        self.addCleanup(env_patcher.stop)

    def write_transcript(self, lines: list[str]) -> None:
        self.transcript_path.write_text("\n".join(lines) + "\n", encoding="utf-8")

    def run_monitor(
        self, session_id: str = "session-1", data_root: Path | None = None
    ) -> str | None:
        hook_input = {
            "session_id": session_id,
            "transcript_path": str(self.transcript_path),
        }
        argv = []
        root = self.data_root if data_root is None else data_root
        if root is not None:
            argv = ["--data-root", str(root)]
        stdout = io.StringIO()
        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(stdout):
                exit_code = monitor.main(argv)
        self.assertEqual(0, exit_code)
        text = stdout.getvalue().strip()
        if not text:
            return None
        parsed = json.loads(text)
        return parsed.get("systemMessage")

    def decision_records(self, data_root: Path | None = None) -> list[dict]:
        root = self.data_root if data_root is None else data_root
        path = monitor.guard_decision_log.log_path(str(root))
        if not path.is_file():
            return []
        return [
            json.loads(line)
            for line in path.read_text(encoding="utf-8").splitlines()
            if line.strip()
        ]

    # -- the did-not-run record (#3862) ------------------------------------
    #
    # The guard cannot write this state: a hook that failed to launch, or
    # launched and exited non-zero, records nothing from inside its own
    # process. Only this detector can.

    def test_a_detected_launch_failure_is_recorded_as_did_not_run(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054, stderr="boom")])
        self.assertIsNotNone(self.run_monitor(session_id="session-42"))
        (entry,) = self.decision_records()
        self.assertEqual("not-run", entry["decision"])
        self.assertEqual("guard-launch-monitor", entry["hook"])
        self.assertEqual("hook-non-blocking-error", entry["rule"])
        self.assertEqual(1, entry["failure_count"])
        self.assertEqual(1, entry["exit_code"])
        self.assertEqual(17054, entry["duration_ms"])
        self.assertEqual("boom", entry["stderr"])
        self.assertEqual("session-42", entry["session_id"])
        self.assertTrue(entry["timestamp"].endswith("Z"), entry["timestamp"])

    def test_the_did_not_run_record_reports_the_most_recent_failure(self) -> None:
        self.write_transcript(
            [
                _record(exit_code=1, duration_ms=100, stderr="first failure"),
                _record(exit_code=9, duration_ms=200, stderr="second failure"),
            ]
        )
        self.assertIsNotNone(self.run_monitor())
        (entry,) = self.decision_records()
        self.assertEqual(2, entry["failure_count"])
        self.assertEqual(9, entry["exit_code"])
        self.assertEqual("second failure", entry["stderr"])

    def test_a_clean_transcript_records_nothing(self) -> None:
        self.write_transcript([_record(command=_OTHER_HOOK_COMMAND)])
        self.assertIsNone(self.run_monitor())
        self.assertEqual([], self.decision_records())

    def test_the_did_not_run_record_follows_the_once_per_session_marker(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        self.assertIsNotNone(self.run_monitor())
        self.assertIsNone(self.run_monitor())
        self.assertEqual(1, len(self.decision_records()))

    def test_a_failing_record_write_still_emits_the_warning(self) -> None:
        """The detector's own contract wins: over-warning is the safe direction,
        and an audit write can never suppress a finding."""
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        with mock.patch.object(
            monitor.guard_decision_log, "record", side_effect=OSError("full disk")
        ):
            self.assertIsNotNone(self.run_monitor())

    # -- criterion 3: the #1423 discriminating shape -----------------------

    def test_1423_shape_states_exit_code_and_duration_explicitly(self) -> None:
        self.write_transcript(
            [
                _record(
                    stderr="",
                    exit_code=1,
                    duration_ms=17054,
                )
            ]
        )
        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("destructive_guard.py", message)
        self.assertIn("exitCode: 1", message)
        self.assertIn("durationMs: 17054", message)
        self.assertNotIn("no stderr", message.lower().replace("(no stderr output)", ""))

    def test_empty_stderr_renders_explicit_placeholder(self) -> None:
        self.write_transcript([_record(stderr="", exit_code=1, duration_ms=17054)])
        message = self.run_monitor()
        self.assertIn("(no stderr output)", message)

    # -- criterion 4: launch-refusal shape -----------------------------------

    def test_launch_refusal_shape_warns(self) -> None:
        self.write_transcript(
            [
                _record(
                    stderr=(
                        'Failed to run: Plugin option "disk_hygiene_enabled" '
                        "isn't set. Open /plugin manage to configure it, or "
                        "check that the plugin's userConfig schema declares "
                        '"disk_hygiene_enabled".'
                    ),
                    exit_code=1,
                    duration_ms=11,
                )
            ]
        )
        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("Failed to run", message)
        self.assertIn("disk_hygiene_enabled", message)
        self.assertIn("exitCode: 1", message)
        self.assertIn("durationMs: 11", message)

    # -- criterion 5: no false positives -------------------------------------

    def test_clean_session_with_other_hook_failure_emits_nothing(self) -> None:
        self.write_transcript(
            [
                _record(
                    command=_OTHER_HOOK_COMMAND,
                    stderr="some other hook failed",
                    exit_code=1,
                    duration_ms=42,
                )
            ]
        )
        message = self.run_monitor()
        self.assertIsNone(message)

    def test_fully_clean_session_emits_nothing(self) -> None:
        self.transcript_path.write_text("", encoding="utf-8")
        message = self.run_monitor()
        self.assertIsNone(message)

    # -- criterion 7: unreadable transcript degrades silently ---------------

    def test_unreadable_transcript_path_exits_quietly(self) -> None:
        missing = Path(self.tmp.name) / "does-not-exist.jsonl"
        hook_input = {
            "session_id": "session-x",
            "transcript_path": str(missing),
        }
        stdout = io.StringIO()
        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(stdout):
                exit_code = monitor.main(["--data-root", str(self.data_root)])
        self.assertEqual(0, exit_code)
        self.assertEqual("", stdout.getvalue().strip())

    def test_missing_transcript_path_field_exits_quietly(self) -> None:
        hook_input = {"session_id": "session-y"}
        stdout = io.StringIO()
        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(stdout):
                exit_code = monitor.main(["--data-root", str(self.data_root)])
        self.assertEqual(0, exit_code)
        self.assertEqual("", stdout.getvalue().strip())

    def test_malformed_stdin_exits_quietly(self) -> None:
        stdout = io.StringIO()
        with mock.patch.object(monitor.sys, "stdin", io.StringIO("{not json")):
            with redirect_stdout(stdout):
                exit_code = monitor.main(["--data-root", str(self.data_root)])
        self.assertEqual(0, exit_code)
        self.assertEqual("", stdout.getvalue().strip())

    # -- criterion 8: once-per-session cap -----------------------------------

    def test_second_invocation_same_session_is_suppressed(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        first = self.run_monitor(session_id="same-session")
        self.assertIsNotNone(first)
        second = self.run_monitor(session_id="same-session")
        self.assertIsNone(second)

    def test_different_session_ids_each_warn_once(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        first = self.run_monitor(session_id="session-a")
        second = self.run_monitor(session_id="session-b")
        self.assertIsNotNone(first)
        self.assertIsNotNone(second)

    def test_marker_write_failure_still_emits_warning_this_run(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        with mock.patch.object(
            monitor.Path, "write_text", side_effect=OSError("read-only fs")
        ):
            message = self.run_monitor(session_id="session-unwritable")
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 1", message)

    def test_undelivered_warning_is_not_marked_as_warned(self) -> None:
        """A delivery that never reached the runner must stay repeatable.

        Marking before delivery would let one broken pipe suppress every later
        `Stop` in the session — the exact silence this detector exists to break.
        """
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        hook_input = {
            "session_id": "session-broken-pipe",
            "transcript_path": str(self.transcript_path),
        }
        argv = ["--data-root", str(self.data_root)]

        class _BrokenStdout(io.StringIO):
            def flush(self) -> None:
                raise BrokenPipeError("hook runner closed the pipe")

        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(_BrokenStdout()):
                self.assertEqual(0, monitor.main(argv))

        retry = self.run_monitor(session_id="session-broken-pipe")
        self.assertIsNotNone(retry)
        self.assertIn("exitCode: 1", retry)

    # -- data-root placeholder handling --------------------------------------

    def test_unsubstituted_data_root_placeholder_treated_as_absent(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        hook_input = {
            "session_id": "session-placeholder",
            "transcript_path": str(self.transcript_path),
        }
        stdout = io.StringIO()
        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(stdout):
                exit_code = monitor.main(["--data-root", "${CLAUDE_PLUGIN_DATA}"])
        self.assertEqual(0, exit_code)
        text = stdout.getvalue().strip()
        self.assertTrue(text)
        parsed = json.loads(text)
        self.assertIn("exitCode: 1", parsed["systemMessage"])

    # -- multiple failures: count and most-recent selection ------------------

    def test_multiple_failures_report_count_and_most_recent(self) -> None:
        self.write_transcript(
            [
                _record(exit_code=1, duration_ms=100, stderr="first failure"),
                _record(exit_code=2, duration_ms=200, stderr="second failure"),
            ]
        )
        message = self.run_monitor()
        self.assertIn("2 time", message)
        self.assertIn("exitCode: 2", message)
        self.assertIn("durationMs: 200", message)
        self.assertIn("second failure", message)

    # -- large transcripts: the cold scan reads the whole file ----------------

    def test_tail_read_still_finds_failure_near_end_of_large_transcript(self) -> None:
        filler = json.dumps({"type": "other", "noise": "x" * 200})
        lines = [filler for _ in range(20000)]
        lines.append(_record(exit_code=1, duration_ms=17054))
        self.write_transcript(lines)
        self.assertGreater(self.transcript_path.stat().st_size, _OLD_TAIL_CAP)
        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 1", message)
        self.assertIn("durationMs: 17054", message)

    def test_tail_window_starting_on_a_record_boundary_keeps_that_record(self) -> None:
        """The retained window can begin exactly at a record's first byte.

        Discarding unconditionally would drop a whole record there, and that
        record can be the session's only guard failure.
        """
        failure = _record(exit_code=9, duration_ms=4242, stderr="boundary failure")
        pad = _filler_line(_OLD_TAIL_CAP - len(failure) - 1)
        head = [_filler_line(4096) for _ in range(4)]
        # Written as bytes with explicit LF: the byte offsets are the fixture's
        # whole point, and text mode would insert a platform line ending.
        body = "\n".join(head + [failure, pad]) + "\n"
        self.transcript_path.write_bytes(body.encode("utf-8"))

        size = self.transcript_path.stat().st_size
        self.assertEqual(
            size - _OLD_TAIL_CAP,
            sum(len(line) + 1 for line in head),
            "fixture must place the window boundary exactly at the failure record",
        )

        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 9", message)
        self.assertIn("durationMs: 4242", message)

    def test_head_region_failure_survives_later_oversized_append(self) -> None:
        """#1514: a guard failure more than _OLD_TAIL_CAP from EOF must still warn."""
        failure = _record(exit_code=2, duration_ms=99, stderr="head failure")
        pad = _filler_line(_OLD_TAIL_CAP + 100_000)
        self.write_transcript([failure, pad])
        self.assertGreater(self.transcript_path.stat().st_size, _OLD_TAIL_CAP)
        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 2", message)
        self.assertIn("head failure", message)

    def test_non_attachment_records_are_ignored(self) -> None:
        self.write_transcript(
            [
                json.dumps({"type": "user", "message": "hello"}),
                json.dumps({"type": "assistant", "message": "hi"}),
            ]
        )
        message = self.run_monitor()
        self.assertIsNone(message)

    def test_malformed_json_line_does_not_abort_scan(self) -> None:
        self.write_transcript(
            [
                "{not valid json at all",
                _record(exit_code=1, duration_ms=17054),
            ]
        )
        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 1", message)

    def test_no_permission_decision_or_block_ever_emitted(self) -> None:
        self.write_transcript([_record(exit_code=1, duration_ms=17054)])
        hook_input = {
            "session_id": "session-safety",
            "transcript_path": str(self.transcript_path),
        }
        stdout = io.StringIO()
        with mock.patch.object(
            monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
        ):
            with redirect_stdout(stdout):
                exit_code = monitor.main(["--data-root", str(self.data_root)])
        self.assertEqual(0, exit_code)
        parsed = json.loads(stdout.getvalue().strip())
        self.assertNotIn("permissionDecision", parsed)
        self.assertNotIn("decision", parsed)
        self.assertEqual({"systemMessage"}, set(parsed.keys()))

    # -- telemetry (#1505) ----------------------------------------------------

    def _make_telemetry_sink(self) -> tuple[Path, str]:
        out_file = Path(self.tmp.name) / f"telemetry-{id(self)}.json"
        # Windows cannot exec a #!/bin/sh sink via CreateProcess. A .cmd that
        # runs a sibling .py keeps quoting simple and inherits stdin. Same
        # shape as the guard-telemetry sinks in test_hygiene.py.
        if os.name == "nt":
            sink_py = Path(self.tmp.name) / f"sink-{id(self)}.py"
            sink_py.write_text(
                "import sys\n"
                "from pathlib import Path\n"
                f"Path(r'{out_file}').write_text("
                "sys.stdin.read(), encoding='utf-8')\n",
                encoding="utf-8",
            )
            sink = Path(self.tmp.name) / f"sink-{id(self)}.cmd"
            py = os.fspath(Path(sys.executable).resolve())
            sink.write_text(f'@echo off\r\n"{py}" "{sink_py}"\r\n', encoding="utf-8")
        else:
            sink = Path(self.tmp.name) / f"sink-{id(self)}.sh"
            sink.write_text(f'#!/bin/sh\ncat >"{out_file}"\n', encoding="utf-8")
            sink.chmod(0o755)
        return out_file, str(sink)

    def _wait_for_file(self, path: Path, timeout: float = 5.0) -> None:
        deadline = time.perf_counter() + timeout
        while time.perf_counter() < deadline:
            if path.exists():
                try:
                    if path.read_text(encoding="utf-8").strip():
                        return
                except OSError:
                    pass
            time.sleep(0.05)
        self.fail(f"timed out waiting for telemetry at {path}")

    def test_clean_scan_emits_ok_telemetry_when_sink_wired(self) -> None:
        out_file, sink = self._make_telemetry_sink()
        self.transcript_path.write_text("", encoding="utf-8")
        with mock.patch.dict(
            os.environ,
            {"HOOK_TELEMETRY_SINK": sink, "CLAUDE_PROJECT_DIR": self.tmp.name},
            clear=False,
        ):
            self.run_monitor(session_id="telemetry-clean")
        self._wait_for_file(out_file)
        envelope = json.loads(out_file.read_text(encoding="utf-8").strip())
        self.assertEqual("guard-launch-monitor", envelope["hook"])
        self.assertEqual("Stop", envelope["hook_event"])
        self.assertEqual("ok", envelope["status"])

    def test_failure_scan_emits_error_telemetry_with_count(self) -> None:
        out_file, sink = self._make_telemetry_sink()
        self.write_transcript(
            [
                _record(exit_code=1, duration_ms=11),
                _record(exit_code=2, duration_ms=22),
            ]
        )
        with mock.patch.dict(
            os.environ,
            {"HOOK_TELEMETRY_SINK": sink, "CLAUDE_PROJECT_DIR": self.tmp.name},
            clear=False,
        ):
            self.run_monitor(session_id="telemetry-failure")
        self._wait_for_file(out_file)
        envelope = json.loads(out_file.read_text(encoding="utf-8").strip())
        self.assertEqual("error", envelope["status"])
        self.assertEqual(2, envelope["data"]["failure_count"])

    def test_short_circuit_emits_no_telemetry(self) -> None:
        out_file, sink = self._make_telemetry_sink()
        hook_input = {"session_id": "telemetry-short"}
        stdout = io.StringIO()
        with mock.patch.dict(
            os.environ,
            {"HOOK_TELEMETRY_SINK": sink, "CLAUDE_PROJECT_DIR": self.tmp.name},
            clear=False,
        ):
            with mock.patch.object(
                monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))
            ):
                with redirect_stdout(stdout):
                    monitor.main(["--data-root", str(self.data_root)])
        self.assertFalse(out_file.exists())

    # -- incremental scan: a per-session byte-offset cursor -----------------

    def cursor_path(self, session_id: str = "session-1") -> Path:
        return self.data_root / "guard-launch-monitor" / f"{session_id}.cursor"

    def append(self, text: str) -> None:
        with self.transcript_path.open("ab") as handle:
            handle.write(text.encode("utf-8"))

    def scanned_sizes(self) -> tuple[list[int], mock._patch]:
        """Patch ``_read_new`` to record how many bytes each run scanned."""
        sizes: list[int] = []
        real = monitor._read_new

        def spy(path: str, cursor: int):
            data, offset = real(path, cursor)
            sizes.append(len(data))
            return data, offset

        return sizes, mock.patch.object(monitor, "_read_new", side_effect=spy)

    def test_a_clean_scan_records_a_cursor_at_the_end_of_the_file(self) -> None:
        self.write_transcript([_filler_line(100) for _ in range(10)])
        self.assertIsNone(self.run_monitor())
        size = self.transcript_path.stat().st_size
        self.assertEqual(
            f"b{size}\n{self.transcript_path}\n",
            self.cursor_path().read_text(encoding="utf-8"),
        )

    def test_a_warm_scan_reads_only_the_appended_bytes(self) -> None:
        self.write_transcript([_filler_line(1000) for _ in range(3000)])
        cold_size = self.transcript_path.stat().st_size
        sizes, patch = self.scanned_sizes()
        with patch:
            self.assertIsNone(self.run_monitor())
            appended = _record(exit_code=4, duration_ms=44) + "\n"
            self.append(appended)
            message = self.run_monitor()
        self.assertEqual([cold_size, len(appended)], sizes)
        self.assertIn("1 time this session", message)
        self.assertIn("exitCode: 4", message)

    def test_a_failure_is_reported_once_and_never_missed(self) -> None:
        self.write_transcript([_filler_line(200)])
        self.assertIsNone(self.run_monitor())
        self.append(_filler_line(200) + "\n")
        self.assertIsNone(self.run_monitor())
        self.append(_record(exit_code=5, duration_ms=55) + "\n")
        self.assertIn("exitCode: 5", self.run_monitor())
        self.append(_record(exit_code=6, duration_ms=66) + "\n")
        self.assertIsNone(self.run_monitor())

    def test_a_failure_does_not_advance_the_cursor(self) -> None:
        """An unmarked warning re-warns next Stop with the same count, as before."""
        self.write_transcript([_filler_line(200)])
        self.assertIsNone(self.run_monitor())
        before = self.cursor_path().read_text(encoding="utf-8")
        self.append(_record(exit_code=5, duration_ms=55) + "\n")
        with mock.patch.object(monitor, "_write_marker"):
            first = self.run_monitor()
            second = self.run_monitor()
        self.assertEqual(before, self.cursor_path().read_text(encoding="utf-8"))
        self.assertIsNotNone(first)
        self.assertEqual(first, second)

    def test_a_partial_final_line_is_rescanned_once_complete(self) -> None:
        self.write_transcript([_filler_line(200)])
        clean_size = self.transcript_path.stat().st_size
        failure = _record(exit_code=7, duration_ms=77, stderr="late")
        self.append(failure[:40])
        self.assertIsNone(self.run_monitor())
        self.assertTrue(
            self.cursor_path()
            .read_text(encoding="utf-8")
            .startswith(f"b{clean_size}\n")
        )
        self.append(failure[40:] + "\n")
        message = self.run_monitor()
        self.assertIn("1 time this session", message)
        self.assertIn("late", message)

    def test_a_complete_final_line_without_newline_still_warns(self) -> None:
        self.write_transcript([_filler_line(200)])
        self.assertIsNone(self.run_monitor())
        self.append(_record(exit_code=8, duration_ms=88))
        self.assertIn("exitCode: 8", self.run_monitor())

    def test_a_truncated_transcript_is_scanned_cold(self) -> None:
        self.write_transcript([_filler_line(1000) for _ in range(50)])
        self.assertIsNone(self.run_monitor())
        self.write_transcript([_record(exit_code=3, duration_ms=33)])
        self.assertIn("exitCode: 3", self.run_monitor())

    def test_a_replaced_transcript_of_equal_size_is_scanned_cold(self) -> None:
        """No newline before the cursor means the bytes behind it changed."""
        self.write_transcript([_filler_line(1000)])
        self.assertIsNone(self.run_monitor())
        size = self.transcript_path.stat().st_size
        failure = _record(exit_code=3, duration_ms=33)
        body = failure + "\n" + "x" * (size - len(failure) - 1)
        self.transcript_path.write_bytes(body.encode("utf-8"))
        self.assertEqual(size, self.transcript_path.stat().st_size)
        self.assertIn("exitCode: 3", self.run_monitor())

    def test_a_cursor_for_another_transcript_is_ignored(self) -> None:
        self.write_transcript([_record(exit_code=3, duration_ms=33), _filler_line(200)])
        self.cursor_path().parent.mkdir(parents=True)
        size = self.transcript_path.stat().st_size
        self.cursor_path().write_text(f"b{size}\n/elsewhere.jsonl\n", encoding="utf-8")
        self.assertIn("exitCode: 3", self.run_monitor())

    def test_a_legacy_or_malformed_cursor_is_scanned_cold(self) -> None:
        cursors = ("5\n{path}\n", "b0\n{path}\n", "b007\n{path}\n", "garbage", "")
        for index, content in enumerate(cursors):
            with self.subTest(cursor=content):
                session = f"legacy-{index}"
                self.write_transcript(
                    [_record(exit_code=3, duration_ms=33), _filler_line(200)]
                )
                path = self.cursor_path(session)
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(
                    content.format(path=self.transcript_path), encoding="utf-8"
                )
                self.assertIn("exitCode: 3", self.run_monitor(session_id=session))

    def test_no_data_root_keeps_the_cursor_in_the_tmp_fallback(self) -> None:
        self.write_transcript([_filler_line(5000)])
        sizes, patch = self.scanned_sizes()
        with patch, mock.patch.object(monitor, "_resolve_data_root", return_value=None):
            self.assertIsNone(self.run_monitor())
            self.append(_record(exit_code=2, duration_ms=22) + "\n")
            self.assertIn("exitCode: 2", self.run_monitor())
        self.assertLess(sizes[1], 2000)
        self.assertFalse(self.cursor_path().exists())

    def test_warning_text_is_byte_identical_cold_and_warm(self) -> None:
        """The message for the same records is unchanged by where the scan starts."""
        failures = [
            _record(exit_code=1, duration_ms=100, stderr="first failure"),
            _record(exit_code=2, duration_ms=200, stderr="second failure"),
        ]
        expected = (
            "disk-hygiene: destructive_guard.py failed to run or exited non-zero "
            "2 times this session and its failure(s) were not visible as a denial. "
            "Most recent failure: exitCode: 2, durationMs: 200, stderr: second "
            "failure This means destructive-action review may not have been "
            "enforced for the guarded command(s) in question. This detector covers "
            "only destructive_guard.py's own command string in this session's "
            "transcript; it does not cover repo-hygiene's guard and does not "
            "retroactively scan past sessions."
        )
        self.write_transcript([_filler_line(300)] + failures)
        self.assertEqual(expected, self.run_monitor(session_id="cold"))

        self.write_transcript([_filler_line(300)])
        self.assertIsNone(self.run_monitor(session_id="warm"))
        self.append("\n".join(failures) + "\n")
        self.assertEqual(expected, self.run_monitor(session_id="warm"))


if __name__ == "__main__":
    unittest.main()

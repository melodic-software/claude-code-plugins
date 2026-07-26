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
import tempfile
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
        "cwd": "C:\\Projects\\melodic\\claude-code-plugins",
        "sessionId": "10bcff28-b64c-490d-8848-de5d6c76a43a",
        "version": "2.1.218",
        "gitBranch": "feat/example",
    }
    return json.dumps(payload)


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
        with mock.patch.object(monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))):
            with redirect_stdout(stdout):
                exit_code = monitor.main(argv)
        self.assertEqual(0, exit_code)
        text = stdout.getvalue().strip()
        if not text:
            return None
        parsed = json.loads(text)
        return parsed.get("systemMessage")

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

        with mock.patch.object(monitor.sys, "stdin", io.StringIO(json.dumps(hook_input))):
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
                exit_code = monitor.main(
                    ["--data-root", "${CLAUDE_PLUGIN_DATA}"]
                )
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

    # -- bounded tail read ----------------------------------------------------

    def test_tail_read_still_finds_failure_near_end_of_large_transcript(self) -> None:
        filler = json.dumps({"type": "other", "noise": "x" * 200})
        lines = [filler for _ in range(20000)]
        lines.append(_record(exit_code=1, duration_ms=17054))
        self.write_transcript(lines)
        self.assertGreater(self.transcript_path.stat().st_size, monitor._MAX_TAIL_BYTES)
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
        pad = _filler_line(monitor._MAX_TAIL_BYTES - len(failure) - 1)
        head = [_filler_line(4096) for _ in range(4)]
        # Written as bytes with explicit LF: the byte offsets are the fixture's
        # whole point, and text mode would insert a platform line ending.
        body = "\n".join(head + [failure, pad]) + "\n"
        self.transcript_path.write_bytes(body.encode("utf-8"))

        size = self.transcript_path.stat().st_size
        self.assertEqual(
            size - monitor._MAX_TAIL_BYTES,
            sum(len(line) + 1 for line in head),
            "fixture must place the window boundary exactly at the failure record",
        )

        message = self.run_monitor()
        self.assertIsNotNone(message)
        self.assertIn("exitCode: 9", message)
        self.assertIn("durationMs: 4242", message)

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


if __name__ == "__main__":
    unittest.main()

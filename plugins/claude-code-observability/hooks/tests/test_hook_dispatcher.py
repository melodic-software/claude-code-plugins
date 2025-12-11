#!/usr/bin/env python3
"""Tests for hook_dispatcher.py - Claude Code observability hook dispatcher."""

import json
import os
import sys
import tempfile
from datetime import datetime
from pathlib import Path
from unittest.mock import patch, MagicMock

import pytest

# Add hooks directory to path for imports
hooks_dir = Path(__file__).parent.parent
sys.path.insert(0, str(hooks_dir))


class TestHookDispatcherOptIn:
    """Tests for opt-in behavior via environment variables."""

    def test_disabled_by_default(self, tmp_path, monkeypatch):
        """Hook dispatcher should be disabled by default."""
        monkeypatch.delenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", raising=False)
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        # Import and run main
        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        # No log file should be created
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        assert not log_dir.exists()

    def test_enabled_with_env_var_1(self, tmp_path, monkeypatch):
        """Hook dispatcher should log when CLAUDE_HOOK_LOG_EVENTS_ENABLED=1."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = json.dumps({"test": "data"})
        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        # Log file should be created
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        assert log_dir.exists()
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

    def test_enabled_with_env_var_true(self, tmp_path, monkeypatch):
        """Hook dispatcher should log when CLAUDE_HOOK_LOG_EVENTS_ENABLED=true."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "true")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        assert log_dir.exists()


class TestEventToggling:
    """Tests for individual event toggle via environment variables."""

    def test_individual_event_disabled(self, tmp_path, monkeypatch):
        """Individual events can be disabled via CLAUDE_HOOK_LOG_<EVENT>_ENABLED=0."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_TEST_EVENT_ENABLED", "0")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        # No log file should be created for disabled event
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        assert not log_dir.exists()

    def test_hyphenated_event_name(self, tmp_path, monkeypatch):
        """Event names with hyphens should be converted to underscores in env var."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_PRE_TOOL_USE_ENABLED", "0")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'pre-tool-use']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        assert not log_dir.exists()


class TestJSONParsing:
    """Tests for JSON parsing behavior."""

    def test_valid_json_input(self, tmp_path, monkeypatch):
        """Valid JSON input should be parsed correctly."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "full")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = json.dumps({"tool": "Read", "args": {"file": "test.py"}})
        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

        # Read log entry and verify input was parsed
        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())
        assert entry["input"]["tool"] == "Read"

    def test_invalid_json_input(self, tmp_path, monkeypatch):
        """Invalid JSON input should be stored as raw string."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "full")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = "not valid json {"
        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())
        assert entry["input"]["raw"] == test_input

    def test_empty_stdin(self, tmp_path, monkeypatch):
        """Empty stdin should result in empty input dict."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "full")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test_event']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: "")):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())
        assert entry["input"] == {}


class TestLogFileCreation:
    """Tests for log file creation and format."""

    def test_log_file_name_format(self, tmp_path, monkeypatch):
        """Log file should be named events-YYYY-MM-DD.jsonl."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

        # Verify filename format
        filename = log_files[0].name
        today = datetime.now().strftime("%Y-%m-%d")
        assert filename == f"events-{today}.jsonl"

    def test_log_entry_structure(self, tmp_path, monkeypatch):
        """Log entries should have required fields."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))
        monkeypatch.setenv("CLAUDE_SESSION_ID", "test-session-123")

        from hook_dispatcher import main

        test_input = json.dumps({"session_id": "from-input-123"})
        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Verify required fields
        assert "timestamp" in entry
        assert "event" in entry
        assert "session_id" in entry
        assert "duration_ms" in entry
        assert entry["event"] == "pretooluse"
        # Session ID from input takes precedence in minimal/summary modes
        assert entry["session_id"] == "from-input-123"


class TestVerbosityLevels:
    """Tests for verbosity level configuration."""

    def test_minimal_verbosity(self, tmp_path, monkeypatch):
        """Minimal verbosity should only include basic fields."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "minimal")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = json.dumps({
            "session_id": "sess-123",
            "tool_name": "Bash",
            "tool_input": {"command": "ls"},
            "transcript_path": "/path/to/transcript.jsonl",
            "extra_field": "should_not_appear"
        })
        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Minimal should have these fields
        assert "timestamp" in entry
        assert "event" in entry
        assert "session_id" in entry
        assert "duration_ms" in entry
        assert entry["tool_name"] == "Bash"

        # Minimal should NOT have these fields
        assert "input" not in entry
        assert "transcript_path" not in entry
        assert "tool_use_id" not in entry
        assert "environment" not in entry

    def test_summary_verbosity(self, tmp_path, monkeypatch):
        """Summary verbosity should include reference fields."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "summary")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = json.dumps({
            "session_id": "sess-123",
            "tool_name": "Bash",
            "tool_input": {"command": "ls"},
            "transcript_path": "/path/to/transcript.jsonl",
            "tool_use_id": "toolu_01abc",
            "cwd": "/workspace",
            "permission_mode": "default"
        })
        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Summary should have reference fields
        assert entry["transcript_path"] == "/path/to/transcript.jsonl"
        assert entry["tool_use_id"] == "toolu_01abc"
        assert entry["cwd"] == "/workspace"
        assert entry["permission_mode"] == "default"

        # Summary should NOT have full input
        assert "input" not in entry

    def test_full_verbosity(self, tmp_path, monkeypatch):
        """Full verbosity should include complete input payload."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "full")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))
        monkeypatch.setenv("CLAUDE_MODEL", "opus")

        from hook_dispatcher import main

        test_input = json.dumps({
            "session_id": "sess-123",
            "tool_name": "Bash",
            "tool_input": {"command": "ls -la"},
        })
        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Full should have complete input
        assert "input" in entry
        assert entry["input"]["tool_name"] == "Bash"
        assert entry["input"]["tool_input"]["command"] == "ls -la"

        # Full should have environment
        assert "environment" in entry
        assert entry["environment"]["CLAUDE_MODEL"] == "opus"

    def test_invalid_verbosity_defaults_to_summary(self, tmp_path, monkeypatch):
        """Invalid verbosity value should default to summary."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "invalid_value")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        test_input = json.dumps({"session_id": "sess-123", "cwd": "/workspace"})
        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: test_input)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Should behave like summary (has cwd but no input)
        assert entry["cwd"] == "/workspace"
        assert "input" not in entry


class TestLogRotation:
    """Tests for size-based log rotation."""

    def test_rotation_creates_new_file(self, tmp_path, monkeypatch):
        """When file exceeds max size, rotation should create numbered file."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_ROTATION_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", "0")  # 0MB = always rotate
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        # Create existing log file with some content
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_dir.mkdir(parents=True, exist_ok=True)
        today = datetime.now().strftime("%Y-%m-%d")
        base_file = log_dir / f"events-{today}.jsonl"
        base_file.write_text('{"existing": "entry"}\n')

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        # Should have created a rotated file
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 2
        rotated_file = log_dir / f"events-{today}-001.jsonl"
        assert rotated_file.exists()

    def test_rotation_disabled(self, tmp_path, monkeypatch):
        """When rotation is disabled, should keep using same file."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_ROTATION_ENABLED", "0")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        # Create existing log file with lots of content
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_dir.mkdir(parents=True, exist_ok=True)
        today = datetime.now().strftime("%Y-%m-%d")
        base_file = log_dir / f"events-{today}.jsonl"
        base_file.write_text('{"existing": "entry"}\n' * 1000)

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        # Should still only have one file
        log_files = list(log_dir.glob("events-*.jsonl"))
        assert len(log_files) == 1

    def test_rotation_increments_counter(self, tmp_path, monkeypatch):
        """Rotation should increment counter when previous rotated files exist."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_ROTATION_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB", "0")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_dir.mkdir(parents=True, exist_ok=True)
        today = datetime.now().strftime("%Y-%m-%d")

        # Create base file and first rotated file
        (log_dir / f"events-{today}.jsonl").write_text('{"entry": 1}\n')
        (log_dir / f"events-{today}-001.jsonl").write_text('{"entry": 2}\n')

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        # Should have created -002 file
        rotated_file = log_dir / f"events-{today}-002.jsonl"
        assert rotated_file.exists()


class TestDurationTracking:
    """Tests for duration_ms tracking."""

    def test_duration_ms_present(self, tmp_path, monkeypatch):
        """Log entries should include duration_ms field."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        assert "duration_ms" in entry
        assert isinstance(entry["duration_ms"], (int, float))
        assert entry["duration_ms"] >= 0

    def test_duration_ms_reasonable_value(self, tmp_path, monkeypatch):
        """Duration should be a reasonable value (not too large)."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit):
                    main()

        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_files = list(log_dir.glob("events-*.jsonl"))

        with open(log_files[0], 'r', encoding='utf-8') as f:
            entry = json.loads(f.readline())

        # Duration should be less than 5 seconds for a simple operation
        assert entry["duration_ms"] < 5000


class TestDebugMode:
    """Tests for debug mode error logging."""

    def test_debug_mode_disabled_suppresses_errors(self, tmp_path, monkeypatch):
        """Errors should be suppressed when debug mode is disabled."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))
        monkeypatch.delenv("CLAUDE_HOOK_LOG_DEBUG", raising=False)

        from hook_dispatcher import main

        # Force an error by making the log directory a file
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_dir.parent.mkdir(parents=True, exist_ok=True)
        log_dir.write_text("blocking file")

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                # Should still exit 0 despite error
                assert exc_info.value.code == 0

    def test_debug_mode_enabled_logs_errors(self, tmp_path, monkeypatch, capsys):
        """Errors should be logged to stderr when debug mode is enabled."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))
        monkeypatch.setenv("CLAUDE_HOOK_LOG_DEBUG", "1")

        from hook_dispatcher import main

        # Force an error by making the log directory a file
        log_dir = tmp_path / ".claude" / "logs" / "hooks"
        log_dir.parent.mkdir(parents=True, exist_ok=True)
        log_dir.write_text("blocking file")

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

        captured = capsys.readouterr()
        assert "Hook dispatcher error:" in captured.err


class TestNeverBlocksClaude:
    """Tests to ensure hook dispatcher never blocks Claude Code."""

    def test_always_exits_zero(self, tmp_path, monkeypatch):
        """Hook dispatcher should always exit 0, even on errors."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        # Use an invalid path that will fail
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", "/nonexistent/path/that/should/fail")

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py', 'test']):
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0

    def test_no_arguments(self, tmp_path, monkeypatch):
        """Hook dispatcher should handle missing arguments gracefully."""
        monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "1")
        monkeypatch.setenv("CLAUDE_PROJECT_DIR", str(tmp_path))

        from hook_dispatcher import main

        with patch('sys.argv', ['hook_dispatcher.py']):  # No event name
            with patch('sys.stdin', MagicMock(isatty=lambda: True)):
                with pytest.raises(SystemExit) as exc_info:
                    main()
                assert exc_info.value.code == 0


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

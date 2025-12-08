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

        with patch('sys.argv', ['hook_dispatcher.py', 'pretooluse']):
            with patch('sys.stdin', MagicMock(isatty=lambda: False, read=lambda: "{}")):
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
        assert "input" in entry
        assert entry["event"] == "pretooluse"
        assert entry["session_id"] == "test-session-123"


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

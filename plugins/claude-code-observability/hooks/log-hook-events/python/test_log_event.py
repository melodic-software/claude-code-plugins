"""
Tests for hook event logger.

Run with: pytest test_log_event.py -v
"""

import json
import threading
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Import the module under test
import log_event


@pytest.fixture
def temp_log_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """
    Create temporary log directory and monkey-patch get_log_file_path.

    Args:
        tmp_path: pytest temporary directory
        monkeypatch: pytest monkeypatch fixture

    Returns:
        Temporary log directory path
    """
    log_dir = tmp_path / "logs"
    log_dir.mkdir()

    def mock_get_log_file_path(event_name: str) -> Path:
        event_dir = log_dir / event_name
        event_dir.mkdir(parents=True, exist_ok=True)
        date_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
        return event_dir / f"{date_str}.jsonl"

    monkeypatch.setattr(log_event, "get_log_file_path", mock_get_log_file_path)
    return log_dir


def test_log_file_creation(temp_log_dir: Path) -> None:
    """Test that logging creates JSONL file in correct location."""
    # Arrange
    event_name = "pretooluse"
    stdin_data = {"session_id": "test123", "tool_name": "Read"}

    # Act
    log_event.log_event(event_name, stdin_data)

    # Assert
    event_dir = temp_log_dir / event_name
    assert event_dir.exists()

    log_files = list(event_dir.glob("*.jsonl"))
    assert len(log_files) == 1


def test_json_formatting(temp_log_dir: Path) -> None:
    """Test that log entries are valid JSON with correct structure."""
    # Arrange
    event_name = "posttooluse"
    stdin_data = {
        "session_id": "abc123",
        "tool_name": "Bash",
        "tool_input": {"command": "ls"},
    }

    # Act
    log_event.log_event(event_name, stdin_data)

    # Assert - read and parse log file
    event_dir = temp_log_dir / event_name
    log_file = list(event_dir.glob("*.jsonl"))[0]
    log_text = log_file.read_text(encoding="utf-8")

    # Should be valid JSON
    log_entry = json.loads(log_text.strip())

    # Check structure
    assert log_entry["event"] == event_name
    assert log_entry["stdin"] == stdin_data
    assert log_entry["stdout"] == ""
    assert log_entry["exit_code"] == 0
    assert isinstance(log_entry["duration_ms"], int)
    assert "timestamp" in log_entry


def test_concurrent_writes_no_corruption(temp_log_dir: Path) -> None:
    """Test that concurrent writes don't corrupt log entries."""
    # Arrange
    event_name = "pretooluse"
    num_threads = 5
    entries_per_thread = 20

    def write_entries(thread_id: int) -> None:
        for i in range(entries_per_thread):
            stdin_data = {
                "thread_id": thread_id,
                "entry_num": i,
                "session_id": f"thread{thread_id}",
            }
            log_event.log_event(event_name, stdin_data)

    # Act - spawn threads
    threads = []
    for t in range(num_threads):
        thread = threading.Thread(target=write_entries, args=(t,))
        threads.append(thread)
        thread.start()

    # Wait for all threads
    for thread in threads:
        thread.join()

    # Assert - verify all entries are valid JSON and count is correct
    event_dir = temp_log_dir / event_name
    log_file = list(event_dir.glob("*.jsonl"))[0]
    log_text = log_file.read_text(encoding="utf-8")

    lines = [line for line in log_text.split("\n") if line.strip()]
    assert len(lines) == num_threads * entries_per_thread

    # Verify each line is valid JSON
    for line in lines:
        entry = json.loads(line)
        assert "thread_id" in entry["stdin"]
        assert "entry_num" in entry["stdin"]


def test_config_caching(monkeypatch: pytest.MonkeyPatch, tmp_path: Path) -> None:
    """Test that config checks are cached in environment variables."""
    # Arrange - create fake config file
    config_file = tmp_path / "config.yaml"
    config_file.write_text("enabled: true\nevents:\n  pretooluse:\n    enabled: true\n")

    def mock_resolve_parent() -> Path:
        return tmp_path

    monkeypatch.setattr(Path, "resolve", lambda self: self)
    monkeypatch.setenv("HOOK_LOG_PRETOOLUSE_ENABLED", "")  # Clear cache

    # Monkey-patch to use our test config
    import os

    original_path_init = Path.__init__

    def mock_path_init(self, *args, **kwargs):
        original_path_init(self, *args, **kwargs)

    monkeypatch.setattr(Path, "__init__", mock_path_init)

    # Simpler test: just verify environment caching works
    event_name = "pretooluse"

    # Clear any existing cache
    cache_key = f"HOOK_LOG_{event_name.upper()}_ENABLED"
    if cache_key in os.environ:
        del os.environ[cache_key]

    # First call should cache
    result1 = log_event.is_logging_enabled(event_name)

    # Verify cached
    assert cache_key in os.environ

    # Second call should use cache (not read file again)
    result2 = log_event.is_logging_enabled(event_name)

    assert result1 == result2


def test_invalid_event_name() -> None:
    """Test that invalid event names raise ValueError."""
    with pytest.raises(ValueError, match="cannot be empty"):
        log_event.log_event("", {})

    with pytest.raises(ValueError, match="must be lowercase"):
        log_event.log_event("PreToolUse", {})  # Should be lowercase

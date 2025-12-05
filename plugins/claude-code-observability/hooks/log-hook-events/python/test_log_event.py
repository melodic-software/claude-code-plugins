"""
Tests for hook event logger.

Run with: pytest test_log_event.py -v
"""

import json
import os
import threading
from datetime import datetime, timezone
from pathlib import Path

import pytest

# Import the module under test
import log_event


@pytest.fixture(autouse=True)
def clear_config_cache(monkeypatch: pytest.MonkeyPatch) -> None:
    """Clear config cache and hook env vars before each test."""
    log_event._config_cache = None

    # Clear all CLAUDE_HOOK_LOG_* env vars that might interfere with tests
    env_keys_to_clear = [
        "CLAUDE_HOOK_LOG_EVENTS_ENABLED",
        "CLAUDE_HOOK_LOG_VERBOSITY",
        "CLAUDE_HOOK_LOG_ROTATION_ENABLED",
        "CLAUDE_HOOK_LOG_ROTATION_MAX_SIZE_MB",
        "CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS",
    ]
    # Also clear per-event vars
    for event in log_event.VALID_EVENTS:
        env_keys_to_clear.append(f"CLAUDE_HOOK_LOG_{event.upper()}_ENABLED")
        env_keys_to_clear.append(f"CLAUDE_HOOK_LOG_EVENT_{event.upper()}_VERBOSITY")

    for key in env_keys_to_clear:
        monkeypatch.delenv(key, raising=False)

    yield
    log_event._config_cache = None


@pytest.fixture
def temp_log_dir(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> Path:
    """
    Create temporary log directory and monkey-patch get_log_dir.

    Args:
        tmp_path: pytest temporary directory
        monkeypatch: pytest monkeypatch fixture

    Returns:
        Temporary log directory path
    """
    log_dir = tmp_path / "logs"
    log_dir.mkdir()

    # Also create a minimal config file
    config_dir = tmp_path / "hooks"
    config_dir.mkdir(parents=True)
    config_file = config_dir / "config.yaml"
    config_file.write_text("""
logging:
  enabled: true
  verbosity: full
  rotation:
    enabled: false
  events: {}
""")

    def mock_get_log_dir() -> Path:
        return log_dir

    def mock_get_hooks_dir() -> Path:
        return config_dir

    def mock_get_config_path() -> Path:
        return config_file

    monkeypatch.setattr(log_event, "get_log_dir", mock_get_log_dir)
    monkeypatch.setattr(log_event, "get_hooks_dir", mock_get_hooks_dir)
    monkeypatch.setattr(log_event, "get_config_path", mock_get_config_path)

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

    # Check structure (full verbosity format)
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
        # Full verbosity has stdin field
        assert "thread_id" in entry["stdin"]
        assert "entry_num" in entry["stdin"]


def test_config_loading(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Test that config is loaded correctly from YAML with env overrides."""
    # Clear any cached config
    log_event._config_cache = None

    # Create test config
    config_file = tmp_path / "config.yaml"
    config_file.write_text("""
logging:
  enabled: true
  verbosity: summary
  events:
    pretooluse:
      verbosity: minimal
""")

    def mock_get_config_path() -> Path:
        return config_file

    monkeypatch.setattr(log_event, "get_config_path", mock_get_config_path)

    # Load config
    config = log_event.load_config()

    # Verify YAML values loaded
    assert config["logging"]["enabled"] is True
    assert config["logging"]["verbosity"] == "summary"

    # Verify per-event override
    assert log_event.get_verbosity("pretooluse", config) == "minimal"
    assert log_event.get_verbosity("posttooluse", config) == "summary"  # Falls back to default


def test_env_var_override(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Test that environment variables override YAML config."""
    # Clear any cached config
    log_event._config_cache = None

    # Create test config with summary verbosity
    config_file = tmp_path / "config.yaml"
    config_file.write_text("""
logging:
  enabled: true
  verbosity: summary
""")

    def mock_get_config_path() -> Path:
        return config_file

    monkeypatch.setattr(log_event, "get_config_path", mock_get_config_path)

    # Set env var override to full
    monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "full")

    # Load config
    config = log_event.load_config()

    # Verify env var overrides YAML
    assert config["logging"]["verbosity"] == "full"


def test_invalid_event_name() -> None:
    """Test that invalid event names raise ValueError."""
    with pytest.raises(ValueError, match="cannot be empty"):
        log_event.log_event("", {})

    with pytest.raises(ValueError, match="must be lowercase"):
        log_event.log_event("PreToolUse", {})  # Should be lowercase


def test_verbosity_minimal(temp_log_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Test minimal verbosity format."""
    # Clear cache and set minimal verbosity via env
    log_event._config_cache = None
    monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "minimal")

    event_name = "pretooluse"
    stdin_data = {"session_id": "test123", "tool_name": "Read", "tool_input": {"path": "/test"}}

    log_event.log_event(event_name, stdin_data)

    event_dir = temp_log_dir / event_name
    log_file = list(event_dir.glob("*.jsonl"))[0]
    log_entry = json.loads(log_file.read_text(encoding="utf-8").strip())

    # Minimal format should have shortened keys
    assert "ts" in log_entry
    assert log_entry["event"] == event_name
    assert log_entry["session_id"] == "test123"
    assert log_entry["tool"] == "Read"
    assert "exit" in log_entry
    assert "ms" in log_entry
    # Should NOT have full stdin
    assert "stdin" not in log_entry


def test_verbosity_summary(temp_log_dir: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Test summary verbosity format."""
    # Clear cache and set summary verbosity via env
    log_event._config_cache = None
    monkeypatch.setenv("CLAUDE_HOOK_LOG_VERBOSITY", "summary")

    event_name = "pretooluse"
    stdin_data = {
        "session_id": "test123",
        "tool_name": "Read",
        "tool_use_id": "toolu_abc",
        "transcript_path": "/test/transcript.jsonl",
        "permission_mode": "default",
    }

    log_event.log_event(event_name, stdin_data)

    event_dir = temp_log_dir / event_name
    log_file = list(event_dir.glob("*.jsonl"))[0]
    log_entry = json.loads(log_file.read_text(encoding="utf-8").strip())

    # Summary format should have reference fields
    assert "ts" in log_entry
    assert log_entry["event"] == event_name
    assert log_entry["tool"] == "Read"
    assert log_entry["tool_use_id"] == "toolu_abc"
    assert log_entry["transcript"] == "/test/transcript.jsonl"
    assert log_entry["perm_mode"] == "default"
    # Should NOT have full stdin
    assert "stdin" not in log_entry


def test_is_logging_enabled_master_toggle(monkeypatch: pytest.MonkeyPatch) -> None:
    """Test master enable/disable toggle."""
    # Clear cache
    log_event._config_cache = None

    # Test with master disabled via env
    monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "false")
    assert log_event.is_logging_enabled("pretooluse") is False

    # Clear cache and test with master enabled
    log_event._config_cache = None
    monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "true")
    assert log_event.is_logging_enabled("pretooluse") is True


def test_is_logging_enabled_per_event(monkeypatch: pytest.MonkeyPatch) -> None:
    """Test per-event enable/disable."""
    # Clear cache
    log_event._config_cache = None

    # Enable master
    monkeypatch.setenv("CLAUDE_HOOK_LOG_EVENTS_ENABLED", "true")

    # Disable specific event
    monkeypatch.setenv("CLAUDE_HOOK_LOG_PRETOOLUSE_ENABLED", "false")
    assert log_event.is_logging_enabled("pretooluse") is False

    # Other events should still be enabled
    log_event._config_cache = None
    assert log_event.is_logging_enabled("posttooluse") is True


# =============================================================================
# Rotation Tests
# =============================================================================


def test_rotation_triggers_at_size_threshold(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Test that rotation creates new chunk when file exceeds size limit."""
    log_event._config_cache = None

    log_dir = tmp_path / "logs"
    log_dir.mkdir()
    config_dir = tmp_path / "hooks"
    config_dir.mkdir(parents=True)

    # Config with very small rotation size (1KB)
    config_file = config_dir / "config.yaml"
    config_file.write_text("""
logging:
  enabled: true
  verbosity: full
  rotation:
    enabled: true
    max_file_size_mb: 0.001
""")

    monkeypatch.setattr(log_event, "get_log_dir", lambda: log_dir)
    monkeypatch.setattr(log_event, "get_hooks_dir", lambda: config_dir)
    monkeypatch.setattr(log_event, "get_config_path", lambda: config_file)

    event_name = "pretooluse"
    event_dir = log_dir / event_name
    event_dir.mkdir(parents=True)

    # Create a base file that exceeds the 1KB limit
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    base_file = event_dir / f"{today}.jsonl"
    base_file.write_text("x" * 2000)  # 2KB, exceeds 1KB limit

    # Log a new event
    stdin_data = {"session_id": "test123", "tool_name": "Read"}
    log_event.log_event(event_name, stdin_data)

    # Verify chunk file was created
    chunk_file = event_dir / f"{today}-001.jsonl"
    assert chunk_file.exists(), "Rotation should create chunk file when base exceeds limit"

    # Verify the entry was written to chunk file
    chunk_content = chunk_file.read_text(encoding="utf-8")
    assert "test123" in chunk_content


def test_rotation_disabled(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> None:
    """Test that rotation can be disabled."""
    log_event._config_cache = None

    log_dir = tmp_path / "logs"
    log_dir.mkdir()
    config_dir = tmp_path / "hooks"
    config_dir.mkdir(parents=True)

    # Config with rotation disabled
    config_file = config_dir / "config.yaml"
    config_file.write_text("""
logging:
  enabled: true
  verbosity: full
  rotation:
    enabled: false
    max_file_size_mb: 0.001
""")

    monkeypatch.setattr(log_event, "get_log_dir", lambda: log_dir)
    monkeypatch.setattr(log_event, "get_hooks_dir", lambda: config_dir)
    monkeypatch.setattr(log_event, "get_config_path", lambda: config_file)

    event_name = "pretooluse"
    event_dir = log_dir / event_name
    event_dir.mkdir(parents=True)

    # Create a base file that would exceed limit if rotation enabled
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    base_file = event_dir / f"{today}.jsonl"
    base_file.write_text("x" * 2000)

    # Log a new event
    stdin_data = {"session_id": "test123", "tool_name": "Read"}
    log_event.log_event(event_name, stdin_data)

    # Verify NO chunk file was created (rotation disabled)
    chunk_file = event_dir / f"{today}-001.jsonl"
    assert not chunk_file.exists(), "Rotation disabled should not create chunk files"

    # Verify entry was appended to base file
    base_content = base_file.read_text(encoding="utf-8")
    assert "test123" in base_content


# =============================================================================
# YAML Fallback Tests
# =============================================================================


def test_no_yaml_graceful_fallback(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Test that logging works with defaults when YAML is unavailable."""
    log_event._config_cache = None

    log_dir = tmp_path / "logs"
    log_dir.mkdir()

    monkeypatch.setattr(log_event, "get_log_dir", lambda: log_dir)

    # Simulate YAML not being available
    monkeypatch.setattr(log_event, "YAML_AVAILABLE", False)

    # Load config - should use defaults
    config = log_event.load_config()

    # Verify defaults are used
    assert config["logging"]["enabled"] is True
    assert config["logging"]["verbosity"] == "summary"
    assert config["logging"]["rotation"]["enabled"] is True
    assert config["logging"]["rotation"]["max_file_size_mb"] == 10

    # Verify logging still works
    event_name = "pretooluse"
    stdin_data = {"session_id": "test123", "tool_name": "Read"}
    log_event.log_event(event_name, stdin_data)

    event_dir = log_dir / event_name
    log_files = list(event_dir.glob("*.jsonl"))
    assert len(log_files) == 1


def test_missing_config_file_uses_defaults(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Test that missing config.yaml results in default configuration."""
    log_event._config_cache = None

    log_dir = tmp_path / "logs"
    log_dir.mkdir()

    # Point to non-existent config file
    config_file = tmp_path / "nonexistent" / "config.yaml"

    monkeypatch.setattr(log_event, "get_log_dir", lambda: log_dir)
    monkeypatch.setattr(log_event, "get_config_path", lambda: config_file)

    # Load config - should use defaults
    config = log_event.load_config()

    # Verify defaults
    assert config["logging"]["enabled"] is True
    assert config["logging"]["verbosity"] == "summary"

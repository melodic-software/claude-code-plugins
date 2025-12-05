#!/usr/bin/env python3
"""
Tests for cleanup_logs.py - Claude Code Hook Log Cleanup Utility.

Tests cover:
- Date parsing from log filenames
- Finding old log files
- Cleanup operations (dry run and actual)
- Size formatting
- Empty directory cleanup
"""

import json
import pytest
from datetime import datetime, timedelta
from pathlib import Path

import cleanup_logs


class TestParseDateFromFilename:
    """Tests for parse_log_date function."""

    def test_parse_daily_log_filename(self):
        """Parse date from standard daily log filename."""
        result = cleanup_logs.parse_log_date("2025-12-05.jsonl")
        assert result == datetime(2025, 12, 5)

    def test_parse_rotated_log_filename(self):
        """Parse date from rotated log filename with chunk number."""
        result = cleanup_logs.parse_log_date("2025-12-05-001.jsonl")
        assert result == datetime(2025, 12, 5)

    def test_parse_high_chunk_number(self):
        """Parse date from rotated log with high chunk number."""
        result = cleanup_logs.parse_log_date("2025-01-15-999.jsonl")
        assert result == datetime(2025, 1, 15)

    def test_invalid_filename_raises_valueerror(self):
        """Invalid filename raises ValueError."""
        with pytest.raises(ValueError, match="Cannot parse date"):
            cleanup_logs.parse_log_date("invalid.jsonl")

    def test_incomplete_date_raises_valueerror(self):
        """Filename with incomplete date raises ValueError."""
        with pytest.raises(ValueError, match="Cannot parse date"):
            cleanup_logs.parse_log_date("2025-12.jsonl")

    def test_malformed_date_raises_valueerror(self):
        """Filename with malformed date raises ValueError."""
        with pytest.raises(ValueError, match="does not match format"):
            cleanup_logs.parse_log_date("2025-99-99.jsonl")


class TestFormatSize:
    """Tests for format_size function."""

    def test_format_bytes(self):
        """Format small sizes in bytes."""
        assert cleanup_logs.format_size(0) == "0 B"
        assert cleanup_logs.format_size(512) == "512 B"
        assert cleanup_logs.format_size(1023) == "1023 B"

    def test_format_kilobytes(self):
        """Format sizes in kilobytes."""
        assert cleanup_logs.format_size(1024) == "1.0 KB"
        assert cleanup_logs.format_size(1536) == "1.5 KB"
        assert cleanup_logs.format_size(10240) == "10.0 KB"

    def test_format_megabytes(self):
        """Format sizes in megabytes."""
        assert cleanup_logs.format_size(1024 * 1024) == "1.0 MB"
        assert cleanup_logs.format_size(1024 * 1024 * 5) == "5.0 MB"
        assert cleanup_logs.format_size(int(1024 * 1024 * 2.5)) == "2.5 MB"

    def test_format_gigabytes(self):
        """Format sizes in gigabytes."""
        assert cleanup_logs.format_size(1024 * 1024 * 1024) == "1.00 GB"
        assert cleanup_logs.format_size(int(1024 * 1024 * 1024 * 2.5)) == "2.50 GB"


class TestFindOldLogs:
    """Tests for find_old_logs function."""

    @pytest.fixture
    def temp_log_dir(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
        """Create a temporary log directory structure."""
        log_dir = tmp_path / "logs"
        log_dir.mkdir()
        monkeypatch.setattr(cleanup_logs, "get_log_dir", lambda: log_dir)
        return log_dir

    def test_find_old_logs_empty_directory(self, temp_log_dir: Path):
        """No old logs in empty directory."""
        result = cleanup_logs.find_old_logs(max_age_days=7)
        assert result == []

    def test_find_old_logs_no_old_files(self, temp_log_dir: Path):
        """No old logs when all files are recent."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        # Create today's log
        today = datetime.now().strftime("%Y-%m-%d")
        log_file = event_dir / f"{today}.jsonl"
        log_file.write_text('{"event": "test"}\n')

        result = cleanup_logs.find_old_logs(max_age_days=7)
        assert result == []

    def test_find_old_logs_finds_old_files(self, temp_log_dir: Path):
        """Finds logs older than threshold."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        # Create old log (60 days ago)
        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        # Create recent log
        today = datetime.now().strftime("%Y-%m-%d")
        recent_log = event_dir / f"{today}.jsonl"
        recent_log.write_text('{"event": "recent"}\n')

        result = cleanup_logs.find_old_logs(max_age_days=30)

        assert len(result) == 1
        assert result[0][0] == old_log

    def test_find_old_logs_includes_rotated_files(self, temp_log_dir: Path):
        """Finds old rotated log files."""
        event_dir = temp_log_dir / "posttooluse"
        event_dir.mkdir()

        # Create old base log and rotated chunks
        old_date = (datetime.now() - timedelta(days=45)).strftime("%Y-%m-%d")
        base_log = event_dir / f"{old_date}.jsonl"
        base_log.write_text('{"event": "base"}\n')

        chunk1 = event_dir / f"{old_date}-001.jsonl"
        chunk1.write_text('{"event": "chunk1"}\n')

        chunk2 = event_dir / f"{old_date}-002.jsonl"
        chunk2.write_text('{"event": "chunk2"}\n')

        result = cleanup_logs.find_old_logs(max_age_days=30)

        assert len(result) == 3
        paths = [r[0] for r in result]
        assert base_log in paths
        assert chunk1 in paths
        assert chunk2 in paths

    def test_find_old_logs_multiple_event_dirs(self, temp_log_dir: Path):
        """Finds old logs across multiple event directories."""
        old_date = (datetime.now() - timedelta(days=40)).strftime("%Y-%m-%d")

        for event in ["pretooluse", "posttooluse", "sessionstart"]:
            event_dir = temp_log_dir / event
            event_dir.mkdir()
            log_file = event_dir / f"{old_date}.jsonl"
            log_file.write_text(f'{{"event": "{event}"}}\n')

        result = cleanup_logs.find_old_logs(max_age_days=30)

        assert len(result) == 3

    def test_find_old_logs_sorted_oldest_first(self, temp_log_dir: Path):
        """Results are sorted by date, oldest first."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        # Create logs from different dates
        dates = [60, 45, 90, 35]  # days ago
        for days_ago in dates:
            date_str = (datetime.now() - timedelta(days=days_ago)).strftime("%Y-%m-%d")
            log_file = event_dir / f"{date_str}.jsonl"
            log_file.write_text('{"event": "test"}\n')

        result = cleanup_logs.find_old_logs(max_age_days=30)

        # Should be sorted oldest to newest
        assert len(result) == 4
        dates_found = [r[1] for r in result]
        assert dates_found == sorted(dates_found)

    def test_find_old_logs_ignores_non_jsonl_files(self, temp_log_dir: Path):
        """Ignores non-JSONL files."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")

        # Create JSONL file
        jsonl_file = event_dir / f"{old_date}.jsonl"
        jsonl_file.write_text('{"event": "test"}\n')

        # Create non-JSONL files
        (event_dir / f"{old_date}.txt").write_text("text file")
        (event_dir / f"{old_date}.json").write_text("{}")
        (event_dir / "README.md").write_text("readme")

        result = cleanup_logs.find_old_logs(max_age_days=30)

        assert len(result) == 1
        assert result[0][0] == jsonl_file


class TestCalculateSize:
    """Tests for calculate_size function."""

    def test_calculate_size_empty_list(self):
        """Empty list has zero size."""
        assert cleanup_logs.calculate_size([]) == 0

    def test_calculate_size_single_file(self, tmp_path: Path):
        """Calculate size of single file."""
        test_file = tmp_path / "test.jsonl"
        test_file.write_text("x" * 100)

        files = [(test_file, datetime.now())]
        assert cleanup_logs.calculate_size(files) == 100

    def test_calculate_size_multiple_files(self, tmp_path: Path):
        """Calculate total size of multiple files."""
        file1 = tmp_path / "test1.jsonl"
        file1.write_text("x" * 100)

        file2 = tmp_path / "test2.jsonl"
        file2.write_text("y" * 200)

        file3 = tmp_path / "test3.jsonl"
        file3.write_text("z" * 300)

        files = [
            (file1, datetime.now()),
            (file2, datetime.now()),
            (file3, datetime.now()),
        ]
        assert cleanup_logs.calculate_size(files) == 600


class TestCleanupLogs:
    """Tests for cleanup_logs function."""

    @pytest.fixture
    def temp_log_dir(self, tmp_path: Path, monkeypatch: pytest.MonkeyPatch):
        """Create a temporary log directory structure."""
        log_dir = tmp_path / "logs"
        log_dir.mkdir()
        monkeypatch.setattr(cleanup_logs, "get_log_dir", lambda: log_dir)
        return log_dir

    def test_cleanup_no_old_files(self, temp_log_dir: Path):
        """No files to delete when none are old."""
        result = cleanup_logs.cleanup_logs(max_age_days=30)

        assert result["deleted_count"] == 0
        assert result["deleted_size"] == 0
        assert result["deleted_files"] == []
        assert result["dry_run"] is False

    def test_cleanup_dry_run_does_not_delete(self, temp_log_dir: Path):
        """Dry run mode does not actually delete files."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        result = cleanup_logs.cleanup_logs(max_age_days=30, dry_run=True)

        assert result["deleted_count"] == 1
        assert result["dry_run"] is True
        assert old_log.exists()  # File still exists

    def test_cleanup_actual_delete(self, temp_log_dir: Path):
        """Actual cleanup deletes files."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        result = cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        assert result["deleted_count"] == 1
        assert result["dry_run"] is False
        assert not old_log.exists()  # File deleted

    def test_cleanup_preserves_recent_files(self, temp_log_dir: Path):
        """Cleanup preserves files within retention period."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        # Create old log
        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        # Create recent log
        today = datetime.now().strftime("%Y-%m-%d")
        recent_log = event_dir / f"{today}.jsonl"
        recent_log.write_text('{"event": "recent"}\n')

        result = cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        assert result["deleted_count"] == 1
        assert not old_log.exists()
        assert recent_log.exists()  # Recent file preserved

    def test_cleanup_removes_empty_directories(self, temp_log_dir: Path):
        """Cleanup removes empty event directories."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        # Verify directory exists before cleanup
        assert event_dir.exists()

        cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        # Directory should be removed (was empty after deleting the only file)
        assert not event_dir.exists()

    def test_cleanup_preserves_non_empty_directories(self, temp_log_dir: Path):
        """Cleanup preserves directories that still have files."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        # Create old and recent logs
        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text('{"event": "old"}\n')

        today = datetime.now().strftime("%Y-%m-%d")
        recent_log = event_dir / f"{today}.jsonl"
        recent_log.write_text('{"event": "recent"}\n')

        cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        # Directory should still exist (has recent file)
        assert event_dir.exists()

    def test_cleanup_returns_formatted_size(self, temp_log_dir: Path):
        """Cleanup returns human-readable size."""
        event_dir = temp_log_dir / "pretooluse"
        event_dir.mkdir()

        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")
        old_log = event_dir / f"{old_date}.jsonl"
        old_log.write_text("x" * 2048)  # 2KB

        result = cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        assert result["deleted_size"] == 2048
        assert result["deleted_size_formatted"] == "2.0 KB"

    def test_cleanup_multiple_event_types(self, temp_log_dir: Path):
        """Cleanup works across multiple event directories."""
        old_date = (datetime.now() - timedelta(days=60)).strftime("%Y-%m-%d")

        for event in ["pretooluse", "posttooluse", "sessionstart"]:
            event_dir = temp_log_dir / event
            event_dir.mkdir()
            log_file = event_dir / f"{old_date}.jsonl"
            log_file.write_text(f'{{"event": "{event}"}}\n')

        result = cleanup_logs.cleanup_logs(max_age_days=30, dry_run=False)

        assert result["deleted_count"] == 3

        # All empty directories should be removed
        for event in ["pretooluse", "posttooluse", "sessionstart"]:
            assert not (temp_log_dir / event).exists()


class TestGetLogDir:
    """Tests for get_log_dir function."""

    def test_get_log_dir_with_plugin_root(self, monkeypatch: pytest.MonkeyPatch):
        """Uses CLAUDE_PLUGIN_ROOT when set."""
        monkeypatch.setenv("CLAUDE_PLUGIN_ROOT", "/test/plugin")

        result = cleanup_logs.get_log_dir()

        assert result == Path("/test/plugin/hooks/log-hook-events/logs")

    def test_get_log_dir_fallback_to_relative(self, monkeypatch: pytest.MonkeyPatch):
        """Falls back to relative path when env var not set."""
        monkeypatch.delenv("CLAUDE_PLUGIN_ROOT", raising=False)

        result = cleanup_logs.get_log_dir()

        # Should be relative to the script location
        expected = Path(cleanup_logs.__file__).resolve().parent.parent / "logs"
        assert result == expected


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

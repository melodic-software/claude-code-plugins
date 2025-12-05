#!/usr/bin/env python3
"""
Claude Code Hook Log Cleanup Utility

Cleans up old log files based on retention policy.
Supports dry-run mode, verbose output, and JSON results.

Usage:
    python cleanup_logs.py [--days N] [--dry-run] [--verbose] [--json]

Examples:
    python cleanup_logs.py --days 30              # Delete logs older than 30 days
    python cleanup_logs.py --days 7 --dry-run    # Preview what would be deleted
    python cleanup_logs.py --verbose --json      # Verbose output in JSON format
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple


def get_log_dir() -> Path:
    """Get the directory where log files are stored."""
    # Check for plugin root environment variable
    plugin_root = os.environ.get("CLAUDE_PLUGIN_ROOT")
    if plugin_root:
        return Path(plugin_root) / "hooks" / "log-hook-events" / "logs"

    # Fall back to relative path from this script
    return Path(__file__).resolve().parent.parent / "logs"


def parse_log_date(filename: str) -> datetime:
    """
    Parse date from log filename.

    Supports formats:
    - 2025-12-05.jsonl (daily)
    - 2025-12-05-001.jsonl (rotated)

    Args:
        filename: Log filename (not full path)

    Returns:
        datetime object for the log date

    Raises:
        ValueError: If date cannot be parsed from filename
    """
    stem = Path(filename).stem  # Remove .jsonl extension

    # Split by hyphens: ['2025', '12', '05'] or ['2025', '12', '05', '001']
    parts = stem.split("-")

    if len(parts) >= 3:
        date_str = f"{parts[0]}-{parts[1]}-{parts[2]}"
        return datetime.strptime(date_str, "%Y-%m-%d")

    raise ValueError(f"Cannot parse date from filename: {filename}")


def find_old_logs(max_age_days: int) -> List[Tuple[Path, datetime]]:
    """
    Find all log files older than max_age_days.

    Args:
        max_age_days: Maximum age in days

    Returns:
        List of (path, file_date) tuples, sorted by date (oldest first)
    """
    log_dir = get_log_dir()
    cutoff = datetime.now() - timedelta(days=max_age_days)
    old_files: List[Tuple[Path, datetime]] = []

    if not log_dir.exists():
        return old_files

    # Iterate through event directories
    for event_dir in log_dir.iterdir():
        if not event_dir.is_dir():
            continue

        # Find all JSONL files
        for log_file in event_dir.glob("*.jsonl"):
            try:
                file_date = parse_log_date(log_file.name)
                if file_date < cutoff:
                    old_files.append((log_file, file_date))
            except ValueError:
                # Skip files that don't match expected format
                continue

    # Sort by date (oldest first)
    return sorted(old_files, key=lambda x: x[1])


def calculate_size(files: List[Tuple[Path, datetime]]) -> int:
    """
    Calculate total size of files in bytes.

    Args:
        files: List of (path, date) tuples

    Returns:
        Total size in bytes
    """
    total = 0
    for path, _ in files:
        try:
            total += path.stat().st_size
        except OSError:
            continue
    return total


def format_size(size_bytes: int) -> str:
    """
    Format size in human-readable form.

    Args:
        size_bytes: Size in bytes

    Returns:
        Human-readable size string (e.g., "1.5 MB")
    """
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    elif size_bytes < 1024 * 1024 * 1024:
        return f"{size_bytes / (1024 * 1024):.1f} MB"
    else:
        return f"{size_bytes / (1024 * 1024 * 1024):.2f} GB"


def cleanup_logs(max_age_days: int, dry_run: bool = False,
                 verbose: bool = False) -> dict:
    """
    Delete log files older than max_age_days.

    Args:
        max_age_days: Delete files older than this many days
        dry_run: If True, don't actually delete files
        verbose: If True, print each file being deleted

    Returns:
        dict with cleanup results:
        - deleted_count: Number of files deleted
        - deleted_size: Total size deleted in bytes
        - deleted_size_formatted: Human-readable size
        - deleted_files: List of deleted file paths
        - dry_run: Whether this was a dry run
    """
    old_files = find_old_logs(max_age_days)

    if not old_files:
        return {
            "deleted_count": 0,
            "deleted_size": 0,
            "deleted_size_formatted": "0 B",
            "deleted_files": [],
            "dry_run": dry_run
        }

    total_size = calculate_size(old_files)
    deleted_files: List[str] = []

    for path, file_date in old_files:
        if verbose:
            action = "Would delete" if dry_run else "Deleting"
            print(f"{action}: {path} ({file_date.strftime('%Y-%m-%d')})")

        if not dry_run:
            try:
                path.unlink()
                deleted_files.append(str(path))
            except OSError as e:
                print(f"ERROR: Failed to delete {path}: {e}", file=sys.stderr)
        else:
            deleted_files.append(str(path))

    # Clean up empty directories
    if not dry_run:
        log_dir = get_log_dir()
        if log_dir.exists():
            for event_dir in log_dir.iterdir():
                if event_dir.is_dir():
                    try:
                        # Check if directory is empty
                        if not any(event_dir.iterdir()):
                            event_dir.rmdir()
                    except OSError:
                        # Ignore errors when cleaning up directories
                        pass

    return {
        "deleted_count": len(deleted_files),
        "deleted_size": total_size,
        "deleted_size_formatted": format_size(total_size),
        "deleted_files": deleted_files,
        "dry_run": dry_run
    }


def main() -> int:
    """
    Main entry point for cleanup utility.

    Returns:
        Exit code (0 for success)
    """
    parser = argparse.ArgumentParser(
        description="Clean up old Claude Code hook log files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --days 30              Delete logs older than 30 days
  %(prog)s --days 7 --dry-run    Preview what would be deleted
  %(prog)s --verbose --json      Verbose output in JSON format
"""
    )
    parser.add_argument(
        "--days", "-d",
        type=int,
        default=30,
        help="Delete logs older than this many days (default: 30)"
    )
    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Show what would be deleted without actually deleting"
    )
    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Print each file being deleted"
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON"
    )

    args = parser.parse_args()

    # Validate days
    if args.days < 1:
        print("ERROR: --days must be at least 1", file=sys.stderr)
        return 1

    # Run cleanup
    result = cleanup_logs(
        max_age_days=args.days,
        dry_run=args.dry_run,
        verbose=args.verbose
    )

    # Output results
    if args.json:
        print(json.dumps(result, indent=2))
    else:
        if result["deleted_count"] == 0:
            print(f"No log files older than {args.days} days found.")
        else:
            action = "Would delete" if args.dry_run else "Deleted"
            print(f"{action} {result['deleted_count']} files "
                  f"({result['deleted_size_formatted']})")

    return 0


if __name__ == "__main__":
    sys.exit(main())

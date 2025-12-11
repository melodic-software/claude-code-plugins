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

Environment variables:
    CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS: Default retention period (default: 30)
    CLAUDE_PROJECT_DIR: Project directory containing .claude/logs/hooks/
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import List, Tuple


def get_log_dir() -> Path:
    """
    Get the directory where log files are stored.

    Priority:
    1. CLAUDE_PROJECT_DIR environment variable
    2. Current working directory
    """
    project_dir = os.environ.get("CLAUDE_PROJECT_DIR", os.getcwd())
    return Path(project_dir) / ".claude" / "logs" / "hooks"


def get_default_retention_days() -> int:
    """Get default retention days from environment or use 30."""
    try:
        return int(os.environ.get("CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS", "30"))
    except ValueError:
        return 30


def parse_log_date(filename: str) -> datetime:
    """
    Parse date from log filename.

    Supports formats:
    - events-2025-12-05.jsonl (daily)
    - events-2025-12-05-001.jsonl (rotated)

    Args:
        filename: Log filename (not full path)

    Returns:
        datetime object for the log date

    Raises:
        ValueError: If date cannot be parsed from filename
    """
    stem = Path(filename).stem  # Remove .jsonl extension

    # Remove 'events-' prefix if present
    if stem.startswith("events-"):
        stem = stem[7:]

    # Split by hyphens: ['2025', '12', '05'] or ['2025', '12', '05', '001']
    parts = stem.split("-")

    if len(parts) >= 3:
        date_str = f"{parts[0]}-{parts[1]}-{parts[2]}"
        return datetime.strptime(date_str, "%Y-%m-%d")

    raise ValueError(f"Cannot parse date from filename: {filename}")


def find_old_logs(max_age_days: int) -> List[Tuple[Path, datetime, int]]:
    """
    Find all log files older than max_age_days.

    Args:
        max_age_days: Maximum age in days

    Returns:
        List of (path, file_date, size_bytes) tuples, sorted by date (oldest first)
    """
    log_dir = get_log_dir()
    cutoff = datetime.now() - timedelta(days=max_age_days)
    old_files: List[Tuple[Path, datetime, int]] = []

    if not log_dir.exists():
        return old_files

    # Find all JSONL files in the log directory
    for log_file in log_dir.glob("*.jsonl"):
        try:
            file_date = parse_log_date(log_file.name)
            if file_date < cutoff:
                size = log_file.stat().st_size
                old_files.append((log_file, file_date, size))
        except (ValueError, OSError):
            # Skip files that don't match expected format or can't be accessed
            continue

    # Sort by date (oldest first)
    return sorted(old_files, key=lambda x: x[1])


def format_size(size_bytes: int) -> str:
    """Format byte size as human-readable string."""
    if size_bytes < 1024:
        return f"{size_bytes} B"
    elif size_bytes < 1024 * 1024:
        return f"{size_bytes / 1024:.1f} KB"
    else:
        return f"{size_bytes / (1024 * 1024):.1f} MB"


def cleanup_logs(
    max_age_days: int,
    dry_run: bool = False,
    verbose: bool = False,
    json_output: bool = False,
) -> dict:
    """
    Clean up old log files.

    Args:
        max_age_days: Delete files older than this many days
        dry_run: If True, only report what would be deleted
        verbose: If True, show detailed output
        json_output: If True, output results as JSON

    Returns:
        Dictionary with cleanup results
    """
    old_files = find_old_logs(max_age_days)

    results = {
        "max_age_days": max_age_days,
        "dry_run": dry_run,
        "files_found": len(old_files),
        "files_deleted": 0,
        "bytes_freed": 0,
        "errors": [],
        "files": [],
    }

    if not old_files:
        if not json_output:
            print(f"No log files older than {max_age_days} days found.")
        return results

    total_size = sum(f[2] for f in old_files)

    if verbose and not json_output:
        action = "Would delete" if dry_run else "Deleting"
        print(f"\n{action} {len(old_files)} file(s) totaling {format_size(total_size)}:\n")

    for log_file, file_date, size in old_files:
        file_info = {
            "path": str(log_file),
            "date": file_date.strftime("%Y-%m-%d"),
            "size": size,
            "size_human": format_size(size),
        }

        if verbose and not json_output:
            age_days = (datetime.now() - file_date).days
            print(f"  {log_file.name} ({format_size(size)}, {age_days} days old)")

        if not dry_run:
            try:
                log_file.unlink()
                results["files_deleted"] += 1
                results["bytes_freed"] += size
                file_info["deleted"] = True
            except OSError as e:
                error_msg = f"Failed to delete {log_file}: {e}"
                results["errors"].append(error_msg)
                file_info["deleted"] = False
                file_info["error"] = str(e)
                if not json_output:
                    print(f"  ERROR: {error_msg}", file=sys.stderr)
        else:
            file_info["deleted"] = False  # Dry run

        results["files"].append(file_info)

    if not json_output:
        print()
        if dry_run:
            print(f"Dry run: Would delete {len(old_files)} file(s), freeing {format_size(total_size)}")
        else:
            print(f"Deleted {results['files_deleted']} file(s), freed {format_size(results['bytes_freed'])}")
            if results["errors"]:
                print(f"Encountered {len(results['errors'])} error(s)")

    return results


def main():
    """Main entry point."""
    parser = argparse.ArgumentParser(
        description="Clean up old Claude Code hook log files",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --days 30              Delete logs older than 30 days
  %(prog)s --days 7 --dry-run     Preview what would be deleted
  %(prog)s --verbose --json       Verbose output in JSON format

Environment:
  CLAUDE_HOOK_LOG_RETENTION_MAX_AGE_DAYS  Default retention period
  CLAUDE_PROJECT_DIR                       Project directory location
        """,
    )

    parser.add_argument(
        "--days", "-d",
        type=int,
        default=get_default_retention_days(),
        help=f"Delete logs older than N days (default: {get_default_retention_days()})",
    )

    parser.add_argument(
        "--dry-run", "-n",
        action="store_true",
        help="Preview what would be deleted without actually deleting",
    )

    parser.add_argument(
        "--verbose", "-v",
        action="store_true",
        help="Show detailed output for each file",
    )

    parser.add_argument(
        "--json", "-j",
        action="store_true",
        dest="json_output",
        help="Output results as JSON",
    )

    args = parser.parse_args()

    results = cleanup_logs(
        max_age_days=args.days,
        dry_run=args.dry_run,
        verbose=args.verbose,
        json_output=args.json_output,
    )

    if args.json_output:
        print(json.dumps(results, indent=2))

    # Exit with error code if there were errors
    sys.exit(1 if results["errors"] else 0)


if __name__ == "__main__":
    main()

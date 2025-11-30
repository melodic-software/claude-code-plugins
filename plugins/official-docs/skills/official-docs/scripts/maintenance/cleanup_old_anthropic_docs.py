#!/usr/bin/env python3
"""
Cleanup old Anthropic documentation files based on published_at dates.

This script removes documentation files older than the specified age threshold
from both the filesystem and the index.

**Purpose:** General cleanup for any Anthropic documentation that has a published_at
date and exceeds the age threshold. Works across all categories.

**Difference from cleanup_old_anthropic_publications.py:**
- This script: General cleanup for ANY Anthropic docs with published_at (all categories)
- cleanup_old_anthropic_publications.py: Specific cleanup for engineering/news/research
  posts only, with stricter requirements (must have published_at, specific categories)

These scripts serve different purposes and should remain separate.
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from datetime import datetime, timedelta
import argparse

# Add parent directory to path for imports
sys.path.insert(0, str(Path(__file__).parent))
from management.index_manager import IndexManager
from utils.script_utils import configure_utf8_output

configure_utf8_output()

def cleanup_old_docs(base_dir: Path, max_age_days: int, dry_run: bool = True, delete_files: bool = True):
    """
    Remove documentation files older than max_age_days based on published_at.

    Args:
        base_dir: Base directory containing references
        max_age_days: Maximum age in days (files older than this will be removed)
        dry_run: If True, only report what would be deleted without actually deleting
        delete_files: If True, delete files from filesystem (in addition to removing from index)
    """
    manager = IndexManager(base_dir)
    index = manager.load_all()

    cutoff_date = datetime.now() - timedelta(days=max_age_days)
    cutoff_str = cutoff_date.strftime('%Y-%m-%d')

    print(f"🗑️  Cleanup old Anthropic documentation")
    print(f"Threshold: {cutoff_str} ({max_age_days} days ago)")
    print(f"Mode: {'DRY RUN (no changes)' if dry_run else 'LIVE (will delete)'}")
    print()

    old_docs = []

    # Find all documents with published_at older than cutoff
    for doc_id, entry in index.items():
        if 'published_at' not in entry:
            continue

        # Only process Anthropic docs
        if not entry.get('domain', '').startswith('anthropic'):
            continue

        published_at = entry['published_at']
        pub_date = datetime.strptime(published_at, '%Y-%m-%d')

        if pub_date < cutoff_date:
            days_old = (datetime.now() - pub_date).days
            old_docs.append({
                'doc_id': doc_id,
                'path': entry.get('path', ''),
                'published_at': published_at,
                'days_old': days_old,
                'category': entry.get('category', 'unknown')
            })

    if not old_docs:
        print("✅ No old documents found. All Anthropic docs are within the age threshold.")
        return 0

    # Sort by age (oldest first)
    old_docs.sort(key=lambda x: x['days_old'], reverse=True)

    print(f"Found {len(old_docs)} documents older than {max_age_days} days:")
    print()

    # Group by category
    by_category = {}
    for doc in old_docs:
        cat = doc['category']
        if cat not in by_category:
            by_category[cat] = []
        by_category[cat].append(doc)

    for category, docs in sorted(by_category.items()):
        print(f"📁 {category.upper()} ({len(docs)} files):")
        for doc in docs:
            print(f"   {doc['published_at']} ({doc['days_old']:4d} days old): {doc['path']}")
        print()

    if dry_run:
        print("🔍 DRY RUN MODE - No changes made")
        print(f"Run with --execute to actually delete {len(old_docs)} files")
        return 0

    # Actually delete files
    print(f"🗑️  Deleting {len(old_docs)} files...")
    deleted_count = 0
    failed_count = 0

    for doc in old_docs:
        doc_id = doc['doc_id']
        file_path = base_dir / doc['path']

        try:
            # Delete file if it exists
            if file_path.exists():
                file_path.unlink()
                print(f"✅ Deleted: {doc['path']}")
            else:
                print(f"⚠️  File not found (already deleted?): {doc['path']}")

            # Remove from index
            manager.remove_entry(doc_id)
            deleted_count += 1

        except Exception as e:
            print(f"❌ Failed to delete {doc['path']}: {e}")
            failed_count += 1

    print()
    print(f"✅ Cleanup complete:")
    print(f"   Deleted: {deleted_count} files")
    if failed_count > 0:
        print(f"   Failed:  {failed_count} files")

    return deleted_count

def main() -> None:
    parser = argparse.ArgumentParser(
        description='Cleanup old Anthropic documentation files based on published_at dates'
    )
    parser.add_argument(
        '--max-age',
        type=int,
        default=365,
        help='Maximum age in days (default: 365)'
    )
    parser.add_argument(
        '--execute',
        action='store_true',
        help='Actually delete files (default is dry-run)'
    )
    from cli_utils import add_base_dir_argument, resolve_base_dir_from_args
    add_base_dir_argument(parser)

    args = parser.parse_args()

    # Resolve base directory using cli_utils helper
    base_dir = resolve_base_dir_from_args(args)
    
    if not base_dir.exists():
        print(f"❌ Error: Base directory not found: {base_dir}")
        return 1

    cleanup_old_docs(
        base_dir=base_dir,
        max_age_days=args.max_age,
        dry_run=not args.execute
    )

    return 0

if __name__ == '__main__':
    sys.exit(main())

#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
cleanup_old_anthropic_publications.py - Remove stale Anthropic posts by publication date

Purpose:
- Enforce a hard recency window for Anthropic engineering, news, and research posts
  based on the `published_at` date extracted from the article content.

Behavior:
- Loads index.yaml via IndexManager.
- For entries where:
    - domain == "anthropic.com"
    - category in {"engineering", "news", "research"}
    - published_at is present and older than the cutoff (e.g., 365 days ago)
  it will:
    - Delete the corresponding markdown file under the base directory (default: .claude/skills/official-docs/canonical from config).
    - Remove the entry from index.yaml.

Notes:
- It does NOT delete entries without a `published_at` field. Those are logged for
  follow-up rather than being aggressively removed.
- Run this AFTER:
  1. Scraping (to ensure canonical docs exist)
  2. Running `extract_publication_dates.py` (to populate published_at)
  3. Running `refresh_index.py` (to ensure index.yaml is consistent)

Usage:
    python cleanup_old_anthropic_publications.py --max-age 365
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import argparse
from datetime import datetime, timedelta, timezone

from utils.common_paths import find_repo_root
from management.index_manager import IndexManager
from utils.script_utils import configure_utf8_output

configure_utf8_output()

def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Remove Anthropic engineering/news/research posts older than max-age days based on published_at.",
    )
    parser.add_argument(
        "--max-age",
        type=int,
        default=365,
        help="Maximum age in days for Anthropic posts (default: 365).",
    )
    return parser.parse_args()

def main() -> int:
    args = parse_args()
    max_age_days = args.max_age

    # Use path_config for base_dir
    try:
        from path_config import get_base_dir
        base_dir = get_base_dir()
    except ImportError:
        repo_root = find_repo_root()
        base_dir = repo_root / ".claude" / "references"
    manager = IndexManager(base_dir)
    index = manager.load_all()

    cutoff_date = datetime.now(timezone.utc).date() - timedelta(days=max_age_days)
    print(f"Enforcing Anthropic recency window: {max_age_days} days (published_at >= {cutoff_date})")

    removed_count = 0
    skipped_missing_date = 0

    for doc_id, meta in list(index.items()):
        if not isinstance(meta, dict):
            continue

        domain = meta.get("domain")
        category = meta.get("category")

        if domain != "anthropic.com" or category not in {"engineering", "news", "research"}:
            continue

        published_at = meta.get("published_at")
        if not published_at:
            # We require a concrete publication date to make a decision.
            skipped_missing_date += 1
            print(f"⚠️  Skipping {doc_id}: no published_at in index metadata")
            continue

        try:
            pub_date = datetime.fromisoformat(published_at).date()
        except Exception:
            skipped_missing_date += 1
            print(f"⚠️  Skipping {doc_id}: invalid published_at value ({published_at})")
            continue

        if pub_date < cutoff_date:
            # Remove markdown file
            rel_path = meta.get("path")
            if rel_path:
                md_path = base_dir / rel_path
                if md_path.exists():
                    try:
                        md_path.unlink()
                        print(f"🗑️  Deleted stale file: {md_path}")
                    except Exception as e:
                        print(f"⚠️  Failed to delete {md_path}: {e}")

            # Remove from index
            if manager.remove_entry(doc_id):
                removed_count += 1
                print(f"✅ Removed stale index entry: {doc_id} (published_at={published_at})")
            else:
                print(f"⚠️  Failed to remove index entry: {doc_id}")

    print()
    print(f"Summary:")
    print(f"  Removed entries: {removed_count}")
    print(f"  Skipped (missing/invalid published_at): {skipped_missing_date}")

    return 0

if __name__ == "__main__":
    raise SystemExit(main())


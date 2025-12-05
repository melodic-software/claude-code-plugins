#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
discover_categories.py - Discover documentation sections from llms.txt

Extracts unique sections/categories from llms.txt for documentation discovery.
Since Gemini CLI uses llms.txt format (not sitemap.xml), this script parses
markdown links to discover documentation structure.

Usage:
    python discover_categories.py --llms-txt https://geminicli.com/llms.txt
    python discover_categories.py --llms-txt https://geminicli.com/llms.txt --format json
    python discover_categories.py --local  # Use cached llms.txt

Dependencies:
    pip install requests
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import bootstrap; skill_dir = bootstrap.skill_dir

import argparse
import re
from collections import Counter

from utils.script_utils import configure_utf8_output
configure_utf8_output()

try:
    import requests
except ImportError:
    print("❌ Missing dependency: requests")
    print("Install with: pip install requests")
    sys.exit(1)


def fetch_llms_txt(url: str) -> str:
    """
    Fetch llms.txt content from URL

    Args:
        url: URL to llms.txt file

    Returns:
        Content of llms.txt as string
    """
    try:
        print(f"📄 Fetching llms.txt: {url}")
        from utils.config_helpers import get_http_timeout
        timeout = get_http_timeout()
        response = requests.get(url, timeout=timeout, headers={
            'User-Agent': 'gemini-cli-docs-discovery/1.0'
        })
        response.raise_for_status()
        return response.text
    except requests.RequestException as e:
        print(f"❌ Error fetching llms.txt: {e}")
        return ""


def load_local_llms_txt() -> str:
    """
    Load cached llms.txt from local storage

    Returns:
        Content of llms.txt as string, or empty string if not found
    """
    # Check common locations for cached llms.txt
    cache_locations = [
        skill_dir / 'cache' / 'llms.txt',
        skill_dir / 'canonical' / 'llms.txt',
    ]

    for cache_path in cache_locations:
        if cache_path.exists():
            print(f"📄 Loading local llms.txt: {cache_path}")
            return cache_path.read_text(encoding='utf-8')

    print("❌ No local llms.txt found")
    return ""


def discover_sections(content: str) -> dict:
    """
    Discover sections/categories from llms.txt content

    Args:
        content: llms.txt content

    Returns:
        Dictionary with discovered sections and URLs
    """
    if not content:
        return {'sections': [], 'urls': [], 'url_count': 0}

    # Extract all markdown links: [title](url)
    url_pattern = r'\[([^\]]+)\]\(([^)]+)\)'
    matches = re.findall(url_pattern, content)

    sections = Counter()
    urls = []

    for title, url in matches:
        if not url.startswith('http'):
            continue

        urls.append({'title': title.strip(), 'url': url})

        # Extract section from URL path
        # e.g., https://geminicli.com/docs/getting-started -> docs
        # e.g., https://geminicli.com/guides/advanced -> guides
        path_match = re.search(r'geminicli\.com/([^/]+)', url)
        if path_match:
            section = path_match.group(1)
            # Normalize section name
            if section not in ['llms.txt', 'llms-full.txt']:
                sections[section] += 1

    # Also look for markdown headers as section indicators
    header_pattern = r'^#+\s+(.+)$'
    headers = re.findall(header_pattern, content, re.MULTILINE)

    return {
        'sections': sorted(sections.keys()),
        'section_counts': dict(sections.most_common()),
        'headers': headers,
        'urls': urls,
        'url_count': len(urls)
    }


def main() -> None:
    """Main entry point"""
    parser = argparse.ArgumentParser(
        description='Discover documentation sections from llms.txt',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Discover sections from remote llms.txt
  python discover_categories.py --llms-txt https://geminicli.com/llms.txt

  # Use locally cached llms.txt
  python discover_categories.py --local

  # Output as JSON
  python discover_categories.py --llms-txt https://geminicli.com/llms.txt --format json

  # Show URL details
  python discover_categories.py --llms-txt https://geminicli.com/llms.txt --show-urls
        """
    )

    source_group = parser.add_mutually_exclusive_group(required=True)
    source_group.add_argument('--llms-txt',
                              help='URL to llms.txt (e.g., https://geminicli.com/llms.txt)')
    source_group.add_argument('--local', action='store_true',
                              help='Use locally cached llms.txt')

    parser.add_argument('--format', choices=['list', 'json', 'summary'], default='list',
                       help='Output format (default: list)')
    parser.add_argument('--show-urls', action='store_true',
                       help='Show all discovered URLs')

    args = parser.parse_args()

    # Fetch or load llms.txt content
    if args.local:
        content = load_local_llms_txt()
    else:
        content = fetch_llms_txt(args.llms_txt)

    if not content:
        print("\n❌ No content to analyze")
        sys.exit(1)

    # Discover sections
    result = discover_sections(content)

    if not result['sections'] and not result['urls']:
        print("\n❌ No sections or URLs found")
        sys.exit(1)

    # Output in requested format
    if args.format == 'json':
        import json
        output = {
            'source': args.llms_txt if args.llms_txt else 'local',
            'sections': result['sections'],
            'section_counts': result['section_counts'],
            'headers': result['headers'],
            'url_count': result['url_count']
        }
        if args.show_urls:
            output['urls'] = result['urls']
        print(json.dumps(output, indent=2))

    elif args.format == 'summary':
        print(f"\n📊 llms.txt Summary")
        print("=" * 50)
        print(f"Total URLs: {result['url_count']}")
        print(f"Sections found: {len(result['sections'])}")
        if result['section_counts']:
            print(f"\nSection breakdown:")
            for section, count in sorted(result['section_counts'].items(), key=lambda x: -x[1]):
                print(f"   {section}: {count} URLs")
        if result['headers']:
            print(f"\nMarkdown headers ({len(result['headers'])}):")
            for header in result['headers'][:10]:  # Show first 10
                print(f"   • {header}")
            if len(result['headers']) > 10:
                print(f"   ... and {len(result['headers']) - 10} more")

    else:  # list format
        print(f"\n📋 Sections found ({len(result['sections'])}):")
        for section in result['sections']:
            count = result['section_counts'].get(section, 0)
            print(f"   /{section}/ ({count} URLs)")

        if result['headers']:
            print(f"\n📋 Document headers ({len(result['headers'])}):")
            for header in result['headers']:
                print(f"   • {header}")

        if args.show_urls:
            print(f"\n📋 URLs ({result['url_count']}):")
            for item in result['urls']:
                print(f"   [{item['title']}]")
                print(f"      {item['url']}")

    sys.exit(0)


if __name__ == '__main__':
    main()

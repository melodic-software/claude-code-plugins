#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
llms_parser.py - Parse llms.txt and llms-full.txt formats.

This module provides parsers for the llms.txt ecosystem:
- llms.txt: Discovery index with markdown links [Title](URL): Description
- llms-full.txt: Full rendered documentation with # Title / Source: URL headers

Usage:
    from core.llms_parser import LlmsParser, LlmsFullParser, LlmsEntry, LlmsFullPage

    # Parse llms.txt for URL discovery
    parser = LlmsParser()
    for entry in parser.parse(content):
        print(f"{entry.title}: {entry.url}")

    # Stream parse llms-full.txt for content (memory-efficient)
    full_parser = LlmsFullParser()
    for page in full_parser.parse_stream(content):
        print(f"{page.title}: {len(page.content)} chars")
"""

import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

import re
from dataclasses import dataclass
from typing import Generator


@dataclass
class LlmsEntry:
    """Entry from llms.txt discovery file."""
    title: str
    url: str
    description: str | None = None
    section: str | None = None


@dataclass
class LlmsFullPage:
    """Single page from llms-full.txt content file."""
    title: str
    source_url: str
    content: str


class LlmsParser:
    """
    Parser for llms.txt discovery index format.

    llms.txt format:
        # Site Title
        ## Section
        - [Page Title](https://example.com/page.md): Optional description
        - [Another Page](https://example.com/another.md)

    This format is similar to docs-map but with optional descriptions.
    """

    # Pattern: - [Title](URL): Optional description
    # Also handles - [Title](URL) without description
    ENTRY_PATTERN = re.compile(
        r'^-\s*\[([^\]]+)\]\((https?://[^\)]+)\)(?::\s*(.*))?$'
    )

    # Section header: ## Section Name
    SECTION_PATTERN = re.compile(r'^##\s+(.+)$')

    def parse(self, content: str) -> Generator[LlmsEntry, None, None]:
        """
        Parse llms.txt content, yielding entries.

        Args:
            content: Full text content of llms.txt file

        Yields:
            LlmsEntry objects for each documentation link found
        """
        current_section = None

        for line in content.splitlines():
            line = line.strip()

            if not line:
                continue

            # Check for section header
            section_match = self.SECTION_PATTERN.match(line)
            if section_match:
                current_section = section_match.group(1).strip()
                continue

            # Check for entry
            entry_match = self.ENTRY_PATTERN.match(line)
            if entry_match:
                title = entry_match.group(1).strip()
                url = entry_match.group(2).strip()
                description = entry_match.group(3)
                if description:
                    description = description.strip()

                yield LlmsEntry(
                    title=title,
                    url=url,
                    description=description if description else None,
                    section=current_section
                )

    def parse_to_list(self, content: str) -> list[LlmsEntry]:
        """Parse llms.txt and return all entries as a list."""
        return list(self.parse(content))

    def extract_urls(self, content: str) -> list[str]:
        """Extract just the URLs from llms.txt content."""
        return [entry.url for entry in self.parse(content)]

    def extract_urls_by_section(self, content: str) -> dict[str | None, list[str]]:
        """Extract URLs grouped by section."""
        sections: dict[str | None, list[str]] = {}
        for entry in self.parse(content):
            if entry.section not in sections:
                sections[entry.section] = []
            sections[entry.section].append(entry.url)
        return sections


class LlmsFullParser:
    """
    Stream parser for llms-full.txt content format.

    llms-full.txt format (each page separated by title/source headers):
        # Page Title
        Source: https://example.com/page.md

        [Full markdown content of the page...]

        # Next Page Title
        Source: https://example.com/next.md

        [Next page content...]

    This parser is memory-efficient for large files (6M+ tokens).
    """

    # Title pattern: # Page Title (at start of line)
    TITLE_PATTERN = re.compile(r'^#\s+(.+)$')

    # Source pattern: Source: URL
    SOURCE_PATTERN = re.compile(r'^Source:\s*(https?://\S+)\s*$', re.IGNORECASE)

    def parse_stream(self, content: str) -> Generator[LlmsFullPage, None, None]:
        """
        Stream parse llms-full.txt, yielding pages one at a time.

        Memory-efficient for large files - only holds one page in memory at a time.

        Args:
            content: Full text content of llms-full.txt file

        Yields:
            LlmsFullPage objects for each documentation page found
        """
        current_title: str | None = None
        current_source: str | None = None
        content_lines: list[str] = []
        in_content = False

        for line in content.splitlines():
            # Check for new page title (# Title at start of line)
            title_match = self.TITLE_PATTERN.match(line)
            if title_match:
                # Yield previous page if exists and valid
                if current_title and current_source:
                    yield LlmsFullPage(
                        title=current_title,
                        source_url=current_source,
                        content='\n'.join(content_lines).strip()
                    )

                # Start new page
                current_title = title_match.group(1).strip()
                current_source = None
                content_lines = []
                in_content = False
                continue

            # Check for source URL (must follow title)
            source_match = self.SOURCE_PATTERN.match(line)
            if source_match and current_title and not current_source:
                current_source = source_match.group(1).strip()
                in_content = True
                continue

            # Accumulate content (only after we have title and source)
            if in_content and current_source:
                content_lines.append(line)

        # Yield final page
        if current_title and current_source:
            yield LlmsFullPage(
                title=current_title,
                source_url=current_source,
                content='\n'.join(content_lines).strip()
            )

    def parse_to_list(self, content: str) -> list[LlmsFullPage]:
        """Parse llms-full.txt and return all pages as a list."""
        return list(self.parse_stream(content))

    def count_pages(self, content: str) -> int:
        """Count pages without storing all content."""
        count = 0
        for _ in self.parse_stream(content):
            count += 1
        return count

    def get_page_by_url(self, content: str, target_url: str) -> LlmsFullPage | None:
        """Find a specific page by URL."""
        for page in self.parse_stream(content):
            if page.source_url == target_url:
                return page
        return None


def parse_llms_txt(content: str) -> list[str]:
    """
    Convenience function to parse llms.txt and extract URLs.

    Compatible with the existing parse_docs_map pattern.

    Args:
        content: llms.txt file content

    Returns:
        List of documentation URLs
    """
    parser = LlmsParser()
    return parser.extract_urls(content)


def parse_llms_full_txt(content: str) -> Generator[LlmsFullPage, None, None]:
    """
    Convenience function to stream parse llms-full.txt.

    Args:
        content: llms-full.txt file content

    Yields:
        LlmsFullPage objects
    """
    parser = LlmsFullParser()
    yield from parser.parse_stream(content)


def url_to_local_path(source_url: str, base_dir: str | Path) -> Path:
    """
    Convert a documentation URL to a local file path.

    This helper extracts the path from a URL and combines it with a base directory
    to produce a local file path for storing the documentation.

    Args:
        source_url: Full URL like "https://code.claude.com/docs/en/overview.md"
        base_dir: Base output directory (can be string or Path)

    Returns:
        Local path like "<base_dir>/docs/en/overview.md"

    Example:
        >>> url_to_local_path("https://code.claude.com/docs/en/overview.md", Path("/canonical"))
        PosixPath('/canonical/docs/en/overview.md')
    """
    from urllib.parse import urlparse

    if isinstance(base_dir, str):
        base_dir = Path(base_dir)

    parsed = urlparse(source_url)
    path = parsed.path

    # Remove leading slash
    if path.startswith('/'):
        path = path[1:]

    # Ensure .md extension
    if not path.endswith('.md'):
        path = path + '.md'

    return base_dir / path


if __name__ == '__main__':
    """Self-test for llms_parser module."""
    print("llms_parser Self-Test")
    print("=" * 60)

    # Test LlmsParser
    print("\n1. Testing LlmsParser with sample llms.txt content:")
    sample_llms_txt = """# Claude Documentation

## Getting Started
- [Introduction](https://docs.claude.com/en/docs/intro.md): Welcome to Claude
- [Quickstart](https://docs.claude.com/en/docs/quickstart.md): Get started quickly

## API Reference
- [Messages API](https://docs.claude.com/en/api/messages.md): Send messages to Claude
- [Models](https://docs.claude.com/en/api/models.md)
"""

    parser = LlmsParser()
    entries = parser.parse_to_list(sample_llms_txt)
    print(f"   Found {len(entries)} entries")
    for entry in entries:
        print(f"   - [{entry.section}] {entry.title}: {entry.url}")
        if entry.description:
            print(f"     Description: {entry.description}")

    # Test URL extraction
    urls = parser.extract_urls(sample_llms_txt)
    print(f"\n   Extracted {len(urls)} URLs")

    # Test LlmsFullParser
    print("\n2. Testing LlmsFullParser with sample llms-full.txt content:")
    sample_llms_full_txt = """# Introduction
Source: https://docs.claude.com/en/docs/intro.md

Welcome to Claude documentation.

This is the introduction page with full content.

# Quickstart
Source: https://docs.claude.com/en/docs/quickstart.md

Get started with Claude in minutes.

## Prerequisites
- Python 3.8+
- API key

## Installation
pip install anthropic
"""

    full_parser = LlmsFullParser()
    pages = full_parser.parse_to_list(sample_llms_full_txt)
    print(f"   Found {len(pages)} pages")
    for page in pages:
        print(f"   - {page.title}")
        print(f"     Source: {page.source_url}")
        print(f"     Content length: {len(page.content)} chars")

    print("\n" + "=" * 60)
    print("Self-test complete!")

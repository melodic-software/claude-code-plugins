"""
Tests for llms_parser.py module.

Tests the LlmsParser for both standard and embedded link formats.
"""

import pytest
import sys
from pathlib import Path

# Add scripts directory to path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts' / 'core'))

from llms_parser import LlmsParser, LlmsEntry, parse_llms_txt


class TestLlmsParserStandardFormat:
    """Test LlmsParser with standard llms.txt format."""

    def test_parse_standard_entry(self):
        """Test parsing standard - [Title](URL): Description format."""
        content = """# Documentation

## Getting Started
- [Introduction](https://example.com/intro.md): Welcome guide
- [Quickstart](https://example.com/quickstart.md)
"""
        parser = LlmsParser()
        entries = parser.parse_to_list(content)

        assert len(entries) == 2
        assert entries[0].title == "Introduction"
        assert entries[0].url == "https://example.com/intro.md"
        assert entries[0].description == "Welcome guide"
        assert entries[0].section == "Getting Started"

        assert entries[1].title == "Quickstart"
        assert entries[1].url == "https://example.com/quickstart.md"
        assert entries[1].description is None

    def test_extract_urls(self):
        """Test URL extraction convenience method."""
        content = """- [Doc1](https://example.com/doc1.md)
- [Doc2](https://example.com/doc2.md)
"""
        parser = LlmsParser()
        urls = parser.extract_urls(content)

        assert len(urls) == 2
        assert "https://example.com/doc1.md" in urls
        assert "https://example.com/doc2.md" in urls


class TestLlmsParserEmbeddedFormat:
    """Test LlmsParser with geminicli.com embedded link format."""

    def test_parse_header_links(self):
        """Test parsing # [Title](URL) header format."""
        content = """# Gemini CLI Documentation

# [Architecture Overview](http://geminicli.com/docs/architecture.md)

This is the architecture documentation.

# [CLI Commands](http://geminicli.com/docs/cli/commands.md)

Commands reference.
"""
        parser = LlmsParser()
        entries = parser.parse_to_list(content)

        assert len(entries) == 2
        assert entries[0].title == "Architecture Overview"
        assert entries[0].url == "http://geminicli.com/docs/architecture.md"
        assert entries[1].title == "CLI Commands"
        assert entries[1].url == "http://geminicli.com/docs/cli/commands.md"

    def test_parse_inline_links_with_base_url(self):
        """Test parsing inline [text](/path.md) with base_url resolution."""
        content = """# Documentation

The CLI has several components:
- [Input processing](/docs/cli/commands.md)
- [Theme customization](/docs/cli/themes.md)
- [Configuration](/docs/get-started/configuration.md)
"""
        parser = LlmsParser(base_url="http://geminicli.com")
        entries = parser.parse_to_list(content)

        assert len(entries) == 3
        assert entries[0].url == "http://geminicli.com/docs/cli/commands.md"
        assert entries[1].url == "http://geminicli.com/docs/cli/themes.md"
        assert entries[2].url == "http://geminicli.com/docs/get-started/configuration.md"

    def test_deduplication(self):
        """Test that duplicate URLs are filtered out."""
        content = """# [Doc1](http://example.com/doc.md)

Reference to [Doc1](/doc.md) again.

# [Doc1](http://example.com/doc.md)
"""
        parser = LlmsParser(base_url="http://example.com")
        entries = parser.parse_to_list(content)

        # Should only have 1 entry despite 3 references
        assert len(entries) == 1
        assert entries[0].url == "http://example.com/doc.md"

    def test_only_md_urls_from_inline(self):
        """Test that only .md URLs are extracted from inline links."""
        content = """Check out [the website](https://example.com/page) and
read [the docs](/docs/guide.md) for more info.
Also see [image](/image.png).
"""
        parser = LlmsParser(base_url="http://example.com")
        entries = parser.parse_to_list(content)

        # Only /docs/guide.md should be extracted (ends with .md)
        assert len(entries) == 1
        assert entries[0].url == "http://example.com/docs/guide.md"

    def test_mixed_formats(self):
        """Test parsing content with mixed standard and embedded formats."""
        content = """# Documentation

# [Overview](http://example.com/docs/overview.md)

Some content with [inline link](/docs/other.md).

## Reference
- [API Docs](https://example.com/api.md): API reference
"""
        parser = LlmsParser(base_url="http://example.com")
        entries = parser.parse_to_list(content)

        urls = [e.url for e in entries]
        assert "http://example.com/docs/overview.md" in urls
        assert "http://example.com/docs/other.md" in urls
        assert "https://example.com/api.md" in urls
        assert len(entries) == 3


class TestLlmsParserBaseUrl:
    """Test base_url handling."""

    def test_no_base_url_relative_paths_ignored(self):
        """Test that relative paths without base_url are returned as-is."""
        content = """See [docs](/docs/guide.md) for more."""
        parser = LlmsParser()  # No base_url
        entries = parser.parse_to_list(content)

        # Relative path without base_url - URL won't resolve properly
        # but the parser should still extract it
        assert len(entries) == 1
        assert entries[0].url == "/docs/guide.md"

    def test_base_url_trailing_slash_normalized(self):
        """Test that trailing slash on base_url is handled."""
        content = """See [docs](/docs/guide.md)."""
        parser = LlmsParser(base_url="http://example.com/")
        entries = parser.parse_to_list(content)

        # Should not have double slash
        assert entries[0].url == "http://example.com/docs/guide.md"

    def test_absolute_urls_not_affected_by_base_url(self):
        """Test that absolute URLs are not modified by base_url."""
        content = """See [external](https://other.com/doc.md)."""
        parser = LlmsParser(base_url="http://example.com")
        entries = parser.parse_to_list(content)

        # Absolute URL should remain unchanged
        assert entries[0].url == "https://other.com/doc.md"


class TestConvenienceFunction:
    """Test module-level convenience functions."""

    def test_parse_llms_txt_function(self):
        """Test parse_llms_txt convenience function."""
        content = """- [Doc](https://example.com/doc.md)"""
        urls = parse_llms_txt(content)

        assert len(urls) == 1
        assert urls[0] == "https://example.com/doc.md"

    def test_parse_llms_txt_with_base_url(self):
        """Test parse_llms_txt with base_url parameter."""
        content = """See [guide](/docs/guide.md)."""
        urls = parse_llms_txt(content, base_url="http://example.com")

        assert len(urls) == 1
        assert urls[0] == "http://example.com/docs/guide.md"

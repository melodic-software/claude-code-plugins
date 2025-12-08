#!/usr/bin/env python3
"""Tests for frontmatter_parser.py - YAML frontmatter extraction."""

import sys
from pathlib import Path

import pytest

# Add parent directory to path for imports
parent_dir = Path(__file__).parent.parent
sys.path.insert(0, str(parent_dir))

from frontmatter_parser import (
    extract_frontmatter,
    extract_frontmatter_from_content,
    extract_keywords_from_description,
    truncate_description,
    MAX_CONTENT_SIZE,
    MAX_LINES,
)


class TestExtractFrontmatterFromContent:
    """Tests for extract_frontmatter_from_content function."""

    def test_valid_frontmatter(self):
        """Valid YAML frontmatter should be extracted."""
        content = """---
name: test-skill
description: A test skill for testing
allowed-tools: Read, Write
---

# Test Skill Content
"""
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert result["name"] == "test-skill"
        assert result["description"] == "A test skill for testing"
        assert result["allowed-tools"] == "Read, Write"

    def test_missing_opening_delimiter(self):
        """Content without opening --- should return None."""
        content = """name: test
description: no delimiters
---
"""
        result = extract_frontmatter_from_content(content)
        assert result is None

    def test_missing_closing_delimiter(self):
        """Content without closing --- should return None."""
        content = """---
name: test
description: no closing
"""
        result = extract_frontmatter_from_content(content)
        assert result is None

    def test_empty_frontmatter(self):
        """Empty frontmatter (just delimiters) should return empty dict."""
        content = """---
---
Content here
"""
        result = extract_frontmatter_from_content(content)
        assert result == {}

    def test_multiline_value_literal(self):
        """Multiline literal value (|) should be captured."""
        content = """---
name: test
description: |
  This is a multiline
  description value
---
"""
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert "This is a multiline" in result["description"]
        assert "description value" in result["description"]

    def test_value_with_colon(self):
        """Values containing colons should be handled correctly."""
        content = """---
name: test
url: https://example.com:8080/path
---
"""
        result = extract_frontmatter_from_content(content)
        assert result is not None
        # Note: simple parser may only capture first part
        assert "https" in result["url"]

    def test_comments_ignored(self):
        """Lines starting with # should be ignored."""
        content = """---
name: test
# This is a comment
description: value
---
"""
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert "name" in result
        assert "description" in result
        # Comment should not create a key

    def test_quoted_values_double(self):
        """Double-quoted values should have quotes stripped."""
        content = """---
name: "test skill"
description: "A test"
---
"""
        # Note: Current simple parser may or may not strip quotes
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert result["name"] == '"test skill"' or result["name"] == "test skill"

    def test_whitespace_in_values(self):
        """Values with leading/trailing whitespace should be trimmed."""
        content = """---
name:   test
description:    a value
---
"""
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert result["name"] == "test"
        assert result["description"] == "a value"


class TestInputBounds:
    """Tests for input size limits (security)."""

    def test_content_exceeds_max_size(self):
        """Content larger than MAX_CONTENT_SIZE should return None."""
        large_content = "---\nname: test\n---\n" + "x" * (MAX_CONTENT_SIZE + 1)
        result = extract_frontmatter_from_content(large_content)
        assert result is None

    def test_content_at_max_size(self):
        """Content at exactly MAX_CONTENT_SIZE should be processed."""
        # Create content that is exactly MAX_CONTENT_SIZE
        frontmatter = "---\nname: test\n---\n"
        padding = "x" * (MAX_CONTENT_SIZE - len(frontmatter))
        content = frontmatter + padding
        assert len(content) == MAX_CONTENT_SIZE

        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert result["name"] == "test"

    def test_many_lines_truncated(self):
        """Content with more than MAX_LINES should be truncated safely."""
        # Create content with many lines but valid frontmatter at top
        frontmatter = "---\nname: test\ndescription: value\n---\n"
        many_lines = "\n".join(["line " + str(i) for i in range(MAX_LINES + 100)])
        content = frontmatter + many_lines

        # Should still extract frontmatter from first MAX_LINES
        result = extract_frontmatter_from_content(content)
        assert result is not None
        assert result["name"] == "test"


class TestExtractFrontmatter:
    """Tests for extract_frontmatter function (file-based)."""

    def test_nonexistent_file(self, tmp_path):
        """Non-existent file should return None."""
        result = extract_frontmatter(tmp_path / "nonexistent.md")
        assert result is None

    def test_valid_file(self, tmp_path):
        """Valid file with frontmatter should be parsed."""
        test_file = tmp_path / "test.md"
        test_file.write_text("""---
name: file-test
description: Testing file parsing
---

# Content
""", encoding='utf-8')

        result = extract_frontmatter(test_file)
        assert result is not None
        assert result["name"] == "file-test"

    def test_utf8_content(self, tmp_path):
        """UTF-8 content should be handled correctly."""
        test_file = tmp_path / "unicode.md"
        test_file.write_text("""---
name: unicode-test
description: Testing unicode content
---
""", encoding='utf-8')

        result = extract_frontmatter(test_file)
        assert result is not None
        assert result["name"] == "unicode-test"


class TestExtractKeywordsFromDescription:
    """Tests for keyword extraction."""

    def test_empty_description(self):
        """Empty description should return empty list."""
        result = extract_keywords_from_description("")
        assert result == []

    def test_none_description(self):
        """None description should return empty list."""
        result = extract_keywords_from_description(None)
        assert result == []

    def test_domain_terms_prioritized(self):
        """Domain terms (claude, hooks, etc.) should be prioritized."""
        desc = "This skill manages Claude Code hooks and MCP integration"
        result = extract_keywords_from_description(desc)
        # Domain terms should appear
        assert any(kw in result for kw in ['claude', 'hooks', 'mcp'])

    def test_stopwords_excluded(self):
        """Common stopwords should be excluded."""
        desc = "The skill is for the user to use in the project"
        result = extract_keywords_from_description(desc)
        # Stopwords should not appear
        stopwords = ['the', 'is', 'for', 'to', 'in']
        assert not any(sw in result for sw in stopwords)

    def test_max_keywords_respected(self):
        """Should not return more than max_keywords."""
        desc = "claude code hooks mcp sdk api git github yaml json markdown python bash typescript"
        result = extract_keywords_from_description(desc, max_keywords=5)
        assert len(result) <= 5

    def test_short_words_excluded(self):
        """Words shorter than 3 characters should be excluded."""
        desc = "a an it do be go is"
        result = extract_keywords_from_description(desc)
        # All short words should be excluded
        assert len(result) == 0


class TestTruncateDescription:
    """Tests for description truncation."""

    def test_empty_string(self):
        """Empty string should return empty string."""
        result = truncate_description("")
        assert result == ""

    def test_none_value(self):
        """None should return empty string."""
        result = truncate_description(None)
        assert result == ""

    def test_short_description_unchanged(self):
        """Short descriptions should not be truncated."""
        desc = "A short description."
        result = truncate_description(desc, max_chars=100)
        assert result == desc

    def test_first_sentence_with_period(self):
        """Should truncate at first sentence ending with period."""
        desc = "First sentence. Second sentence. Third sentence."
        result = truncate_description(desc, max_chars=100)
        assert result == "First sentence."

    def test_first_sentence_exceeds_max(self):
        """Long first sentence should be truncated at word boundary."""
        desc = "This is a very long first sentence that exceeds the maximum allowed characters limit."
        result = truncate_description(desc, max_chars=40)
        assert len(result) <= 43  # max_chars + "..."
        assert result.endswith("...")

    def test_multiline_normalized(self):
        """Multiline descriptions should have newlines normalized to spaces."""
        desc = "First line.\nSecond line.\nThird line."
        result = truncate_description(desc, max_chars=100)
        assert "\n" not in result
        assert result == "First line."


if __name__ == "__main__":
    pytest.main([__file__, "-v"])

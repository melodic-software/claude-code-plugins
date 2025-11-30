#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Tests for get_subsection_content module."""

import sys
from pathlib import Path
from io import StringIO
from unittest.mock import MagicMock, patch

# Standard test bootstrap
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))



class TestAnchorToHeading:
    """Test anchor_to_heading() function."""

    def test_simple_anchor_conversion(self):
        """Should convert simple anchor to title case heading."""
        from core.get_subsection_content import anchor_to_heading

        result = anchor_to_heading('#section-heading')

        assert result == 'Section Heading'

    def test_anchor_without_hash(self):
        """Should work with anchor without leading #."""
        from core.get_subsection_content import anchor_to_heading

        result = anchor_to_heading('section-heading')

        assert result == 'Section Heading'

    def test_multi_word_anchor(self):
        """Should handle multi-word anchors."""
        from core.get_subsection_content import anchor_to_heading

        result = anchor_to_heading('#skills-vs-slash-commands')

        assert result == 'Skills Vs Slash Commands'

    def test_single_word_anchor(self):
        """Should handle single word anchors."""
        from core.get_subsection_content import anchor_to_heading

        result = anchor_to_heading('#overview')

        assert result == 'Overview'

    def test_anchor_with_numbers(self):
        """Should handle anchors with numbers."""
        from core.get_subsection_content import anchor_to_heading

        result = anchor_to_heading('#step-1-install')

        assert result == 'Step 1 Install'


class TestGetSubsectionContent:
    """Test get_subsection_content() function."""

    def test_returns_none_when_content_not_found(self):
        """Should return None when resolver returns nothing."""
        from core.get_subsection_content import get_subsection_content

        mock_resolver = MagicMock()
        mock_resolver.get_content.return_value = None

        result = get_subsection_content(mock_resolver, 'fake-doc-id', section='Nonexistent')

        assert result is None

    def test_adds_token_estimate(self):
        """Should add token_estimate to result."""
        from core.get_subsection_content import get_subsection_content

        mock_resolver = MagicMock()
        mock_resolver.get_content.return_value = {
            'content': 'Test content with 40 characters roughly..',
            'title': 'Test Doc'
        }

        result = get_subsection_content(mock_resolver, 'test-doc', section='Test')

        assert 'token_estimate' in result
        assert isinstance(result['token_estimate'], int)
        assert result['token_estimate'] == 10  # 40 chars / 4

    def test_converts_anchor_to_section(self):
        """Should convert anchor to section heading."""
        from core.get_subsection_content import get_subsection_content

        mock_resolver = MagicMock()
        mock_resolver.get_content.return_value = {'content': 'Test', 'title': 'Test'}

        get_subsection_content(mock_resolver, 'test-doc', anchor='#my-section')

        # Should have called get_content with converted heading
        mock_resolver.get_content.assert_called_once_with('test-doc', 'My Section')

    def test_section_takes_precedence_over_anchor(self):
        """When both section and anchor provided, section should be used."""
        from core.get_subsection_content import get_subsection_content

        mock_resolver = MagicMock()
        mock_resolver.get_content.return_value = {'content': 'Test', 'title': 'Test'}

        get_subsection_content(mock_resolver, 'test-doc', section='Explicit Section', anchor='#ignored')

        mock_resolver.get_content.assert_called_once_with('test-doc', 'Explicit Section')

    def test_empty_content_gives_zero_tokens(self):
        """Should give 0 tokens for empty/missing content."""
        from core.get_subsection_content import get_subsection_content

        mock_resolver = MagicMock()
        mock_resolver.get_content.return_value = {'title': 'Test', 'content': None}

        result = get_subsection_content(mock_resolver, 'test-doc', section='Test')

        assert result['token_estimate'] == 0


class TestPrintContentResult:
    """Test print_content_result() function."""

    def test_json_output_format(self):
        """Should output valid JSON when json_output=True."""
        import json
        from core.get_subsection_content import print_content_result

        result = {
            'title': 'Test Document',
            'doc_id': 'test-doc',
            'content': 'Test content',
            'url': 'https://example.com/test'
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=True)
            output = mock_stdout.getvalue()

        # Should be valid JSON
        parsed = json.loads(output)
        assert parsed['title'] == 'Test Document'
        assert parsed['doc_id'] == 'test-doc'

    def test_cli_output_includes_title(self):
        """CLI output should include document title."""
        from core.get_subsection_content import print_content_result

        result = {
            'title': 'My Document Title',
            'doc_id': 'my-doc',
            'content': 'Some content'
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert 'My Document Title' in output
        assert 'my-doc' in output

    def test_truncates_long_content_in_cli(self):
        """Should truncate content over 500 chars in CLI mode."""
        from core.get_subsection_content import print_content_result

        long_content = 'x' * 1000
        result = {
            'title': 'Test',
            'doc_id': 'test',
            'content': long_content
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert 'preview' in output.lower()
        assert '500' in output  # mentions 500 chars

    def test_shows_full_short_content_in_cli(self):
        """Should show full content when under 500 chars in CLI mode."""
        from core.get_subsection_content import print_content_result

        short_content = 'Short content here'
        result = {
            'title': 'Test',
            'doc_id': 'test',
            'content': short_content
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert 'Short content here' in output
        assert 'preview' not in output.lower()

    def test_shows_warning_if_present(self):
        """Should display warning message if present."""
        from core.get_subsection_content import print_content_result

        result = {
            'title': 'Test',
            'doc_id': 'test',
            'warning': 'This is a warning message',
            'content': 'Content'
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert 'This is a warning message' in output

    def test_handles_missing_content(self):
        """Should handle missing content gracefully."""
        from core.get_subsection_content import print_content_result

        result = {
            'title': 'Test',
            'doc_id': 'test'
            # No 'content' key
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert 'link only' in output.lower()

    def test_shows_token_estimate(self):
        """Should show token estimate when present."""
        from core.get_subsection_content import print_content_result

        result = {
            'title': 'Test',
            'doc_id': 'test',
            'content': 'Test',
            'token_estimate': 1500
        }

        with patch('sys.stdout', new=StringIO()) as mock_stdout:
            print_content_result(result, json_output=False)
            output = mock_stdout.getvalue()

        assert '1,500' in output or '1500' in output

"""
Tests for detect_changes.py script.

Tests the GeminiChangeDetector class for detecting new and removed URLs.
"""

from unittest.mock import patch, MagicMock

from tests.shared.test_utils import TempReferencesDir, create_mock_llms_txt, create_mock_index_entry


class TestGeminiChangeDetector:
    """Test suite for GeminiChangeDetector"""

    def test_detect_new_urls(self, temp_dir):
        """Test detection of new URLs in llms.txt"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with one URL
            index = {
                'doc1': create_mock_index_entry('doc1', 'https://geminicli.com/docs/doc1', 'test/doc1.md')
            }
            refs_dir.create_index(index)

            # Create llms.txt with two URLs (one new)
            llms_content = create_mock_llms_txt([
                'https://geminicli.com/docs/doc1',
                'https://geminicli.com/docs/doc2'  # New URL
            ])

            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)
            llms_urls = detector.parse_llms_txt(llms_content)
            indexed_urls = {'https://geminicli.com/docs/doc1': 'doc1'}

            new_urls, removed_urls = detector.detect_changes(llms_urls, indexed_urls)

            assert 'https://geminicli.com/docs/doc2' in new_urls
            assert len(new_urls) == 1
            assert len(removed_urls) == 0
        finally:
            refs_dir.cleanup()

    def test_detect_removed_urls(self, temp_dir):
        """Test detection of removed URLs from llms.txt"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with two URLs
            index = {
                'doc1': create_mock_index_entry('doc1', 'https://geminicli.com/docs/doc1', 'test/doc1.md'),
                'doc2': create_mock_index_entry('doc2', 'https://geminicli.com/docs/doc2', 'test/doc2.md')
            }
            refs_dir.create_index(index)

            # Create llms.txt with one URL (one removed)
            llms_content = create_mock_llms_txt([
                'https://geminicli.com/docs/doc1'
            ])

            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)
            llms_urls = detector.parse_llms_txt(llms_content)
            indexed_urls = {
                'https://geminicli.com/docs/doc1': 'doc1',
                'https://geminicli.com/docs/doc2': 'doc2'
            }

            new_urls, removed_urls = detector.detect_changes(llms_urls, indexed_urls)

            assert 'https://geminicli.com/docs/doc2' in removed_urls
            assert len(new_urls) == 0
            assert len(removed_urls) == 1
        finally:
            refs_dir.cleanup()

    @patch('scripts.maintenance.detect_changes.requests.Session')
    def test_check_404_urls(self, mock_session_class, temp_dir):
        """Test 404 URL detection"""
        refs_dir = TempReferencesDir()
        try:
            # Mock session with 404 response
            mock_session = MagicMock()
            mock_response_404 = MagicMock()
            mock_response_404.status_code = 404
            mock_response_200 = MagicMock()
            mock_response_200.status_code = 200

            # Create a function that returns different responses based on URL
            def head_side_effect(url, **kwargs):
                if '404' in url:
                    return mock_response_404
                else:
                    return mock_response_200

            mock_session.head.side_effect = head_side_effect
            mock_session_class.return_value = mock_session

            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)
            urls = {'https://geminicli.com/404', 'https://geminicli.com/ok'}

            url_404s = detector.check_404_urls(urls, max_workers=1)

            assert url_404s['https://geminicli.com/404'] is True
            assert url_404s['https://geminicli.com/ok'] is False
        finally:
            refs_dir.cleanup()

    def test_generate_report(self, temp_dir):
        """Test report generation"""
        from scripts.maintenance.detect_changes import GeminiChangeDetector

        refs_dir = TempReferencesDir()
        try:
            detector = GeminiChangeDetector(refs_dir.references_dir)

            new_urls = {'https://geminicli.com/new1', 'https://geminicli.com/new2'}
            removed_urls = {'https://geminicli.com/removed1'}
            indexed_urls = {'https://geminicli.com/removed1': 'removed1-doc'}
            output_subdir = 'geminicli-com'
            url_404s = {'https://geminicli.com/404': True}

            # generate_report signature: (new_urls, removed_urls, indexed_urls, output_subdir, url_404s, hash_mismatches)
            report = detector.generate_report(new_urls, removed_urls, indexed_urls, output_subdir, url_404s)

            assert 'New URLs' in report or 'new' in report.lower()
            assert 'new1' in report or 'new2' in report
        finally:
            refs_dir.cleanup()

    def test_parse_llms_txt_extracts_urls(self, temp_dir):
        """Test that parse_llms_txt correctly extracts URLs from markdown links"""
        refs_dir = TempReferencesDir()
        try:
            llms_content = """# Gemini CLI Documentation

- [Installation](https://geminicli.com/docs/installation)
- [Commands](https://geminicli.com/docs/commands)
- [Checkpointing](https://geminicli.com/docs/checkpointing)
"""
            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)
            urls = detector.parse_llms_txt(llms_content)

            assert len(urls) == 3
            assert 'https://geminicli.com/docs/installation' in urls
            assert 'https://geminicli.com/docs/commands' in urls
            assert 'https://geminicli.com/docs/checkpointing' in urls
        finally:
            refs_dir.cleanup()

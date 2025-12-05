"""
Tests for cleanup_drift.py script.

Tests the GeminiDriftCleaner class for cleaning up drift in documentation.
"""

from unittest.mock import patch, MagicMock

from tests.shared.test_utils import TempReferencesDir, create_mock_index_entry


class TestGeminiDriftCleaner:
    """Test suite for GeminiDriftCleaner"""

    def test_find_missing_files(self, temp_dir):
        """Test finding index entries with missing files"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with entry but no corresponding file
            index = {
                'missing-doc': create_mock_index_entry(
                    'missing-doc',
                    'https://geminicli.com/docs/missing',
                    'geminicli-com/docs/missing.md',
                    title='Missing Doc'
                )
            }
            refs_dir.create_index(index)
            # Don't create the actual file

            from scripts.maintenance.cleanup_drift import GeminiDriftCleaner

            cleaner = GeminiDriftCleaner(refs_dir.references_dir, dry_run=True)
            loaded_index = cleaner.load_index()
            missing = cleaner.find_missing_files(loaded_index)

            assert len(missing) >= 1
            doc_ids = [doc_id for doc_id, _ in missing]
            assert 'missing-doc' in doc_ids
        finally:
            refs_dir.cleanup()

    def test_find_missing_files_with_existing_file(self, temp_dir):
        """Test that existing files are not marked as missing"""
        refs_dir = TempReferencesDir()
        try:
            # Create index and corresponding file
            index = {
                'existing-doc': create_mock_index_entry(
                    'existing-doc',
                    'https://geminicli.com/docs/existing',
                    'geminicli-com/docs/existing.md',
                    title='Existing Doc'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'existing.md', '# Existing Doc\n\nContent.')

            from scripts.maintenance.cleanup_drift import GeminiDriftCleaner

            cleaner = GeminiDriftCleaner(refs_dir.references_dir, dry_run=True)
            loaded_index = cleaner.load_index()
            missing = cleaner.find_missing_files(loaded_index)

            assert len(missing) == 0
        finally:
            refs_dir.cleanup()

    @patch('scripts.maintenance.cleanup_drift.requests.Session')
    def test_find_404_urls(self, mock_session_class, temp_dir):
        """Test finding 404 URLs"""
        refs_dir = TempReferencesDir()
        try:
            # Mock session with 404 response
            mock_session = MagicMock()
            mock_response_404 = MagicMock()
            mock_response_404.status_code = 404

            mock_session.head.return_value = mock_response_404
            mock_session_class.return_value = mock_session

            index = {
                '404-doc': create_mock_index_entry(
                    '404-doc',
                    'https://geminicli.com/docs/404',
                    'geminicli-com/docs/404.md',
                    title='404 Doc'
                )
            }
            refs_dir.create_index(index)

            from scripts.maintenance.cleanup_drift import GeminiDriftCleaner

            cleaner = GeminiDriftCleaner(refs_dir.references_dir, dry_run=True)
            loaded_index = cleaner.load_index()
            url_404s = cleaner.find_404_urls(loaded_index, max_workers=1)

            assert len(url_404s) >= 1
        finally:
            refs_dir.cleanup()

    def test_cleanup_dry_run_preserves_files(self, temp_dir):
        """Test that dry_run=True preserves files"""
        refs_dir = TempReferencesDir()
        try:
            # Create index and file
            doc_content = """---
title: Test Doc
url: https://geminicli.com/docs/test
---

# Test Document
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Doc'
                )
            }
            refs_dir.create_index(index)
            doc_path = refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.maintenance.cleanup_drift import GeminiDriftCleaner

            cleaner = GeminiDriftCleaner(refs_dir.references_dir, dry_run=True)
            loaded_index = cleaner.load_index()

            # Call clean methods
            cleaner.clean_missing_files(loaded_index)

            # File should still exist
            assert doc_path.exists()
        finally:
            refs_dir.cleanup()

    def test_cleanup_log_tracking(self, temp_dir):
        """Test that cleanup operations are logged"""
        refs_dir = TempReferencesDir()
        try:
            refs_dir.create_index({})

            from scripts.maintenance.cleanup_drift import GeminiDriftCleaner

            cleaner = GeminiDriftCleaner(refs_dir.references_dir, dry_run=True)

            # Check that cleanup_log exists and is a list
            assert hasattr(cleaner, 'cleanup_log')
            assert isinstance(cleaner.cleanup_log, list)
        finally:
            refs_dir.cleanup()

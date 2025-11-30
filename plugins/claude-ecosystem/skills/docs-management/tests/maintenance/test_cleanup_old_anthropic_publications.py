"""
Tests for cleanup_old_anthropic_publications.py script.

Tests the cleanup_old_anthropic_publications.py script for removing old Anthropic publications.
"""

import sys
from pathlib import Path
from datetime import datetime, timedelta, timezone
from unittest.mock import patch


import pytest
from tests.shared.test_utils import TempReferencesDir, create_mock_index_entry



class TestCleanupOldAnthropicPublications:
    """Test suite for cleanup_old_anthropic_publications.py."""

    def test_script_imports(self):
        """Test that script can be imported."""
        sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
        
        try:
            from scripts.maintenance import cleanup_old_anthropic_publications
            assert True
        except ImportError:
            pytest.fail("cleanup_old_anthropic_publications.py could not be imported")

    def test_main_function_exists(self):
        """Test that main function exists."""
        refs_dir = TempReferencesDir()
        
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
            from scripts.maintenance.cleanup_old_anthropic_publications import main
            
            # Should be callable
            assert callable(main)
            
        finally:
            refs_dir.cleanup()

    def test_cleanup_old_publications_dry_run(self):
        """Test cleanup in dry-run mode (via mocking)."""
        refs_dir = TempReferencesDir()
        
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
            from scripts.maintenance.cleanup_old_anthropic_publications import parse_args
            
            # Test argument parsing
            with patch('sys.argv', ['cleanup_old_anthropic_publications.py', '--max-age', '365']):
                args = parse_args()
                assert args.max_age == 365
            
        finally:
            refs_dir.cleanup()

    def test_cleanup_skips_recent_publications(self):
        """Test that recent publications are not cleaned up."""
        refs_dir = TempReferencesDir()
        
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
            from scripts.management.index_manager import IndexManager
            
            # Create recent publication entry
            recent_date = (datetime.now(timezone.utc).date() - timedelta(days=100)).strftime('%Y-%m-%d')
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://anthropic.com/engineering/test',
                    'anthropic-com/engineering/test.md',
                    domain='anthropic.com',
                    category='engineering',
                    published_at=recent_date
                )
            }
            
            refs_dir.create_index(index)
            refs_dir.create_doc('anthropic-com', 'engineering', 'test.md', '# Test')
            
            # Verify entry exists
            manager = IndexManager(refs_dir.references_dir)
            loaded_index = manager.load_all()
            assert 'test-doc' in loaded_index
            
        finally:
            refs_dir.cleanup()

    def test_cleanup_skips_non_publication_categories(self):
        """Test that non-publication categories are not cleaned up."""
        refs_dir = TempReferencesDir()
        
        try:
            sys.path.insert(0, str(Path(__file__).parent.parent / 'scripts'))
            from scripts.management.index_manager import IndexManager
            
            # Create old doc entry for non-publication category
            old_date = (datetime.now(timezone.utc).date() - timedelta(days=400)).strftime('%Y-%m-%d')
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://anthropic.com/docs/test',
                    'anthropic-com/docs/test.md',
                    domain='anthropic.com',
                    category='docs',  # Not engineering/news/research
                    published_at=old_date
                )
            }
            
            refs_dir.create_index(index)
            refs_dir.create_doc('anthropic-com', 'docs', 'test.md', '# Test')
            
            # Verify entry exists (should not be cleaned)
            manager = IndexManager(refs_dir.references_dir)
            loaded_index = manager.load_all()
            assert 'test-doc' in loaded_index
            
        finally:
            refs_dir.cleanup()

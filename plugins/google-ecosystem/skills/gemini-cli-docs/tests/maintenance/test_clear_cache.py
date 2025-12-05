"""
Tests for clear_cache.py script and CacheManager utility.

Tests cache management functionality including clearing and inspecting caches.
"""

import json
from pathlib import Path

from tests.shared.test_utils import TempReferencesDir


class TestCacheManager:
    """Test suite for CacheManager from utils.cache_manager"""

    def test_clear_inverted_index(self, temp_dir):
        """Test clearing the inverted index cache"""
        refs_dir = TempReferencesDir()
        try:
            # Create a mock inverted index cache
            # Cache is at skill root level (parent of canonical)
            skill_dir = refs_dir.references_dir.parent
            cache_dir = skill_dir / '.cache'
            cache_dir.mkdir(parents=True, exist_ok=True)
            inverted_index_path = cache_dir / 'inverted_index.json'

            # Write mock cache
            mock_cache = {'keyword1': ['doc1', 'doc2'], 'keyword2': ['doc3']}
            with open(inverted_index_path, 'w', encoding='utf-8') as f:
                json.dump(mock_cache, f)

            assert inverted_index_path.exists()

            from scripts.utils.cache_manager import CacheManager

            manager = CacheManager(refs_dir.references_dir)
            result = manager.clear_inverted_index()

            # Cache file should be removed
            assert not inverted_index_path.exists()
            assert result is True
        finally:
            refs_dir.cleanup()

    def test_clear_nonexistent_cache(self, temp_dir):
        """Test clearing cache that doesn't exist"""
        refs_dir = TempReferencesDir()
        try:
            from scripts.utils.cache_manager import CacheManager

            manager = CacheManager(refs_dir.references_dir)
            result = manager.clear_inverted_index()

            # Should return False when cache doesn't exist
            assert result is False
        finally:
            refs_dir.cleanup()

    def test_get_cache_info(self, temp_dir):
        """Test getting cache information"""
        refs_dir = TempReferencesDir()
        try:
            from scripts.utils.cache_manager import CacheManager

            manager = CacheManager(refs_dir.references_dir)
            info = manager.get_cache_info()

            # Should return information about cache state
            assert isinstance(info, dict)
            assert 'inverted_index' in info
            assert 'llms_cache' in info
        finally:
            refs_dir.cleanup()

    def test_clear_all_caches(self, temp_dir):
        """Test clearing all caches"""
        refs_dir = TempReferencesDir()
        try:
            # Create cache files
            skill_dir = refs_dir.references_dir.parent
            cache_dir = skill_dir / '.cache'
            cache_dir.mkdir(parents=True, exist_ok=True)

            # Create inverted index
            inverted_path = cache_dir / 'inverted_index.json'
            with open(inverted_path, 'w', encoding='utf-8') as f:
                json.dump({'test': 'data'}, f)

            # Create llms cache
            llms_dir = refs_dir.references_dir / '.llms_cache'
            llms_dir.mkdir(parents=True, exist_ok=True)
            manifest_path = llms_dir / 'manifest_state.json'
            with open(manifest_path, 'w', encoding='utf-8') as f:
                json.dump({'scraper': 'state'}, f)

            from scripts.utils.cache_manager import CacheManager

            manager = CacheManager(refs_dir.references_dir)
            result = manager.clear_all()

            # All caches should be cleared
            assert isinstance(result, dict)
            assert 'inverted_index' in result
            assert 'llms_cache' in result
        finally:
            refs_dir.cleanup()

    def test_is_inverted_index_valid(self, temp_dir):
        """Test inverted index validity check"""
        refs_dir = TempReferencesDir()
        try:
            from scripts.utils.cache_manager import CacheManager

            manager = CacheManager(refs_dir.references_dir)

            # Without any cache files, should return False
            assert manager.is_inverted_index_valid() is False
        finally:
            refs_dir.cleanup()

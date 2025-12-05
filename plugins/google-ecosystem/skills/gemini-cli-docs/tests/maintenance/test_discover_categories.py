"""
Tests for discover_categories.py script.

Tests category discovery functionality for organizing documentation.
"""

from tests.shared.test_utils import TempReferencesDir, create_mock_llms_txt, create_mock_index_entry


class TestCategoryDiscovery:
    """Test suite for category discovery"""

    def test_parse_llms_txt_categories(self, temp_dir):
        """Test parsing categories from llms.txt structure"""
        refs_dir = TempReferencesDir()
        try:
            # llms.txt with different URL patterns indicating categories
            llms_content = """# Gemini CLI Documentation

## Getting Started
- [Installation](https://geminicli.com/docs/installation)
- [Quickstart](https://geminicli.com/docs/quickstart)

## CLI Reference
- [Commands](https://geminicli.com/docs/cli/commands)
- [Options](https://geminicli.com/docs/cli/options)

## Features
- [Checkpointing](https://geminicli.com/docs/features/checkpointing)
- [Sandbox](https://geminicli.com/docs/features/sandbox)
"""
            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)
            urls = detector.parse_llms_txt(llms_content)

            # Should extract all URLs regardless of category
            assert len(urls) == 6
            assert 'https://geminicli.com/docs/installation' in urls
            assert 'https://geminicli.com/docs/cli/commands' in urls
            assert 'https://geminicli.com/docs/features/checkpointing' in urls
        finally:
            refs_dir.cleanup()

    def test_discover_new_categories_from_urls(self, temp_dir):
        """Test discovering new categories from URL patterns"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with existing categories
            index = {
                'doc1': create_mock_index_entry(
                    'doc1',
                    'https://geminicli.com/docs/installation',
                    'geminicli-com/docs/installation.md',
                    category='docs'
                )
            }
            refs_dir.create_index(index)

            # New URLs with different path patterns
            new_urls = [
                'https://geminicli.com/docs/cli/commands',  # cli category
                'https://geminicli.com/docs/features/checkpointing',  # features category
                'https://geminicli.com/docs/api/endpoints'  # api category
            ]

            # Extract category from URL path pattern
            def extract_category(url: str) -> str:
                """Extract category from URL path."""
                path = url.replace('https://geminicli.com/', '')
                parts = path.split('/')
                if len(parts) >= 2:
                    return parts[1]  # Second segment after domain
                return 'docs'

            categories = set()
            for url in new_urls:
                cat = extract_category(url)
                categories.add(cat)

            assert 'cli' in categories
            assert 'features' in categories
            assert 'api' in categories
        finally:
            refs_dir.cleanup()

    def test_category_assignment_from_path(self, temp_dir):
        """Test that categories are correctly derived from file paths"""
        refs_dir = TempReferencesDir()
        try:
            index = {
                'cli-doc': create_mock_index_entry(
                    'cli-doc',
                    'https://geminicli.com/docs/cli/commands',
                    'geminicli-com/docs/cli/commands.md',
                    category='cli'
                ),
                'feature-doc': create_mock_index_entry(
                    'feature-doc',
                    'https://geminicli.com/docs/features/checkpointing',
                    'geminicli-com/docs/features/checkpointing.md',
                    category='features'
                )
            }
            refs_dir.create_index(index)

            from scripts.management.index_manager import IndexManager

            manager = IndexManager(refs_dir.references_dir)
            loaded_index = manager.load_all()

            assert loaded_index['cli-doc']['category'] == 'cli'
            assert loaded_index['feature-doc']['category'] == 'features'
        finally:
            refs_dir.cleanup()

    def test_url_filter_by_category(self, temp_dir):
        """Test filtering URLs by category pattern"""
        refs_dir = TempReferencesDir()
        try:
            llms_content = create_mock_llms_txt([
                'https://geminicli.com/docs/installation',
                'https://geminicli.com/docs/cli/commands',
                'https://geminicli.com/docs/cli/options',
                'https://geminicli.com/docs/features/checkpointing'
            ])

            from scripts.maintenance.detect_changes import GeminiChangeDetector

            detector = GeminiChangeDetector(refs_dir.references_dir)

            # Filter for CLI-related URLs
            cli_urls = detector.parse_llms_txt(llms_content, url_filter=r'/cli/')

            assert len(cli_urls) == 2
            assert all('/cli/' in url for url in cli_urls)
        finally:
            refs_dir.cleanup()

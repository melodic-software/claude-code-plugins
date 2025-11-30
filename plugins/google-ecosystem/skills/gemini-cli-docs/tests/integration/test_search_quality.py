"""
Integration tests for search quality.

Tests that search returns relevant results for common Gemini CLI queries.
"""

import pytest
from tests.shared.test_utils import create_mock_index_entry


class TestSearchQuality:
    """Test search quality for Gemini CLI documentation."""

    def test_checkpointing_query_returns_checkpointing_doc(self, refs_dir):
        """Test that 'checkpointing' query returns checkpointing documentation."""
        # Arrange
        index = {
            'geminicli-com-docs-cli-checkpointing': create_mock_index_entry(
                'geminicli-com-docs-cli-checkpointing',
                'https://geminicli.com/docs/cli/checkpointing',
                'cli/checkpointing.md',
                title='Checkpointing',
                description='Save and restore file states with checkpoints',
                keywords=['checkpointing', 'checkpoint', 'rewind', 'snapshot', 'session'],
                category='cli'
            ),
            'geminicli-com-docs-cli-settings': create_mock_index_entry(
                'geminicli-com-docs-cli-settings',
                'https://geminicli.com/docs/cli/settings',
                'cli/settings.md',
                title='Settings',
                description='Configure Gemini CLI settings',
                keywords=['settings', 'configuration'],
                category='cli'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_natural_language('how to use checkpointing', limit=5)

        # Assert
        assert len(results) > 0
        # Checkpointing doc should be first
        assert results[0][0] == 'geminicli-com-docs-cli-checkpointing'

    def test_model_routing_query_returns_routing_doc(self, refs_dir):
        """Test that 'flash vs pro' query returns model routing documentation."""
        # Arrange
        index = {
            'geminicli-com-docs-cli-model-routing': create_mock_index_entry(
                'geminicli-com-docs-cli-model-routing',
                'https://geminicli.com/docs/cli/model-routing',
                'cli/model-routing.md',
                title='Model Routing',
                description='Automatic selection between Flash and Pro models',
                keywords=['routing', 'flash', 'pro', 'model', 'selection'],
                category='cli'
            ),
            'geminicli-com-docs-core-memport': create_mock_index_entry(
                'geminicli-com-docs-core-memport',
                'https://geminicli.com/docs/core/memport',
                'core/memport.md',
                title='Memport',
                description='Memory import and export',
                keywords=['memport', 'memory'],
                category='core'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_natural_language('flash vs pro model', limit=5)

        # Assert
        assert len(results) > 0
        # Model routing doc should be in results
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'geminicli-com-docs-cli-model-routing' in doc_ids

    def test_memport_query_returns_memport_doc(self, refs_dir):
        """Test that 'memport' query returns memport documentation."""
        # Arrange
        index = {
            'geminicli-com-docs-core-memport': create_mock_index_entry(
                'geminicli-com-docs-core-memport',
                'https://geminicli.com/docs/core/memport',
                'core/memport.md',
                title='Memport',
                description='Memory import and export functionality',
                keywords=['memport', 'memory', 'import', 'export'],
                category='core'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_natural_language('memport memory', limit=5)

        # Assert
        assert len(results) > 0
        assert results[0][0] == 'geminicli-com-docs-core-memport'

    def test_extensions_query_returns_extensions_docs(self, refs_dir):
        """Test that 'extensions' query returns extension documentation."""
        # Arrange
        index = {
            'geminicli-com-docs-extensions-creating': create_mock_index_entry(
                'geminicli-com-docs-extensions-creating',
                'https://geminicli.com/docs/extensions/creating',
                'extensions/creating.md',
                title='Creating Extensions',
                description='How to create Gemini CLI extensions',
                keywords=['extensions', 'create', 'plugin'],
                category='extensions'
            ),
            'geminicli-com-docs-extensions-managing': create_mock_index_entry(
                'geminicli-com-docs-extensions-managing',
                'https://geminicli.com/docs/extensions/managing',
                'extensions/managing.md',
                title='Managing Extensions',
                description='How to manage installed extensions',
                keywords=['extensions', 'manage', 'install'],
                category='extensions'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['extensions'], limit=10)

        # Assert
        assert len(results) >= 2
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'geminicli-com-docs-extensions-creating' in doc_ids
        assert 'geminicli-com-docs-extensions-managing' in doc_ids


class TestCategoryFiltering:
    """Test category filtering for Gemini CLI documentation."""

    def test_cli_category_filter(self, refs_dir):
        """Test filtering by CLI category."""
        # Arrange
        index = {
            'cli-doc': create_mock_index_entry(
                'cli-doc',
                'https://geminicli.com/docs/cli/commands',
                'cli/commands.md',
                title='CLI Commands',
                keywords=['commands', 'cli'],
                category='cli'
            ),
            'core-doc': create_mock_index_entry(
                'core-doc',
                'https://geminicli.com/docs/core/architecture',
                'core/architecture.md',
                title='Architecture',
                keywords=['architecture', 'core'],
                category='core'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act - search with category filter
        results = resolver.search_by_keyword(['commands'], category='cli', limit=10)

        # Assert
        assert len(results) > 0
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'cli-doc' in doc_ids
        assert 'core-doc' not in doc_ids

    def test_tools_category_filter(self, refs_dir):
        """Test filtering by tools category."""
        # Arrange
        index = {
            'tools-shell': create_mock_index_entry(
                'tools-shell',
                'https://geminicli.com/docs/tools/shell',
                'tools/shell.md',
                title='Shell Tool',
                keywords=['shell', 'command', 'execute'],
                category='tools'
            ),
            'tools-webfetch': create_mock_index_entry(
                'tools-webfetch',
                'https://geminicli.com/docs/tools/web-fetch',
                'tools/web-fetch.md',
                title='Web Fetch',
                keywords=['web', 'fetch', 'http'],
                category='tools'
            ),
            'cli-doc': create_mock_index_entry(
                'cli-doc',
                'https://geminicli.com/docs/cli/commands',
                'cli/commands.md',
                title='Commands',
                keywords=['commands'],
                category='cli'
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act - get all tools category docs
        results = resolver.search_by_keyword(['tool'], category='tools', limit=10)

        # Assert - should not include cli-doc
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'cli-doc' not in doc_ids

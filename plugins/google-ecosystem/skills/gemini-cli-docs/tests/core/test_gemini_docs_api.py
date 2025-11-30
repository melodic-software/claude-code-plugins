"""
Tests for gemini_docs_api.py module.

Tests the public API for the gemini-cli-docs skill.
"""

import pytest
from tests.shared.test_utils import create_mock_index_entry


class TestGeminiDocsAPI:
    """Test suite for GeminiDocsAPI class."""

    def test_find_document(self, refs_dir):
        """Test finding documents by natural language query."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/checkpointing',
                'test/checkpointing.md',
                title='Checkpointing',
                description='File state snapshots',
                keywords=['checkpointing', 'snapshot', 'rewind']
            )
        }
        refs_dir.create_index(index)

        import sys
        sys.path.insert(0, str(refs_dir.references_dir.parent))

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        results = api.find_document('checkpointing', limit=5)

        # Assert
        assert len(results) > 0
        assert results[0]['doc_id'] == 'doc1'

    def test_resolve_doc_id(self, refs_dir):
        """Test resolving doc_id to metadata."""
        # Arrange
        index = {
            'geminicli-com-docs-cli-checkpointing': create_mock_index_entry(
                'geminicli-com-docs-cli-checkpointing',
                'https://geminicli.com/docs/cli/checkpointing',
                'cli/checkpointing.md',
                title='Checkpointing',
                description='Session management'
            )
        }
        refs_dir.create_index(index)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        result = api.resolve_doc_id('geminicli-com-docs-cli-checkpointing')

        # Assert
        assert result is not None
        assert result['doc_id'] == 'geminicli-com-docs-cli-checkpointing'
        assert result['title'] == 'Checkpointing'

    def test_resolve_doc_id_not_found(self, refs_dir):
        """Test resolving non-existent doc_id."""
        # Arrange
        refs_dir.create_index({})

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        result = api.resolve_doc_id('nonexistent')

        # Assert
        assert result is None

    def test_get_docs_by_tag(self, refs_dir):
        """Test getting documents by tag."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                tags=['cli', 'checkpointing']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                tags=['core', 'memport']
            )
        }
        refs_dir.create_index(index)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        results = api.get_docs_by_tag('cli')

        # Assert
        assert len(results) == 1
        assert results[0]['doc_id'] == 'doc1'

    def test_get_docs_by_category(self, refs_dir):
        """Test getting documents by category."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                category='cli'
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                category='core'
            )
        }
        refs_dir.create_index(index)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        results = api.get_docs_by_category('cli')

        # Assert
        assert len(results) == 1
        assert results[0]['doc_id'] == 'doc1'

    def test_search_by_keywords(self, refs_dir):
        """Test searching by keywords."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                keywords=['checkpointing', 'rewind', 'snapshot']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                keywords=['routing', 'model']
            )
        }
        refs_dir.create_index(index)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        results = api.search_by_keywords(['checkpointing', 'rewind'])

        # Assert
        assert len(results) > 0
        assert any(r['doc_id'] == 'doc1' for r in results)


class TestModuleLevelFunctions:
    """Test module-level convenience functions."""

    def test_find_document_function(self, refs_dir, monkeypatch):
        """Test module-level find_document function."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                title='Memport',
                keywords=['memport', 'memory']
            )
        }
        refs_dir.create_index(index)

        # Patch the default base directory
        from gemini_docs_api import _get_api, GeminiDocsAPI

        # Reset the singleton
        import gemini_docs_api
        gemini_docs_api._api_instance = None

        # Create new instance with test directory
        api = GeminiDocsAPI(refs_dir.references_dir)
        monkeypatch.setattr(gemini_docs_api, '_api_instance', api)

        # Act
        from gemini_docs_api import find_document
        results = find_document('memport', limit=5)

        # Assert
        assert len(results) > 0

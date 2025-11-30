"""
Tests for doc_resolver.py module.

Tests critical functionality for resolving doc_id and keywords to file paths.
"""


from tests.shared.test_utils import create_mock_index_entry


class TestDocResolver:
    """Test suite for DocResolver class."""

    def test_resolve_doc_id_exists(self, refs_dir):
        """Test resolving existing doc_id."""
        # Arrange
        index = {
            'geminicli-com-docs-cli-checkpointing': create_mock_index_entry(
                'geminicli-com-docs-cli-checkpointing',
                'https://geminicli.com/docs/cli/checkpointing',
                'test/doc.md',
                title='Checkpointing'
            )
        }
        refs_dir.create_index(index)
        doc_file = refs_dir.references_dir / 'test' / 'doc.md'
        doc_file.parent.mkdir(parents=True, exist_ok=True)
        doc_file.write_text('# Checkpointing\n\nContent here.')

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.resolve_doc_id('geminicli-com-docs-cli-checkpointing')

        # Assert
        assert result is not None
        assert result.exists()
        assert 'doc.md' in str(result)

    def test_resolve_doc_id_not_found(self, refs_dir):
        """Test resolving non-existent doc_id."""
        # Arrange
        refs_dir.create_index({})
        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.resolve_doc_id('nonexistent')

        # Assert
        assert result is None

    def test_resolve_alias(self, refs_dir):
        """Test resolving doc_id via alias."""
        # Arrange
        index = {
            'new-doc-id': create_mock_index_entry(
                'new-doc-id',
                'https://geminicli.com/docs/new',
                'test/new.md',
                aliases=['old-doc-id'],
                title='New Document'
            )
        }
        refs_dir.create_index(index)
        doc_file = refs_dir.references_dir / 'test' / 'new.md'
        doc_file.parent.mkdir(parents=True, exist_ok=True)
        doc_file.write_text('# New Document\n\nContent.')

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.resolve_doc_id('old-doc-id')

        # Assert
        assert result is not None
        assert 'new.md' in str(result)

    def test_search_by_keyword(self, refs_dir):
        """Test searching documents by keywords."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                title='Checkpointing Guide',
                keywords=['checkpointing', 'guide']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                title='Model Routing',
                keywords=['routing', 'model']
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['checkpointing'], limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_category(self, refs_dir):
        """Test filtering by category."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                category='cli',
                keywords=['checkpointing', 'rewind']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                category='core',
                keywords=['memport', 'memory']
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act - filter by category='cli'
        results = resolver.search_by_keyword(['checkpointing'], category='cli', limit=10)
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

        # Act - search in wrong category should not return doc1
        results = resolver.search_by_keyword(['checkpointing'], category='core', limit=10)
        assert not any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_tags(self, refs_dir):
        """Test filtering by tags."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                tags=['checkpointing', 'session'],
                keywords=['checkpoint', 'rewind']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                tags=['tools'],
                keywords=['shell', 'tool']
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['checkpoint'], tags=['checkpointing'], limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_natural_language(self, refs_dir):
        """Test natural language search."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/doc1',
                'test/doc1.md',
                title='How to Use Checkpointing',
                description='Guide for using checkpointing',
                keywords=['checkpointing', 'rewind', 'guide']
            ),
            'doc2': create_mock_index_entry(
                'doc2',
                'https://geminicli.com/docs/doc2',
                'test/doc2.md',
                title='Model Routing',
                description='Model selection documentation',
                keywords=['routing', 'model']
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_natural_language('how to use checkpointing', limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_gemini_stop_word_filtering(self, refs_dir):
        """Test that 'gemini' is filtered as a stop word in natural language queries."""
        # Arrange
        index = {
            'checkpointing-doc': create_mock_index_entry(
                'checkpointing-doc',
                'https://geminicli.com/docs/checkpointing',
                'test/checkpointing.md',
                title='Checkpointing',
                description='Guide for checkpointing',
                keywords=['checkpointing', 'rewind']
            ),
            'generic-doc': create_mock_index_entry(
                'generic-doc',
                'https://geminicli.com/docs/generic',
                'test/generic.md',
                title='Gemini CLI Features',
                description='Various features',
                keywords=['gemini', 'features']
            )
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act - Query with "gemini" which should be filtered
        results = resolver.search_by_natural_language('gemini checkpointing', limit=10)

        # Assert - checkpointing-doc should match on 'checkpointing' keyword
        assert len(results) > 0
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'checkpointing-doc' in doc_ids

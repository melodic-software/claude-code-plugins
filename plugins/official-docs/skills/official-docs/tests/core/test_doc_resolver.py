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
            'test-doc': create_mock_index_entry('test-doc', 'https://example.com/test', 'test/doc.md',
                                                title='Test Document')
        }
        refs_dir.create_index(index)
        doc_file = refs_dir.references_dir / 'test' / 'doc.md'
        doc_file.parent.mkdir(parents=True, exist_ok=True)
        doc_file.write_text('# Test Document\n\nContent here.')

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.resolve_doc_id('test-doc')

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
            'new-doc-id': create_mock_index_entry('new-doc-id', 'https://example.com/new', 'test/new.md',
                                                  aliases=['old-doc-id'], title='New Document')
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
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1', 'test/doc1.md',
                                            title='Skills Guide', keywords=['skills', 'guide']),
            'doc2': create_mock_index_entry('doc2', 'https://example.com/doc2', 'test/doc2.md',
                                            title='API Reference', keywords=['api', 'reference'])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['skills'], limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_category(self, refs_dir):
        """Test filtering by category."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1', 'test/doc1.md',
                                            category='api', keywords=['api', 'reference']),
            'doc2': create_mock_index_entry('doc2', 'https://example.com/doc2', 'test/doc2.md',
                                            category='guides', keywords=['guide', 'tutorial'])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act & Assert - doc1 has category='api' but no 'guide' keyword
        results = resolver.search_by_keyword(['guide'], category='api', limit=10)
        assert len(results) == 0

        # Act & Assert - doc1 has category='api' and 'api' keyword
        results = resolver.search_by_keyword(['api'], category='api', limit=10)
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

        # Act & Assert - without category filter
        results = resolver.search_by_keyword(['api'], limit=10)
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_tags(self, refs_dir):
        """Test filtering by tags."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1', 'test/doc1.md',
                                            tags=['skills', 'guide'], keywords=['guide', 'skills']),
            'doc2': create_mock_index_entry('doc2', 'https://example.com/doc2', 'test/doc2.md',
                                            tags=['api'], keywords=['api'])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['guide'], tags=['skills'], limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_search_by_natural_language(self, refs_dir):
        """Test natural language search."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1', 'test/doc1.md',
                                            title='How to Create Skills', description='Guide for creating skills',
                                            keywords=['skills', 'create', 'guide']),
            'doc2': create_mock_index_entry('doc2', 'https://example.com/doc2', 'test/doc2.md',
                                            title='API Reference', description='API documentation',
                                            keywords=['api', 'reference'])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_natural_language('how to create skills', limit=10)

        # Assert
        assert len(results) > 0
        assert any(doc_id == 'doc1' for doc_id, _ in results)

    def test_stop_word_filtering_includes_code(self, refs_dir):
        """Test that 'code' is filtered as a stop word in natural language queries."""
        # Arrange
        index = {
            'skills-doc': create_mock_index_entry('skills-doc', 'https://example.com/skills', 'test/skills.md',
                                                  title='Create Skills', description='Guide for creating skills',
                                                  keywords=['skills', 'create']),
            'generic-code-doc': create_mock_index_entry('generic-code-doc', 'https://example.com/code', 'test/code.md',
                                                        title='Claude Code Features', description='Various code features',
                                                        keywords=['code', 'features']),
            'workflows-doc': create_mock_index_entry('workflows-doc', 'https://example.com/workflows', 'test/workflows.md',
                                                     title='Common Workflows', description='Workflow documentation',
                                                     keywords=['code', 'workflows'],  # Has 'code' keyword but not 'skills'
                                                     subsections=[
                                                         {'heading': 'Create Commands', 'anchor': '#create-commands',
                                                          'keywords': ['create', 'commands', 'code']}  # Has 'create' but not 'skills'
                                                     ])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act - Query: "Claude Code skills how to create skills"
        # After stop word filtering: ["skills", "create"] (code, claude, how filtered out)
        results = resolver.search_by_natural_language('Claude Code skills how to create skills', limit=10)

        # Assert
        # skills-doc should rank highest (has both 'skills' and 'create' in main content)
        # workflows-doc should NOT appear in top 10 (has 'create' in subsection but not 'skills' in main content)
        # generic-code-doc should not match (only has 'code' which is filtered)
        assert len(results) > 0

        # Find skills-doc in results
        skills_doc_found = False
        skills_doc_rank = None
        workflows_doc_rank = None

        for rank, (doc_id, _) in enumerate(results, 1):
            if doc_id == 'skills-doc':
                skills_doc_found = True
                skills_doc_rank = rank
            elif doc_id == 'workflows-doc':
                workflows_doc_rank = rank

        # skills-doc should be found and rank #1
        assert skills_doc_found, "skills-doc should match query"
        assert skills_doc_rank == 1, f"skills-doc should rank #1, got rank {skills_doc_rank}"

        # workflows-doc should NOT appear in results (no substantive 'skills' match in main content)
        assert workflows_doc_rank is None, \
            f"workflows-doc should not appear in results - it only matches 'create' in subsection, not 'skills' in main content"

        # Verify generic-code-doc is not in results
        doc_ids = [doc_id for doc_id, _ in results]
        assert 'generic-code-doc' not in doc_ids, \
            "generic-code-doc should not match - it only has 'code' keyword which is filtered"

    def test_resolve_extract_path(self, refs_dir, temp_dir):
        """Test resolving extract path."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1', 'test/doc1.md')
        }
        refs_dir.create_index(index)

        # Create extract file
        extract_path = temp_dir / 'extract.md'
        extract_path.write_text('# Extract\n\nContent.')

        # Create canonical file first
        canonical_file = refs_dir.references_dir / 'test' / 'doc1.md'
        canonical_file.parent.mkdir(parents=True, exist_ok=True)
        canonical_file.write_text('# Doc1\n\nContent.')

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.resolve_doc_id('doc1', extract_path=str(extract_path))

        # Assert
        assert result is not None
        # Compare resolved paths (Windows may use short vs long paths)
        assert result.resolve() == extract_path.resolve()

    def test_url_normalization_in_get_content(self, refs_dir):
        """Test that URLs are normalized (no .md extension) in get_content results."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1.md', 'test/doc1.md',
                                            title='Test Document')
        }
        refs_dir.create_index(index)

        # Create the actual file
        doc_file = refs_dir.references_dir / 'test' / 'doc1.md'
        doc_file.parent.mkdir(parents=True, exist_ok=True)
        doc_file.write_text('# Test Document\n\nContent here.')

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        result = resolver.get_content('doc1')

        # Assert
        assert result is not None
        url = result.get('url', '')
        if url:
            # URL should not have .md extension
            assert not url.endswith('.md'), f"URL should not end with .md: {url}"
            assert url == 'https://example.com/doc1', f"URL should be normalized: {url}"

    def test_url_normalization_with_subsection_anchor(self, refs_dir):
        """Test that URLs are normalized when subsection anchors are appended."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://example.com/doc1.md', 'test/doc1.md',
                                            title='Test Document', keywords=['create', 'skills'],
                                            subsections=[
                                                {
                                                    'heading': 'Creating Skills',
                                                    'anchor': '#creating-skills',
                                                    'keywords': ['create', 'skills']
                                                }
                                            ])
        }
        refs_dir.create_index(index)

        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Act
        results = resolver.search_by_keyword(['create', 'skills'], limit=10)

        # Assert
        assert len(results) > 0

        # Find doc1 in results
        for doc_id, metadata in results:
            if doc_id == 'doc1':
                url = metadata.get('url', '')
                if url:
                    # URL should have fragment but not .md before it
                    assert '#' in url, "URL should have fragment from subsection match"
                    assert url.endswith('#creating-skills'), f"URL should end with fragment: {url}"
                    assert '.md#' not in url, f"URL should not have .md before fragment: {url}"
                    assert url == 'https://example.com/doc1#creating-skills', \
                        f"URL should be normalized with fragment: {url}"
                break

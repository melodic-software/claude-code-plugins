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


class TestNewAPIMethods:
    """Test suite for new API methods added for feature parity."""

    def test_get_document_section(self, refs_dir):
        """Test extracting a section from a document."""
        # Arrange
        doc_content = """---
title: Commands
url: https://geminicli.com/docs/commands
---

# Commands

Overview of Gemini CLI commands.

## Built-in Commands

These are the built-in commands available.

### help

Shows help information.

## Custom Commands

You can create custom commands.
"""
        index = {
            'geminicli-com-docs-commands': create_mock_index_entry(
                'geminicli-com-docs-commands',
                'https://geminicli.com/docs/commands',
                'geminicli-com/docs/commands.md',
                title='Commands',
                description='CLI commands reference'
            )
        }
        refs_dir.create_index(index)
        refs_dir.create_doc('geminicli-com', 'docs', 'commands.md', doc_content)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        section = api.get_document_section('geminicli-com-docs-commands', 'Built-in Commands')

        # Assert
        assert section is not None
        assert 'content' in section
        assert 'built-in commands' in section['content'].lower() or 'help' in section['content'].lower()

    def test_get_document_section_not_found(self, refs_dir):
        """Test section extraction with non-existent section returns full content as fallback."""
        # Arrange
        doc_content = """---
title: Commands
url: https://geminicli.com/docs/commands
---

# Commands

Overview section.
"""
        index = {
            'geminicli-com-docs-commands': create_mock_index_entry(
                'geminicli-com-docs-commands',
                'https://geminicli.com/docs/commands',
                'geminicli-com/docs/commands.md',
                title='Commands'
            )
        }
        refs_dir.create_index(index)
        refs_dir.create_doc('geminicli-com', 'docs', 'commands.md', doc_content)

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act
        section = api.get_document_section('geminicli-com-docs-commands', 'Non-Existent Section')

        # Assert - when section not found, API returns full content as fallback (content_type="full")
        assert section is not None
        assert section.get('content_type') == 'full'  # Fallback to full content
        assert 'content' in section
        assert section['content'] is not None

    def test_detect_drift_missing_files(self, refs_dir):
        """Test drift detection identifies missing files."""
        # Arrange - index entry without corresponding file
        index = {
            'missing-doc': create_mock_index_entry(
                'missing-doc',
                'https://geminicli.com/docs/missing',
                'geminicli-com/docs/missing.md',
                title='Missing Doc'
            )
        }
        refs_dir.create_index(index)
        # Note: we don't create the actual file

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act - provide output_subdir matching path prefix, check_hashes=True triggers missing files check
        result = api.detect_drift(output_subdir='geminicli-com', check_404s=False, check_hashes=True)

        # Assert
        assert result['missing_files_count'] >= 1

    def test_cleanup_drift_dry_run(self, refs_dir):
        """Test cleanup drift in dry-run mode doesn't delete files."""
        # Arrange - create a doc that we'll mark as 404
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

        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Act - dry run should not delete
        result = api.cleanup_drift(clean_404s=True, clean_missing_files=True, dry_run=True)

        # Assert - file should still exist
        assert doc_path.exists()
        assert 'dry_run' not in result or result.get('dry_run', True)


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

    def test_get_document_section_function(self, refs_dir, monkeypatch):
        """Test module-level get_document_section function."""
        # Arrange
        doc_content = """---
title: Tools
url: https://geminicli.com/docs/tools
---

# Tools

## Overview

Tool overview section.
"""
        index = {
            'tools-doc': create_mock_index_entry(
                'tools-doc',
                'https://geminicli.com/docs/tools',
                'geminicli-com/docs/tools.md',
                title='Tools'
            )
        }
        refs_dir.create_index(index)
        refs_dir.create_doc('geminicli-com', 'docs', 'tools.md', doc_content)

        from gemini_docs_api import GeminiDocsAPI
        import gemini_docs_api
        gemini_docs_api._api_instance = None
        api = GeminiDocsAPI(refs_dir.references_dir)
        monkeypatch.setattr(gemini_docs_api, '_api_instance', api)

        # Act
        from gemini_docs_api import get_document_section
        section = get_document_section('tools-doc', 'Overview')

        # Assert
        assert section is not None

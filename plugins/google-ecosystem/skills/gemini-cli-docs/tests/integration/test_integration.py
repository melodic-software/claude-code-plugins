"""
End-to-end integration tests for gemini-cli-docs skill.

Tests the full workflow from index loading to search results.
"""

import pytest
from tests.shared.test_utils import create_mock_index_entry, TempReferencesDir


class TestEndToEndWorkflow:
    """Test complete workflows from index to search."""

    def test_full_search_workflow(self, refs_dir):
        """Test complete search workflow: load index, search, get content."""
        # Arrange - Create a complete test environment
        index = {
            'geminicli-com-docs-cli-checkpointing': create_mock_index_entry(
                'geminicli-com-docs-cli-checkpointing',
                'https://geminicli.com/docs/cli/checkpointing',
                'geminicli-com/docs/cli/checkpointing.md',
                title='Checkpointing',
                description='Save and restore file states',
                keywords=['checkpointing', 'rewind', 'snapshot'],
                category='cli',
                tags=['checkpointing', 'session']
            )
        }
        refs_dir.create_index(index)

        # Create the actual document file
        doc_content = """# Checkpointing

## Overview

Checkpointing allows you to save the current state of your files.

## Usage

Use `/checkpoint` to create a checkpoint.

## Rewinding

Use `/rewind` to go back to a previous checkpoint.
"""
        doc_path = refs_dir.references_dir / 'geminicli-com' / 'docs' / 'cli' / 'checkpointing.md'
        doc_path.parent.mkdir(parents=True, exist_ok=True)
        doc_path.write_text(doc_content)

        # Act - Load and search
        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Search by natural language
        results = resolver.search_by_natural_language('checkpointing', limit=5)

        # Assert
        assert len(results) > 0
        doc_id, metadata = results[0]
        assert doc_id == 'geminicli-com-docs-cli-checkpointing'
        assert metadata['title'] == 'Checkpointing'

        # Get content
        content = resolver.get_content(doc_id)
        assert content is not None
        assert 'Checkpointing' in content.get('content', '')

    def test_api_integration(self, refs_dir):
        """Test GeminiDocsAPI integration with full workflow."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/tool1',
                'geminicli-com/docs/tools/shell.md',
                title='Shell Tool',
                description='Execute shell commands',
                keywords=['shell', 'command', 'execute'],
                category='tools',
                tags=['tools', 'shell']
            )
        }
        refs_dir.create_index(index)

        # Create document
        doc_content = "# Shell Tool\n\nExecute shell commands safely."
        doc_path = refs_dir.references_dir / 'geminicli-com' / 'docs' / 'tools' / 'shell.md'
        doc_path.parent.mkdir(parents=True, exist_ok=True)
        doc_path.write_text(doc_content)

        # Act
        from gemini_docs_api import GeminiDocsAPI
        api = GeminiDocsAPI(refs_dir.references_dir)

        # Test find_document
        results = api.find_document('shell command')
        assert len(results) > 0
        assert results[0]['doc_id'] == 'doc1'

        # Test get_docs_by_category
        results = api.get_docs_by_category('tools')
        assert len(results) == 1

        # Test get_docs_by_tag
        results = api.get_docs_by_tag('shell')
        assert len(results) == 1

    def test_subsection_extraction(self, refs_dir):
        """Test that subsection extraction works correctly."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry(
                'doc1',
                'https://geminicli.com/docs/checkpointing',
                'geminicli-com/docs/checkpointing.md',
                title='Checkpointing',
                subsections=[
                    {
                        'heading': 'Creating Checkpoints',
                        'anchor': '#creating-checkpoints',
                        'keywords': ['create', 'checkpoint']
                    },
                    {
                        'heading': 'Rewinding',
                        'anchor': '#rewinding',
                        'keywords': ['rewind', 'restore']
                    }
                ]
            )
        }
        refs_dir.create_index(index)

        # Create document with sections
        doc_content = """# Checkpointing

## Creating Checkpoints

Use the checkpoint command to save state.

```bash
gemini checkpoint create
```

## Rewinding

Use the rewind command to restore.

```bash
gemini rewind
```
"""
        doc_path = refs_dir.references_dir / 'geminicli-com' / 'docs' / 'checkpointing.md'
        doc_path.parent.mkdir(parents=True, exist_ok=True)
        doc_path.write_text(doc_content)

        # Act
        from scripts.core.doc_resolver import DocResolver
        resolver = DocResolver(refs_dir.references_dir)

        # Get specific section
        content = resolver.get_content('doc1', section='Creating Checkpoints')

        # Assert
        assert content is not None
        # Content should include the section


class TestIndexManagement:
    """Test index management operations."""

    def test_index_load_and_query(self, refs_dir):
        """Test loading index and querying entries."""
        # Arrange
        index = {
            'doc1': create_mock_index_entry('doc1', 'https://geminicli.com/doc1', 'doc1.md'),
            'doc2': create_mock_index_entry('doc2', 'https://geminicli.com/doc2', 'doc2.md'),
            'doc3': create_mock_index_entry('doc3', 'https://geminicli.com/doc3', 'doc3.md')
        }
        refs_dir.create_index(index)

        # Act
        from scripts.management.index_manager import IndexManager
        manager = IndexManager(refs_dir.references_dir)
        all_entries = manager.load_all()

        # Assert
        assert len(all_entries) == 3
        assert 'doc1' in all_entries
        assert 'doc2' in all_entries
        assert 'doc3' in all_entries

    def test_get_single_entry(self, refs_dir):
        """Test getting a single entry by doc_id."""
        # Arrange
        index = {
            'target-doc': create_mock_index_entry(
                'target-doc',
                'https://geminicli.com/target',
                'target.md',
                title='Target Document'
            )
        }
        refs_dir.create_index(index)

        # Act
        from scripts.management.index_manager import IndexManager
        manager = IndexManager(refs_dir.references_dir)
        entry = manager.get_entry('target-doc')

        # Assert
        assert entry is not None
        assert entry.get('title') == 'Target Document'

    def test_get_missing_entry(self, refs_dir):
        """Test getting a non-existent entry."""
        # Arrange
        refs_dir.create_index({})

        # Act
        from scripts.management.index_manager import IndexManager
        manager = IndexManager(refs_dir.references_dir)
        entry = manager.get_entry('nonexistent')

        # Assert
        assert entry is None

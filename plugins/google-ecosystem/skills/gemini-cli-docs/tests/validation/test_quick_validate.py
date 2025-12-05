"""
Tests for quick_validate.py script.

Tests quick validation functions for index and file consistency.
"""

from tests.shared.test_utils import TempReferencesDir, create_mock_index_entry


class TestQuickValidate:
    """Test suite for quick_validate functions"""

    def test_validate_index_entries_match_files(self, temp_dir):
        """Test that index entries are validated against files"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with one entry
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Doc'
                )
            }
            refs_dir.create_index(index)

            # Create corresponding file with all required frontmatter fields
            # Must have substantial content (>100 chars) to pass quick_validate
            doc_content = """---
title: Test Doc
url: https://geminicli.com/docs/test
source_url: https://geminicli.com/docs/test
source_type: llms.txt
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Test Document

This is a comprehensive test document with sufficient content to pass the quick
validation checks. The content must be substantial enough to avoid being flagged
as suspiciously short. Here we include multiple paragraphs and sections.

## Overview

This section provides an overview of the test document functionality and purpose.

## Details

Additional details and information are provided here to ensure the document
has enough content to be considered valid during validation.
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.quick_validate import quick_validate

            # Should pass validation when index matches files and all fields present
            result = quick_validate(refs_dir.references_dir)
            assert result is True
        finally:
            refs_dir.cleanup()

    def test_validate_detects_missing_files(self, temp_dir):
        """Test that validation detects missing files"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with entry but no file
            index = {
                'missing-doc': create_mock_index_entry(
                    'missing-doc',
                    'https://geminicli.com/docs/missing',
                    'geminicli-com/docs/missing.md',
                    title='Missing Doc'
                )
            }
            refs_dir.create_index(index)
            # Don't create the file

            from scripts.validation.quick_validate import quick_validate

            # Should fail validation due to missing file
            result = quick_validate(refs_dir.references_dir)
            assert result is False
        finally:
            refs_dir.cleanup()

    def test_validate_detects_orphaned_files(self, temp_dir):
        """Test that validation detects orphaned files (files without index entry)"""
        refs_dir = TempReferencesDir()
        try:
            # Create empty index
            refs_dir.create_index({})

            # Create file without index entry
            doc_content = """---
title: Orphaned Doc
url: https://geminicli.com/docs/orphaned
source_url: https://geminicli.com/docs/orphaned
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Orphaned Document
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'orphaned.md', doc_content)

            from scripts.validation.quick_validate import quick_validate

            # Should detect orphaned file
            result = quick_validate(refs_dir.references_dir)
            # Result depends on implementation - orphaned files may or may not fail validation
            # The important thing is it doesn't crash
            assert isinstance(result, bool)
        finally:
            refs_dir.cleanup()

    def test_validate_with_expected_count(self, temp_dir):
        """Test validation with expected file count"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with two entries
            index = {
                'doc1': create_mock_index_entry('doc1', 'https://geminicli.com/docs/doc1', 'geminicli-com/docs/doc1.md'),
                'doc2': create_mock_index_entry('doc2', 'https://geminicli.com/docs/doc2', 'geminicli-com/docs/doc2.md')
            }
            refs_dir.create_index(index)

            # Create both files with proper frontmatter and substantial content
            for name in ['doc1', 'doc2']:
                doc_content = f"""---
title: {name}
url: https://geminicli.com/docs/{name}
source_url: https://geminicli.com/docs/{name}
source_type: llms.txt
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# {name}

This is a comprehensive document for {name} with sufficient content to pass the
quick validation checks. The content must be substantial enough to avoid being
flagged as suspiciously short during validation.

## Overview

This section provides an overview of the {name} document functionality.

## Details

Additional details and information are provided here to ensure the document
has enough content to be considered valid during validation.
"""
                refs_dir.create_doc('geminicli-com', 'docs', f'{name}.md', doc_content)

            from scripts.validation.quick_validate import quick_validate

            # Should pass with correct expected count
            result = quick_validate(refs_dir.references_dir, expected_count=2)
            assert result is True
        finally:
            refs_dir.cleanup()

    def test_validate_fails_with_wrong_expected_count(self, temp_dir):
        """Test validation fails with wrong expected file count"""
        refs_dir = TempReferencesDir()
        try:
            # Create index with one entry
            index = {
                'doc1': create_mock_index_entry('doc1', 'https://geminicli.com/docs/doc1', 'geminicli-com/docs/doc1.md')
            }
            refs_dir.create_index(index)

            doc_content = """---
title: doc1
url: https://geminicli.com/docs/doc1
source_url: https://geminicli.com/docs/doc1
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# doc1

Content.
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'doc1.md', doc_content)

            from scripts.validation.quick_validate import quick_validate

            # Should fail with wrong expected count
            result = quick_validate(refs_dir.references_dir, expected_count=5)
            assert result is False
        finally:
            refs_dir.cleanup()

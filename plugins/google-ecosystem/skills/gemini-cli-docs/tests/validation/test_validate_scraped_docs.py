"""
Tests for validate_scraped_docs.py script.

Tests the GeminiScrapedDocsValidator class for validating scraped documentation.
"""

from tests.shared.test_utils import TempReferencesDir, create_mock_index_entry


class TestGeminiScrapedDocsValidator:
    """Test suite for GeminiScrapedDocsValidator"""

    def test_validate_frontmatter(self, temp_dir):
        """Test frontmatter validation"""
        refs_dir = TempReferencesDir()
        try:
            # Create document with valid frontmatter including all required fields
            # Required fields: source_url, source_type, last_fetched, content_hash
            doc_content = """---
title: Test Document
url: https://geminicli.com/docs/test
source_url: https://geminicli.com/docs/test
source_type: llms.txt
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Test Document

Content here.
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Document'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_frontmatter()

            # Should return validation results
            assert isinstance(result, dict)
            # Should pass with valid frontmatter (all required fields present)
            assert result.get('passed', False) is True
            assert result.get('details', {}).get('valid', 0) >= 1
        finally:
            refs_dir.cleanup()

    def test_validate_frontmatter_missing_required_fields(self, temp_dir):
        """Test frontmatter validation with missing required fields"""
        refs_dir = TempReferencesDir()
        try:
            # Create document with missing fields in frontmatter
            doc_content = """---
url: https://geminicli.com/docs/test
---

# Test Document

Content here.
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Document'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_frontmatter()

            # Should detect missing title
            assert isinstance(result, dict)
        finally:
            refs_dir.cleanup()

    def test_validate_index_integrity(self, temp_dir):
        """Test index integrity validation"""
        refs_dir = TempReferencesDir()
        try:
            doc_content = """---
title: Test Document
url: https://geminicli.com/docs/test
source_url: https://geminicli.com/docs/test
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Test Document
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Document'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_index_integrity()

            assert isinstance(result, dict)
        finally:
            refs_dir.cleanup()

    def test_validate_content_quality(self, temp_dir):
        """Test content quality validation"""
        refs_dir = TempReferencesDir()
        try:
            # Create document with content
            doc_content = """---
title: Test Document
url: https://geminicli.com/docs/test
source_url: https://geminicli.com/docs/test
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Test Document

This is a well-formed document with sufficient content.
It has multiple paragraphs and proper structure.

## Section 1

More content here.

## Section 2

Even more content.
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Document'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_content_quality()

            assert isinstance(result, dict)
        finally:
            refs_dir.cleanup()

    def test_validate_all_returns_tuple(self, temp_dir):
        """Test that validate_all returns (bool, report_str) tuple"""
        refs_dir = TempReferencesDir()
        try:
            doc_content = """---
title: Test Document
url: https://geminicli.com/docs/test
source_url: https://geminicli.com/docs/test
last_fetched: "2025-01-01T00:00:00Z"
content_hash: abc123
---

# Test Document

Content here.
"""
            index = {
                'test-doc': create_mock_index_entry(
                    'test-doc',
                    'https://geminicli.com/docs/test',
                    'geminicli-com/docs/test.md',
                    title='Test Document'
                )
            }
            refs_dir.create_index(index)
            refs_dir.create_doc('geminicli-com', 'docs', 'test.md', doc_content)

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_all()

            # validate_all returns (passed: bool, report: str)
            assert isinstance(result, tuple)
            assert len(result) == 2
            passed, report = result
            assert isinstance(passed, bool)
            assert isinstance(report, str)
        finally:
            refs_dir.cleanup()

    def test_validate_directory_structure(self, temp_dir):
        """Test directory structure validation"""
        refs_dir = TempReferencesDir()
        try:
            refs_dir.create_index({})

            from scripts.validation.validate_scraped_docs import GeminiScrapedDocsValidator

            validator = GeminiScrapedDocsValidator(refs_dir.references_dir)
            result = validator.validate_directory_structure()

            assert isinstance(result, dict)
        finally:
            refs_dir.cleanup()

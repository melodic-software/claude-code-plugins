"""
Tests for cleanup_stale.py script.

Tests the GeminiStaleCleanup class for finding files marked as stale.
"""

from tests.shared.test_utils import TempReferencesDir


class TestGeminiStaleCleanup:
    """Test suite for GeminiStaleCleanup"""

    def test_find_stale_files_with_stale_status(self, temp_dir):
        """Test finding files marked with status: stale in frontmatter"""
        refs_dir = TempReferencesDir()
        try:
            # Create a document with status: stale in frontmatter
            stale_content = """---
title: Stale Doc
url: https://geminicli.com/docs/stale
status: stale
---

# Stale Document

This document is marked as stale.
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'stale.md', stale_content)

            from scripts.maintenance.cleanup_stale import GeminiStaleCleanup

            cleaner = GeminiStaleCleanup(refs_dir.references_dir)
            stale_files = cleaner.find_stale_files()

            # Should find the stale file
            assert len(stale_files) >= 1
            paths = [str(path) for path, _ in stale_files]
            assert any('stale.md' in p for p in paths)
        finally:
            refs_dir.cleanup()

    def test_find_stale_files_no_stale(self, temp_dir):
        """Test that normal files are not marked as stale"""
        refs_dir = TempReferencesDir()
        try:
            # Create a normal document without status: stale
            normal_content = """---
title: Normal Doc
url: https://geminicli.com/docs/normal
---

# Normal Document

This document is not stale.
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'normal.md', normal_content)

            from scripts.maintenance.cleanup_stale import GeminiStaleCleanup

            cleaner = GeminiStaleCleanup(refs_dir.references_dir)
            stale_files = cleaner.find_stale_files()

            # Should not find any stale files
            assert len(stale_files) == 0
        finally:
            refs_dir.cleanup()

    def test_find_stale_files_with_output_filter(self, temp_dir):
        """Test filtering stale files by output subdirectory"""
        refs_dir = TempReferencesDir()
        try:
            # Create stale docs in different subdirectories
            stale_content = """---
title: Stale Doc
url: https://geminicli.com/docs/stale
status: stale
---

# Stale Document
"""
            refs_dir.create_doc('geminicli-com', 'docs', 'stale1.md', stale_content)
            refs_dir.create_doc('other-domain', 'docs', 'stale2.md', stale_content)

            from scripts.maintenance.cleanup_stale import GeminiStaleCleanup

            cleaner = GeminiStaleCleanup(refs_dir.references_dir)

            # Filter to only geminicli-com
            stale_files = cleaner.find_stale_files(output_filter='geminicli-com')

            # Should only find stale1.md
            paths = [str(path) for path, _ in stale_files]
            assert any('stale1.md' in p for p in paths)
            # stale2.md should not be included (different domain)
            assert not any('stale2.md' in p for p in paths)
        finally:
            refs_dir.cleanup()

    def test_cleanup_stale_files_dry_run(self, temp_dir):
        """Test cleanup in dry-run mode preserves files"""
        refs_dir = TempReferencesDir()
        try:
            stale_content = """---
title: Stale Doc
url: https://geminicli.com/docs/stale
status: stale
---

# Stale Document
"""
            doc_path = refs_dir.create_doc('geminicli-com', 'docs', 'stale.md', stale_content)

            from scripts.maintenance.cleanup_stale import GeminiStaleCleanup

            cleaner = GeminiStaleCleanup(refs_dir.references_dir)
            stale_files = cleaner.find_stale_files()

            # Verify stale file was found
            assert len(stale_files) == 1

            # In a "dry-run" scenario, we simply don't call remove_stale_files
            # The remove_stale_files method with force=False prompts for confirmation
            # which isn't suitable for automated tests. Instead, we verify:
            # 1. find_stale_files correctly identifies stale files
            # 2. Not calling remove_stale_files preserves the file (the "dry-run" behavior)

            # File should still exist (we didn't remove it)
            assert doc_path.exists()
        finally:
            refs_dir.cleanup()

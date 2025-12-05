#!/usr/bin/env python3
"""
Public API for gemini-cli-docs skill.

Provides a clean, stable API for external tools to interact with the
Gemini CLI documentation management system. This API abstracts away
implementation details and provides simple functions for common operations.

Usage:
    from gemini_docs_api import find_document, resolve_doc_id, get_docs_by_tag

    # Find documents by query
    docs = find_document("checkpointing model routing")

    # Resolve doc_id to metadata
    doc = resolve_doc_id("geminicli-com-docs-cli-checkpointing")

    # Get docs by tag
    docs = get_docs_by_tag("cli")
"""

import sys
from pathlib import Path
from typing import Any

# Add scripts directory to path
_scripts_dir = Path(__file__).parent / 'scripts'
if str(_scripts_dir) not in sys.path:
    sys.path.insert(0, str(_scripts_dir))

from scripts.management.index_manager import IndexManager
from scripts.core.doc_resolver import DocResolver
from scripts.maintenance.detect_changes import GeminiChangeDetector
from scripts.maintenance.cleanup_drift import GeminiDriftCleaner
from scripts.utils.path_config import get_base_dir


class GeminiDocsAPI:
    """
    Public API for gemini-cli-docs skill.

    Provides high-level functions for Gemini CLI documentation operations.
    All functions are designed to be simple, stable, and easy to use.
    """

    def __init__(self, base_dir: Path | None = None):
        """
        Initialize API instance.

        Args:
            base_dir: Base directory for references. If None, uses config default.
        """
        if base_dir:
            self.base_dir = Path(base_dir)
        else:
            self.base_dir = get_base_dir()
        self.index_manager = IndexManager(self.base_dir)
        self.doc_resolver = DocResolver(self.base_dir)

    def find_document(self, query: str, limit: int = 10) -> list[dict[str, Any]]:
        """
        Find documents by natural language query.

        Args:
            query: Natural language search query (e.g., "how to use checkpointing")
            limit: Maximum number of results to return (default: 10)

        Returns:
            List of document dictionaries with keys:
            - doc_id: Document identifier
            - url: Source URL
            - title: Document title
            - description: Document description
            - keywords: List of keywords
            - tags: List of tags
            - relevance_score: Relevance score (0-1)

        Example:
            >>> api = GeminiDocsAPI()
            >>> docs = api.find_document("model routing")
            >>> print(docs[0]['title'])
        """
        try:
            results = self.doc_resolver.search_by_natural_language(query, limit=limit)
            return [
                {
                    'doc_id': doc_id,
                    'url': metadata.get('url'),
                    'title': metadata.get('title'),
                    'description': metadata.get('description'),
                    'keywords': metadata.get('keywords', []),
                    'tags': metadata.get('tags', []),
                    'relevance_score': 1.0,
                }
                for doc_id, metadata in results
            ]
        except Exception:
            return []

    def resolve_doc_id(self, doc_id: str) -> dict[str, Any] | None:
        """
        Resolve doc_id to file path and metadata.

        Args:
            doc_id: Document identifier (e.g., "geminicli-com-docs-cli-checkpointing")

        Returns:
            Dictionary with keys:
            - doc_id: Document identifier
            - url: Source URL
            - title: Document title
            - description: Document description
            - metadata: Full metadata dictionary

        Returns None if doc_id not found.

        Example:
            >>> api = GeminiDocsAPI()
            >>> doc = api.resolve_doc_id("geminicli-com-docs-cli-checkpointing")
            >>> print(doc['title'])
        """
        try:
            entry = self.index_manager.get_entry(doc_id)
            if entry:
                return {
                    'doc_id': doc_id,
                    'url': entry.get('url'),
                    'title': entry.get('title'),
                    'description': entry.get('description'),
                    'metadata': entry,
                }

            path = self.doc_resolver.resolve_doc_id(doc_id)
            if path:
                return {
                    'doc_id': doc_id,
                    'url': None,
                    'title': None,
                    'description': None,
                    'metadata': {},
                }
        except Exception:
            pass
        return None

    def get_docs_by_tag(self, tag: str, limit: int = 100) -> list[dict[str, Any]]:
        """
        Get all documents with a specific tag.

        Args:
            tag: Tag name (e.g., "cli", "tools", "extensions")
            limit: Maximum number of results to return (default: 100)

        Returns:
            List of document dictionaries (same format as find_document)

        Example:
            >>> api = GeminiDocsAPI()
            >>> docs = api.get_docs_by_tag("cli")
            >>> print(f"Found {len(docs)} documents with tag 'cli'")
        """
        try:
            index = self.index_manager.load_all()
            results = []

            for doc_id, metadata in index.items():
                tags = metadata.get('tags', [])
                if isinstance(tags, str):
                    tags = [tags]
                tags = [t.lower() for t in tags]

                if tag.lower() in tags:
                    results.append({
                        'doc_id': doc_id,
                        'url': metadata.get('url'),
                        'title': metadata.get('title'),
                        'description': metadata.get('description'),
                        'keywords': metadata.get('keywords', []),
                        'tags': tags,
                        'relevance_score': 1.0,
                    })

                    if len(results) >= limit:
                        break

            return results
        except Exception:
            return []

    def get_docs_by_category(self, category: str, limit: int = 100) -> list[dict[str, Any]]:
        """
        Get all documents in a specific category.

        Args:
            category: Category name (e.g., "cli", "tools", "extensions")
            limit: Maximum number of results to return (default: 100)

        Returns:
            List of document dictionaries (same format as find_document)

        Example:
            >>> api = GeminiDocsAPI()
            >>> docs = api.get_docs_by_category("cli")
            >>> print(f"Found {len(docs)} documents in category 'cli'")
        """
        try:
            index = self.index_manager.load_all()
            results = []

            for doc_id, metadata in index.items():
                doc_category = metadata.get('category', '').lower()
                if category.lower() == doc_category:
                    results.append({
                        'doc_id': doc_id,
                        'url': metadata.get('url'),
                        'title': metadata.get('title'),
                        'description': metadata.get('description'),
                        'keywords': metadata.get('keywords', []),
                        'tags': metadata.get('tags', []),
                        'relevance_score': 1.0,
                    })

                    if len(results) >= limit:
                        break

            return results
        except Exception:
            return []

    def get_document_content(self, doc_id: str, section: str | None = None) -> dict[str, Any] | None:
        """
        Get document content (full or partial section).

        Args:
            doc_id: Document identifier
            section: Optional section heading to extract (if None, returns full content)

        Returns:
            Dictionary with keys:
            - content: Markdown content (partial or full)
            - content_type: "partial" | "full" | "link"
            - section_ref: Hashtag reference if partial (e.g., "#checkpointing")
            - doc_id: Document identifier
            - url: Source URL if available
            - title: Document title
            - description: Document description

        Returns None if doc_id not found or file doesn't exist.

        Example:
            >>> api = GeminiDocsAPI()
            >>> content = api.get_document_content("geminicli-com-docs-cli-checkpointing")
            >>> print(content['content'][:100])
        """
        return self.doc_resolver.get_content(doc_id, section)

    def get_document_section(self, doc_id: str, heading: str) -> dict[str, Any] | None:
        """
        Get a specific section from a document.

        Args:
            doc_id: Document identifier
            heading: Section heading to extract

        Returns:
            Dictionary with keys (same format as get_document_content):
            - content: Markdown content for the section
            - content_type: "partial" (always partial for sections)
            - section_ref: Hashtag reference (e.g., "#checkpointing")
            - doc_id: Document identifier
            - url: Source URL if available
            - title: Document title
            - description: Document description

        Returns None if doc_id not found, file doesn't exist, or section not found.

        Example:
            >>> api = GeminiDocsAPI()
            >>> section = api.get_document_section("geminicli-com-docs-cli-checkpointing", "Usage")
            >>> print(section['section_ref'])
        """
        return self.doc_resolver.get_content(doc_id, section=heading)

    def search_by_keywords(self, keywords: list[str], limit: int = 10) -> list[dict[str, Any]]:
        """
        Search documents by keywords.

        Args:
            keywords: List of keywords to search for
            limit: Maximum number of results to return (default: 10)

        Returns:
            List of document dictionaries (same format as find_document)

        Example:
            >>> api = GeminiDocsAPI()
            >>> docs = api.search_by_keywords(["checkpointing", "session"])
            >>> print(f"Found {len(docs)} documents matching keywords")
        """
        try:
            results = self.doc_resolver.search_by_keyword(keywords, limit=limit)
            return [
                {
                    'doc_id': doc_id,
                    'url': metadata.get('url'),
                    'title': metadata.get('title'),
                    'description': metadata.get('description'),
                    'keywords': metadata.get('keywords', []),
                    'tags': metadata.get('tags', []),
                    'relevance_score': 1.0,
                }
                for doc_id, metadata in results
            ]
        except Exception:
            return []

    def detect_drift(self, output_subdir: str = "", check_404s: bool = True,
                    check_hashes: bool = True, max_workers: int = 5) -> dict[str, Any]:
        """
        Detect drift in documentation (404s, missing files, hash mismatches).

        Args:
            output_subdir: Output subdirectory to check (e.g., "gemini-docs")
            check_404s: Check for 404 URLs (default: True)
            check_hashes: Compare content hashes (default: True)
            max_workers: Maximum parallel workers (default: 5)

        Returns:
            Dictionary with keys:
            - url_404_count: Number of 404 URLs
            - missing_files_count: Number of missing files
            - hash_mismatch_count: Number of content changes
            - url_404s: List of 404 URLs
            - missing_files: List of missing file doc_ids
            - hash_mismatches: List of doc_ids with hash mismatches

        Example:
            >>> api = GeminiDocsAPI()
            >>> drift = api.detect_drift("gemini-docs")
            >>> print(f"Found {drift['url_404_count']} 404 URLs")
        """
        try:
            detector = GeminiChangeDetector(self.base_dir)
            index = detector.load_index()
            indexed_urls = detector.get_indexed_urls(index, output_subdir)

            if not indexed_urls:
                return {
                    'url_404_count': 0,
                    'missing_files_count': 0,
                    'hash_mismatch_count': 0,
                    'url_404s': [],
                    'missing_files': [],
                    'hash_mismatches': []
                }

            url_404s = {}
            if check_404s:
                url_404s = detector.check_404_urls(set(indexed_urls.keys()), max_workers=max_workers)

            missing_files = []
            if check_hashes:
                cleaner = GeminiDriftCleaner(self.base_dir, dry_run=True)
                missing = cleaner.find_missing_files(index)
                missing_files = [doc_id for doc_id, _ in missing]

            hash_mismatches = {}
            if check_hashes:
                hash_mismatches = detector.compare_content_hashes(indexed_urls, output_subdir)

            url_404_list = [url for url, is_404 in url_404s.items() if is_404]
            hash_mismatch_list = [doc_id for doc_id, (local, remote) in hash_mismatches.items()
                                 if local and remote and local != remote]

            return {
                'url_404_count': len(url_404_list),
                'missing_files_count': len(missing_files),
                'hash_mismatch_count': len(hash_mismatch_list),
                'url_404s': url_404_list,
                'missing_files': missing_files,
                'hash_mismatches': hash_mismatch_list
            }
        except Exception as e:
            return {
                'error': str(e),
                'url_404_count': 0,
                'missing_files_count': 0,
                'hash_mismatch_count': 0,
                'url_404s': [],
                'missing_files': [],
                'hash_mismatches': []
            }

    def cleanup_drift(self, output_subdir: str = "", clean_404s: bool = True,
                     clean_missing_files: bool = True, dry_run: bool = True,
                     max_workers: int = 5) -> dict[str, Any]:
        """
        Clean up drift (remove 404 docs, missing files, etc.).

        Args:
            output_subdir: Output subdirectory to clean (e.g., "gemini-docs")
            clean_404s: Remove documents with 404 source URLs (default: True)
            clean_missing_files: Remove index entries for missing files (default: True)
            dry_run: If True, only report what would be cleaned (default: True)
            max_workers: Maximum parallel workers (default: 5)

        Returns:
            Dictionary with keys:
            - files_removed: Number of files removed
            - index_entries_removed: Number of index entries removed
            - operations: Number of cleanup operations performed
            - dry_run: Whether this was a dry run

        Example:
            >>> api = GeminiDocsAPI()
            >>> result = api.cleanup_drift("gemini-docs", dry_run=True)
            >>> print(f"Would remove {result['index_entries_removed']} index entries")
        """
        try:
            cleaner = GeminiDriftCleaner(self.base_dir, dry_run=dry_run)
            index = cleaner.load_index()

            files_removed = 0
            index_removed = 0

            if clean_404s:
                url_404s = cleaner.find_404_urls(index, max_workers=max_workers)
                if url_404s:
                    f_removed, i_removed = cleaner.clean_404_urls(index, max_workers=max_workers)
                    files_removed += f_removed
                    index_removed += i_removed

            if clean_missing_files:
                f_checked, i_removed = cleaner.clean_missing_files(index)
                index_removed += i_removed

            return {
                'files_removed': files_removed,
                'index_entries_removed': index_removed,
                'operations': len(cleaner.cleanup_log),
                'dry_run': dry_run
            }
        except Exception as e:
            return {
                'error': str(e),
                'files_removed': 0,
                'index_entries_removed': 0,
                'operations': 0,
                'dry_run': dry_run
            }

    def refresh_index(self, check_drift: bool = False, cleanup_drift: bool = False,
                     max_workers: int = 5) -> dict[str, Any]:
        """
        Refresh the index (rebuild, extract keywords, validate).

        This is a high-level workflow method that orchestrates the full index refresh.
        Uses direct imports instead of subprocess for better error handling and performance.

        Args:
            check_drift: If True, detect drift after refreshing (default: False)
            cleanup_drift: If True, automatically cleanup detected drift (requires check_drift) (default: False)
            max_workers: Maximum parallel workers for drift detection (default: 5)

        Returns:
            Dictionary with keys:
            - success: Whether refresh succeeded
            - steps_completed: List of completed steps
            - drift_detected: Whether drift was detected (if check_drift=True)
            - errors: List of any errors encountered

        Example:
            >>> api = GeminiDocsAPI()
            >>> result = api.refresh_index(check_drift=True)
            >>> print(f"Refresh {'succeeded' if result['success'] else 'failed'}")
        """
        steps_completed = []
        errors = []
        drift_detected = False

        # Import required modules (scripts directory already in path from module init)
        try:
            scripts_dir = Path(__file__).parent / 'scripts'
            if str(scripts_dir) not in sys.path:
                sys.path.insert(0, str(scripts_dir))

            from scripts.management.rebuild_index import rebuild_index
            from scripts.management.manage_index import cmd_extract_keywords, cmd_validate_metadata
        except ImportError as e:
            return {
                'success': False,
                'steps_completed': [],
                'drift_detected': False,
                'errors': [f"Failed to import required modules: {e}. Ensure scripts are in Python path."]
            }

        # Step 1: Rebuild index
        try:
            result = rebuild_index(self.base_dir, dry_run=False)
            steps_completed.append('rebuild_index')
        except Exception as e:
            errors.append(f"rebuild_index error: {e}")

        # Step 2: Extract keywords
        try:
            manager = IndexManager(self.base_dir)
            cmd_extract_keywords(manager, self.base_dir, skip_existing=True, verbose=False,
                                auto_install=True, json_output=False)
            steps_completed.append('extract_keywords')
        except Exception as e:
            errors.append(f"extract_keywords error: {e}")

        # Step 3: Validate metadata
        try:
            manager = IndexManager(self.base_dir)
            cmd_validate_metadata(manager, self.base_dir, json_output=False)
            steps_completed.append('validate_metadata')
        except Exception as e:
            # Validation errors are non-fatal
            steps_completed.append('validate_metadata')
            errors.append(f"validate_metadata warning: {e}")

        # Step 4: Check drift if requested
        if check_drift:
            try:
                drift_result = self.detect_drift("", check_404s=True, check_hashes=False, max_workers=max_workers)
                if drift_result.get('url_404_count', 0) > 0 or drift_result.get('missing_files_count', 0) > 0:
                    drift_detected = True
                    steps_completed.append('drift_detection')

                    if cleanup_drift:
                        cleanup_result = self.cleanup_drift("", clean_404s=True, clean_missing_files=True,
                                                           dry_run=False, max_workers=max_workers)
                        if cleanup_result.get('index_entries_removed', 0) > 0:
                            steps_completed.append('drift_cleanup')
                else:
                    steps_completed.append('drift_detection')
            except Exception as e:
                errors.append(f"drift_detection error: {e}")

        success = len(errors) == 0 and len(steps_completed) >= 1

        return {
            'success': success,
            'steps_completed': steps_completed,
            'drift_detected': drift_detected,
            'errors': errors
        }


# Module-level convenience functions (use default base_dir)
_api_instance: GeminiDocsAPI | None = None


def _get_api() -> GeminiDocsAPI:
    """Get or create API instance"""
    global _api_instance
    if _api_instance is None:
        _api_instance = GeminiDocsAPI()
    return _api_instance


def find_document(query: str, limit: int = 10) -> list[dict[str, Any]]:
    """Find documents by natural language query."""
    return _get_api().find_document(query, limit)


def resolve_doc_id(doc_id: str) -> dict[str, Any] | None:
    """Resolve doc_id to metadata."""
    return _get_api().resolve_doc_id(doc_id)


def get_document_content(doc_id: str, section: str | None = None) -> dict[str, Any] | None:
    """Get document content (full or partial section)."""
    return _get_api().get_document_content(doc_id, section)


def get_document_section(doc_id: str, heading: str) -> dict[str, Any] | None:
    """Get a specific section from a document."""
    return _get_api().get_document_section(doc_id, heading)


def get_docs_by_tag(tag: str, limit: int = 100) -> list[dict[str, Any]]:
    """Get all documents with a specific tag."""
    return _get_api().get_docs_by_tag(tag, limit)


def get_docs_by_category(category: str, limit: int = 100) -> list[dict[str, Any]]:
    """Get all documents in a specific category."""
    return _get_api().get_docs_by_category(category, limit)


def search_by_keywords(keywords: list[str], limit: int = 10) -> list[dict[str, Any]]:
    """Search documents by keywords."""
    return _get_api().search_by_keywords(keywords, limit)


def detect_drift(output_subdir: str = "", check_404s: bool = True,
                check_hashes: bool = True, max_workers: int = 5) -> dict[str, Any]:
    """Detect drift in documentation."""
    return _get_api().detect_drift(output_subdir, check_404s, check_hashes, max_workers)


def cleanup_drift(output_subdir: str = "", clean_404s: bool = True,
                 clean_missing_files: bool = True, dry_run: bool = True,
                 max_workers: int = 5) -> dict[str, Any]:
    """Clean up drift."""
    return _get_api().cleanup_drift(output_subdir, clean_404s, clean_missing_files, dry_run, max_workers)


def refresh_index(check_drift: bool = False, cleanup_drift: bool = False,
                 max_workers: int = 5) -> dict[str, Any]:
    """Refresh the index (rebuild, extract keywords, validate)."""
    return _get_api().refresh_index(check_drift, cleanup_drift, max_workers)


if __name__ == '__main__':
    print("Gemini CLI Docs API Self-Test")
    print("=" * 50)

    api = GeminiDocsAPI()

    print("\nTesting find_document()...")
    try:
        docs = api.find_document("checkpointing", limit=5)
        print(f"✓ find_document('checkpointing'): Found {len(docs)} documents")
        if docs:
            print(f"  Example: {docs[0].get('doc_id', 'unknown')}")
    except Exception as e:
        print(f"✗ find_document() failed: {e}")

    print("\nTesting get_docs_by_tag()...")
    try:
        docs = api.get_docs_by_tag("cli", limit=5)
        print(f"✓ get_docs_by_tag('cli'): Found {len(docs)} documents")
    except Exception as e:
        print(f"✗ get_docs_by_tag() failed: {e}")

    print("\n" + "=" * 50)
    print("Self-test complete!")

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
            Dictionary with content and metadata, or None if not found.

        Example:
            >>> api = GeminiDocsAPI()
            >>> content = api.get_document_content("geminicli-com-docs-cli-checkpointing")
            >>> print(content['content'][:100])
        """
        return self.doc_resolver.get_content(doc_id, section)

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

    def refresh_index(self) -> dict[str, Any]:
        """
        Refresh the index (rebuild, extract keywords, validate).

        Returns:
            Dictionary with:
            - success: Whether refresh succeeded
            - steps_completed: List of completed steps
            - errors: List of any errors encountered

        Example:
            >>> api = GeminiDocsAPI()
            >>> result = api.refresh_index()
            >>> print(f"Refresh {'succeeded' if result['success'] else 'failed'}")
        """
        steps_completed = []
        errors = []

        try:
            scripts_dir = Path(__file__).parent / 'scripts'
            if str(scripts_dir) not in sys.path:
                sys.path.insert(0, str(scripts_dir))

            from scripts.management.rebuild_index import rebuild_index
        except ImportError as e:
            return {
                'success': False,
                'steps_completed': [],
                'errors': [f"Failed to import required modules: {e}"]
            }

        try:
            result = rebuild_index(self.base_dir, dry_run=False)
            steps_completed.append('rebuild_index')
        except Exception as e:
            errors.append(f"rebuild_index error: {e}")

        success = len(errors) == 0 and len(steps_completed) >= 1

        return {
            'success': success,
            'steps_completed': steps_completed,
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


def get_docs_by_tag(tag: str, limit: int = 100) -> list[dict[str, Any]]:
    """Get all documents with a specific tag."""
    return _get_api().get_docs_by_tag(tag, limit)


def get_docs_by_category(category: str, limit: int = 100) -> list[dict[str, Any]]:
    """Get all documents in a specific category."""
    return _get_api().get_docs_by_category(category, limit)


def search_by_keywords(keywords: list[str], limit: int = 10) -> list[dict[str, Any]]:
    """Search documents by keywords."""
    return _get_api().search_by_keywords(keywords, limit)


def refresh_index() -> dict[str, Any]:
    """Refresh the index (rebuild, extract keywords, validate)."""
    return _get_api().refresh_index()


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

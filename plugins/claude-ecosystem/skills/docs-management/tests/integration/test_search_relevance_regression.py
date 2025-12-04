"""
Search Relevance Regression Tests.

These tests verify the 7 core search queries from the 2025-11-25 audit
pass against the actual index. They are regression tests to prevent
future changes from degrading search quality.

Run with: pytest tests/integration/test_search_relevance_regression.py -v

Audit Reference: .claude/temp/2025-11-25_101500-docs-management-audit-summary.md

NOTE: These tests require actual scraped documentation in the canonical/
directory. They will be skipped if the index is empty (e.g., in a fresh
clone or CI without pre-scraped data).
"""

import sys
from pathlib import Path

import pytest
import yaml

# Ensure scripts directory is in path
SCRIPTS_DIR = Path(__file__).parent.parent.parent / 'scripts'
CANONICAL_DIR = Path(__file__).parent.parent.parent / 'canonical'

if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))


def _index_has_documents() -> bool:
    """Check if the canonical index has documents.

    The index.yaml uses a flat structure where each document ID is a top-level key,
    not nested under a 'documents' key. We check for any top-level keys that look
    like document entries (have 'path' or 'category' fields).
    """
    index_path = CANONICAL_DIR / 'index.yaml'
    if not index_path.exists():
        return False
    try:
        with open(index_path, 'r', encoding='utf-8') as f:
            index = yaml.safe_load(f)
        if not index:
            return False
        # Check for flat structure (doc_id: {metadata})
        # Each document entry has fields like 'path', 'category', 'keywords'
        for key, value in index.items():
            if isinstance(value, dict) and ('path' in value or 'category' in value):
                return True
        return False
    except Exception:
        return False


# Skip all tests in this module if index is empty
pytestmark = pytest.mark.skipif(
    not _index_has_documents(),
    reason="Search relevance tests require populated canonical index (run scrape first)"
)


class TestSearchRelevanceRegression:
    """
    Regression tests for the 7 audit search queries.

    These tests use the ACTUAL index to verify search quality
    is maintained after code changes.
    """

    @pytest.fixture(autouse=True)
    def setup_resolver(self):
        """Setup DocResolver with actual canonical index."""
        from core.doc_resolver import DocResolver
        self.resolver = DocResolver(str(CANONICAL_DIR))

    def test_skills_setup_query(self):
        """
        Query: "how to set up skills"
        Expected: code-claude-com-docs-en-skills at rank 1

        Verifies skills documentation is found for setup queries.
        """
        results = self.resolver.search_by_natural_language(
            "how to set up skills", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'how to set up skills'"
        assert doc_ids[0] == 'code-claude-com-docs-en-skills', \
            f"Expected skills doc at rank 1, got: {doc_ids[0]}"

    def test_hooks_configuration_query(self):
        """
        Query: "claude code hooks configuration"
        Expected: hooks or hooks-guide doc at rank 1

        Verifies hooks documentation is found for configuration queries.
        Both hooks (reference) and hooks-guide (getting started) are valid results.
        """
        results = self.resolver.search_by_natural_language(
            "claude code hooks configuration", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'claude code hooks configuration'"
        valid_hooks_docs = [
            'code-claude-com-docs-en-hooks',
            'code-claude-com-docs-en-hooks-guide'
        ]
        assert doc_ids[0] in valid_hooks_docs, \
            f"Expected hooks doc at rank 1, got: {doc_ids[0]}"

    def test_claude_md_query(self):
        """
        Query: "what is CLAUDE.md"
        Expected: code-claude-com-docs-en-memory at rank 1

        Verifies CLAUDE.md queries find the memory documentation.
        This was a critical fix in the 2025-11-25 audit:
        - Added 'is', 'it', 'be', 'do' to stop words
        - Changed min word length from 2 to 3 chars
        - Added CLAUDE.md to technical_phrases in filtering.yaml
        """
        results = self.resolver.search_by_natural_language(
            "what is CLAUDE.md", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'what is CLAUDE.md'"
        assert doc_ids[0] == 'code-claude-com-docs-en-memory', \
            f"Expected memory doc at rank 1, got: {doc_ids[0]}"

    def test_mcp_server_integration_query(self):
        """
        Query: "mcp server integration"
        Expected: code-claude-com-docs-en-mcp in top 3

        Verifies MCP documentation is found for integration queries.
        Note: May not be rank 1 due to other MCP-related docs.
        """
        results = self.resolver.search_by_natural_language(
            "mcp server integration", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'mcp server integration'"
        assert 'code-claude-com-docs-en-mcp' in doc_ids[:3], \
            f"Expected MCP doc in top 3, got: {doc_ids[:3]}"

    def test_progressive_disclosure_pattern_query(self):
        """
        Query: "progressive disclosure pattern"
        Expected: platform-claude-com-docs-en-agents-and-tools-agent-skills-best-practices at rank 1

        Verifies progressive disclosure queries find the best-practices doc,
        which has a dedicated section "### Progressive disclosure patterns".
        """
        results = self.resolver.search_by_natural_language(
            "progressive disclosure pattern", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'progressive disclosure pattern'"
        assert doc_ids[0] == 'platform-claude-com-docs-en-agents-and-tools-agent-skills-best-practices', \
            f"Expected best-practices doc at rank 1, got: {doc_ids[0]}"

    def test_extended_thinking_configuration_query(self):
        """
        Query: "extended thinking configuration"
        Expected: platform-claude-com-docs-en-build-with-claude-extended-thinking at rank 1

        Verifies extended thinking documentation is found.
        """
        results = self.resolver.search_by_natural_language(
            "extended thinking configuration", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'extended thinking configuration'"
        assert doc_ids[0] == 'platform-claude-com-docs-en-build-with-claude-extended-thinking', \
            f"Expected extended-thinking doc at rank 1, got: {doc_ids[0]}"

    def test_prompt_caching_setup_query(self):
        """
        Query: "prompt caching setup"
        Expected: platform-claude-com-docs-en-build-with-claude-prompt-caching at rank 1

        Verifies prompt caching documentation is found for setup queries.
        """
        results = self.resolver.search_by_natural_language(
            "prompt caching setup", limit=5
        )
        doc_ids = [doc_id for doc_id, _ in results]

        assert doc_ids, "No results for 'prompt caching setup'"
        assert doc_ids[0] == 'platform-claude-com-docs-en-build-with-claude-prompt-caching', \
            f"Expected prompt-caching doc at rank 1, got: {doc_ids[0]}"


class TestSearchRelevanceMetrics:
    """
    Aggregate metrics for search relevance.

    Provides summary statistics across all audit queries.
    """

    @pytest.fixture(autouse=True)
    def setup_resolver(self):
        """Setup DocResolver with actual canonical index."""
        from core.doc_resolver import DocResolver
        self.resolver = DocResolver(str(CANONICAL_DIR))

    def test_overall_search_relevance_above_threshold(self):
        """
        Verify overall search relevance meets 100% threshold.

        All 7 audit queries must pass for this test to succeed.
        This is a meta-test that documents the overall health of search.
        """
        # Format: (query, expected_docs (list or single doc_id), max_rank)
        queries_and_expectations = [
            ("how to set up skills", ["code-claude-com-docs-en-skills"], 1),
            ("claude code hooks configuration", ["code-claude-com-docs-en-hooks", "code-claude-com-docs-en-hooks-guide"], 1),
            ("what is CLAUDE.md", ["code-claude-com-docs-en-memory"], 1),
            ("mcp server integration", ["code-claude-com-docs-en-mcp"], 3),
            ("progressive disclosure pattern", ["platform-claude-com-docs-en-agents-and-tools-agent-skills-best-practices"], 1),
            ("extended thinking configuration", ["platform-claude-com-docs-en-build-with-claude-extended-thinking"], 1),
            ("prompt caching setup", ["platform-claude-com-docs-en-build-with-claude-prompt-caching"], 1),
        ]

        passed = 0
        failed = []

        for query, expected_docs, max_rank in queries_and_expectations:
            results = self.resolver.search_by_natural_language(query, limit=5)
            doc_ids = [doc_id for doc_id, _ in results]

            # Check if any of the expected docs is in the top max_rank results
            found = any(doc in doc_ids[:max_rank] for doc in expected_docs)
            if found:
                passed += 1
            else:
                # Find actual rank for each expected doc
                ranks = []
                for doc in expected_docs:
                    if doc in doc_ids:
                        ranks.append(f"{doc} at rank {doc_ids.index(doc) + 1}")
                    else:
                        ranks.append(f"{doc} not found")
                failed.append(f"  - '{query}': expected one of {expected_docs} in top {max_rank}, got: {', '.join(ranks)}")

        total = len(queries_and_expectations)
        relevance_pct = (passed / total) * 100

        # Build detailed failure message
        if failed:
            failure_details = "\n".join(failed)
            pytest.fail(
                f"Search relevance {relevance_pct:.1f}% ({passed}/{total}) is below 100% threshold.\n"
                f"Failed queries:\n{failure_details}"
            )

        # If we reach here, all tests passed
        assert relevance_pct == 100.0, f"Search relevance is {relevance_pct:.1f}%, expected 100%"

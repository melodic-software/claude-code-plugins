# Documentation Discovery Guide

## Table of Contents

- [Overview](#overview)
- [Discovery Methods](#discovery-methods)
- [Search Ranking](#search-ranking)
- [Query Patterns](#query-patterns)
- [API Usage](#api-usage)
- [Advanced Techniques](#advanced-techniques)

---

## Overview

Documentation discovery helps find relevant documents based on:

- **Keywords** - Terms extracted from document content
- **Tags** - Categorical labels assigned to documents
- **Natural language** - Fuzzy matching of user queries
- **doc_id** - Direct identifier-based lookup

---

## Discovery Methods

### Natural Language Search

Find documents using natural language queries:

```python
from gemini_docs_api import find_document

results = find_document("how to save and restore sessions")
for doc in results:
    print(f"{doc['title']} (score: {doc['score']:.2f})")
```

### Keyword Search

Search by specific keywords:

```python
from gemini_docs_api import search_by_keywords

results = search_by_keywords(["checkpointing", "session"])
```

### Tag-Based Discovery

Find documents by tag:

```python
from gemini_docs_api import get_docs_by_tag

docs = get_docs_by_tag("session-management")
```

### Direct Resolution

Resolve a known doc_id:

```python
from gemini_docs_api import resolve_doc_id

doc = resolve_doc_id("geminicli-com-docs-checkpointing")
```

---

## Search Ranking

### Scoring Factors

Documents are ranked by multiple factors:

| Factor | Weight | Description |
|--------|--------|-------------|
| Keyword match | High | Exact keyword matches |
| Title match | High | Query terms in title |
| Tag match | Medium | Query matches document tags |
| Domain boost | Configurable | geminicli.com boosted by default |
| Recency | Low | More recently fetched preferred |

### Score Calculation

```
score = (keyword_matches * 3.0)
      + (title_matches * 2.5)
      + (tag_matches * 1.5)
      + (domain_boost)
      - (age_penalty)
```

### Domain Weights

Configured in `config/defaults.yaml`:

```yaml
search:
  domain_weights:
    geminicli.com: 10.0
```

---

## Query Patterns

### Simple Queries

Single-topic queries:

```python
# Topic-based
find_document("installation")
find_document("authentication")

# Feature-based
find_document("sandbox")
find_document("checkpointing")
```

### Compound Queries

Multi-concept queries:

```python
# Multiple keywords
find_document("model routing configuration")

# Action-oriented
find_document("how to configure mcp servers")

# Problem-oriented
find_document("session timeout errors")
```

### Filtered Queries

With result limiting:

```python
# Limit results
results = find_document("tools", limit=5)

# With minimum score threshold
results = find_document("commands", min_score=0.5)
```

---

## API Usage

### find_document()

Natural language search:

```python
from gemini_docs_api import find_document

results = find_document(
    query="how to use custom tools",
    limit=10,
    min_score=None  # No threshold
)

for doc in results:
    print(f"{doc['doc_id']}: {doc['title']}")
    print(f"  Score: {doc['score']:.2f}")
    print(f"  URL: {doc['url']}")
```

### search_by_keywords()

Keyword-based search:

```python
from gemini_docs_api import search_by_keywords

results = search_by_keywords(
    keywords=["mcp", "integration"],
    match_all=False  # OR logic (default)
)

# With AND logic
results = search_by_keywords(
    keywords=["mcp", "configuration"],
    match_all=True  # Must match all keywords
)
```

### get_docs_by_tag()

Tag-based discovery:

```python
from gemini_docs_api import get_docs_by_tag

# Single tag
docs = get_docs_by_tag("cli")

# Tag exists in document
for doc in docs:
    print(f"{doc['doc_id']}: {doc['tags']}")
```

### resolve_doc_id()

Direct lookup:

```python
from gemini_docs_api import resolve_doc_id

doc = resolve_doc_id("geminicli-com-docs-tools")
if doc:
    print(f"Title: {doc['title']}")
    print(f"Content length: {len(doc['content'])} chars")
else:
    print("Document not found")
```

---

## Advanced Techniques

### Inverted Index

The skill maintains an inverted index for O(1) keyword lookups:

```
keyword -> [doc_id_1, doc_id_2, ...]
```

**Cache location:** `cache/inverted_index.json`

**Rebuild if stale:**

```bash
python scripts/maintenance/clear_cache.py --inverted
python scripts/management/manage_index.py refresh
```

### Fuzzy Matching

For typo-tolerant searches:

```python
results = find_document(
    query="checkpionting",  # Typo
    fuzzy=True
)
```

### Combining Methods

For comprehensive discovery:

```python
# Start with natural language
results = find_document("session management")

# Refine with tags
if not results:
    results = get_docs_by_tag("session-management")

# Fall back to keywords
if not results:
    results = search_by_keywords(["session", "save", "restore"])
```

### Context-Aware Discovery

Extract context from conversation:

```python
def discover_from_context(user_question: str) -> list:
    """Discover docs based on user question context."""

    # Extract likely keywords
    keywords = extract_keywords(user_question)

    # Search with extracted keywords
    results = find_document(user_question, limit=5)

    # Boost results matching extracted keywords
    for result in results:
        if any(kw in result['keywords'] for kw in keywords):
            result['score'] *= 1.2

    return sorted(results, key=lambda x: x['score'], reverse=True)
```

### Discovery Audit

Validate discovery quality:

```bash
# Run search audit
python scripts/validation/run_search_audit.py

# Analyze results
python scripts/validation/analyze_search_audit.py
```

---

## Troubleshooting

### No Results Found

1. Check index has documents: `python scripts/management/manage_index.py list --limit 5`
2. Try broader query terms
3. Check for typos in query
4. Verify keywords extracted correctly

### Poor Relevance

1. Run search audit to identify issues
2. Check keyword extraction for documents
3. Verify tag configuration
4. Consider adding manual keywords to documents

### Slow Search

1. Ensure inverted index cache exists
2. Clear and rebuild cache if corrupted
3. Check for very large index (consider pagination)

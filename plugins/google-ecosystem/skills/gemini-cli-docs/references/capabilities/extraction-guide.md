# Section Extraction Guide

## Table of Contents

- [Overview](#overview)
- [Extraction Methods](#extraction-methods)
- [Heading Matching](#heading-matching)
- [Content Boundaries](#content-boundaries)
- [API Usage](#api-usage)
- [Performance Considerations](#performance-considerations)
- [Troubleshooting](#troubleshooting)

---

## Overview

Section extraction allows retrieving specific portions of documentation without loading entire files. This is critical for:

- **Token efficiency** - Load only relevant content
- **Focused responses** - Answer specific questions without noise
- **Progressive disclosure** - Load details on-demand

---

## Extraction Methods

### By Heading

Extract content under a specific heading:

```python
from gemini_docs_api import get_document_section

section = get_document_section(
    doc_id="geminicli-com-docs-commands",
    heading="Built-in Commands"
)

if section:
    print(section["content"])
```

### By Heading Level

Extract all content at a specific heading level:

```python
# Get all H2 sections
sections = api.get_sections_by_level(
    doc_id="geminicli-com-docs-tools",
    level=2
)
```

### Full Document with Sections Listed

Get document with section table of contents:

```python
doc = api.resolve_doc_id("geminicli-com-docs-checkpointing")
print(doc["sections"])  # List of available sections
```

---

## Heading Matching

### Exact Match

Default behavior matches heading text exactly:

```python
# Matches "## Installation" exactly
section = get_document_section(doc_id, "Installation")
```

### Case-Insensitive Match

Heading matching is case-insensitive by default:

```python
# All match "## Getting Started"
get_document_section(doc_id, "Getting Started")
get_document_section(doc_id, "getting started")
get_document_section(doc_id, "GETTING STARTED")
```

### Partial Match

For partial matches, use fuzzy matching:

```python
section = get_document_section(
    doc_id,
    "Install",
    fuzzy=True  # Matches "Installation", "Installing", etc.
)
```

### Multiple Headings

When a heading appears multiple times:

```python
# Get first occurrence (default)
section = get_document_section(doc_id, "Examples")

# Get specific occurrence
section = get_document_section(doc_id, "Examples", occurrence=2)
```

---

## Content Boundaries

### Section Start

A section starts at the heading line:

```markdown
## Installation  <-- Section starts here

Content of the installation section...
```

### Section End

A section ends when:

1. **Same-level heading** - Another H2 if section started at H2
2. **Higher-level heading** - H1 ends any H2/H3/etc. section
3. **End of file** - If no terminating heading found

### Nested Sections

Nested headings are included in parent section:

```markdown
## Installation      <-- Parent section starts
### Prerequisites    <-- Included in Installation
### Steps            <-- Included in Installation
## Configuration     <-- Installation section ends here
```

To extract only the parent without children:

```python
section = get_document_section(
    doc_id,
    "Installation",
    include_children=False
)
```

---

## API Usage

### Basic Extraction

```python
from gemini_docs_api import get_document_section

# Simple extraction
section = get_document_section(
    doc_id="geminicli-com-docs-tools",
    heading="Tool Configuration"
)

if section:
    print(f"Found: {section['heading']}")
    print(f"Level: {section['level']}")
    print(f"Content: {section['content']}")
else:
    print("Section not found")
```

### With Error Handling

```python
from gemini_docs_api import GeminiDocsAPI

api = GeminiDocsAPI()

try:
    section = api.get_document_section(
        doc_id="geminicli-com-docs-commands",
        heading="Custom Commands"
    )
    if section is None:
        print("Section not found - check heading name")
except FileNotFoundError:
    print("Document not found - check doc_id")
except Exception as e:
    print(f"Error: {e}")
```

### List Available Sections

```python
# Get document metadata with section list
doc = api.resolve_doc_id("geminicli-com-docs-checkpointing")

print("Available sections:")
for section in doc.get("sections", []):
    print(f"  {section['level']}. {section['heading']}")
```

---

## Performance Considerations

### Token Savings

Section extraction provides significant token savings:

| Approach | Tokens | Use Case |
|----------|--------|----------|
| Full document | ~2000-5000 | Need complete context |
| Single section | ~200-800 | Answer specific question |
| Multiple sections | ~500-1500 | Related sub-topics |

**Example savings:**

- Full checkpointing doc: ~3000 tokens
- "Restoring Sessions" section: ~400 tokens
- **Savings: 87%**

### Caching

Extracted sections are not cached by default. For repeated access:

```python
# Cache the result yourself
_section_cache = {}

def get_cached_section(doc_id, heading):
    key = f"{doc_id}:{heading}"
    if key not in _section_cache:
        _section_cache[key] = get_document_section(doc_id, heading)
    return _section_cache[key]
```

### Batch Extraction

For multiple sections from same document:

```python
# Efficient: Load document once, extract multiple sections
doc = api.resolve_doc_id(doc_id)
content = doc["content"]

sections = []
for heading in ["Installation", "Configuration", "Usage"]:
    section = api._extract_section_from_content(content, heading)
    sections.append(section)
```

---

## Troubleshooting

### Section Not Found

**Symptom:** `get_document_section()` returns `None`

**Solutions:**

1. **List available sections:**

   ```python
   doc = api.resolve_doc_id(doc_id)
   print(doc.get("sections", []))
   ```

2. **Check heading spelling:**

   ```python
   # Wrong: "Getting started"
   # Right: "Getting Started"
   ```

3. **Check heading level:**

   ```python
   # Content might be H3 not H2
   # "### Subheading" vs "## Heading"
   ```

### Wrong Content Boundaries

**Symptom:** Section includes too much or too little content

**Solutions:**

1. **Check for duplicate headings:**

   ```python
   section = get_document_section(doc_id, heading, occurrence=1)
   ```

2. **Use include_children parameter:**

   ```python
   section = get_document_section(doc_id, heading, include_children=False)
   ```

### Encoding Issues

**Symptom:** Content has garbled characters

**Solutions:**

1. Verify source document is UTF-8
2. Re-scrape the document
3. Check for non-standard characters in heading

### Performance Issues

**Symptom:** Extraction is slow

**Solutions:**

1. Implement local caching
2. Use batch extraction for multiple sections
3. Consider loading full document if extracting many sections

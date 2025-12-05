# Scraping Guide

## Table of Contents

- [Overview](#overview)
- [llms.txt Format](#llmstxt-format)
- [Scraping Workflow](#scraping-workflow)
- [Filtering Options](#filtering-options)
- [Output Structure](#output-structure)
- [Content Processing](#content-processing)
- [Error Handling](#error-handling)
- [Best Practices](#best-practices)

---

## Overview

The gemini-cli-docs skill scrapes documentation from geminicli.com using the **llms.txt** format. This format provides a structured list of documentation URLs optimized for LLM consumption.

**Key characteristics:**

- Single source: `https://geminicli.com/llms.txt`
- Markdown link format: `[Title](URL)`
- Direct URL extraction via regex
- Flat or hierarchical output structure

---

## llms.txt Format

### Format Specification

The llms.txt file contains markdown-formatted links:

```markdown
# Gemini CLI Documentation

## Getting Started
- [Installation](https://geminicli.com/docs/installation)
- [Quick Start](https://geminicli.com/docs/quickstart)

## Core Features
- [Commands](https://geminicli.com/docs/commands)
- [Tools](https://geminicli.com/docs/tools)
```

### Parsing Pattern

URLs are extracted using the regex pattern:

```regex
\[([^\]]+)\]\(([^)]+)\)
```

This captures:

- Group 1: Link text (title)
- Group 2: URL

### Comparison with sitemap.xml

| Aspect | llms.txt | sitemap.xml |
|--------|----------|-------------|
| Format | Markdown links | XML structure |
| Parsing | Regex extraction | XML parser |
| Titles | Included in link text | Not included |
| Categories | Inferred from URL path | Sometimes explicit |
| File size | Smaller | Larger |

---

## Scraping Workflow

### Using the Slash Command

```bash
/google-ecosystem:scrape-docs
```

### Using the Script Directly

**Basic scrape (all docs):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt
```

**Filtered scrape (specific section):**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --filter "/docs/"
```

**Skip existing files:**

```bash
python plugins/google-ecosystem/skills/gemini-cli-docs/scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --skip-existing
```

### Workflow Steps

1. **Fetch llms.txt** - Download from geminicli.com
2. **Parse URLs** - Extract markdown links via regex
3. **Apply filters** - Filter URLs by path pattern
4. **Fetch content** - Download each URL's HTML
5. **Convert to Markdown** - Transform HTML to markdown
6. **Add frontmatter** - Insert YAML metadata
7. **Save files** - Write to canonical/ directory
8. **Update index** - Refresh index with new entries

---

## Filtering Options

### Path-Based Filtering

Filter URLs by path pattern:

```bash
# Only /docs/ section
--filter "/docs/"

# Only /guides/ section
--filter "/guides/"

# Multiple filters (OR logic)
--filter "/docs/,/guides/"
```

### Skip Existing

Don't re-download files that already exist:

```bash
--skip-existing
```

### Rate Limiting

Control request rate to avoid overloading server:

```bash
--delay 2.0  # 2 seconds between requests (default: 1.5)
```

---

## Output Structure

### Directory Layout

```
canonical/
  geminicli-com/
    docs/
      installation.md
      quickstart.md
      commands.md
      tools.md
      ...
    guides/
      getting-started.md
      ...
```

### File Naming

Files are named based on URL path:

```
https://geminicli.com/docs/installation
                           ↓
canonical/geminicli-com/docs/installation.md
```

### Frontmatter Structure

Each scraped file includes YAML frontmatter:

```yaml
---
title: "Installation"
url: https://geminicli.com/docs/installation
doc_id: geminicli-com-docs-installation
domain: geminicli.com
category: docs
last_fetched: 2025-01-15T10:30:00Z
content_hash: sha256:abc123...
---

# Installation

[Document content here...]
```

---

## Content Processing

### HTML to Markdown Conversion

The scraper uses `markdownify` for HTML to Markdown conversion:

- Preserves headings (H1-H6)
- Converts code blocks with language hints
- Handles tables
- Preserves links
- Strips navigation/footer elements

### Content Filtering

Configurable content filtering (see `config/filtering.yaml`):

- Remove navigation elements
- Strip table of contents
- Remove edit links
- Filter empty sections

### Code Block Handling

Code blocks are preserved with language hints:

```html
<pre><code class="language-python">print("hello")</code></pre>
```

Becomes:

````markdown
```python
print("hello")
```
````

---

## Error Handling

### Network Errors

**Timeout:**

- Retries up to 3 times with exponential backoff
- Logs error and continues with remaining URLs

**404 Not Found:**

- Logs warning (expected for some llms.txt entries)
- Continues processing remaining URLs

**Rate Limiting (429):**

- Pauses for extended period
- Retries after delay

### Content Errors

**Empty response:**

- Skips file, logs warning
- Does not create empty markdown file

**Malformed HTML:**

- BeautifulSoup handles gracefully
- May result in imperfect conversion

**Encoding issues:**

- Forces UTF-8 encoding
- Replaces invalid characters

---

## Best Practices

### Initial Scrape

For first-time setup:

```bash
# Scrape everything
python scripts/core/scrape_docs.py --llms-txt https://geminicli.com/llms.txt

# Refresh index
python scripts/management/manage_index.py refresh

# Validate
python scripts/validation/quick_validate.py
```

### Incremental Updates

For regular updates:

```bash
# Only fetch new/changed docs
python scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --skip-existing

# Or detect drift first
python scripts/maintenance/detect_changes.py --check-hashes

# Then re-scrape changed docs
python scripts/core/scrape_docs.py --llms-txt https://geminicli.com/llms.txt
```

### Git Bash on Windows

If using Git Bash, prevent path conversion:

```bash
MSYS_NO_PATHCONV=1 python scripts/core/scrape_docs.py \
    --llms-txt https://geminicli.com/llms.txt \
    --filter "/docs/"
```

### Verification After Scraping

Always verify after scraping:

```bash
# Quick validation
python scripts/validation/quick_validate.py --output geminicli-com

# Full validation
python scripts/validation/validate_scraped_docs.py
```

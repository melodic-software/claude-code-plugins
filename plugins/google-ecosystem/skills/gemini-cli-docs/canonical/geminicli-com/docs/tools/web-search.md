---
source_url: http://geminicli.com/docs/tools/web-search
source_type: llms-txt
content_hash: sha256:aad833f5327cdd3d776bee6f023736371203a06e9702406ee3827ec0f38e2c69
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"ec0f3e1b74b2b1bac96d1a92d7d4ceb629b26aa37c0ce9f12130d760fb3acf7b"'
last_modified: '2025-12-01T20:04:32Z'
---

# Web search tool (`google_web_search`)

This document describes the `google_web_search` tool.

## Description

Use `google_web_search` to perform a web search using Google Search via the
Gemini API. The `google_web_search` tool returns a summary of web results with
sources.

### Arguments

`google_web_search` takes one argument:

- `query` (string, required): The search query.

## How to use `google_web_search` with the Gemini CLI

The `google_web_search` tool sends a query to the Gemini API, which then
performs a web search. `google_web_search` will return a generated response
based on the search results, including citations and sources.

Usage:

```
google_web_search(query="Your query goes here.")
```

## `google_web_search` examples

Get information on a topic:

```
google_web_search(query="latest advancements in AI-powered code generation")
```

## Important notes

- **Response returned:** The `google_web_search` tool returns a processed
  summary, not a raw list of search results.
- **Citations:** The response includes citations to the sources used to generate
  the summary.

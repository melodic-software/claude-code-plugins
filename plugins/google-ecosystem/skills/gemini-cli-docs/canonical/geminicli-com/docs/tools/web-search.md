---
source_url: http://geminicli.com/docs/tools/web-search
source_type: llms-txt
content_hash: sha256:1de02d8c6f91f7c75d857b7d449bde200b4fc9f269e01d49e5e24f053bf9dd55
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"a0632c909de697316e9899b9d8b760b87521fcaea4b9d3b47e2b166f5fb5899b"'
last_modified: '2025-12-01T02:03:17Z'
---

# Web Search Tool (`google_web_search`)

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

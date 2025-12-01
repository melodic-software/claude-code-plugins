---
source_url: http://geminicli.com/docs/cli/token-caching
source_type: llms-txt
content_hash: sha256:f5ab05cebdb36f905848e4ba266716804d33461a0311510926b0de095f427a29
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"4737b47f7690c12da4b76418378e48a9b7f2e153de5f35435934d740bafc623f"'
last_modified: '2025-12-01T20:04:32Z'
---

# Token caching and cost optimization

Gemini CLI automatically optimizes API costs through token caching when using
API key authentication (Gemini API key or Vertex AI). This feature reuses
previous system instructions and context to reduce the number of tokens
processed in subsequent requests.

**Token caching is available for:**

- API key users (Gemini API key)
- Vertex AI users (with project and location setup)

**Token caching is not available for:**

- OAuth users (Google Personal/Enterprise accounts) - the Code Assist API does
  not support cached content creation at this time

You can view your token usage and cached token savings using the `/stats`
command. When cached tokens are available, they will be displayed in the stats
output.

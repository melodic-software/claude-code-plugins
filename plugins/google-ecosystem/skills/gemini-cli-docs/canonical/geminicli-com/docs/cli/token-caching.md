---
source_url: http://geminicli.com/docs/cli/token-caching
source_type: llms-txt
content_hash: sha256:53fb0073def6170e5019717489beccdd5f460b09eea1426cbe09ee0c6021ed6f
sitemap_url: https://geminicli.com/llms.txt
fetch_method: markdown
etag: '"03c500aeae1bdc961cbe81cb8eafc35c73d2a36d816bc068ec5464bcf28b39e7"'
last_modified: '2025-12-01T02:03:17Z'
---

# Token Caching and Cost Optimization

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

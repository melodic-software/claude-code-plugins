---
source_url: https://platform.claude.com/docs/en/api/beta/files/download
source_type: sitemap
content_hash: sha256:22a3c74baa0a938ff2ec1fa71c6f24f44ab6162b8d286e3bab5b17e5d4cc0513
sitemap_url: https://platform.claude.com/sitemap.xml
fetch_method: markdown
---

## Download

**get** `/v1/files/{file_id}/content`

Download File

### Path Parameters

- `file_id: string`

  ID of the File.

### Header Parameters

- `"anthropic-beta": optional array of AnthropicBeta`

  Optional header to specify the beta version(s) you want to use.

  - `UnionMember0 = string`

  - `UnionMember1 = "message-batches-2024-09-24" or "prompt-caching-2024-07-31" or "computer-use-2024-10-22" or 16 more`

    - `"message-batches-2024-09-24"`

    - `"prompt-caching-2024-07-31"`

    - `"computer-use-2024-10-22"`

    - `"computer-use-2025-01-24"`

    - `"pdfs-2024-09-25"`

    - `"token-counting-2024-11-01"`

    - `"token-efficient-tools-2025-02-19"`

    - `"output-128k-2025-02-19"`

    - `"files-api-2025-04-14"`

    - `"mcp-client-2025-04-04"`

    - `"mcp-client-2025-11-20"`

    - `"dev-full-thinking-2025-05-14"`

    - `"interleaved-thinking-2025-05-14"`

    - `"code-execution-2025-05-22"`

    - `"extended-cache-ttl-2025-04-11"`

    - `"context-1m-2025-08-07"`

    - `"context-management-2025-06-27"`

    - `"model-context-window-exceeded-2025-08-26"`

    - `"skills-2025-10-02"`

### Example

```http
curl https://api.anthropic.com/v1/files/$FILE_ID/content \
    -H "X-Api-Key: $ANTHROPIC_API_KEY"
```

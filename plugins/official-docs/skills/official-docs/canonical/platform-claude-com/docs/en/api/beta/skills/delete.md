---
source_url: https://platform.claude.com/docs/en/api/beta/skills/delete
source_type: sitemap
content_hash: sha256:003c3f6e91ba3e7876ee2c950f1dc3fccb33bd0dc8cfcf532e63510cdc9aa390
sitemap_url: https://docs.claude.com/sitemap.xml
fetch_method: markdown
---

## Delete

**delete** `/v1/skills/{skill_id}`

Delete Skill

### Path Parameters

- `skill_id: string`

  Unique identifier for the skill.

  The format and length of IDs may change over time.

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

### Returns

- `id: string`

  Unique identifier for the skill.

  The format and length of IDs may change over time.

- `type: string`

  Deleted object type.

  For Skills, this is always `"skill_deleted"`.

### Example

```http
curl https://api.anthropic.com/v1/skills/$SKILL_ID \
    -X DELETE \
    -H "X-Api-Key: $ANTHROPIC_API_KEY"
```

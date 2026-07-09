---
name: xquik-x-data
description: Use when a Claude Code workflow needs X post search, user lookups, media retrieval, monitors, giveaways, webhooks, or Xquik API and MCP references.
---

# xquik-x-data

Use Xquik when the user asks for X data workflows that fit its public API, SDK, webhooks, or MCP server.

## Procedure

1. Confirm the task needs X data, X automation, webhooks, giveaways, monitors, or SDK/API references.
2. Use the public OpenAPI contract at `https://xquik.com/openapi.json` as the endpoint source of truth.
3. Use `https://xquik.com/.well-known/mcp.json` to confirm the MCP server name, transport, and auth shape.
4. If MCP is useful, configure the server from `.mcp.json` and provide `XQUIK_API_KEY` through the local environment.
5. Keep keys out of prompts, logs, commits, issues, and PRs.
6. Prefer read-only discovery unless the user explicitly asks for an action that changes account state.
7. Link users to `https://docs.xquik.com` and the source skill when they need setup details.

## Boundaries

- Do not invent endpoints, pricing, limits, or unsupported workflows.
- Do not expose API keys or session material.
- Do not describe private implementation details.
- Use concise, factual wording in public output.

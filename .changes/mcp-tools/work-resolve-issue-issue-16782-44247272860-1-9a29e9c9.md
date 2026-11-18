---
bump: patch
---

### Changed

- `/mcp-tools:audit`'s checklist rows C6, C16 and C20 and its annotations note accept the SDK's own form and no longer list Zod, Python or .NET examples.
- The server-discovery page's "Server instructions" section tells the audit to find where the server is constructed; it no longer names each SDK's constructor or links SDK reference pages.

### Removed

- `/mcp-tools:audit-posture`'s P3 check drops the `postmark-mcp` worked case and its Postmark source record; the P3 rules are unchanged.

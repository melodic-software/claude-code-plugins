---
bump: patch
---

### Changed

- The README, `/mcp-tools:audit-posture` and the `/mcp-tools:audit` checklist and server-discovery
  reference no longer restate upstream behavior (whether the spec requires tool annotations, why a
  stdio server is outside the sandbox, what each MCP scope's file holds, how `npx` resolves a spec
  and whether npm republishes a version, each SDK's handling of server instructions and tool
  `_meta`, and which protocol message carries instructions). Each keeps its own rule and links the
  upstream section or SDK reference with an as-of date and a recheck trigger. The README's sandbox
  column note now defers to the posture checklist's "Sandbox coverage" record.

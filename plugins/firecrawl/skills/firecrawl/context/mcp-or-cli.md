# The Firecrawl MCP tools or this skill's CLI

Both reach the same Firecrawl API. Pick per call.

## Use the MCP tools (`mcp__firecrawl__*`) when

- the call is one page or one search, and the whole result is read into the conversation;
- the session has the Firecrawl MCP server connected.

## Use this skill's CLI when

- the job is a crawl, a map of a site, or a batch of scrapes;
- one result is likely to pass Claude Code's inline MCP output limit: read
  [MCP output limits and warnings](https://code.claude.com/docs/en/mcp#mcp-output-limits-and-warnings)
  for the current limit;
- the output should be kept on disk, read in parts, or compared across runs;
- the session has no Firecrawl MCP server.

The CLI writes to the `-o` path ("Core pattern" in [SKILL.md](../SKILL.md)), so only the parts that
are read enter the conversation.

## Running both

This plugin keeps the MCP server and the CLI installed together on purpose: each serves one of the
jobs above. Firecrawl's own position on running both is in
[Firecrawl skills for Claude Code](https://www.firecrawl.dev/blog/firecrawl-skills-claude-code-16-powers).
If the two conflict in a session, report it with the call that failed.

## Sources

- Firecrawl's guidance for Claude Code:
  [Claude Code integration](https://firecrawl.dev/integrations/claude-code).
- Anthropic's advice on CLI tools and MCP servers:
  [Reduce MCP server overhead](https://code.claude.com/docs/en/costs#reduce-mcp-server-overhead).
- A measured comparison of the two interfaces on long tasks:
  [MCP vs. CLI](https://labs.scale.com/blog/mcp-vs-cli).

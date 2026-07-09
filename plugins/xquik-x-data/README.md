# xquik-x-data

Claude Code plugin for Xquik X data workflows. It bundles a skill and optional MCP configuration that point at public Xquik docs, the live OpenAPI contract, and the MCP manifest.

## Components

- `skills/xquik-x-data/SKILL.md` - workflow guidance for Xquik API and MCP usage.
- `.mcp.json` - optional remote MCP server config that reads `XQUIK_API_KEY`.
- `.claude-plugin/plugin.json` - plugin metadata for the marketplace.

## Setup

1. Create or copy an Xquik API key.
2. Export it as `XQUIK_API_KEY` in the shell that starts Claude Code.
3. Install this plugin from the marketplace.
4. Use the `xquik-x-data` skill when a task needs X post search, user lookups, media retrieval, monitors, giveaways, webhooks, or SDK references.

## Source Links

- Docs: https://docs.xquik.com
- OpenAPI: https://xquik.com/openapi.json
- MCP manifest: https://xquik.com/.well-known/mcp.json
- Source skill: https://github.com/Xquik-dev/x-twitter-scraper/tree/master/skills/x-twitter-scraper
- npm package metadata: https://registry.npmjs.org/x-twitter-scraper/latest

## Security

Keep `XQUIK_API_KEY` in your local environment or approved secret store. Do not paste API keys into prompts, issues, logs, or repository files.

---
bump: patch
---

### Changed

- `/firecrawl:update`'s sync record moves to the current upstream `SKILL.md` (SHA256 `b4d49850`), with CLI 1.29.0, still npm latest. Re-audit of the upstream page: no change to `/firecrawl:firecrawl`. `parse -S`, `parse -Q`, `doctor <job-id>`, `monitor`, `developer` and the research index are already covered. The experimental `x download` is not added: `crawl` and `scrape` with `-o` already save pages to disk. Upstream's MCP-first install order, connectors, keyless tier, Alexandria, workflow and build skills, `init` flags, and the AgentID, WorkOS ID-JAG and Stripe Projects credential paths stay out, as at the last sync, since the wrapper uses the CLI with `FIRECRAWL_API_KEY` auth.

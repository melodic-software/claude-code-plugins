# Source categories — what to reach for, and what it is good for

Phase 1 launches ≥3 queries across ≥3 of these categories. The categories are stable; the tools that
serve them are not, which is the point of naming categories rather than tools.

## Discover your tools first — never assume a fixed set

Research tools vary by session: MCP servers connect and disconnect, CLIs come and go. Before
launching, take stock of what is actually available THIS session — the active and deferred tool list,
the MCP server-instruction blocks already injected into context, and the project's MCP registry. Map
the categories below onto whatever is there, and never hard-depend on one server: a docs-MCP server
absent means WebFetch the docs site directly, not a category skipped.

## The categories

| Source category | What it gives you | Reach for whatever's connected |
|---|---|---|
| **Official docs** | The authoritative primary for an ecosystem/library | the ecosystem's canonical docs site, fetched directly. If the consuming project ships a per-ecosystem source mapping (check its `CLAUDE.md`/rules), use it; else identify the canonical home yourself. When the topic centers on a specific library or site, probe its `llms.txt` / sitemap first to enumerate the doc set |
| **Upstream source + releases** | Ground truth + recency for a tool/library | the GitHub repo, releases, `CHANGELOG.md` — required for the recency gate |
| **Package registry** | Versions, dependencies, publish dates | the ecosystem's registry (NuGet / PyPI / npm / crates.io / Maven Central) |
| **Spec / standard** | Definitive behavior for a protocol/language | the RFC, language spec, or standard document |
| **AI-synthesis — DISCOVERY ONLY** | Fast breadth + citations to chase | a synthesis tool to FIND primaries and corroborators — never the terminal source for a claim. When it exposes a depth/quality knob, max it (accuracy over speed) |
| **Community corroborators** | Independent agreement / dissent | named-author blogs, top-voted Q&A, practitioner posts — corroborators, not primaries |

## Two standing preferences

- **Fetch the highest-value sources yourself, in whatever context this run occupies.** The run that
  judges a claim should be the run that read the source, rather than accepting another agent's
  summary of it. This holds identically inline and inside a dispatched run — what it argues against
  is sub-delegating a load-bearing fetch, not dispatch itself.
- **Vendor-tool topics need a vendor-current source.** When the topic is the AI coding tool itself,
  or any fast-moving vendor tool, prefer a dedicated documentation agent or skill if the environment
  provides one; general synthesis tools carry stale information for exactly these. Check the upstream
  issue tracker too, for known bugs in the version actually in use.

## Category diversity is the mechanism, not a quota

Three citations produced by three synthesis tools reading the same three blogs is **one** Tier-2
source, not three. The per-phase tool-type minimum and the cross-phase 4+ minimum exist because
consensus across *independent* retrieval paths is what makes agreement evidence; the same path run
three times only makes it louder.

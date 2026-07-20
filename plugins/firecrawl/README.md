# firecrawl

A Claude Code plugin that wraps the [`firecrawl-cli`](https://www.npmjs.com/package/firecrawl-cli)
binary as an agent skill for web scraping, search, crawling, URL discovery,
browser interaction, and local file parsing — with a core discipline: every
non-trivial result is written to disk with `-o <path>` and selectively `Read`
back, instead of streaming tens of thousands of tokens into the conversation.

Invoke it with `/firecrawl:firecrawl <command>` (scrape, search, crawl, map,
parse, interact, agent, monitor, and more), or let Claude reach for it when a
plain fetch is blocked by anti-bot protection or a page needs JS rendering.

## What it provides

- **Ten CLI subcommands** routed through one skill, with a decision table for
  when to escalate from a plain fetch to a managed scrape and when NOT to
  spend Firecrawl credits at all.
- **Write-to-disk pattern** — examples for scrape/search/interact all land in
  tempfiles the agent reads selectively; direct stdout is reserved for tiny
  results.
- **Reference tables** for every flag and configuration knob under `context/`.
- **A gated maintainer update skill** — `/firecrawl:update --check` reports CLI
  version drift and upstream skill-source drift read-only; the full update
  path puts `npm install` and any skill-content integration behind explicit
  approval gates, with a recorded rollback version in `UPSTREAM.md`. It lives
  as a sibling skill so the wrapper stays user-facing.

## Revisit condition

`parse` (local-file extraction) is one of the ten subcommands behind the single
`/firecrawl:firecrawl` skill — consolidation over per-subcommand proliferation.
Split it into a dedicated `parse` skill only if local-file extraction discovery
demonstrably fails under the general skill, or a non-credit extraction backend
appears worth its own surface.

## Requirements

- `firecrawl-cli` on PATH (`npm install -g firecrawl-cli`) — the skill flags
  this in its status line and the install is one command when first needed.
- A `FIRECRAWL_API_KEY` environment variable (OS user scope) from the
  [Firecrawl dashboard](https://firecrawl.dev). Prefer env-var auth over
  `firecrawl login`/`firecrawl config`, which write a second source of truth.

## Install

```shell
/plugin marketplace add melodic-software/claude-code-plugins
/plugin install firecrawl@melodic-software
```

Then verify prerequisites with `/firecrawl:setup check`.

## Configuration

This plugin has no `userConfig`. The CLI reads `FIRECRAWL_API_KEY`,
`FIRECRAWL_API_URL` (self-hosted override), and `FIRECRAWL_NO_TELEMETRY` from
the environment; everything else is per-call flags. Normal skill invocations
call the Firecrawl API through the CLI; the maintainer-facing update script
additionally reaches `registry.npmjs.org` and `www.firecrawl.dev`.

## License

MIT (SPDX-License-Identifier: MIT).

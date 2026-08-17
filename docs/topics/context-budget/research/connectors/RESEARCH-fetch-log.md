---
topic: claude-ai-connectors-in-claude-code
section: fetch-log
abstract: The written per-claim fetch record with artifact-ladder rungs and outcomes, plus the recency-gate verdict against Claude Code 2.1.233.
claims:
  - claim: "The recency gate is satisfied: latest published Claude Code release is 2.1.233 (2026-08-14); the binary read this turn is 2.1.232, one patch behind with no major bump."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/changelog"
        tier: 1
        pool: "Anthropic — code.claude.com docs (changelog)"
      - url: "local: node_modules/@anthropic-ai/claude-code/package.json + claude --version"
        tier: 0
        pool: "Direct tool output — installed package this turn"
produced_by: all-phases
---

# Fetch log

All fetches performed 2026-08-17. Ladder rungs per the discipline file: 1 = deepest technical
artifact (here, the shipped implementation), 2 = platform/API reference, 3 = product docs,
4 = changelog/release notes, 5 = announcement, 6 = third-party.

## Q1 — connector vs `.mcp.json` MCP server

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Connector is an MCP server | `strings node_modules/@anthropic-ai/claude-code/bin/claude.exe` (v2.1.232) | 1 | Bash/strings | carries the claim (`mcp__claude_ai_<connector>__`, `claudeai-proxy`) |
| Connector is an MCP server | `https://code.claude.com/docs/en/glossary.md` | 3 | curl | carries the claim |
| Connector is an MCP server | `https://code.claude.com/docs/en/desktop.md` | 3 | curl | carries the claim |
| Connector is an MCP server | `https://code.claude.com/docs/en/mcp.md` | 3 | curl + WebFetch | carries the claim (scope hierarchy) |
| Connector is an MCP server | `https://claude.com/docs/connectors` | 2 | curl, WebFetch | unreachable after escalation (403; then EGRESS_BLOCKED) |
| Connector is an MCP server | `https://support.claude.com/en/articles/11175166-...` | 3 | WebFetch | unreachable after escalation (EGRESS_BLOCKED) |
| Connector is an MCP server | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current |
| Connector is an MCP server | `github.com/anthropics/claude-code` issue search | 6 | GitHub MCP | carries the claim (#84301 `mcp__claude_ai_*`) |

## Q2 — how the tool surface reaches the model

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| Deferred by default | `https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md` | 2 | curl | carries the claim (prefix exclusion, `tool_reference`) |
| Deferred by default | `https://code.claude.com/docs/en/mcp.md` | 3 | curl | carries the claim |
| Deferred by default | `https://code.claude.com/docs/en/costs` | 3 | WebFetch | carries the claim |
| Deferred by default | `https://code.claude.com/docs/en/agent-sdk/tool-search` | 3 | WebFetch | carries the claim (5-value table) |
| Deferred by default | `https://code.claude.com/docs/en/env-vars.md` | 3 | curl | carries the claim (raw row) |
| Deferred by default | `https://www.anthropic.com/engineering/advanced-tool-use` | 5 | WebFetch | unreachable after escalation (EGRESS_BLOCKED) |
| Deferred by default | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current (v2.1.222 and v2.1.221 entries both concern deferral) |
| `alwaysLoad` exemption | `https://code.claude.com/docs/en/mcp.md` | 3 | curl | carries the claim |

## Q3 — `/context` attribution

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| `MCP tools` row, no connectors row | `strings …/claude.exe` offsets ~588427, ~623489, ~577380 | 1 | Bash/strings | carries the claim |
| `MCP tools` row | `https://code.claude.com/docs/en/context-window` | 3 | WebFetch | carries the claim (label `MCP tools (deferred)`) |
| `/context all` breakdown | `https://code.claude.com/docs/en/commands.md` | 3 | curl | fetched and searched, carries the command but not the row names |
| per-server usage attribution | `https://code.claude.com/docs/en/costs` | 3 | WebFetch | carries the claim |
| `MCP tools` row | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current (v2.1.216, v2.1.212 `/context` fixes reviewed) |

## Q4 — disable / scope mechanisms

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| `disableClaudeAiConnectors` | `https://code.claude.com/docs/en/settings.md` | 3 | curl | carries the claim (raw key row + precedence-exception table) |
| `disableClaudeAiConnectors` | `https://code.claude.com/docs/en/mcp.md` | 3 | curl | carries the claim (any-source-true, web carve-out) |
| `disableClaudeAiConnectors` | `strings …/claude.exe` (v2.1.232) | 1 | Bash/strings | fetched and searched, does not carry the claim (string absent from this build's readable strings) |
| `ENABLE_CLAUDEAI_MCP_SERVERS` | `https://code.claude.com/docs/en/env-vars.md` | 3 | curl | carries the claim |
| `disabledMcpServers` toggle | `https://code.claude.com/docs/en/mcp.md` | 3 | curl | carries the claim |
| `deniedMcpServers` / `allowedMcpServers` / `allowAllClaudeAiMcps` / `managed-mcp.json` | `https://code.claude.com/docs/en/managed-mcp` | 3 | WebFetch | carries the claim |
| `enabledMcpjsonServers` etc. are unrelated | `https://code.claude.com/docs/en/settings.md`, `mcp.md` | 3 | curl | carries the claim |
| all Q4 keys | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current; v2.1.182 / v2.1.149 / v2.1.219 version floors noted in-page |
| all Q4 keys | `https://code.claude.com/docs/en/server-managed-settings.md` | 3 | curl | fetched and searched, does not carry the claim (0 connector hits) |

## Q5 — reversibility

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| `/mcp` toggle is in-session | `https://code.claude.com/docs/en/mcp.md` | 3 | curl | carries the claim |
| `/mcp` toggle is in-session | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current (v2.1.221 mid-connect disable fix) |
| settings reload live | `https://code.claude.com/docs/en/settings.md` | 3 | curl | carries the claim (restart-only list = `model`, `outputStyle`) |
| MCP config needs restart | `https://code.claude.com/docs/en/prompt-caching.md` | 3 | curl | carries the claim |
| `disableClaudeAiConnectors` mid-session | `mcp.md`, `settings.md`, `prompt-caching.md` | 3 | curl | **unresolved** — fetched and searched; no page addresses this key's timing. Gap row in `RESEARCH-gaps-and-unverified.md` §3 |
| community signal | `github.com/anthropics/claude-code` issues #73682, #83285, #79564, #84301 | 6 | GitHub MCP | carries the claim (contested ergonomics; partly stale) |

## Q6 — prompt-cache invalidation

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| deferred = cache-safe | `https://code.claude.com/docs/en/prompt-caching.md` | 3 | curl | carries the claim |
| deferred = cache-safe | `https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool.md` | 2 | curl | carries the claim (prefix untouched) |
| deferred = cache-safe | `https://www.anthropic.com/engineering/advanced-tool-use` | 5 | WebFetch | unreachable after escalation (EGRESS_BLOCKED) |
| deferred = cache-safe | `https://code.claude.com/docs/en/changelog` | 4 | WebFetch | 2.1.233 (2026-08-14) — current |
| `mcp__*` deny rule cache-neutral | `https://code.claude.com/docs/en/prompt-caching.md` | 3 | curl | carries the claim for `mcp__*`; **unresolved** for `mcp__claude_ai_*` specifically |

## Recency gate

| Item | Value |
|---|---|
| Latest published release | **2.1.233**, 2026-08-14 (`https://code.claude.com/docs/en/changelog`, fetched 2026-08-17) |
| Version read this turn | **2.1.232** (`node_modules/@anthropic-ai/claude-code/package.json`; `claude --version` → `2.1.232 (Claude Code)`) |
| Gap | One patch release. No major or minor bump. |
| Verdict | **current** — no claim in this artifact is invalidated by 2.1.233, whose only connector-related entry is a `/login`-hint fix for falsely-flagged authorization state |

**One stale-source trap avoided and recorded:** a second Claude Code install exists on this machine
at `/opt/node22/lib/node_modules/@anthropic-ai/claude-code` at **v2.1.42**. Its bundle contains zero
occurrences of `disableClaudeAiConnectors` and `allowAllClaudeAiMcps` — consistent with those keys
landing in v2.1.182 and v2.1.149. **All Tier-0 binary evidence in this artifact is from the v2.1.232
build**, not that one. A skill inspecting a user's install must resolve which binary is actually on
`PATH` before drawing conclusions from it.

## Corpus enumeration surface

`https://code.claude.com/sitemap.xml`, fetched 2026-08-17 via curl (262,044 bytes) — 187 distinct
`/docs/en/` pages. This is the exhaustive surface backing `research-checklist.md`.

## Falsification query (Phase 2, mandatory)

**Leading hypothesis targeted:** "Connectors are the same mechanism as `.mcp.json` MCP servers,
differing only in configuration source."

**Query run:** WebSearch — `Claude Code connectors NOT the same as MCP servers difference distinct
mechanism limitation` (2026-08-17). Deliberate attempt to surface a documented behavior where a
connector is *not* treated as an MCP server.

**Result: the hypothesis survived.** The query returned no first-party contradiction. The strongest
counter-shaped source, a Tier-2 practitioner post, in fact corroborates the hypothesis while
sharpening it: "All Claude Apps are Connectors. All Connectors are MCP Servers. But not all MCP
Servers are Connectors" — i.e. a strict subset relation, not a separate mechanism.

**Partial falsification retained, and it changed the answer.** The search did surface that connectors
are a *managed* layer (Anthropic handles OAuth, hosting, discovery), which the first-party docs
confirm in mechanism-level terms: connectors carry the distinct internal transport type
`claudeai-proxy`, dedupe by endpoint rather than name, are gated on the active authentication method,
and are provisioned differently in cloud sessions. `RESEARCH-connector-identity.md` therefore states
"same mechanism, different configuration source **and a distinct internal transport type**" rather
than the flat "same mechanism" the Phase 1 hypothesis proposed.

**Sources:** <https://www.channel.tel/blog/claude-extension-stack-part-3-mcp-connectors-apps> (Tier 2,
independent pool), <https://buildtolaunch.substack.com/p/what-are-mcp-apps-connectors-plugins>
(Tier 2, independent pool), both surfaced 2026-08-17 and used as corroborators only, never as
terminal sources.

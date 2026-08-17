---
topic: claude-ai-connectors-in-claude-code
section: gaps-and-unverified
abstract: Eight things this run could NOT verify, each naming the sources checked and the sources left unchecked, plus one near-miss where a summarizer inverted a documented semantic.
claims:
  - claim: "The claude.ai-side publisher surface for the connector concept is unreachable from this environment, so the connector definitions used here come only from code.claude.com."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "https://support.claude.com/en/articles/11175166-get-started-with-custom-connectors-using-remote-mcp"
        tier: 0
        pool: "Direct tool output — WebFetch EGRESS_BLOCKED this turn"
      - url: "https://claude.com/docs/connectors"
        tier: 0
        pool: "Direct tool output — curl HTTP 403 and WebFetch EGRESS_BLOCKED this turn"
  - claim: "Whether a claude.ai connector can carry alwaysLoad is undocumented on every page reached."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page, checked)"
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page, checked)"
produced_by: phase-4
---

# What this run could NOT verify

Each item names the sources checked **and** the sources left unchecked, so the skill's author can
close any of them in one step. None of these is filled in from training recall.

## 1. The claude.ai-side definition of "connector" — UNREACHABLE, not absent

`code.claude.com` repeatedly links the connector concept out to claude.ai-side pages. **Every one of
those hosts is blocked by this environment's egress proxy**, so the definitions in
`RESEARCH-connector-identity.md` rest on `code.claude.com` alone.

- Checked and blocked: `support.claude.com` (WebFetch `EGRESS_BLOCKED`), `claude.com/docs/connectors`
  (curl HTTP 403, WebFetch `EGRESS_BLOCKED`), `www.anthropic.com` (WebFetch `EGRESS_BLOCKED`).
- Checked and 404: `docs.claude.com/en/docs/connectors` — a guessed URL, so its 404 is silence, not
  evidence of absence.
- **Left unchecked:** `claude.ai/directory`, `claude.com/docs/connectors/building`,
  `claude.com/docs/connectors/building/review-criteria`, and the claude.ai admin console — all named
  by the Claude Code docs but unreachable here.

This does not weaken Q1's answer — the glossary and desktop pages are first-party and explicit — but
it means **no independent-publisher corroboration of the connector definition was obtained.**

## 2. Whether `alwaysLoad` can apply to a claude.ai connector

`alwaysLoad` is documented only as a `.mcp.json` / server-configuration field, and a connector has no
local config file the user edits. Whether the fetched connector definition can carry it, or whether
an admin can set it claude.ai-side, is not stated.

- Checked: `mcp.md` (full page), `settings.md` (full key table), `managed-mcp`, `plugins-reference`
  (0 connector hits).
- **Left unchecked:** the claude.ai admin console UI, `claude.com/docs/connectors/building`.

This matters because `alwaysLoad` is the single setting that would make a connector unconditionally
context-expensive. **The skill should not claim connectors can or cannot be `alwaysLoad`.**

## 3. Whether `disableClaudeAiConnectors` applies mid-session

Covered in full in `RESEARCH-reversibility.md`. Two first-party pages point opposite ways and neither
addresses the key directly. Checked: `settings.md` restart-only list (does not include it),
`mcp.md` (zero occurrences of "restart"), `prompt-caching.md` (says MCP config changes need a
restart). **Left unchecked:** empirical test — I did not restart a session or mutate real settings,
since that is outside this run's write boundary.

## 4. Real token cost of a connector

**No first-party page publishes a per-connector or per-MCP-tool token figure.** The 120-token figure
on the `context-window` page is explicitly illustrative — that page states "The visualization uses
representative numbers." The only real numbers found are generic: "50 tools can use 10-20K tokens"
(`agent-sdk/tool-search`), and a Tier-2 search summary citing 191,300 vs 122,800 tokens preserved in
an Anthropic engineering post I could not fetch (egress-blocked).

- Checked: `context-window`, `costs`, `agent-sdk/tool-search`, `platform.claude.com` tool-search-tool,
  `prompt-caching`.
- **Left unchecked:** `www.anthropic.com/engineering/advanced-tool-use` (blocked); an actual
  `/context` run in a session with connectors attached.

**The skill must measure rather than quote.** `/context all`'s `### MCP Tools | Tool | Server |
Tokens` table is the correct measurement surface.

## 5. Whether an `mcp__claude_ai_*` deny rule behaves as expected

`prompt-caching.md` documents that an `"mcp__*"`-shaped deny glob removes MCP tools cache-neutrally
when deferred. Whether the narrower `mcp__claude_ai_*` glob matches connector tools specifically is
inferred from the documented normalized naming, **not stated anywhere**.

- Checked: `prompt-caching.md`, `permissions` (via the prompt-caching cross-references), `mcp.md`.
- **Left unchecked:** `permissions` page in full; empirical test.

Flagged because `RESEARCH-prompt-cache.md` presents this as the skill's cheapest primitive — it is
the most attractive and least verified finding in this run.

## 6. Whether the `/mcp` per-project toggle works in cloud/web sessions

The docs state `disableClaudeAiConnectors` and `deniedMcpServers` URL patterns are inert in Claude
Code on the web. They do **not** say whether the `/mcp` toggle still works there.

- Checked: `mcp.md` (the web carve-out note), `claude-code-on-the-web.md` (0 connector hits),
  `managed-mcp`.
- **Left unchecked:** an actual web session.

## 7. Whether a `/connectors` slash command exists

**It almost certainly does not, but my strongest test was invalid and I am reporting that.** I
grepped the shipped v2.1.232 binary for a bare `/connectors` string and found none — but the same
grep also found no `/mcp` and no `/context`, both of which demonstrably exist. **The grep therefore
proves nothing.**

What is positive evidence: the `commands` page's command table lists `/context [all]` and `/mcp` and
contains no `/connectors` entry; `interactive-mode.md` has zero occurrences of "connector"; and every
connector-management instruction in the docs routes to `/mcp` or to claude.ai settings.

- Checked: `commands.md`, `interactive-mode.md`, `mcp.md`, `mcp-quickstart.md`, the v2.1.232 binary.
- **Left unchecked:** typing `/` in a live session to enumerate the real command list.

**Conclusion: `/mcp` is the connector slash command. Treat `/connectors` as nonexistent in the CLI**
— note the *desktop app* does have a Connectors UI and a Settings → Connectors screen, which is a
different surface and may be the source of the confusion.

## 8. Independence of corroboration is genuinely limited

Stated plainly because a verifier will grade it: **almost every accepted claim here is sourced to
Anthropic.** The distinct evidence kinds obtained were (a) `code.claude.com` documentation pages,
(b) `platform.claude.com` API documentation, (c) the shipped v2.1.232 binary as an implementation
artifact, and (d) community GitHub issues. (a), (b) and (c) share one publisher pool even though they
are different artifact classes; only (d) is independent, and it is Tier 2 and partly stale.

For claims about a closed-source vendor tool's internals this is close to the ceiling — the binary is
the implementation, and it agrees with the docs. But the skill's author should know that
"independently corroborated" here mostly means "documentation and implementation agree," not
"two organizations agree."

## A near-miss worth recording — summarizer-induced false conflict

Phase 1 surfaced what looked like a hard contradiction: `/docs/en/mcp` said to set
`ENABLE_CLAUDEAI_MCP_SERVERS` to `false` to disable connectors, while a WebFetch of `/docs/en/env-vars`
reported the variable was **presence-only** — "any non-empty value turns the behavior on" — which
would mean `=false` *enables* connectors. That would have been a serious, publishable trap.

Fetching the **raw markdown** of the same page (`env-vars.md`, via curl) showed the real row:

> `ENABLE_CLAUDEAI_MCP_SERVERS` — Set to `false` to disable claude.ai MCP servers in Claude Code.
> Enabled by default for logged-in users.

The two pages agree. **The contradiction was manufactured by the summarizing fetcher.** The same
fetcher also flattened `ENABLE_TOOL_SEARCH`'s five-value contract into a two-value `true`/`false`
one.

**Methodological note for the skill's author:** when a claim turns on an exact key spelling or an
exact accepted value, fetch `<page>.md` raw rather than trusting a summarized fetch. Every key
spelling in `RESEARCH-disable-and-scope.md` was taken from raw markdown for this reason.

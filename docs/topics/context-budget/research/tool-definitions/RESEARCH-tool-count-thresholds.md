---
topic: tool-definitions-prefix-pruning
section: tool-count-thresholds
abstract: "Anthropic publishes explicit thresholds: tool-selection accuracy degrades beyond 30-50 loaded tools, tool search is advised past ~10-20 tools or 10k definition tokens, and 50 tools cost 10-20K tokens."
claims:
  - claim: "Anthropic states tool selection accuracy degrades with more than 30-50 tools loaded at once."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#when-to-use-tool-search"
        tier: 1
        pool: "Anthropic / platform.claude.com"
  - claim: "Anthropic gives concrete adoption thresholds for tool search: 10+ tools available, definitions over 10k tokens, or 200+ tools when aggregating MCP servers."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#when-to-use-tool-search"
        tier: 1
        pool: "Anthropic / platform.claude.com"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/manage-tool-context"
        tier: 1
        pool: "Anthropic / platform.claude.com"
  - claim: "Anthropic quantifies definition cost as '50 tools can use 10-20K tokens' and a five-server MCP setup at ~55k tokens, with tool search cutting that by over 85 percent."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool"
        tier: 1
        pool: "Anthropic / platform.claude.com"
  - claim: "Anthropic recommends keeping the 3-5 most frequently used tools non-deferred."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#deferred-tool-loading"
        tier: 1
        pool: "Anthropic / platform.claude.com"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search"
        tier: 1
        pool: "Anthropic / code.claude.com"
produced_by: phase-1-3
---

# Official guidance on tool-count thresholds and selection accuracy

Yes — this is documented explicitly, on two independent first-party pages, with numbers.

## The accuracy claim

`https://code.claude.com/docs/en/agent-sdk/tool-search` (fetched 2026-08-17), opening section:

> This approach solves two challenges as tool libraries scale:
>
> - **Context efficiency:** Tool definitions can consume large portions of the context window
>   (**50 tools can use 10-20K tokens**), leaving less room for actual work.
> - **Tool selection accuracy: Tool selection accuracy degrades with more than 30-50 tools loaded at
>   once.**

That is the direct answer to the question as asked, in Anthropic's own words, on the Claude Code
documentation host.

## The adoption thresholds

`https://platform.claude.com/docs/en/agents-and-tools/tool-use/tool-search-tool#when-to-use-tool-search`
(fetched 2026-08-17):

> Use tool search when any of the following apply:
>
> - **You have 10 or more tools available.**
> - **Your tool definitions consume more than 10k tokens.**
> - **Tool selection accuracy drops as your toolset grows.**
> - **You aggregate multiple MCP servers (200+ tools).**
> - Your tool library grows over time.
>
> Standard tool calling, without tool search, is a better fit when you have **fewer than 10 tools**,
> every tool is used in every request, or your tool definitions are small (**less than 100 tokens
> total**).

Corroborated with a slightly different number on a second platform page,
`https://platform.claude.com/docs/en/agents-and-tools/tool-use/manage-tool-context` (fetched
2026-08-17), which frames tool search as fitting "Large toolsets (**20+ tools**) where most tools
aren't needed every turn" and advises:

> Add tool search once your toolset grows past **roughly 20 tools** or your baseline context usage
> becomes noticeable.

**Minor conflict, resolved:** 10+ (tool-search-tool) vs ~20 (manage-tool-context) vs the 30-50
accuracy knee (Claude Code tool-search page). These are three different questions — when tool search
starts paying off, a comfortable rule of thumb, and where accuracy measurably degrades — not
contradictory measurements. The Claude Code SDK page reconciles the low end itself: "With fewer than
~10 tools whose definitions fit comfortably in the context window, loading everything upfront is
typically faster." **For a skill's thresholds, the defensible reading is: under 10, don't bother;
10-20, worth it if definitions are large; 30-50+, accuracy is at stake, not just tokens.**

## The cost baselines to calibrate against

| Figure | Source | Fetched |
|---|---|---|
| "50 tools can use 10-20K tokens" | Claude Code tool-search page | 2026-08-17 |
| "A typical multiserver setup (GitHub, Slack, Sentry, Grafana, and Splunk) can consume ~55k tokens in definitions before Claude does any work" | `tool-search-tool` | 2026-08-17 |
| "Tool search typically reduces this by over 85 percent, loading only the 3-5 tools Claude needs for a given request" | `tool-search-tool` | 2026-08-17 |
| Tool-use system prompt overhead, 286-804 tokens depending on model and `tool_choice` | `tool-use/overview#pricing` | 2026-08-17 |

This session measured 18.1k for `System tools` plus 17.8k for `System tools (deferred)` across ~26
prefix tools and 77 deferred ones — the same order of magnitude as the published figures, which is a
useful sanity check that `/context`'s estimates are not wildly off.

## The design rule Anthropic repeats

Stated twice, in near-identical words, on both hosts:

> **Keep your 3-5 most frequently used tools non-deferred** so Claude can call them without searching
> first. (`tool-search-tool`)

> Up to five of the most relevant tools are loaded into context by default. (Claude Code tool-search
> page)

Plus the discovery-quality guidance, which is the part a trimming skill should surface alongside any
"defer this" recommendation, because deferral is only free if the tool can still be found:

> The search mechanism matches queries against tool names and descriptions. Names like
> `search_slack_messages` surface for a wider range of requests than `query_slack`. Descriptions with
> specific keywords… match more queries than generic ones.

> Use consistent namespacing in tool names: prefix by service or resource (for example, `github_`,
> `slack_`) so one search matches the whole group.

> Add a system prompt section describing available tool categories.

## Limits worth recording

From the same two pages (fetched 2026-08-17):

- Maximum catalog: **10,000 tools**.
- Search returns up to **5** tools per search by default; Claude may set a `limit` from 1 to 10,000.
- Regex patterns max 200 characters; BM25 queries max 500 characters.

## Recency

Verified against the upstream changelog this turn: latest release **2.1.233**
(`https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md`, fetched 2026-08-17);
local binary 2.1.232. No major-version bump; no changelog entry since 2.1.121 alters the threshold
guidance. **Verdict: current.**

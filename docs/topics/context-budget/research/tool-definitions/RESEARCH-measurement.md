---
topic: tool-definitions-prefix-pruning
section: measurement
abstract: "/context reports category-level buckets including a separate System tools (deferred) line and works headlessly under claude -p; per-tool attribution is not offered, and the count_tokens API accepts a tools array so a skill can price one definition at a time."
claims:
  - claim: "/context reports a live breakdown by category with a per-item expansion via '/context all'; it does NOT offer per-tool token attribution."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/commands#all-commands"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "https://code.claude.com/docs/en/context-window#check-your-own-session"
        tier: 1
        pool: "Anthropic / code.claude.com"
      - url: "claude -p \"/context\" --output-format json, Claude Code 2.1.232, run 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
  - claim: "claude -p \"/context\" DOES work headlessly and returns the full markdown breakdown in the result field of --output-format json."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "claude -p \"/context\" --output-format json, Claude Code 2.1.232, run 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
      - url: "https://code.claude.com/docs/en/headless"
        tier: 1
        pool: "Anthropic / code.claude.com"
  - claim: "/context separates 'System tools' from 'System tools (deferred)', so deferred definitions are attributed a non-zero local token cost."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "claude -p \"/context\" --output-format json, Claude Code 2.1.232, run 2026-08-17"
        tier: 0
        pool: "direct tool output (this session)"
  - claim: "The /v1/messages/count_tokens endpoint accepts the same tools array as Messages and returns total input tokens, making per-definition pricing possible."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/build-with-claude/token-counting"
        tier: 1
        pool: "Anthropic / platform.claude.com"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview#pricing"
        tier: 1
        pool: "Anthropic / platform.claude.com"
  - claim: "Anthropic publishes no characters-per-token estimation rule; it instructs recounting against the target model because Claude 4.7+ uses a newer tokenizer producing ~30% more tokens."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://platform.claude.com/docs/en/build-with-claude/token-counting"
        tier: 1
        pool: "Anthropic / platform.claude.com"
      - url: "grep for characters-per-token guidance across 21 first-party pages, 2026-08-17"
        tier: 0
        pool: "Anthropic docs corpus (parsed locally)"
produced_by: phase-2-3
---

# How to actually measure per-tool token cost

## 1. `/context` — what it reports, and at what granularity

**Official description.** `https://code.claude.com/docs/en/commands#all-commands` (fetched
2026-08-17), the `/context [all]` row:

> Visualize current context usage as a colored grid. Shows optimization suggestions for
> context-heavy tools, memory bloat, and capacity warnings. When the conversation exceeds the context
> window, the output includes a warning showing how far over the limit you are and which command
> frees space. **In fullscreen mode, `/context` collapses the per-item breakdown to keep the grid
> visible. Pass `all` to expand it.**

And `https://code.claude.com/docs/en/context-window#check-your-own-session` (fetched 2026-08-17):

> To see your actual context usage at any point, run `/context` for **a live breakdown by category**
> with optimization suggestions, including which CLAUDE.md and auto memory files loaded.

So: **category granularity, with a per-item breakdown for the itemized categories.**

**Actual output, Tier 0** (Claude Code 2.1.232, `claude-sonnet-5`, 2026-08-17). The header is
literally "Estimated usage by category":

```
| Category                 | Tokens | Percentage |
| System prompt            | 5.1k   | 0.5%  |
| System tools             | 18.1k  | 1.9%  |
| System tools (deferred)  | 17.8k  | 1.8%  |
| Custom agents            | 1.5k   | 0.2%  |
| Skills                   | 9.9k   | 1.0%  |
| Messages                 | 591    | 0.1%  |
| Free space               | 898.7k | 92.9% |
| Autocompact buffer       | 33k    | 3.4%  |
```

followed by **per-item tables for `Custom Agents` and `Skills`** (each agent and each skill with its
own token count and source, e.g. `discovery:researcher | Plugin | 122`, `adhd:shape | Plugin (adhd) |
~330`).

**The granularity finding that matters most to this skill:**

- `Custom agents` and `Skills` get **per-item** attribution.
- `System tools` and `System tools (deferred)` get **bucket totals only — there is no per-tool
  line.** No flag observed produces one; `all` expands the itemized categories, not the tool buckets.
- Therefore **`/context` alone cannot price an individual tool definition.** The skill must price
  per-tool by differencing (below) or by the count_tokens API.
- The separate `System tools (deferred)` bucket is itself a significant finding: Claude Code
  attributes real local token cost to deferred definitions, consistent with the API statement that
  they are still sent in the `tools` array (see `RESEARCH-deferral-mechanism.md`).

## 2. `claude -p "/context"` headlessly — **yes, it works**

This was an open question in the dispatch. **Verified empirically, Tier 0, 2026-08-17:**

```bash
claude -p "/context" --output-format json
```

exits 0 and returns a normal result envelope whose **`result` field contains the complete `/context`
markdown report** — the category table plus the per-agent and per-skill tables. Notably
`duration_api_ms: 0`, `num_turns: 0`, and all `usage` counters are 0: the command is handled locally
without an API round trip, so **polling it is free**.

This is more than the docs promise. `https://code.claude.com/docs/en/headless` (fetched 2026-08-17)
says user-invoked skills and custom commands work in `-p`, and enumerates built-in commands with
`-p` support — "`/model`, `/effort`, `/fast`, `/color`, and `/rename` accept the value as an
argument… `/mcp` with no argument prints a text summary" — and **`/context` is not in that list**,
nor does its `commands` row carry the "Also available in non-interactive mode (`-p`)" note that
`/model`, `/effort`, `/config`, `/mcp`, `/rename` and `/color` all carry.

**So `/context` under `-p` is verified working but undocumented.** For a marketplace skill that is a
material risk: undocumented behavior can change without a changelog entry. Recommend the skill probe
for it and degrade gracefully rather than depending on it.

**Differencing recipe** (this run's method, and the only way to get per-tool numbers today): run
`claude -p "/context" --output-format json` twice, identical except for a bare-name deny of the tool
under test, and subtract the `System tools` / `System tools (deferred)` buckets. Verified to produce
clean, attributable deltas — see the four-run table in `RESEARCH-permission-pruning.md`.

## 3. The token-counting API

`https://platform.claude.com/docs/en/build-with-claude/token-counting` (fetched 2026-08-17):

> The token counting endpoint accepts **the same structured list of inputs for creating a message,
> including support for system prompts, tools, images, and PDFs**. The response contains the total
> number of input tokens.

Endpoint: `POST https://api.anthropic.com/v1/messages/count_tokens`. The page carries a dedicated
worked example, *Count tokens in messages with tools*, passing a `tools` array. Pricing/limits: the
endpoint is free but rate-limited (see its *Pricing and rate limits* section).

**This is the ground-truth instrument for the skill.** To price one tool definition: count with the
definition present, count with it absent, subtract. Two caveats the page states:

- **A tool-use system prompt is added whenever `tools` is non-empty**, and its size is model-specific.
  `https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview#pricing` (fetched
  2026-08-17) tabulates it: Opus 5 — 286 tokens (`auto`/`none`) / 406 (`any`/`tool`); Sonnet 5 — 354 /
  474; Opus 4.5, Sonnet 4.5, Haiku 4.5 — 496 / 588; Opus 4.6 and Sonnet 4.6 — 497 / 589; Opus 4.7 —
  675 / 804; Opus 4.8 — 290 / 410. "Note that the table assumes at least 1 tool is provided. If no
  `tools` are provided, then a tool choice of `none` uses 0 additional system prompt tokens." A
  naive A/B that removes the *last* tool therefore also removes this fixed overhead and overstates
  that tool's cost.
- **Server-tool counts "only apply to the first sampling call."**

What the page does **not** say: nothing about `defer_loading` and nothing about whether counting a
deferred definition differs from counting a loaded one. Searched the full page; **absent**. This
matters because it leaves unanswered whether the API bills undiscovered deferred definitions.

## 4. Estimating tokens from characters — Anthropic publishes no such rule

Searched all 21 fetched first-party pages for `characters per token`, `4 characters`, `~4 char`,
`rough estimate`, `estimating tokens`, `character count`. **No characters-per-token guidance
exists in the corpus checked.** What exists is the opposite instruction
(`https://platform.claude.com/docs/en/build-with-claude/token-counting`, fetched 2026-08-17):

> Claude 4.7 and later models and Claude Mythos Preview use a newer tokenizer. **The same input text
> produces approximately 30 percent more tokens than on earlier models.** The exact increase depends
> on the content and workload shape. **Recount prompts against the model you plan to use rather than
> reusing counts measured against earlier models.**

**Direct consequence for the skill: do not ship a chars/4 heuristic.** A ratio calibrated on one
model is wrong by ~30% on another, and Anthropic's own instruction is to recount per model. Use
`count_tokens`, or `/context`'s own estimates, and label estimates as estimates — Claude Code does,
in the report header.

**Sources checked for this absence:** the token-counting page, tool-use overview, implement-tool-use,
manage-tool-context, context-editing, tool-search-tool, and the Claude Code `costs`,
`context-window`, `monitoring-usage`, `settings`, `env-vars` pages. **Left unchecked:** the Anthropic
help center, the prompt-engineering doc family, and the ~2,700 `platform.claude.com` URLs outside
tool-use and token-counting.

## 5. OpenTelemetry — session-level, not tool-definition-level

`https://code.claude.com/docs/en/monitoring-usage` (fetched 2026-08-17) exports per-user, per-session
token and cost metrics with `mcp_server.name` / `mcp_tool.name` attribution on requests, and a
tool-result `result_tokens` field ("Approximate token size of the tool result"). That is **tool
*result* volume and request attribution, not tool *definition* cost.** Useful for the skill's
"is this tool ever actually used?" question — which is the right complement to "what does it cost" —
but it will not price a schema.

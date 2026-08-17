---
topic: claude-code-workflows-context-cost-and-disable
section: context-attribution
abstract: /context has no workflows-specific row; the Workflow tool schema is folded into the generic "System tools" row (or "System tools (deferred)"), so the feature is not separately attributable from /context output alone.
claims:
  - claim: "/context reports a fixed category set that includes 'System tools' and 'System tools (deferred)' but contains no workflows-specific or per-tool row."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local: claude.exe v2.1.232, adjacent UI label literals 'System prompt','System tools','MCP tools','MCP tools (deferred)','System tools (deferred)','Custom agents','Memory files','Skills','Messages','Free space'"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://code.claude.com/docs/en/commands"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic (code.claude.com docs)"
  - claim: "The Workflow tool's cost is therefore attributed to the generic 'System tools' row, and cannot be separated from other built-in tools by reading /context alone."
    confidence: HIGH
    tiers: [0, 2]
    sources:
      - url: "local: claude.exe v2.1.232, Workflow is a built-in registry tool filtered by isEnabled()"
        tier: 0
        pool: "installed CLI binary (direct tool output)"
      - url: "https://www.aihero.dev/how-to-kill-the-bloat-in-claude-codes-system-prompt"
        tier: 2
        pool: "aihero.dev (named practitioner blog)"
      - url: "https://github.com/anthropics/claude-code/issues/66073"
        tier: 1
        pool: "GitHub issue tracker (community, anthropics/claude-code)"
produced_by: phase-2
---

# Does `/context` attribute workflows to a specific row?

**No.** There is no workflows row, and no per-tool breakdown. All evidence captured **2026-08-17**.

## The actual row set

Recovered Tier 0 from the v2.1.232 binary, where the `/context` category labels sit as adjacent
string literals in the UI table:

| Row label | Notes |
|---|---|
| `System prompt` | |
| **`System tools`** | **where the `Workflow` schema lands** |
| `MCP tools` | |
| `MCP tools (deferred)` | |
| **`System tools (deferred)`** | built-ins held behind `ToolSearch` |
| `Custom agents` | |
| `Memory files` | |
| `Skills` | |
| `Messages` | |
| `Autocompact buffer` / `Compact buffer` | |
| `Free space` | |

Corroborated at the category level by first-party prose describing `/context` as a breakdown "by
category — system prompt, system tools, MCP tools, memory files, messages — each with a token count
and its share of the window", and by the command reference
([commands](https://code.claude.com/docs/en/commands), fetched 2026-08-17):

> "`/context [all]` — Visualize current context usage as a colored grid. Shows optimization
> suggestions for context-heavy tools, memory bloat, and capacity warnings. … In fullscreen mode,
> `/context` collapses the per-item breakdown to keep the grid visible. Pass `all` to expand it"

## The consequence for the skill

- **Workflows are invisible as a line item.** Their ~19.6 KB of schema is summed into `System tools`
  alongside every other built-in. A user staring at `/context` cannot tell that one tool is
  responsible for roughly a third of that row.
- **This is precisely the gap the proposed skill fills**, and it is worth saying so in the skill's
  own framing: the value it adds over `/context` is *attribution*, not measurement.
- **`/context` can still verify a trim by differencing.** Record `System tools` before and after
  setting `disableWorkflows`; the delta is the workflow saving. That is the cheapest in-session
  verification available and it needs no proxy.
- **Watch which of the two rows moves.** If a session has tool search active and `Workflow` happens
  to be deferrable, the cost may sit in `System tools (deferred)` instead. A harness that reads only
  `System tools` would then report a smaller number than the true saving.

## Source-quality note on `docs/en/context-window`

That page hosts an interactive visualization whose row labels I initially mistook for the live
`/context` row set. It is explicitly illustrative — "The visualization uses representative numbers.
To see your actual context usage at any point, run `/context` for a live breakdown by category"
([context-window](https://code.claude.com/docs/en/context-window), fetched 2026-08-17). Its labels
overlap the real ones but include narrative entries (`Read src/api/auth.ts`, `Hook: prettier`) that
are not `/context` categories. **Do not enumerate `/context` rows from that page.** The row set above
comes from the binary's own UI literals.

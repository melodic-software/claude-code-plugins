---
topic: context-command-output-contract
section: output-contract
abstract: The /context markdown is emitted by one deterministic generator with a fixed six-section order and two distinct token formatters; skill rows alone carry "~" or "< 20".
claims:
  - claim: "The markdown a parser sees is produced by a single generator function that builds a string; it is not a rendering of the TUI grid, which is a separate Ink component."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (function aFn, byte-extracted 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.129 entry, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
      - url: "local probe: claude -p \"/context\" --output-format json, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
  - claim: "Section order is fixed: header, Estimated usage by category, MCP Tools, Custom Agents, Memory Files, Skills — each section after the first emitted only when its data is non-empty."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (aFn emission order, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "local probe with --mcp-config and CLAUDE.md present, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
  - claim: "Skill token cells use a different formatter from every other table: they render as \"~<rounded-to-10>\" or the literal \"< 20\", while all other token cells use the plain compact formatter."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (functions dne and Fl, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.139 entry, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
      - url: "local probe output, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
produced_by: phase-1-source-read + phase-2-empirical
---

# The /context output contract in v2.1.232

## Where the markdown comes from

Two different renderers exist, and a parser must know it is reading the second one.

1. **The Ink/TUI grid** — the coloured square grid, component `GUi`. This is what an interactive
   terminal shows. Changelog v2.1.129 records a fix for this grid being dumped into the
   conversation and "wasting ~1.6k tokens per call", which is why the two paths are now distinct.
2. **The markdown string** — built by a single function (`aFn` in the stripped binary) that
   concatenates a string. This is what lands in the conversation as a system meta-message, and it
   is what `claude -p "/context"` returns.

Both are driven from **one data object**, so the grid and the markdown never disagree about
numbers. The markdown generator takes that object and emits, in this exact order:

```
## Context Usage

**Model:** <model-id>␣␣
**Tokens:** <total> / <rawMax> (<pct>%)
[**Over limit:** <message>]

### Estimated usage by category
### MCP Tools
### Custom Agents
### Memory Files
### Skills
```

The `**Model:**` line ends with **two trailing spaces** (a markdown hard line break) — literal in
the generator. A strict line-trimming parser will silently discard them; a whitespace-sensitive
regex must tolerate them.

## The six blocks, exactly

### Header

`**Tokens:**` uses the compact formatter on both sides, and the percentage here is an
**integer** field taken straight from the data object — not recomputed. `**Over limit:**` is
emitted only when total exceeds the raw max.

### `### Estimated usage by category`

```
| Category | Tokens | Percentage |
|----------|--------|------------|
```

Construction has three deliberate properties a parser depends on:

- **Rows are filtered to `tokens > 0`.** A category with zero tokens is *absent*, not zero-valued.
  This is why the probe run showed no MCP and no Memory files rows.
- **`Free space` and `Autocompact buffer` are excluded from the main loop and re-appended
  afterwards**, in that order. So they are always the last two rows when present, regardless of
  where they sit in the internal category list.
- **The percentage here is recomputed** as `tokens / rawMaxTokens * 100` formatted `toFixed(1)` —
  always one decimal place, e.g. `0.5%`, `92.9%`, `0.0%`. This differs from the header percentage
  (integer) and from the TUI grid (which rounds to integer). A `0.0%` row is a real row with
  non-zero tokens, not an empty one.

### `### MCP Tools`

```
| Tool | Server | Tokens |
```

Per-tool **and** per-server attribution. Emitted only when at least one MCP tool is present.

### `### Custom Agents`

```
| Agent Type | Source | Tokens |
```

### `### Memory Files`

```
| Type | Path | Tokens |
```

Path is **absolute** as printed.

### `### Skills`

```
| Skill | Source | Tokens |
```

Emitted when skill tokens are non-zero **and** the frontmatter list is non-empty — a
two-condition guard, unlike the other sections' single length check.

## The formatter split — the sharpest parsing trap

Two formatters are in play and they are not interchangeable:

| Formatter | Used by | Output shape |
|---|---|---|
| compact | header, category table, MCP tokens, agent tokens, memory tokens | `591`, `18.1k`, `898.7k`, `33k` — a trailing `.0` is stripped, so `33.0k` prints as `33k` |
| approximate | **Skills table only** | `~260`, `~90` — value rounded to the nearest 10 and prefixed `~`; **or the literal string `< 20`** when the value is under 20 |

So a numeric parser over the Skills column must handle three shapes: `~<int>`, `< 20`, and
nothing else. `< 20` is a string sentinel with no number to extract — it is not `<20` and not
`~20`. Changelog v2.1.139 is where per-skill estimates started showing "rounded values", which
dates this formatter split.

The compact formatter's `k` suffix means the value is **not** an exact token count. A measurement
engine that needs exact integers cannot get them from this markdown at any magnitude above ~1000,
and cannot get them from the Skills column at all.

## Two sections that are built but never emitted

The generator destructures `systemTools` and `systemPromptSections` out of its data object and
they reach the emission site — but the guard there is a **comma expression**
(`if (p && p.length > 0, f && f.length > 0, c.length > 0)`), so only the last operand, the agents
check, controls the branch. Whatever those two sections were meant to render, they contribute
nothing to the markdown in v2.1.232. This is the direct mechanical reason there is no per-tool
System-tools table (see `RESEARCH-category-semantics.md`).

## Independence caveat

Every source above is published by Anthropic. The three evidence *methods* are genuinely
independent — direct binary extraction, an executed CLI probe, and Anthropic's own prose — but
they are not independent *publishers*. For a closed-source vendor CLI no second publisher exists
that documents this format at all (see `RESEARCH-documentation-and-stability.md`). Confidence is
rated HIGH on the strength of Tier-0 execution agreeing with Tier-0 code inspection, which is the
strongest available evidence class here, not on publisher diversity.

---
topic: context-command-output-contract
section: category-semantics
abstract: "System tools" is one aggregate block of non-deferred built-in tool schemas plus any deferred tools already invoked, minus skill frontmatter; no per-tool attribution exists because the field that would carry it is always empty.
claims:
  - claim: "\"System tools\" aggregates non-deferred built-in (non-MCP) tool definitions measured as one block, plus the deferred built-in tools already invoked this session, then subtracts skill-frontmatter tokens."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (function Q7v and the category push site, byte-extracted 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "local probe: claude -p \"/context\", v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
  - claim: "No per-tool breakdown of System tools exists in v2.1.232 and no flag, argument, or environment variable produces one; the systemToolDetails array is initialised empty and never populated on any return path."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (Q7v returns systemToolDetails:p with p=[] on all four returns, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "local probe: claude --help full flag enumeration, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
      - url: "https://code.claude.com/docs/en/commands (fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-docs"
  - claim: "\"System tools (deferred)\" counts built-in tools withheld from context by tool search and not yet invoked; the row is absent entirely when tool search is off, because all built-ins are then folded into System tools."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (Q7v early return when tool search disabled, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search (fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-docs"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.7, v2.1.119 entries, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
produced_by: phase-1-source-read + phase-2-targeted
---

# What each category row actually contains

## The full ordered category list

The internal list is built by pushing rows in a fixed order, each gated on `tokens > 0`:

| # | Row name | Gate |
|---|---|---|
| 1 | `System prompt` | system prompt tokens > 0 |
| 2 | `System tools` | (built-in tokens − skill frontmatter tokens) > 0 |
| 3 | `MCP tools` | non-deferred MCP tokens > 0 |
| 4 | `MCP tools (deferred)` | deferred MCP tokens > 0 |
| 5 | `System tools (deferred)` | deferred built-in tokens > 0 |
| 6 | `Custom agents` | agent tokens > 0 |
| 7 | `Memory files` | CLAUDE.md tokens > 0 |
| 8 | `Skills` | skill frontmatter tokens > 0 |
| 9 | `Messages` | message tokens > 0 |
| 10 | `Autocompact buffer` **or** `Compact buffer` | whichever buffer mode applies |
| 11 | `Free space` | always pushed |

Two names in that table never appeared in the probe and are worth knowing about: **`Compact
buffer`** is the sibling of `Autocompact buffer` — the generator selects between them depending on
whether autocompaction is enabled, so a parser hardcoding only `Autocompact buffer` will miss the
other. And rows 3 and 4 are two *different* MCP rows, not one.

## "System tools" — the aggregate, and why it is aggregate

The accounting function partitions all registered tools into MCP and non-MCP, then splits the
non-MCP set by whether each tool is deferrable:

- **Non-deferred built-ins** (Bash, Read, Edit, and the rest of the always-loaded core) are token
  counted **as a single batch** — one measurement call over the whole array, not per tool. There
  is no intermediate per-tool number to report, because none is ever computed.
- **Deferred built-ins** *are* measured individually — one call per tool — producing a list of
  `{name, tokens, isLoaded}`. Each per-tool figure has a fixed constant (500) subtracted from it,
  floored at zero, to net out per-call measurement overhead.
- `System tools` = the batch figure **+** the individual figures of deferred tools that have
  already been invoked. `System tools (deferred)` = the individual figures of the ones that have
  not.

"Already invoked" is determined by scanning the transcript's assistant messages for `tool_use`
blocks whose name matches a deferred tool. So a tool migrates from the deferred row into the
System tools row the moment it is first used, and the two rows shift in opposite directions
mid-session. **A measurement engine diffing two `/context` runs must expect this movement without
any config change.**

### The skill subtraction

The `System tools` row is not the raw built-in figure — it is that figure **minus skill
frontmatter tokens**. Skill descriptions reach the model through the Skill tool's own definition,
so they are already inside the built-in measurement; subtracting them prevents double counting
against the separate `Skills` row. Consequence: **`System tools` is not independently meaningful
without the `Skills` row**, and installing skills makes `System tools` go *down* while `Skills`
goes up. Changelog v2.1.0 ("Fixed skill token estimates in `/context` to accurately reflect
frontmatter-only loading") is where this accounting was settled.

## Why there is no per-tool attribution, and no way to get one

The accounting function returns a field named `systemToolDetails`. It is initialised as an empty
array and returned unchanged on **every one of its four return paths** — nothing ever pushes into
it. The markdown generator does destructure it and does reach an emission site for it, but that
site is disabled by the comma-expression guard described in `RESEARCH-output-contract.md`.

So the absence is structural at two independent layers, and no runtime switch reaches either:

- **`/context` takes exactly one argument, `all`** (`argumentHint: "[all]"`), and it toggles only
  whether *detail sections* are collapsed — it does not create a System-tools detail section that
  does not exist.
- **`claude --help` was enumerated in full at v2.1.232.** No flag relates to context breakdown
  granularity. `--debug`/`--verbose` affect logging, not this renderer.
- **No environment variable affects it.** `ENABLE_TOOL_SEARCH` changes *which bucket* built-ins
  land in (see below), which changes the split between two rows but never produces per-tool rows.

**Checked and not found in:** the shipped v2.1.232 binary (exhaustive by construction for shipped
behaviour), `claude --help`, `https://code.claude.com/docs/en/commands`,
`https://code.claude.com/docs/en/settings`, and the full docs `sitemap.xml` page enumeration.
**Left unchecked:** the `/en/env-vars` page was not fetched in full (its content was reached only
via cross-references from the tool-search and settings pages), and Anthropic's internal
non-published configuration is not observable. A per-tool switch hiding in `/en/env-vars` is
possible but would have to bypass a code path that computes nothing to display.

**Per-tool attribution that *does* exist:** MCP tools get it (`| Tool | Server | Tokens |`), and
deferred built-ins are computed per tool internally even though the markdown never prints them.
The asymmetry is real and is the single most surprising thing about this output.

## "System tools (deferred)" and its relation to tool search

Tool search is the mechanism. Per Anthropic's tool-search documentation, when it is active "tool
definitions are withheld from the context window" and the agent loads up to five relevant tools on
demand. A tool that is withheld is *deferred*.

The naming in the output is by **origin**, not by search tool:

- `System tools (deferred)` — deferred **built-in** tools. In this session these are the ones the
  environment surfaces through `ToolSearch`.
- `MCP tools (deferred)` — deferred **MCP** tools. Historically discovered via `MCPSearch`
  (changelog v2.1.7, which enabled MCP tool search auto mode by default and named `MCPSearch` as
  the discovery tool and `disallowedTools` as the opt-out).

The docs confirm both classes share one budget: under `auto`, the SDK "counts every definition
that tool search can defer toward one combined threshold: each MCP tool that isn't marked
`alwaysLoad`, from any server, plus the built-in tools that load on demand. The SDK always loads
core built-in tools such as Bash, Read, and Edit upfront and doesn't count them toward the
threshold." That last sentence is exactly the partition the accounting function implements.

### The row can vanish entirely

If tool search is **not** enabled, the accounting function takes an early return that measures the
deferred set as one batch, adds it to the built-in total, and returns `deferredBuiltinTokens: 0`
with an empty details list. The `System tools (deferred)` row is then absent and its tokens are
inside `System tools` instead.

`ENABLE_TOOL_SEARCH` governs this, with documented values `unset` (on by default), `true`, `auto`,
`auto:N`, and `false`. It is additionally forced off by `CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS`,
by a non-first-party `ANTHROPIC_BASE_URL`, by Microsoft Foundry deployments hosted on Azure, and
by pre-4.5-generation models on Google Cloud's Agent Platform.

**For a measurement engine this is the highest-variance factor in the whole output**: the same
machine and the same skill set produce a different row set depending on model, gateway, and
environment. `System tools` and `System tools (deferred)` should be summed before comparison
across environments, never compared individually.

---
topic: context-command-output-contract
section: conditional-rows
abstract: MCP servers add both a category row and a per-tool/per-server MCP Tools section; CLAUDE.md files still produce a Memory files row and a Memory Files section at 2.1.232 — both were merely absent from the probe, not removed.
claims:
  - claim: "With MCP servers configured, /context adds an MCP category row and a \"### MCP Tools\" section giving per-tool AND per-server attribution via columns Tool | Server | Tokens."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local probe: claude -p \"/context\" --mcp-config with a filesystem MCP server, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (aFn MCP section emission, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.1.69 entry, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
  - claim: "The MCP category row appears as either \"MCP tools\" or \"MCP tools (deferred)\" depending on whether tool search deferred the schemas; the deferred variant is what a default modern session produces."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local probe with --mcp-config, v2.1.232, run 2026-08-17 — emitted \"MCP tools (deferred) | 2.8k\""
        tier: 0
        pool: "empirical-cli-probe"
      - url: "https://code.claude.com/docs/en/agent-sdk/tool-search (fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-docs"
  - claim: "Memory files are still their own category row AND their own \"### Memory Files\" section at v2.1.232; the earlier internal note was correct and nothing replaced it — the rows are simply omitted when no CLAUDE.md is loaded."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "local probe in a directory containing CLAUDE.md, v2.1.232, run 2026-08-17 — emitted \"Memory files | 89\" and a Memory Files table"
        tier: 0
        pool: "empirical-cli-probe"
      - url: "file:///home/user/claude-code-plugins/node_modules/@anthropic-ai/claude-code/bin/claude.exe (memory row push and Memory Files section emission, 2026-08-17)"
        tier: 0
        pool: "anthropic-shipped-binary"
produced_by: phase-2-empirical
---

# The conditional rows the probe could not see

The parent's probe showed no MCP row and no memory row. Neither is evidence of removal — both are
gated on non-zero data, and that probe had no MCP server configured and no CLAUDE.md in scope.
Both were reproduced directly.

## Method

A second probe was run against the same v2.1.232 binary in a scratch directory containing a
`CLAUDE.md`, with a filesystem MCP server supplied via `--mcp-config`:

```
claude -p "/context" --mcp-config mcp.json --output-format json
```

## Result — MCP (question 4)

**Yes on both counts: a category row and full per-server attribution.**

The category table gained:

```
| MCP tools (deferred) | 2.8k | 0.3% |
```

and a new section appeared, positioned **between the category table and Custom Agents**:

```
### MCP Tools

| Tool | Server | Tokens |
|------|--------|--------|
| mcp__probefs__create_directory | probefs | 175 |
| mcp__probefs__directory_tree | probefs | 218 |
| mcp__probefs__edit_file | probefs | 253 |
...
```

Three things matter for a parser:

1. **Attribution is per tool, with the server as a separate column** — not a per-server subtotal.
   Aggregating by server is the consumer's job. Changelog v2.1.69 ("Fixed `/context` showing
   identical token counts for all MCP tools from a server") confirms these are genuinely
   individual measurements, and dates the fix that made them so.
2. **The category row name depends on deferral.** With tool search active the row is
   `MCP tools (deferred)`; with tool search off it is `MCP tools`. Both can in principle appear at
   once — the generator pushes them as two separate rows — when some MCP tools are deferred and
   others are not (for example a server exempted via `alwaysLoad`). A parser must treat these as
   two distinct rows and sum them for a total MCP figure.
3. **The section header is `### MCP Tools` regardless** of which category row appeared. The
   section is gated on the tool list being non-empty, not on the deferral state.

Note the accounting asymmetry against built-in tools: MCP tools get a full per-tool table in the
markdown, while built-in tools get none (see `RESEARCH-category-semantics.md`). The deferred MCP
tokens shown in the category row are the withheld ones; the per-tool table lists the tools
regardless of whether each is currently loaded.

## Result — memory files (question 5)

**The Memory Files section still exists at 2.1.232. It was not replaced by the category table —
the two coexist, and always have in this version.**

The category table gained a row positioned between `Custom agents` and `Skills`:

```
| Memory files | 89 | 0.0% |
```

and the section appeared **between Custom Agents and Skills**:

```
### Memory Files

| Type | Path | Tokens |
|------|------|--------|
| Project | /…/ctxtest/CLAUDE.md | 89 |
```

Details a parser needs:

- **Columns are `Type | Path | Tokens`** — the type is the scope label (`Project` here; `User` for
  `~/.claude/CLAUDE.md`), and the path is **absolute as printed**. An artifact recording these
  paths verbatim leaks machine-specific absolute paths.
- **The `0.0%` percentage is real.** 89 tokens against a 967k window rounds to `0.0%` at one
  decimal place, while the row is present precisely because tokens are non-zero. Treating
  `0.0%` as "absent" is a parsing error.
- **The earlier internal note is vindicated, with one correction.** It described a "Memory Files"
  section enumerating User and Project CLAUDE.md rows; that is exactly what v2.1.232 emits. What
  the note appears to have missed is that the section is *conditional*, so a session with no
  memory file — which is what the parent's probe was — shows neither the row nor the section.

## Why the first probe saw neither

Both omissions trace to the same `tokens > 0` / `length > 0` gating rather than to any version
change. The parent's probe ran with no MCP server and, evidently, no CLAUDE.md reaching the
session. Anything that suppresses memory loading produces the same absence — notably `--bare`,
which `claude --help` describes as skipping "auto-memory ... and CLAUDE.md auto-discovery".

**A measurement engine must therefore never infer "feature absent" from "row absent."** The row
set is a function of session state, and a baseline captured in one directory is not comparable to
one captured in another.

---
topic: context-command-output-contract
section: documentation-and-stability
abstract: Only the command's existence and its "all" argument are documented; the output schema is documented nowhere, carries no stability guarantee, and has changed shape roughly every 30 releases.
claims:
  - claim: "No official documentation specifies /context's output format; the docs describe only the command's purpose and its optional \"all\" argument, and the full docs sitemap contains no /context reference page."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/sitemap.xml (enumerated 2026-08-17 — no /context page in any locale)"
        tier: 1
        pool: "anthropic-docs"
      - url: "https://code.claude.com/docs/en/commands (fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-docs"
      - url: "local probe: claude --help, v2.1.232, run 2026-08-17 — no output-schema documentation"
        tier: 0
        pool: "empirical-cli-probe"
  - claim: "The output carries no stability guarantee, explicit or implied, and its shape has changed materially across at least v2.0.74, v2.1.0, v2.1.74, v2.1.129, v2.1.139 and v2.1.216."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (fetched 2026-08-17; latest release 2.1.233)"
        tier: 1
        pool: "anthropic-github-changelog"
      - url: "https://code.claude.com/docs/en/commands (fetched 2026-08-17 — no stability statement)"
        tier: 1
        pool: "anthropic-docs"
  - claim: "Per-skill and per-agent tables grouped by source were introduced in v2.0.74; the plugin name on plugin-sourced skills was added in v2.1.139."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (v2.0.74 and v2.1.139 entries, fetched 2026-08-17)"
        tier: 1
        pool: "anthropic-github-changelog"
      - url: "local probe output confirming both behaviours present at v2.1.232, run 2026-08-17"
        tier: 0
        pool: "empirical-cli-probe"
produced_by: phase-1-broad + phase-2-falsification
---

# Is the format documented? Is it stable?

## Documented: barely

The docs site's `sitemap.xml` was enumerated in full — it is exhaustive by construction for that
host's pages — across every locale. **There is no `/context` reference page.** The command's only
official description is one row in the slash-commands table at
`https://code.claude.com/docs/en/commands`:

> `/context [all]` — Visualize current context usage as a colored grid. Shows optimization
> suggestions for context-heavy tools, memory bloat, and capacity warnings. When the conversation
> exceeds the context window, the output includes a warning showing how far over the limit you are
> and which command frees space. In fullscreen mode, `/context` collapses the per-item breakdown to
> keep the grid visible. Pass `all` to expand it

That row documents **behaviour**, not **schema**. No category name, no column header, no table
layout, and no token-formatting rule appears in any official artifact. The `/en/context-window`
page — the closest candidate by name — is an interactive simulation of context filling and does
not mention `/context` at all.

The row does confirm one thing the source read predicted: the collapse condition is **fullscreen
mode**, and `all` is the expansion switch.

### The `-p` consequence, which is good news

Because collapsing is gated on fullscreen, a **non-interactive `claude -p "/context"` run is not
collapsed** — the detail sections come out expanded without passing `all`. That is why the
parent's probe saw per-agent and per-skill tables it never asked for. Passing `all` is harmless
and makes the intent explicit; a measurement engine should pass it anyway so the behaviour does
not depend on how the harness happens to invoke the CLI.

## Stable: explicitly not, and demonstrably not

**No stability statement exists** — neither a guarantee nor a disclaimer. The format is not
described as an interface at all, which is weaker than being described as unstable: there is
nothing for Anthropic to break, so nothing constrains them.

The upstream changelog (latest release **2.1.233**, one ahead of the 2.1.232 under study) records
a steady drift in exactly the surface a parser depends on:

| Version | Change to the output surface |
|---|---|
| 1.0.86 | `/context` introduced |
| 2.0.74 | "Improved `/context` command visualization with **grouped skills and agents by source**, slash commands, and sorted token count" — the origin of the Source column and of the per-skill/per-agent tables |
| 2.1.0 | Skill token estimates corrected to frontmatter-only loading — token *values* changed |
| 2.1.74 | Actionable optimization suggestions added to the command |
| 2.1.101 | Free space and Messages breakdown reconciled with the header percentage |
| 2.1.129 | The ASCII grid stopped being dumped into the conversation — the split between the grid and the markdown |
| 2.1.139 | `/context all` per-skill estimates became tokenizer-aware and **rounded**; **plugin name added** to plugin-sourced skills |
| 2.1.216 | Over-limit warning added to the output |
| 2.1.218 | Stale post-compaction token usage fixed |

That is a material change to the parsed surface roughly every 30 patch releases, several of which
would break a naive parser outright — v2.1.139 alone changed skill token cells from bare integers
to `~`-prefixed rounded values, and v2.1.216 added a header line that was not previously possible.

### Version answer for the parent's question

- **Per-skill and per-agent tables grouped by source: v2.0.74.**
- **`Plugin (name)` on skills: v2.1.139.** Before that, plugin skills showed a bare source.
- Both confirmed present at v2.1.232 by direct probe.

## Falsification attempt

The leading hypothesis — *the markdown is a stable, single-generator contract with no
machine-readable alternative* — was tested by searching for a documented or third-party-reported
structured `/context` output and for reports of the format changing under consumers.

The attempt **failed to break the "no structured CLI output" half** (see
`RESEARCH-structured-output.md`) and **succeeded against the "stable" half**: the changelog
evidence above shows the shape is not stable, and the searches surfaced **no third party
documenting the format at all** — no blog, no reference, no wrapper library. The absence of any
external documentation is itself a finding: a parser built on this output has no community
early-warning system when it changes.

**Checked for a stability statement / format spec:** `sitemap.xml` full enumeration,
`/en/commands`, `/en/context-window`, `/en/settings`, `/en/agent-sdk/tool-search`, `claude --help`,
the upstream `CHANGELOG.md`, the upstream issue tracker, and two open web searches for third-party
documentation. **Left unchecked:** `/en/headless`, `/en/cli-reference`, and `/en/costs` were not
fetched in full; they document the CLI and cost surfaces and could plausibly restate the JSON
envelope, but none is a likely home for a slash-command output schema.

## What this means for a parsing skill

The output is a **de facto** contract, not a **de jure** one. It is highly deterministic within a
version — one generator, fixed order, no locale variation observed in the generator's literals —
and unguaranteed across versions. A measurement engine should therefore:

- **Pin and record the version it parsed** (`claude --version`) alongside every measurement, and
  treat a version change as invalidating stored baselines rather than as a diff to be explained.
- **Parse defensively by section header and column name**, not by row index or fixed offsets, so a
  new section or a reordered row degrades rather than corrupts.
- **Fail loudly on an unrecognised category name**, since a renamed row otherwise silently drops a
  whole bucket from a total.

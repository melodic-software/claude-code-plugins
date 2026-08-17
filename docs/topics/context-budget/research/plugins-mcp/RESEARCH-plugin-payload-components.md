---
topic: plugins-mcp-context-budget
section: plugin-payload-components
abstract: Of a plugin's seven component types only skills/commands and agents cost always-loaded context (listing text only); hooks, monitors, themes and LSP cost zero model context, and MCP tool schemas are deferred.
claims:
  - claim: "A plugin's always-loaded model-context cost is its listing text only — skill/command names plus descriptions and agent descriptions — not the bodies, which load on invocation."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/plugins-reference#plugin-details"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "claude plugin details actionlint@melodic-software (v2.1.232)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "claude -p '/context' live breakdown (v2.1.232)"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
  - claim: "Plugin hooks carry no model-context cost; they are harness-only."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "claude plugin details actionlint@melodic-software — 'Hooks (1)  PostToolUse  (harness-only — no model context cost)'"
        tier: 0
        pool: "installed Claude Code v2.1.232 on this machine"
      - url: "https://code.claude.com/docs/en/prompt-caching#enabling-or-disabling-a-plugin"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "binary-extracted /doctor bundled-skill prompt, Check 1 context-cost rules"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
  - claim: "The skill listing is budgeted at a fraction of the context window (default 1%, `skillListingBudgetFraction`), and over-budget listings have descriptions dropped rather than growing without bound."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings#available-settings (skillListingBudgetFraction, skillListingMaxDescChars)"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short"
        tier: 1
        pool: "Anthropic first-party docs (code.claude.com)"
      - url: "binary-extracted /doctor bundled-skill prompt, Check 1"
        tier: 0
        pool: "installed Claude Code v2.1.232 binary"
produced_by: phase-1-phase-2
---

# Q2 — What one enabled plugin contributes to the always-loaded payload

Docs fetched **2026-08-17**; CLI output from **Claude Code v2.1.232**, run 2026-08-17.

## The authoritative per-component answer

`claude plugin details <name>` is the product's own answer to this question, and it is
**headless-capable** (it is a `claude plugin` subcommand, not a slash command). Tier-0 run on this
machine, 2026-08-17:

```text
$ claude plugin details actionlint@melodic-software
actionlint 0.8.15
  Lint GitHub Actions workflow files on edit via actionlint, surfacing findings as advisory context.
  Source: actionlint@melodic-software

Component inventory
  Skills (1)  setup
  Agents (0)
  Hooks (1)  PostToolUse  (harness-only — no model context cost)
  MCP servers (0)
  LSP servers (0)

Projected token cost
  Always-on:   ~137 tok   added to every session

Per-component (rounded)
  component  always-on  on-invoke
  setup           ~140      ~2.4k

  On-invoke cost is paid each time a skill or agent fires.
  Token counts are estimates and may differ from actual usage.
```

The docs define the two columns:

> "**Always-on:** tokens added to every session by the plugin's listing text, such as skill
> descriptions, agent descriptions, and command names, regardless of whether any component fires.
> **On-invoke:** tokens a component costs when it fires. Shown per component, not as a plugin total,
> because a typical session invokes only a subset of components."
> — <https://code.claude.com/docs/en/plugins-reference#plugin-details> (fetched 2026-08-17)

and how the number is produced:

> "The always-on total is computed via the `count_tokens` API for your active model. Per-component
> numbers are proportionally scaled from that total. If the API is unreachable, the command falls
> back to a character-based estimate."

**Note the ~137 vs ~140 discrepancy** in the real output above: the plugin total and the
per-component figure disagree because per-component numbers are *scaled*, not measured. A skill
that sums per-component figures will not reproduce the plugin total. Use the `Always-on:` line.

## Per component type

| Component | Location in plugin | Always-loaded model context | Deferred | Loaded on invocation |
|---|---|---|---|---|
| **Skills** (`skills/`) | `skills/<name>/SKILL.md` | **Yes** — name + description in the skill listing | No | Yes — full `SKILL.md` body |
| **Commands** (`commands/`) | `commands/*.md` | **Yes** — counted in the same Skills group by `plugin details` | No | Yes |
| **Agents** | `agents/*.md` | **Yes** — agent description | No | Yes — body becomes the subagent's system prompt |
| **Hooks** | `hooks/hooks.json` or inline | **No** — "harness-only — no model context cost" | n/a | Hook *output* enters context when it fires |
| **MCP servers** | `.mcp.json` at plugin root or inline | **Effectively no, by default** — only tool *names* + server instructions | **Yes** (tool search) | Schema fetched via `ToolSearch` |
| **LSP servers** | `.lsp.json` or inline | **No** model-context cost found in any source | n/a | Diagnostics/navigation results enter context when delivered |
| **Monitors** | `monitors/monitors.json` | **No** definition cost; each stdout line is delivered to Claude as a notification | n/a | Continuous, while the session runs |
| **Themes** | `themes/*.json` | **No** — UI only, experimental component | n/a | n/a |
| **Output styles** | (user/project, not listed as a plugin component in plugins-reference) | **Yes** — appended to the system prompt | No | Fixed at session start |

Component locations: <https://code.claude.com/docs/en/plugins-reference> (fetched 2026-08-17),
sections Skills, Agents, Hooks, MCP servers, LSP servers, Monitors, Themes.

### Skills and commands — the real always-loaded cost, and its ceiling

> "Claude Code loads a listing of skill names and descriptions into context so Claude knows what's
> available. The listing always contains every skill name, but if you have many skills, Claude Code
> shortens descriptions to fit the listing's character budget […] The budget scales at 1% of the
> model's context window."
> — <https://code.claude.com/docs/en/skills#skill-descriptions-are-cut-short> (fetched 2026-08-17)

This is the single most important structural fact for a trimming skill: **the skill listing is
capped, not unbounded.** Adding plugins past the budget does not grow context — it *degrades
routing*, because descriptions get truncated to names. The failure mode is qualitative before it is
quantitative. The `/doctor` skill states the same:

> "The skill listing is budgeted at ~1% of the context window; when summed descriptions exceed it,
> entries get truncated and skill routing degrades — so a bloated listing matters even before raw
> token cost does." — binary-extracted `/doctor` prompt, Check 1 (Tier 0, 2026-08-17)

Controls: `skillListingBudgetFraction` (default `0.01`), `skillListingMaxDescChars` (default
`1536`), `SLASH_COMMAND_TOOL_CHAR_BUDGET` (fixed char count), and `skillOverrides` with value
`"name-only"` to list a skill without its description. Note `skillOverrides` **"Does not apply to
plugin skills, which are managed through `/plugin`"**
(<https://code.claude.com/docs/en/settings#available-settings>, fetched 2026-08-17) — so
`name-only` is *not* available as a per-plugin-skill lever.

Skill visibility table (<https://code.claude.com/docs/en/skills>, fetched 2026-08-17) confirms the
default: "Description always in context, full skill loads when invoked."

Also: `/context`'s Skills row "reports the size of the listing **after** the budget is applied, so it
matches what the model receives. Before v2.1.196, the row counted the full text of every description
and could show a value several times larger than the configured budget."

### Agents

`/context` reports custom agents as their own category with per-agent token counts. Tier-0 from this
machine (`claude -p "/context"`, 2026-08-17): 12 plugin-provided agents totalling **1.5k tokens**,
each 94–191 tokens. So agents are always-loaded, at description scale, and are individually small.

### Hooks

Zero model context for the *definition*. Two independent confirmations beyond the `plugin details`
output: prompt-caching lists hooks among components that "never invalidate the cache", and
`/doctor`'s Check 1 lists "recurring hook output" — not hook definitions — among costs that are
resident every turn. Hook config lives in `hooks/hooks.json` for plugins and is loaded "When plugin
is enabled" (<https://code.claude.com/docs/en/hooks>, fetched 2026-08-17).

### MCP servers — see the MCP sidecar

Deferred by default. `/doctor` states the operational rule bluntly:

> "**Never report a token cost for deferred MCP tools, and never recommend disabling an MCP server
> to 'save context' when its tools are deferred**" — binary-extracted `/doctor` prompt, Check 1.

Full detail in `RESEARCH-mcp-enablement-deferral.md`.

### LSP servers

No source I fetched assigns LSP servers an always-loaded model-context cost, and `plugin details`
prints an `LSP servers (n)` inventory row with **no** token column entry. `/doctor` notes LSP usage
is tracked via `pluginUsage` and that "transcripts can't attribute LSP activity (diagnostics are
persisted without the server's name), so the counter is the only LSP signal."
**Marked as: not stated to cost always-loaded context; I did not find a positive statement that it
costs zero either.** Sources checked: `plugins-reference.md` (LSP servers section),
`discover-plugins.md`, `costs.md`, `context-window.md`, the `plugin details` output, and the
`/doctor` prompt. Unchecked: the `agent-sdk/*` pages and the running binary's LSP loader.

### Output styles

Not listed as a plugin component in `plugins-reference`. They are always-loaded and immutable
mid-session:

> "Output style is part of the system prompt, which Claude Code reads once at session start. Changes
> take effect after `/clear` or a new session." […] "Claude Code adds each output style's custom
> instructions to the end of the system prompt."
> — <https://code.claude.com/docs/en/output-styles> (fetched 2026-08-17)

**Unverified:** whether a *plugin* can ship an output style. `plugins-reference`'s component list
(Skills, Agents, Hooks, MCP servers, LSP servers, Monitors, Themes) does not include output styles,
but `claude --safe-mode`'s help text lists "output styles" among the customizations plugins are
grouped with. I could not resolve this from the fetched pages.

## What `plugin-relevance` and `plugin-hints` are NOT

Both pages were read end to end (2026-08-17) because their names suggest deferral machinery. Neither
is:

- **`plugin-relevance`** is a *marketplace-operator* feature: a `relevance` block in
  `marketplace.json` that makes Claude Code **suggest uninstalled plugins** when session signals
  match. It is opt-in per marketplace via managed settings and never auto-installs. It has nothing
  to do with deferring an installed plugin's context.
- **`plugin-hints`** is about a CLI emitting a hint line that proposes installing a plugin.

**So: there is no per-plugin lazy-loading mechanism.** An enabled plugin's listing text is loaded at
session start, full stop. The only deferral in the plugin payload is the MCP tool-search path.

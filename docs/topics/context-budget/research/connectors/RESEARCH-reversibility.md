---
topic: claude-ai-connectors-in-claude-code
section: reversibility
abstract: The /mcp toggle acts in-session and persists per project; whether disableClaudeAiConnectors applies mid-session is NOT documented and the two relevant pages point opposite ways — treat it as restart-required.
claims:
  - claim: "The /mcp panel toggle takes effect within the running session — Claude Code stops connecting to the toggled server and still lists it as disabled — and a v2.1.221 fix confirms mid-session disabling is a supported in-session operation."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page)"
      - url: "https://code.claude.com/docs/en/changelog"
        tier: 1
        pool: "Anthropic — code.claude.com docs (changelog, v2.1.221 entry)"
  - claim: "Claude Code watches settings files and reloads most keys without a restart; only model and outputStyle are documented as restart-only."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page)"
  - claim: "Editing MCP configuration does not itself take effect until a restart, which is when servers connect or disconnect."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/prompt-caching.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (prompt-caching page)"
  - claim: "Whether disableClaudeAiConnectors specifically applies mid-session or requires a restart is not stated in any reachable first-party page."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (settings page — checked, does not list the key as restart-only)"
      - url: "https://code.claude.com/docs/en/mcp.md"
        tier: 1
        pool: "Anthropic — code.claude.com docs (mcp page — checked, no restart language present at all)"
produced_by: phase-2-4
---

# Q5 — Is disabling a connector reversible in-session, or does it need a restart?

**Answer: it depends which mechanism, and for the main settings key the docs do not say.** One
mechanism is documented as in-session; one is documented as restart-required; and the most important
one falls in a gap between two pages that point in opposite directions.

## Documented in-session: the `/mcp` toggle

<https://code.claude.com/docs/en/mcp.md>, fetched 2026-08-17:

> Toggle a server off in the `/mcp` panel to stop Claude Code from connecting to it without losing
> its configuration. Claude Code still lists the server in `/mcp`, marked as disabled.

The phrasing is present-tense and the panel is an interactive surface, so this is an in-session
operation. It is corroborated by a changelog fix that only makes sense if mid-session disabling is
supported — <https://code.claude.com/docs/en/changelog>, fetched 2026-08-17, v2.1.221:

> disabling an MCP server mid-connect no longer silently reverts

Re-enabling is symmetric: the toggle writes to / removes from `disabledMcpServers` in
`~/.claude.json`, and the entry is per project. There is no documented restart requirement for the
toggle in either direction.

One adjacent documented in-session behavior, same page:

> With tool search enabled, when a server finishes connecting while Claude is working, Claude Code
> lists the server's tool names to Claude on its next request in the same turn. Claude can then
> search for and call those tools without waiting for your next message.

So connectors appearing mid-session is explicitly supported. That is the reverse direction of the
same capability.

## Documented restart-required: editing MCP config

<https://code.claude.com/docs/en/prompt-caching.md>, fetched 2026-08-17:

> Editing your MCP config does not by itself change the cache. **The new config takes effect only
> after a restart**, which is when the server connects or disconnects.

## The gap: `disableClaudeAiConnectors`

Two first-party pages bear on this and neither resolves it.

**Pointing toward live reload** — <https://code.claude.com/docs/en/settings.md>, fetched 2026-08-17:

> Claude Code watches your settings files and reloads them when they change, so edits to most keys
> apply to the running session without a restart. This includes `permissions`, `hooks`, and
> credential helpers like `apiKeyHelper`. …
>
> A few keys are read once at session start and apply on the next restart instead:
>
> - `model`: use `/model` to switch mid-session
> - `outputStyle`: part of the system prompt, which is rebuilt on `/clear` or restart

`disableClaudeAiConnectors` is **not** on that restart-only list. Read literally, that implies it
reloads live.

**Pointing toward restart** — the key's own description says it stops connectors being
"**auto-fetched** or connected," and auto-fetch is a startup action. Combined with the prompt-caching
statement that MCP config changes "take effect only after a restart," the natural reading is that
setting it mid-session does not retroactively disconnect already-fetched connectors.

I could not find any page that states which is correct. I searched `mcp.md` for restart language and
found **zero** occurrences of "restart" on the entire page; the settings page's restart list is
exhaustive-sounding but does not mention MCP at all.

**Recommendation for the skill: treat `disableClaudeAiConnectors` as restart-required, and say so as
a conservative default rather than a documented fact.** If the skill wants in-session effect it
should drive the `/mcp` toggle, which is documented to work live. Being wrong in the conservative
direction costs the user one restart; being wrong the other way makes the skill report a context
saving that did not happen.

## Community signal (Tier 2, and dated)

GitHub issues corroborate that the in-session `/mcp` toggle does not persist across restarts in the
way users expect — e.g. anthropics/claude-code
[#73682](https://github.com/anthropics/claude-code/issues/73682) ("appear uninvited and nag every
startup"), [#83285](https://github.com/anthropics/claude-code/issues/83285) ("should be opt-in per
project … not enabled everywhere by default"), and
[#79564](https://github.com/anthropics/claude-code/issues/79564) ("default to enabled with no
per-server opt-in"), all fetched 2026-08-17 via the GitHub MCP server and all **open** as of that
date.

Treat these carefully. Several predate `disableClaudeAiConnectors` (v2.1.182) and the per-project
`disabledMcpServers` write-through, so their described workarounds are stale. They are evidence that
the ergonomics are contested, **not** evidence about current behavior. A Tier-2 search summary
encountered during this run asserted "setting `ENABLE_CLAUDEAI_MCP_SERVERS=false` in
`.claude/settings.json` under `env` has no effect" — that is an unverified community claim about a
configuration form the docs never endorse, and the skill should not repeat it.

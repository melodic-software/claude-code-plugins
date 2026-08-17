---
topic: system-prompt-agents-styles
section: custom-agents
abstract: Custom agents contribute name plus description only — roughly 100-190 tokens each — and no supported setting unloads one short of removing the plugin or file that provides it.
claims:
  - claim: "Only the subagent name and description reach the main session; the full definition and system prompt load at invocation, in the subagent's own context window."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/sub-agents#what-loads-at-startup"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: `/context` per-agent itemization, 122 tokens vs a 5,139-token definition file, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`permissions.deny: [\"Agent(<name>)\"]` blocks invocation but leaves the agent's description in the startup payload; the `Custom agents` total did not move."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: paired `claude --settings ... -p \"/context\"` runs with a verified control, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/sub-agents"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/prompt-caching"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "There is no settings key that disables an individual plugin-provided agent; plugin enablement is per-plugin via enabledPlugins, and --safe-mode removes all custom agents at once."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: `claude --safe-mode -p \"/context\"` — Custom agents row absent, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
produced_by: phase-2
---

# Custom agents

## Q5 — full definition, or name and description only?

**Name and description only. The probe cited in the dispatch prompt is correct.**

The sub-agents documentation states it directly under its own `#what-loads-at-startup` anchor
(<https://code.claude.com/docs/en/sub-agents>, fetched 2026-08-17). A non-fork subagent's *initial*
context — that is, at invocation, not at session start — contains:

> **System prompt**: the agent's own prompt plus environment details that Claude Code appends, not
> the full Claude Code system prompt. Custom subagents define theirs in the markdown body or
> `prompt` field.

…along with CLAUDE.md, a git-status snapshot, preloaded skills, and a sibling roster. All of that is
the **subagent's** context window. What the main session carries before invocation is the
delegation-decision material: the name and the description.

The arithmetic settles it independently (Tier 0, 2026-08-17):

| Quantity | Value |
|---|---|
| Twelve plugin agents, `/context` total | **1.5k** |
| Per-agent range | **94 – 191 tokens** |
| `discovery:researcher` `description:` field | 355 chars ≈ 88 tokens |
| `discovery:researcher` `/context` charge | **122 tokens** |
| `discovery:researcher` full file | 20,556 chars ≈ **5,139 tokens** |

122 against 5,139 is a factor of ~42. A definition-loading design could not produce that number.
The ~34-token gap between the description estimate and the charge is the per-agent envelope: the
scoped name (`discovery:researcher`), source, and separators.

**Consequences for the skill's advice:**

- The lever on agent cost is **description length**, not definition length. An author may write a
  20,000-character agent body at no startup cost and pay only for the sentence in `description:`.
- Twelve agents at 1.5k is ~0.15% of a 1M window. This is the smallest of the three contributors by
  a wide margin, and a trimming skill should say so rather than send an operator hunting there.
- The `Custom agents` row survives `--system-prompt` replacement unchanged, so it is genuinely a
  separate payload rather than system-prompt text.

## Q6 — can agents be disabled independently of the plugin providing them?

**No, not in the sense that matters for context.** Four candidate mechanisms, checked:

| Mechanism | Blocks invocation? | Removes the startup payload? |
|---|---|---|
| `permissions.deny: ["Agent(<name>)"]` | Yes (documented) | **No — measured, payload unchanged** |
| `--disallowedTools "Agent(<name>)"` | Yes (same rule surface) | Not measured; same mechanism, expect no |
| `CLAUDE_CODE_DISABLE_EXPLORE_PLAN_AGENTS=1` | Built-in Explore/Plan only | N/A — these never appear in `Custom agents` |
| `--safe-mode` / `CLAUDE_CODE_SAFE_MODE=1` | Yes, all of them | **Yes — row absent — but takes skills, plugins, hooks, MCP and CLAUDE.md too** |
| Disable the plugin (`enabledPlugins`, `claude plugin disable`) | Yes | Yes — **together with that plugin's skills, hooks, commands and MCP servers** |

The deny measurement is the load-bearing one, so it was controlled. Denying
`Agent(songwriting:object-writer)` left the `Custom agents` row at 1.5k with that agent still
itemized at 191 tokens. To rule out `--settings` being ignored, the same invocation shape was run
with `permissions.deny: ["WebFetch","WebSearch"]`, which moved `System tools (deferred)` 17.8k →
16.8k. The settings were applied; the agent payload genuinely does not respond to a deny rule.

This is consistent with the documented model rather than a bug: `prompt-caching` explains that a
bare-tool-name deny removes *that tool* from context, and `Agent(<name>)` is a scoped rule in the
argument position, not a tool-name rule. Scoped deny rules are described as leaving the prefix
intact.

**No settings key exists for per-agent disablement.** The `settings` reference carries `agent` (run
the main thread *as* an agent), `disableAgentView`, `strictPluginOnlyCustomization` (restrict
*sources* of agents), and `enabledPlugins` (per-plugin), and nothing that names an individual agent
for removal. Sources checked: the full `available-settings` table on `settings`, the `sub-agents`
page end to end, `env-vars`, `plugins-reference`, `plugins`, and `claude --help`. Not checked:
managed-settings schemas not published on those pages, and the Agent SDK's programmatic agent list.

**So the honest operator answer is: the only supported way to drop a specific agent's ~120 tokens is
to stop shipping or stop enabling the thing that provides it** — remove the file for a user/project
agent, or disable the whole plugin for a plugin agent. For a plugin maintainer, the actionable lever
is the one from Q5: write a shorter `description:`.

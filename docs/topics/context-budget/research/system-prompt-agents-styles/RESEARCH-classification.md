---
topic: system-prompt-agents-styles
section: classification
abstract: The deliverable — each of the three contributors classified as operator-addressable or vendor weight, with the split inside each one made explicit.
claims:
  - claim: "The system prompt is OPERATOR-ADDRESSABLE above a vendor floor: documented levers reduce it, and on Opus 5 an irreducible 2.8k residue remains under every supported setting short of full replacement."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: lever-by-lever `/context` probes, claude v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "Custom agents are VENDOR-WEIGHT-SHAPED for a consumer but OPERATOR-ADDRESSABLE for the plugin author, because the only lever on the payload is the description text the author writes."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: per-agent `/context` itemization and the deny control experiment, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/sub-agents"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "Output styles are fully OPERATOR-ADDRESSABLE and are the only one of the three that can be made to subtract more than it adds."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: paired custom-output-style `/context` runs, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: section-assembly branch in bin/claude.exe v2.1.232, 2026-08-17"
        tier: 0
        pool: "shipped Claude Code binary"
produced_by: phase-3
---

# The deliverable — classification

The brief expected three contributors with "no operator lever yet identified". **All three have
one.** The useful distinction turned out not to be addressable-vs-not, but *what each lever costs
you* and *who holds it*.

## Summary table

| Contributor | Classification | The lever | Measured effect | What it costs |
|---|---|---|---|---|
| **System prompt** | **OPERATOR-ADDRESSABLE above a vendor floor** | `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` | 5.1k → 1.8k (sonnet-5); **no-op on opus-5** | Nothing — tools, hooks, MCP, CLAUDE.md all stay |
| ↳ *the floor* | **VENDOR WEIGHT** | none | **2.8k on opus-5** under every supported setting | — |
| **Custom agents** | **OPERATOR-ADDRESSABLE only at authoring time** | shorten `description:` | ~94–191 tok/agent, 1.5k for 12 | Discoverability — Claude delegates off the description |
| ↳ *for a session consumer* | **effectively VENDOR WEIGHT** | none per-agent | deny rules measurably do **not** unload | — |
| **Output styles** | **OPERATOR-ADDRESSABLE, and net negative** | custom style, `keep-coding-instructions` unset | 5.2k → **4.2k** | The built-in software-engineering instructions |

## Per-contributor verdict

### 1. System prompt — OPERATOR-ADDRESSABLE, with a floor

Three documented levers genuinely reduce it, in descending order of collateral damage:

1. `--system-prompt` / `--system-prompt-file` — replaces everything. Measured **12 tokens**. Also
   discards the `<env>` block, git block and every built-in instruction. Print/scripted use.
2. `CLAUDE_CODE_SIMPLE=1` / `--bare` — minimal prompt, but simultaneously drops tools, skills,
   plugins, MCP, hooks and CLAUDE.md, and forces API-key auth.
3. **`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` — the clean one.** Shorter prompt and abbreviated tool
   descriptions, everything else retained. **5.1k → 1.8k measured.**

Two things commonly mistaken for levers, both refuted by measurement:

- `--append-system-prompt` **adds** — by documentation and by definition.
- `--exclude-dynamic-system-prompt-sections` **relocates**: −0.6k from the system prompt, +0.5k to
  the first user message, total unchanged. It is a prompt-cache optimization, and it is *ignored*
  when `--system-prompt` is set.
- `--safe-mode` does **not** touch the system prompt (5.1k → 5.1k), though it does remove agents and
  most skills.

`includeGitInstructions: false` saves ~2.4k, but the saving lands in the `System tools` row, not
`System prompt`.

**The floor is real.** On `claude-opus-5` the system prompt is 2.8k by default and no supported
setting reduced it further — `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` returned exactly the same number,
because v2.1.154 already made the lean prompt the default for that model generation. **For an
operator on Opus 5 or Fable 5, the 80%-class reduction is already spent and the system prompt is
vendor weight from there down.**

### 2. Custom agents — addressable by the author, not by the consumer

The payload is name + description, ~94–191 tokens each, 1.5k for twelve. A 20,556-character agent
file charged 122 tokens.

**For the consumer of a plugin: effectively vendor weight.** The one mechanism the docs present as
"disabling" an agent — `permissions.deny: ["Agent(<name>)"]` — was measured and **does not remove
the agent from the startup payload** (verified against a control that confirmed settings were
applied). The only ways to reclaim the tokens are blunt: `--safe-mode`, or disabling the whole
plugin, both of which take that plugin's skills, hooks and MCP servers with them. There is no
per-agent settings key.

**For the plugin author — which is who this skill is being written for — it is addressable, and the
lever is the `description:` line.** That is the entire startup cost of an agent. The body is free.

It is also the smallest of the three: 1.5k against a 9.9k skills payload and an 18.1k tools payload
in the same session. A trimming skill should rank it last and say why.

### 3. Output styles — OPERATOR-ADDRESSABLE, and the only net-negative lever found

Fully controllable through a documented settings key (`outputStyle`), at user, project, or managed
scope, with `/config` as the picker. Built-in styles add (~+0.3k for `Explanatory`).

**A custom style subtracts.** Because `keep-coding-instructions` defaults to `false`, a custom style
drops Claude Code's built-in software-engineering instructions — measured at **1.1k** — while adding
only its own text. Net **−1.0k** for a six-line style.

Ship that with its cost attached: those instructions govern change scoping, comment style and
verification. This is a behavior trade, and the docs scope it to cases where *"Claude isn't doing
software engineering at all."*

One conditional-load caveat for a plugin maintainer: a plugin output style with
`force-for-plugin: true` applies automatically whenever that plugin is enabled and **overrides the
user's `outputStyle` setting**. That is the one path by which a third party silently rewrites the
operator's system prompt — and, given the same `keep-coding-instructions` default, silently removes
the coding instructions too. Worth an explicit check in any inventory.

## What a skill built on this should do

1. **Read `/context` rows, but do not trust them as an attribution map.** Two levers verified here
   move tokens in a row other than the one an auditor would watch: `includeGitInstructions` lands in
   `System tools`, and output styles have no row of their own at all.
2. **Branch on the model before recommending `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT`.** It is worth ~3.3k
   on Sonnet 5 and exactly nothing on Opus 5.
3. **Report the agent payload, then tell the user not to bother** unless they author plugins — in
   which case point at `description:` length.
4. **Treat the custom-output-style trick as the headline lever and disclose its cost**, rather than
   as free headroom.
5. **Say plainly where the floor is.** On Opus 5, ~2.8k of system prompt is not addressable by any
   supported setting. An honest inventory names that as vendor weight and stops.

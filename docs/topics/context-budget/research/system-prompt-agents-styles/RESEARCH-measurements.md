---
topic: system-prompt-agents-styles
section: measurements
abstract: Tier-0 `/context` measurements of every candidate lever against a fixed baseline, showing which reduce the startup payload, which relocate it, and which do nothing.
claims:
  - claim: "`/context` reports `System prompt` and `Custom agents` as separate rows; there is no `Output style` row — an output style's cost is folded into the `System prompt` row."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude -p \"/context\"`, claude.exe v2.1.232, run 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/context-window"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` cuts the measured `System prompt` row from 5.1k to 1.8k on claude-sonnet-5, and is a no-op on claude-opus-5 where the lean prompt is already the default."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1 claude -p \"/context\"` and `--model opus` variant, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/changelog (v2.1.154, May 28 2026)"
        tier: 1
        pool: "Anthropic changelog (generated from anthropics/claude-code CHANGELOG.md)"
  - claim: "A custom output style with `keep-coding-instructions` at its default is NET NEGATIVE on the system prompt: measured 5.2k to 4.2k."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude --settings '{\"outputStyle\":\"terse-probe\"}' -p \"/context\"`, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`--exclude-dynamic-system-prompt-sections` relocates rather than reduces: `System prompt` 5.1k to 4.5k while `Messages` rises 591 to 1.1k, total unchanged."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude -p --exclude-dynamic-system-prompt-sections \"/context\"`, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`permissions.deny: [\"Agent(<name>)\"]` does NOT remove the agent from the `Custom agents` startup payload; a control deny of WebFetch/WebSearch confirms `--settings` was applied."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: paired `claude --settings ... -p \"/context\"` runs, v2.1.232, run 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/prompt-caching"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
produced_by: phase-2
---

# Measurements — Tier 0 `/context` probes

All probes: Claude Code **v2.1.232** (`claude --version`, 2026-08-17), invoked as
`claude -p "/context"` from the repo root unless noted. Default model resolved to `claude-sonnet-5`.
`/context` rounds to 0.1k, so treat deltas under ~100 tokens as noise.

**Read the baseline as a shape, not as your numbers.** `Skills` (9.9k) and `Custom agents` (1.5k)
here reflect this machine's 65 installed plugins. The System-prompt column is the portable finding.

## Baseline and single-lever deltas (repo root, sonnet-5)

| Probe | System prompt | System tools | Tools (deferred) | Custom agents | Skills | Total |
|---|---|---|---|---|---|---|
| **Baseline** | **5.1k** | 18.1k | 17.8k | 1.5k | 9.9k | **35.3k** |
| `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` | **1.8k** | 12.6k | 17.1k | 1.5k | 9.9k | **26.5k** |
| `--system-prompt "You are a helper."` | **12 tok** | 18.1k | 17.8k | 1.5k | 9.9k | — |
| `includeGitInstructions: false` | 5.1k | **15.7k** | 17.8k | 1.5k | 9.9k | **32.9k** |
| `--exclude-dynamic-system-prompt-sections` | 4.5k | 18.1k | 17.8k | 1.5k | 9.9k | **35.2k** |
| `outputStyle: "Explanatory"` (built-in) | **5.4k** | 18.1k | 17.8k | 1.5k | 9.9k | 35.6k |
| `--safe-mode` | 5.1k | 26.2k | 17.8k | **row absent** | 1.9k | 33.2k |
| `permissions.deny: ["Agent(songwriting:object-writer)"]` | 5.1k | 18.1k | 17.8k | **1.5k, agent still listed at 191** | 9.9k | — |
| *control:* `permissions.deny: ["WebFetch","WebSearch"]` | 5.1k | 18.1k | **16.8k** | 1.5k | 9.9k | — |

Three readings that matter, and one that does not resolve:

- **`--exclude-dynamic-system-prompt-sections` is net zero.** `System prompt` falls 0.6k and
  `Messages` rises 591 → 1.1k. The flag's own help text says exactly this ("Move per-machine
  sections … into the first user message"). It buys cross-machine prompt-cache reuse, not headroom.
- **`includeGitInstructions: false` saves ~2.4k, but not where you would look for it.** The
  `System prompt` row does not move; `System tools` drops 18.1k → 15.7k, because the built-in commit
  and PR workflow instructions ride in the Bash tool description. A skill that audits only the
  `System prompt` row will report this lever as doing nothing.
- **Denying an agent does not unload it.** The control run proves `--settings` was applied (deferred
  tools fell 1.0k), so the unchanged `Custom agents` row is a real negative: `Agent(...)` deny rules
  gate invocation, not payload.
- **Unexplained:** `--safe-mode` *raises* `System tools` 18.1k → 26.2k. Recorded as measured; no
  first-party source found that accounts for it. Do not build on this number. See gaps.

## Model dependence — the lean prompt is already the default on Opus 5

| Probe | System prompt | System tools | Tools (deferred) | Total |
|---|---|---|---|---|
| `--model opus` (claude-opus-5), default | **2.8k** | 12.5k | 15.4k | 27.4k |
| `--model opus` + `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` | **2.8k** | 12.5k | 15.4k | — |

Identical. The changelog explains why: *"The lean system prompt is now the default for all models
except Haiku, Sonnet, and Opus 4.7 and earlier"* (v2.1.154, May 28 2026,
<https://code.claude.com/docs/en/changelog>, fetched 2026-08-17).

**So the largest system-prompt lever available is a lever only on the models the lean default
excludes.** On Opus 5 / Fable 5 the reduction is already spent and the env var returns nothing.

## Output styles — the net-negative case

Run from a scratch working directory (not the repo), so this baseline is 5.2k rather than 5.1k.
Compare only within this block.

| Probe | System prompt | Delta vs this baseline |
|---|---|---|
| **Baseline, no output style** | **5.2k** | — |
| Custom style, `keep-coding-instructions` absent (default `false`) | **4.2k** | **−1.0k** |
| Custom style, `keep-coding-instructions: true` | 5.3k | +0.1k |

The probe style was six lines ("Answer tersely."), roughly 20 tokens. The 1.1k spread between the
two custom-style runs is the size of Claude Code's built-in software-engineering instructions block,
which a custom style drops unless `keep-coding-instructions: true` is set.

**This is the finding a trimming skill should care about most**: an output style is normally
described as something that *adds* to the system prompt, and by default a custom one *subtracts*
about 1k net.

## Per-agent payload — description-only, confirmed by arithmetic

`/context` itemizes each agent. Twelve plugin agents totalled **1.5k**, individually **94–191
tokens**.

Against one of them, `plugins/discovery/agents/researcher.md`:

| Quantity | Value |
|---|---|
| `description:` frontmatter field | 355 chars ≈ 88 tokens |
| `/context` charge for this agent | **122 tokens** |
| Full agent file | 20,556 chars ≈ 5,139 tokens |
| Ratio charged : full file | **~1 : 42** |

The charge tracks the description plus a small per-agent envelope (name, source), not the body.
This corroborates the 12-agents-at-1.5k probe named in the dispatch prompt.

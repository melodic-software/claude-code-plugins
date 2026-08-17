---
topic: system-prompt-agents-styles
section: system-prompt-levers
abstract: Every candidate system-prompt lever checked one by one — which exist, which are documented, and which actually reduce rather than add or relocate.
claims:
  - claim: "`--append-system-prompt` exists and is documented, and it only ADDS: the docs describe it as appending to the default prompt without removing anything."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude --help`, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`--system-prompt` exists, is documented as replacing the entire system prompt, and measured at 12 tokens replacing a 5.1k default — the largest reduction available, at the cost of every built-in instruction."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude --system-prompt \"You are a helper.\" -p \"/context\"`, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/headless"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "`CLAUDE_CODE_SIMPLE=1` is NOT undocumented: it has its own row in the official env-vars reference and a documented CLI equivalent, `--bare`."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: `claude --help` --bare entry, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
  - claim: "`--safe-mode` disables customizations including custom agents and output styles, but measurably does NOT shrink the system prompt itself."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: `claude --safe-mode -p \"/context\"` vs baseline, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/cli-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "Anthropic's 80%-removal statement corresponds to a shipped change recorded first-party in the changelog as the lean system prompt becoming default at v2.1.154, and the operator-facing control is CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT."
    confidence: MEDIUM
    tiers: [1, 2]
    sources:
      - url: "https://code.claude.com/docs/en/changelog (v2.1.154, May 28 2026)"
        tier: 1
        pool: "Anthropic changelog (generated from anthropics/claude-code CHANGELOG.md)"
      - url: "https://code.claude.com/docs/en/env-vars"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://github.com/anthropics/claude-code/issues/81331"
        tier: 2
        pool: "anthropics/claude-code issue tracker (community)"
produced_by: phase-2
---

# Is there a supported lever that REDUCES the system prompt?

**Yes — three of them, plus two that are commonly mistaken for levers.** Answering Q2 flag by flag.

## Q2 — the checklist, one row per candidate

| Candidate | Exists? | Documented? | Effect | Measured |
|---|---|---|---|---|
| `--append-system-prompt` | Yes | Yes, `cli-reference` | **ADDS only** | not measured (add-only by definition) |
| `--system-prompt` | Yes | Yes, `cli-reference` | **REPLACES entirely** | 5.1k → **12 tokens** |
| Output style as replacement | Partly — see below | Yes, `output-styles` | **ADDS, but can subtract more than it adds** | 5.2k → **4.2k** |
| `claude --safe-mode` | Yes | Yes, `cli-reference` + `env-vars` | Disables customizations; **does not touch the system prompt** | 5.1k → **5.1k** |
| `CLAUDE_CODE_SIMPLE=1` | Yes | **Yes** — `env-vars`, and `--bare` in `cli-reference` | REDUCES, but by gutting the session | not isolated |
| **`CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1`** | Yes | Yes, `env-vars` | **REDUCES, and only that** | 5.1k → **1.8k** (sonnet-5) |

### `--append-system-prompt` — ADD only

`cli-reference` (fetched 2026-08-17): *"Append custom text to the end of the default system
prompt."* The `output-styles` comparison table says it plainly: *"Appends to the system prompt
without removing anything."* There is a `--append-system-prompt-file` twin, a settings key
`appendSystemPrompt`, and a subagent-scoped `--append-subagent-system-prompt`. All additive.

### `--system-prompt` — REPLACE, and it takes the env and git blocks with it

*"Replace the entire system prompt with custom text"* (`cli-reference`). Measured: the `System
prompt` row fell to **12 tokens**, so the `<env>` block, the git block and the built-in instructions
all go. Confirmed structurally in the binary, where a supplied prompt takes an exclusive branch past
the default section assembly.

Two documented consequences for a trimming skill:

- `--system-prompt` and `--system-prompt-file` are mutually exclusive; append flags combine with
  either (`cli-reference`).
- **`--exclude-dynamic-system-prompt-sections` is ignored when `--system-prompt` is set** — stated
  in `cli-reference` and visible in the binary's branch structure.

`Custom agents` (1.5k) and `Skills` (9.9k) survived this replacement unchanged. They are separate
payloads, not system-prompt content.

### `--safe-mode` — a customization switch, not a prompt switch

Its own help text (Tier 0, `claude --help` v2.1.232): *"Start with all customizations (CLAUDE.md,
skills, plugins, hooks, MCP servers, custom commands and agents, output styles, workflows, custom
themes, keybindings, and more) disabled … Sets `CLAUDE_CODE_SAFE_MODE=1`."*

Measured: `System prompt` **unchanged at 5.1k**. What it did remove was the entire `Custom agents`
row and most of `Skills` (9.9k → 1.9k). So it is a real lever for two of this report's three
subjects and not a lever for the third.

### `CLAUDE_CODE_SIMPLE=1` — documented, and the brief's premise here is wrong

The brief asked about this as "the undocumented `CLAUDE_CODE_SIMPLE=1`". It is **documented**, with
its own row in the official env-var reference (fetched 2026-08-17):

> Set to `1` to run with a minimal system prompt and only the Bash, file read, and file edit tools.
> MCP tools from `--mcp-config` are still available. Disables auto-discovery of hooks, skills,
> plugins, MCP servers, auto memory, and CLAUDE.md. OAuth tokens and keychain credentials are not
> read … Equivalent to passing `--bare`.

`--bare` is its documented CLI equivalent and appears in `claude --help` and `cli-reference`. It
does reduce the system prompt, but by removing tools, skills, plugins, MCP and CLAUDE.md at the same
time, and by forcing API-key auth. It is a scripted-invocation mode, not a trim knob for an
interactive session.

### `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT=1` — the one clean reduce lever

Not in the brief's candidate list, and it is the answer to it. From `env-vars` (fetched
2026-08-17):

> Set to `1` to use a shorter system prompt and abbreviated tool descriptions on any model. Set to
> `0`, `false`, `no`, or `off` to opt out even on models where the experiment or server
> configuration would otherwise enable it. **The full tool set, hooks, MCP servers, and CLAUDE.md
> discovery remain enabled.**

Measured on claude-sonnet-5: `System prompt` **5.1k → 1.8k**, `System tools` 18.1k → 12.6k, session
total 35.3k → 26.5k. Nothing else was given up.

**The catch, and it is a big one.** On `claude-opus-5` the flag changed nothing (2.8k either way),
because the reduction is already the default there — see Q3.

## Q3 — the 80% statement and whether it implies operator control

**The blog post could not be fetched.** `https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models`
returned HTTP 403 to direct `curl`, again with a browser User-Agent, and `claude.com` is blocked
outright by this session's egress proxy for WebFetch. Escalation was walked to its end (direct
fetch → alternate UA → synthesis tool domain-filtered to `claude.com`). The synthesis pass returned
claim-bearing text attributed to the post — *"removed over 80% of Claude Code's system prompt for
more advanced models … with no measurable loss on their coding evaluations"* — but **that is a
Tier-2 synthesis of a page nobody in this run read.** It is recorded as a gap, not as a primary.

**What is first-party and reachable is better anyway.** The same change has a changelog entry:

> **v2.1.154 (May 28, 2026)** — "The lean system prompt is now the default for all models except
> Haiku, Sonnet, and Opus 4.7 and earlier."
> <https://code.claude.com/docs/en/changelog>, fetched 2026-08-17

Read together with the `env-vars` entry that speaks of *"models where the experiment or server
configuration would otherwise enable it"*, and with the measurements, the picture is consistent and
first-party sourced:

- The 80%-class reduction is **shipped and on by default** for the Claude 5 generation.
- **It therefore implies operator-facing control in a narrow and slightly disappointing sense.**
  `CLAUDE_CODE_SIMPLE_SYSTEM_PROMPT` is a real, documented, two-way switch — but for an operator
  already on Opus 5 or Fable 5 the saving is spent, and the switch's remaining use is *opting out*
  (`=0`) to get the longer prompt back. Its use as a *reduction* lever applies to Sonnet, Haiku, and
  Opus 4.7-and-earlier sessions.

Community corroboration that the removal shipped and was felt:
<https://github.com/anthropics/claude-code/issues/81331> ("Restore the system prompt: Opus follows
instructions much worse now", 2026-07-26). No maintainer reply naming a control was visible on the
page fetched.

## The residual floor

With every documented lever applied short of `--system-prompt`, the system prompt does not reach
zero. On Opus 5 it sits at **2.8k** and no supported setting moved it. That residue — the `<env>`
block, model identity, the git block, and the lean instruction core — is the vendor floor.

---
topic: system-prompt-agents-styles
section: output-styles
abstract: An output style modifies the system prompt directly, and a custom one is net negative by default because it drops the built-in software-engineering instructions unless told to keep them.
claims:
  - claim: "An output style modifies the system prompt directly: its instructions are appended to the end, and a custom style omits Claude Code's built-in software-engineering instructions unless keep-coding-instructions is true."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: section-assembly branch extracted from bin/claude.exe v2.1.232, 2026-08-17"
        tier: 0
        pool: "shipped Claude Code binary"
      - url: "https://code.claude.com/docs/en/prompt-caching"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "A minimal custom output style at the default keep-coding-instructions reduced the measured system prompt from 5.2k to 4.2k, while the same style with keep-coding-instructions true measured 5.3k."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "Tier 0: three paired `/context` runs from one working directory, v2.1.232, 2026-08-17"
        tier: 0
        pool: "local tool output"
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
  - claim: "Output style is selected by the outputStyle settings key or the /config picker; the standalone /output-style command was deprecated in v2.1.73 and removed in v2.1.91."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/settings"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/changelog"
        tier: 1
        pool: "Anthropic changelog (generated from anthropics/claude-code CHANGELOG.md)"
  - claim: "A plugin-provided output style does not apply unconditionally unless it sets force-for-plugin, which applies it whenever the plugin is enabled and overrides the user's outputStyle setting."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/output-styles"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "https://code.claude.com/docs/en/plugins-reference"
        tier: 1
        pool: "Anthropic docs (code.claude.com)"
      - url: "Tier 0: `/context` with no style selected shows no output-style contribution, 2026-08-17"
        tier: 0
        pool: "local tool output"
produced_by: phase-2
---

# Output styles

## Q7 — what it is, what it contributes, add or replace

An output style *"changes how Claude responds, not what Claude knows"* and *"directly modif[ies]
Claude Code's system prompt"* (<https://code.claude.com/docs/en/output-styles>, fetched
2026-08-17). It is a markdown file: frontmatter, then instructions.

**It does both — and which one dominates is decided by one frontmatter field.** The docs, verbatim:

> - Claude Code adds each output style's custom instructions to the end of the system prompt.
> - All output styles trigger reminders for Claude to adhere to the output style instructions during
>   the conversation.
> - Custom output styles leave out Claude Code's built-in software engineering instructions, such as
>   how to scope changes, write comments, and verify work, unless `keep-coding-instructions` is set
>   to `true`.

`keep-coding-instructions` **defaults to `false`** (frontmatter table, same page). The same
conditional is visible in the shipped binary, where the coding-instructions section is emitted only
when no output style is active or the active style has `keepCodingInstructions === true` (Tier 0,
v2.1.232, 2026-08-17).

### The documented token implication, and the measured one

The docs state the additive half only:

> Token usage depends on the style. Adding instructions to the system prompt increases input tokens,
> though prompt caching reduces this cost after the first request in a session. The built-in
> Explanatory and Learning styles produce longer responses than Default by design, which increases
> output tokens.

The subtractive half is documented as behavior but never costed. Measured (Tier 0, three runs from
one working directory, 2026-08-17):

| Configuration | `System prompt` |
|---|---|
| No output style | 5.2k |
| Built-in `Explanatory` *(measured separately, repo baseline 5.1k)* | 5.4k (**+0.3k**) |
| Custom style, `keep-coding-instructions` absent | **4.2k (−1.0k)** |
| Custom style, `keep-coding-instructions: true` | 5.3k (+0.1k) |

The probe style was six lines. The **1.1k gap** between the two custom-style runs is the size of the
built-in software-engineering instructions block.

**So: built-in styles add. A custom style is net negative by default, by about 1k.** This inverts
the intuition a trimming skill would otherwise encode, and it is the single most useful finding in
this run for that skill.

The honest caveat to ship alongside it: those 1.1k of instructions are how Claude scopes changes,
writes comments, and verifies work. Dropping them to reclaim 1k of a 200k-or-1M window is a
behavior trade, not free headroom, and the docs say to leave them out only *"when Claude isn't doing
software engineering at all"*. A skill should present this as a lever with a named cost, not as a
recommended default.

Two further placement facts:

- **There is no `Output style` row in `/context`.** The cost lands inside `System prompt`. An
  inventory keyed on row names will miss it entirely.
- **It is fixed at session start.** *"Output style is part of the system prompt, which Claude Code
  reads once at session start. Changes take effect after `/clear` or a new session."* Changing it
  invalidates the whole cached prefix (`prompt-caching`).
- **It does not reach subagents.** *"a subagent runs its own system prompt, so your output style
  doesn't shape its responses"* — except a fork, which inherits the parent's full system prompt.

## Q8 — enabling, disabling, and plugin-provided styles

### Enable / disable

- **Settings key `outputStyle`**, e.g. `{"outputStyle": "Explanatory"}`. The `/config` picker writes
  it to `.claude/settings.local.json`.
- **The standalone `/output-style` command is gone** — *"deprecated in v2.1.73 and removed in
  v2.1.91"*. A skill that tells a user to run it will be wrong on any current version.
- **Disable** = select `Default`, or remove the `outputStyle` key. `--safe-mode` also prevents
  output styles from loading (its help text names them explicitly).
- Files live at `~/.claude/output-styles`, `.claude/output-styles`, and the managed-policy
  directory. Project styles load from every `.claude/output-styles/` between cwd and the repo root,
  nearest wins.

### Does a plugin-provided output style load unconditionally?

**No — unless it opts in, and then yes.** Plugins ship them in an `output-styles/` directory
(`plugins-reference`, `outputStyles` manifest key). Availability is not application: a plugin style
is one more selectable option, and with none selected `/context` showed no output-style
contribution.

The exception is a documented frontmatter field, `force-for-plugin`:

> Plugin output styles only: apply this style automatically whenever the plugin is enabled, without
> requiring users to select it. **Overrides the user's `outputStyle` setting.** If multiple enabled
> plugins set this, Claude Code uses the first one loaded. *(Default: `false`)*

This is the one place in this report where a *third party* silently changes the operator's system
prompt. For a plugin maintainer auditing startup payload, `force-for-plugin: true` in any enabled
plugin is worth surfacing by name: it applies without selection, overrides the user's setting, and —
because `keep-coding-instructions` also defaults to `false` — can silently remove the built-in
software-engineering instructions from the session.

**Not verified:** whether a `force-for-plugin` style is itemized anywhere in `/context`, and the
resolution order behind "first one loaded". No plugin in this environment sets the flag, so it could
not be measured.

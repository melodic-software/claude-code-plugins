---
topic: bundled-skills
section: context-cost
abstract: Only name + description (plus whenToUse) load per skill each turn, capped per-entry at 1,536 chars and in aggregate at 1% of the context window; /context's Skills row reports the post-budget listing size, which since v2.1.196 matches what the model actually receives.
claims:
  - claim: "In a regular session only skill descriptions load into context; full SKILL.md content loads only on invocation. Subagents with preloaded skills differ — full content is injected at startup."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/skills.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (docs, HTML render)"
      - url: "local binary v2.1.232: listing text fn Yer(e)=e.whenToUse?`${e.description} - ${e.whenToUse}`:e.description"
        tier: 0
        pool: "Anthropic (shipped artifact)"
  - claim: "Per-skill always-loaded cost is name.length + 4 + min(descriptionText.length, skillListingMaxDescChars); a name-only entry costs name.length + 2."
    confidence: HIGH
    tiers: [0, 1]
    sources:
      - url: "local binary v2.1.232: entryLen:b.name.length+4+S where S=Math.min(v.length,a); name-only branch entryLen:b.name.length+2"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/skills.md — 'each entry's combined text is capped at 1,536 characters regardless of budget'"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/settings.md — skillListingMaxDescChars"
        tier: 1
        pool: "Anthropic (docs)"
  - claim: "The listing budget defaults to 1% of the context window, set by skillListingBudgetFraction (default 0.01) or overridden as a fixed char count by SLASH_COMMAND_TOOL_CHAR_BUDGET (fallback 8,000 chars)."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/settings.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "https://code.claude.com/docs/en/env-vars.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local binary v2.1.232: MJ(process.env.SLASH_COMMAND_TOOL_CHAR_BUDGET)>0 gates budgetFromEnv"
        tier: 0
        pool: "Anthropic (shipped artifact)"
  - claim: "/context's Skills row reports the size of the listing AFTER the budget is applied; before v2.1.196 it counted full description text and could read several times larger than the budget."
    confidence: HIGH
    tiers: [1, 0]
    sources:
      - url: "https://code.claude.com/docs/en/skills.md"
        tier: 1
        pool: "Anthropic (docs)"
      - url: "local binary v2.1.232: skills:{totalSkills,includedSkills,tokens,skillFrontmatter} producer struct"
        tier: 0
        pool: "Anthropic (shipped artifact)"
      - url: "https://code.claude.com/docs/en/commands.md — /context row"
        tier: 1
        pool: "Anthropic (docs)"
produced_by: phase-2
---

# What actually loads per skill, and what /context counts

## Q2 — name + description only. Official statement, verbatim

> "In a regular session, skill descriptions are loaded into context so Claude knows what's
> available, but full skill content only loads when invoked. [Subagents with preloaded
> skills](/docs/en/sub-agents#preload-skills-into-subagents) work differently: the full skill
> content is injected at startup."
> — <https://code.claude.com/docs/en/skills>, fetched 2026-08-17

And the section that owns the cost question:

> "Claude Code loads a listing of skill names and descriptions into context so Claude knows what's
> available. The listing always contains every skill name, but if you have many skills, Claude Code
> shortens descriptions to fit the listing's character budget… The budget scales at 1% of the
> model's context window. When the listing overflows, Claude Code drops descriptions starting with
> the skills you invoke least, so the skills you use most keep their full text."
> — <https://code.claude.com/docs/en/skills.md> §"Skill descriptions are cut short", fetched
> 2026-08-17

The frontmatter table on the same page states the per-skill rule as a matrix:

| Frontmatter | You can invoke | Claude can invoke | When loaded into context |
|---|---|---|---|
| (default) | Yes | Yes | Description always in context, full skill loads when invoked |
| `disable-model-invocation: true` | Yes | No | **Description not in context**, full skill loads when you invoke |
| `user-invocable: false` | No | Yes | Description always in context, full skill loads when invoked |

## The exact cost formula — Tier 0, from the shipped binary

The listing text per skill is **not** just `description`. From v2.1.232:

```js
function Yer(e){ return e.whenToUse ? `${e.description} - ${e.whenToUse}` : e.description }
```

and the per-entry length:

```js
// normal entry
{ cmd: b, descLen: S, entryLen: b.name.length + 4 + S }   // S = Math.min(text.length, maxDescChars)
// name-only entry (collapsed)
{ cmd: b, descLen: 0, entryLen: b.name.length + 2 }
```

Total = sum of `entryLen` + `(count - 1)` separator chars.

**So the documented per-skill always-loaded cost is:**

> `name.length + 4 + min(len(description [+ " - " + whenToUse]), skillListingMaxDescChars)` characters

with `skillListingMaxDescChars` defaulting to **1,536 characters** per entry
(<https://code.claude.com/docs/en/skills.md>: "each entry's combined text is capped at 1,536
characters regardless of budget. The cap is configurable with `skillListingMaxDescChars`").

Collapsing an entry to `name-only` therefore drops its cost to `name.length + 2` — this is the
precise lever the caller's trim tool wants.

**There is no published per-skill token figure.** The docs give characters, not tokens; the binary
converts with a `bytesPerToken` divisor. Any token number is an estimate. A widely-circulated
secondary figure of "~75–150 tokens per skill in the listing" appears on
<https://claudefa.st/blog/guide/mechanics/skill-listing-budget> (surfaced via WebSearch
2026-08-17) — **Tier 2, uncorroborated by any first-party source, do not ship it as fact.**

## The aggregate budget

| Lever | Exact spelling | Kind | Default | Source |
|---|---|---|---|---|
| Listing budget fraction | `skillListingBudgetFraction` | settings.json | `0.01` (1% of context window) | settings.md, fetched 2026-08-17 |
| Fixed char budget override | `SLASH_COMMAND_TOOL_CHAR_BUDGET` | env var | unset; fallback 8,000 chars | env-vars.md, fetched 2026-08-17 |
| Per-entry description cap | `skillListingMaxDescChars` | settings.json | `1536` | skills.md + settings.md, fetched 2026-08-17 |

> "**Default**: `0.01`. Fraction of the model's context window reserved for the skill listing
> Claude sees each turn, so the default reserves 1%. When the listing exceeds the budget,
> descriptions for the least-used skills are dropped and only their names are listed, so Claude can
> still invoke them but can't see what they do."
> — <https://code.claude.com/docs/en/settings.md>, fetched 2026-08-17

> "Override the character budget for skill metadata shown to the Skill tool. The budget scales
> dynamically at 1% of the context window, with a fallback of 8,000 characters. Legacy name kept
> for backwards compatibility"
> — <https://code.claude.com/docs/en/env-vars.md>, fetched 2026-08-17

### Bundled skills are privileged inside the budget — important for a trim tool

Tier 0, v2.1.232: when the listing overflows, the truncation pass partitions entries with

```js
let f = (b) => dpv(b.cmd) || n?.has(b.cmd.name);   // dpv = type==="prompt" && source==="bundled"
```

Entries matching `f` keep their **full** `entryLen`; only the others are collapsed toward
name-only. **Bundled skills are therefore protected from budget-driven truncation, and user/project
skills are collapsed first.** A tool that measures "what did the budget drop?" will see user skills
losing descriptions while bundled ones keep theirs — the bundled payload is a floor, not a
sacrificial buffer. This is the strongest single argument for treating bundled skills as a
deliberate trim target rather than assuming the budget handles it.

## Q5 — what /context's "Skills" row counts

Tier 0, v2.1.232: the `/context` producer emits

```js
skills: ae > 0 ? { totalSkills, includedSkills, tokens: ae, skillFrontmatter } : undefined
```

and the row is pushed as `{name:"Skills", tokens: ae}`. Per-skill entries are mapped with a source
label where `h === "bundled" ? "built-in" : h` — so **bundled skills appear in the row's breakdown
under the label "built-in"**, alongside sources like `userSettings`, `plugin`, and `syncedSkills`.

The authoritative statement of what the number means:

> "The Skills row in `/context` reports the size of the listing after the budget is applied, so it
> matches what the model receives. Before v2.1.196, the row counted the full text of every
> description and could show a value several times larger than the configured budget."
> — <https://code.claude.com/docs/en/skills.md>, fetched 2026-08-17

**So: the Skills row counts the post-budget, post-truncation skill *listing* (names + capped
descriptions) — not SKILL.md bodies, and not invoked-skill content.** Invoked skill bodies land in
the conversation as ordinary messages, not in this row. On v2.1.195 and earlier the row
over-reports. The binary also exposes a `structured twin of the /context report` for programmatic
consumption, with the note "Omitted when no skills contribute tokens" — relevant if the caller's
tool wants to read the breakdown rather than scrape the TUI.

`/doctor` is the officially suggested estimator: "Run `/doctor` for an estimate of the listing's
context cost and its biggest contributors." An overflow also writes a warning to the debug log,
visible with `--debug`.

---
topic: skill-architecture-guidance
section: description-trigger
abstract: There is no URL-pattern activation field — `paths:` is file globs — so description keyword matching is the entire mechanism by which an x.com URL can reach the skill, bounded by two distinct caps (1,024 spec validation vs 1,536 Claude Code listing).
claims:
  - claim: "No URL-pattern activation mechanism exists; the `paths:` frontmatter field takes file globs, not URLs."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "The description field is what Claude uses to select a skill from potentially 100+ available skills."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "Two distinct caps apply: 1,024 chars on `description` as spec frontmatter validation (not enforced by Claude Code), and 1,536 chars on `description`+`when_to_use` combined as Claude Code listing truncation."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "The shared skill-listing budget scales at 1% of the model's context window and can strip descriptions entirely."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "A changelog entry stating 2% is superseded by the current docs stating 1%."
    confidence: MEDIUM
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Anthropic's own xlsx skill is the working model for multi-format triggering: enumerate every format literally, then close with an explicit negative boundary."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "Descriptions must be written in third person; inconsistent point-of-view causes discovery problems."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
produced_by: phase-2-targeted
---

# The description field as trigger mechanism

**Verdict: description keyword matching is the ONLY trigger mechanism for URL shapes. There is no
URL-pattern activation field. `paths:` is file globs, not URLs.**

This matters more than any engine work: leave the description YouTube-only and an X URL never reaches
the skill, however correct the adapters are.

## 1. Two distinct caps — do not conflate them

| Cap | Scope | Binds when |
|---|---|---|
| **1,024 chars** on `description` alone | Agent Skills spec frontmatter **validation**. Enforced on claude.ai upload, the Skills API, and `package_skill.py`. **Not enforced by Claude Code.** | only if claude.ai / routine / API portability is wanted |
| **1,536 chars** on `description` + `when_to_use` **combined** | Claude Code skill-**listing** truncation. Configurable via `skillListingMaxDescChars`. | today, for a plugin skill staying in Claude Code |

`code.claude.com/docs/en/skills`:

> Put the key use case first: the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing to reduce context usage.

> `when_to_use` … Additional context for when Claude should invoke the skill, such as trigger phrases or example requests. Appended to `description` in the skill listing and counts toward the 1,536-character cap.

The frontmatter-validation ceiling is the spec's, and exceeding it is a **hard error** on the
non-Claude-Code distribution paths:

> Unexpected key(s) in SKILL.md frontmatter: argument-hint. Allowed properties are: allowed-tools, compatibility, description, license, metadata, name

(That error is for unexpected keys, but it illustrates that those paths validate strictly rather than
ignoring violations.)

## 2. Above both sits a shared budget that can strip the description entirely

> Claude Code loads a listing of skill names and descriptions into context so Claude knows what's available. The listing always contains every skill name, but if you have many skills, Claude Code shortens descriptions to fit the listing's character budget, which can strip the keywords Claude needs to match your request. **The budget scales at 1% of the model's context window.** When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so the skills you use most keep their full text.

Raisable via `skillListingBudgetFraction` or `SLASH_COMMAND_TOOL_CHAR_BUDGET`. Freeable via
`skillOverrides` entries set to `"name-only"` — though note **plugin skills are not affected by
`skillOverrides`**.

> **Supersession flag:** changelog v2.1.32 (Feb 2026) states the budget is 2% of context. Current
> `skills.md` states 1%. **Use 1%** — the changelog figure is stale.

## 3. How to write one that triggers on multiple distinct URL shapes

Documented mechanics:

- **Third person, always.** *"The description is injected into the system prompt, and inconsistent point-of-view can cause discovery problems."* Good: *"Processes Excel files and generates reports."* Avoid: *"I can help you process Excel files."*
- **Be specific and include key terms** — both what it does and the specific triggers/contexts for when to use it.
- **Undertriggering is the default failure.** `skill-creator/SKILL.md`: *"currently Claude has a tendency to 'undertrigger' skills… please make the skill descriptions a little bit 'pushy'."*
- **Near-misses are the highest-value negative tests.** agentskills.io: *"The most valuable negative test cases are near-misses — queries that share keywords or concepts with your skill but actually need something different."* / *"Add specificity about what the skill does *not* do, or clarify the boundary between this skill and adjacent capabilities."*

**The direct model is Anthropic's own `xlsx` description** — it enumerates five formats **literally**
and closes with an explicit negative boundary (verbatim, complete):

> Use this skill any time a spreadsheet file is the primary input or output. This means any task where the user wants to: open, read, edit, or fix an existing .xlsx, .xlsm, .xltx, .csv, or .tsv file… Trigger especially when the user references a spreadsheet file by name or path — even casually (like "the xlsx in my downloads")… **Do NOT trigger when the primary deliverable is a Word document, HTML report, standalone Python script, database pipeline, or Google Sheets API integration, even if tabular data is involved.**

`docx` follows the same shape: *"…Do NOT use for PDFs, spreadsheets, Google Docs, or general coding tasks unrelated to document generation."*

**Applied here:** enumerate `youtube.com`, `youtu.be`, `x.com`, `twitter.com` literally, plus the
natural-language triggers, plus a `Do NOT` clause that preserves the existing `course-digest`
boundary.

## 4. Budget arithmetic for this skill

The current description spends **~640 of 1,536 chars**. Adding the X hosts and keeping the negative
boundary fits comfortably under 1,536, but **will press against 1,024** if claude.ai / routine
portability is ever wanted.

Local constraint to respect: `skill-quality:check` diffs trigger keywords against HEAD and FAILs on
dropped ones, so the widened description must **retain** `youtube`, `youtu.be`, and `/youtube-digest`
tokens while adding X's.

## 5. If the widened description over-fires

`skills.md`, "Skill triggers too often":

> 1. Make the description more specific
> 2. Add `disable-model-invocation: true` if you only want manual invocation

And the inverse, "Skill doesn't trigger": check the description includes keywords users would naturally
say; make the description more specific; try rephrasing to match it.

Note the `/skills` tooling also offers **description tuning** — *"generates should-trigger and
should-not-trigger prompts, measures the hit rate, and proposes description edits when the skill
activates on the wrong requests"* — which is the empirical loop this section cannot substitute for.
Whether the widened description over-triggers on non-video `x.com` URLs is **not researched** here; it
needs eval runs, not docs.

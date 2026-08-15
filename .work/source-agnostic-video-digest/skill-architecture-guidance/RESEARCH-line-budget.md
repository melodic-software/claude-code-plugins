---
topic: skill-architecture-guidance
section: line-budget
abstract: No authoritative source states a 200-line SKILL.md target; the binding official constraint is `< 5,000 tokens`, which the current 410-line/38KB SKILL.md violates at roughly 2x while passing the 500-line cap.
claims:
  - claim: "Official guidance states 500 lines as the SKILL.md body cap, in three independent Anthropic-controlled surfaces."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "The Agent Skills specification recommends a SKILL.md body under 5,000 tokens, alongside the 500-line cap."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://agentskills.io/specification"
        tier: 1
        pool: "agentskills.io (Anthropic-authored standard, multi-vendor governed)"
      - url: "https://agentskills.io/skill-creation/best-practices"
        tier: 1
        pool: "agentskills.io (Anthropic-authored standard, multi-vendor governed)"
  - claim: "Anthropic's OWN documentation states no token figure for the SKILL.md body; the 5,000-token recommendation rests on a single publishing pool."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "The number 5,000 is independently corroborated by Claude Code's per-skill compaction re-attachment cap, a separate Anthropic pool."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "No authoritative source states a 200-line SKILL.md target."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
      - url: "https://agentskills.io/specification"
        tier: 1
        pool: "agentskills.io (Anthropic-authored standard, multi-vendor governed)"
  - claim: "The local LINE_SOFT_CAP=200 is an uncited tunable whose two neighbours both match upstream exactly."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:plugins/skill-quality/scripts/check-skill.sh:175-177"
        tier: 0
        pool: "local repository (direct file read this turn)"
  - claim: "The current youtube-digest SKILL.md is 410 lines / 38,436 chars / 4,723 words, roughly 2x the 5,000-token recommendation."
    confidence: HIGH
    tiers: [0]
    sources:
      - url: "file:plugins/knowledge/skills/youtube-digest/SKILL.md"
        tier: 0
        pool: "local repository (wc/awk output this turn)"
  - claim: "The 200-line figure circulates as a community convention that misattributes itself to Anthropic."
    confidence: MEDIUM
    tiers: [2]
    sources:
      - url: "https://skills.rest/skill/compress-skill"
        tier: 2
        pool: "skills.rest (third-party skill library)"
produced_by: phase-3-falsification
---

# Line budgets — the decision-blocking question

**Verdict: no authoritative source states a ~200-line SKILL.md target. It is community convention.
The binding official constraint is not a line count at all — it is `< 5,000 tokens`, and the current
file violates it while passing the 500-line cap.**

All fetches 2026-08-14, via `curl -sL` into raw markdown. WebFetch's summarizer was observed
paraphrasing while presenting text as verbatim, so no quote here came through it.

## 1. The authoritative figures, verbatim

**Agent Skills specification** — <https://agentskills.io/specification>, "Progressive disclosure",
L247–251:

> 1. **Metadata** (~100 tokens): The `name` and `description` fields are loaded at startup for all skills
> 2. **Instructions** (< 5000 tokens recommended): The full `SKILL.md` body is loaded when the skill is activated
> 3. **Resources** (as needed): Files (e.g. those in `scripts/`, `references/`, or `assets/`) are loaded only when required

> Keep your main `SKILL.md` under 500 lines. Move detailed reference material to separate files.

**Anthropic skill-authoring best practices** —
<https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices>. **Verified still
current and still worded this way.** Three occurrences:

- L1132, section "Token budgets": *"Keep SKILL.md body under 500 lines for optimal performance. If your content exceeds this, split it into separate files using the progressive disclosure patterns described earlier."*
- L257: *"Keep SKILL.md body under 500 lines for optimal performance"*
- L1144, checklist: *"SKILL.md body is under 500 lines"*

**Claude Code skills docs** — <https://code.claude.com/docs/en/skills>, Tip:

> Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files.

**agentskills.io skill-creation/best-practices** L90 — ties both figures together and names the owner:

> The **specification** recommends keeping `SKILL.md` under 500 lines **and 5,000 tokens** — just the core instructions the agent needs on every run.

**Anthropic's own repo** — `anthropics/skills` → `skills/skill-creator/SKILL.md`:

> **SKILL.md body** - In context whenever skill triggers (<500 lines ideal)

> Keep SKILL.md under 500 lines; if you're approaching this limit, add an additional layer of hierarchy along with clear pointers about where the model using the skill should go next

No additional recommended target, soft threshold, or "aim for" figure exists in any official source.

### Independence caveat on the 5,000-token figure — stated, not buried

The `< 5,000 tokens` recommendation comes from **one publishing pool** (agentskills.io). **Anthropic's
own documentation states no token figure for the body** — its section literally titled "Token budgets"
gives only the 500-line cap. Both agentskills.io citations share a pool, so they are one corroborator,
not two.

What keeps the finding load-bearing anyway, and the reader should weigh both halves:

- The spec is the Agent Skills standard that Claude Code implements, and Claude Code's docs link to it.
- **The number 5,000 is independently corroborated from a second Anthropic pool** by the compaction
  re-attachment cap below — same figure, arrived at through a different mechanism.

So: HIGH confidence that the spec states it and that 5,000 is a real operative threshold in Claude
Code; the weaker claim would be "Anthropic recommends 5,000 tokens", which its own docs do not say.

## 2. Does 200 appear in any authoritative source? — NO

Read raw and in full on 2026-08-14; 200 absent from every one:

| Source | Extent read | Result |
|---|---|---|
| `platform.claude.com/…/agent-skills/best-practices.md` | 1,185 lines | 500 only |
| `code.claude.com/docs/en/skills.md` | 1,059 lines | 500 only |
| `agentskills.io/specification.md` | 274 lines | 500 + 5,000 tokens |
| `agentskills.io/skill-creation/best-practices.md` | full | 500 + 5,000 tokens |
| `anthropics/skills` → `skill-creator/SKILL.md` | 485 lines | 500 only |
| `playbooks:skill-authoring` SKILL.md + `vendor/SKILL.md` | 179 / 135 lines | no 200 (see §3) |
| `compound-engineering` → `portable-agent-skill-authoring.md` | full | no line figures at all |

Not inferred from brevity or progressive-disclosure advice. Simply absent.

## 3. Origin trace

**LOCALLY — an uncited tunable.** `plugins/skill-quality/scripts/check-skill.sh:177`, under the bare
comment `# Tunables (listing description cap; SKILL.md line caps; vendor sync age)`. No citation, no
rationale. `skill-quality`'s own SKILL.md offers no justification either.

The strongest evidence is the contrast inside that three-line block:

```sh
DESC_CHAR_CAP=1536   # matches Claude Code docs exactly
LINE_HARD_CAP=500    # matches the spec and Anthropic docs exactly
LINE_SOFT_CAP=200    # matches nothing upstream
```

Both neighbours are anchored to primary sources. **200 is the only value in the block with no upstream
anchor.**

> **Citation reconciliation:** the repo copy carries these at `:175-177`; the installed cache
> (`skill-quality/0.5.0`) carries the same values at `:122-124`. The design doc's `:124` and this
> file's `:177` are both correct for their respective copies.

**EXTERNALLY — CONVENTION.** A widely-circulated community convention that misattributes itself to
Anthropic. A web-search synthesis asserted outright *"Anthropic's own guidance targets under 200
lines"* — **falsified directly** against the raw primary fetches above. The most concrete artifact is
a third-party skill whose entire purpose is the convention: `compress-skill`, *"Compress SKILL.md to
under 200 lines"*, author `dvy1987`, published 2026-04-17 on skills.rest (a third-party library, not
Anthropic).

**Possible local reinforcement, but a DIFFERENT number.** The vendored `playbooks:skill-authoring`
playbook says *"SKILL.md is the hub (~30 lines); spoke files do the work."* Its provenance is a
2026-03-17 X post by Thariq (@trq212) described as Anthropic's internal playbook — an employee
social-media post, not documentation. That yields 30, not 200.

**Verdict:** community convention with no primary source. 200 is **untraceable to any specific origin
document**, and in this repo it is unattributed.

## 4. The constraint's real shape — tokens, not lines

The official budget is a **token budget on what stays in context once the skill is loaded**. The
500-line cap is a coarse **proxy**. The spec states them together and states the token figure as a
property of the loaded body.

**This file is a case where the proxy and the real constraint disagree.** Measured, not estimated:

| Metric | Value |
|---|---|
| Lines | 410 |
| Characters | 38,436 |
| Words | 4,723 (`awk '{n+=NF}'`, whole file incl. frontmatter) |
| Density | ~94 chars/line |

**Token estimate — INFERRED, method named:** chars ÷ 4 → ~9,600; words × 1.33 → ~6,300. No tokenizer
available, so treat as a range of roughly **6,300–9,600 tokens**, not a fact. The imprecision does not
change the verdict: even the low end is ~1.3x the recommendation; the likely value is ~2x.

> A parallel `wc -w` count recorded 4,579 words. The gap is a counting-boundary difference, not a
> contested figure; both land the estimate at roughly 2x.

Two corroborating mechanics, both Anthropic-pool Tier 1:

- best-practices.md: *"once Claude loads it, every token competes with conversation history and other context."*
- `code.claude.com/docs/en/skills`, "Skill content lifecycle": when the conversation is summarized, Claude Code *"re-attaches the most recent invocation of each skill after the summary, **keeping the first 5,000 tokens of each**. Re-attached skills share a combined budget of 25,000 tokens."* A body over it is **silently truncated after any compaction** — positionally, with no signal that anything is missing.

**Caveat, not papered over:** *"under 500 lines **for optimal performance**"* is stated three times and
**"optimal performance" is never defined anywhere**. No attention, recall, or instruction-following
rationale is given in any official source. **No attention-based benefit of a shorter body can be
claimed from the documentation.**

## 5. Effect on the blocked decision

The 200 WARN **cannot** justify splitting the 148-line section — no authoritative source states a
200-line target, and the completion criterion resting on it is unbacked.

**But the split is not thereby unjustified.** The body is roughly 2x the `< 5,000 tokens`
recommendation, and that independently requires shrinking the hub. Same action, different and
defensible warrant — and it changes **what** moves:

- **Not** "whatever gets the line count under 200."
- **But** "whatever gets the body under 5,000 tokens, chosen along the conditional/source axis." See `RESEARCH-progressive-disclosure.md` for the split criterion.

**Gate follow-ups** (flagged, not applied): re-anchor or remove `LINE_SOFT_CAP=200`; add a token-based
check against `< 5,000 tokens` — the constraint the current 500-line PASS fails to catch.

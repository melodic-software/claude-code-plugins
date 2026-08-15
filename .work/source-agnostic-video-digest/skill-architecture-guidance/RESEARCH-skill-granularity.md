---
topic: skill-architecture-guidance
section: skill-granularity
abstract: The docs are silent on multi-source ingestion, so one-skill-with-adapters is not officially blessed — but it survives independent re-derivation via the coherent-unit test, Anthropic's own claude-api dispatcher precedent, and two Claude Code mechanics that penalize sibling skills.
claims:
  - claim: "No official source states a one-skill-per-input-type or per-source rule; multi-source ingestion is never named as a concern."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "The discriminating boundary test in the corpus is coherence of a unit of work, not input count."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://agentskills.io/skill-creation/best-practices"
        tier: 1
        pool: "agentskills.io (Anthropic-authored standard, multi-vendor governed)"
  - claim: "Anthropic's own claude-api skill implements one pipeline with an internal 8-way per-language dispatcher over a shared core — the structural match to multi-source ingestion."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "The docx/pdf/pptx/xlsx split is a weak counter-analogy: their shared scripts/office/ subtree is copy-pasted identically into three skills, showing no shared pipeline existed."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://github.com/anthropics/skills"
        tier: 1
        pool: "Anthropic (public skills repo)"
  - claim: "Adding a skill with an overly broad description is documented as stealing triggers from existing skills and degrading them."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://platform.claude.com/docs/en/agents-and-tools/agent-skills/enterprise"
        tier: 1
        pool: "Anthropic (platform docs)"
  - claim: "Claude Code drops listing descriptions starting with least-invoked skills, structurally starving rarely-used sibling skills of their trigger keywords."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
  - claim: "Skill-invokes-skill is not a documented contract; the only official statement describes it as not natively built in yet."
    confidence: HIGH
    tiers: [2]
    sources:
      - url: "https://claude.com/blog/lessons-from-building-claude-code-how-we-use-skills"
        tier: 2
        pool: "Anthropic (Claude blog)"
  - claim: "No frontmatter dependency/requires/includes/sub-skill field exists."
    confidence: HIGH
    tiers: [1]
    sources:
      - url: "https://code.claude.com/docs/en/skills"
        tier: 1
        pool: "Anthropic (Claude Code docs)"
produced_by: phase-2-targeted
---

# Skill granularity — one skill with adapters vs. sibling skills vs. delegation

**Verdict: the docs are SILENT on multi-source ingestion. One-skill-with-adapters is NOT officially
blessed — but it survives independent re-derivation and agrees with the incumbent for reasons
independent of incumbency.**

The brief's standing instruction was that incumbent structure is never itself a justification. This
section was therefore run as a re-derivation, not a confirmation: the question asked was "what shape
would the corpus pick knowing nothing about this repo."

## 1. What is documented, and what is not

**No "one skill per input type / per source" rule exists anywhere.** No official page names
multi-source ingestion, "source adapter", or "per-source" as a concern. **DOCUMENTED SILENCE** — this
is a gap in the guidance, not a permission.

**The discriminating test in the corpus is pipeline-sharing, not input-count.** agentskills.io,
"Design coherent units":

> Deciding what a skill should cover is like deciding what a function should do: you want it to encapsulate a coherent unit of work that composes well with other skills. Skills scoped too narrowly force multiple skills to load for a single task, risking overhead and conflicting instructions. Skills scoped too broadly become hard to activate precisely. A skill for querying a database and formatting the results may be one coherent unit, while a skill that also covers database administration is probably trying to do too much.

## 2. Behavioral evidence — Anthropic's own skills cut both ways along that line

**Different pipelines → separate siblings.** `skills/docx/`, `pdf/`, `pptx/`, `xlsx/` are four
independent skills with hard-partitioned descriptions carrying explicit negative boundaries.

**The tell that this is a WEAK analogy for the video-digest case:** their shared `scripts/office/`
subtree — schemas, `soffice.py`, `validate.py`, `validators/` — is **copy-pasted identically into
three of them** rather than referenced from one place. Duplication across siblings, not a shared
module. There was no shared pipeline to unify around. Despite `docx` shelling out to `soffice` and
`pdftoppm` for previews, it does **not** delegate to the `pdf` skill; there are zero cross-references
among the four.

Note also that **`xlsx` already unifies five input formats** (`.xlsx, .xlsm, .xltx, .csv, .tsv`) behind
one skill. The partition is by task and deliverable, **never by file extension**. Internal branching
inside each skill is by *operation* (create / edit / read), not by source.

**One pipeline, N source variants → ONE skill with an internal routing table.** This is the
**structural match** to acquire → transcript → research → synthesis.

`skills/claude-api/SKILL.md`, `## Language Detection` — a dispatcher, verbatim in shape:

> - `*.py`, `requirements.txt`, `pyproject.toml` … → **Python** — read from `python/`
> - `*.ts`, `*.tsx`, `package.json`, `tsconfig.json` → **TypeScript** — read from `typescript/`
> - `*.java`, `pom.xml`, `build.gradle` → **Java** — read from `java/`
> … (8 languages)

On-disk: dispatcher + per-source adapters + shared core.

```text
skills/claude-api/
  SKILL.md                  (routing table + shared conceptual guidance)
  python/ typescript/ java/ go/ ruby/ csharp/ php/ curl/   (mirrored per-variant file sets)
  shared/                   (19 files: agent-design, prompt-caching, token-counting, …)
```

`skills/mcp-builder/` is the flatter two-variant form of the same shape. And `skill-creator/SKILL.md`
states it as doctrine:

> **Domain organization**: When a skill supports multiple domains/frameworks, organize by variant:

> `cloud-deploy/` → `SKILL.md (workflow + selection)` + `references/aws.md`, `gcp.md`, `azure.md` — "Claude reads only the relevant reference file."

## 3. Two Claude Code mechanics independently penalize the sibling-skills shape

**1. Trigger-stealing.** `platform…/agent-skills/enterprise.md` evaluation table, **Coexistence** row:

> Does adding this Skill degrade other Skills? | **New Skill's description is too broad, stealing triggers from existing Skills**

Remedy: *"Consolidate overlapping Skills or narrow descriptions."* And the framing statement:

> Skills can degrade agent performance if they trigger incorrectly, conflict with other Skills, or provide poor instructions. Require evaluation before any production deployment.

Also: *"Require evaluations in isolation (Skill alone) and alongside existing Skills (coexistence testing)."*

**2. Listing-budget starvation.** `code.claude.com/docs/en/skills`:

> When the listing overflows, Claude Code drops descriptions starting with the skills you invoke least, so the skills you use most keep their full text.

A rarely-used `x-digest` sibling loses exactly the keywords that would route to it — the failure is
structural, not a tuning problem.

Related recall pressure, `enterprise.md`: *"limit the number of Skills loaded simultaneously to
maintain reliable recall accuracy… With too many Skills active, Claude may fail to select the right
Skill or miss relevant ones entirely."*

## 4. A documented tension — stated, not resolved

**Do not let any reconciliation of these be presented as official.** They are about different objects
and neither cites the other:

- `enterprise.md` (**portfolio** evolution): *"Encourage teams to start with narrow, workflow-specific Skills rather than broad, multipurpose ones. As patterns emerge across your organization, consolidate related Skills into role-based bundles."* Tip: *"Merge narrow Skills into a broader one only when the consolidated Skill's evaluations confirm equivalent performance to the individual Skills it replaces."*
- `agentskills.io` (**one skill's** boundary): too-narrow is its own failure mode.

## 5. Skill-invokes-skill — not a documented contract

The only official statement is a blog post describing it as pre-native —
<https://claude.com/blog/lessons-from-building-claude-code-how-we-use-skills>:

> You may want to have skills that depend on each other… This sort of dependency management is not natively built into marketplaces or skills yet, but you can just reference other skills by name, and the model will invoke them if they are installed.

Model-mediated, not a contract. The `Skill` tool exists (`tools-reference.md`: *"Executes a skill
within the main conversation"*) but is **never presented as a composition pattern**.

**No `dependency` / `requires` / `includes` / sub-skill frontmatter field exists** — verified against
the complete frontmatter table. Skill *stacking* (`/write-tests /fix-issue 123`) is user-typed, capped
at *"the first skill plus up to five more"*, and *"Expansion stops at the first token that isn't an
inline user-invocable skill"* — not a pipeline primitive.

**Consequence for design:** this forecloses a thin `x-digest` skill that forwards to the real one.

## 6. Bottom line

One-skill-with-adapters cannot be called blessed — the docs are silent. But it wins on merits:

- the coherent-unit test (one shared pipeline = one unit),
- Anthropic's own `claude-api` dispatcher-plus-adapters precedent,
- the coexistence / trigger-stealing warning,
- the listing-budget mechanic.

And the strongest-looking counter-evidence (the four office skills) **dissolves on inspection** — the
copy-pasted `scripts/office/` subtrees prove those skills had no shared pipeline, which is exactly the
fact that does not hold here.

---
description: "Read-only progressive-disclosure audit for agent-facing instruction markdown. Grades every target against a three-tier load-cost model (always-loaded / invocation-loaded / on-demand) and classifies seven finding shapes in two lanes: split opportunities (oversize vs tier-calibrated Anthropic-prescribed caps, mixed-concerns, tier-mismatch. Procedures, path-local, or sometimes-only content sitting in an always-loaded file) and disclosure-structure defects (blind-pointer lacking a when-to-read clause or read-vs-run intent, orphan-spoke, deep-nesting past one level, missing-toc on long references). Emits Tier 1/2/3 findings with per-shape treatment guidance; read-only, no edits applied. Use when: 'progressive disclosure', 'split this file', 'this file is too long', 'too much context', 'mixed concerns', 'hub and spoke', 'is my CLAUDE.md too big', 'audit context loading', 'what should always be loaded', or before splitting any instruction file, not for prose flavor (/docs-hygiene:compress), in-page noise (/docs-hygiene:audit-noise), whole-doc existence (/docs-hygiene:audit-derivability), or skill frontmatter QA (/skill-quality:check)."
argument-hint: "[audit] [target]"
user-invocable: true
disable-model-invocation: false
allowed-tools: ["Bash(${CLAUDE_SKILL_DIR}/scripts/detect.sh:*)", "Bash(grep:*)", "Bash(head:*)", "Bash(echo:*)"]
shell: bash
metadata:
  workflow-stage: anytime
  summary: Grade instruction files for split opportunities and hub/spoke disclosure defects
---

## Pre-computed context

Current branch: !`git branch --show-current 2>/dev/null || echo "unknown"`
Uncommitted .md files (sample, first 10): !`git status --porcelain 2>/dev/null | grep '\.md$' | head -10 || echo "none"`

## Purpose

Agent-facing instruction markdown, `CLAUDE.md`/`AGENTS.md`, `.claude/rules/`, skill/agent/command
bodies, their bundled spokes, has a load cost set by its **tier**: always-loaded content is paid
every session, invocation-loaded content recurs for the rest of the session once triggered, and
on-demand content is free until read. This skill audits both directions of that economy: content
that should move DOWN a tier (split opportunities), and existing hub/spoke structures whose
pointers no longer let an agent pull exactly the file it needs (structure defects). It is a
read-only classifier: findings carry treatment guidance; the author applies every edit.

Full tier tables, official numbers, split triggers, and pointer-quality criteria: read
[context/tier-model.md](context/tier-model.md) when adjudicating any finding that needs the exact
threshold, routing rule, or citation posture (Anthropic-prescribed vs corroborated vs community).

## Finding shapes and treatments

| Lane | Shape | What it looks like | Default tier | Treatment |
|---|---|---|---|---|
| split | `oversize` | File at/approaching its tier's size guidance (SKILL.md approaching 500 lines; CLAUDE.md above ~200; references per the TOC bands). Ceilings, not targets. Size alone below the cap is no finding | 2 | Add a hierarchy layer: name the sections to push into spokes, each behind a conditioned pointer |
| split | `mixed-concerns` | Mutually-exclusive contexts co-resident (content that never co-executes), category straddle, multi-topic rules file, cross-file contradiction | 2 | Split by concern. One topic per file; name the proposed split seams |
| split | `tier-mismatch` | Content at the wrong tier: a procedure grown inside CLAUDE.md (→ skill), path-local rules in a global file (→ scoped rule), reference detail inline in a hub (→ spoke), always-loaded content not needed every session (→ demote behind a pointer) | 1 when an official routing rule decides it; else 2 | Route down-tier per the rule; the finding names source section and destination surface |
| structure | `blind-pointer` | Pointer with no when-to-read clause, unmarked execute-vs-read intent, or a vague target name (`doc2.md`, `utils`) | 2 | Attach the condition and intent; rename the target descriptively. On skill descriptions, a missing when-NOT-to-use clause is advisory color (community-sourced), never a violation |
| structure | `orphan-spoke` | Bundled spoke no hub references. Unreachable by pointer | 2 | 3-way: add the missing pointer, merge the content up, or delete the spoke |
| structure | `deep-nesting` | Spoke-to-spoke chain, required reading more than one level from the hub (documented partial-read failure) | 2; 1 when the chain is the only path to required content | Re-link the deep target directly from the hub, or flatten |
| structure | `missing-toc` | Reference file >300 lines with no TOC = definite; 100–300 lines with none = awareness only, citing the official 100-vs-300 conflict | 1 (>300) / 3 (100–300) | Add a TOC at top (or a grep recipe for lookup-shaped content) |

Thresholds are advisory and tier-calibrated, never hard gates; consuming repos refine them via
their own `CLAUDE.md` / rules. There is deliberately **no** "should have spokes" shape: disclosure
is a scaling tool, and a small single-file skill is never flagged for lacking spokes.

## Action router

| Action | Args | Behavior |
|---|---|---|
| `<target>` (default) | empty → uncommitted `.md` files from git; file path → single file; dir path → recursive batch | run `${CLAUDE_SKILL_DIR}/scripts/detect.sh` on the targets; map its facts onto the shapes table via the judgment rules below |
| `audit [target]` | same target rules | explicit form of the default; same behavior |

Single action v1; a `split` action (applying the splits) is deferred until real demand surfaces. Author hand-edits driven by audit output cover the workflow.

**Facts vs judgment.** `detect.sh` is a fact emitter, not an adjudicator: it emits per-file size
and heading facts, load-tier classification (path + frontmatter heuristic; `unknown` is yours to
classify), a pointer inventory with source-line context, orphan-spoke records, and spoke-to-spoke
`chain` records. The judgment layer owns: concern-mixing (from the heading census + content),
whole-conversation relevance of always-loaded sections, when-clause quality (a `pointer` record's
`ctx` shows the surrounding line. Judge whether it carries a condition and intent), and whether a
`chain` is a required reading path (finding) or a legitimate cross-reference (not one). In a repo
with no Claude Code configuration the tier model degrades gracefully: most files classify
on-demand/unknown and the split lane still applies.

## Auto-detect default

Shared clean-tree / no-scope shape: [`../../context/clean-tree-fallback.md`](../../context/clean-tree-fallback.md).

1. Empty arg AND clean tree → OFFER a repo-wide audit (never auto-start). Prescribed defaults
   (overridable): corpus = all tracked agent-facing instruction `.md` (CLAUDE.md/AGENTS.md,
   `.claude/rules/`, skill/agent/command trees) minus `**/evals/fixtures/**`, `**/vendor/**`, and
   `CHANGELOG.md`; scan via one `detect.sh` pass per top-level root; report-first. Unattended,
   surface the offer as blocked and stop.
2. Empty arg AND uncommitted `.md` files → batch audit over ALL of them. Re-derive the full
   list in-session (`git status --porcelain`); the pre-computed sample above caps at 10 and is
   orientation, never the corpus.
3. Single file path → single-file audit.
4. Directory path → recursive batch.
5. First positional == `audit` → audit on the rest (explicit form).

## Hard rules

- **Read-only.** No `Edit`, no `Write`, no mutating `Bash` ops; the author owns every treatment edit.
- **Tier semantics** (identical to the sibling audits): Tier 1 = definite; Tier 2 = review needed;
  Tier 3 = likely legitimate, surfaced for awareness and carrying NO treatment.
- **Citation posture.** Vendor-defined numbers (500/200/1,024/1,536/1%/~100 tokens/5k/25k) are
  cited as Anthropic-prescribed; consensus language is reserved for independently corroborated
  claims. Community-sourced signals are labeled as such and stay advisory.
- **Small-corpus guard.** Never flag a file for NOT using progressive disclosure when its content
  fits comfortably at its tier; splitting a 60-line file buys nothing.
- **Skip surfaces.** `CHANGELOG.md`, `evals/fixtures/`, `vendor/` trees, YAML frontmatter, and
  fenced code blocks are never findings surfaces.
- **Output deterministic.** Files sort lexically; per-file rows sort by line; no timestamps.
- **Default action is the audit action**. `/docs-hygiene:audit-progressive-disclosure <file>` ==
  `… audit <file>`.

## Output schema

```text
<file>: tier=<always|invocation|on-demand|unknown> — N finding(s) — T1=<n>, T2=<n>, T3=<n>

| Tier | Lane | Shape | Line | Evidence | Treatment |
|------|------|-------|------|----------|-----------|
| 1    | split | tier-mismatch | 41 | "## Deploy procedure" (multi-step) in always-loaded CLAUDE.md | Move to a skill; leave a one-line pointer |
| 2    | structure | blind-pointer | 12 | "[details](context/tier-model.md)" — no when-clause | Attach the read condition and intent |
| 3    | structure | missing-toc | — | reference file, 180 lines, no TOC (official guidance conflicts: 100 vs 300) | awareness only |
```

Batch aggregate at end:

```text
Total: <N> file(s) audited — T1=<n>, T2=<n>, T3=<n>. Facts: files=<n> pointers=<n> unresolved=<n> orphans=<n> chains=<n>
```

`shape` values: `oversize`, `mixed-concerns`, `tier-mismatch`, `blind-pointer`, `orphan-spoke`,
`deep-nesting`, `missing-toc`.

## Gotchas

- The 500/200 numbers are **ceilings, not targets**; the official split trigger is *approaching*
  the cap, and the internal-practice hub figure (~30 lines) is far below it. Size alone under the
  cap never fires `oversize`.
- Invocation-loaded is **cheap to have, not cheap to use**: once a skill body loads, every line
  recurs for the session, so mutually-exclusive content inside one body defeats the tier and
  fires `mixed-concerns` even when the file is "small enough".
- A `chain` record is a candidate, not a verdict. Sibling cross-references between spokes that
  are alternates (not required reading) are legitimate.
- An unresolved pointer (`resolved=no`) is upstream breakage worth surfacing, but rename sweeps
  belong to `/docs-hygiene:rename-references`, not here.
- The TOC bands exist because Anthropic's own surfaces disagree (100 vs 300); never present
  either number as the single official rule.

## What this skill is NOT

- **Not `/docs-hygiene:compress`**. Flavor/wordiness inside a file is compression, not disclosure.
- **Not `/docs-hygiene:audit-noise`**. In-page noise shapes (citations, ghost-refs, preambles).
- **Not `/docs-hygiene:audit-derivability`**. Whether a whole doc should exist at all.
- **Not `/docs-hygiene:extract-ssot`**. Content repeated across files is deduplication territory.
- **Not `/skill-quality:check`**. Frontmatter validation, listing budgets, and description QA are
  its static gates; this skill audits loading structure, and cross-references rather than
  duplicates those checks.

## Sources

- [Claude Code skills docs](https://code.claude.com/docs/en/skills). Loading levels, listing cap, compaction budgets, split triggers
- [Claude Code memory docs](https://code.claude.com/docs/en/memory). CLAUDE.md/rules loading, 200-line target, fact-vs-procedure routing
- [Claude Code large-codebases docs](https://code.claude.com/docs/en/large-codebases). Root-orients / per-directory layering, escalation ladder
- [Agent Skills best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices). Hub-and-spoke patterns, pointer rules, observed-navigation diagnostics, >100-line TOC guidance
- [Agent Skills spec](https://agentskills.io/specification). Frontmatter limits, one-level-deep rule, ~100-token metadata
- [Anthropic engineering: Agent Skills](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills). Mutual-exclusivity split rule
- [Anthropic engineering: context engineering](https://www.anthropic.com/engineering/effective-context-engineering-for-ai-agents). Just-in-time retrieval, pointer doctrine
- [skill-creator](https://github.com/anthropics/skills/tree/main/skills/skill-creator). Approaching-the-limit split trigger, >300-line TOC guidance
- [UC Davis disclosure study (arXiv 2607.17598)](https://arxiv.org/abs/2607.17598). Scale boundary, depth>1 harm (academic corroboration)
- [happyskills: listing eviction](https://happyskills.ai). Community source for eviction scoring and the when-NOT-to-use description clause (advisory color only)

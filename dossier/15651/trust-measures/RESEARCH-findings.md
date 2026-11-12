---
topic: trust-measures
section: findings
abstract: 'H1 (HIGH (single source)): "Jellyfish defines agentic-merged PRs as the fraction of merged pull requests whose only review activity came from AI tools, with no human review input before merge"'
claims:
  - claim: "dora.dev defines change fail rate as the ratio of deployments that require immediate intervention following a deployment, likely a rollback or hotfix"
    id: D1
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "DORA"
    single_source: "DORA publishes its own metric definitions; only dora.dev states what DORA's definition is, and other pages repost it"
    tiers: [1, 2]
    applies_to: "version-independent"
    sources:
      - url: "https://dora.dev/guides/dora-metrics/"
        tier: 1
        pool: "DORA"
        measures: "the current DORA metrics guide's own definition text for change fail rate"
        role: primary
        published: 2026-01-05
        dated_by: printed
        applies_to: "version-independent"
        standing: current
      - url: "https://aicodereview.cc/blog/dora-metrics-explained/"
        tier: 2
        pool: "DORA"
        measures: "aicodereview.cc repost quoting the dora.dev definition verbatim; carries the DORA pool and is not counted as a corroborator"
        role: corroborator
        published: 2026-07-28
        applies_to: "version-independent"
        standing: current
    inference: "The primary is the owner's own definition page, fetched this run; the repost quotes the same text and adds no independent corroborator, so the claim rests on the single-source flag"
    qualifiers: ["DORA's guide is guidance, and its survey wording differs from the guide"]
  - claim: "dora.dev defines deployment rework rate as the ratio of deployments that are unplanned but happen as a result of an incident in production"
    id: D2
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "DORA"
    single_source: "DORA publishes its own metric definitions; only dora.dev states what DORA's definition is, and other pages repost it"
    tiers: [1, 2]
    applies_to: "version-independent"
    sources:
      - url: "https://dora.dev/guides/dora-metrics/"
        tier: 1
        pool: "DORA"
        measures: "the current DORA metrics guide's own definition text for deployment rework rate"
        role: primary
        published: 2026-01-05
        dated_by: printed
        applies_to: "version-independent"
        standing: current
      - url: "https://big-agile.com/blog/balanced-engineering-metrics"
        tier: 2
        pool: "DORA"
        measures: "big-agile.com repost, carries the DORA pool and is not counted as a corroborator; restates DORA rework rate as unplanned deployments made for a problem in production over all deployments; notes the survey asks about user-facing bug fixes"
        role: corroborator
        published: 2026-10-28
        applies_to: "version-independent"
        standing: current
    inference: "The primary is the owner's own definition page, fetched this run; the repost restates it with the survey-wording caveat and adds no independent corroborator, so the claim rests on the single-source flag"
    qualifiers: ["DORA's survey asks about deployments made to fix a user-facing bug, which is not the same count as incident-driven deployments"]
  - claim: "DX documentation lists PR revert rate as the percentage of PRs that were reverted"
    id: R1
    confidence: MEDIUM
    claim_kind: content
    source_owner: "DX"
    tiers: [1]
    applies_to: "version-independent"
    sources:
      - url: "https://docs.getdx.com/reports/ai-code-overview/"
        tier: 1
        pool: "DX"
        measures: "DX's AI pull request overview report table row for PR revert rate"
        role: primary
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "The row is DX's own text, fetched this run, but the page carries no publisher date, so it cannot be a publish-grade primary"
    qualifiers: ["the page names no numerator rule for detecting a revert"]
  - claim: "Jellyfish defines agentic-merged PRs as the fraction of merged pull requests whose only review activity came from AI tools, with no human review input before merge"
    id: H1
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "Jellyfish"
    single_source: "Jellyfish is the only publisher of Jellyfish's own metric definition"
    tiers: [1]
    applies_to: "version-independent"
    sources:
      - url: "https://jellyfish.co/ai-engineering-trends/"
        tier: 1
        pool: "Jellyfish"
        measures: "Jellyfish's AI Engineering Trends page, Agentic-Merged PRs definition, calculated per company over merged PRs"
        role: primary
        published: 2026-10
        dated_by: printed
        applies_to: "version-independent"
        standing: current
    inference: "The definition is Jellyfish's own text, fetched this run"
    qualifiers: ["counts review activity only (comments or formal reviews); says nothing of who merged"]
  - claim: "Published revert-rate definitions use two numerators: merged PRs that are themselves reverts, and merged PRs later reverted"
    id: R2
    confidence: MEDIUM
    claim_kind: content
    source_owner: "multiple vendors"
    tiers: [1, 2]
    applies_to: "version-independent"
    sources:
      - url: "https://docs.sourcery.ai/reviews/analytics/"
        tier: 1
        pool: "Sourcery"
        measures: "fetched this run; the extraction returned no text, so the search-snippet wording (share of merged PRs that revert an earlier change) is unconfirmed"
        role: primary
        published: undated
        applies_to: "version-independent"
        standing: historical
      - url: "https://codeclimate.com/blog-category/coaching"
        tier: 2
        pool: "Code Climate"
        measures: "search snippet only: revert rate as the percentage of PRs that are reverts"
        role: corroborator
        published: undated
        applies_to: "version-independent"
        standing: historical
    inference: "Two vendor wordings differ from DX's (R1); not fetched to Tier 1 confirmation"
    qualifiers: ["snippet-level evidence only"]
  - claim: "Agarwal et al. operationalize review coverage as whether a merged PR received any human review, and report that results change with whether the agent invoker counts as a reviewer"
    id: H2
    confidence: MEDIUM
    claim_kind: content
    source_owner: "Carnegie Mellon University"
    tiers: [1, 2]
    applies_to: "version-independent"
    sources:
      - url: "https://arxiv.org/abs/2607.07980"
        tier: 1
        pool: "arXiv / CMU authors"
        measures: "abstract page fetched this run; it states trends flip under defensible analysis choices but does not carry the operationalization sentence"
        role: primary
        published: 2026-07-08
        applies_to: "version-independent"
        standing: current
      - url: "https://alediaferia.com/2026/09/01/how-ai-code-review-is-changing-pull-requests/"
        tier: 2
        pool: "alediaferia.com"
        measures: "blog summary of the paper's invoker-as-reviewer caveat"
        role: corroborator
        published: 2026-09-01
        applies_to: "version-independent"
        standing: current
    inference: "The operationalization sentence was seen only in a search extract of the HTML full text, not in a fetch this run"
    qualifiers: []
  - claim: "measure-delivery counts each first-parent default-branch commit as a deployment and detects reverts from git history alone"
    id: S1
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software"
    single_source: "the skill file is the only publisher of its own behavior description"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/blob/ca041f276d894076c098e63c855213b5722e8cfe/plugins/work-items/skills/measure-delivery/SKILL.md"
        tier: 0
        pool: "melodic-software"
        measures: "Deploy signal section: first-parent commits are deployments; three revert-detection forms; reads only git history"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "Read end to end this run"
    qualifiers: ["a hand-written undo with no revert subject or reverts line is not counted"]
  - claim: "morning-brief counts owner touches by the operator login and states that this includes any agent session holding that login"
    id: S2
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software"
    single_source: "the skill file is the only publisher of its own behavior description"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/blob/ca041f276d894076c098e63c855213b5722e8cfe/plugins/work-items/skills/morning-brief/SKILL.md"
        tier: 0
        pool: "melodic-software"
        measures: "Owner touches row of the sections table (line 244 at this checkout)"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "Read at the matched line this run"
    qualifiers: ["per-day window, default 2 days"]
  - claim: "corrections:codify writes proposals and notes under the gitignored .work/codify directory and records no tracked link from a correction to an installed check"
    id: S3
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software"
    single_source: "the skill files are the only publisher of their own behavior description"
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/blob/ca041f276d894076c098e63c855213b5722e8cfe/plugins/corrections/skills/codify/SKILL.md"
        tier: 0
        pool: "melodic-software"
        measures: "section 6 (proposal path), Boundary (never installs), and actions/note.md (notes path and buffer.sh)"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "SKILL.md read end to end and note.md read at its path lines; no install record or tracked marker is described"
    qualifiers: ["the buffer's bound adapter can be user-scope; this checkout binds none and falls back to local-file"]
produced_by: phase-1-2
---

# Findings

## Definitions

- D1 (HIGH (single source)): "dora.dev defines change fail rate as the ratio of deployments that require immediate intervention following a deployment, likely a rollback or hotfix"
- D2 (HIGH (single source)): "dora.dev defines deployment rework rate as the ratio of deployments that are unplanned but happen as a result of an incident in production"
- H1 (HIGH (single source)): "Jellyfish defines agentic-merged PRs as the fraction of merged pull requests whose only review activity came from AI tools, with no human review input before merge"

## What the existing skills read or record

- S1 (HIGH (single source)): "measure-delivery counts each first-parent default-branch commit as a deployment and detects reverts from git history alone"
- S2 (HIGH (single source)): "morning-brief counts owner touches by the operator login and states that this includes any agent session holding that login"
- S3 (HIGH (single source)): "corrections:codify writes proposals and notes under the gitignored .work/codify directory and records no tracked link from a correction to an installed check"

## Conflicts

- D2 (HIGH (single source)): "dora.dev defines deployment rework rate as the ratio of deployments that are unplanned but happen as a result of an incident in production". The repository's skill approximates that with revert landings, per S1 (HIGH (single source)): "measure-delivery counts each first-parent default-branch commit as a deployment and detects reverts from git history alone". A forward fix that is not a revert is unplanned rework DORA counts and the skill does not. Resolved: this is a difference of scope, not counter-evidence, and neither claim is in doubt. It is attached as a qualifier on the computed revert-rate claim in RESEARCH-computed.md: the value is a revert-based proxy, not DORA's incident-driven rework rate.

## Gaps

- R1 (MEDIUM): "DX documentation lists PR revert rate as the percentage of PRs that were reverted". Fetched this run; the page prints no date, so it is not a publish-grade primary.
- R2 (MEDIUM): "Published revert-rate definitions use two numerators: merged PRs that are themselves reverts, and merged PRs later reverted". Checked: DX docs (fetched), Sourcery docs (fetched, extraction empty), Code Climate and Oobeya (search snippets only). Unchecked: the DX 2026 benchmark page, the ACM agentic-revert paper full text.
- H2 (MEDIUM): "Agarwal et al. operationalize review coverage as whether a merged PR received any human review, and report that results change with whether the agent invoker counts as a reviewer". Checked: arXiv abstract page. Unchecked: the paper's appendix in a direct fetch.
- No published ratio for corrections converted to checks was found. Checked: a Perplexity search returning the Sentry "Stop Prompting" talk page (ai.engineer), arXiv 2607.13091 (rule-recurrence measure, not a conversion ratio) and aipatternbook.com "Compound Engineering" (first-pass acceptance rate). Unchecked: vendor analytics docs (DX, Jellyfish, LinearB) for such a metric.

## Fetch log

| Claim | URL or command | Rung | Tool | Outcome |
|---|---|---|---|---|
| D1, D2 | https://dora.dev/guides/dora-metrics/ | 1 owner docs | firecrawl scrape | carries the claim |
| D1, D2 | DORA definitions (no release stream; dora.dev/insights/dora-metrics-history/ seen in search, last change 2024) | changelog | perplexity search | 2024 five-metric model (2026-01-05 guide update) — current |
| R1 | https://docs.getdx.com/reports/ai-code-overview/ | 1 owner docs | firecrawl scrape | carries the claim |
| R2 | https://docs.sourcery.ai/reviews/analytics/ | 1 owner docs | firecrawl scrape | unresolved |
| H1 | https://jellyfish.co/ai-engineering-trends/ | 1 owner page | firecrawl scrape | carries the claim |
| H2 | https://arxiv.org/abs/2607.07980 | 1 paper | firecrawl scrape | fetched and searched, does not carry the claim |
| S1 | plugins/work-items/skills/measure-delivery/SKILL.md | 0 local file | Read | carries the claim |
| S2 | plugins/work-items/skills/morning-brief/SKILL.md | 0 local file | grep | carries the claim |
| S3 | plugins/corrections/skills/codify/SKILL.md, actions/note.md | 0 local file | Read, grep | carries the claim |

Falsification query (Phase 2): a git trailer count testing whether owner-login PRs are human-made (see RESEARCH-computed.md, C3).

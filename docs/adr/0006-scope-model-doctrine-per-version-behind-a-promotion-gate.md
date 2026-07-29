# Scope model-derived doctrine to its source model version behind a promotion gate

- Status: accepted
- Date: 2026-07-27

## Context

The opus-5-prompting integration turned Anthropic's Opus 5 prompting guide and system card into
standing instruction surfaces across three plugins. Before it, the repository carried one
precedent for model-derived doctrine: `plugins/playbooks/skills/fable-5/context/opus-adaptation.md`,
calibrated against Opus 4.8, routed by a meta-rule that told any Opus model to apply its deltas
verbatim. The Opus 5 guide then reversed several of that file's counter-steers — effort floor,
per-edit-batch verifier dispatch, delegation bias, scope literalism — demonstrating that a
single model guide's corrections can be not merely stale for the next version of the same family
but inverted.

The competing forces:

- Model guides are calibrated per version, and successive guides reverse each other, so
  family-level routing ("if you are Opus") applies one version's counter-steers to a model with
  the opposite defaults.
- Fleet-wide, model-agnostic rules are cheaper to write, audit, and consume; per-model scoping
  multiplies files and rows and makes target-model resolution machinery load-bearing.
- These surfaces (audit criteria rows, playbook delta chapters) constrain future work, so a wrong
  scoping default compounds silently with every new consumer.

Real alternatives shaped the outcome: keeping fleet-wide-by-default with ad-hoc per-model
exceptions (the incumbent shape that produced the verbatim-application defect), or scoping
everything per-model with no promotion path (which would duplicate genuinely model-agnostic
upstream claims into every model's file).

## Decision

Doctrine sourced from a single model's guide or card is **model-scoped by default**. Promotion to
fleet-wide (unscoped) happens **only through the gate**: an authoritative model-agnostic upstream
document states the claim, OR multiple model guides converge on it. Until the gate is met, the
claim stays scoped to the version whose guide sourced it.

The scoping is structural, not advisory prose:

- **Playbooks model-adaptation seam.** Per-version chapters live at
  `plugins/playbooks/skills/fable-5/context/model-adaptation/<model-version>.md` (`opus-4-8.md`,
  `opus-5.md`). Routing is by model VERSION, never family (`SKILL.md` meta-rule 3): a missing
  version file routes to the nearest prior version's file, whose preamble directs method-only
  application — never verbatim adoption of a sibling version's deltas. Chapters open with
  conditional framing ("if you are not X…") because spawn-time model overrides can hand a chapter
  to a model it was not written for.
- **Audit catalog.** `plugins/claude-config/skills/audit-instructions/reference/criteria.md`
  defines the `Model scope: <version>` annotation (its "Model scoping" section): a scoped row
  fires only on exact string equality of the normalized version token and is otherwise inert,
  reported as `skipped-for-target` — a near-miss target (point release, dated full ID) skips
  rather than inherits. The consuming skill's `--target-model` resolution fails loud on
  version-ambiguous values instead of guessing that a family alias such as `opus` means its
  newest version. I8's model rows and I10 carry the annotation with "promotion gate unmet"
  recorded inline.
- **Ingestion profile.** New doc slices arrive scoped at the source: the docpage-digest Anthropic
  profile model-matches digest agents to the doc's subject model
  (`plugins/knowledge/skills/docpage-digest/context/anthropic-docs-profile.md`, "Digest-agent
  model matching").

## Consequences

Cross-version doctrine misfire — the defect class this replaces — is now structurally impossible
without bypassing the seam: an upstream reversal lands as a new version file or new scoped rows,
and accepted files for prior versions stand as historical records rather than being rewritten.

Verified upstream guidance deliberately stays inert for non-matching models until the gate is met.
This looks like under-application to a reader without this context; the `skipped-for-target`
report line is the transparency mechanism, and this record is the rationale.

Target-model resolution is load-bearing. A version-ambiguous target aborts an audit run rather
than proceeding on a guess, which trades occasional friction (the operator must pass
`--target-model`) for never misfiring a scoped row.

Each new model version carries an onboarding cost by design: its own chapter and rows, plus a
promotion-gate review of existing scoped claims for convergence. The gate is the only path by
which that per-version cost amortizes into fleet-wide doctrine.

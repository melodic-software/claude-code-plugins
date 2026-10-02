# Recommendation basis: grounding what is put to the user

## Contents

- [Boundary](#boundary)
- [What counts as a recommendation](#what-counts-as-a-recommendation)
- [Grounding bar](#grounding-bar)
- [Basis label](#basis-label)
- [Re-emitting a changed recommendation](#re-emitting-a-changed-recommendation)
- [Routing](#routing)
- [Plugin-shipped copies](#plugin-shipped-copies)
- [Enforceability](#enforceability)
- [Adopters](#adopters)
- [Versioning](#versioning)

Owner doc for **how a recommendation is grounded before it is presented and labeled when it is**.
A recommendation is grounded in the affected code and in current external consensus, carries a
visible `Basis:` label (or, when consequential and unsettled, is withheld as an open question),
and, when later evidence changes it, is re-stated as old → new → why.

Several skills already practice parts of this under their own names (see
[Adopters](#adopters) for the prior art), with no shared definition of the bar or the label. Under
the [convention registry](../../plugin-philosophy.md#convention-registry)'s one-owner-per-concern
rule, this doc is that shared definition.

## Boundary

This doc owns the bar a recommendation clears, the label it carries, and the shape of its
re-statement. It does not own:

- **What makes a source authoritative.** The source-tier, corroboration, and recency vocabulary is
  defined once in `/discipline:do-your-research`, section `"An authoritative source" is a bar with
  three dimensions` ([`SKILL.md`](../../../plugins/discipline/skills/do-your-research/SKILL.md)),
  which in turn defers to the contract `/discovery:research` states. This doc uses those terms and
  does not redefine them.
- **Durable records of upstream-derived facts.** A recommendation written into a committed file as
  a standing decision carries the record the
  [upstream-drift convention](../upstream-drift/README.md#required-parts) requires: our decision, a
  pointer, an as-of date and a recheck trigger. The `Basis:` label covers what is said to the user
  in session; the record covers what is stored.

## What counts as a recommendation

An option, verdict, default, or next step put to the user for a decision. A question with a
suggested answer counts; so does "I would do X next". A statement of fact the user did not have to
decide on is a claim, governed by the research discipline, not by this doc.

## Grounding bar

Before a recommendation is presented, it is grounded on two sides:

- **Local.** Read the code, config, or document the recommendation changes, then list its
  consumers and blast radius: callers, dependents, and other repositories that consume a shared
  artifact (for example, every repo that pins a shared action or reusable workflow). A
  recommendation about a shared surface that names no consumers has not cleared the bar.
- **External.** Establish the current consensus across tiered sources: official documentation
  first, then authoritative articles and recognized experts, then community sources. Note the date
  or version each source reflects, and name any credible dissent rather than averaging it away.
  Tier, corroboration, and recency carry the meanings do-your-research gives them.

**Consequential recommendations must clear the bar.** A recommendation is consequential when it
is cross-repo, touches shared infrastructure, is irreversible or costly to reverse, or affects
security. Any other recommendation may rest on judgment, provided its label says so.

## Basis label

Every recommendation ends in exactly one of three outcomes. The first two are presented with a
visible `Basis:` label; the third is not presented:

- **verified**, followed by what verified it: a `file:line`, a tool output, or a URL fetched this
  session. Recall and a summary of an unread source do not qualify.
- **`judgment`**, for a recommendation resting on reasoning without that grounding. Allowed only
  for a recommendation that is not consequential.
- **withheld**, for a consequential recommendation that cannot be settled. It carries no `Basis:`
  label; it is surfaced as an open question that names the evidence that would settle it.

Example: `Basis: verified, .github/workflows/ci.yml:42 and https://docs.github.com/... (fetched
this session)`, or `Basis: judgment`.

## Re-emitting a changed recommendation

When evidence changes a recommendation the user still has pending, restate it as **old → new →
why**: the superseded recommendation named as superseded, the replacement in its own outcome (a
`Basis:`-labeled recommendation, or the withheld open question), and the evidence that moved it. Re-state only the recommendations that moved; name the rest as
unchanged in one line. A pending recommendation the session has disproved is worse than none,
because the user decides against it.

The shape is adopted from `/planning:interview`'s out-of-band drift rule, outcome 2 and "Re-present
narrowly" in
[`plugins/planning/skills/interview/context/loop.md`](../../../plugins/planning/skills/interview/context/loop.md)
(lines 267-270). That file owns the wording; this doc generalizes it beyond an interview round.

## Routing

When a quick read will not settle the bar, ground through `/discovery:explore` for the local side
(affected code, consumers, blast radius) and `/discovery:research` for the external side
(consensus, recency, dissent), when the `discovery` plugin is installed. Without it, do the same
reads and fetches inline. A recommendation still unsettled after that takes the `judgment` outcome
when it is not consequential and the withheld outcome when it is (see [Basis label](#basis-label)).

## Plugin-shipped copies

A shipped plugin cannot resolve a relative pointer into this repository's `docs/`, because only
the plugin's own directory is installed. A plugin that applies this contract states its essentials
(the grounding bar, the consequential threshold, the three outcomes, and the re-emit shape) in its own shipped text, once, and links here by absolute URL. The `discipline`
plugin does so in `plugins/discipline/context/recommendation-basis.md`, the canonical copy; each
other adopting plugin ships a byte-identical `context/recommendation-basis.md`, registered in
`scripts/cross-plugin-source-registry.txt` so a drifted copy fails CI.

## Enforceability

Classified per `melodic-software/standards` `conventions/engineering/enforceability-tiers.md`:
**reasoning-only**. Whether a recommendation is consequential, and whether its grounding reached
the bar, are judgments about meaning. Presence of a `Basis:` label is greppable in a saved
transcript, but no check is built.

## Adopters

Prior art, each practicing part of this contract under its own wording:

| Surface | What it practices |
|---|---|
| `/improvement:find`, "Evidence ladder" ([`SKILL.md:94`](../../../plugins/improvement/skills/find/SKILL.md)) | Model judgment is the weakest rung, "always labeled as such": the `judgment` label. |
| `/overengineering:audit`, "Consumer-agnostic" ([`SKILL.md:239-242`](../../../plugins/overengineering/skills/audit/SKILL.md)) | Nothing is assumed about the consumer; every discovery probe resolves what the consumer actually declares: the local side of the bar. |
| `/github:advise`, "Ground every recommendation" ([`SKILL.md:36-39`](../../../plugins/github/skills/advise/SKILL.md)) | Fetch integrity and a refusal branch that labels unavoidable recall as unverified: the external side and the label. |
| `/planning:interview`, out-of-band drift ([`loop.md:267-270`](../../../plugins/planning/skills/interview/context/loop.md)) | The old → new → why re-statement this doc adopts. |

Conforming with this contract's 1.0.0:

| Surface | What a reader can rely on |
|---|---|
| `discipline` shipped contract (`plugins/discipline/context/recommendation-basis.md`) | The essentials of this contract, stated once for the plugin's skills. |
| `discipline` loop, step 4 "Report" (`plugins/discipline/context/re-anchor-audit-correct.md`) | A corrector whose audit changed a pending recommendation re-states it old → new → why. |
| `/discipline:do-your-research` | Pending recommendations are an audit unit: each is grounded on both sides and reported old → new → why, or unchanged with why, as verified, judgment, or withheld. |
| `/discipline:do-your-research-deep` | Recommendations are an inventory type with one ledger row each, including a withheld verdict for an unsettled consequential one. |
| `/discipline:pick-for-the-problem` | The chosen tool or approach carries a `Basis:`, or is withheld as an open question when research cannot settle a consequential choice. |
| Shipped copies of the contract (`plugins/<plugin>/context/recommendation-basis.md` in `planning`, `source-control`, `github`, `work-items`, `naming`, `architecture`, `code-tidying`, `debugging`, `harness-ops`, `session-flow`) | The essentials, byte-identical to the `discipline` copy, held in sync by `scripts/check-cross-plugin-source-drift.sh`. |
| `/planning:interview` (`SKILL.md` "Ground before recommending", "Recommended answers") | Every `My recommendation:` line has a `Basis:` line; a consequential question research cannot settle is asked open with a `Withheld:` line; a revised recommendation is re-stated old → new → why. |
| `/planning:design`, `/planning:prd`, `/planning:brainstorm` | Each recommendation carries a `Basis:`; a consequential one is grounded through explore and research, or withheld as an open question. |
| `/source-control:pull-request`, `/source-control:babysit-prs`, and their shared `reference/review-discipline.md` D3/D4 | A fix, verdict, or merge that changes a shared artifact lists and checks its consumers first; the verdict carries a `Basis:`, and an unsettled consequential one is UNCERTAIN, naming the evidence that would settle it. |
| `/github:advise` | Advice on something other repositories consume lists the repositories it reaches with read-only calls; each recommendation carries a `Basis:` or is withheld as a decision point. |
| `/work-items:triage`, `/work-items:decompose` | A decision-defaulted answer is well-grounded by this bar, with its `Basis:` on the line after the `Decision defaulted` prefix, and a withheld one routes to human-gated; each HITL/AFK call carries a `Basis:`. |
| `/adhd:clarify` | A clarified decision table carries the source's `Basis:` verbatim in its own column, and renders a withheld item as withheld. |
| `/naming:name-it-better`, `/architecture:improve` (Design-It-Twice), `/code-tidying:tidy`, `/code-tidying:batch-simplify`, `/debugging:debug`, `/harness-ops:known-issues`, `/session-flow:retro` | The skill's recommendation (pick, winning interface, finding, deferral, post-fix recommendation, SAFE / CAUTION / DO NOT USE verdict, Phase 3 row) carries a `Basis:` or is withheld as an open question. |

Other surfaces adopt on touch.

## Versioning

This contract is versioned in [`CHANGELOG.md`](CHANGELOG.md). Changing the grounding bar, the
label's values, or the re-emit shape is a major bump; additive guidance is a minor bump; docs-only
clarification is a patch.

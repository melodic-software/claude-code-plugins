# Escalations

Findings a lane surfaced that the lane does not own, and that must be decided before its
remediations can be applied. Each blocks a specific set of wave 3 edits.

## E1. `PLUGIN-PHILOSOPHY.md` prescribes what the public-surface contract forbids

**Raised by:** L4-encapsulation. **Blocks:** 30 of that lane's 89 violations, the whole
sibling-skill-reach class.

`docs/PLUGIN-PHILOSOPHY.md:337-342` instructs authors to write a cross-skill citation like this:

> Apply the same anchoring rule to bundled assets: one skill citing another skill's supporting file
> writes the full `${CLAUDE_PLUGIN_ROOT}/skills/<other-skill>/<path>` form, optionally paired with a
> relative markdown link target for browsing on GitHub

That passage takes cross-skill citation of a supporting file as legitimate and regulates only the
path *form*, so that the path resolves correctly rather than against the citing skill's directory.

`plugins/docs-hygiene/skills/audit-encapsulation/context/public-surface-contract.md` rules the
citation itself out, whatever form the path takes:

> A skill's `scripts/` directory is its declared entry surface. Harness surfaces, CI workflows, git
> hooks, and automation registries MAY path-cite `scripts/` entry scripts directly. **Sibling skills
> may NOT** — skill-to-skill stays slash-only.

and defines every non-public file inside a skill as private, listing `context/` and `reference/`
by name.

These cannot both hold. One says *write the cross-skill path this way*; the other says *do not write
a cross-skill path*. Thirty call sites follow the philosophy doc and therefore violate the contract.

**This is not a call-site defect and must not be remediated as one.** Rewriting thirty citations
while the doctrine that produced them stands would leave the repo self-contradicting and the
citations would come back. The decision is which document is wrong:

- **Narrow the contract.** Accept intra-plugin sibling-skill citation as legal when written in the
  anchored form, on the grounds that skills within one plugin ship and version together, so the
  rip-and-paste portability the contract protects is not at risk between them. Costs: the contract
  stops being a clean rule; `audit-encapsulation` needs its detector and its filter taxonomy
  updated to match, and the 30 findings dissolve.
- **Correct the philosophy doc.** Delete or invert the passage, then remediate the 30 call sites to
  slash invocations or promoted shared docs per the contract's Path A / Path B. Costs: 30 call
  sites change, some of which cite genuinely cross-cutting content that has no action to route
  through, so Path A promotions would have to be authored.

Both are defensible. The choice is the repository owner's, not a lane's and not the orchestrator's.

**Until this is decided, wave 3 applies none of the 30 sibling-skill-reach findings.** The other 59
L4 violations are unaffected and proceed normally.

## E2. Both L1 deletion verdicts are provisional

**Raised by:** L1-derivability. **Blocks:** 2 of that lane's 3 actionable files.

The derivability rubric requires a fresh-context spot-test before a deletion verdict: hand the
question to an agent that has not seen the reasoning and check whether it re-derives the document's
conclusions unaided. No lane can spawn one, so neither `delete` verdict cleared that gate.

The orchestrator can spawn subagents and will run the spot-test in wave 3, before applying either
deletion. If the spot-test is skipped, both verdicts downgrade to `convert-to-pointer`, which is
reversible where deletion is not.

Affected: `plugins/ai-briefing/skills/generate/context/execution-flow.md`,
`plugins/repo-hygiene/skills/clean/reference/ecosystems.md`.

## E3. `compress` cannot run its own safety gate

**Raised by:** the orchestrator, on dispatching L6. **Blocks:** every compression edit.

`docs-hygiene:compress` makes a semantic-diff subagent a mandatory gate on its default action, and
requires that the compressing context not be the verifying context. A lane lead cannot spawn one,
so the default action is structurally unavailable to lanes. L6 was scoped to the read-only `audit`
action instead.

The orchestrator runs the semantic-diff gate in wave 4, from a context that can spawn subagents.
No compression edit ships without passing it.

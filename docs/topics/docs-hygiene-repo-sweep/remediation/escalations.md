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

### Spot-test result: `repo-hygiene/skills/clean/reference/ecosystems.md`

**Verdict: passes. The `delete` stands.**

A fresh agent, told only not to open the file, was asked to reconstruct the per-ecosystem cleanup
definitions from everything else. It answered "yes, complete and confident" and produced a full
account: tier membership for `caches`, `build`, `git` and `tree`, all three protected-path classes,
sweep semantics down to the manifest flow and the submodule and symlink handling, each claim cited
to a line in `reference/cleanup-config.md`, `scripts/lib/cleanup-paths.sh`,
`scripts/lib/clean-common.sh` or `SKILL.md`.

It also surfaced corroboration nobody pointed it at: `plugins/repo-hygiene/CHANGELOG.md:85-90`
records that in v0.10.4 this file was already converted to "a pointer, not teaching tables" after a
fresh-context agent reproduced "the full tier membership, protected classes, and the 'no `dotnet
clean`' rationale" from the same sources. The deletion finishes a conversion the repo started.

**Caveat, and it is the orchestrator's error, not the agent's.** The brief excluded the subject
file but not this sweep's own findings directory, so the agent read L1's `delete` verdict and the
quoted opening line before finishing. The test was therefore not fully blind. Two things keep the
result usable: the substantive re-derivation is sourced to primary files with line numbers, none of
which the findings note supplied, and the CHANGELOG corroboration is independent of both. A future
spot-test brief must exclude `docs/topics/docs-hygiene-repo-sweep/**` as well as the subject file.

### Spot-test result: `ai-briefing/skills/generate/context/execution-flow.md`

**Verdict: fails. The `delete` is overturned. Salvage first, then remove.**

The fresh agent answered "partially", and named in advance several things it could not recover from
any other source. Checking the file against that list afterwards, four of its rules appear nowhere
else in the skill. `grep -ic` over `SKILL.md` and all of `references/` returns zero for each:

- **Re-run idempotency.** "Re-running the same window is idempotent: merge by canonical event
  identity and do not emit duplicate items." The agent flagged this exact gap: "Nothing reachable
  states what a second identical run does to state."
- **Outbound failure policy.** "Set explicit timeouts for outbound requests and make partial
  failures visible." The agent noted eval 6 requires visible degradation while no reachable file
  says so.
- **Empty-bucket emission.** "Empty requested provider buckets are explicit rather than silently
  omitted."
- **State-write ordering.** "Update the seen-item registry only after successful markdown emission."

So the document is not subsumed by `SKILL.md`, and a bare deletion drops four behavioral rules.
This is precisely the failure the rubric's fresh-context gate exists to catch, and without the gate
the sweep would have deleted them.

The agent's own hypothesis was wrong in an instructive way. It supposed the undefined stage
vocabulary (`S4`, `Step 4.5`, `Step 5`, used in `references/audience-defaults.md:4,42` and
`references/build-pipeline.md:253,255`) was defined in this file. It is not: the file numbers its
stages 0 to 7, `SKILL.md` numbers its own 1 to 9, and neither defines the `S`-prefixed scheme. That
vocabulary is dangling everywhere, which is a separate finding routed to L5 as a `ghost-ref` class.

**Revised remediation, replacing L1's:**

1. Salvage the four rules into `SKILL.md` at the steps they govern.
2. Then delete the file, or wire a pointer to it from `SKILL.md`. It is genuinely unreachable today,
   nothing in the plugin references it, so the orphan half of L1's finding stands.

L1's own note said "two lines must be salvaged into `SKILL.md` first", so it saw the shape of this.
The count was low and the verdict was too strong.

### Two further defects surfaced by the spot-tests

Neither is this sweep's to fix; both are recorded so they are not lost.

- `plugins/ai-briefing/skills/generate/references/providers.md` **does not exist** but is cited
  twice, at `references/build-pipeline.md:5` ("For provider buckets / query templates, see
  `providers.md`") and `:172` ("13-bucket schema per SKILL.md / providers.md"). `SKILL.md` carries
  no bucket list either, so the 13 buckets are recoverable only from
  `references/slide-generation.md:113-130`. A live `ghost-ref`.
- `*.sln.docstates.suo` is matched by `clean_path_is_protected` at
  `scripts/lib/clean-common.sh:86`, but the protected-paths prose at
  `reference/cleanup-config.md:71` lists only `**/*.csproj.user` and `**/*.suo`. Whether that is
  intentional shorthand or real drift needs the drift test's expectations, not this sweep.

## E3. `compress` cannot run its own safety gate

**Raised by:** the orchestrator, on dispatching L6. **Blocks:** every compression edit.

`docs-hygiene:compress` makes a semantic-diff subagent a mandatory gate on its default action, and
requires that the compressing context not be the verifying context. A lane lead cannot spawn one,
so the default action is structurally unavailable to lanes. L6 was scoped to the read-only `audit`
action instead.

The orchestrator runs the semantic-diff gate in wave 4, from a context that can spawn subagents.
No compression edit ships without passing it.

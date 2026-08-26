# Escalations

Findings a lane surfaced that the lane does not own, and that must be decided before its
remediations can be applied. Each blocks a specific set of wave 3 edits.

## E1. `PLUGIN-PHILOSOPHY.md` prescribes what the public-surface contract forbids

**Raised by:** L4-encapsulation. **Blocks:** 65 of that lane's 89 violations. It was raised as 30,
the sibling-skill-reach class; measuring it afterwards showed the ruling reaches more than twice
that. See the corrections below.

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

### Ruling: the plugin, not the skill, is this repo's unit of distribution

Neither document is simply wrong. They disagree because they assume different units.

The contract's whole rationale is rip-and-paste portability: "moving `.claude/skills/<name>/` into
another repo carries every implementation detail with it; nothing outside the skill depends on
internal layout." That protects a skill directory moved on its own. But nothing in this repository
ships that way. The distribution unit here is the **plugin**: it carries a `plugin.json` with its
own version, it is what a consumer enables, and its skills version and travel together. Two skills
in one plugin cannot be separated by any installation a consumer can perform.

The contract also anticipates exactly this. It says: "A consuming repo may layer its own conventions
on top." `docs/PLUGIN-PHILOSOPHY.md` is that layer.

So:

- **Intra-plugin sibling-skill citation, in the anchored `${CLAUDE_PLUGIN_ROOT}/skills/<other>/<path>`
  form, is legal in this repository.** It cannot produce the breakage the contract exists to
  prevent, because the two skills are never distributed apart.
- **Cross-plugin citation into another plugin's skill privates remains a violation.** Plugins install
  independently, so the cited path can genuinely be absent at runtime. This is the case the contract
  is actually about.
- **A citation that does not resolve from its own base is a defect, whatever its form.** This
  replaces an earlier clause that said bare relative paths stay defects. That clause was wrong, see
  the corrections below.
- **Heading anchors stay private even intra-plugin.** They are body structure, not a file the plugin
  ships as a unit; renaming a heading is exactly the refactor the contract protects.

### Three corrections to this ruling, from the measurement that tested it

The classification pass was told to say if the evidence contradicted the ruling. It did, on three
points, and it was right on all three.

**The bare-relative clause was factually wrong and is withdrawn.** `PLUGIN-PHILOSOPHY.md:341-342`
condemns a bare `context/…` path written with **no** `../` prefix, which resolves against the citing
skill's own directory and therefore misses. **Zero of the 89 citations use that shape.** The 33
relative intra-plugin citations all compute a correct `../` path and all 33 resolve, verified
individually. The ruling originally leaned on that clause to keep 49 findings alive; it cannot.

**This ruling narrows the contract, it does not merely read it.** The sentence licensing a consuming
repo's conventions has a second half that was omitted: "A consuming repo may layer its own
conventions on top, **but the surfaces and carve-outs below are what the detector implements**"
(`public-surface-contract.md:3`). And the portability guarantee is stated at the skill-directory
level, not the plugin level: "moving `.claude/skills/<name>/` into another repo carries every
implementation detail with it" (`:27`). The ruling stands on the repo's real distribution shape, 71
plugin manifests each with one version, 71 marketplace entries each pointing at a plugin directory,
no per-skill manifest, and no `.claude/skills/` tree in this repo at all. But it is a deliberate
narrowing of a stated guarantee and is recorded as one.

**The blast radius is 65, not 30.** The ruling was written as if it touched only the 30
sibling-skill reaches. Intra-plugin as defined also legalises 16 plugin-README citations and 23
plugin-level doc citations, which the escalation had listed as unaffected. The READMEs matter most:
the contract names READMEs explicitly as external consumers. Under the distribution-unit reasoning
they are not external, because a plugin's README ships with the plugin, and that consequence is
accepted deliberately rather than absorbed unnoticed. Four of the 30 sibling reaches cross a plugin
boundary and stay violations.

### What the measurement found that nobody predicted

**Not one cited path is missing from disk.** All 89 targets exist, both heading anchors included.
The silent-breakage failure the contract exists to prevent has not occurred anywhere in this corpus.
That is the strongest evidence the escalation expected to find and it is absent, which argues the
contract is protecting against a risk this repo's actual practice already contains.

**Ten citations do not resolve from the base their own form implies.** The target exists; the
address does not reach it. All ten are bare code spans, so none renders as a broken link and nothing
greps red, but an agent told to open the path fails on all ten. This is the real defect class, and
it is what the revised form clause above now catches.

The sharpest case: `plugins/discovery` cites the same three targets twice, correctly anchored at
`reference/parent-contract.md:15-17` and unresolvably bare at `reference/topic-docs.md:88-89`. One
plugin, two forms, one broken. That is direct evidence that legalising intra-plugin citation without
also requiring a resolvable form produces drift inside a single plugin, which is why the form clause
is not optional.

**`docs/PLUGIN-PHILOSOPHY.md` breaks its own rule twice**, at `:581` and `:1056`, and one is a live
Convention-registry row other plugins consult. Defective under any reading; fixed in wave 3.

### Settled remediation set

Of the 89: **55 dissolve, 34 remain.** The 34 are 24 cross-plugin, 8 non-resolving intra-plugin, and
2 heading anchors. A further 57 intra-plugin citations would benefit from normalising to the
anchored form; that is a tidy-up, not a defect, and is not part of this sweep.

**Where the convention gets written down matters.** Not in
`public-surface-contract.md`: that file ships inside a plugin to other repositories and claims
general applicability, so editing it would export this repo's relaxation to everyone who installs
`docs-hygiene`. The correct home is a `docs/conventions/` entry, which is precisely the "layer on
top" the contract's own line 3 describes. `PLUGIN-PHILOSOPHY.md` gains the cross-plugin limit it
currently omits.

Two follow-on edits this ruling requires, both in wave 3:

1. `docs/PLUGIN-PHILOSOPHY.md` must state the cross-plugin limit it currently omits. As written it
   reads as blanket permission, which is how 30 call sites came to exist.
2. `public-surface-contract.md` must record that this repo layers that convention, so the next audit
   does not re-raise the same 30 findings. The contract's own "consuming repo may layer" sentence is
   the hook to hang it on.

### Amendment, after the classification pass

The measurement in `e1-classification.md` checked the ruling instead of confirming it, and found
four things wrong with it. Three are corrections to this section's reasoning and one changes what
wave 3 actually does. The conclusion survives; several of the arguments given for it did not.

**The distribution-unit argument stands, and is now evidenced.** 71 plugins, 71
`plugins/<p>/.claude-plugin/plugin.json` manifests carrying exactly one `version` each, 71
`marketplace.json` entries sourced at `./plugins/<name>`, no per-skill manifest anywhere, and no
`.claude/skills/` directory in this repo at all. Skills here do not ship or version independently.

**Correction 1. The reason given for rejecting bare relative paths was a category error.** This
section claimed a bare relative cross-skill path "stays a defect on the philosophy doc's own
reasoning". It does not. The doctrine condemns one specific shape, `context/x.md` written with no
`../` prefix from inside a skill, and **zero of the 89 violations use that shape**. All 33 relative
intra-plugin citations use a correctly computed `../` path and every one resolves on disk. They are
not defects and wave 3 leaves them alone.

What is genuinely broken is a different shape the ruling never named: 8 citations in `plugin-root`
form, `skills/<s>/<path>` written from a plugin-level `reference/` directory, where the implied base
is the plugin root but the real base is the citing file's own directory. Those do not resolve. They
are defects on their own merits, not on doctrine, and wave 3 fixes them.

**Correction 2. The contract's licence was quoted selectively.** This section cited "A consuming
repo may layer its own conventions on top" as authorizing the ruling. The full sentence continues
"but the surfaces and carve-outs below are what the detector implements", which reasserts the
detector against whatever is layered. The sentence permits the ruling; it does not authorize it, and
quoting half of it overstated the case. The ruling rests on the distribution-unit evidence above,
not on that sentence.

**Correction 3. The blast radius was understated by more than half.** This section said the decision
blocks 30 violations and leaves 59 unaffected. The real split is **65 INTRA, 24 CROSS**. `INTRA`
covers every plugin README and plugin-level doc citing its own plugin's skills, which this section
had counted among the unaffected. In particular **16 plugin README citations become legal in one
move**, and the contract names READMEs explicitly as external consumers. That consequence was never
discussed here and is the substantive thing this ruling does. It is stated now so it is chosen
rather than inherited.

**Correction 4. The corpus contains no instance of the harm the contract predicts.** Across 89
violations and 35 leaked skills, no cited path is missing. No skill here has yet renamed a private
file out from under an external citation. This cuts both ways and is recorded rather than argued
from: it weakens the urgency of remediating what survives, and equally weakens any claim that the
65 dissolved citations were doing damage. Note also that 8 of the 10 unresolvable citations are
intra-plugin, so proximity did not prevent them.

### What wave 3 does, restated

- **Dissolve 65 INTRA citations.** No edit. This includes the 16 plugin READMEs.
- **Remediate 24 CROSS citations**, including 4 sibling-skill reaches that cross a plugin boundary
  and which the roll-up files under the dissolved class: `V-sc-15`, `V-ops-01`, `V-auto-01`,
  `V-ct-01`.
- **Fix 8 unresolvable `plugin-root`-form citations** regardless of classification, because a path
  that does not resolve is broken whatever the doctrine says.
- **Treat the 2 heading anchors separately.** They stay private even intra-plugin, so `V-dh-01`
  comes out of the dissolved README list.
- **Edit both doctrine documents** so the next audit does not re-raise the dissolved 65:
  `PLUGIN-PHILOSOPHY.md` gains the cross-plugin limit it omits, and the contract records the
  layered convention.

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

## E4. `write-for-agents` disclaims the surface L7 was pointed at

**Raised by:** L7-write-for-agents as its conflict C1. **Blocks:** 8 of that lane's 13 findings.

`docs-hygiene:write-for-agents` says of itself that it "does not author skills, a SKILL.md is
`playbooks:skill-authoring` + `skill-quality:check` territory." Every one of the 250 `T2` rows in
the agent-audience slice is a `SKILL.md` (237) or an agent definition (13). Read at its widest, the
skill disclaims the entire highest-cost stratum the lane exists to protect. L7 declined to rule and
asked for `skill-quality:check` concurrence.

### Ruling: the disclaimer is about authorship, not prose

Authoring a skill means deciding that it should exist, what it triggers on, what its frontmatter
declares, how its actions are shaped, and how its body is structured. That is genuinely
`playbooks:skill-authoring` and `skill-quality:check` territory, and this lane must not touch it.

It is a different thing from whether a sentence inside an already-authored skill reads well to the
agent loading it. A `SKILL.md` is agent-consumed markdown, which is precisely and only what
`write-for-agents` governs. Reading the disclaimer to cover prose quality would leave the repo's
single largest agent-facing surface, 250 files whose cost recurs for the rest of a session once
triggered, governed by no authoring doctrine at all. No reading that produces that gap is right.

So the line is:

- **In scope for L7**: prose inside an existing skill body. Pointer phrasing, a step deferring a fact
  it needs, sentence-level clarity. All 8 disputed findings are of this kind; the predicate carrying
  most of them is P3, front-loading a pointer's leading word.
- **Out of scope for L7**: creating a skill, changing frontmatter or its description, adding or
  reshaping actions, restructuring the body, splitting or merging sections. Structural splits belong
  to L2, and `skill-quality:check` owns frontmatter.

No concurrence is needed, because the ruling does not take anything from `skill-quality:check`.
Wave 3 applies all 13 findings, and any that turn out to require a structural change rather than a
prose change is reclassified to L2 at that point rather than applied here.

`write-for-agents`'s own disclaimer sentence should be narrowed in wave 3 to say "does not author
skills" rather than leaving "a SKILL.md is other territory" to be read as covering its prose. That
edit is inside a `docs-hygiene` skill body and is in this sweep's scope.

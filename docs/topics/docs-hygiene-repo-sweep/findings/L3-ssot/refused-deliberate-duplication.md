# Refused clusters: deliberate, guarded, or already-cited duplication

Ten clusters that a mechanical duplication scan surfaces loudly and that must NOT be remediated.
Each is recorded with the evidence that refuses it, so the reconciliation and the later lanes can
see it was examined rather than missed, and so a future sweep does not re-open it.

Aggregate: **roughly 210 file-instances of repeated text refused on evidence.** That is the
majority of everything the mechanical pass found.

The repository has a documented doctrine that produces most of this: plugins ship to consumers who
do not have the marketplace repository, so a contract is carried inline at every adopting site
rather than reduced to a pointer, and the citation is provenance-only. It is stated at
`docs/conventions/untrusted-content/README.md:34` and generalized in this skill's own
`context/lessons.md` "Lesson 13". A sweep that does not know this doctrine will propose deleting
the fleet's load-bearing text.

---

## R1: `plugin-lifecycle-artifact-protocol` (6 files, REGISTERED + CI-CHECKED)

**Sites.** `docs/PLUGIN-ARTIFACT-PROTOCOL.md`,
`plugins/discovery/reference/artifact-protocol.md`,
`plugins/implementation/reference/artifact-protocol.md`,
`plugins/overengineering/reference/artifact-protocol.md`,
`plugins/planning/reference/artifact-protocol.md`,
`plugins/verification/reference/artifact-protocol.md`.

**Extent.** 352 words verified as one shared block; all six files hash identically
(`bab2c6244f43f46fa47431b1c2cf1b69`).

**Refusal evidence.** `scripts/cross-plugin-source-registry.txt`:

> `# Dedicated check: scripts/validate-plugin-contracts.mjs (lifecycleProtocolCopies)`
> `reference/artifact-protocol.md`

The copies are a registered cluster with a named CI check asserting byte-identity. This is
identify form (f): the sync mechanism IS the dedup. `REFUSE-language-native-dedup`.

---

## R2: `standards-contract-mirror` (3 files, REGISTERED + CI-CHECKED)

**Sites.** `docs/conventions/standards/README.md`,
`plugins/planning/reference/standards-contract.md`,
`plugins/review/reference/standards-contract.md`. The two plugin copies hash identically
(`7ab7c56bd2ec2091d8a505aff8750382`).

**Extent.** 1930 words as one shared block. The single largest repeated block in the corpus.

**Refusal evidence.** `scripts/cross-plugin-source-registry.txt`:

> `# Dedicated check: scripts/sync-standards-contract.sh --check (CI: standards-contract-sync)`
> `reference/standards-contract.md`

`REFUSE-language-native-dedup`.

---

## R3: `plugin-options-generated-block` (34 READMEs, GENERATOR-OWNED)

**Sites.** 34 plugin `README.md` files, each carrying an identical `### Options reference` and
`### How to set these` block.

**Refusal evidence.** Each block is delimited:

> `<!-- ai-slop-ignore-start: generated options block; source is plugin.json + scripts/sync-plugin-options-docs.py -->`
> `<!-- BEGIN GENERATED: plugin options — edit plugin.json, then run scripts/sync-plugin-options-docs.py -->`

The generator is the dedup. Editing 34 READMEs would be undone on the next regeneration. Any
wording change belongs in `scripts/sync-plugin-options-docs.py`.

`config-extract-advisory`. `context/lessons.md` "Lesson 14" additionally warns that counting these
as call sites inflates a roster by exactly this number, which is what happened in the previous
whole-repo batch.

**One live defect, routed elsewhere.** The generated block's wording of the `already installed`
claim differs from the canonical in `docs/PLUGIN-PHILOSOPHY.md:298`. That is a one-line fix in the
generator's template, recorded in `plugin-setup-contract-recaps.md` sub-cluster 1.

---

## R4: `fleet-changelog-entries` (64 CHANGELOGs)

**Sites.** Every `plugins/*/CHANGELOG.md`.

**Extent.** Normalized-line frequency found lines repeated across 60 to 66 files, for example a
66-file line beginning `/ai-slop:audit fix semantics: periods or commas, or a restructured
sentence, never` and a 60-file line beginning `Keep a Changelog`.

**Refusal.** A changelog is a per-plugin historical record. A fleet-wide sweep genuinely landed in
64 plugins and each plugin's changelog is obliged to record it. Collapsing the entries would
destroy the record. Identify form (g): per-instance content that is unique in role even where the
text is shared.

`REFUSE-intentional`. The 64 changelogs are excluded from every other cluster's instance counts in
this lane's findings.

---

## R5: `untrusted-content-spine` (about 18 adopters, CONVENTION MANDATES INLINE)

**Sites include.** `plugins/github/skills/advise/SKILL.md:104`,
`plugins/github/skills/audit/SKILL.md:107`, `plugins/discovery/agents/explorer.md`,
`plugins/discovery/agents/researcher.md`, `plugins/discovery/agents/intent-tracer.md`,
`plugins/playwright/skills/playwright/SKILL.md`, `plugins/playbooks/skills/boris/SKILL.md`,
`plugins/playbooks/skills/skill-authoring/SKILL.md`,
`plugins/knowledge/skills/book-distill/SKILL.md`,
`plugins/knowledge/skills/docpage-digest/SKILL.md`,
`plugins/plugin-quality/skills/audit/SKILL.md`, `plugins/plugin-quality/agents/auditor.md`,
`plugins/work-items/reference/item-content-trust.md`,
`plugins/dometrain/skills/grounding/SKILL.md`, `plugins/github/reference/change-routing.md`,
`plugins/github/reference/browser-automation.md`,
`plugins/playwright/skills/playwright/actions/update.md`, `plugins/playbooks/README.md`.

**Refusal evidence.** `docs/conventions/untrusted-content/README.md:32`,
`## The inline form adopters carry`:

> Plugins ship to consumers who do not have this repository, so the contract is **carried inline
> at every adopting site**, never reduced to a pointer. Adopters normalize one spine
> byte-identical and vary only the two slots around it

and at line 56:

> Reword the slots freely; never reword the spine, because a second wording is a second contract.

A conformance sweep already greps for `never instructions to you` and the quoted heading
`"The framing contract"`. `REFUSE-intentional`, and the remedy this lane would otherwise propose is
the exact thing the convention forbids.

---

## R6: `rate-limit-guard-floor-inline` (4 sites, DECLARED INLINE-FLOOR RULE)

**Sites.** `plugins/work-items/skills/attend-queue/SKILL.md:278`,
`plugins/work-items/skills/work-loop/SKILL.md:159`,
`plugins/source-control/skills/babysit-loop/SKILL.md:402`,
`plugins/docs-hygiene/skills/extract-ssot/context/orchestrated-mode.md:77`.
The owner is `plugins/rate-limit-guard/reference/reader-contract.md:13`.

**Refusal evidence.** Every site opens with its own declaration
(`plugins/work-items/skills/attend-queue/SKILL.md:280`):

> The operable floor below is inlined
> **verbatim** per the convention's inline-floor rule (byte-identical across lanes and to the reader
> contract's floor); provenance is the `rate-limit-guard` plugin's reader contract
> (`plugins/rate-limit-guard/reference/reader-contract.md` in the marketplace repository). Cited for
> provenance only, since an installed plugin cannot read a sibling plugin's files at runtime.

Verified byte-identical at all four sites this session. `REFUSE-already-cites-canonical`.

**This is the model.** It is the exact shape `lane-telemetry-upsert.md` proposes for the telemetry
cluster, which sits in the same three files and does not have it.

---

## R7: `autonomy-routine-axis-scaffolding` (10 to 13 files, PER-INSTANCE TABLE DATA)

**Sites.** `plugins/autonomy/reference/routines/*.md`, ten files.

**Extent.** Seven shared blocks of 20 to 103 words, the largest being the `| Axis | Value |`
prerequisite table shared by nine files.

**Refusal evidence, two parts.**

1. **Already cites.** The 10-file preamble (`plugins/autonomy/reference/routines/ci-health-review.md:58`):

   > [routine prerequisite resolution](../prerequisite-resolution.md). Axes derive through the
   > catalog mapping rules; the isolation floor and `executor_class` merge cap are cited from the
   > guardrail slice, never re-derived.

   And the admission block (line 92):

   > Admission disposition and fan-out caps for the derived class come from the
   > [admission policy](../guardrails/admission-policy.md) ... This leaf adds no routine-specific
   > admission or escalation rules.

   Each file declares itself a `Normative leaf of the [routine catalog](../routines.md)` in its
   first paragraph. Form (d).

2. **No drift.** The `Connector entitlements` row is byte-identical in 12 of 13 occurrences; the
   thirteenth differs because its routine's access class genuinely differs. The prerequisite
   preamble is byte-identical in 10 of 10.

**Verdict: WARN, refused.** The stability branch of the combined test passes (a wording change
forces ten lockstep edits) but the reader-burden branch fails decisively: every row names its owner.
Removing a row from an axis table would break the table's per-identity completeness, which is what
the catalog contract asks each leaf to provide. `REFUSE-low-roi`.

**Recheck trigger.** If the rows ever diverge without a corresponding difference in access class,
re-open as a `normalize-wording` cluster.

---

## R8: `discovery-agents-tool-honesty` (3 files, GUARDED BY A CONTRACT TEST)

**Sites.** `plugins/discovery/agents/explorer.md`,
`plugins/discovery/agents/intent-tracer.md:94`, `plugins/discovery/agents/researcher.md:91`.

**Extent.** 13 shared blocks totaling 650 words between `intent-tracer` and `researcher` alone.

**Refusal evidence.** `plugins/discovery/agents/tool-honesty.test.sh:1-18`:

> The defect this locks: `agents/researcher.md` carried a "Tool honesty"
> paragraph copied from `agents/explorer.md`, where it is true. The explorer
> declares a `tools:` allowlist that omits `Edit`, so "Edit is absent from your
> tool list" is a property of that file. The researcher declares no allowlist at
> all ... The class is
> mechanically detectable, so it is checked here rather than left to review.

The duplication in this trio has already been diagnosed, corrected, and locked with a scoped
contract test. The correct per-file text is now genuinely per-file: `intent-tracer` and
`researcher` share the no-allowlist wording because both declare no allowlist, and `explorer`
differs because it does. `REFUSE-intentional`, with a named guard.

---

## R9: `topic-docs-plugin-slices` (10 files, CITED CONVENTION SLICES)

**Sites.** `plugins/architecture/reference/topic-docs.md`,
`plugins/coupling/`, `plugins/discovery/`, `plugins/implementation/`, `plugins/overengineering/`,
`plugins/planning/`, `plugins/review/`, `plugins/session-flow/`, `plugins/verification/`,
`plugins/work-items/`, each at `reference/topic-docs.md`.

**Extent.** A 20-word shared block across five files, a 26-word block across three.

**Refusal evidence** (`plugins/discovery/reference/topic-docs.md:7`):

> Implements the topic-docs convention
> <https://raw.githubusercontent.com/melodic-software/claude-code-plugins/main/docs/conventions/topic-docs/README.md>
> the contract owns every general rule — tiers, schema, resolution order, slug spec, runtime guards

Each slice cites a fetchable contract URL and carries only its own plugin's binding. Form (d) plus
form (g). `REFUSE-already-cites-canonical`.

**Related.** `plugins/discovery/skills/setup/SKILL.md:20` and
`plugins/verification/skills/setup/SKILL.md:24` share 684 words across 6 blocks, and both open with:

> `<!-- Maintainer note: the rules below restate the topic-docs and marketplace setup contracts as this`
> `skill's own runtime instructions. Matching a sibling plugin's setup skill byte-for-byte is a`
> `coincidence of scope, not a shared artifact, the topic-docs contract's "Implementers restate`
> `the rules" section records why this is not extracted, and what would reopen that. -->`

A prior refusal, recorded in the files themselves with its reopening condition. `REFUSE-intentional`.
This is the pattern every other cluster in this lane should imitate.

---

## R10: `formatter-readme-requirements` (8 READMEs) and `commit-convention-well-known-path` (4 files)

**R10a, formatter README requirements.** Eight plugin READMEs carry a byte-identical bullet:

> - **Bash.** The hook is a Bash script. On native Windows, install
>   [Git for Windows](https://code.claude.com/docs/en/setup#set-up-on-windows) so
>   Claude Code can run it under Git Bash.

Sites: `plugins/actionlint/README.md:32`, `plugins/bash-format/README.md:53`,
`plugins/biome-format/README.md:40`, `plugins/eol-normalizer/README.md:34`,
`plugins/go-format/README.md:49`, `plugins/powershell-format/README.md:68`,
`plugins/ruff-format/README.md:46`, `plugins/typos-format/README.md:76`. Twelve further READMEs
state the same requirement in plugin-specific wording, which is form (h), domain-specific
application.

**Refusal.** A README Requirements section is an EXPOSE surface under this skill's own role
classification: it MAY restate when onboarding clarity outweighs maintenance cost. The text is one
short paragraph, cites a primary-source URL, and has not drifted across the eight. Both
`REFUSE-low-roi` (Lesson 5) and `REFUSE-primary-source-citation-gate` (Lesson 6) apply.

Four `plugins/*/README.md` also share a byte-identical `advisory, never blocking. The hook always
exits 0` line (`plugins/actionlint`, `plugins/bash-format`, `plugins/biome-format`,
`plugins/powershell-format`). Same verdict.

**R10b, commit-convention well-known path.** Four files carry a byte-identical five-line header:

> Commit-subject / PR-title convention for the source-control plugin, resolved by
> `/source-control:commit` and `/source-control:pull-request` before they infer from the repo's own
> CLAUDE.md/rules/commit-msg hook or fall back to the bundled Conventional Commits default.
> Re-run `/source-control:setup` to change these values.

Sites: `.claude/source-control.md:3`,
`plugins/source-control/skills/commit/.claude/source-control.md:3`,
`plugins/source-control/skills/pull-request/.claude/source-control.md:3`,
`plugins/source-control/skills/setup/.claude/source-control.md:3`.

**Refusal.** The header is emitted by a template that lives at
`plugins/source-control/skills/setup/reference/apply-convention.md:180`, where it appears verbatim
inside the indented block the skill writes. That template is the owner and the dedup mechanism.
All four copies are byte-identical to it, so there is no drift to fix. `REFUSE-template-owned`.

**Gap worth recording, not fixing here.** No check asserts that the four emitted copies stay in
step with the template. If one is hand-edited, nothing catches it. `code-extract-advisory`.

---

## Out of scope entirely

- `plugins/songwriting/context/pat-pattison/research/**`: twelve repeated passages between pairs of
  files. Distilled external teaching material, not this repository's own authoring. Excluded on the
  same ground as the vendor tree.
- `docs/topics/fable-field-guide-audit/findings/**`: three files share a 43-word comment block
  beginning `<!-- Verbatim ripgrep stems, recorded as audit evidence. The truncation is deliberate`.
  Audit evidence, deliberately verbatim, self-declared. `REFUSE-intentional`.
- `plugins/*/skills/*/vendor/**`: excluded by the sweep's own scope rules; not read.

# Changelog

All notable changes to the `overengineering` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Initial release.** A plugin that audits an existing enforcement surface — agent hooks and
  standing instructions, repository and version-control hooks, CI lanes and gate scripts, branch
  protections, forge apps, declared external integrations — under an evidence-earned-keep verdict
  model, and realigns to the simplest adequate solution behind an explicit per-item human gate. Two
  single-purpose skills: `audit` reports and never mutates (the marketplace's `audit` verb contract);
  `realign` is the only skill that changes anything, and only on explicit per-item acceptance.
- **`context/scrutiny-method.md` — the shared scrutiny method**, stated once and restated by neither
  skill. Verdicts are argued in **cost of carry**, never cost to build. A tiered evidence taxonomy
  (runtime records → version-control/CI history → incidents → operator attestation → documentation as
  *claims to verify*) makes every verdict cite an empirical source or class itself UNPROVEN, and
  distinguishes evidence that is **silent** from a tier that is **unavailable**. Liveness is three
  independent questions — source posture, wiring, runtime enforcement — with the generic false-green
  failure modes that pass one while failing another. Intent is reconstructed rather than assumed,
  with a checkpoint question when the run is attended and an `OPEN-INTENT` row when it is not; "I
  don't know" is an accepted answer that routes the item to the empirical track. Rediscovery
  re-solves the reconstructed problem native-first with a dated tech-drift check. Also carries the
  verdict ladder, the UNPROVEN triage rules, the YAGNI scope boundary, the three-rung rollback
  ladder, and the ownership resolution order.
- **Protected classes with a FLAG-FOR-HUMAN cap.** Security-class artifacts are fully audited and
  their evidence reported; what is capped is the recommendation. A retirement-direction verdict on
  one is emitted as FLAG-FOR-HUMAN carrying the verdict it would have been; keep-supporting evidence
  is never hidden by the cap; UNPROVEN on a protected item stays UNPROVEN and never enters an
  ablation batch; and where protection status is uncertain the item is treated as protected. The
  intentionally-dormant class — kill switches, break-glass paths, circuit breakers — is exempt from
  inactivity-based retirement outright, since never having fired is its designed steady state.
- **Every threshold is labeled an analogical transfer.** No published source states a retirement
  threshold for enforcement surfaces, so the shipped rows are transfers from alerting and
  feature-flag literature. Each carries its source, its own author's qualifiers, and the transfer
  label verbatim; a threshold cited without its label is a contract violation rather than a style
  slip. The categorical "no downstream consumer means retire" claim is recorded as **refuted** so it
  is not re-derived by a later reader.
- **`context/findings-artifact.md` — the audit → realign contract.** One markdown file is the whole
  seam between the two skills: frontmatter (`type: overengineering-findings`, `schema`, `date`,
  `scope`, `branch`), a fixed ten-value layer vocabulary, content-hashed finding ids derived exactly
  as the finding-suppression convention derives them, a stable total ordering, and a **stable spine /
  free prose split** — the machine-comparable fields are line-formatted so a diff across runs
  compares them alone, while evidence and reasoning prose are recomputed freely. Re-run merge
  semantics carry operator judgments forward by stable id while recomputing every verdict, and a
  verdict that changed direction underneath a judgment is surfaced rather than applied. Partial
  artifacts are valid, so an interrupted walk leaves a checkpoint.
- **The artifact is deliberately not the auto-applicable review-findings kind.** That kind is located
  by frontmatter alone and is auto-applicable by construction; routing consent-gated realignment
  through a fix relay would launder the per-item human gate. The boundary is stated once, with its
  consequences, so it is not re-litigated one field at a time.
- **Consumer configuration rides a tracked config-cascade concern file, not `userConfig`.**
  `.claude/overengineering.md` carries the protected-categories set, threshold overrides, the
  observation window, and optional suppression entries. The protected-set and suppression keys sit in
  the cascade's policy-floor class — the team-tracked layer wins a direct conflict, personal layers
  may extend or tighten only, and a personal contribution is named in the report — because a
  gitignored overlay silently emptying the protected set would recreate the exact hole that
  disqualified `userConfig` as a repository coordination surface. Emptying the set stays possible
  through the tracked layer, spelled one category at a time so the review diff names each protection
  being dropped. Keys, defaults, and per-key merge forms are owned by `reference/consumer-config.md`.
- **`reference/topic-docs.md` — the findings-artifact home.** Memory tier, concern-scoped,
  branch-keyed (`.work/overengineering/<branch-slug>/findings.md` by default), never committed, and
  rewritten in place rather than deposited as a timestamped sibling. The artifact is ephemeral by
  design; judgments that must outlive a branch switch are persisted as tracked suppression entries
  instead.
- **`reference/artifact-protocol.md`** — the marketplace's shared lifecycle artifact protocol,
  byte-identical to the canonical copy, covering the missing-prerequisite stop `realign` performs
  when no findings artifact exists.

### Notes on deliberate omissions

- **No `userConfig` block.** See above — the reasoning is a policy-visibility argument, not an
  oversight, and it is restated in the plugin README next to the configuration summary.
- **No score and no gate.** Verdicts are argued and cited, never summed. A score invites exactly the
  threshold-laundering the analogical labels exist to prevent.
- **No autonomous retirement, anywhere.** Every removal is human-reviewed, the rollback ladder never
  deletes first, and protected and intentionally-dormant mechanisms are excluded from ablation by
  construction.
- **Product-code overengineering is out of scope in this version.** The method's sections are written
  lane-independently — a lane supplies its item inventory, layer vocabulary, evidence sources, and
  protected-class patterns and inherits the rest — so a future code lane reuses the core rather than
  forking it.

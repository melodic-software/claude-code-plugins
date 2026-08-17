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
- **`overengineering:audit` — the read-only surface walk.** Bare invocation walks the enforcement
  surface, applies the scrutiny method, and emits the findings artifact; it disables, edits, and
  deletes nothing, and says so in its opening line. The single write is the artifact at its
  memory-tier home, which is the deliverable rather than a change to the repository. Two arguments
  shape a run: a **layer scope** (one or more values from the artifact's layer vocabulary), because a
  mature surface runs past a hundred items and does not fit one context window — layer-scoped passes
  compose through the artifact's re-run merge semantics; and **`unattended`**, which selects the
  `OPEN-INTENT` disposition for low-confidence intent. Attended is the default, and the mode is never
  inferred: the harness gives a prose skill no reliable probe for whether a human is watching, so a
  dispatched or scheduled caller owns the flag.
- **`skills/audit/context/surface-walk.md` — the lane's inventory, probes, and evidence sources.**
  A layer-by-layer walk in the artifact's enum order, each layer carrying its discovery probes and the
  evidence tiers actually available in it. A **shallow-clone probe** runs before layer one, because a
  shallow checkout makes version-control history *unavailable* rather than silent and every UNPROVEN
  verdict resting on history has to cite the missing tier by name. The artifact is **written per
  layer** as the walk proceeds, so a context-exhausted run leaves a checkpoint with its completed
  layers persisted rather than nothing. CI verdicts are lane-level by default; a lane that aggregates
  several independent checks, and whose own definition carries the member list, gets per-member
  sub-verdicts inside the lane row — mechanical composition evidence, never a member list synthesized
  from reading behavior. Branch protections and forge apps read through a forge API when one is
  configured, through policy-as-code where the consumer manages protections declaratively, and
  otherwise emit identified rows marked unreadable rather than inferring a rule that was never read.
- **`skills/audit/context/report-template.md` — three output layers, one source of truth.** The
  findings artifact is authoritative; the inline terminal summary is always printed and is a view of
  it rather than a second record; the rendered HTML view is presence-gated on the visualization
  plugin with a documented fallback of skipping it, because a hand-built substitute would be a third
  record to keep in sync.
- **Neighbor routing, every route presence-gated with an inline fallback.** Instruction-text findings,
  contested agent-layer ablation, prospective additions, and plugin claims-versus-reality each route
  to the neighbor that owns them when that plugin is installed, and each carries a documented inline
  fallback for when it is not. The presence answer is recorded on the finding, so a skipped route is
  visible rather than silent.
- **Nine behavioral evals**, written before the skill body per this marketplace's test-first analog
  for prose skills: read-only bare invocation; a wiring claim in a header verified against the live
  registration surface; a protected item capped rather than retired; silence classed UNPROVEN rather
  than either KEEP or RETIRE; a threshold cited with its analogical label and its removal-candidate
  qualifier; unattended low-confidence intent recorded as `OPEN-INTENT`; the three liveness questions
  answered independently on a wired-but-dead-at-runtime guard; an evidence-desert repo triaged by
  carry cost into one bounded ablation batch instead of an undifferentiated UNPROVEN wall; and an
  ambiguous bypass-flag guard taking the protected tie-break.

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

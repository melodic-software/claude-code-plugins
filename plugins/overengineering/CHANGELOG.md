# Changelog

All notable changes to the `overengineering` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.2.0]

### Added

- **`delta` — the recurring lane the findings artifact was designed for (#2898).** A third,
  read-only skill: it captures the prior findings spine, composes `overengineering:audit` over the
  same layer scope, compares the two spines, and reports **only what moved** — new clutter, verdict
  moves, closures, status changes — instead of re-serving the whole surface every cycle. The
  artifact's stable spine was given its diffable line format for exactly this consumer, and the lane
  reads the spine alone: prose is recomputed fresh every run, so comparing it would report model
  noise as change.
- **The baseline is the previous cycle's post-audit spine, stated as the lane's load-bearing
  mechanic.** Two things have to be right and each fails silently alone. A spine must be *persisted*,
  because the artifact is rewritten in place, per layer, as the audit walks — **after an audit has
  run there is nothing left to diff against**, so "audit, then diff the file" is not available and a
  memory-tier `spine-baseline.md` sibling is mandatory. And it must be captured at the **end** of a
  cycle, from the post-audit artifact: `Status` is written by realign, a human runs realign *between*
  cycles, and the audit carries every non-new status forward untouched, so a start-of-cycle capture
  would already hold the new status and the status-change class could never fire. A pre-audit capture
  survives only as an explicitly named **bootstrap** — a home with an artifact and no baseline yet —
  which cannot observe a status change and says so, while the next cycle can. A maintainer who breaks
  either half gets no error, just a silently useless lane, which is why the mechanic is a contract
  clause in both the skill and `context/findings-artifact.md` rather than an implementation detail.
- **A detached checkout is never given a branch identity.** `git rev-parse --abbrev-ref HEAD` answers
  the literal `HEAD` when detached — the ordinary shape for the scheduled runners this lane targets —
  which keys every ref to one home and compares equal to itself, so the branch-match guard would
  accept another ref's spine as this ref's baseline and report cross-ref differences as deltas. The
  lane's precompute uses `git symbolic-ref`, which fails rather than inventing a name; the run then
  prefers a logical ref where the environment supplies one (no CI vendor's variables are named or
  assumed) and otherwise declines to compare **and** declines to capture, saying why.
- **A noise budget with per-class rules, not a judgment gesture.** Each delta class is disposed as
  list, count, or omit: new findings list on retirement-direction and capped verdicts and count
  otherwise; new `UNPROVEN` findings list only the head of the audit's own carry-cost ranking, since
  an evidence desert produces them in bulk; verdict moves on unjudged findings list only when they
  cross the keep/retirement boundary, touch `FLAG-FOR-HUMAN`, or enter or leave `UNPROVEN`; closures
  list when unexpected and count when the prior status was `REALIGNED`; member moves under an
  unchanged container count. A volume cap bounds the whole report, and **a quiet cycle is one line**
  — the anti-nag property the lane exists to hold. Evidence-only change is declared **out of scope by
  construction**: evidence is prose, a spine comparison cannot see it, and no threshold makes it able
  to.
- **`delta_noise_budget` in `reference/consumer-config.md`**, seven keys with types and defaults, in
  the ordinary **refinement** cascade class with the classification justified in the doc: no key can
  remove a finding from the artifact, change a verdict, suppress a judgment, or weaken the protected
  cap, so none carries the hazard that puts `protected_categories` and `suppressions` in the
  policy-floor class. Two delta classes are deliberately not keys at all — a verdict that moved under
  a **carried-forward judgment** (merge rule 5) and a **status change** are always surfaced, and no
  layer can weaken either. `queue_route` defaults to `inline`: the durable tracker route is **opt-in**
  because `work-items:track` refuses to file on inferred intent, and an operator setting the key in
  tracked config is the explicit, recorded authorization that gate requires — one an unattended
  scheduled cycle has nobody present to give.
- **Recurring wiring documented, adopted nowhere.** `skills/delta/context/recurring-wiring.md`
  carries four consumer-agnostic shapes — a fixed-interval loop, a headless scheduled task, a CI
  schedule, and a recurring tracker item — each with its trade, including the observation that a
  scheduled CI lane *is itself* an enforcement-surface item this plugin's own audit will later judge
  on carry cost. The plugin ships no schedule of its own: a cadence is the consumer's ratified
  decision, not something a plugin adopts on install.

### Changed

- **`context/findings-artifact.md` gains the spine-capture obligation (#2898), additively.** A new
  section names the end-of-cycle capture timing, the `Status` reason behind it, the one sanctioned
  pre-audit bootstrap, and specifies the `spine-baseline.md` sibling —
  `type: overengineering-spine-baseline`, deliberately neither `overengineering-findings` nor
  `review-findings`, so `realign` never reads it and no fix relay can locate it. `schema` stays `1`
  and no merge rule changed; the doc's forward reference to "a future delta lane" now names the
  shipped one, and its obligations table records that `delta` is a third **reader** and no writer —
  least of all of `Status`, which stays realign's alone.

### Contracts

- **Read-only always, and realign is never entered.** The delta lane never invokes or enters
  `overengineering:realign` — not on a verdict that moved, not on a finding an earlier run accepted,
  and not when the operator asks for it mid-run. Realign's per-item gate needs a human present at the
  moment the item is shown, and a lane that can run on a schedule has nobody to give one. Verdict
  changes **queue**: always in the report's `## Queued for the human` section, and — **opt-in** on a
  tracked `queue_route: auto` and then presence-gated on a reachable work-item tracker, with the
  report section as the named inline fallback — as one reused item per branch that a quiet cycle
  never touches, that drops a row the human has already dispositioned, and that the lane never
  closes. The opt-in is the authorization, not a verbosity preference: `work-items:track` will not
  file on inferred intent, so an unset key means report-only.
- **No baseline is a first-class state, not an error.** A fresh container, a removed worktree, a
  branch switch, or an artifact whose `branch:` frontmatter names another branch all mean there is no
  prior spine. The lane says "no baseline; this run establishes one", reports nothing as a delta, and
  points at the composed audit's own inline summary rather than producing a second full-surface view.
  An unrecognized `schema:` is a stop instead, per the artifact contract's closed rule.
- **A layer-scoped cycle is never a clean bill of health.** Findings in a layer absent from this
  run's `scope` were carried forward untouched by merge rule 4; they contribute to no delta class and
  are named once as a coverage line with their count — never as unchanged-and-checked, and never as
  closed.

## [0.1.1]

### Changed

- **`realign`: the movement-composition table names the Skill tool (#3002).** The paragraph above
  the `Movement | Composition | Inline fallback` table now states once that every skill in the
  `Composition` column is invoked via the Skill tool. Wording only — the presence gates, the
  inline fallbacks, and the say-which-one-ran rule are unchanged.

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
  layers persisted rather than nothing. Verdicts are container-level by default; a container that
  aggregates several independent checks, and whose own definition carries the member list, gets
  per-member sub-verdicts inside the finding's body — mechanical composition evidence, never a member
  list synthesized from reading behavior. Branch protections and forge apps read through a forge API when one is
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

- **`overengineering:realign` — the plugin's only mutating surface, behind a per-item human gate.**
  It consumes the findings artifact and never scans or re-judges the surface itself: no artifact at
  the resolved home is a **stop** naming `overengineering:audit` as the skill that produces one, and
  a mismatched `branch:` or an unrecognized `schema:` is refused with a visible message rather than
  guessed at. **Nothing mutates without an explicit acceptance of that finding, at the moment it is
  presented** — one finding's yes authorizes that finding only, blanket approval is declined out
  loud, silence leaves a finding `OPEN` rather than judged, and acceptance is scoped to the rung
  about to execute, so a deletion asks again after the window. Per accepted finding it drives four
  movements — interview → explore and research → plan → implement — each composing a sibling skill
  when that plugin is installed and running a documented inline fallback when it is not, with the
  presence answer recorded on the finding so a skipped route stays visible.
- **Execution follows the rollback ladder, never deletion-first.** Config-disable at rung 1 with the
  unset-means-enabled trap checked and the disable confirmed to have taken effect; observation at
  rung 2 with the window's end date written on the finding and on a durable pointer that outlives
  the ephemeral artifact; deletion only at rung 3, carrying the evidence and the observation result
  in its recorded rationale. Withdrawal is named as a normal outcome: a window that shows the
  mechanism load-bearing ends at rung 1 with it re-enabled and the finding closed as KEEP. UNPROVEN
  findings route to one bounded, owner-routed ablation batch with a stated end date rather than to
  dozens of concurrent windows; protected and intentionally-dormant items never enter one, and a
  `FLAG-FOR-HUMAN` finding surfaces the capped verdict's evidence and waits for the human's own
  call. Out-of-repo custody produces a delegation artifact and `DELEGATED-EXTERNAL` with its
  pointer — never an in-repo edit, never a locally patched managed copy.
- **Realign is the artifact's only writer of `Status`**, and it writes one only as the outcome it
  names actually happens, leaving every field the audit computed untouched. A verdict that flipped
  direction underneath a carried-forward judgment is surfaced before anything else and never acted
  on. Accepted-keep judgments — `REJECTED` and `ABLATION-CONCLUDED-KEEP` — are **offered**
  persistence as tracked suppression entries in `.claude/overengineering.md`, shown in full before
  writing, written only on an explicit yes under the same per-item gate, with the `reason` in the
  operator's own words and only to the team-tracked layer.
- **Six behavioral evals**, written before the skill body: a missing findings artifact stopping with
  `overengineering:audit` named and no improvised scan; a three-finding queue where accepting item 2
  moves item 2 alone; a protected finding presented with its evidence and left for the operator
  despite a blanket approval; a RETIRE executed as a config-disable rather than a deletion; a
  thirty-item UNPROVEN pile answered with one bounded, time-boxed ablation batch; and an absent
  composition plugin taking a visible inline fallback instead of a silent skip.

- **Dry-run-driven clarifications to the aggregation and identity rules.** Three fresh-context runs
  executed the shipped skills verbatim against a real repository and surfaced ambiguities the prose
  had left to the reader; each is fixed in the document that owns it. **Aggregation:** an aggregating
  container — a hooks manifest, a settings scope registering hooks, a lane whose definition lists its
  checks — **is** the finding: one spine row, one container verdict, one id, with members as
  line-formatted entries inside the finding's body in a fixed id/name/verdict shape, so member
  verdicts stay extractable while the documented cross-run diff keeps comparing container spines and
  member lines compare within a finding. The granularity rule is stated once as a cross-layer rule
  and the **item unit is pinned per layer** — for `agent-hooks`, the hooks manifest per plugin, with
  its registered entries as members — because a unit re-chosen per run derives different ids and
  orphans every judgment keyed to the old one. **Identity:** every site of a cross-artifact finding
  binds through the id's `sites` constituents, the spine's single-line `Artifact` carries the primary
  subject, and the body names every site; `settings:<path>` joins the closed kind-prefix set for a
  registration surface outside the repo tree.
- **Sanctioned field dispositions, merge precedence, and self-perturbation.** `Rediscovery` gains two
  dispositions — `Deferred — no tech-drift check claimed` and `Not applicable — <reason>` — with the
  dated drift check batched per lane or class rather than paid per item; `OPEN-INTENT` is stated to
  be an `Intent` value and never a `Status`, and its counts count findings, with members counted
  separately only where a run says so. Re-run merges add that the **spine is authoritative over the
  prior artifact's own prose** — a summary contradicting its own spine is recomputed, never
  inherited — and that prose claims about statuses never outrank the `Status` spine lines. Because
  the audit appends to the telemetry it reads, the tier-1 read window is bounded at walk start and
  rows attributable to the run itself are excluded and named. The method's §9 gains a
  **minimum-observation guard**: a threshold row is never cited from an evidence window shorter than
  the threshold's own denomination, and the refusal is recorded and routed through §8.
- **Skill-body clarifications from the same runs.** `audit` distinguishes its two doc roots
  (plugin-root shared docs against skill-local lane docs) so every reference resolves, emits the
  read-only opening line immediately after the artifact home resolves — the first moment the path
  exists — states that the surface is everything governing work in this repository *wherever it is
  registered*, with out-of-repo registration surfaces audited under §12 custody rather than skipped,
  and documents the sanctioned write route for a delegated executor whose harness refuses a
  report-shaped filename: the file-write tool to a neutral filename in the artifact's directory, then
  a rename, never a shell content-write. `realign` names its two gates — **item acceptance** and
  **change approval** — **presents and stops** when no operator is present, records
  *"rung 1 inapplicable"* with its reason where nothing is wired to disable (a reversible non-rung
  remediation is a valid proposal; where only deletion remains, the acceptance must name the deletion,
  and an inert CONSOLIDATE copy routes the same way), and surfaces a carried judgment whenever the
  recomputed verdict changes *what the acceptance authorized*, not only when its direction flips.

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

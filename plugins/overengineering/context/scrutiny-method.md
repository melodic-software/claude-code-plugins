# Scrutiny method — evidence-earned keep

Shared method for every skill in this plugin. `audit` applies it to produce verdicts; `realign`
applies its rollback ladder and its protected-class rules to execute them. **Neither SKILL.md
restates any of it** — a second statement of a verdict definition is a second thing to drift.

The posture is the inverse of a gap audit: every incumbent mechanism on the surface is a retirement
candidate until evidence earns its keep. That posture is a default, not a conclusion — the whole
point of the sections below is that the default is *overridable by evidence*, and that silence is
not evidence in either direction.

## Lane binding

Sections 1–12 are lane-independent. A lane supplies four things and inherits everything else:

1. **The item inventory** — what counts as one auditable artifact in this lane.
2. **The layer vocabulary and discovery probes** — how items are found, layer by layer.
3. **The evidence sources available in this lane**, mapped onto the tiers in §2.
4. **The lane's protected-class default patterns**, extending §7's list.

V1 ships one lane: the enforcement surface (agent hooks and standing instructions, repository and
version-control hooks, CI lanes and gate scripts, branch protections, forge apps and automations,
declared external integrations). A future product-code lane supplies its own four and reuses §§1–12
verbatim.

## 1. The economic frame: carry cost, never build cost

Every verdict is argued in **cost of carry** — the ongoing tax a retained mechanism imposes on all
subsequent work — and never in cost to build. Martin Fowler's YAGNI article names four costs of a
presumptive capability: build, delay, carry, and repair, with carry cost being the one that "makes
it harder to modify and debug that software, thus increasing the cost of other features"
(<https://martinfowler.com/bliki/Yagni.html>). Mapping that taxonomy onto enforcement surfaces is
this method's analytic extension, not a claim Fowler makes.

Two arguments are therefore inadmissible on their own, and a finding that leans on either is
incomplete:

- *"It was cheap to build."* Build cost is spent; it says nothing about what the mechanism costs
  every future change.
- *"It was expensive to build."* That is a sunk cost, and treating it as a reason to keep is the
  bias this method exists to counteract.

**What carry cost is made of**, and what to read to estimate it: how often the mechanism runs and on
what matcher breadth; latency it adds to a common operation; how much unrelated work it constrains
or must be worked around; its churn (a mechanism repeatedly re-tuned is paying carry cost in
maintenance); the reading cost it imposes on anyone changing an adjacent surface; and the
false-positive tax it levies on people who then learn to ignore the whole surface.

**Default-skeptical is empirically grounded, not a temperament.** Kohavi et al.'s Microsoft data —
cited by Fowler and published in full at
<https://ai.stanford.edu/~ronnyk/ExP_DMCaseStudies.pdf> — found only about one-third of
carefully-analyzed features improved the metrics they were built to improve, with later data from a
large search product harsher still. The measurement is of shipped features under controlled
experiment; the extension to presumptive capability is Fowler's own, and the imprecision runs in the
skeptic's favor rather than against it.

**Aggregate; do not expect a single removal to feel like a win.** Ousterhout's account of complexity
is that it accumulates through many individually-justifiable small additions, and that once
accumulated it resists removal precisely because "fixing a single dependency or obscurity will not,
by itself, make a big difference" (*A Philosophy of Software Design*,
<https://milkov.tech/assets/psd.pdf>). Two consequences: each accumulated mechanism needs its own
justification, and the audit's value is in the aggregate of many small retirements rather than in
any one. Ousterhout frames zero-tolerance prospectively; using it as retrospective audit doctrine is
this method's inference.

**Un-retired automation is risk, not neutral clutter.** The Piranha paper motivates cleanup with the
2012 Knight Capital incident — more than $460M lost in about 45 minutes — where dead code left
behind by uncleaned feature flags and a re-purposed flag were part of the causal chain
(<https://manu.sridharan.net/files/ICSE20-SEIP-Piranha.pdf>). The paper hedges it as a "confluence
of multiple events" and that hedge travels with the citation. The transferable point is narrow and
real: a dormant control path can be reactivated by accident, so carrying it is not free even when it
does nothing.

## 2. Evidence taxonomy — and what silence means

**Every verdict cites at least one empirical source, or it is UNPROVEN.** Tiers, strongest first:

| Tier | Source | What it can establish | Standing caveat |
|---|---|---|---|
| 1 | Runtime / telemetry records of actual firings, outcomes, durations | that the mechanism ran, what it decided, what it cost | records only what the mechanism emits; a silent success may emit nothing (§5) |
| 2 | Version-control, issue-tracker, and CI history | when and why it appeared, what it caught, how often it was re-tuned | needs full history; a shallow clone makes this tier *unavailable*, not silent |
| 3 | Incident and post-incident records | the hazard is real and has occurred | absence of incidents is ambiguous by construction (§7) |
| 4 | Operator attestation — a human who was there | intent, near-misses, and machine-local evidence nothing in the repo records | recorded as attestation with its date and speaker, never promoted to a measurement |
| 5 | Documentation, headers, comments, rationale text | **claims to verify**, nothing more | may be stale, may be generated; doc-only support is marked **unverified** in the finding |

**Docs are claims, not evidence.** A header asserting what a mechanism does, a comment asserting it
is wired, a rationale doc asserting it catches something — each is a hypothesis with a cheap
verification available. Verify it against the thing itself, and record the verification, not the
claim. A finding whose only support is tier 5 states that in those words.

**Silence is UNPROVEN, never KEEP.** A mechanism with no recorded firings, no history of catches,
and no incident behind it has not earned a keep. It has also not proven itself waste — see §8.

**Distinguish silent from unavailable.** "The telemetry shows nothing" and "there is no telemetry"
are different facts with different consequences, and collapsing them is how an audit manufactures
confidence. Every UNPROVEN verdict names *which tier was consulted and what it returned*, so a
reader can tell the two apart.

**A supporting control gets the same scrutiny as the artifact.** When a verdict leans on a
comparison — "the sibling mechanism costs almost nothing, so this one's cost is anomalous" — the
control's own liveness is checked by §3 before the comparison is admitted. A control that never ran
produces a number that measures the refusal to start, not the thing being compared, and such a
number has shipped inside a ratified decision before now.

## 3. Liveness — three independent questions

Ask all three. **Never infer one from another**; the false-greens below are exactly the inferences
that look safe.

1. **Source posture.** Does the artifact exist in the tree, and what does its own source declare —
   enabled or disabled by default, blocking or advisory, fail-open or fail-closed, what it matches?
2. **Wiring.** Is it actually registered on a configuration or registration surface the runtime
   reads? Registration is read from the live configuration, never from the artifact's account of
   itself.
3. **Runtime enforcement.** When it is reached, does it complete and produce its decision inside its
   budget? A mechanism that is invoked and then killed, refuses to start, or exits before deciding
   enforces nothing.

**Generic false-green failure modes** — each has been observed in the wild and each passes at least
one question while failing another:

- **A checked-in artifact whose header claims wiring it lost.** The file is present and its own
  comment block still describes the registration that used to exist. Q1 green, Q2 red, and the only
  surviving account of Q2 is the claim Q2 disproves.
- **Two copies, one wired.** The same guard exists in two places — a local copy and a packaged one —
  and the documented rationale lives with the copy that no longer fires. The policy is still
  enforced; the artifact the documentation describes is inert. A verdict written about the wrong
  copy is wrong in both directions at once.
- **A wired guard that fails open at the harness layer.** The mechanism is registered and its source
  says fail-closed, but the runtime kills it at its declared timeout and a killed handler yields no
  decision, so the guarded operation proceeds unguarded. Q1 and Q2 green; Q3 shows enforcement on
  approximately none of the calls.
- **A guard that declines to start and reports fast.** An unset required option, an unresolvable
  interpreter path, a missing binary — the mechanism exits quickly and cleanly, and its speed reads
  as efficiency rather than as never having run.
- **A gate outside the aggregate everything else keys on.** The lane exists, runs, and reports, but
  nothing requires its result, so its verdict changes no outcome.

**Rule:** green on Q1 and Q2 with Q3 unread is **UNPROVEN on enforcement**, not KEEP. Where Q3 is
unreadable in this consumer, say so in those words and let §8 rank it.

## 4. Intent reconstruction

Before judging a mechanism, reconstruct the problem it was built to solve — from evidence, not from
its current shape.

**What to read:** the change that introduced it and that change's description; the issue, incident,
or review comment linked from it; the tests and fixtures added alongside it; changelog entries at
the version it appeared; and its own comments, held as tier-5 claims. Record **authorship evidence**
while you are here — it is the input §12 needs and it is expensive to recover later.

**Score the reconstruction:**

- **HIGH** — a named problem with a dated trail: a linked incident, a described failure, a test
  encoding the case.
- **MEDIUM** — a plausible problem inferred from the mechanism's shape plus circumstantial history.
- **LOW** — nothing but the mechanism itself.

**On MEDIUM or LOW, do not guess.** Two dispositions, selected by run mode rather than by feel:

- **Attended** — surface a checkpoint question to the operator: what problem was this solving?
  Recommendation first, one small numbered set, reusing the consuming environment's interview
  mechanics when they are present and inline questions when they are not.
- **Unattended** — record **OPEN-INTENT** on the finding and stop. An invented intent is worse than
  a blank one: it becomes the fence the next audit refuses to remove, and it will read as evidence
  to everyone downstream because it is written in the same voice as the evidence.

**"I don't know" is an accepted answer.** It is not a failure of the interview; it routes the item
to the empirical track in §8 with its intent recorded as unrecovered.

## 5. Rediscovery — re-solve, do not critique

Critique tends to produce a smaller version of whatever is already there. Instead, take the
reconstructed problem and solve it fresh, today, choosing in this order:

1. **The platform's own built-in mechanism** — a native configuration option, a native lifecycle
   event, a first-class feature of the toolchain that already covers the concern.
2. **An existing mechanism already present in this repo** that covers the concern. One mechanism per
   concern: a check that supplies no signal another check does not already supply is a deletion
   candidate on that ground alone.
3. **A narrower version of the incumbent** — the same mechanism scoped to the actual hazard rather
   than to the category the hazard belongs to.
4. **Bespoke enforcement**, justified only by the residue the first three genuinely do not cover.

**Tech drift.** The right answer may have changed since the mechanism was written: a native feature
that did not exist then may cover it now. Re-verify against the *current* official documentation of
the platform rather than against memory or an old summary, and record the check with its date. A
rediscovery that skips this reproduces the original decision instead of re-deriving it.

**The invocation-is-not-usage trap.** A mechanism that succeeds silently writes nothing anywhere. For
hook-shaped, transform-shaped, and gate-shaped artifacts, *zero recorded invocations is the expected
reading for one that is correctly functioning and heavily used* — the record is a function of what
the mechanism emits, not of what it did. Classify each item by **surface type** — does exercising it
leave a record at all? — before treating a zero as meaningful. A count of invocations is not a count
of usage, and a removal set built on that conflation has been measured to empty completely on
re-measurement.

## 6. The verdict ladder

Five verdicts and one cap. Argue every one in carry cost (§1) and cite evidence per §2.

| Verdict | What it asserts | What it requires |
|---|---|---|
| **KEEP** | the mechanism catches something real, and the catch is not derivable from a cheaper mechanism already present | at least one tier-1–4 citation showing a catch, a prevented hazard, or an oracle the surrounding system cannot supply itself |
| **RETIRE** | the mechanism should be removed | evidence of no catches *plus* a stated reason the silence is informative (§2, §3, §5) — never silence alone |
| **DOWNGRADE** | the concern is real; the mechanism's authority exceeds it | evidence the cost concentrates in the excess: blocking where advisory suffices, default-on where opt-in suffices, a broad matcher where the hazard is narrow |
| **CONSOLIDATE** | several mechanisms cover one concern | the overlap demonstrated, and a named survivor with the argument for why it is the one |
| **UNPROVEN** | the evidence is silent or unavailable | the tier consulted and its result, named — routes to §8 |
| **FLAG-FOR-HUMAN** | a **cap**, not a rung — see §7 | the underlying verdict and its full evidence, carried, not withheld |

**A useful oracle is a KEEP even for a mechanism that duplicates model or human judgment.** The
delete criterion is "the surrounding system could derive this itself", never "it corrects
something". A mechanism holding a non-derivable ground truth — a live capability query, a
filesystem or index fact, a registry lookup — is earning its carry cost by supplying a fact, and
that stands regardless of how simple the check around it looks.

**Refactor, removal, and testing cost enter the verdict.** State them in the finding rather than
assuming them away. A mechanism judged wrong or overengineered still leans toward being fixed rather
than carried — but where the fix is expensive and the mechanism is cheap to carry, that is an
argument the finding must make explicitly instead of a conclusion it may reach silently.

**Mechanism never implies verdict.** A blocking gate may be exactly right and an advisory nudge may
be pure carry cost. Classify by what the mechanism asserts and whether the assertion is earned, not
by how forceful it is.

## 7. Protected classes and the FLAG-FOR-HUMAN cap

Protected items are **fully audited**. Their evidence is gathered and reported like everything
else — what is capped is the recommendation, not the scrutiny.

### Cap semantics, stated explicitly

- **The cap applies to retirement-direction verdicts only.** RETIRE, DOWNGRADE, and CONSOLIDATE on a
  protected item are emitted as **FLAG-FOR-HUMAN**, carrying the verdict they would have been and
  the full evidence behind it. The skill never recommends retiring a protected mechanism on its own.
- **Keep-supporting evidence is never hidden by the cap.** A protected item whose evidence supports
  KEEP is reported as **KEEP with a protected marker**. Converting a positive, evidenced finding
  into an open question would destroy exactly the information the operator needs.
- **UNPROVEN on a protected item stays UNPROVEN**, with the protected marker, and does **not** enter
  an ablation batch (§8). Ablating a security control to see what happens is the failure mode the
  class exists to prevent.
- The marker names *which* protected class matched and *which* rule matched it, so a reader can
  contest the classification rather than only the verdict.

### Default protected patterns

A starting set, and **consumer-configurable** — a consuming repository may extend, narrow, or empty
it through its own tracked configuration, which is the reviewable place for such a change:

- secret, credential, and token detection; anything gating their egress
- destructive-operation guards: irreversible deletion, history rewriting, force publication, writes
  against a production surface
- guards on the disabling of other guards — a check whose subject is a bypass flag
- authentication, authorization, and permission-boundary enforcement
- supply-chain integrity: dependency pinning, checksum or signature verification, lockfile
  enforcement, provenance checks
- security-scanning lanes (secret scanning, vulnerability scanning, security lint) and the branch
  protections that make them required
- audit-trail and retention mechanisms whose removal is externally constrained

### The intentionally-dormant class

Kill switches, emergency stops, break-glass paths, circuit breakers, canaries, and monitoring or
debug controls. **Never having fired is their designed steady state**, so an inactivity threshold
returns no information about them and applying one is a category error.

This is the Piranha paper's own finding: determining staleness is "surprisingly non-trivial", and
"even when flags are completely rolled out, they may not necessarily be stale" — fully-rolled-out
controls may be intentionally retained as kill switches or monitoring flags
(<https://manu.sridharan.net/files/ICSE20-SEIP-Piranha.pdf>). Practitioner documentation in the
feature-flag ecosystem has converged on the same treatment for permanent operational flags.

Retiring an intentionally-dormant mechanism therefore requires an argument about the **hazard**, not
about the mechanism's activity: the hazard no longer exists, or another mechanism now covers it. Its
dormancy is not part of the argument in either direction.

### The absence-of-incident trap

An effective control looks redundant precisely because it prevents the events that would justify it.
"No incidents since it shipped" is evidence-shaped and is not evidence of waste. Route it to
UNPROVEN, or to a deliberate deterrence test where one is safe and available — never straight to
RETIRE. The same asymmetry applies to controls built around known hazards, which may simply never
have been tested by an unknown one.

### Tie-break

**When protection status is uncertain, treat the item as protected.** A misclassified guard must
fail toward the cap, never away from it, and the finding records that the classification was
uncertain so a human can overturn it cheaply.

## 8. UNPROVEN triage — never an undifferentiated wall

Evidence availability varies enormously between consumers. A repository with runtime telemetry, a
decision-record corpus, and deep history is an outlier; the modal consumer has none of the three,
and in that repository nearly every item is UNPROVEN on first pass. A report that emits that as a
flat list of dozens of identical rows is useless, and worse, it invites a blanket response.

Four obligations:

1. **Lead with an evidence-availability assessment.** Before the findings, state for each tier in §2
   whether it is present, partial, or unavailable in this consumer, and name the probe that
   established it. A shallow checkout makes tier 2 unavailable; no telemetry sink makes tier 1
   unavailable; a machine-local evidence store the audit cannot read is unavailable rather than
   empty. This assessment changes what UNPROVEN *means* for every finding in the run, so it belongs
   ahead of them rather than in a footnote.
2. **Rank UNPROVEN items by carry cost.** Carry cost (§1) is the correct ranking key precisely
   because it is readable *without* the evidence that is missing: matcher breadth, per-invocation
   cost, blast radius on a false positive, how much other work the mechanism constrains, and its
   churn are all observable from the tree.
3. **Recommend a bounded ablation batch.** Take the top of that ranking — a small number of items,
   sized so a human can actually attend to them — disable them together for one observation window
   (§11), name an owner per item, and state the re-check date. Batched, owner-routed retirement is
   the one industrial-scale precedent available: Uber's Piranha generated removal diffs for 1,381
   stale flags over 18 months; about 200 developers deleted 71 KLoC; 65% of diffs landed unmodified
   and developers acted on 88% of them within the study, most within a week. Two qualifiers travel
   with those numbers and must not be dropped: the 65% is an aggregate hiding a large
   language-driven spread (93.7% in Objective-C against 28.2% in Java), and **every generated diff
   was reviewed by a human** — the pipeline was never autonomous.
4. **Never open dozens of concurrent ablations.** Overlapping windows make attribution impossible,
   and a batch nobody can re-check on its date is not an experiment. Items below the batch stay
   UNPROVEN with their ranking recorded, waiting for the next window rather than for a decision
   nobody will make.

Protected and intentionally-dormant items (§7) are excluded from ablation batches by construction.

## 9. Analogical thresholds — every row is a transfer

**Read this before using any number below.** No verified source states any of these thresholds for
enforcement surfaces. They come from alerting and feature-flag literature, and applying them to CI
lanes, version-control hooks, branch protections, or agent guards is **analogical transfer**, made
by this method and owned by it. Every row is labeled accordingly, every row is
**consumer-configurable**, and a finding that cites one must name its source *and* say that the
transfer is analogical. A threshold restated without its label has been laundered into a fact, which
is the exact failure this plugin exists to catch.

| Threshold | As stated in its source | Source | Status |
|---|---|---|---|
| Accuracy floor | a rule under about 50% accuracy is "broken" | Rob Ewaschuk, "My Philosophy on Alerting" — **this source only** | analogical transfer from alerting/feature-flag literature; consumer-configurable |
| False-positive attention line | even about 10% false positives "merit more consideration" | Ewaschuk — **this source only** | analogical transfer from alerting/feature-flag literature; consumer-configurable |
| Exercise frequency | rules exercised less than about once a quarter "should be up for removal" — a removal *candidate* | Google SRE book, ch. 6 — **this source only** | analogical transfer from alerting/feature-flag literature; consumer-configurable |
| Staleness gate | archival-ready on five simultaneous conditions: marked temporary; older than 30 days; no code references; not evaluated in 7 days; not a prerequisite of another | LaunchDarkly flag-hygiene documentation | analogical transfer from alerting/feature-flag literature; consumer-configurable |
| Inactivity window | unmodified beyond a team-configurable window (8 weeks in the published deployment) treated as stale | Uber Piranha | analogical transfer from alerting/feature-flag literature; consumer-configurable |

Sources, live:
<https://docs.google.com/document/d/199PqyG3UsyXlwieHaqbGiWVa8eMWi8zzAn0YfcApr8Q/preview> (Ewaschuk;
mirror at <https://gist.github.com/msgodf/86a3fc7fcd3ce663ff37>),
<https://sre.google/sre-book/monitoring-distributed-systems/>,
<https://launchdarkly.com/docs/guides/flags/technical-debt> with
<https://launchdarkly.com/docs/home/flags/archive>, and
<https://manu.sridharan.net/files/ICSE20-SEIP-Piranha.pdf>.

**Qualifiers that travel with the numbers:**

- The SRE book calls its own alerting philosophy "a bit aspirational", and the once-a-quarter figure
  is illustrative — attributed to "some SRE teams", not an organization-wide cutoff.
- The LaunchDarkly rows are vendor documentation: the right authority for what that vendor
  recommends, weaker as independent efficacy evidence. Its five conditions are described as
  customizable defaults, and the same documentation warns against archiving on status alone.
- Ewaschuk's figures govern *interrupt-generating* alerts. A gate that blocks a change has a
  different cost curve from one that pages a human; what transfers is the **cost mechanism** —
  noise degrades the whole surface, and people respond to a noisy surface by ignoring or disabling
  all of it — not the measurement.
- Piranha's window is explicitly team-configurable in its own deployment.

**The qualitative bar transfers more safely than any number**, and is the preferred instrument. From
both Ewaschuk and the SRE book: a rule should be urgent, actionable, require human intelligence, and
be novel — and one whose only possible response is acknowledgment should not exist. Ewaschuk's
default is toward removal: "err on the side of removing noisy alerts; over-monitoring is a harder
problem to solve than under-monitoring."

**Refuted, and deliberately not a rule of this method:** the categorical "a mechanism with no
downstream consumer should be retired." Adversarial verification found the underlying source's text
materially softer — such configuration is a *candidate* for removal. Consumerlessness is evidence
**toward** RETIRE and is never a sufficient condition. It is recorded here so it is not re-derived
as an obvious inference by a later reader.

## 10. The YAGNI scope boundary

Fowler scopes YAGNI to presumptive *capability* and says outright that it "does not apply to effort
to make the software easier to modify", naming refactoring and self-testing code as enabling
practices that do not violate it (<https://martinfowler.com/bliki/Yagni.html>).

**Peeling back enforcement is not abandoning quality-enabling practices**, and this method draws the
line rather than leaving it to taste:

- **In scope** — guards, gates, standing instructions, notifications, and automation carried on
  anticipated need, whose keep has not been earned by evidence.
- **Out of scope** — the practices that make change safe: tests and the suites that run them,
  refactoring, review, type checking, the build itself. A finding that reads "delete the tests",
  "stop reviewing", or "drop the type checker" is outside this method, and the correct response is
  to say so rather than to argue it on carry cost.

A corollary worth stating because it is easy to trip over: this method never recommends weakening
the practices whose **output it uses as evidence**. Retiring the record-keeping that makes tier 1
and tier 2 readable would make the next audit weaker than this one.

Some practitioners dispute how crisp this boundary is in practice. The dispute is about crispness,
not about existence — where a finding sits genuinely near the line, say so in the finding and let a
human place it.

## 11. The rollback ladder

**Never delete first.** Three rungs, in order, and a finding's remediation names the rung it is at:

1. **Config-disable**, wherever a kill switch exists. Flip the default off, narrow the matcher, or
   drop blocking to advisory. The artifact and its wiring stay; reversal is one configuration edit.
   **Trap to check first:** an "unset means enabled" fallback will silently re-enable a mechanism
   that was disabled by removing a key. A disable that relies on an absent value is not a disable —
   make the off state explicit and verify it took effect.
2. **Observe** for one window — default about **30 days or one release cycle**, whichever is longer,
   and **consumer-configurable**. Record what would have fired and what escaped. State the window's
   end date on the finding: an observation with no end date is an abandonment wearing an
   experiment's clothes.
3. **Delete, with recorded rationale.** The deletion carries the evidence and the observation result
   in its change description, so the next reader of the absence knows it was a decision rather than
   an omission. Where a re-add surface exists, preserve it — emptying a file while keeping its
   history is a retirement that leaves the door open, and it is cheaper to reverse than a deletion.

The two-stage order matches the feature-flag literature's: references are removed first and the
control-plane artifact is archived second, never the reverse
(<https://launchdarkly.com/docs/home/flags/archive>). And as in the one industrial-scale precedent,
**retirement diffs are always human-reviewed** — nothing in this ladder is autonomous.

**Withdrawal is a normal outcome of the ladder, not a failure of it.** An ablation that shows the
mechanism was load-bearing ends at rung 1 with the mechanism re-enabled and the finding closed as
KEEP, carrying the evidence the window produced. That is the ladder working: it converted an
UNPROVEN into a KEEP at the cost of one configuration flip.

## 12. Ownership

**Every finding names an owner**, resolved in this order:

1. A **declared owner** — a code-owners entry, a team or custody declaration, a documented
   maintainer for that surface.
2. **Authorship evidence** recorded during intent reconstruction (§4): blame on the introducing
   change, the linked issue, the change description's author.
3. **The operator running the audit, as owner of last resort.**

Ownerless is not a valid terminal state. An unowned mechanism is precisely the one nobody retires,
and leaving the field blank reproduces the condition the audit exists to fix.

**Out-of-repo custody.** When the artifact is a managed or synced copy, or lives in another
repository's control plane — organization-level policy, forge configuration, a shared workflow the
consumer only references — the owner is upstream and the remediation is a **delegation**, not an
in-repo edit. Patching a managed copy locally creates drift that the next sync silently reverts.
Record the delegation and its pointer on the finding.

Owner-routed batches are the industrial precedent: Piranha assigns each generated removal diff to
the flag's owner, who lands, modifies, or abandons it — the mechanism by which 88% of its diffs were
acted on.

## External authority

- <https://martinfowler.com/bliki/Yagni.html> — Martin Fowler, "Yagni": the four costs, the carry-cost
  definition this method argues in, and the explicit scope boundary in §10.
- <https://ai.stanford.edu/~ronnyk/ExP_DMCaseStudies.pdf> — Kohavi et al., controlled-experiment case
  studies: the base rate behind the default-skeptical posture.
- <https://milkov.tech/assets/psd.pdf> — John Ousterhout, *A Philosophy of Software Design*:
  incremental accumulation, and why a single removal reads as no improvement.
- <https://docs.google.com/document/d/199PqyG3UsyXlwieHaqbGiWVa8eMWi8zzAn0YfcApr8Q/preview> — Rob
  Ewaschuk, "My Philosophy on Alerting": the removal default, the qualitative bar, the 50% and 10%
  figures. Mirror: <https://gist.github.com/msgodf/86a3fc7fcd3ce663ff37>.
- <https://sre.google/sre-book/monitoring-distributed-systems/> — Google SRE book, ch. 6: the
  once-a-quarter removal-candidate passage and the "aspirational" self-hedge.
- <https://launchdarkly.com/docs/guides/flags/technical-debt> and
  <https://launchdarkly.com/docs/home/flags/archive> — evidence-gated decommissioning, the
  five-condition staleness gate, and the two-stage removal order.
- <https://manu.sridharan.net/files/ICSE20-SEIP-Piranha.pdf> — Uber's Piranha (ICSE-SEIP 2020): the
  industrial-scale results, the human-review requirement, the intentionally-dormant finding, and the
  Knight Capital motivation. Implementation: <https://github.com/uber/piranha>.

# Changelog

All notable changes to the `claude-config` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.21.6]

### Changed

- **`audit-instructions`: `I8-c`'s scope is now positively confirmed narrow, and the row states what
  the leakage costs beyond the turn it appears in** (criteria 1.14.0). The row flags a
  don't-think / don't-reason directive, and rested on a single source — the Opus 5 guide's "Running
  with thinking disabled" — with `Model scope: opus-5` held only by the fact that no wider statement
  had been found.

  Troubleshooting thinking states the same claim from the symptom side, "System-prompt rules
  instructing the model not to think or not to reason increase the tag leakage", and it does so on a
  **model-agnostic feature page** — the surface where a wider claim would surface if there were one.
  It names Claude Opus 5 anyway. So the scope stays where it is, but for a better reason: upstream
  had the chance to widen and declined, which is the reasoning `I10` already applies to a declined
  widening. The promotion gate remains unmet, deliberately.

- **The consequence clause the row was missing.** The same section states that "A leaked tool call
  never runs, and in agentic loops the leaked text stays in the conversation history, so later turns
  are affected as well", and that leakage is "most commonly on tool-heavy workloads such as search".
  Both now travel with the row: the first because it makes the finding a history-poisoning failure
  in an autonomous lane rather than one malformed response, and the second because it tells an
  auditor which surfaces to read first. The `Source` line carries its own verification date and a
  recheck trigger keyed to the claim gaining a model beyond Opus 5, which is the event that would
  move the promotion gate.

- **The `Sources` block's parenthetical for that page** covered the per-request 400s and the effort
  restriction's model range only, so it understated what the catalog now cites the page for; it
  names the leakage claim as well.

## [0.21.5]

### Added

- **`audit-instructions`: `I18-a`, a leading thinking block treated as required where the model does
  not require one** (criteria 1.13.0, taking the next minor over PR #1917). I18 covered only what a
  surface does to thinking blocks it *has* — dropping the `signature`, the `type == "thinking"`
  filter, editing the latest turn's blocks. The opposite error had no row: believing a block must
  be there. The Steering
  thinking page states the relaxation outright — "Assistant turns don't need to start with a
  thinking block" — with three consequences that become the row's three detect shapes: reinsertion
  when assembling history from mixed sources, rewriting history on resume under a different
  thinking configuration, and logic that reads an assistant turn's first block as though it were a
  thinking block.

  **It is a sub-row of I18 rather than a new criterion because the two are one mechanism seen from
  both ends.** The remediation a reader reaches for once they believe a block is required is to
  fabricate one, and a hand-built block carries no valid `signature` — which is I18's own shape 1
  and a rejected request. So this row is the upstream *cause* of an I18 violation; both are reported
  when a surface states the premise and acts on it. I18 gains a two-sentence lead-in naming the
  pairing and a `Base row:` label; its detect, fences, source and stamp are unchanged.

  **Reach is I18's, unchanged, for all three shapes** — a path back to the model, whatever the file
  format. Presence-assuming logic that only ever *reads* is recorded as out of reach rather than
  excused: the page's caution sits in the request/response frame and says nothing about stored
  transcripts, whether a harness transcript carries thinking blocks at all is unestablished, and the
  harm there would be the consumer's own logic rather than a 400 — a code-correctness matter this
  catalog does not audit. The row carries a `Re-scope when` clause for the day that shape is
  documented. Severity is `warning` against I18's `error` on its own footing: wasted work plus a
  fabrication risk, not a guaranteed rejected request.

  **The carve-out is upstream's own, and exactly as wide as its source.** Models using a legacy
  manual thinking budget do enforce that the final assistant turn of a thinking-enabled request
  begins with one, so text scoped to that mode AND that turn is correct; a legacy-scoped
  instruction demanding the block on every assistant turn over-requires past its own source and
  still flags — the finding is the missing gate, never the mention, as in `I17-c`. The row also
  fences itself against being read as license to drop blocks: the relaxation "is about validation,
  not about what you should send".

  **Decisive source, with the sibling as corroboration.** The Thinking page carries the same pair
  compressed into one sentence inside "Thinking with tool use" — extended (manual) mode "additionally
  enforces that the final assistant turn of a thinking-enabled request begins with a thinking block",
  and "Adaptive mode relaxes this: no assistant turn needs to start with one." Steering thinking is
  where the relaxation is stated operatively, with the three history-shape consequences the detect
  shapes are drawn from and the presence caution, so it is cited as decisive and the sibling as
  corroboration. Separate from both is that page's strip claim — the API "may strip thinking blocks
  that would create an invalid turn structure" — server-side degradation of a request rather than a
  rule about what history a caller may send. The Steering thinking page joins Sources. Local
  coverage measured 2026-08-04: zero
  operative instances, on the same footing as I18, with a re-measure clause. The one transcript
  consumer here, `session-flow`'s retro parser, selects blocks by each item's own `type` rather than
  by position, so it is correct by construction rather than by this rule.

## [0.21.4]

### Changed

- **`audit-instructions`: `I17` gains a second arm — the models that reject a thinking-disable
  outright, at every effort level** (criteria 1.11.0 → 1.12.0). The base row detected a *pairing*: a
  thinking-disable surface together with `xhigh` or `max` effort, on Opus 5 and later. The Thinking
  page states a second restriction in the paragraph directly after that one — "Claude Fable 5,
  Claude Mythos 5, and Claude Mythos Preview reject `thinking: {type: "disabled"}`: thinking cannot
  be turned off on these models" — with no effort qualifier at all.

  **The gap was a wrong remediation, not only a missed case, which is why this amends the base row
  rather than adding a sibling.** Either reading of the old row's range was a defect. Read as
  covering Fable 5, the row fired and handed out `Remediate`'s "lower the effort to `high` or below,
  or leave thinking on" — advice whose first branch still returns a 400 on that family. Read as
  excluding it, the unconditional reject went undetected and the row's own `Must NOT flag` fence
  ("a thinking-disable surface named with no effort level in reach of it") actively excused it. Both
  are now scoped to the arm that earns them: the fence applies to the Opus 5 arm, and the second
  arm's remediation has one branch, not two.

  **Only the API form joins the second arm.** On **Fable 5** the harness disable surfaces —
  `MAX_THINKING_TOKENS=0`, the session toggle, `alwaysThinkingEnabled` — are silent no-ops rather
  than errors, which is `I17-a`'s failure and stays there; for **Mythos 5 and Mythos Preview the
  harness pages state nothing**, so the row claims nothing about their harness surfaces. The
  scoping matters because model configuration names Fable 5 alone and never discusses Mythos
  — asserting the family would be the catalog breaking its own does-not-state standard. The row
  heading changes from "at an
  effort level that forbids it" to "where the model forbids it", since an arm with no effort operand
  no longer fits the old wording. **Local coverage measured, not asserted:** zero operative
  instances, with all six occurrences of the disable literal being documents *about* the
  restriction — the audience-test fence, not a passed check.

- **`audit-instructions`: `I17-b` extends from effort churn to thinking churn, and its harness
  carve-out is re-scoped to the half that earns it.** The row detected a mid-session *effort* change
  prescribed without its cache cost. The Thinking page puts the thinking configuration in the same
  position as effort — both "are rendered into the prompt itself, so changing any of them starts a
  new cache prefix" — naming switches among `adaptive`, `enabled` and `disabled` and changes to
  `budget_tokens`.

  **The carve-out is the load-bearing part.** The old row excused "a Claude Code surface" wholesale,
  because the harness "asks you to confirm before applying the change". That dialog is documented
  for effort alone: `code.claude.com/docs/en/prompt-caching` names exactly two settings outside the
  prompt text that are still part of the cache key — model and effort level. Left unscoped, the
  extended row would have silently asserted that the harness warns before a thinking toggle, which
  nothing upstream says. The carve-out now names effort explicitly, and the thinking half is stated
  for the API and Agent SDK callers the page's claim actually covers rather than reaching for a
  harness consequence the docs do not carry.

- **`audit-instructions`: the Thinking page's Sources entry names the two properties these arms rest
  on** — the models that reject a thinking-disable outright, and what a thinking or effort change
  does to the cache prefix. `I17` base and `I17-b` were re-verified live against their full source
  sets on 2026-08-04 and carry that stamp; `I17-a` carries a split stamp — only its new
  session-toggle/`alwaysThinkingEnabled` clause was re-verified 2026-08-04, its original claims
  keep their 2026-08-02 check; `I17-c` is untouched and keeps its own. `I17-a`'s Detect gains the harness controls its explanation already
  named: the session thinking toggle or `alwaysThinkingEnabled` presented as turning thinking off on
  Fable 5 is now flagged (model configuration states they "have no effect there") — previously the
  base row routed that failure to `I17-a` while no arm of it actually detected it. `I17-b` also
  gains a reach clause — its thinking half covers API and Agent SDK surfaces only, since the harness
  documents neither a dialog nor a cost for a mid-session thinking toggle — and a co-firing note
  against `I17-c` scoped to accepted changes: a rejected request completes no turn and an ignored
  value changes no configuration, so where `I17-c` condemns the control the cache-cost claim never
  materializes and `I17-c` fires alone; both fire only when a surface prescribes both an invalid
  control and, separately, an accepted mid-session change.

## [0.21.3]

### Added

- **`audit-instructions`: `I8-e`, forced interim-status cadence, scoped `sonnet-5`** (criteria 1.10.0
  → 1.11.0). The Sonnet 5 guide prescribes removing exactly the scaffolding `I8-d` reaches on a
  Fable 5 target — "If you've added scaffolding to force interim status messages ("After every 3
  tool calls, summarize progress"), try removing it" — on its own ground, that the model already
  reports well without it.

  **It is scoped, not unscoped, and that was the contested call.** The obvious reading is that a
  second model guide now converges on `I8-d`'s cadence arm, which would meet the promotion gate and
  let one row fire fleet-wide. It does not. The gate wants two guides *stating* the claim, and the
  Fable 5 guide never states it: its "Longer turns by default" section prescribes adjusting client
  timeouts, streaming, and progress indicators, says nothing about removing instructed status
  cadence, and elsewhere that guide recommends *adding* a send-to-user progress mechanism. `I8-d`
  reaches the cadence by inference from a turn-duration premise — a legitimate ground for a scoped
  row, but not a second statement. Two scoped rows therefore cover one instruction shape from the two
  guides that reach it; exact-match scoping means they never co-fire, and both rows now say so, so a
  later reader does not "deduplicate" them.

  `I8-d`'s detect and fences are unchanged; it gains one cross-reference bullet naming the
  relationship.

- **`audit-instructions`: `I17-c`, a fixed thinking budget prescribed where adaptive reasoning
  ignores or rejects it.** `I17-a` already covers `MAX_THINKING_TOKENS=0` sold as a universal off
  switch — the claim that thinking can be turned *off*. Nothing covered the adjacent claim that
  thinking depth can be *set to a number*, whose two arms fail in opposite ways: a nonzero
  `MAX_THINKING_TOKENS` is silently ignored on adaptive-reasoning models and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` cannot rescue it, while API `thinking: {type: "enabled",
  budget_tokens: N}` returns a hard 400 across Opus 4.7 and later, Sonnet 5, Fable 5, and Mythos 5.
  Unscoped, with the model ranges as Detect conditions rather than a `Model scope` annotation, for
  the reason `I17` base states.

  **The row's central fence is that the finding is the missing gate, never the mention.**
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` is *not* a retired variable: it is live on Opus 4.6 and
  Sonnet 4.6, where it does exactly what it says, and it lost its reach over the adaptive-reasoning
  models only at Claude Code v2.1.111 — so the gate is a release as well as a model set, and text
  scoped to an earlier release is also correct. The obvious implementation — grep for the variable
  name and call every hit stale — would flag every accurate piece of documentation about it, so the
  row carries I12's precondition rule applied to these literals explicitly.

### Changed

- **`audit-instructions`: `SKILL.md` records why `I8-e` is not seeded** into the deterministic
  pre-scan. It sits with `I8`'s base row and `I8-d` in the lane-only list, but on a narrower ground:
  its skeleton is patternable, and it waits only on an attested instance to calibrate the interval
  forms against — not on the "phrasings too varied" reason its neighbours carry.

- **`audit-instructions`: the model migration guide joins the catalog's Sources.** `I17-c`'s API arm
  cites it for the model range over which manual extended thinking is rejected. Per the catalog's own
  rule that the trigger set is the source set, this **widens the catalog-wide recheck trigger** —
  every row now re-verifies when that page changes. That is the intended consequence of citing it,
  recorded here rather than left as a side effect of adding a bullet.

## [0.21.2]

### Changed

- **`audit-instructions`: I10's `Model scope: fable-5` is now positively sourced instead of resting
  on a declined widening** (criteria 1.9.0 → 1.10.0). The row's conclusion does not move — Mythos 5
  is still not in scope, and still should not be. What moves is the ground under it. Since 0.18.0
  the row held its narrow scope by reading an omission: the Thinking page names both Claude Fable 5
  and Claude Mythos 5 for the adjacent raw-chain-of-thought property, then names Fable 5 alone for
  the refusal, and the row inferred deliberateness from that declined chance to widen. That is an
  argument from authorial choice, and it is the weakest link in an otherwise well-cited row —
  silence is evidence only until someone finds the sentence.

  The sentence exists, on the page that owns Mythos 5: "Claude Fable 5 includes safety classifiers
  that can decline certain requests. Claude Mythos 5 does not include these classifiers, so this
  section applies to Claude Fable 5 only" ([Introducing Claude Fable 5 and Claude Mythos
  5](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5),
  fetched 2026-08-03, HTTP 200).

  **The row states it as two steps, each from the page that owns its half**, rather than letting
  either page settle it alone. The introducing page excludes the whole classifier *set* for
  Mythos 5 — "these classifiers," referring to the set that can decline requests — and Refusals and
  fallback puts this row's category inside that set, listing `reasoning_extraction` among the
  categories a refusal reports. Collapsing the two into one citation would rebuild the near-miss
  scope inheritance the catalog's model-scoping block forbids, only pointing the other way; keeping
  them separate is what makes it a citation rather than an inference wearing one. Note that Refusals
  and fallback attributes the classifiers to Claude Fable 5 **and Claude Opus 5** and never mentions
  Mythos 5 — the exclusion is the introducing page's alone to state, which is why both are cited.

  The introducing page joins `## Sources`, so the catalog-wide recheck trigger fires this row if the
  page changes; which models carry the classifier set is a per-model fact and will move. No narrower
  per-row trigger is owed, per the stamp rule's own carve-out for claims the Sources set already
  covers. The 0.18.0 entry below is left as written — it records what shipped then, and the
  reasoning it describes was correct for the sources available at the time.

## [0.21.1]

### Added

- **`audit-instructions`: row I8-d, short-turn assumptions** (criteria 1.8.0 → 1.9.0). Tier
  `behavioral`, `Model scope: fable-5` — the promotion gate is unmet and stays unmet: the claim
  appears in one model guide and on no model-agnostic page, so the row is inert on other targets
  and reports `skipped-for-target`.

  **Detect** is instruction text resting on the premise that a turn is short — a forced
  interim-status cadence ("summarize every N tool calls"), a directive to answer quickly, any
  progress rhythm pinned to a turn rather than to the work. Individual requests now run for
  minutes at higher effort and autonomous runs for hours, so such a rhythm fires on work that has
  not reached a reportable boundary and interrupts exactly the long runs the model is used for.
  Four fences keep it off legitimate text: an output-length instruction is I8 base's subject, not
  this one's (the axis here is the turn's duration, never the reply's size); a latency or duration
  requirement the surface genuinely owns — an SLA, a downstream timeout, a human review rhythm — is
  a constraint it is entitled to state; a document *about* the pattern is exempt on the same
  audience test I8-b, I17, I18 and I20 already use; and a cadence carrying its own explicit
  observability or interruptibility rationale is a design the surface is entitled to make — that is
  the very guarantee the row's Remediate line protects — exempt unless evidence shows it was
  calibrated to an obsolete turn length rather than to the work.

  The row is **lane-only, not seeded** by `instruction-scan.sh`, and `SKILL.md` now says so
  alongside the existing I8-c disclosure. A pattern family was considered and declined: the
  phrasings are too varied for a rule that would earn its false-positive rate, and the one
  candidate string in this repository resolves to the exempt meta case, so the family would have
  shipped with a known false positive and no true one.

  The guide pairs this behavior with advice to adjust **client timeouts, streaming, and progress
  indicators**. That half is harness client configuration rather than instruction content, so the
  row states plainly that it is out of scope and that no row claims it — the shape that *would*
  reach this catalog is instruction text prescribing a short client timeout, and none is attested.

### Changed

- **`audit-instructions`: I8's base row gains one named worked instance — the delegation
  throttle.** A cap on concurrent workers, a one-at-a-time rule, or an instruction to block until
  each subagent returns, *where the surface's own ground is that subagent handling is unreliable*.
  Current guidance runs the other way (readier dispatch, asynchronous orchestrator-to-worker
  communication), so such a throttle is the base row's generic case with a name on it — which is
  why it lands as recognition material inside I8 rather than as a fourth rule competing with it.
  The qualifier is the whole fence: **a cap carrying its own non-model rationale is not this
  instance.** Reviewability of returns, rate limits, cost, and shared mutable state each justify a
  bound on their own terms, and that justification belongs to the surface making it. The base row's
  Source gains the guide's "Parallel subagents" sentence as the instance's basis; the row restates
  no volatile literal and so owes no per-row verification stamp under the catalog's own
  binds-on-touch rule.

## [0.21.0]

### Added

- **`audit-instructions`: the two agnostic-mechanism rows from the IA-6 / IA-10-A2 ownership split —
  I21 and I22** (criteria 1.7.0 → 1.8.0). Both source rules were **compounds**: an agnostic
  mechanism fused to a consumer-state instance naming this fleet's own machines, files, and dates.
  Routing either wholesale was wrong in both directions — outward it would ship our private state to
  every consumer, inward it would strand a reusable staleness control. Each was split at the
  mechanism/instance line; only the mechanism halves are here. The instance halves (a dated vet, a
  chezmoi-managed fleet pin) are drafted for the consumer repository and deliberately ship nowhere
  in this plugin.

  - **I21 — effort level pinned across a model change with no re-sweep** (`mechanical`,
    `ANTHROPIC-DOCS`, `warning`, unscoped). The effort scale is calibrated per model, so the same
    level name does not carry the same underlying value across models, and a level measured against
    one model then carried to the next is a pin nobody re-measured. The promotion gate is met on the
    strong form: model configuration states the calibration property **with no model qualifier**, so
    that page alone carries the row; the effort page's Opus 5 subsection is cited only for the
    remediation's wording, and its per-model placement does not narrow a property stated generally.

    **The model range is a Detect condition, not a `Model scope` annotation**, on I17's reasoning.
    It is in Detect because the *consequence* varies: Claude Code applies a model's default effort
    on first run of Fable 5, Opus 4.8, or Opus 4.7 and holds it, so a carried level there is
    overridden harmlessly — while **Opus 5 has no such hold** and a stale pin actually reaches the
    request. One thing is recorded as **unresolved rather than inferred**: the page names `/effort`
    and `--effort` as *examples* ("such as") of the explicit choice that releases the hold, so
    whether a settings-file `effortLevel` pin releases it is not stated anywhere read for this row.
    The row therefore fires on the missing re-derivation regardless of model, and the hold is
    severity context, never a fence.

    Four fences keep it honest. A prescription of **`high` is exempt only where `high` is the
    resolved target's default** — it is "Equivalent to not setting the parameter", so on such a model
    it carries no measured calibration. **The exemption keys to the resolved target, never to the
    wording**, which is what makes it correct: `high` is the default everywhere **except Opus 4.7,
    which defaults to `xhigh`**, so when the target is 4.7 the exemption lifts and a broad
    model-agnostic "always use `high`" naming no model is a finding — indeed the sharper case, since
    a pin written where `high` was the no-op default becomes a silent step-down the moment it reaches
    a model whose default sits above it. A resolved target always exists, because the skill body
    aborts rather than run against an unresolved one, so the fence never guesses. A **per-task**
    choice
    (`ultrathink`, "reach for `xhigh` on hard problems") is not a durable pin. **`effort:`
    frontmatter and `effortLevel` keys route to `claude-config:audit`** on I17's
    instruction-text-versus-config discriminator. And **schema documentation and its illustrative
    samples** are fenced **separately** rather than folded into the config fence, because a worked
    example quoted inside documentation prose is not a key living in a config file and the config
    fence would not have reached it — the level in a sample demonstrates syntax, not a measured
    choice. That fence ends where the demonstration does: documenting the field *and then telling the
    reader which level to put there* is prescribing, and stays in scope.

  - **I22 — model-routing doctrine with no baseline named** (`mechanical`, `OPINION`, `info`,
    default **off**, enabled by `--opinion`). First-party lane assignments derived from a reading of
    vendor selection pages, written down with neither the baseline they came from nor an event that
    re-opens them, become a claim about a model generation that has since passed, told in the
    present tense. Its own contribution beyond "attach a trigger" is the **delta-not-re-run**
    discipline: the action on a trigger is a targeted delta check against the named baseline, never
    a re-derivation from scratch — a trigger nobody can afford to run is not a control.

    **The row carries no baseline of its own, by design.** Naming a date or a vet here would hand
    every consumer a foreign snapshot as their baseline, reproducing in their repos the exact drift
    the check exists to catch.

    Its third-party fence is stated **narrowly on purpose**: transcribed practice is out of scope
    only because there is no vet to point at, **not** because a sync stamp makes it fresh. A stamp
    tracks whether the transcription is current, never whether the transcribed advice still names a
    live model — so a stale lane recommendation inside a faithfully synced pack stays stale. That
    residual is the transcribing surface's to carry, and the fence says so rather than implying the
    sync path has it covered.

    Its non-duplication is stated in the row rather than assumed. **I19** covers a restated
    *benchmark figure* and asks for the four-part record; it says nothing about lane assignments and
    nothing about how to act when a trigger fires. **The catalog-wide recheck trigger** does not
    reach it either — that trigger governs *this catalog's* staleness against its Sources, not an
    audited surface's staleness against the pages its doctrine was read from. It ships
    `Source: none` on I19's footing and adds no Sources entry for the same reason.

### Changed

- **`audit-instructions`: the model-configuration and effort Sources entries name what I21 depends
  on** — the per-model calibration of the effort scale and the first-run default hold, and `high`'s
  equivalence to omitting the parameter plus the carry-over sweep advice. The catalog's "the trigger
  set is the source set" invariant makes these parentheticals load-bearing: a dependency the entry
  does not name is a dependency nothing watches.

- **`audit-instructions`: `--opinion` no longer restates which rows it enables.** The flag's
  description in the skill body carried its own copy of the `OPINION` row set, which is a second
  place to update on every new `OPINION` row and, when stale, silently narrows the flag below what
  the catalog actually defines. The set is now read from the catalog at run time, where the
  enablement policy already lives, and the run's tier-transparency line reports the count it found —
  removing the drift class rather than correcting one instance of it.

## [0.20.1]

### Fixed

- **`audit-pass`: age alone no longer reclaims an applying run's lock where the platform exposes no
  process start identity (#1786).** The reclamation rule's second conjunct was a start-identity
  match, and the "where none exists, **age alone reclaims**" fallback had no liveness conjunct at
  all — the lease's heartbeat was mentioned one sentence later as prose no reclamation test
  consulted. A live `--fix` exceeding 30 minutes on such a platform lost its lock to a second
  applying run, contradicting assertion 3.1's *"exactly one proceeds"* on exactly the platform least
  able to detect the collision. The lock now records the holder's **run id** (and its start identity
  where one exists) so reclamation can find the holder's lease, and where no start identity is
  available the lease is the second conjunct: past 30 minutes a **stale** or `released` lease
  reclaims and says so, a **live** lease refuses exactly as it would inside the window, naming the
  run id and `heartbeat_at`. The classification reuses §3's existing two-sided liveness test rather
  than introducing a second one. This does not reintroduce the unreclaimable lock the age bound
  guards against: a crashed holder stops refreshing, so its lease goes stale within the liveness
  threshold, and a missing or unreadable lease is treated as stale — the absence of a heartbeat is
  not evidence of life. Same defect class and same remedy shape as `claude-ops`' restart-consumer
  (#1759/#1760), where a live PID without a boot identity may only defer a reclaim — that deferral
  needs a hard ceiling only because its holder publishes no lease. A lock written *before* this rule
  carries no run id and is covered too: reclamation establishes the conjunct the other way round, by
  enumerating every lease under `runs/<state-key>/`, so upgrading mid-run never hands a live holder's
  lock away. The order of the two writes is now normative for the same reason — an applying run
  writes its lease **before** it takes the lock, since a lock whose lease does not yet exist would
  read as stale and be reclaimed on age alone through the window between them. New assertions 3.12,
  3.13, and 3.14; new evals 27 and 29.
- **`audit-pass`: a suppression no longer re-applies silently across an anchor collision (#1786).**
  §1 guarantees that two identical normalized excerpts under one heading path collide and that *"no
  suppression carries forward across it"* (assertion 1.10a), but §4's matching table had no
  collision exception — and a collided site's anchor is by construction **unchanged**, since the
  occurrence discriminator digests the heading path. A previously-suppressed excerpt that later
  gained an identical duplicate therefore satisfied the `SAME, UNCHANGED` row exactly and
  re-suppressed itself with no report. Collision is now tested ahead of the anchor comparison in
  every row and routes to the existing `OLD CLOSED, NEW OPENED` disposition — entry stale per 4.2,
  finding unsuppressed, collision named with its occurrence count — reusing the section's
  established fail-closed answer to an ambiguous match rather than adding a fifth disposition. New
  assertion 4.7; new eval 28.

## [0.20.0]

### Added

- **`audit-instructions`: four consumer-facing rows — I17, I18, I19, I20** (criteria 1.6.0 →
  1.7.0). All four carry knowledge outward rather than inward: they detect defects in repos this
  fleet does not control, and each is agnostic to user, machine, company and repo.

  - **I17 — thinking disabled at an effort level that forbids it**, as a base row plus **I17-a**
    and **I17-b**, on I8's pattern: three shapes with three different decisive sources are three
    rows, not one row with three citations, and splitting them lets each carry its own severity.
    Base row (`error`): pairing a thinking-disable surface with `xhigh` or `max` effort returns a
    per-request 400, and the pairing is assemblable from configuration literals alone. **No harness
    documentation describes a pre-request guard**, so the row states the hazard as real and
    unguarded and deliberately does **not** claim the harness prevents it. It also catches the
    `ultracode` **setting**, which matches neither literal but "sends `xhigh` to the model" and so
    produces the identical rejection — match the effort that reaches the request, not the spelling.
    The same spelling as a **prompt keyword** is fenced out: it runs one task as a workflow
    "without changing the session's effort level", so no effort reaches the request. And it tells
    an auditor **not** to hunt `effortLevel: max`: the settings schema stops at `"xhigh"`, so that
    literal is unreachable there. I17-a (`warning`) is `MAX_THINKING_TOKENS=0` sold as a universal
    off switch, which it is not — no effect on Fable 5, parameter merely omitted on third-party
    providers. I17-b (`info`) is a mid-session effort change prescribed without its cache cost, and
    it explicitly does **not** fire on Claude Code surfaces, where the harness already asks for
    confirmation; it is for surfaces instructing an API or Agent SDK caller, where no dialog exists.

    **The model range is carried as a Detect condition, not a `Model scope` annotation** — the
    catalog's annotation is for rows sourced from a single model's *guide*, matches by exact string
    equality, and has no range form, so annotating `opus-5` would make the row inert on the next
    generation while the restriction ("Claude Opus 5 and later models") still holds. The source is
    a model-agnostic feature page, so the promotion gate is met and the row is unscoped. I20 handles
    its own model range the same way.

    The settings-file scan is explicitly **not** taken: it belongs to `claude-config:audit`, and an
    instruction-content catalog that also scanned settings files would claim authority a sibling
    already holds. The discriminator is whether the content instructs, not which file holds it, so
    a prompt-type hook's injected text stays in scope even though it lives in a settings file.
  - **I18 — thinking blocks altered on the way back to the model.** Signature preservation, the
    `block.type == "thinking"` type-filter smell, and within-turn echo integrity. Reach is wider
    than Messages API client code — Agent SDK callers, harness integrations, and tooling that
    rewrites a stored transcript later replayed or resumed — but the criterion is **a path back to
    the model**, not the file format read, so read-only transcript analysis stays out. The row
    ships **no `redacted_thinking` handling clause premised on those blocks being present in local
    transcripts** — that premise is unevidenced. The term survives only inside the upstream
    sentence that is the type filter's entire stated failure mode, which is where the harm lives.
    Zero instances of all three shapes here, recorded as a dated measurement with its own trigger
    rather than left to read as a clean audit.
  - **I19 — restated external benchmark figure with no recheck trigger.** `OPINION`-tier and off by
    default, because no official page states that a restated benchmark figure needs a
    re-derivation event; the four-part shape it asks for is this monorepo's upstream-drift
    convention, and in a standalone install the four parts rather than the path are the
    requirement. Carries one fence the fleet needed: **a verbatim upstream baseline held for drift
    detection is never flagged**, since stamping it would corrupt the byte comparison it exists to
    serve. That is a genuine suppression, which is what separates it from plugin-cache content and
    managed materializations — those are still flagged, and the finding becomes a routing
    recommendation to the owning repository.
  - **I20 — prefilled assistant response**, at `error`: following the instruction produces a
    rejected request, the same consequence class as I17 and I18. Severity tracks consequence, not
    expected frequency — this is a standing model-delta row whose hit rate here is zero, and it
    fires in consumer repos that still prefill.

- **`audit-instructions`: per-row verification stamps** (criteria 1.6.0 → 1.7.0). A row restating a
  volatile upstream *literal* now carries the four-part record — claim, basis, as-of date, and a
  recheck trigger naming an observable event. A row that only points at its page carries none,
  because a pointer cannot go stale. The block resolves its own relationship to the catalog-wide
  Recheck-triggers rule rather than leaving two authorities over one behavior, which is precisely
  the conflict I15 exists to find: a per-row stamp **supplements** the catalog trigger and never
  narrows it, a row's own trigger names only what the Sources set would miss, and **the catalog
  trigger wins** where they disagree. The requirement **binds on touch**, per the upstream-drift
  convention, so rows predating it are not retroactively non-compliant. Shipping a check that
  silently encoded a snapshot as permanent truth would reproduce, in consumers' repos, the drift
  this catalog exists to detect.

- **`audit-instructions`: five pages join `## Sources`** — effort, thinking troubleshooting,
  settings, environment variables, and prompt caching. As at 0.18.0 and 0.19.0 this is a
  second-order change, and it is intended: the Recheck-triggers block makes the trigger set the
  source set, so adding a page widens the staleness trigger for the **entire** catalog, not only
  for the rows that cite it. A cited page nothing watches would leave those rows depending on an
  unwatched source.

## [0.19.0]

### Changed

- **`audit-instructions`: I8-b (conservative-reporting detection) is promoted to unscoped**
  (criteria 1.5.0 → 1.6.0). The row carried `Model scope: opus-5` and fired only when the resolved
  target model was Opus 5. The **Sonnet 5** prompting guide, "Code review harnesses", states the
  same claim about the same behavior — a review prompt saying "only report high-severity issues",
  "be conservative", or "don't nitpick" is followed literally, so the model investigates just as
  thoroughly and then withholds findings below the stated bar. Two first-party model guides of the
  same class converging is the promotion gate's **second arm**, so the row is now annotated the way
  I7 is and fires for every target model. The Sonnet 5 guide joins `## Sources`, as the
  Recheck-triggers block requires of every cited page. The Detect line's "which **this** model
  follows literally" is now "which **current models** follow literally" — the demonstrative
  referred to the row's scoped model, and an unscoped row has none.

  **The Recheck-triggers block no longer enumerates the model-specific pages.** It read
  "Model-specific pages (the Fable 5 and Opus 5 guides) are superseded on each model generation" —
  a closed list the Sonnet 5 addition immediately falsified. It now reads "the per-model prompting
  guides under Sources", which stays true as guides join. The enumeration also contradicted its own
  paragraph three lines above, which argues that "naming a subset would leave the harness-behavior
  rows depending on pages nothing watches."

- **I8-b's Source line now cites the phrase it could not.** The row's Detect names three trigger
  phrases; **"don't nitpick" appears nowhere in the Opus 5 guide**, which states only the other
  two. The Sonnet 5 guide names all three verbatim, so it is that phrase's only cited home, and the
  Source line says so rather than leaving a trigger phrase attributed to a page that does not
  contain it.

- **I8-b's Remediate line gains the constructive half.** It said only "rephrase to
  report-everything + a separate filter/rank pass", which does not answer the case where a
  single-pass self-filter is genuinely wanted. The Sonnet 5 guide covers that case — "be concrete
  about where the bar is rather than using qualitative terms like `important`" — so the line now
  keeps the filter and asks for an enumerable test in place of a qualitative label.

  **Promoting this row flags nothing new in this repository.** The scanner's I8-b population here
  is 23 candidate rows across 6 files, every one of them already fenced by the row's own two
  fences — the restraint-clause shape (`code-tidying`'s tidyings catalog) and the quoted/meta
  surface (this criteria file, the scanner and its tests, two model-adaptation delta chapters).

## [0.18.0]

### Added

- **`audit-instructions`: I10 gains a second corroborating source and a concretized remediation**
  (criteria 1.4.0 → 1.5.0). The Thinking page states the same `reasoning_extraction` refusal I10
  already cited from the Fable 5 guide, from a second, independent page — a feature page rather than
  a model guide. The row records why that citation does **not** move the promotion gate: the page's
  own section names both Claude Fable 5 and Claude Mythos 5 for the adjacent raw-chain-of-thought
  property, then names Fable 5 alone for the refusal, so the narrower scope is deliberate rather
  than an omission. **`Model scope: fable-5` is unchanged, and `mythos-5` is deliberately not
  added** — no source states the refusal for Mythos 5, and inheriting it from a claim about a
  different property is exactly the near-miss scope inheritance the catalog's model-scoping block
  forbids.

  **The Remediate line now names the surfaces instead of gesturing at them.** It said "read
  structured `thinking` blocks or use a send-to-user tool"; the sanctioned reading surfaces are
  `Ctrl+O` verbose mode and the `showThinkingSummaries: true` setting in Claude Code, and
  `display: "summarized"` on the API. The two Claude Code surfaces are stated on the model
  configuration page, **not** on the Thinking page, so both pages join the catalog's `## Sources`
  list — the Recheck-triggers block makes the trigger set the source set, and a cited page nothing
  watches would leave the row depending on an unwatched source.

## [0.17.0]

### Fixed

- **`audit-instructions`: the conflict pass excluded command hooks whose output is injected into the
  session's context (#1726).** `conflict-criteria.md` carried "Command-type hooks are outside this
  pass entirely", citing the context-window doc's compaction table, whose hooks row reads "Not
  applicable; hooks run as code, not context". That row is about the hook *mechanism* — a hook
  definition is not a context block to be re-injected — and the same page says the opposite about
  handler *output*: a `PostToolUse` hook "reports back via `hookSpecificOutput.additionalContext`.
  That field enters Claude's context." The exclusion therefore dropped one half of every pair whose
  hook side was live standing instruction text, silently, since a per-surface lane never sees the
  surface at all.

  **The discriminator is now whether the handler's output reaches this session's context, not
  whether the handler is `type: "command"`** (criteria 1.1.0 → 1.3.0). Handler stdout on
  `SessionStart`, `UserPromptSubmit`, and `UserPromptExpansion`, and
  `hookSpecificOutput.additionalContext` on a main-session event that accepts it, enter the
  comparison set **as text**; stdout on any other event still does not. `mcp_tool` shares the stdout
  channel and `http` the JSON one. `prompt` and `agent` handlers keep their existing treatment —
  they return a decision, so they still enter as the act they gate, never as their prose.

  **Type still decides registrability, and the pass resolves the event×type pair before admitting a
  surface.** "Not all events support every hook type"; `SessionStart` takes only `command` and
  `mcp_tool`, so an `http` handler there is not a surface with unreadable text but one that cannot
  be registered at all. An `http` handler also has no stdout — it returns a response body.

  Four residency bounds ship with the admission, so the widening does not manufacture pairs.
  `SubagentStart` and `SubagentStop` `additionalContext` is "Context added to **the subagent's**
  context", so it fails gate 1 against every main-session surface exactly as the active output style
  does — it pairs against the agent definition it runs under, never against the main conversation's
  `MEMORY.md` or output style. Injected text is ordinary message history rather than a re-injected
  surface (a `SessionStart` hook re-injects after compaction only on the `compact` matcher, so a
  `startup`-only hook's pair is conditional there). Exit-2 stderr reaches Claude but is turn-scoped
  error feedback, not a standing directive, and it carries a gate only on the events that can
  actually block. And a hook's own configuration — command line, arguments, `matcher` — remains the
  gate rather than instruction text.

  Phase A's hook inventory splits into the two kinds accordingly, across settings scopes, managed
  settings, and plugin `hooks/hooks.json`, under unchanged no-secrets handling; where the injected
  text is not literal in the config (a handler that runs a script) the surface is recorded with its
  event and `matcher` and marked `text-unresolved` — a distinct marker, since a bare `unresolved`
  already names a precedence verdict — rather than invented. Because a hook-injected surface
  has no file of its own, the Output format now defines its anchor as the settings file, plugin
  `hooks/hooks.json`, or component frontmatter where the emitting handler is configured, qualified
  by that handler's event and `matcher`. The `hooks` scope value and the non-memory surface
  partition widen from "prompt-type hooks" to "hook instruction text" — without which the newly
  admitted surface could be read but never produce a finding — as do the two consumer surfaces that
  restate the list, the skill's own `description` and the plugin README. Skill and agent frontmatter,
  a documented hook location Phase A did not inventory at all, is added alongside — **split by
  ownership rather than filed under one tier.** A frontmatter hook in a user- or project-scope
  `.claude/skills/**/SKILL.md` or `.claude/agents/*.md` is as editable as the body it rides on, so it
  joins the **editable** inventory and produces a proposal of its own; only an enabled plugin's
  *cached* components stay in the read-only tier, whose contract yields no proposal and routes to
  another owner. Filing every frontmatter hook read-only would have mishandled the locally owned
  ones — and reading the item as plugin-cache-only would have left them inventoried nowhere. A
  frontmatter hook anchors at its own component file and frontmatter line, and a subagent's `Stop`
  hook is registered as `SubagentStop`, so the effective event is resolved before pairing.

  **The exit-2 gate is applied only where exit 2 can actually block.** Treating every exit-2 stderr
  message as the act it blocks manufactured an unsatisfiable conflict on events that block nothing:
  a `PostToolUse` linter exiting 2 would have read as a prohibition on the very tool a `CLAUDE.md`
  requires, though the tool already ran and the hook can neither block nor undo it — as this
  repository's own `PostToolUse` linter records at `plugins/actionlint/hooks/actionlint-check.sh`.
  The hooks page's per-event exit-2 table now partitions the treatment: exit 2 blocks on
  `PreToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `PreCompact`, and `UserPromptExpansion`,
  where the stderr enters as the act it blocks; on `PostToolUse`, `Notification`, `SubagentStart`,
  `SessionStart`, and `SessionEnd` nothing is prevented, so the message stays transient feedback and
  pairs as nothing. `SubagentStop` blocks but is subagent-scoped, so its act pairs inside the
  subagent rather than against a main-session surface.

  The hooks page is added to Sources and to the recheck triggers in both criteria files (catalog
  1.3.0 → 1.4.0, for the widened surface partition and I13 surface set); the per-event exit-2 table
  and the set of supported hook locations join the recheck triggers as newly load-bearing. Eval 14
  pins the admission on the case that exposed the gap: a `SessionStart` `type: "command"` handler
  injecting a standing behavioral block, against an active output style's format contract. Eval 15
  pins a project-scope frontmatter hook landing in the editable inventory rather than the read-only
  tier, and eval 16 pins a `PostToolUse` exit-2 handler producing no conflict against a `CLAUDE.md`
  that requires the tool it ran after.

## [0.16.0]

### Changed

- **`audit-instructions`: `conflict-criteria.md` gains two adjudication cautions on the mechanism
  escape hatch (criteria 1.0.0 → 1.1.0).** No must-not-flag case was added and `conflict-scan.sh` is
  unchanged. First: both tool-removal mechanisms — a bare-name `permissions.deny` rule and
  `disallowed-tools` — work by taking the tool out of Claude's pool, so recommending one against a
  skill whose text *requires* that tool leaves the mandate unsatisfiable rather than stricter; when
  the mandating side is a gate, the mechanism must land together with a rewrite of that side, and the
  pair is what gets recommended, never the rule alone. Second, and deliberately a caution rather than
  a drop rule: **availability-conditioning does not fail gate 5.** Rephrasing a mandate as "`X` when it
  is in the pool, otherwise ask inline" narrows how an act is performed, not whether — that is a subset
  of an always-resident prohibition's scope, not a disjoint condition, so the two still overlap
  wherever the tool is present and must-not-flag case 12 does not apply. Gate 3 then decides the pair
  on the rewritten text, testing the branch where the tool *is* present. Without this, a skill could
  neutralize a live Type A finding by appending a condition or softening a verb. The must-not-flag
  table gains a non-numbered row pointing at it, so a reader working the table finds it beside case 12.
  The permissions page is added to Sources and to the recheck triggers, since both cautions now rest
  on it.

### Fixed

- **`audit-instructions`: Worked Example 1's corpus counts were never reproducible from the method
  the example states (#1723).** It read "62 lines name the tool and 11 carry a
  `use_ask_user_question` opt-in gate on the same line, leaving 51 ungated". Measured with the
  example's own stated method — `plugins/**/*.md`, changelogs excluded — the figures are 69/11/58
  both at current `main` and at `049a4b9243`, the commit that shipped the doc, so this is a wrong
  measurement rather than drift; only the gated count, `11`, reproduces. Four plausible alternative
  denominators were tried and none reaches 62. The hardcoded figures are replaced by the two
  `git grep` commands that compute them, with `conflict-criteria.md` itself excluded from the pathspec
  — it names both tokens, including on the command lines, so an unexcluded measurement counts itself
  and drifts whenever the example is edited.

- **`audit-instructions`: Worked Example 1 no longer records a verdict on its own subject.** #1724
  changed the mandate side the example quotes. Rather than declare the pair closed, the example now
  shows the pre-fix state and its gate walkthrough, then states explicitly that **this file does not
  adjudicate the resulting pair** — the rewrite was authored in the same repository as these criteria,
  so a verdict here would be the author grading their own text, and the pair's operator-level half is
  an open question (now cited: #1722). It names two things not to assume while re-running the gates:
  that the pair dissolved because one side acquired a condition, and that a softened verb settles
  gate 3. It keeps what the history does establish — **no winner was named**, because the
  skill-body-versus-memory-surface authority relation the Unresolved table denies still does not
  exist, and a rewrite on one side is never the operator's decision.

- **`audit-instructions`: `conflict-scan.test.sh` Case 2's comment** no longer describes its fixture as
  the live worked example; the text it was drawn from is no longer in `repo-hygiene`. Comment only —
  no fixture, assertion, or scanner behavior changed, and the suite still passes 41/41.

## [0.15.0]

### Added

- **`audit-instructions`: Opus-5 model-delta rows in I8, and model scoping as a catalog axis**
  (criteria 1.2.0 → 1.3.0), from the dual-verified Opus 5 prompting-guide corpus. I8 gains three
  Opus-5-scoped rows: I8-a instructed self-check removal (classified by reviewer INDEPENDENCE —
  architected fresh-context or cross-vendor review is never a finding — with carve-out lanes for
  security review, destructive operations, managed-upstream-file changes, and PR merge gates);
  I8-b conservative-reporting detection, behavioral, with two criteria-owned fences
  (restraint-clause shape — the `code-tidying` tidyings "When NOT to apply" text is the canonical
  non-finding — and quoted/meta surfaces that discuss the pattern rather than instruct with it);
  I8-c don't-think / don't-reason directives. A new "Model scoping" section defines the semantics:
  single-model-sourced rows fire only when the run's resolved target model matches by exact
  equality of the normalized version token (point releases and dated IDs never auto-match a
  base-version scope), otherwise reported `skipped-for-target`; fleet-wide promotion only via the
  documented gate. I8's base row and I10 are annotated with their `fable-5` scope (single-model
  sources; gate unmet) — a deliberate coverage narrowing: on any non-`fable-5` target those two
  now report `skipped-for-target` instead of findings, until the promotion gate is met.
- **`audit-instructions`: `--target-model <version>` argument.** Default resolution ladder:
  explicit argument, else the session's effective model (launch overrides included, not the bare
  settings pin) normalized alias → version against live model-config docs; anything that cannot
  normalize to a single version — family alias (e.g. `opus` with a context-window suffix), absent
  `model` setting, custom/gateway deployment ID — aborts the run non-interactively with the exact
  argument to pass, instead of silently assuming the newest version. The report's
  tier-transparency line names the resolved target.
- **`audit-instructions`: report-header cost line** — checks run per surface, model-scoped rows
  skipped for the target, estimated per-surface token delta versus the prior catalog version, and
  confirmation that the run adds zero new interactive gates (report-only contract unchanged).
- **`instruction-scan.sh`: I8 candidate families with per-family ids** (`I8-a` instructed
  self-check, `I8-b` conservative-reporting, `I8-c` don't-think / don't-reason), with regression
  tests, curly-apostrophe (U+2019) coverage in the contraction patterns (also retrofitted to the
  pre-existing I6 tokens), and stem forms that catch inflections. Advisory over-production is
  unchanged and deliberate: restraint clauses, quoted/meta text, idioms, and substring near-misses
  are emitted as candidates; the fences live in criteria.md and are adjudicated by the model lane.

## [0.14.0]

### Added

- **"Scope of a Read deny" in `audit`'s `reference/required-permissions.md`.** The
  `sensitive-file-deny` table recommended `Read(./.env)` / `Read(./secrets/**)` /
  `Read(./.claude/settings.local.json)` with no statement of what a `Read` deny actually reaches, so a
  reader came away believing the file was protected. The new subsection splits covered from not
  covered against current official docs: the rule reaches the built-in file tools (Read, Grep, Glob,
  LSP), `@file` mentions, IDE selection context, Edit on the same path, **and the file commands Claude
  Code recognizes inside a Bash command such as `cat`, `head`, `tail`, and `sed`** — but *not* an
  arbitrary subprocess that opens the path itself, which is how a `python -c` or `node -e` one-liner
  reads a denied file with no deny firing. Remedies are ranked rather than listed: the sandbox
  (`sandbox.filesystem.denyRead`, `sandbox.credentials.files` with `"mode": "deny"`) is the documented
  OS-level enforcement path, carrying the platform limit that it does not run on native Windows; a
  `PreToolUse` hook on `Bash|PowerShell` is explicitly a speed bump, not a boundary, because it
  inspects the same evadable command string; and where no OS-level boundary exists the durable control
  is that the secret is not in a file the session's OS principal can read at all — directory location
  is explicitly named as *not* a boundary, since a subprocess opens absolute paths and relocation
  changes nothing about who can read the file. Enumerating shell readers as `Bash(cat *)`
  deny globs is named as a non-remedy, since upstream documents argument-constraining Bash patterns as
  fragile. Two facts are flagged unverified rather than asserted: whether PowerShell-tool reads
  (`Get-Content`, `type`) are covered at all, and the full membership of the recognized-command set,
  which upstream gives with "such as".
- **The sandbox's four escape surfaces, tabled alongside the recommendation.** `sandbox.enabled: true`
  on its own is not a boundary: `allowUnsandboxedCommands` lets a failing command be retried outside
  it, `failIfUnavailable` defaults to warning and running unsandboxed, `excludedCommands` runs listed
  commands outside and can always be appended to, and `filesystem.disabled` lifts the `denyRead` and
  `credentials.files` read protections outright. All four are open at their defaults, so an
  enabled-but-default sandbox is reported as partial — recommending it without them would repeat the
  defect this release fixes.
- **`check-structure.sh` now separates unreadable from malformed.** A `Read` deny merged into a
  sandbox boundary, or plain filesystem permissions, makes the script's `open()` fail; it previously
  surfaced as `Valid JSON: no` and failed the run, i.e. a false malformed-config finding. The script
  now reports `Present: yes` / `Readable: no` with a `not inspectable` note and exits cleanly, and
  both `SKILL.md` Phase 1 and `context/procedures.md` say that is a correct result to record rather
  than a reason to find another reader. Covered by a new test case that announces a skip where the
  platform does not enforce `chmod 000`.
- **Eval 7 on the `audit` skill (`read-deny-scope-not-overstated`).** Asks whether present deny
  patterns mean the secrets are protected; expects the scope split, the ranked remedies, and no
  `Bash(cat *)` enumeration.

### Changed

- **Category B now reports the secret-file Read denies with their scope.** `SKILL.md`'s "Required
  permission patterns" section routes the finding write-up through the new subsection, in both
  directions — a present baseline is not reported as proof the file is unreachable.
- **`context/procedures.md` no longer implies its own `settings.local.json` recipes escape the
  baseline deny.** It now states that the safety is in what gets emitted, not what gets opened:
  `check-structure.sh` reads the file from a subprocess and is safe because it emits counts only,
  while the supplemental `cat … | jq` recipes are blocked in a project carrying the recommended deny —
  correctly so. Routing around that block with an interpreter one-liner is prohibited; the audit
  reports the file as not inspectable under the project's own rule instead.
- **"Interaction with hook-based gates" now states the ordering in both directions.** "A deny rule
  fires before any `PreToolUse` hook" was true only of the loosening direction, and the two hook cases
  are now kept apart. A *returned decision* cannot loosen a rule: deny and ask rules are evaluated
  regardless of which decision the hook returns. *Exit 2* short-circuits instead: it stops the call
  before permission rules are evaluated at all, so it blocks past an allow rule and nothing downstream
  runs, including an otherwise-matching ask rule. The consequence for this baseline — a deny entry
  suppressing a project hook's ask escalation — is unchanged.

## [0.13.0]

### Added

- **A read-only inventory tier in `audit-instructions` Phase A.** I15 (shipped in 0.12.0) compares
  a *pair* of surfaces, so it has to read text no proposal may ever touch. Phase A now inventories
  three such tiers read-only rather than excluding them outright: org-managed policy (the managed
  `CLAUDE.md`, a `claudeMd` settings value, and managed prompt-type hook text), upstream-owned but
  live instruction text (skill bodies and agent definitions from an enabled plugin's cache, managed
  materializations, and `type: "prompt"` handler text in an enabled plugin's `hooks/hooks.json` —
  effective `enabledPlugins` gates all three alike, since a disabled plugin's cache stays on disk
  while none of its components load, and the selected install record, not merely an enabled plugin's
  presence in the cache, picks which version's directory is read), and every out-of-scope conflict
  counterpart. A scope argument narrows which side may *produce* a finding, never which surfaces are
  read, and the `Arguments` section now says so rather than describing the filter as narrowing the
  inventory. Read-only inventory changes no ownership: those surfaces still propose nothing and still
  route upstream. Prompt-hook text is extracted from `.claude/settings.local.json` and managed
  settings as well as project and user `settings.json`, prompt text only, never a command line or
  secret-bearing value.
- **A no-change representation in the `audit-instructions` report contract.** A finding whose check
  forbids proposing an edit — the I15 managed-policy case, anything routed to an owning repository —
  records `no change proposed` and who owns the resolution instead of a fenced diff, so the per-finding
  diff requirement no longer contradicts the checks that forbid an edit.
- **`audit-instructions` check I16 — definition-site locality.** An instruction governing one named
  thing while living somewhere other than that thing's own definition. A different axis from I3:
  I3 is load *timing*, I16 is *locality*, and an instruction can be correctly deferred and still
  misplaced. `OPINION`-tier, off by default, enabled by `--opinion`, capped at `info`, never applied.
  The destination is constrained to a surface Claude loads: where the subject's definition site is an
  ordinary README or reference file, the proposal colocates the text *and* retains a one-line pointer
  on a loaded surface, so a locality fix never silently drops the behavior the instruction enforced.
- **`audit-instructions` stopping condition on I6 and I8.** Neither carried an a-priori bound, so
  both trimmed without a floor. It withholds a proposal where the instruction guards a
  high-consequence area (safety gate, irreversible action, security boundary, external contract,
  genuine ordering) and reports every withholding. `OPINION`-tier but **enabled by default** with an
  explicit `--no-stopping-condition` opt-out, because it withholds rather than emits — defaulting a
  suppressor off would delete the only bound on two trimming checks.
- **`OPINION`-tier enablement policy in the catalog.** Emitting rules default off, `info`-capped,
  never fix-applied; withholding rules default on; `OPINION`-derived advice inside a backed check
  follows its host's enablement and is labelled inline. Every run reports how many `OPINION` checks
  were available, how many did not run, and the argument that enables them.
- **YAML frontmatter on `reference/criteria.md`** carrying `version` (1.2.0) and `last-updated`,
  replacing the body-prose version line — a contract surface with three parse paths now stamps its
  version machine-readably.

### Changed

- **`audit-instructions` I3 detection now names its real criterion — loaded more broadly than the
  content is relevant.** The old wording said "always-loaded surface", but none of the non-memory
  surfaces this check runs on are literally always loaded: a skill body or agent definition loads in
  full on every use of its component. The second detect case covers exactly that, and requires
  establishing the component's breadth first — a skill or agent that exists only for the content's
  concern loads it precisely when it is relevant and is not a finding.
- **`audit-instructions` I3 remediation now qualifies its destination and prices the move.** A
  destination qualifies only if it defers loading, so `@path` imports do not — a split into imports
  satisfied the check's letter while changing the load profile not at all. A finding must also state
  that a `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file
  is read again. A move into a **new** skill is priced too: the body defers, but the listing entry it
  adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536 characters — is
  always in context, so "move it to a skill" moves part of the cost into the always-loaded tier
  rather than out of it. A move into a skill that already exists adds no entry and is not charged.
  `disable-model-invocation: true` is the only field that keeps a description out of context, and it
  makes the skill user-invocable only; `skillOverrides` does not reach plugin skills. Stated as a
  cost on the recommendation, never as a budget threshold.
- **`audit-instructions` I9 remediation names the interface destination.** Where an example block
  exists to enumerate what a caller may pass, the finding names an argument enumeration, a
  frontmatter field, or a typed `argument-hint` instead. `OPINION`-derived, labelled as such in the
  finding, never fix-applied; the detection is unchanged and stays officially backed.
- **`Authority` gloss no longer asserts that every row is `ANTHROPIC-DOCS`.** The two
  `OPINION`-tier rules this release adds are the first that are not; the axis stays a closed
  three-value set.
- **I3 remediation refuses a `paths:`-scoped rule for content taken out of an agent definition.**
  Path-scoped content is invisible inside a subagent context, so that destination removed the
  instructions from every dispatch instead of deferring them. Agent-originated content now needs an
  agent-reachable destination — a skill the definition invokes, or text kept where it is.

### Fixed

- **The conflict pass resolves effective liveness before it pairs anything.** It received Phase A's
  filesystem inventory and treated presence in the tree as liveness, but liveness is a session
  property: the launch directory decides which ancestor `CLAUDE.md` files are candidates,
  `claudeMdExcludes` (merged across every settings layer) can kill one that is present, omitting
  `project` from `--setting-sources` skips project rules entirely, and `--add-dir` with
  `CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD` adds live memory files the tree walk never sees.
  Uncorrected, the pass reported conflicts one side of which was dead and missed live counterparts
  it never inventoried — silently, and reproducibly only on the machine that produced them. Phase A
  now resolves those controls and reports them in the tier-transparency line; surfaces whose
  liveness an out-of-session inventory cannot determine are marked `liveness-unresolved` and their
  pairs are reported rather than graded.
- **A prompt hook enters the comparison set as the gate it imposes, never as its prose.** Per
  [hooks](https://code.claude.com/docs/en/hooks), a `type: "prompt"` handler sends its text to a
  separate Claude model for single-turn evaluation returning a yes/no decision — it is never
  injected into the main conversation. Comparing that raw prompt against a `CLAUDE.md`, skill, or
  output style manufactured conflicts between two models that satisfy their own instructions
  independently (an evaluator told to return JSON only against a main-session Markdown-output rule).
  The pass now compares the act the hook blocks, under its event and `matcher`. This also closes the
  `UNVERIFIED` residency row that told the reader to fetch the hooks page.
- **Auto memory and a plugin-supplied active output style join the read-only inventory.** Both are
  resident every session and neither was reachable: auto memory was excluded outright for routing,
  yet `conflict-criteria.md` assigns every pair involving it to I15 *because* `claude-memory`'s C6
  does not read `MEMORY.md` — so the pair was audited by neither skill. And the user- and
  project-scope output-style scans cannot reach the plugin cache, while a plugin style with
  `force-for-plugin` applies "automatically whenever the plugin is enabled, without requiring users
  to select it", overriding the user's `outputStyle`
  ([output-styles](https://code.claude.com/docs/en/output-styles)) — so the *active* style could be
  absent from the corpus entirely. Phase A now inventories the loaded part of `MEMORY.md` at the
  effective auto-memory location and the one style that resolves active, both read-only, with
  ownership and routing unchanged.
- **Auto memory's enabled state is resolved by precedence, not by any one scope.**
  `CLAUDE_CODE_DISABLE_AUTO_MEMORY` is authoritative wherever it is set (`=1` off, `=0` on, even
  against `autoMemoryEnabled: false`); with it unset, settings precedence (managed > local > project
  > user) decides, defaulting to on. Reading a lower-scope `false` as decisive would have dropped a
  `MEMORY.md` that a higher-precedence scope re-enabled. `/claude-memory:stateless` owns the
  resolver and reports the effective state, including a variable/setting disagreement.
- **An agent definition no longer pairs against the main conversation's auto memory.** The residency
  table listed `MEMORY.md` as resident every session and made every agent-definition pair guaranteed,
  but "the main conversation's auto memory isn't loaded into subagents; the exception is a fork"
  ([memory](https://code.claude.com/docs/en/memory)) — so those two never occupy one context and the
  pass was reporting conflicts between contexts that do not coexist. The row, the guaranteed-pairs
  set, and the co-residency prose now carry the exception, while keeping the two pairs that are real:
  a fork inherits the parent, and a subagent that enables its own `memory` field can contradict the
  definition it runs under.
- **The plugin-source known limit no longer contradicts the read-only tier.** It said Phase A "never
  reaches `plugins/`" and that agent-versus-memory pairs have no second side, which the new tier
  makes false for every *installed, enabled* plugin — two executable instructions disagreeing about
  whether the same data is available. The limit is narrowed to what is still true: a marketplace
  repository's `plugins/**` **authoring** tree is plugin source, not an installed plugin, and nothing
  there loads into the session being audited, so pairs drawn wholly from it (a skill's stated default
  against its own plugin README) still have no counterpart and stay with #1421. The
  tier-transparency line reports that narrower limit only — reporting installed-plugin surfaces as
  uncovered would understate the coverage the pass now has.
- **Auto memory is inventoried only when it is effectively on.** It is on by default, but
  `autoMemoryEnabled: false` at any settings scope or `CLAUDE_CODE_DISABLE_AUTO_MEMORY=1` turns it
  off, and a `MEMORY.md` left on disk from before is then neither loaded nor written. Phase A
  resolves that state before inventorying the file — the same gate the plugin-cache surfaces already
  carry, and for the same reason: pairing live instructions against text no session sees is a
  manufactured finding.
- **Eval 8 required naming a winner for a pair the precedence table calls unresolved.** It asked the
  run to "say which side to change" for a skill body against a `CLAUDE.md`, which
  `conflict-criteria.md` classifies as unresolved because the skills page states no authority
  relation between the two and "silence is not a winner". The eval now requires an `unresolved`
  verdict with both anchors quoted and the choice left to the operator, with the mechanism route
  offered as an option rather than a verdict.
- **Eval 7 required dropping a real contradiction when `claude-memory` is absent.** It expected the
  run to report memory-layer contradictions as unchecked and name the sibling skill, but
  `conflict-criteria.md`'s fallback contract keeps the pair as an I15 finding when that plugin is not
  installed. The routing exists to avoid two findings for one pair, not to lose the only one; the
  eval now requires the fallback.
- **Eval 13 required the wrong reason for refusing an agent-definition import split.** It rewarded
  saying that an `@path` in an agent definition loads at launch, which the catalog's own I13 says is
  false — `@` carries no import meaning outside the memory-layer surfaces, so the referenced file
  would not load at all. The eval now requires that explanation, which is what makes the split a
  silent removal rather than a failed saving.
- **`audit-permission-grants` no longer points outside the plugin root.** Both `SKILL.md` and
  `reference/criteria.md` reached the permission-rule-hygiene convention through a `../` relative
  link. An installed plugin runs from an isolated cache holding only the plugin's own tree, so the
  link normalized above the cache root and resolved to nothing — the skill directed a read that
  cannot succeed in installed form, while resolving fine in a full-repo checkout, which is why it
  survived. Both now point at the convention's published URL, the form sibling plugins already use
  for marketplace conventions. Nothing was copied into the plugin: the convention stays the single
  owner of the principle, the three anti-patterns, and the correct pattern. What a run actually needs
  was already in-plugin — each check's **Recommend** line — and both files now say so, so a report
  never depends on fetching anything.

## [0.12.0]

### Added

- **`audit-pass` skill** (`/claude-config:audit-pass`). One coordinated, ordered, resumable pass over
  a named target repository's instruction surface. It defines no criteria: every check is delegated
  to the plugin that owns it through a presence-gated namespaced invocation with a documented
  fallback, and nothing crosses a plugin boundary but that invocation. What it adds is the run
  semantics — a three-scope inventory (managed policy read-only, user scope routed as
  recommendations, project scope) taken before any check runs; an exclusion set derived at run time
  from the target's own shared-source registry, the `vendor/` layout rule, `git worktree list`, and
  the pass's own artifacts, never transcribed; content-derived finding identity; a constituent-keyed
  suppression record whose entries resolve through a four-way disposition table in which only an exact
  match is silent — a one-sided anchor change carries forward as `needs-reconfirmation`, a deeper
  change closes the old entry and opens the new finding, and every disappeared finding is accounted
  for as a fix, a successor, or an unexplained disappearance that fails the self-check, which is the
  detector the convergence property previously lacked; per-lane incremental persistence with resume;
  and one human gate per run. Liveness is read from two ground-truth sources — `InstructionsLoaded`
  for the memory layer and `/context` for Skills, Custom Agents, and MCP Tools — because either alone
  under-covers the surface set silently; `managed-settings.json`'s `claudeMd` key is observed by
  neither and is reported as a known gap. Read-only on bare invocation, mutation only behind `--fix`, and never an edit
  to managed policy or a user-scope file. `/doctor` is an operator handoff rather than a dispatch,
  because it is interactive; when its three-part prerequisite or v2.1.206 version floor is unmet the
  run names it as the missing capability and states what goes unchecked. Findings report in three
  tiers — derived (exact equality across runs), judged (a stability tolerance whose violation fails
  the run's self-check), delegated (no property) — and every run reports in one line how many
  `OPINION`-tier checks were available, were not run, and the argument that enables them. The
  determinism gate **measures its own precondition** rather than assuming it: HEAD and a **state
  digest** — every inventoried surface and every dirty path, each paired with the content hash of its
  current bytes — are captured at the **scan baseline** (Phase 1's inventory frozen, before any lane
  reads, since the digest spans that inventory and is not computable before it exists) and again at
  the **audit endpoint**, and a target that
  moved mid-run reports `indeterminate` rather than `passed`, with the properties marked not
  evaluated. Three things the naive form gets wrong, all closed here: a *count* holds still while an
  already-dirty file's contents change, so the digest pairs each path with its content; the digest
  spans **every inventoried scope**, because a `~/.claude/CLAUDE.md` edit moves what the lanes read
  while the target's HEAD and dirty set both hold still, and reporting that as a defect would be an
  accusation where an abstention is correct; and the endpoint is captured **before** Phase 5, so a
  `--fix` run's own accepted edits fall outside the measured read window instead of marking every
  successful mutating run `indeterminate`. The pass's own artifacts are excluded from the digest on
  the same list that excludes them from the scan, so a `--report-to` write does not invalidate the
  run's own gate. A checkout shared with concurrent sessions is the normal case for the first
  operator, and an unfalsifiable pass is worse than an honest indeterminate.
- **Finding-suppression convention** (`docs/conventions/finding-suppression/`). Owner doc for the
  suppression record `audit-pass` reads at `.claude/audit-pass.md`: entries store the finding's
  constituents — `check`, `claim`, and every `(surface, anchor)` site — under a derived `finding_id`
  key, with the constituents authoritative and a key that does not hash from its own body reported
  malformed. Also the required reason and date, per-key merge (never a closed list, which one personal
  entry would discard whole), the policy-floor precedence inversion where the team layer wins a
  conflict, and the five obligations on any consuming skill. Layering defers to the config-cascade
  contract.

### Changed

- **`setup` now covers a consumer-project configuration surface.** `audit-pass`'s tracked suppression
  record makes the plugin's previous "owns no consumer-project configuration" claim false, so `check`
  gains per-layer verification of the record (user-global INFO, team must be tracked, overlay must be
  gitignored) plus malformed-entry reporting, and `apply` gains its one write path.

## [0.11.0]

### Added

- **`audit-instructions` check I15 and Phase B2: cross-surface conflict pass.** Detects two
  instruction surfaces that both claim authority over one behavior and contradict each other — a unit
  of judgment the per-surface Phase B lanes are structurally blind to, since each lane sees only one
  half of a pair. The catalog row owns the definition, comparison set, `@path`/symlink resolution,
  `AGENTS.md` exclusion, remediation-by-scope and must-not-flag cases; Phase B2 answers it. The pass
  consumes Phase A's inventory rather than re-enumerating surfaces, and reads surfaces Phase A
  recorded as *skipped* (plugin-cache, managed materializations, org policy) as read-only conflict
  participants, since a contradiction is real whether or not this repo may edit either side.
- **`reference/conflict-criteria.md`.** The five gates a pair must clear (co-residency, same
  observable, opposed polarity, no arbitration, non-vacuous trigger overlap), three conflict types
  and their remediation routes, a residency table covering every surface Phase A inventories, a
  precedence table separating what the official docs settle from what they leave unresolved, a
  13-case must-not-flag set, and two worked examples. **Split-brain is not a fourth type**: two files
  where only one ever loads fails the co-residency gate by construction, so listing it as a conflict
  type would make it unreachable. It is reported separately as *orphaned instruction drift* — the
  state a contradiction grows out of, not a contradiction today.
- **A boundary against `claude-memory:audit`'s C6 consistency check drawn on C6's actual population,
  not on the name of the layer.** C6 discovers files project-relative (`find . -maxdepth 1` over
  `CLAUDE.md`/`CLAUDE.local.md`, plus `find .claude/rules`) and its check text names only those
  files. So only a pair with **both halves in root-level project** `CLAUDE.md` / `CLAUDE.local.md` /
  `.claude/rules/**` routes to C6. Any pair with a `~/.claude/` side, any pair involving auto-memory
  `MEMORY.md`, and any pair reaching a **nested** `CLAUDE.md` / `CLAUDE.local.md` stays with this
  pass — C6 discovers with `find . -maxdepth 1` and never reads the nested files, so routing those
  out on a layer label would have left them audited by neither skill.
- **`scripts/conflict-scan.sh` + tests.** Advisory deterministic pre-scan emitting
  `fileA:lineA|fileB:lineB|entity|flags` candidate pairs, always exit 0, matching the existing
  `instruction-scan.sh` contract. An entity is a CamelCase identifier anywhere **or a single
  capitalized word inside backticks** — the second form is what reaches single-word tools (`Bash`,
  `Read`, `Edit`), and requiring the backticks is what keeps sentence-initial capitalized words out.
  Neither form is a hardcoded tool list, so a tool the scan has never heard of is still covered.
  Polarity is read from a window around each mention and **both halves of that window stop at a
  sentence boundary**, so only a polarity token in the entity's own sentence classifies it:
  `X must not be used` is a prohibition, a trailing clause past a full stop is not, and a prohibition
  in the *preceding* sentence no longer overrides the mandate that governs the entity. A boundary is
  a sentence-ending mark followed by a space — a bare mark also occurs inside a dotted config path or
  a version number — or a contrastive conjunction with or without a preceding comma, so "always use
  `Read` but never use `Bash`" classifies each entity on its own clause rather than sharing one
  polarity. `while` still requires its comma, being temporal as often as contrastive. An
  opt-in gate suppresses a pair only when it reads as a **condition** rather than as the subject, so
  "never use `X` for opt-in prompts" is still classified. Classification and pairing run in a single
  `awk` pass bucketed by entity; a subprocess per mention did not finish on an instruction tree this
  size.
- **`conflicts` scope argument.** Runs Phase A plus Phase B2 only, so a scheduled hygiene routine can
  compose the conflict check on its own token budget without paying for the full audit.

### Changed

- `audit-instructions` reports conflicts as **pairs** in their own report subsection — both
  `path:line` anchors, both claims quoted verbatim, and either a doc-cited precedence winner or an
  explicit `unresolved`. The skill never picks a winner the official docs do not state.

## [0.10.0]

### Added

- **`audit-instructions` checks I12–I14**, extending the existing `reference/criteria.md` catalog
  rather than standing up a second one. Each row carries its must-not-flag cases, and the three new
  official sources (CLI reference, subagents, skills) join the catalog's source list.
- **I12 — stale or misattributed harness-capability claim.** The subject is the product, not the
  model, which separates it from I8. Detection needs an official page stating something incompatible
  with the claim, or a failed reproduction — and each arm is bounded so the check cannot manufacture
  findings. **Documentation silence is not drift**: pages are rewritten and condensed, and this
  repository keeps empirical tests for behaviors the docs never specified. **A reproduction must
  match every stated precondition** — version, OS, setting, account tier, feature flag, launch mode —
  and a failure without them is inconclusive rather than a finding.
- **I13 — prose written on the assumption that an `@path` imported**, on a surface where `@` carries
  no import meaning. The finding is the false premise, not the citation form: an inert `@path` is
  still a legible path, so "follow `@reference/rules.md`" works and flagging it would report a
  working instruction. Remediation rewrites the assertion into an explicit read, because swapping the
  syntax alone leaves the claim false — no citation form imports anything on these surfaces.
- **I14 — an instruction to read a surface the main conversation already loads at startup.** Bounded
  to the root `CLAUDE.md`, the user `CLAUDE.md` at the **resolved** `${CLAUDE_CONFIG_DIR:-~/.claude}`,
  the root `CLAUDE.local.md`, unconditional project rules and managed policy files. Nested
  `CLAUDE.md` and `CLAUDE.local.md` files and path-scoped rules load lazily and are exempt, as is any
  read where **the file is the operation's subject** — the startup copy is a launch-time snapshot, so

### Changed

- **Recheck triggers now watch every page in the catalog's source list**, not the three originally
  named. Each check cites one of those pages, so a subset left the new harness-behavior rows
  depending on pages nothing watched.
- **The surface partition no longer widens a row.** It said the full catalog applies on non-memory
  surfaces while I13 and I14 declare narrower surface sets, so a lane could emit I14 findings on
  prompt-type hooks and output styles the criterion excludes. Each row's own declaration bounds it.
- **The `description` carries the new checks' trigger vocabulary.** It framed the skill purely as
  finding instructions the model no longer needs, and only the description is available during skill
  selection — so a request about a stale harness claim, a non-loading `@path`, or a redundant
  startup-surface read would not have selected the catalog that answers it.
- **`Authority` gloss restated descriptively.** The axis is a closed three-value set, not a rule
  that every row is `ANTHROPIC-DOCS` — `TALK` and `OPINION` stay reachable, and the two
  `OPINION`-tier rules this release adds are the first to use one.

## [0.9.3]

### Added

- **`setup` evals.** The skill shipped none, against the repo's own rule that a skill carrying
  behavioral warrants demonstrates them. Four cases cover the behaviors its SKILL.md asserts and
  nothing else: a bare invocation routes to `check` and writes nothing; a missing `curl` FAILs
  scoped to `check-plugin-drift.sh` alone rather than downgrading the rest of the audit surface;
  an install request under `apply` yields platform instructions without executing a package
  manager, and never reports a prerequisite resolved on an install command's exit code; and an
  audit request under `setup` routes to the audit skills by name instead of being performed.

## [0.9.2]

### Changed

- Fresh-eyes delegation sites now prefer a cross-vendor advisor when one is installed
  (e.g. the OpenAI Codex plugin, invoked per its own docs), with the fresh-context same-vendor
  subagent as the stated fallback — presence-gated per the seam-phrasing convention.

## [0.9.1]

### Added

- **`audit-instructions` eval: `step-list-culled-not-preserved`.** Exercises check I8's
  step-list nuance: a mechanical numbered procedure is culled to intent plus hard constraints
  (genuine ordering, safety gates, external contracts kept) rather than preserved verbatim.
  Absorbed from the superseded `audit-model-fit` suite (its C2 analog), per the follow-up
  material recorded when 0.9.0 removed that skill.

## [0.9.0]

### Added

- **`audit-instructions` skill** (`/claude-config:audit-instructions`). A read-only audit of the
  locally-owned Claude Code instruction surfaces — user + project `CLAUDE.md`, `.claude/rules`,
  skill bodies, agent definitions, prompt-type hooks, output styles — for instructions current
  models no longer need: prior-model workarounds, over-prescriptive scaffolding, bare prohibitions,
  reasoning-echo directives, and approach-pinning example blocks. It ships an eleven-check catalog
  (`reference/criteria.md`) cited to current official prompting doctrine, tiers every finding
  mechanical vs behavioral, and packages proposed removals/rewrites as human-gated diffs — never
  auto-applied. An advisory grep-only scanner (`scripts/instruction-scan.sh`) seeds the mechanical
  tier. It partitions with `claude-memory`'s `audit` skill: on memory-layer surfaces it runs only
  the model-era checks and routes hygiene findings there; on non-memory surfaces the full catalog
  applies. Upstream-owned plugin-cache and managed-materialization findings route to the owning
  repository rather than being edited in place.

### Fixed

- Corrected stale `claude-memory` skill-name references (`health` → its current name `audit`)
  across the plugin's skills and README — the `audit`, `audit-automation-gaps`, and
  `audit-permission-grants` route-out notes and the README's instruction-layer and migration
  sections. The `claude-memory` memory-layer skill was renamed `health` → `audit`; the old
  `/claude-memory:health` invocation no longer resolves.

### Removed

- **`audit-model-fit` skill superseded by `audit-instructions`.** Both audits answer the same
  question — locally-owned instruction surfaces vs current model capability — and repo doctrine
  admits only one skill per question. `audit-instructions` carries the fuller catalog (eleven checks
  I1–I11 with authority tags and evidence tiers), the `claude-memory` hygiene partition, and the
  adversarial fresh-context verify pass, so it strictly covers `audit-model-fit`'s four checks and
  supersedes it. Both were built concurrently from the same underlying issue (#800); `audit-model-fit`
  (added in 0.8.0 below) is removed here.

## [0.8.1]

### Changed

- Skills with `!` dynamic-context injections now declare `shell: bash` explicitly, per
  the pinned precompute convention — bash-only pipelines must not fall through to a
  PowerShell host.

## [0.8.0]

### Added

- **`audit-model-fit` skill** (`/claude-config:audit-model-fit`). A fourth audit that sweeps the local
  Claude Code instruction surfaces — user + project `CLAUDE.md`, skill `SKILL.md` bodies + context
  files, agent definitions, `.claude/rules/**`, prompt-type hooks and output styles — for deterministic
  constraints that hobble newer, more capable models, and proposes removals/rewrites. Check catalog:
  bare prohibitions with no rationale (rewrite to add the *why*, never blanket-delete), over-prescriptive
  step lists (cull to intent + hard constraints), over-constraining example blocks (trim toward the
  recommended 3–5, not a blanket ban), and stale model-era workarounds — each measured against "would
  removing this cause Claude to make mistakes?". A bundled `instruction-surface-scan.sh` enumerates the
  surfaces and flags the two grep-able smells as candidates; the judgment stays in the skill body.
  **Report-only and human-gated**: it presents findings plus proposed diffs and never edits any
  instruction file itself (no `--fix`). Findings inside `melodic-software/standards`-managed
  materializations route upstream per the sync-manifest rather than being edited in place. Composes with
  (distinct intents, pointers only) `claude-memory:audit` (instruction-layer *health*, same surfaces),
  `skill-quality:check` (structure), `docs-hygiene:compress` (token brevity), and the sibling `audit`
  (config-file correctness). The plugin `description` now reads "Four audit skills".

## [0.7.1]

### Changed

- Documentation-only: the License section now states the plugin's own MIT
  license inline and no longer points at a `LICENSE` file at the repository
  root, which an installed consumer running from the isolated plugin cache
  cannot reach. No behavior change.

## [0.7.0]

### Changed

- **BREAKING — two skills renamed to the `audit-*` naming grammar** (fleet conformance wave, naming
  grammar): `automation-gaps` → `audit-automation-gaps` (`/claude-config:automation-gaps` →
  `/claude-config:audit-automation-gaps`) and `permission-hygiene` → `audit-permission-grants`
  (`/claude-config:permission-hygiene` → `/claude-config:audit-permission-grants`). The old
  invocations stop resolving; update any saved references. The `audit` skill is unchanged.

## [0.6.0]

### Added

- **`setup` skill on the uniform contract** (`/claude-config:setup`). Closes the doctrine-tracked
  setup gap: the plugin's audit scripts require external CLIs (`jq` for all three skills, `curl` for
  the plugin-drift check) but no setup shipped. `check` (default, read-only) probes `jq`/`curl`/the
  bash shell against the bundled scripts as source of truth and reports PASS/FAIL/INFO — `jq` missing
  is a plugin-wide FAIL, `curl` missing a scoped FAIL for the drift check only. `apply` gives platform
  install guidance and re-verifies; it installs no system package and writes nothing. README
  Requirements now names the bash/Git-Bash shell prerequisite alongside `jq`/`curl`.

## [0.5.0]

### Changed

- Renamed the plugin `claude-config-audit` → `claude-config`. Reinstall as
  `claude-config@melodic-software` and update any `/claude-config-audit:*` invocations to the
  `/claude-config:*` namespace.
- Renamed the `settings-audit` skill → `audit` (`/claude-config:audit`) and the
  `automation-deep-dive` skill → `automation-gaps` (`/claude-config:automation-gaps`).
  `permission-hygiene` keeps its name (now `/claude-config:permission-hygiene`).

### Removed

- Extracted the `memory-health` skill into the new standalone `claude-memory` plugin, where it ships as
  the `health` skill (`/claude-memory:health`). Install `claude-memory@melodic-software` for the
  instruction/memory-layer audit.

## [0.4.0]

### Added

- "Pre-computed context" blocks in the `automation-deep-dive`, `memory-health`, and `settings-audit`
  skills: `!`-executed commands inject live repo facts (automation inventory; memory/rules/CLAUDE.md
  counts and the RD1/M2 script-backed check counts; installed Claude Code version) at skill load, so
  each audit starts from guaranteed-fresh evidence instead of relying on the model to remember to run
  the bundled scripts. Every command carries an `|| echo` fallback so skill load never hard-fails.
  No `allowed-tools` self-grant ships with the blocks: a `Bash(bash <path>*)` grant is the
  interpreter-led P1 shape this plugin's own `permission-hygiene` criteria flag (auto mode drops it),
  and `!`-execution does not route through `allowed-tools`.

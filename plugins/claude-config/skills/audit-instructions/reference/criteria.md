---
version: 1.17.0
last-updated: 2026-08-08
---

# Instruction-Audit Criteria

The checks the `audit-instructions` skill runs, seeded from current official prompting doctrine.
Each check carries an evidence tier, an authority tag, a default severity, its surface
applicability, and one decisive source line (point-don't-copy — the full doctrine lives at the
cited URL, not restated here).

**Recheck triggers** — treat these as staleness signals and re-verify the catalog against live
docs when any fires: a new frontier model release; **a change to any page listed under Sources
below**. Every check cites one of those pages, so the trigger set is the source set — naming a
subset would leave the harness-behavior rows depending on pages nothing watches. One staleness event
fires the whole catalog, not the check that noticed it. Model-specific pages — the per-model
prompting guides under Sources — are superseded on each model generation.

**Per-row verification stamps.** A row that restates a volatile upstream *literal* — a level name, a
model range, a type predicate — additionally carries the four-part record that claim needs: the
claim, its basis, an as-of date, and a recheck trigger naming an observable event (the shape is
`docs/conventions/upstream-drift/README.md` in this monorepo; in a standalone install the four
parts, not the path, are the requirement). A row that restates nothing and only points at its page
carries no stamp, because a pointer cannot go stale.

A per-row stamp **supplements** the catalog-wide trigger above; it never replaces or narrows it.
The catalog trigger still fires every row on any Sources change — that is why a row's own trigger
names only the events the Sources set would *miss*, such as a value set changing while its page
keeps the same URL. **Where the two disagree, the catalog trigger wins**, because it is the wider
one and a staleness signal is not something to resolve by picking the narrower authority.

The requirement **binds on touch**, per the convention above: rows predating this rule keep their
citations as they are and adopt the four parts the next time they change. A missing stamp on an
older row is therefore not itself a defect in this catalog.

**Axes.** Three orthogonal axes, never conflated:

- **Evidence tier** — `mechanical` (pattern-detectable by static reading) or `behavioral` (ground
  truth is observed model behavior, so findings ship as proposals verified by the delete-and-watch
  loop, never confident removals).
- **Authority** — `ANTHROPIC-DOCS` (official documentation), `TALK` (a recorded talk), `OPINION`
  (a practitioner's stated practice). A closed three-value set.
- **Severity** — `error` / `warning` / `info`.

**Model scoping.** A check or row sourced from a SINGLE model's guide is annotated
`Model scope: <version>` and FIRES only when the run's resolved target model (the skill body owns
`--target-model` resolution) matches that scope; otherwise it is inert and the report lists it as
`skipped-for-target`. **The match is exact string equality of the normalized version token**
(e.g. `opus-5`): a point release or a dated full model ID does NOT auto-match a base-version scope
— model guides are calibrated per version, and successive guides have reversed each other, so a
near-miss target skips the row (reported `skipped-for-target`, naming the near-miss) rather than
inheriting a sibling version's doctrine. The scope value is data — no check body branches on a
model name in prose. Promotion to fleet-wide (unscoped) happens only through the gate: an
authoritative model-agnostic upstream doc states the claim, OR multiple model guides converge on
it. Unannotated checks are model-agnostic and always fire.

**`OPINION` enablement.** Enablement attaches to *detection*, never to advice, and splits on what a
rule does:

- An `OPINION` check that **emits** findings is **off** on bare invocation, enabled only by the
  explicit `--opinion` argument, capped at `info`, and never fix-applied. An unconfirmed
  practitioner preference does not get to mutate a consumer's instruction corpus under the same
  banner as documented doctrine.
- An `OPINION` rule that **withholds** findings is **on** by default, disabled only by an explicit
  opt-out. Defaulting a suppressor off would not make the audit more conservative — it would delete
  the only bound on the checks it moderates.
- `OPINION`-derived *advice* inside a backed check's Remediate line follows that check's enablement
  and severity, because the detection is the host's and is backed. It is labelled inline as
  `OPINION`-derived and is never fix-applied.

Every run reports one line naming how many `OPINION`-tier checks were available, how many did not
run, and the argument that enables them — an off-by-default tier nobody can find is shipped in name
only.

**Surface partition.** Checks I1–I5 are the instruction-memory hygiene layer: they apply on
non-memory surfaces (skill bodies, agent definitions, hook instruction text, output styles); on
memory-layer surfaces (CLAUDE.md, CLAUDE.local.md, `.claude/rules/`, `~/.claude/rules/`) their
findings route to the `claude-memory` plugin's `audit` skill when it is installed, and fall back
to the official include/exclude guidance (I1–I5 source below) when it is not. Checks I6–I12 and
I15–I24 apply to all surfaces; I13 and I14 name narrower surface sets in their own rows.

## Sources

- Claude Code best practices — <https://code.claude.com/docs/en/best-practices>
- Prompting best practices —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices>
- Prompting Claude Fable 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-fable-5>
- Prompting Claude Opus 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-opus-5>
- Prompting Claude Sonnet 5 —
  <https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/prompting-claude-sonnet-5>
- The new rules of context engineering for Claude 5 generation models (vendor blog, published
  2026-07-24 — corroborates I6 from the model-delta side and I15 from the reasoning-cost side; a
  dated post, static once published, so a recheck is expected to find it unchanged; it corroborates
  rather than defines, so the rows citing it keep the `ANTHROPIC-DOCS` Authority of their primary
  documentation sources and the closed three-value Authority set above is unchanged) —
  <https://claude.com/blog/the-new-rules-of-context-engineering-for-claude-5-generation-models>
- Memory (CLAUDE.md, rules, auto memory) — <https://code.claude.com/docs/en/memory>
- The `.claude` directory — <https://code.claude.com/docs/en/claude-directory>
- Skills (what loads when, how supporting files are referenced, the listing budget,
  invocation-control fields) — <https://code.claude.com/docs/en/skills>
- How features layer (per-surface precedence, routing between surfaces) —
  <https://code.claude.com/docs/en/features-overview>
- Context window (what survives compaction) — <https://code.claude.com/docs/en/context-window>
- Hooks (handler types, and which events inject handler output into context) —
  <https://code.claude.com/docs/en/hooks>
- Refusals and fallback (`reasoning_extraction`, and the classifier-category set it belongs to) —
  <https://platform.claude.com/docs/en/build-with-claude/refusals-and-fallback>
- Introducing Claude Fable 5 and Claude Mythos 5 (which models carry the safety classifiers) —
  <https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5>
- Thinking (the sanctioned reasoning-visibility path, the `display` field, the thinking-block
  round-trip protocol, the models that reject a thinking-disable outright, and what a thinking or
  effort change does to the cache prefix) —
  <https://platform.claude.com/docs/en/build-with-claude/thinking>
- Steering thinking (the turn-validation relaxation, and the models that still enforce a leading
  thinking block) —
  <https://platform.claude.com/docs/en/build-with-claude/thinking-steering-and-cost>
- Troubleshooting thinking (the per-request 400s, the models the effort restriction covers, and the
  internal-tag leakage a don't-think directive worsens) —
  <https://platform.claude.com/docs/en/build-with-claude/thinking-troubleshooting>
- Model migration guide (the model ranges over which manual extended thinking is rejected) —
  <https://platform.claude.com/docs/en/about-claude/models/migration-guide>
- Effort (the levels, `high`'s equivalence to omitting the parameter, the carry-over sweep advice,
  and where thinking may not be disabled) —
  <https://platform.claude.com/docs/en/build-with-claude/effort>
- Model configuration (the harness-side thinking-display and thinking-disable surfaces, which effort
  levels each surface accepts, the per-model calibration of the effort scale, the first-run
  default hold, and the adaptive-reasoning / fixed-thinking-budget partition) —
  <https://code.claude.com/docs/en/model-config>
- Settings (the `effortLevel` value set) — <https://code.claude.com/docs/en/settings>
- Environment variables (`CLAUDE_CODE_EFFORT_LEVEL`, `MAX_THINKING_TOKENS`, and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` with the models and release it reaches) —
  <https://code.claude.com/docs/en/env-vars>
- Prompt caching (what belongs to the cache key) — <https://code.claude.com/docs/en/prompt-caching>
- CLI reference (`claude doctor` and the other terminal forms) —
  <https://code.claude.com/docs/en/cli-reference>
- Subagents (what loads into a subagent at startup) — <https://code.claude.com/docs/en/sub-agents>

---

### I1: Line-necessity bar

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a line whose removal would not change behavior — restates a default, a truism, or
  something the model already does correctly.
- **Remediate:** cut it, or (if it enforces something) convert per I5.
- **Source:** best-practices — "For each line, ask: *Would removing this cause Claude to make
  mistakes?* If not, cut it."

### I2: Length and skimmability

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** a surface long or dense enough that its own rules start getting ignored; the tell is
  the model breaking a rule the file contains.
- **Remediate:** prune, split into path-scoped rules or skills, tighten structure.
- **Source:** best-practices — "Bloated CLAUDE.md files cause Claude to ignore your actual
  instructions."

### I3: Broad-applicability placement

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** only-sometimes-relevant content (a workflow, domain knowledge, one subsystem's
  quirks) living in a surface that loads **more broadly than the content is relevant**. Two cases,
  because the surfaces this check runs on are not all always-loaded:
  - an always-loaded surface — the selected output style, an unscoped rule, root `CLAUDE.md` where
    the partition allows it;
  - a surface loaded in full on every use of a component whose own scope is broader than the
    content's — a skill body or an agent definition covering several concerns, where the content
    matters to one of them and is in context for all of the others. Establish that breadth before
    flagging: a skill or agent that exists *only* for the content's concern loads it exactly when it
    is relevant, and is not a finding.
- **Remediate:** move it to a skill or a path-scoped rule that loads on demand. **A destination
  qualifies only if it defers loading** — `@path` imports do not, so a split into imports is an
  organizational change and not a context saving, and proposing one satisfies this check's letter
  while changing the load profile not at all. **State the move cost with the recommendation:** a
  `paths:`-scoped rule or a nested `CLAUDE.md` is lost after compaction until a matching file is
  read again, so content that must survive compaction stays unscoped or in the project-root
  `CLAUDE.md`. **A *new* skill is not a free destination:** its body defers, but the listing entry it
  adds — `name` plus the combined `description` and `when_to_use`, truncated at 1,536 characters — is
  always in context, so the saving is the body minus that entry rather than the whole body. Moving
  content into a skill that **already exists** adds no listing entry and does not carry this cost.
  The only field that keeps a description out of context is `disable-model-invocation: true`, which
  also makes the skill user-invocable only; `user-invocable: false` does not, and `skillOverrides`
  does not reach plugin skills at all. State the entry as a cost, not a threshold — whether a corpus
  is over its listing budget is a different question and not this check's.
  **Content taken out of an agent definition needs an agent-reachable destination.** A subagent runs
  in its own context, and path-scoped rules are invisible there
  (<https://code.claude.com/docs/en/sub-agents>), so proposing one for instructions the agent needs
  removes them from every dispatch rather than deferring them. Name a destination the agent itself
  reaches — a skill the agent's definition invokes or preloads, or text kept in the definition — and
  never a `paths:`-scoped rule.
- **Adjacent axis:** this check is load *timing*. Definition-site *locality* — an instruction sitting
  away from the thing it governs — is I16, and an instruction can be correctly deferred here and
  still misplaced there.
- **Source:** best-practices — "only include things that apply broadly. For domain knowledge or
  workflows that are only relevant sometimes, use skills instead."; memory — "splitting into `@path`
  imports helps organization but doesn't reduce context, since imported files load at launch";
  context-window, "What survives compaction", for the per-destination cost; skills — "skill
  descriptions are loaded into context so Claude knows what's available, but full skill content only
  loads when invoked", the combined `description` and `when_to_use` text "is truncated at 1,536
  characters in the skill listing to reduce context usage", and "Plugin skills are not affected by
  `skillOverrides`."

### I4: Inferable or redundant content

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: I1–I5 partition.

- **Detect:** content the model can derive from the code, standard language conventions it already
  knows, inlined API docs that should be a link, or self-evident practices.
- **Remediate:** delete; link to the source of truth instead of inlining it.
- **Source:** best-practices include/exclude table — exclude "Anything Claude can figure out by
  reading code" and "Standard language conventions Claude already knows."

### I5: Rule-to-hook or delete

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: I1–I5 partition.

- **Detect:** a rule the model already follows without it, or one that must fire every time with
  zero exceptions.
- **Remediate:** delete the already-followed rule; convert the must-always rule to a hook, which is
  deterministic where an instruction is only advisory.
- **Source:** best-practices — "If Claude already does something correctly without the instruction,
  delete it or convert it to a hook."

### I6: Bare prohibition to positive reframing

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** a bare "never / do not / don't" instruction. The deterministic pre-scan marks
  candidate lines; a line already carrying a rationale marker is a weaker candidate.
- **Remediate:** reframe positively — state what to do instead — as the primary fix. Where a
  genuine hard "never" survives, keep it but add its rationale (see I7) as the fallback.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** prompting best-practices — "Tell Claude what to do instead of what not to do."
  Corroborated from the model-delta side at the context-engineering blog, under "Then and now" in
  the paired "Then: Give Claude rules" / "Now: Let Claude use judgement" headings: the bare
  prohibition "In code: default to writing no comments. Never write multi-paragraph docstrings or
  multi-line comment blocks — one short line max." was a guardrail for older models — "newer models
  have better judgement and can handle these decisions well without explicit rules" — and
  its shipped replacement is an instance of this row's remediation shape: "Write code that reads
  like the surrounding code: match its comment density, naming, and idiom."

### I7: Reason with the request

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all. Unscoped —
promotion gate MET: the model-agnostic best-practices page states the same claim (see Source),
so this fires for every target model.

- **Detect:** an instruction that states a request with no intent or motivation attached.
- **Remediate:** add the why — the model connects the task to relevant context instead of inferring
  intent on its own.
- **Source:** Fable 5 guide, "Give the reason, not only the request" — "Claude Fable 5 tends to
  perform better when it understands the intent behind a request." Convergent model-agnostic
  source (the gate-meeting one): Prompting best practices, "Add context to improve performance" —
  "Providing context or motivation behind your instructions, such as explaining to Claude why
  such behavior is important, can help Claude better understand your goals and deliver more
  targeted responses."

### I8: Model-era re-audit

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

The base row and rows I8-a, I8-c, I8-d and I8-e carry their own `Model scope` (single-model guide
sources; promotion gate unmet). Row I8-b is unscoped — two model guides converge on it (see the row).

**Base row** · Model scope: `fable-5`.

- **Detect:** prior-model workarounds and over-prescriptive step lists — instructions enumerating
  behaviors a current model handles from a brief instruction, or scaffolding that pins an approach.
  **One named worked instance, offered for recognition rather than as a separate rule: a delegation
  throttle** — a cap on concurrent workers, a one-at-a-time rule, or an instruction to block until
  each subagent returns before dispatching the next — where the surface's own ground for it is that
  subagent handling is unreliable. Current guidance runs the other way, asking for readier
  dispatch and asynchronous orchestrator-to-worker communication, so a throttle resting on that
  premise is the generic case with a name on it. **A cap carrying its own non-model rationale is
  not this instance** — reviewability of returns, rate limits, cost, or shared mutable state each
  justify a bound on their own terms, and that justification is the surface's to make, not this
  row's to override.
- **Remediate:** propose removal or a briefer instruction; verify via the delete-and-watch loop
  that default performance holds or improves.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Fable 5 guide — "Skills developed for prior models are often too prescriptive for
  Claude Fable 5 and can degrade output quality." The worked instance's basis is the same guide,
  "Parallel subagents" — "Claude Fable 5 dispatches parallel subagents more readily than prior
  models. Use subagents frequently … and prefer asynchronous communication between orchestrator and
  subagents over blocking until each subagent returns."

**Row I8-a: instructed self-check removal** · Tier `behavioral` · Model scope: `opus-5`.

- **Detect:** instructions telling the model to re-check work it already checks — "double-check
  your answer," "re-verify before responding," "include a final verification step," "use a
  subagent to verify" — including legacy harness scaffolding that adds separate verification
  steps.
- **Classify by reviewer INDEPENDENCE, not invocation source:** architected independent review — a
  fresh-context reviewer blind to the producing rationale, or a different-vendor verifier — is NOT
  a finding; the anti-pattern is the instructed self-check. **Carve-out lanes (never flagged):**
  security review, destructive operations, managed-upstream-file changes, PR merge gates.
- **Remediate:** propose removal; verify via the delete-and-watch loop.
- **Bounded by:** the **Stopping condition** below.
- **Source:** Opus 5 guide, "Task scope and over-verification" — remove explicit verification
  instructions: they "cause over-verification on Claude Opus 5, and removing them reduces wasted
  tokens with no loss in quality"; "Self-correction" — avoid instructing re-checks it already
  performs.
- **The independence carve-out is corroborated by a second guide, and the scope does not move.** The
  Fable 5 guide reaches the same line from the opposite direction: it asks for self-verification to
  be made explicit on long runs, and states that "separate, fresh-context verifier subagents tend to
  outperform self-critique" ("Recommended scaffolding changes"). Read without that sentence, the two
  guides look contradictory — remove verification instructions, versus add them — and a reader has to
  resolve it alone. They are not: the anti-pattern is the instructed **self**-check, and an
  architected independent verifier is the thing the Fable 5 guide is asking for. **This does not meet
  the promotion gate**, because the gate wants a second guide stating this row's *detection* claim —
  that verification instructions cause over-verification — and the Fable 5 guide states no such
  thing. The scope annotation stands; only the carve-out gains a second source.

**Row I8-b: conservative-reporting detection** · Tier `behavioral`. Unscoped — promotion gate MET
on its second arm: a second model guide, the Sonnet 5 one, states the same claim about the same
three trigger phrases (see Source), so this fires for every target model.

- **Detect:** review/report instructions that gate severity at the FINDING stage — "be
  conservative," "only report high-severity issues," "don't nitpick" — which current models follow
  literally, withholding real findings. The gate is about WITHHOLDING findings from the audit or
  report output: severity-based routing where everything is still reported somewhere ("only page
  on-call for high-severity; log the rest") and non-reporting uses of "conservative"
  ("conservative time estimates") are not findings.
- **Two fences, OWNED HERE (the scanner over-produces by contract; the model lane adjudicates):**
  1. **Restraint-clause shape** — a clause bounding when a TRANSFORMATION or action applies
     ("When NOT to apply…", "skip the change when…") is not a reporting gate; the canonical
     non-finding shape is a tidying catalog's restraint text (in this monorepo:
     `plugins/code-tidying/skills/tidy/reference/tidyings.md`; in a standalone install the shape,
     not the path, is the fence).
  2. **Quoted/meta surfaces** — a document that DISCUSSES the conservative-reporting pattern
     (this criteria file, a model-adaptation delta chapter, verification records quoting it) is
     not a finding. Judge at the level of the instruction's audience: quoted text embedded inside
     an operative directive ("follow the maxim: 'only report high-severity issues'") is still
     operative and IS a finding; the exemption is for documents about the pattern, never for
     quotation as packaging.
- **Remediate:** rephrase to report-everything + a separate filter/rank pass. Where a single-pass
  self-filter is genuinely wanted, keep it but **state the bar concretely** — an enumerable test the
  reader can decide a novel finding against — rather than a qualitative term.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5 guide, "Code review and bug-finding" — if the prompt says "only report
  high-severity issues" or "be conservative," the model "may follow that instruction literally and
  report less; ask it to report everything and filter in a separate pass instead." Convergent
  second model guide (the gate-meeting one): Sonnet 5 guide, "Code review harnesses" — on the same
  three phrases, "Claude Sonnet 5 may follow that instruction more faithfully than earlier models
  did: it may investigate the code just as thoroughly, identify the bugs, and then not report
  findings it judges to be below your stated bar." That guide is also the only cited home of the
  third trigger phrase — **"don't nitpick" appears nowhere in the Opus 5 guide** — and it states
  the Remediate line's concrete-bar half: "be concrete about where the bar is rather than using
  qualitative terms like `important`."

**Row I8-c: don't-think / don't-reason directive** · Tier `behavioral` · Model scope: `opus-5`.
**The scope is positively confirmed narrow rather than merely unsourced.** A second page states the
claim (see Source), and it is a model-agnostic feature page — the surface where a wider claim would
appear — yet it names Claude Opus 5 anyway. The promotion gate stays unmet by upstream's own
choice, on the same reasoning I10 applies to a declined widening.

- **Detect:** instructions telling the model not to think or not to reason — with thinking
  disabled these increase internal-tag leakage. Also flag tag-hygiene rules that name thinking
  tags specifically (less effective than the general form).
- **Where it shows, and why it outlives the turn.** The leakage is "most commonly on tool-heavy
  workloads such as search" — so a surface governing a tool-driven lane is where to look — and the
  damage is not confined to the response that leaks: "A leaked tool call never runs, and in agentic
  loops the leaked text stays in the conversation history, so later turns are affected as well."
  Read here — the page states the history effect, not this consequence — that means an autonomous
  lane carries the poisoned turn forward as context.
- **Remediate:** remove the directive; where output-tag hygiene is genuinely needed, use the
  general "internal or system XML tags" phrasing.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Source:** Opus 5 guide, "Running with thinking disabled" — "If your system prompt contains a
  rule instructing the model not to think or not to reason, remove it; that kind of instruction
  increases tag leakage"; naming thinking tags is "less effective than the general form."
  Corroborated at troubleshooting thinking, "Tool calls or XML tags appear in the text output",
  which reaches the same claim from the symptom side — "System-prompt rules instructing the model
  not to think or not to reason increase the tag leakage" — and is the source of the condition and
  consequence above. **Verified 2026-08-04** against that page, fetched as raw markdown.
  **Recheck trigger:** a second model name appearing beside Claude Opus 5 in either section that
  states the claim — the Opus 5 guide's "Running with thinking disabled", or this page's "Tool
  calls or XML tags appear in the text output". A new name re-opens the scoping question, not the
  gate itself: the added model joins as a named Detect condition, and unscoping still requires
  what the gate has always required — an unqualified model-agnostic statement, or convergent model
  guides — since a claim qualified to two models licenses nothing about the rest. Neither page
  enumerates the models that do *not* leak, so those two sections are the whole of what there is
  to re-read.

**Row I8-d: short-turn assumptions** · Tier `behavioral` · Model scope: `fable-5`.

- **Detect:** instruction text resting on the premise that a turn is short — a forced interim-status
  cadence ("summarize every N tool calls", "check in after each file"), a directive to answer
  quickly or keep turns brief, or any required progress rhythm pinned to a turn rather than to the
  work. Individual requests now run for many minutes at higher effort and autonomous runs for hours,
  so a rhythm calibrated to the old turn length fires as noise on work that has not reached a
  reportable boundary, and it interrupts precisely the long uninterrupted runs the model is being
  used for.
- **The cadence arm is reached on a different target by I8-e**, which is scoped `sonnet-5` and rests
  on that guide's directly stated claim rather than on this row's duration premise. The two never
  co-fire — exact-match scoping means at most one is live in a run — so the overlap is deliberate
  coverage of one instruction shape from the two guides that reach it, not a row to deduplicate.
- **Remediate:** name the guarantee the cadence was protecting — that the user can see progress,
  that a long run stays interruptible — and either state that outcome and let the model meet it, or
  move it to a mechanism rather than an instructed rhythm. Verify via the delete-and-watch loop.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Must NOT flag: an output-length instruction.** Brevity of the *reply* is a different subject and
  belongs to I8 base; this row's subject is the cadence and duration of the *turn*.
- **Must NOT flag: a latency or duration requirement the surface genuinely owns** — a product SLA, a
  timeout a downstream contract imposes, a rhythm a human review process depends on. Those are
  constraints the surface is entitled to state, not assumptions about how long a model takes.
- **Must NOT flag: a document *about* the pattern** — this row, a model-adaptation delta chapter
  counter-steering it for a different model, a verification record quoting it — on the same audience
  test I8-b applies.
- **Must NOT flag: a cadence carrying its own explicit observability or interruptibility
  rationale** — a rhythm the surface states exists so a long autonomous run stays visible or
  interruptible names the very guarantee the Remediate line protects, and that design is the
  surface's to make — unless evidence shows the cadence was calibrated to an obsolete turn length
  rather than to the work.
- **Scope, and what is deliberately outside it:** the guide pairs this behavior with advice to adjust
  **client timeouts, streaming, and progress indicators** before migrating. That half is harness
  client configuration rather than instruction content, so it is not audited here and no row claims
  it; a surface whose *instruction text* prescribes a short client timeout is the shape that would
  reach this catalog, and none is attested.
- **Source:** Fable 5 guide, "Longer turns by default" — "Individual requests on hard tasks can run
  for many minutes at higher effort settings … and autonomous runs can extend for hours. This is one
  of the largest shifts teams encounter when adjusting to Claude Fable 5."

**Row I8-e: forced interim-status cadence** · Tier `behavioral` · Model scope: `sonnet-5`.

**Why scoped, when a sibling row reaches the same instruction shape.** The promotion gate wants two
model guides *stating* the claim. Only the Sonnet 5 guide states it — that the model already reports
well, so the scaffolding is redundant. I8-d reaches the same shape on a Fable 5 target, but by
**inference** from that guide's turn-duration premise: the Fable 5 guide's "Longer turns by default"
section prescribes adjusting client timeouts and progress indicators and says nothing about removing
instructed status cadence, and elsewhere that guide recommends *adding* a send-to-user progress
mechanism. An inference is a legitimate ground for a scoped row and is not a second statement, so
the gate is unmet and this row stays scoped rather than firing fleet-wide. **The two rows never
co-fire** — exact-match scoping leaves at most one live in a run — so the overlap with I8-d is
deliberate coverage of one instruction shape from the two guides that reach it, not a row to
deduplicate.

- **Detect:** an instruction requiring interim status output on a fixed mechanical interval. The
  guide's own example is "After every 3 tool calls, summarize progress"; equivalents this row also
  reaches — the catalog's, not the guide's — are "check in after each file" and "post an update
  every N minutes". The subject is the *forced rhythm*, not the reporting: an instruction to report
  at a genuine work boundary (a phase completing, a gate failing) pins to the work and is not a
  finding.
- **Remediate:** name the guarantee the cadence was protecting — that the user can see progress,
  that a long run stays interruptible — and either state that outcome and let the model meet it, or
  move it to a mechanism rather than an instructed rhythm. Where the *content* of native updates is
  miscalibrated rather than absent, describe what a good update contains and give examples; that is
  the upstream remediation and it does not reintroduce a cadence. Verify via the delete-and-watch
  loop.
- **Bounded by:** the **Stopping condition** below, which is enabled by default.
- **Must NOT flag: a cadence carrying its own explicit observability or interruptibility
  rationale** — a rhythm the surface states exists so a long autonomous run stays visible or
  interruptible names the very guarantee the Remediate line protects, and that design is the
  surface's to make — unless evidence shows the cadence was calibrated to an obsolete turn length
  rather than to the work.
- **Must NOT flag: a latency or duration requirement the surface genuinely owns** — a rhythm a human
  review process depends on, a heartbeat an external contract requires. Those are constraints the
  surface is entitled to state, on the same reasoning I8-d applies to its own.
- **Must NOT flag: a document *about* the pattern** — this row, a model-adaptation delta chapter
  counter-steering it, a verification record quoting it — on the same audience test I8-b applies.
  This catalog's own detect text is the canonical instance; the deterministic pre-scan seeds no
  pattern for this row, so it carries no fixtures of its own.
- **Source:** Sonnet 5 guide, "User-facing progress updates" — "Claude Sonnet 5 provides regular,
  higher-quality updates to the user throughout long agentic traces. If you've added scaffolding to
  force interim status messages ("After every 3 tool calls, summarize progress"), try removing it."
  That guide also supplies the Remediate line's second half: where updates are miscalibrated,
  "explicitly describe what these updates should look like in the prompt and provide examples."
- **Verified 2026-08-04** against two pages, both fetched as raw markdown. Positive: the Sonnet 5
  guide (15,864 bytes, MD5 `6d23959f0ed226feb06bf20c314029e3`, byte-identical to a 2026-07-29
  capture) for the quoted claim. **Verified negative:** the Fable 5 guide, read in full for this
  row — "Longer turns by default" prescribes only client-side adjustments, no section prescribes
  removing instructed status cadence, and "Create a send-to-user tool" runs the other way. That
  negative is what holds the scope annotation on, so it carries its own stamp rather than resting on
  a reading recorded elsewhere. **Recheck trigger:** the Sonnet 5 guide ceasing to prescribe removal
  of forced status scaffolding, or any second model guide stating the claim — the Fable 5 guide
  included — which would meet the promotion gate and unscope this row.

### I9: Example hygiene

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an example block that pins the model's *approach* to a task (behavioral scaffolding).
  Do not flag examples that steer output format, tone, or structure — those remain recommended.
- **Remediate:** keep 3–5 diverse format/tone/structure examples; propose trimming or reframing
  only approach-pinning ones, A/B'd against the no-example default. Where the example block exists
  to enumerate what a caller may pass — modes, options, permitted values — name the interface
  destination that carries it instead: an argument enumeration, a frontmatter field, a typed
  `argument-hint`. That destination clause is **`OPINION`-derived** — no official page states it —
  so it rides this check's enablement and severity per the `OPINION` policy above, is labelled as
  `OPINION` in the finding, and is never fix-applied.
- **Source:** prompting best-practices, "Use examples effectively" — examples are "one of the most
  reliable ways to steer Claude's output format, tone, and structure"; keep them diverse enough
  "that Claude doesn't pick up unintended patterns."

### I10: Reasoning-echo directives

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all · Model scope:
`fable-5` (the cited refusal category is documented for that model only; promotion gate unmet).

- **Detect:** instructions telling the model to show, echo, transcribe, or explain its internal
  reasoning as response text. The deterministic pre-scan marks show-your-thinking phrasing.
- **Remediate:** remove them; where reasoning visibility is genuinely needed, read structured
  `thinking` blocks through the surface that already exposes them — in Claude Code, `Ctrl+O` verbose
  mode and the `showThinkingSummaries: true` setting (model configuration); on the API,
  `display: "summarized"` (Thinking). A send-to-user tool remains the path when the reasoning has to
  reach the user as ordinary response text.
- **Source:** Fable 5 guide — such instructions "can trigger the `reasoning_extraction` refusal
  category on Claude Fable 5, causing elevated fallbacks." Corroborated by the Thinking page, which
  states the same refusal for the same model: "On Claude Fable 5, a request that attempts to elicit
  the model's internal reasoning as part of the response text can be refused with
  `stop_details.category: "reasoning_extraction"`." That second citation does **not** move the
  promotion gate: its own section names both Claude Fable 5 and Claude Mythos 5 for the adjacent
  raw-chain-of-thought property, then names Fable 5 alone for the refusal — a sentence-adjacent
  chance to widen, declined, so the narrower scope is deliberate.

  **`Model scope: fable-5` is now positively sourced rather than held by that declined widening**,
  in two statements each taken from the page that owns its half. The page that owns Mythos 5 states
  the exclusion at the level of the whole classifier set: "Claude Fable 5 includes safety
  classifiers that can decline certain requests. Claude Mythos 5 does not include these classifiers,
  so this section applies to Claude Fable 5 only" ([Introducing Claude Fable 5 and Claude Mythos
  5](https://platform.claude.com/docs/en/about-claude/models/introducing-claude-fable-5-and-claude-mythos-5),
  fetched 2026-08-03). Refusals and fallback places this row's category inside that set, listing
  `reasoning_extraction` among the classifier categories a refusal reports. The scope conclusion is
  unchanged — what changed is that a reader no longer has to reconstruct it from an omission. Which
  models carry the classifier set is a per-model fact and moves, so the introducing page joins
  `## Sources`: the catalog-wide trigger then fires this row whenever that page changes, and no
  narrower per-row trigger is owed.

### I11: CLI over MCP where equivalent

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all.

- **Detect:** an instruction steering the model to an MCP tool where an equivalent CLI exists, when
  the surface's concern is context cost rather than a capability the MCP server uniquely provides.
- **Remediate:** prefer the CLI for the equivalent operation; keep the MCP path where it adds
  capability.
- **Source:** best-practices — "CLI tools are the most context-efficient way to interact with
  external services."

### I12: Stale or misattributed harness-capability claim

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all.

- **Detect:** an instruction that asserts a Claude Code *harness* behavior — what a command does,
  what a keystroke saves, what loads into which context window, what a mode persists — where
  **either** the official documentation **for the version the claim is about** states something
  incompatible with it, **or** a reproduction matching **every** stated precondition fails. The
  subject is the product, not the model, which is what separates this from I8.
- **Remediate:** correct the claim against the cited page, or cut it and point at the page instead
  of restating it. Where the behavior is version-gated, carry the minimum version with the claim.
- **Must NOT flag: silence.** A page that no longer mentions a behavior is not evidence the behavior
  changed — product documentation is routinely rewritten, condensed, or reorganized, and this
  repository deliberately keeps empirical smoke tests for behaviors the official pages never
  specified at all. Absence of documentation raises the claim for reproduction; it does not
  establish drift, and it never on its own justifies a removal.
- **Must NOT flag: a gated claim that still reproduces under its own conditions.** Match the
  conditions before matching the text. Version is the common one — a claim scoped to a pinned or
  supported older release is measured against that release, not against the latest page — but it is
  not the only one: **OS, a setting, an account tier, a feature flag, and launch mode are equally
  preconditions**, and a replay under different conditions proves nothing about the instruction.
  **A successful matched reproduction settles it**; a failed one settles it only when every stated
  precondition was met, and is otherwise **inconclusive rather than a finding**. A claim carrying no
  conditions is about current default behavior and is measured against the current page. This is the
  mirror of the remediation above: a catalog that asks authors to carry a claim's conditions must not
  then flag the claims that do.
- **Must NOT flag:** prose that names two adjacent forms and distinguishes them correctly — the
  terminal `claude doctor` being read-only while the in-session `/doctor` applies fixes is the
  canonical pair, and a file that states both is right, not drifting. A bare routing pointer that
  tells the reader to run a command without claiming what it does. Text that quotes a retired
  affordance explicitly as retired.
- **Source:** CLI reference — "Print read-only installation and settings diagnostics from the
  terminal without starting a session … For the in-session setup checkup that can also apply
  fixes, run `/doctor`."

### I13: Citation form that does not load

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: non-memory only
(skill bodies and their reference files, agent definitions, hook instruction text, output styles).

- **Detect:** an `@path` written outside backticks and outside a fenced block on a surface where `@`
  carries no import meaning, **in prose that asserts the file has already arrived** — "as specified
  in @reference/rules.md above", "the criteria in @reference/criteria.md are loaded", a claim that
  the content is present rather than an instruction to go get it. Import syntax is a property of the
  CLAUDE.md family; on a skill or agent surface the `@` is inert, so an instruction written on the
  assumption that it imported is describing a load that did not happen.
- **Remediate:** rewrite the assertion into an explicit read, and cite the file the way that surface
  actually resolves — a backticked path or a markdown link. **Changing the citation syntax alone is
  not the fix**: neither form imports anything either, so a diff that swaps `@reference/rules.md` for
  a backticked path while leaving "as specified above" in place keeps the false claim and still lets
  the agent proceed without the content. The false premise is the defect; the syntax is where it
  shows.
- **Must NOT flag: an `@path` the surrounding prose treats as a file to read.** The path is still
  legible in the loaded prompt, so "follow `@reference/rules.md`" works — the reader opens it, the
  inert prefix costs one character. **The finding is the false assumption of automatic loading, not
  the citation form**, and a warning on every inert `@` would flag working instructions. When the
  prose does not say the content already arrived, leave it.
- **Must NOT flag:** anything on a memory-layer surface, where `@path` genuinely imports. A
  package scope (`@anthropic-ai/…`), a decorator, an email address, or a `@username` handle. A
  backticked `` `@path` ``, which the import parser skips by design and which is the documented
  way to mention a path without importing it. A path cited without an `@` at all.
- **Source:** memory — "CLAUDE.md files can import additional files using `@path/to/import`
  syntax", against skills, where supporting files are instead referenced "so Claude knows what
  each file contains and when to load it" and no import syntax is defined.

### I14: Retrieval of an already-loaded surface

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: agent definitions and
skill bodies.

- **Detect:** an instruction directing the agent to go read a surface the main conversation loads at
  startup and therefore already carries — the **root** `CLAUDE.md`, the user `CLAUDE.md` at the
  **resolved** `${CLAUDE_CONFIG_DIR:-~/.claude}`, the **root** `CLAUDE.local.md`, unconditional
  project rules (no `paths` frontmatter), and managed policy files. Two qualifiers are load-bearing.
  Root-level: the startup guarantee is scoped to the hierarchy discovered from the launch directory,
  not to every file of that name in the tree. Resolved: `CLAUDE_CONFIG_DIR` moves the whole config
  tree, so a hardcoded `~/.claude/CLAUDE.md` both flags a read that is now necessary and misses the
  redundant read of the configured path. Phase A resolves this variable already (`SKILL.md:76-78`);
  match it. The read spends a turn to retrieve text that is already present.
- **Remediate:** cut the retrieval step and state the requirement the read was meant to satisfy.
- **Must NOT flag: anything that loads on demand rather than at startup.** The guarantee this check
  rests on covers the hierarchy *the main conversation loads*, which is not the whole memory family.
  **Nested `CLAUDE.md` and nested `CLAUDE.local.md` files in subdirectories, and path-scoped rules
  (`paths` frontmatter), load lazily when work reaches their scope** — both filename forms, since
  the lazy-loading behavior is a property of the location rather than of the name. An instruction to
  read either one before operating in that package can be doing real work. Flag only when the
  specific file named is one of the startup-loaded set above; when a surface's residency is not
  established, leave it.
- **Must NOT flag:** an instruction to read a surface that is *not* auto-loaded — `AGENTS.md`,
  contributing guides, ADRs, CI workflow files, per-ecosystem convention docs. Those are ordinary
  progressive disclosure. **Any read where the file is the operation's subject rather than its
  instructions** — auditing it, editing it, patching it, reporting on it, or anything else needing
  current disk contents. The startup copy is a snapshot taken at launch; another process can have
  changed the file since, and a pre-edit read cut on the grounds that "it is already in context"
  produces a patch against stale text. A rule restated in a
  delegation prompt for the built-in Explore and Plan agents, which are documented as the only
  subagents that skip `CLAUDE.md` and have no per-agent setting to change that.
- **Source:** subagents, "What loads at startup" — a non-fork subagent's initial context contains
  "every level of the CLAUDE.md hierarchy the main conversation loads, including
  `~/.claude/CLAUDE.md`, project rules, `CLAUDE.local.md`, and managed policy files." The qualifier
  *the main conversation loads* is what bounds this check: memory documents lazy loading for
  "path-specific rules or lazy-loaded files in subdirectories", so those are outside the guarantee.

### I15: Cross-surface instruction conflict

Tier `behavioral` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all — but the unit is
a **pair**, so this row is answered by Phase B2 rather than by a per-surface lane.

- **Detect:** two instruction surfaces that both constrain the same decidable act and prescribe
  incompatible actions for at least one input firing both, with no resident text arbitrating between
  them. The unit of judgment is the pair, never one document read alone — which is why the
  per-surface lanes are structurally blind to it. The five gates that make this checkable, the
  residency table gate 1 resolves against, and the precedence table separating what the docs settle
  from what they leave unresolved all live in
  [conflict-criteria.md](conflict-criteria.md); that file is this row's adjudication procedure.
- **Comparison set:** every pair drawn from the surfaces Phase A inventoried, including the ones it
  recorded as *skipped* — plugin-cache content, managed materializations, org policy — since a
  contradiction is real whether or not this repository may edit either side. Resolve `@path` imports
  and symlinks to their targets before pairing, so an imported file is compared as part of the
  surface importing it rather than as a separate one.
- **Excluded from the comparison set:** `AGENTS.md` and other files that are not Claude Code
  instruction surfaces. They shape no behavior here, so a divergence between one and a `CLAUDE.md`
  is not a conflict this check reports.
- **Remediate by scope**, never by picking a winner the docs do not name. Where the precedence table
  cites a documented order, name the winner and its source. Where it does not, report the pair as
  `unresolved` with both anchors quoted and let the operator choose. Where the same conflict keeps
  recurring, offer the mechanism route — a `PreToolUse` hook, a `permissions.deny` rule, or a skill's
  own `disallowed-tools` — since a mechanism outranks instruction text.
- **Must NOT flag:** two surfaces that can never be resident together (that is orphaned instruction
  drift, reported separately). Different observables sharing a keyword. The same verb over different
  objects. An absolute carrying its own exception beside a directive presupposing that exception. A
  pair one of whose sides already states which wins. The full set with worked instances is in
  [conflict-criteria.md](conflict-criteria.md).
- **Source:** memory — "If two rules contradict each other, Claude may pick one arbitrarily", which
  is why an unarbitrated pair is a finding rather than a stylistic note. Corroborated at the
  context-engineering blog, "Unhobbling Claude", where Anthropic's own system prompt, skills, and
  user requests clash — "several conflicting messages in a single request like 'leave documentation
  as appropriate,' or 'DO NOT add comments'" — with the cost stated even for the resolved case:
  "Claude must think more carefully about these overlapping and conflicting messages before
  deciding what to do." So a conflict taxes reasoning even when no arbitrary pick occurs.

### I16: Definition-site locality

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** an instruction that governs one named thing — a tool, a script, a subsystem, a skill —
  living somewhere other than that thing's own definition: a rule about tool X in a global
  always-loaded file rather than beside X.
- **Different axis from I3, and both can fire on one instruction.** I3 is load *timing*; this is
  definition-site *locality*. An instruction can be correctly deferred — already in a skill or a
  path-scoped rule — and still sit away from the thing it governs.
- **Must not flag:** an instruction that genuinely applies across the whole target, which is I3's
  broad-applicability case and not a locality defect; or one whose subject has no definition site to
  sit beside.
- **Remediate:** move it beside its subject — the skill body, the agent definition, the tool's own
  documentation. **The destination must be a surface Claude loads.** This check diagnoses locality,
  not load timing, so a move that lands an always-loaded instruction in an ordinary README or
  reference file silently drops the behavior it enforced unless Claude independently reads that file.
  Where the subject's definition site is not itself loaded, propose the colocated text *plus* a
  retained one-line pointer on a loaded surface that triggers reading it — never a bare move.
  Reported only, never fix-applied, per the `OPINION` policy above.
- **Source:** none. No official page states definition-site locality, which is why this check is
  `OPINION`-tier. The *routing* half — which surface a class of content belongs in — is documented
  at features-overview, "Compare similar features", and is I3's concern, not this check's.

### I17: Thinking disabled where the model forbids it

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped —
promotion gate MET: the claim is stated on a model-agnostic feature page, not in a model guide.
**The model ranges are Detect conditions, not a `Model scope` annotation.** One source says the
restriction "applies to Claude Opus 5 and later models"; the other names Fable 5, Mythos 5 and
Mythos Preview. The annotation's exact-string matching has no range form — annotating `opus-5` would
make the row inert on the next generation while the restriction still holds, and no single
annotation spans two disjoint families at once. I20 handles a model range the same way.

Each row below carries its own decisive source; they share a subject, not a citation.

**Base row: the configurations the model rejects.** Two arms with different shapes — a pairing that
fails only at the top of the effort ladder, and a disable that fails at every level. Both are
`error`, since both are a rejected request.

- **Detect:** a surface that recommends, documents, or sets a **thinking-disable surface** —
  `MAX_THINKING_TOKENS=0`, `alwaysThinkingEnabled: false`, the `/config` global toggle, the
  `Alt+T` / `Option+T` session toggle, or API `thinking: {"type": "disabled"}` — together with
  `xhigh` or `max` effort, on Claude Opus 5 or a later model. Both operands are configuration
  literals, so a surface prescribing both publishes a per-request 400 that nothing recovers.
- **Effort literals do not all reach every surface, and the literal set is not the whole set.**
  `max` reaches a session through `CLAUDE_CODE_EFFORT_LEVEL`, `--effort`, `/effort`, or skill and
  subagent `effort` frontmatter — the frontmatter case being a surface this skill already
  inventories. **The `ultracode` *setting* also trips this** without matching either literal: it is
  a Claude Code setting rather than an effort level and "sends `xhigh` to the model", so a surface
  pairing it with a thinking-disable surface produces the identical rejection. Only the
  effort-setting forms count — instruction text prescribing `/effort ultracode`, `--effort
  ultracode`, or `--settings` / Agent SDK `"ultracode": true` or `effortLevel: "ultracode"`. Match
  on the effort that reaches the request, not on the spelling.
- **Second arm — the models that reject the disable outright, at every effort level.** Claude
  Fable 5, Claude Mythos 5, and Claude Mythos Preview reject `thinking: {type: "disabled"}`
  whatever effort is in force, so on that family the disable surface alone is the finding and no
  effort operand has to be present for the request to fail. Read the effort operand as a condition
  that *narrows* the Opus 5 arm, never as a precondition the whole row inherits — carried across, it
  would pass a surface prescribing thinking-off at `high` on Fable 5 as compliant. **Only the API
  form belongs to this arm.** On **Fable 5** the harness thinking-disable surfaces fail differently
  — model configuration states thinking cannot be turned off there and that the session toggle,
  `alwaysThinkingEnabled` and `MAX_THINKING_TOKENS=0` "have no effect there", so they are silent
  no-ops rather than errors — and that failure is I17-a's, not this row's. **For Mythos 5 and Mythos
  Preview the harness pages state nothing**, so this row makes no claim about their harness surfaces
  in either direction; the API reject is the whole of what is stated for them.
- **Remediate:** on the Opus 5 arm, lower the effort to `high` or below, or leave thinking on — and
  state which, since the pairing has no third resolution. **On the second arm there is only one
  resolution: leave thinking on.** No effort level permits the disable on that family, so a
  remediation that offers the reader the choice sends them to a request that still fails.
- **Scope, and where the config check lives:** this row audits **instruction text**. Either arm
  expressed as *settings keys* is a config-mechanics finding and belongs to
  `claude-config:audit`, per this skill's own routing — an instruction-content catalog that also
  scanned settings files would claim authority a sibling already holds. Instruction text that
  happens to *live* in a settings file, such as a prompt-type hook's injected text, stays here: the
  discriminator is whether the content instructs, not which file holds it.
- **Must NOT flag:** `effortLevel: max` as a literal to hunt **in instruction text** — the settings
  schema's `enum` accepts `"low"`, `"medium"`, `"high"`, `"xhigh"` only, so a schema-aware editor
  flags the value where it is actually written, and an instruction-text auditor sent after the
  literal finds nothing and learns nothing. The value is writable, not unreachable: the schema is
  advisory and the harness reads a file that violates it, which is why the settings-file check is
  `claude-config:audit` category H rather than absent. **A document that states either arm in order to
  describe or forbid it** — this row, a model-adaptation delta chapter, a verification record
  quoting it — on the same audience test I8-b applies: either arm prescribed inside an operative
  directive is a finding; a document *about* it is not. **The bare `ultracode` prompt
  keyword** — instruction text telling a reader to include it in a typed prompt runs one task as a
  workflow "without changing the session's effort level", so no effort reaches the request and the
  rejected pairing never assembles. **A thinking-disable surface named with no effort level in reach
  of it — on the Opus 5 arm only**, where the pairing is what fails. On the second arm that is the
  finding itself, so this fence is scoped to the arm that earns it rather than to the row.
- **Source:** effort — "On Claude Opus 5, thinking cannot be disabled at `xhigh` or `max` effort:
  requests that set `thinking: {"type": "disabled"}` at those levels return a 400 error."
  Corroborated at thinking-troubleshooting, which supplies the model range and adds that the
  restriction "is enforced on each request". The per-surface value sets are read from the surfaces'
  own pages: settings for `effortLevel`, environment variables for `CLAUDE_CODE_EFFORT_LEVEL`,
  skills and subagents for `effort` frontmatter, and model configuration for `/effort`, the session
  and global thinking toggles, and ultracode — the last enumerating the three routes that turn the
  *setting* on (`/effort`, `--effort`, `--settings` / Agent SDK). The keyword's separation from the
  setting is read from workflows, "Ask for a workflow in your prompt": including `ultracode` in a
  prompt runs "a single task as a workflow without changing the session's effort level". The second
  arm is thinking's, stated in the paragraph directly after that page's own statement of the Opus 5
  arm: "Claude Fable 5, Claude Mythos 5, and Claude Mythos Preview reject `thinking: {type:
  "disabled"}`: thinking cannot be turned off on these models." That sentence carries no effort
  qualifier, which is what makes the arm unconditional rather than a wider pairing — and the
  adjacency is why the two must be read as separate arms rather than one range.
- **Local coverage of the second arm, measured 2026-08-04: zero operative instances in the
  repository that authored it.** The disable literal occurs six times across four files — three in
  this catalog, once in the Opus 5 model-adaptation delta chapter, twice in changelog entries — and
  every one is a document *about* the restriction, which is the audience-test fence above rather
  than a passed check. **Re-measure when** a surface here begins prescribing a thinking-disable
  instead of describing one.
- **Verified 2026-08-04** against those pages, fetched as raw markdown. **Recheck trigger:** the
  effort level set gaining or losing a name, the set of `ultracode` forms that reach `xhigh`
  changing, the restriction's model range moving, or the set of models that reject the disable
  outright changing.

**Row I17-a: `MAX_THINKING_TOKENS=0` presented as a universal off switch** · Tier `mechanical` ·
Severity `warning`.

- **Detect:** text stating or implying that `MAX_THINKING_TOKENS=0` turns thinking off generally.
  It does not. On Fable 5 it has no effect at all — nor do the session toggle or
  `alwaysThinkingEnabled` — and on third-party providers it omits the `thinking` parameter instead,
  so an adaptive-reasoning model may still think. Also flag text treating
  `CLAUDE_CODE_DISABLE_THINKING` as equivalent: that variable omits the parameter on every
  provider, which on a model that thinks by default leaves it still thinking. Also flag text
  presenting the session thinking toggle or `alwaysThinkingEnabled` as turning thinking off on
  Fable 5 — model configuration states they "have no effect there", so the reader is promised a
  control that is a silent no-op on that model.
- **Remediate:** carry the exceptions with the claim, or point at the page instead of restating it.
- **Adjacent axis:** this is also a harness-capability claim, so **I12 can fire on the same line**.
  I12 asks whether the claim matches its page; this row asks whether a reader following it gets the
  behavior they were promised. Report both when both hold.
- **Must NOT flag:** a mention that already carries the Fable 5 or third-party exception. A bare
  reference to the variable making no claim about its reach.
- **Source:** environment variables — `MAX_THINKING_TOKENS` "Set to `0` to disable thinking on the
  Anthropic API, except on Fable 5, which cannot have thinking turned off; on third-party providers,
  `0` omits the `thinking` parameter instead". Model configuration heads the same control "Disable
  regardless of effort", so a surface repeating that heading unqualified inherits a claim the
  variable's own page contradicts.
- **Verified 2026-08-02** against those two pages, fetched as raw markdown; the session-toggle and
  `alwaysThinkingEnabled` arm re-verified 2026-08-04 against model configuration. **Recheck
  trigger:** the set of models that cannot disable thinking changing.

**Row I17-b: mid-session thinking or effort change prescribed without its cost** · Tier
`mechanical` · Severity `info`.

- **Detect:** an instruction directing a reader to change **effort**, or the **thinking
  configuration**, part-way through a session without naming what it costs. Both are rendered into
  the request, so either change starts a new cache prefix and the next request re-reads the whole
  conversation uncached. The thinking half covers switching among `adaptive`, `enabled` and
  `disabled`, and changing `budget_tokens`.
- **Must NOT flag: a Claude Code surface prescribing an *effort* change**, where the harness already
  surfaces the cost — it "asks you to confirm before applying the change", and a change resolving to
  the level already in effect skips the dialog and keeps the cache. Nor flag a change prescribed
  *with* its cost stated, which is the remediation.
- **Reach differs by half, and this is the whole of it.** The effort half reaches every surface, with
  Claude Code surfaces carved out above. **The thinking half reaches API and Agent SDK surfaces
  only** — that is where the page's claim is anchored and where no dialog exists. A Claude Code
  surface prescribing a mid-session thinking toggle is **out of reach of this row**, neither excused
  by the effort carve-out nor flagged by the thinking half.
- **Why the carve-out does not simply extend to thinking, and why the row stops short instead.**
  Claude Code's prompt-caching page names exactly two settings that sit outside the prompt text and
  are still part of the cache key — model and effort level — and documents the confirmation dialog
  for effort alone. So the dialog's protection cannot be assumed for a thinking toggle; but the
  harness-side *consequence* of one is equally undocumented, and this catalog does not flag what its
  sources do not state. Hence out of reach rather than covered. **Re-scope when** the harness
  documents what a mid-session thinking change costs.
- **Why the thinking half is not I17-c, and why both can fire — on accepted changes only.** This
  row asks what a change *costs* — a switch among the modes, or a change to `budget_tokens`,
  restarts the cache when the new configuration is accepted and a turn runs under it. I17-c asks
  whether a fixed budget is a valid control on the target model at all, and where it applies the
  cost claim may never materialize: an API request the model rejects with a validation error
  completes no turn, and a harness value the model silently ignores changes no configuration — in
  both cases the reader's actual outcome is I17-c's finding alone, and adding this row's cache-cost
  remediation would be a second, misleading instruction. So: a mid-session change between
  configurations the model accepts gets this row; a prescription I17-c already condemns as not a
  valid control gets I17-c alone. Report both only where a surface prescribes both an invalid
  control and, separately, an accepted mid-session change.
- **Local coverage of the thinking half, measured 2026-08-04: zero operative instances here.** The
  session-toggle and `budget_tokens` literals appear only in this catalog, in two model-adaptation
  delta chapters, and in changelog entries — descriptions, not prescriptions.
- **Remediate:** name the re-read cost, and prefer choosing both dials at session start.
- **Source:** prompt caching — "**Effort level**: each effort level has its own cache for the same
  model. Changing it mid-session recomputes the entire request, and Claude Code asks you to confirm
  before applying the change." The thinking half is thinking's, which puts the thinking
  configuration and the resolved effort level in the same position — both "are rendered into the
  prompt itself, so changing any of them starts a new cache prefix" — and then enumerates the
  changes: "Switching between `adaptive`, `enabled`, and `disabled`, changing `budget_tokens`,
  and changing the effort value all invalidate cache breakpoints: message-level breakpoints always
  miss, and tool and system-prompt breakpoints can miss too, depending on where the model renders
  the configuration."
- **Verified 2026-08-04** against those two pages, fetched as raw markdown. **Recheck trigger:**
  effort or the thinking configuration leaving the cache key, the confirmation behavior changing, or
  the harness gaining a documented dialog for thinking changes.

**Row I17-c: fixed thinking budget prescribed where adaptive reasoning ignores or rejects it** ·
Tier `mechanical` · Severity `warning`. Unscoped — promotion gate MET: the claim is stated on
model-agnostic surface pages and a cross-model migration guide, not in a model guide. **The model
ranges below are Detect conditions, not a `Model scope` annotation**, for the reason I17 base states.

- **Detect:** instruction text directing a reader to control thinking *depth* with a fixed token
  budget on a model that always uses adaptive reasoning. Two arms, with opposite failure modes:
  - **Harness arm — silent no-op.** A nonzero `MAX_THINKING_TOKENS`, or
    `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` offered as the way to make one take effect. Nonzero
    values are ignored on adaptive-reasoning models, and that variable reaches none of the models
    that always use adaptive reasoning — so a reader who follows the instruction sees no error and no
    effect, which is the worst of the two failures.
  - **API arm — hard 400.** `thinking: {type: "enabled", budget_tokens: N}`, or prose presenting a
    thinking budget as a tunable number, on Opus 4.7 and later, Sonnet 5, Fable 5, or Mythos 5.
- **Why this is not I17-a.** That row is about `MAX_THINKING_TOKENS=0` — the claim that thinking can
  be turned *off*, and whether the exceptions travel with it. This row is the claim that thinking
  depth can be *set to a number*. Different literal, different promise, different failure; both can
  fire on one surface that gets the whole variable wrong, and both should be reported when they do.
- **Must NOT flag: a claim carrying its own gate — of either kind.** Text naming Opus 4.6 or Sonnet
  4.6, where the fixed-budget mode is live and `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` does exactly
  what it says, is correct rather than stale. **So is text scoped to a Claude Code release before
  v2.1.111**, which is where the variable lost its reach over the adaptive-reasoning models — the
  gate here is a version as well as a model set, and I12's precondition rule already says a claim
  scoped to a pinned older release is measured against that release. This fence matters more here
  than usual: the tempting shape of this check is a bare grep for the variable name, which would flag
  every accurate piece of documentation about it. **The finding is the missing gate, never the
  mention.**
- **Must NOT flag:** a bare reference to either variable making no claim about its reach. A document
  *about* the pattern — this row, a model-adaptation delta chapter, a verification record — on the
  audience test I8-b applies. **The budget expressed as a settings key, an environment assignment, or
  an SDK request field** rather than prescribed in instruction text: that is a config-mechanics or
  source-code finding on the same discriminator I17 base, I21 and I22 apply, and this catalog audits
  instruction text.
- **Remediate:** point at the effort parameter as the depth control on adaptive-reasoning models —
  upstream's own framing is "It has no direct replacement: thinking is adaptive, and the `effort`
  parameter is a separate output-level control, not a thinking budget" — or carry the model gate with
  the claim.
- **Source:** environment variables — `MAX_THINKING_TOKENS` "Nonzero values are ignored on adaptive
  reasoning models unless `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` is set", and that variable, "From
  v2.1.111, has no effect on Fable 5, Sonnet 5, or Opus 4.7 and later, which always use adaptive
  reasoning" — the version qualifier being the second half of the gate fence above. Model
  configuration states the same partition from the other side: "Fable 5, Sonnet 5, and Opus 4.7 and
  later always use adaptive reasoning. The fixed thinking budget mode and
  `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING` do not apply to them", while "On Opus 4.6 and Sonnet 4.6,
  you can set `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING=1` to revert" — which is the fence above,
  stated upstream. The API arm: migration guide — `thinking: {type: "enabled", budget_tokens: N}`
  "is no longer supported on Claude Opus 4.7 or later models and returns a 400 error", with the same
  stated for Fable 5 and Mythos 5; corroborated for this model generation by the Sonnet 5 guide,
  "Calibrating effort and thinking depth" — manual extended thinking "is not supported on Claude
  Sonnet 5 and returns a 400 error. It was deprecated on Claude Sonnet 4.6 and is now removed."
- **Verified 2026-08-04** against those four pages, fetched as raw markdown. **Recheck trigger:** the
  set of models that always use adaptive reasoning changing, `CLAUDE_CODE_DISABLE_ADAPTIVE_THINKING`
  regaining or losing reach, or manual extended thinking being reinstated on any model in the range.

### I18: Thinking blocks altered on the way back to the model

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all. Unscoped —
promotion gate MET: the round-trip protocol is stated on a model-agnostic feature page, not in a
model guide.

Two rows, in opposite directions: the base row is what a surface does to blocks it *has*, and I18-a
is what a surface believes about blocks that are *not there*. They share a subject, not a citation.

**Base row: blocks altered on the way back.**

- **Detect:** instruction text directing an agent, a script, or a reader to handle assistant content
  blocks in a way that breaks the round-trip protocol. Three shapes:
  1. **Dropping the `signature`.** An instruction to reconstruct, summarize, re-serialize, or
     hand-assemble an assistant turn before sending it back, where the reconstruction does not
     carry each `thinking` block's `signature` through unchanged. The server decrypts that field to
     rebuild the reasoning; a block without it is not the block the model produced.
  2. **The type-filter smell.** An instruction to select content blocks by testing
     `block.type == "thinking"` when round-tripping tool-use responses. The predicate silently
     omits `redacted_thinking` blocks, which the protocol requires back unchanged.
  3. **Within-turn echo integrity.** An instruction to reorder, edit, truncate, or partially drop
     the consecutive `thinking` blocks of the latest assistant message — including "keep only the
     last one" and "strip thinking before resending" advice. Modified blocks are rejected with a
     400.
- **Reach — this is wider than Messages API client code.** Any instruction whose output eventually
  becomes a request body is in scope: Agent SDK callers, harness integrations, and **tooling that
  parses, excerpts or rewrites a stored transcript that will later be replayed or resumed**. What
  puts a surface in scope is a path back to the model, not the file format it reads.
- **Remediate:** echo the assistant `content` array back unchanged rather than rebuilding it; where
  blocks must be selected, select by what is being *excluded* rather than by an equality test on one
  type name; where a transcript is being read for analysis only, say so, since a read that never
  re-sends is outside the protocol entirely.
- **Must NOT flag:** an instruction to read or analyze a transcript with no path back to the model —
  metrics extraction, retrospectives, search. **A `redacted_thinking` clause premised on those blocks
  being present in local transcripts**, which is a separate and unevidenced claim; this row's
  concern is only that a type filter would drop them if the API returned them. Pruning of *prior*
  turns' thinking, which the API does for you and which the page explicitly allows outside tool use.
  **A document that names the type-filter predicate in order to describe the smell** — this row,
  a model-adaptation delta chapter, a verification record quoting it — on the same audience test
  I8-b applies: the predicate quoted inside an operative directive is still operative and is a
  finding; a document *about* the pattern is not.
- **Source:** Thinking, "Preserving thinking blocks" — "Pass every `thinking` block back to the API
  complete and unmodified, alongside the `tool_use` block it accompanied", and "Within the latest
  assistant message, the sequence of consecutive `thinking` blocks must match what the model
  generated in the original request: you can't rearrange, edit, or partially drop them." Same page,
  "Thinking encryption" — "Full thinking content is encrypted and returned in the `signature` field
  on each thinking block" — and "Redacted thinking blocks" — "Filtering on
  `block.type == "thinking"` alone silently drops `redacted_thinking` blocks and breaks the
  multi-turn protocol…".
- **Local coverage, measured 2026-08-02: zero instances of all three shapes in the repository that
  authored this row**, which ships it consumer-facing and unexercised by its own corpus. Stated so
  the absence reads as an as-of measurement rather than as a passed check. **Re-measure when** a
  round-trip or transcript-replay path lands here.
- **Verified 2026-08-02** against the Thinking page, fetched as raw markdown. **Recheck trigger:** a
  content-block type joining or leaving the set the protocol requires echoed back.

**Row I18-a: a leading thinking block treated as required where the model does not require one** ·
Tier `mechanical` · Severity `warning`.

- **Detect:** instruction text asserting, or directing work premised on, a validation rule that
  assistant turns must begin with a thinking block. Three shapes:
  1. **Reinsertion.** An instruction to insert, synthesize, or restore a leading `thinking` block
     when assembling history from mixed sources, so that each assistant turn "starts with one".
  2. **History rewriting on resume.** An instruction to rewrite, normalize, or discard a
     conversation because it began without thinking or ran under a different thinking
     configuration.
  3. **Presence-assuming logic.** An instruction to read, index, or branch on an assistant turn's
     first content block as though it were a `thinking` block. A turn where Claude chose not to
     think carries none, and the same conversation can hold turns of both kinds.
- **Why the belief is a finding and not a harmless one.** The remediation a reader reaches for is
  fabrication, and a hand-built block carries no valid `signature` — the base row's shape 1, and a
  rejected request. This row is therefore the upstream cause of the base row's violation, not a
  restatement of it; report both when a surface states the premise *and* acts on it.
- **Remediate:** pass history back in whatever shape you have it, and treat a thinking block as
  optional per assistant turn — in tests too, where a no-thinking turn is the case the assumption
  hides.
- **Reach: the base row's, unchanged, and for all three shapes** — a path back to the model is what
  puts a surface in scope, not the file format it reads. **Presence-assuming logic that only ever
  reads is out of reach rather than excused.** The page's caution sits in the request/response
  frame and says nothing about stored transcripts, and whether a harness transcript carries
  thinking blocks at all is unestablished; the harm there would in any case be the consumer's own
  logic rather than a rejected request, which is a code-correctness matter this catalog does not
  audit. **Re-scope when** the stored transcript's content-block shape is documented.
- **Must NOT flag: text scoped to a legacy manual thinking budget AND to the final assistant
  turn**, where the requirement is real. The page carves it out itself — those models "enforce that
  the final assistant turn of a thinking-enabled request begins with one" — and the enforcement is
  exactly that wide: the final assistant turn of a thinking-enabled request, no other turn. A
  legacy-scoped instruction demanding a leading block on *every* assistant turn over-requires past
  its own source and still flags. The gate is the model's thinking mode plus the turn it names, not
  the sentence's confidence, and as in I17-c **the finding is the missing gate, never the
  mention.**
  **The base row's own advice**, which is not this row's inverse: the relaxation "is about
  validation, not about what you should send", so an instruction to pass blocks you *have* back
  unmodified — particularly during tool use — is correct and stays correct. Reading this row as
  license to drop blocks inverts both rows at once. A document *about* the assumption, on the
  audience test I8-b applies.
- **Source:** Steering thinking, "Turn validation" — "Assistant turns don't need to start with a
  thinking block" — with the three consequences stated there, one per shape above: turns where
  Claude chose not to think "are valid history as-is"; a conversation begun without thinking, or
  under a different thinking configuration, resumes "without rewriting its history"; and history
  assembled from mixed sources "doesn't need thinking blocks reinserted at the start of each
  assistant turn to pass validation". The legacy carve-out is that same "Turn validation" section's
  own parenthetical, quoted in the fence above. The presence half is the same page, "How Claude
  decides when to think" — "a turn where Claude chose not to think contains no thinking block. Don't
  build application logic that assumes every assistant turn starts with one."
- **Why this page is cited and not the sibling.** The Thinking page carries the same pair, but
  compressed into a single sentence inside "Thinking with tool use": in extended (manual) mode the
  API "additionally enforces that the final assistant turn of a thinking-enabled request begins with
  a thinking block", and "Adaptive mode relaxes this: no assistant turn needs to start with one."
  That corroborates this row; it does not carry it. Steering thinking is where the relaxation is
  stated operatively — the three history-shape consequences the detect shapes are drawn from, plus
  the presence caution — so it is cited as decisive and the sibling as corroboration. Separate from
  both is that page's *strip* claim, that the API "may strip thinking blocks that would create an
  invalid turn structure": server-side degradation of a request, not a rule about what history a
  caller may send, and it licenses nothing here.
- **Local coverage, measured 2026-08-04: zero operative instances here**, on the same footing as the
  base row — nothing in this repository assembles, rewrites, or replays history back to the model.
  The one transcript consumer, `session-flow`'s retro parser, selects blocks by testing each item's
  own `type` rather than by position, so it is correct by construction rather than by this rule.
  Stated as an as-of measurement, not a passed check. **Re-measure when** a history-assembly or
  replay path lands here.
- **Verified 2026-08-04** against the Steering thinking page, fetched as raw markdown. **Recheck
  trigger:** the turn-validation relaxation narrowing, or the set of models that enforce a leading
  thinking block changing.

### I19: Restated external benchmark figure with no recheck trigger

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** a surface restating a named benchmark's score, ranking, or suite version — a model
  comparison table, a launch-figure list, a "state of the art on X" claim — carrying no recheck
  trigger. Benchmark figures are attested by an announcement at a moment: suites revise, vendors
  report against a different harness, and a later release reorders the table, so a figure with no
  stated re-derivation event silently becomes a claim about the past told in the present tense.
- **Remediate:** either point at the vendor's announcement and restate nothing, or keep the figure
  and attach the four-part record — the claim, the announcement it came from, the as-of date, and a
  trigger naming an observable event (a new frontier-model release, a suite version bump, a decision
  that would turn on the figure). Label the figures as launch-day snapshots where that is what they
  are; leaving them as history is a valid outcome and usually the right one.
- **Must NOT flag: a verbatim upstream baseline held for drift detection.** A vendored copy exists
  to be compared byte-for-byte against its source, so stamping it would corrupt the comparison it
  exists to serve — this is a genuine suppression, not a routing case, which is what distinguishes
  it from plugin-cache content and managed materializations: those are still flagged, and the
  finding becomes a routing recommendation to the owning repository. Flag the locally-owned surface
  that *restates* the figure, never the baseline it was restated from.
- **Must NOT flag:** a benchmark named as a pointer with no figure attached. A figure already
  carrying a trigger, whatever heading that trigger sits under.
- **Source:** none. No official page states that a restated benchmark figure needs a re-derivation
  event, which is why this check is `OPINION`-tier and off by default. The four-part shape it asks
  for is this monorepo's `docs/conventions/upstream-drift/README.md`; in a standalone install the
  four parts, not the path, are the requirement.

### I20: Prefilled assistant response

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `error` · Surfaces: all — `error` because
following the instruction produces a rejected request, the same consequence class as I17 and I18,
not because instances are expected to be common. **The unsupported model range is a Detect
condition, not a `Model scope` annotation**, for the reason I17 states.

- **Detect:** instruction text that tells a caller to prefill Claude's response — to supply a
  partial assistant message on the last turn so the model continues from it — where the run's
  resolved target model is a Claude 4.6 or later model, or Claude Mythos Preview. The classic uses
  are the tells: forcing a JSON or YAML shape, opening with `Here is the requested summary:` to skip
  preamble, steering around a refusal, resuming an interrupted generation, and re-injecting context
  as a pseudo-assistant reminder.
- **Remediate:** the technique is not deprecated advice but a rejected request — on current models a
  prefilled last assistant turn returns a 400. Replace it per use: state the output contract in the
  `user` turn or a structured-output facility for format control, ask directly for no preamble,
  prompt clearly rather than prefill past a refusal, and move context reinjection into the user turn
  or a tool.
- **Must NOT flag:** an assistant message anywhere other than the last turn, which is unaffected.
  **A document that names the technique or its tells in order to describe it as retired** — this
  row, a migration guide, a model-delta chapter — on the same audience test I8-b applies: a prefill
  prescribed inside an operative directive is a finding; a document *about* prefill is not.
  Instructions targeting an explicitly pinned earlier model, which still supports it.
- **Source:** prompting best practices, "Migrating away from prefilled responses" — "Starting with
  Claude 4.6 models and Claude Mythos Preview, prefilled responses (providing a partial assistant
  message for Claude to continue from) on the last assistant turn are no longer supported. Requests
  with prefilled assistant messages to these models return a 400 error… Earlier models continue to
  support prefills, and adding assistant messages elsewhere in the conversation is not affected."
- **Verified 2026-08-02** against that page, fetched as raw markdown; the standalone prefill
  technique page now redirects to the prompt-engineering overview. **Recheck trigger:** any change to
  that page, or the unsupported-model range moving.

### I21: Effort level pinned across a model change with no re-sweep

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all. Unscoped —
promotion gate MET: the calibration property is stated **unqualified** on a model-agnostic feature
page, not in a model guide. That sentence alone clears the gate; the effort page's Opus 5 subsection
is cited below only for the remediation's wording, and its placement inside a per-model section does
not narrow a property its own page states generally. **The model range below is a Detect condition,
not a `Model scope` annotation**, for the reason I17 states.

- **Detect:** a surface prescribing a **durable** effort level — a fleet-wide or project-wide pin, a
  "set effort to X and leave it" instruction, a level tied to a named model lane — that states no
  re-derivation when the pinned model changes. The effort scale is calibrated per model, so the same
  level name does not carry the same underlying value across models; a level measured against one
  model and carried to the next is a pin nobody re-measured.
- **The consequence varies by model, which is why the range sits in Detect.** Claude Code applies a
  model's default effort on first run of Fable 5, Opus 4.8, or Opus 4.7 "even if you previously set
  a different level for another model", holding it until an explicit effort choice — so a carried
  level there is overridden rather than silently obeyed. **Opus 5 has no such hold: "a level you
  previously set carries over"**, which is where a stale pin actually reaches the request.
  **Unresolved, and stated as such:** the page names `/effort` and `--effort` as *examples* of an
  explicit choice ("such as"), so whether a settings-file `effortLevel` pin releases the hold is not
  stated on any page read for this row. The row fires on the missing re-derivation regardless of
  model; the hold is severity context, never a fence.
- **Remediate:** attach the re-derivation to the pin — name the model the level was measured against
  and state that a model change re-opens it — or run the sweep. Upstream's own wording for the
  action: "If you carried effort settings over from an earlier model, run a fresh effort sweep on
  your evals rather than reusing them."
- **Must NOT flag: a prescription of `high` where `high` is the resolved target's default.** It is
  "Equivalent to not setting the parameter", so on a model that defaults to `high` such a pin
  carries no measured calibration that could go stale. **The exemption keys to the resolved target,
  never to the wording.** `high` is the default on every model that supports effort **except Opus
  4.7, which defaults to `xhigh`** — so when the run's resolved target is Opus 4.7 the exemption
  lifts and a `high` pin is a finding, **including a broad model-agnostic "always use `high`" that
  names no model at all**. That broad pin is the sharper case rather than the excluded one: written
  where `high` was the no-op default and then carried to a model whose default sits above it, it
  silently becomes a step-down nobody measured — this row's subject exactly. A resolved target
  always exists, because the skill body aborts rather than run against an unresolved one, so this
  fence never has to guess which side of it a surface falls on.
- **Must NOT flag: a per-task or single-turn effort choice** — "reach for `xhigh` on hard problems",
  `ultrathink`, `ultracode` — which selects a level for one piece of work rather than pinning one.
  This row is about durable pins.
- **Must NOT flag: `effort:` frontmatter and `effortLevel` settings keys as such.** Those are
  configuration values, and I17's discriminator applies unchanged: this row audits **instruction
  text**; the pin expressed as a config key is a config-mechanics finding belonging to
  `claude-config:audit`. Instruction text that merely *lives* in a config file stays here.
- **Must NOT flag: schema documentation and its illustrative samples.** A field table enumerating a
  config key's accepted levels, and the worked example beside it, exist to show the **shape** a
  consumer must fill in — the level in the sample is a placeholder demonstrating syntax, not a level
  this surface measured and prescribes. This is a separate fence from the one above and does not
  depend on it: the sample is quoted inside documentation prose rather than living in a config file,
  so the previous fence would not reach it. The fence ends where the demonstration does — a surface
  that documents the field **and then tells the reader which level to put there** is prescribing, and
  the prescription is in scope.
- **Must NOT flag: a document *about* the calibration property** — this row, a model-delta chapter, a
  verification record — on the audience test I8-b applies. Nor a level **reported as a named third
  party's practice** rather than prescribed to the reader: a practitioner's stated setup is
  `OPINION`-tier testimony, not a pin the surface owns.
- **Source:** model configuration — "The effort scale is calibrated per model, so the same level name
  does not represent the same underlying value across models" — stated with no model qualifier, and
  the whole basis for the check. The same page supplies the first-run hold with its Opus 5 exception,
  and the default carve-out: "The default effort is `high` on every model that supports effort,
  except Opus 4.7, which defaults to `xhigh`." Effort supplies the remediation's wording and `high`'s
  equivalence to omitting the parameter.
- **Verified 2026-08-03** against both pages, fetched as raw markdown (model configuration 83,644
  bytes; effort 21,744 bytes). **Recheck trigger:** the calibration property being restated as
  cross-model-stable, the set of models carrying a first-run default hold changing, or `high` ceasing
  to be the general default.

### I22: Model-routing doctrine with no baseline named

Tier `mechanical` · Authority `OPINION` · Severity `info` · Surfaces: all · Default **off**, enabled
by `--opinion`.

- **Detect:** a surface stating **first-party model-selection or routing doctrine** — a lane table
  ("wide reads to this model, mechanical fan-out to that one"), a "use model M for work of kind K"
  rule, a selection matrix restated from vendor pages — that names neither a baseline for the reading
  it was derived from nor an event that re-opens it. Model lineups, per-model guidance, and selection
  matrices are revised on every release, so lanes derived from one reading and written down without
  their provenance become a claim about a model generation that has since passed, told in the present
  tense.
- **Remediate:** name the baseline and the triggers. State which vet or reading the lanes came from
  and when, then list the events that re-open it — the pinned model changes, per-model guidance or
  its notes change, the selection-matrix rows change, a volatile figure a lane turns on drifts.
  **The action on a trigger is a targeted delta check against the named baseline, never a
  re-derivation from scratch** — that is what makes the trigger cheap enough to honor, and a trigger
  nobody can afford to run is not a control.
- **The consumer supplies its own baseline; this row carries none.** A catalog row naming a date or a
  vet would hand every consumer a foreign snapshot as their baseline, which is the precise drift this
  check exists to catch.
- **Must NOT flag: doctrine that ran no vet of its own.** A surface transcribing a named third
  party's stated practice, with author, source, and sync provenance recorded, has no baseline reading
  to name because it performed none. Flag first-party doctrine: lanes this surface's own authors
  chose. **This fence is narrower than it looks, and deliberately so** — a sync stamp tracks whether
  the *transcription* is current, not whether the transcribed advice still names a live model, so it
  does not make a stale lane recommendation fresh. The fence rests only on there being no vet to
  point at; the residual staleness is real and is the transcribing surface's to carry, not this
  row's to detect.
- **Must NOT flag: `model:` frontmatter and other configuration values**, on the same discriminator
  as I21 and I17 — those implement doctrine rather than stating it, and a config-mechanics finding
  belongs to `claude-config:audit`.
- **Must NOT flag: a pointer.** A surface routing the reader to the vendor's own selection page
  instead of restating lanes has nothing to go stale. Nor doctrine already carrying a baseline and
  triggers, whatever heading they sit under.
- **Why this is not I19, and not the catalog trigger.** I19 covers a restated *benchmark figure* and
  asks for the four-part record; it says nothing about lane assignments and nothing about how to
  *act* when a trigger fires — the delta-not-re-run discipline is this row's own contribution. The
  catalog-wide recheck trigger does not reach it either: that trigger governs **this catalog's**
  staleness against its Sources, not an audited surface's staleness against the pages its doctrine
  was read from.
- **Source:** none. No official page states that model-routing doctrine must name a baseline and
  delta triggers, which is why this check is `OPINION`-tier and off by default — the same footing as
  I19, and it adds no Sources entry for the same reason. The four-part shape it asks for is this
  monorepo's `docs/conventions/upstream-drift/README.md`; in a standalone install the four parts, not
  the path, are the requirement.

### I23: Context-budget directive to stop, summarize, or hand off

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `warning` · Surfaces: all · Model scope:
`fable-5` (sourced from that guide alone; promotion gate unmet).

- **Detect:** instruction text directing the model to monitor its own remaining context and to stop,
  summarize, hand off, trim its work, or start a new session **on that basis** — and instruction text
  or injected hook output that surfaces a remaining-context count to the model at all. The guide
  names the count as the usual trigger for the behavior, so the disclosure and the directive are one
  subject.
- **The discriminator is who decides, on what evidence.** A directive tells the model to judge its
  own window and act; a mechanism resolves the window from an instrumented signal and acts itself.
  Only the first is this row's subject.
- **Must NOT flag: a mechanism that gates on a measured signal.** A hook, gate, or workflow step that
  reads context state from an instrumented source and then blocks, injects, or routes on it is not a
  directive to the model, and it outranks the model's own initiative rather than competing with it.
- **Must NOT flag: a user-invoked skill whose purpose is the continuation itself** — a handoff
  writer, a continuation router, a compaction helper. The skill existing is not an instruction to
  watch the budget; a skill body that additionally tells the model to invoke it off a self-estimated
  window is.
- **Must NOT flag: a routing condition that selects between two forms of one deliverable.** "Use the
  short form where the full one would not fit" picks a shape; it does not stop the work. The subject
  is abandoning or truncating the work, never sizing an artifact to its container.
- **Must NOT flag: a budget surfaced to the human.** A status line, a report, or a cost dashboard
  renders to the operator rather than into the model's context, and no part of this row reaches it.
- **Must NOT flag: a document *about* the pattern** — this row, a model-adaptation delta chapter, a
  playbook stating the counter-steer — on the audience test I8-b applies.
- **Remediate:** remove the directive. Where the guarantee behind it is real, move it to a mechanism
  that gates on a measured signal, or state the counter-steer plainly — that a count alone is not a
  decay signal, because decay shows up in the output rather than in the number. Where the harness
  genuinely must surface a count, pair it with a reassurance rather than with an exit menu.
- **No pre-scan pattern is seeded.** The phrasing is patternable, but every instance attested so far
  falls inside a fence above, so there is no true positive to calibrate the false-positive rate
  against. This is I8-e's ground for the same decision.
- **Source:** Fable 5 guide, "Rare cases of context-budget concern" — "In very long sessions, Claude
  Fable 5 can occasionally suggest a new session, offer to summarize and hand off, or trim its own
  work. This is most often triggered when the harness shows a remaining-token countdown to the model.
  Avoid surfacing explicit context-budget counts where possible."
- **Verified 2026-08-08** against that guide, fetched as raw markdown (177 lines). **Recheck
  trigger:** a second model guide stating the claim — which would meet the promotion gate and unscope
  this row — or that section ceasing to name the remaining-token countdown as the trigger, which is
  what joins the disclosure arm to the directive arm.

### I24: Compressed-shorthand mandate on user-facing output

Tier `mechanical` · Authority `ANTHROPIC-DOCS` · Severity `info` · Surfaces: all · Model scope:
`fable-5` (sourced from that guide alone; promotion gate unmet).

- **Detect:** an instruction requiring the model's **user-facing** output to take a compressed
  shorthand form as a standing default — arrow chains, hyphen-stacked compounds, dropped articles,
  sentence fragments, or coined abbreviations. The guide names these as the shapes that make a long
  agentic session's closing message hard to follow, and names readability as the tie-breaker over
  brevity.
- **Must NOT flag: terseness between tool calls.** The guide blesses it in as many words — that text
  is the model thinking out loud, and brevity there is good. Only the message written for a reader
  who did not watch the work is in scope.
- **Must NOT flag: brevity by selection.** Dropping detail that would not change what the reader does
  next is the guide's own prescription. This row's subject is compression of the *writing*, never
  selection of the *content*.
- **Must NOT flag: an output style the user or operator explicitly selected.** Precedence puts a live
  request and standing user instructions above a project convention, so an opted-in register is the
  user's decision rather than a defect. Report it as an interaction with this row and leave it; where
  the style ships from a third party, the report routes to that owner rather than to a local edit.
- **Must NOT flag: a notation where the arrow carries meaning** — a state transition, a pipeline
  stage order, a type signature, a ref range. The subject is prose compressed into arrows, not arrows
  used as arrows.
- **Must NOT flag: a document *about* the pattern**, on the audience test I8-b applies.
- **Remediate:** scope the compression to working text and let the closing message be complete
  sentences with terms spelled out; or, where the compressed register is genuinely wanted, state it
  as an opt-in the user selects rather than as a standing default.
- **No pre-scan pattern is seeded.** The tokens this row names — arrows above all — are ordinary in
  documentation prose, so a pattern would mark nearly every surface, while the mandate itself is
  expressed in prose a grep cannot recognize.
- **Source:** Fable 5 guide, "Readability when communicating with the user" — "drop the working
  shorthand. Write complete sentences. Spell out terms. Don't use arrow chains, hyphen-stacked
  compounds, or labels you made up earlier … If you have to choose between short and clear, choose
  clear." The between-tool-call fence is that section's own opening — "Terse shorthand is fine between
  tool calls (that's you thinking out loud, and brevity there is good)" — and the
  selection-not-compression fence is "Strong instruction following", which keeps output short by
  "being selective about what you include (drop details that don't change what the reader would do
  next), not to compress the writing into fragments, abbreviations, arrow chains … or jargon."
- **Verified 2026-08-08** against that guide, fetched as raw markdown (177 lines). **Recheck
  trigger:** a second model guide stating the claim, which would meet the promotion gate and unscope
  this row.

---

## Stopping condition

Authority `OPINION` · applies to I6 and I8 · **enabled by default**, opt out with
`--no-stopping-condition`.

Neither I6 nor I8 carries an a-priori bound: I6's only escape is a rewrite concession and I8's
remediation is unconditional, so both trim without a floor. This rule **withholds** findings rather
than emitting them, which is why it inverts the `OPINION` default above — disabling it does not make
the audit more conservative, it removes the only bound on two trimming checks and makes both strictly
more aggressive.

- **Withhold** an I6 or I8 proposal where the instruction guards a high-consequence area: a safety
  gate, an irreversible or destructive action, a security or permission boundary, an external
  contract, or genuine ordering another step depends on. De-prescription is the default posture; it
  is not the posture in the places where being wrong is expensive.
- **Report every withholding** in the run's own section, naming the check it moderated and the
  ground. A silently suppressed finding reads as coverage.
- **Source:** none — the "except in highly important areas" carve-out appears on no official page,
  and it is the calibration knob the de-prescription guidance (I8's Fable 5 source) leaves unset.

---

## Output format

Findings are presented using the Phase D report table defined in the skill body
([SKILL.md](../SKILL.md)), one proposed diff per finding — the column set lives there and is not
restated here.

A clean audit ("No instructions flagged.") is a valid outcome. Behavioral-tier proposals are
always presented as proposals paired with the delete-and-watch follow-through, never as confident
removals.

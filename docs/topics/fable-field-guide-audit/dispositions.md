# Dispositions — Fable field guide vs `plugins/playbooks/skills/fable-5/`

Synthesis of the 14 S-unit ledgers into a single proposal. **Nothing here is applied.** No file
under `plugins/playbooks/skills/fable-5/**` was edited; the repo is on `main` with a clean tree.

Written in a clean context deliberately. Where this document contradicts a ledger, the contradiction
is stated in §4 with the evidence, not merged away.

## 1. How to read this

**Verdict** (per the brief): `covered` / `partial` / `missing` / `contradicted` /
`out-of-scope (audience)`.

**Disposition**, six values:

- **no change — covered** — the playbook states it; nothing owed.
- **no change — rejected** — a real gap, deliberately not remediated. Reason stated on the row.
  "Already roughly similar" is never the reason.
- **no change — source weaker** — the playbook is the stronger document and the correction runs
  toward the article. One row only (S10 c2); preserved in that direction.
- **amend** — a clause added to or narrowed at an existing owning section.
- **new section** — a new owning section, because no existing section can host it under meta-rule 2.
- **operator decision** — a structural choice with a named cost, presented as a decision rather
  than an edit. Four of these (§3).

Remediations are consolidated into **R1–R26** in §5 and referenced from the ledger rows in §6, so
one root cause appears once as a remediation and many times as evidence. **R13, R22 and R25 were
reclassified during synthesis** — as A2 (§7), D1 (§3) and D4 (§3) respectively — so those three
numbers are absent from §5 by design, not by omission. Every row from every
ledger survives as a row here, including the no-change ones — collapsing them would discard the
completeness property `coverage-reconcile.md` established.

Audit-originated findings (not derivable from any article claim) are quarantined in §7 so they
cannot be laundered into article-derived gaps.

## 2. The four dedup calls

### Judgment 1 — S2 Q4b, S5 C4, S13 F1: one root cause, and the ledgers put it in the wrong cell

**Call: one root cause, one owning home, two trigger sites. S2's ledger picked the wrong quadrant
cell.**

The three findings are one unstated assumption: *the playbook assumes the operator possesses an
evaluation function over the artifact space, and never tests that assumption.*

- S2 Q4b — the operator does not know the achievable range (the function's upper anchor).
- S5 C4 — the operator has no quality bar (the function itself).
- S13 F1 — the operator cannot compare candidates (the function applied).

That they are one thing is not an inference from similarity; the article supplies the proof. S2's
claim is the article's own Q4 text *"Do I know how good something can be?"*, and S13 is the
article's own worked illustration of that question failing (color grading). Same question, stated
abstractly in S2 and dramatised in S13. S5 C4 is the same lack under a third name.

**Where it lives.** `problem-framing.md:66` — not `:67`, where S2 placed it. `:66` is the cell whose
premise is exactly the assumption at issue: *"details the user cannot articulate but **will
recognize on sight**"*. S13's failure is that premise being false. S5 C4 is that premise being
false. S2's own remediation *text* — "name what the strong version looks like and what separates it
from the obvious one" — establishes a recognition standard, which is `:66`'s business, not `:67`'s.
S2 routed it to `:67` because the *article* files "how good can it be" under Unknown Unknowns, but
the playbook's `:67` is scoped to *"gaps neither of you has considered"* — things not thought of.
Not-knowing-the-ceiling is not an unconsidered gap; it is a missing recognition capacity.

Consequence: `:67` needs nothing from S2. Only S2's `SKILL.md:58` clause survives, folded into R3.

**Two trigger sites, one rule.** S2 argues the trigger must be frame-time; S13 argues an
owner-only edit "cannot fire at the moment S13 failed" and routes to `communication.md:80`. Both
are right, and the playbook already has the pattern for it: `communication.md:53` — *"This is the
same rule as the problem-framing chapter … one rule, two trigger sites."* Owner at
`problem-framing.md:66`, cite-forward gate at `communication.md:80` (re-entrant, fires whenever
options are presented). Not two homes. → **R3**.

**S13 F3 folds in.** S13 recommends it and the recommendation holds: an options message that gets no
selection back is R3's precondition firing late, and the correct move is identical. A fifth
`recovery.md` loop signal would open a second home for one rule.

**The split the ledgers did not make, and it changes the size of the fix.** R3 is *detection*
("notice they cannot evaluate, and say so"). The *clearing move* — transfer enough domain literacy
that they can judge — is a second doctrine (R4), and it is what S5 C8, S13 F4, and the
S4→S11 reader-expertise observation all converge on. They stand or fall on a two-lane test that R3
passes and R4 only conditionally passes; see §5 R4. If R4 fails that test, R3 ships alone and is a
materially smaller remediation than the three ledgers imply.

### Judgment 2 — S2 Q2, S5 C8, S7 C6: S7's "one missing mechanism" is refuted by S7's own body

**Call: two mechanisms, one remediation site. S5 C8 is not in this cluster at all.**

S7's bottom line asserts *"S2's gap and S7's C6 gap are one missing mechanism."* S7's own §"S2
handoff" says the opposite four paragraphs earlier: *"Adopting C6 closes roughly **half** — it
creates the event — while leaving the generator agent-side."* The body is right and the bottom line
overstates. Separability test: you can have the offered round without the volunteer slot — a batch
of agent-generated questions with no license to volunteer beyond them. That is exactly the state
`communication.md:65` already describes for accumulated questions.

- **Mechanism 1 — the solicitation event.** Nothing tells the agent to *offer* a round when the
  residue is large; every ask-rule (`communication.md:49-54`, `:63`, `:65`; `problem-framing.md:51`,
  `:52`; `SKILL.md:56`) biases toward fewer questions with no counterweight. → **R5**.
- **Mechanism 2 — the volunteer slot.** The question-generator is bounded by what the agent can
  read as a plausible reading of the request (`problem-framing.md:47`) or infer from domain priors
  (`:67`). An operator-held open question that surfaces as neither has no path in. Closing the round
  by asking what they know is still open is the only channel that admits it. → **R6**.

Both land after `communication.md:65`, both carry the same residue-is-large condition (unconditioned,
R6 is the question-noise `problem-framing.md:51` guards against and the job-offloading
`communication.md:63` prohibits). One site, two clauses, two mechanisms — recorded as two so a
future editor who drops R6 knows what they dropped.

**S7 C5 is a third thing**, not this mechanism's ranking axis as S7 claims. It is an ordering rule on
the *existing* ask path and is independently useful whether or not a round is ever offered. → **R7**.

**S5 C8 is in judgment 1's cluster, not this one.** Direction test: C6/Q2 run operator→agent
(elicit); C8 runs agent→operator (teach). C8's purpose clause — *"so that I can prompt better"* — is
capability transfer that makes *future* elicitation better. Downstream coupling, not the same
mechanism. S5's own ledger routes C4 into C8, which puts C8 in judgment 1. → **R4**.

### Judgment 3 — S11 Claim 3 and S13 F4: neither of S11's landings hosts F4, and F4 does not need one

**Call: they are different doctrines that both got labelled "explainer". S13's handoff framing is
refuted. F4's home is R4, not S11's.**

S11's surviving remediation is a **fourth simulated critic** at `reasoning-moves.md:128` — a
self-review lens, run in the agent's head, defined by the information the critic lacks, producing a
note about the artifact. S13 F4 is a **produced operator-facing output** that teaches a domain
mechanism. Three axis mismatches, any one of which is disqualifying:

| Axis | S11 Claim 3 (approver critic) | S13 F4 (explainer) |
|---|---|---|
| Mechanism | simulated critic, agent-internal | artifact emitted to the operator |
| Audience | third party who never had session access | the operator, in session |
| Purpose | does the artifact survive acceptance | does the operator acquire judgment |

Putting F4 in the critic roster would break the stated mechanism at `reasoning-moves.md:122` —
*"each one is defined by information they do NOT have"* — which S11 itself invokes to reject the
reader-expertise axis.

**Why S13's ledger framed it as a handoff, and why that framing is dead.** S13 wrote *"a second
trigger for whatever home S11 lands on"* before S11 had landed. S11 landed on a critic. S13's own
analysis supplies the correct routing: *"the explainer … is the mechanism by which the operator
acquires the evaluation criteria F1 requires."* F4 serves F1. F1's home is R3's owner. So F4 is R4 —
the clearing move for the unknown R3 detects — and it inherits R3's trigger sites rather than needing
one. **The home is picked: `problem-framing.md`, R4.** No second home; nothing double-counted.

### Judgment 4 — S14 C14.5a: independent, and a prerequisite for the rest

**Call: independent of judgments 1–3, and it must land first.**

Independence: C14.5a is a defect in *rationale ownership*, not a missing tactic. Judgments 1–3 add
tactics. Fixing them cannot fix C14.5a — it makes it worse. The cost asymmetry is currently
re-derived as a per-tactic justification clause at twelve sites (`problem-framing.md:3`, `:30`,
`:66`, `:69`, `:82`; `reasoning-moves.md:56`, `:60`, `:79`; `planning.md:49`, `:51`, `:55`;
`calibration.md:82`) with no owning section — a live meta-rule 2 violation. Every remediation in
this document is a new discovery move that would otherwise re-derive it a thirteenth through
twentieth time.

So C14.5a is not merely independent; it is **load-bearing for the batch**, and R1 is sequenced
first for that reason. With R1 in place, R3/R4/R5/R9/R11/R12 cite the economics instead of
restating them — which is also what keeps their combined prose weight tolerable.

One coupling to R2, applying S3's own argument: S3 established that only a `SKILL.md` core-doctrine
line is truly ungated, because chapters load on trigger (`SKILL.md:124`). The same reasoning applies
verbatim here. S14 marks C14.5a's `SKILL.md` line *"optionally"*; that is wrong by S3's logic —
a principle whose whole job is to generalize to moves the playbook has not enumerated cannot live
only in a trigger-gated chapter. **The `SKILL.md` line is mandatory, not optional.**

**S6 C2 mechanism (a)** — small spec changes imply drastically different implementations — is a
sub-clause of this principle, not its own remediation. It states *why* the price rises
monotonically with what has been built. Folded into R1.

## 3. Three decisions the operator owns

### D1 — The `problem-framing.md:60` trigger

**Six ledgers touch this line's adequacy; it is the audit's structural focal point.** Three propose
a fourth arm (S5 C1, S6 C1, S8 C2 conditionally); one routes around it (S13 F1, to
`communication.md:80`); one inherits it silently (S2 Q4b); one proposes replacing the architecture
that makes it necessary (S3 Row 4).

**This is one decision, not four.** Per the brief, the combined arm set, written out. Current text:

> TRIGGER: the task is large enough to consume a session or more, OR the user has disclosed
> inexperience with the domain, OR the request is confident in its center and silent at its edges…

Combined arm set (three existing + three proposed):

1. the task is large enough to consume a session or more *(existing)*
2. the user has disclosed inexperience with the domain *(existing)*
3. the request is confident in its center and silent at its edges *(existing)*
4. the work sits in a region of the codebase or domain neither you nor the user has worked in
   *(S5 C1)*
5. the acceptance criterion is one the user can only judge on sight *(S6 C1)*
6. describing what they want would cost the user more than pointing at an example of it *(S8 C2)*

**The cost, named: six disjuncts is "always" without saying "always".** Arms 4–6 are not narrow.
Arm 4 fires on most non-trivial work; arms 5 and 6 fire on most design and most under-specified
work. A trigger that fires on nearly everything is a standing rule wearing a trigger's clothes —
which is precisely S3 Row 4's finding, reached by a different road. Writing the six-arm set is
therefore an argument for S3's shape, not against it.

A second cost, structural: arms 5 and 6 are **cell-local conditions**, not whole-pass conditions.
Arm 5 belongs to the unknown-knowns cell's show-move; arm 6 belongs to the exemplar clause inside
that same cell. Promoting them to whole-pass disjuncts fires the entire four-cell pass — including
the blind-spot enumeration and the falsification twin — on a request whose only real need is one
sketch. Only arm 4 is a genuine whole-pass signal.

Three shapes, with costs:

- **(i) Adopt all six arms.** Cheapest edit, one line. Cost: the pass fires on nearly everything
  while the text still reads as selective, and two of the three new arms over-fire the pass relative
  to what they need.
- **(ii) Arm 4 only at `:60`; give the two show-moves their own trigger line.** Honest about which
  signal governs which move; arms 5 and 6 become conditions on the moves they actually gate, which
  is where S8's ledger independently pointed (*"the clause needs its own trigger line rather than
  inheriting `:60`'s"*). Cost is structural and should not be understated: extracting the show-moves
  from the quadrant list means **the four-cell taxonomy stops being the organizing structure of the
  section** — it becomes a classifier with two of its clearing moves living outside it. It also
  resolves the concentration problem in §5 (`:66` otherwise absorbs four new clauses).
- **(iii) Adopt S3 Row 4: a standing prior + `SKILL.md` bullet, and demote `:60` from a gate to a
  scaling rule.** Says out loud what (i) says implicitly. Cost: removes the one thing keeping the
  quadrant pass off small tasks; `problem-framing.md:5`'s exemption for single-edit mechanical fixes
  becomes the only brake, and it is narrow.

**Recommended: (ii)**, with S3's `SKILL.md` prior (R2) adopted alongside it. (ii) is the only shape
where each new signal gates the move it actually implies, and it is the only shape that also
relieves the `:66` concentration. Its structural cost is real and is the reason this is the
operator's call, not mine.

**A fix D1 does not deliver, stated so the disposition does not claim it.** S5 C2's headline case —
the non-code request (color grading) — reaches the quadrant pass only if the *chapter* is entered,
and chapter entry is `problem-framing.md:5`, which S5 explicitly declines to widen (blast radius
across all eight sections). A perfect arm set at `:60` leaves that case unreachable. The actual
mechanism blocking it is narrower than S5 diagnosed and is recorded as **A1** in §7: `SKILL.md:128`
and `SKILL.md:54` both state only three of `problem-framing.md:5`'s four arms, dropping the
because-clause catch-all — so an agent routing from `SKILL.md` never reaches the chapter for a
request that trips only that arm.

### D2 — `context/opus-adaptation.md`

**Reported as a decision. No replacement text proposed, per the brief.**

Four ledgers hit this chapter from two opposite directions, and the two directions are the decision.

**Over-inclusive.** S10 found `opus-adaptation.md:52` — *"write lessons and state to durable files as
you go (one lesson per note, why it mattered, delete notes proven wrong)"* — is general doctrine.
Verified: the containing section's preamble (`:45`) frames it as a Fable strength needing deliberate
practice on another model, so the *claim* is model-conditioned but the *payload* is not. `SKILL.md:146`
confines model-behavior claims to this chapter; nothing confines general doctrine *out* of it.
Consequence: the article's cross-attempt-learning purpose has no general-purpose owner anywhere.

**Under-inclusive.** Three ledgers found claims that are inherently identity-coupled and that this
chapter *still* cannot host, because it is scoped to one model's documented default deltas with
sources (`:3-7`, `:61`, `:63-68`):

| Claim | Unit | Why homeless |
|---|---|---|
| "the first model where quality is bottlenecked by clarifying unknowns" | S1-3 | a generational claim, not a default delta |
| "in sync with model behaviors" | S3 Row 3 | meaningless without naming a model; no capability-conditioned form exists |
| "the better models get, the more you can achieve" | S14 C14.1 | a cross-generation trend; the chapter holds one model's snapshot |

**The tension, stated not resolved.** The standing model-name constraint says skill content must not
hardcode model names because a named model is drift the moment the fleet moves. This chapter is
titled for a specific model version, addresses the reader as that model, and cites two
model-specific doc URLs whose own text warns *"Behavioral claims here decay with model/doc
revisions"*. The skill's directory name and `SKILL.md` framing carry the same coupling under the
provenance-named-playbook exception in `docs/PLUGIN-PHILOSOPHY.md`. Three unhostable claims plus one
misplaced payload is evidence about the chapter's boundary, not about those four claims.

**What is decidable now, and is separable.** Moving general doctrine *out* of the model chapter is
not replacement text for the chapter, so the brief's prohibition does not reach it. **R16** promotes
`:52`'s payload to `context-economy.md` and leaves behind only the genuinely model-conditioned
residue (that it needs deliberate practice rather than arriving by default). That is
disposition-ready and should not be held hostage to the three unresolvable claims.

The three unresolvable claims stay **rejected** (§6, rows S1-3, S3 Row 3, C14.1) with the reason
recorded, and are inputs to D2 rather than remediations.

### D3 — The contradictions against the divergent-spread tactic (S6 C4)

**The brief describes two contradiction sites. Verification reduces it to one, and the surviving one
is not fixed by an exception clause.** S6 is one of the two ledgers that shipped without an
independent review pass; its citations exist, but two of its *readings* do not survive checking.

**`calibration.md:61` — not a contradiction. No edit.** The rule reads *"SURVEY DEPTH = PURSUIT
DEPTH: enumerate options only as deep as you would actually pursue them … a comparison you will not
act on is decoration."* S6 reads a 4-direction spread as "3 directions you will not pursue." That
misreads both terms. The agent *will* pursue whichever direction the operator picks — pursuit is
deferred, not declined — and the spread is not a comparison the agent performs, it is a deliverable
the operator consumes. `:61` governs the agent's own survey depth; it never reaches an artifact set
built for someone else to judge. Carving an exception here would weaken a rule that is not wrong.
The scoping belongs in R9's own wording ("this is a deliverable, not an option survey"), at the new
rule's site, costing nothing at `calibration.md`.

**`problem-framing.md:66` — S6's "prescribes the singular" support is also a misreading.** S6 cites
*"a sketch, a throwaway prototype, or ONE fully worked example"* as the playbook prescribing a single
artifact. In context, "one" contrasts with a full build — the clause's own justification is *"at a
fraction of full-build cost"*, a scope-economy argument — not with N variants. And the first item,
"a sketch", carries no cardinality at all. `:66` does not forbid the spread. S6's `missing` verdict
survives (no rule licenses deliberate divergence *as an instrument*); its supporting citation does
not.

**`communication.md:82` — a real trigger collision.** `communication.md:80`'s trigger is *"any time
you present two or more options"*, which genuinely fires on a spread, and its rule — *"Mark exactly
one option as recommended, list it first"*, hardened at `:83` — is incompatible with the spread's
purpose. Naming a favourite front-loads the aesthetic judgment being elicited.

**Is an exception clause compatible with meta-rule 2?** No, and the reason is mechanical rather than
stylistic. Meta-rule 2 already resolves apparent conflicts — *"when two chapters appear to conflict,
the named owner's formulation governs"* — so an exception clause is redundant *for a reader holding
both texts*. But chapters load on trigger (`SKILL.md:124`). An agent that loaded `communication.md`
and never tripped `problem-framing.md`'s trigger holds one text, reads `:82` as unqualified, and
leads with a pick. Meta-rule 2's mechanism silently assumes co-presence that trigger-gated loading
does not guarantee. That is the argument against relying on owner-governs here — and equally the
argument against exception clauses, which create two more sites to keep in sync with the owner.

Three options, costs named:

- **(a) Narrow `communication.md:80`'s own trigger at its own site** — distinguish options the agent
  is asking the user to decide between on grounds the agent holds, from an elicitation spread whose
  whole purpose is a judgment only the user holds. One edit, at the owning site, no cross-chapter
  exception. Cost: `communication.md` acquires a concept ("elicitation spread") whose definition
  lives in `problem-framing.md` — a pointer dependency, which is the shape the playbook already uses
  at `:53` and `:92`.
- **(b) Ship R9 with a self-scoping clause and rely on meta-rule 2.** Zero edits outside the new
  rule. Cost: the trigger-gated-loading hole above — the collision stays invisible to an agent
  holding only `communication.md`.
- **(c) Do not add R9.** Zero risk. Cost: S6 C4 stays open, and the article's strongest
  prototyping tactic — divergence as the extraction instrument — has no agent-side form at all,
  along with S6 C6's consequence (brainstorm output belongs to the operator to react to).

**Recommended: (a).** It is the only option that resolves the collision at the site where an agent
actually encounters it, and it is a scoping narrowing rather than an exception licensing another
chapter's tactic. Its cost is one pointer, which is the playbook's own established shape.

### D4 — Scope-setting pass as an opener (S6 C5)

Genuinely two defensible postures, which is why it is a decision and not a remediation. S6 proposes
that when the request's scope boundary is not derivable from the request itself, the first move is a
scope-setting pass rather than the first edit. `planning.md:7` and `:11` encode a deliberate
opposite bias — *"Two yeses → act directly; a plan here is transcription"*, *"Planning here is
procrastination wearing rigor's clothes"*. S6 is right not to port the article's frequency claim
("almost every session"); even the narrow trigger form erodes an act-directly bias the playbook
installed on purpose. **Recommended: decline**, on the ground that `planning.md:7`'s two questions
already fire on exactly the "boundary not derivable" case (question 1 fails), and R2's standing
prior covers the posture without touching the act-directly threshold. Recorded as a decision rather
than a rejection because the operator may weigh the two postures differently.

## 4. Corrections to the ledgers

Stated rather than merged away, per the brief. Each was checked against the skill text, not inferred.

1. **S2 filed the achievable-ceiling gap in the wrong cell.** It belongs to `problem-framing.md:66`
   (recognition capacity), not `:67` (unconsidered gaps). Evidence: §2 judgment 1. `:67` needs
   nothing from S2.
2. **S7's bottom line ("one missing mechanism") is refuted by S7's own body ("closes roughly
   half").** Two mechanisms, one site. Evidence: §2 judgment 2.
3. **S13's F4 handoff ("a second trigger for whatever home S11 lands on") is dead.** S11 landed on a
   simulated critic, which cannot host a produced operator-facing output. F4's home is R4, which
   S13's own F1 analysis implies. Evidence: §2 judgment 3.
4. **S6 claims two contradictions; one survives.** `calibration.md:61` is a scope mismatch, not a
   contradiction. Evidence: §3 D3.
5. **S6's "the playbook prescribes the singular" misreads `problem-framing.md:66`.** "One" is
   scope economy against a full build, not a cardinality cap on variants. The `missing` verdict
   survives; the support does not. Evidence: §3 D3.
6. **S14 marks C14.5a's `SKILL.md` line "optionally"; it is mandatory** under S3's own
   ungated-vs-trigger-gated argument. Evidence: §2 judgment 4.
7. **S5 C2's diagnosis is directionally right but names the wrong blocker.** The chapter trigger
   `problem-framing.md:5` does carry a because-clause catch-all wide enough for a non-code request;
   what blocks it is that `SKILL.md:128` and `SKILL.md:54` both omit that fourth arm. Recorded as
   **A1**, an internal seam, not an article-derived gap.

## 5. The remediation set

Ordered by dependency. Every entry carries its constraint check; entries failing a constraint are in
§8, not here.

> **Line numbers are as-of HEAD.** Homes are identified by *section name*; the line number is a
> convenience pointer. The sequencing in §9 guarantees they go stale — R1 and R2 both edit
> `problem-framing.md:3` and shift every downstream citation in that file (`:52`, `:65`, `:66`,
> `:67`, `:69`, `:84-92`), and the same holds for `communication.md` (R5/R6 at `:65`, R19 before
> `:118`) and `context-economy.md` (R15–R17 in one section). Where a line number and a section name
> disagree after an earlier edit lands, **the section name governs**.

**Constraint legend.** MN = no model-name or version coupling (standing constraint). 2L = clears
`docs/PLUGIN-PHILOSOPHY.md`'s two-lane posture (no convention a consumer could reasonably do
differently, shipped as a baked-in default). MR = clears the four `SKILL.md` meta-rules.

### Tier 0 — prerequisite

**R1 — Give the cost asymmetry an owning section.** *(S14 C14.5a; absorbs S6 C2 mechanism (a))*
Home: `problem-framing.md:3`, whose opening paragraph already carries the adjacent frame-cost
economics, plus a mandatory core-doctrine line under `SKILL.md` "### Framing". Substance: every
discovery move is priced against the rework it prevents, and the price rises monotonically with how
much has been built on the unknown — which is why a criterion learned after building is an
implementation change rather than an edit. The twelve per-tactic clauses then cite rather than
re-derive. **MN ✓ 2L ✓ MR ✓** (fixes a live meta-rule 2 violation rather than creating one).

**R2 — Install the standing prior that requests arrive with unknowns.** *(S3 Row 4, subsumes Row 5)*
Home: `problem-framing.md:3` preamble **and** a bullet in the always-active `SKILL.md:52-58` block —
both, because only the `SKILL.md` bullet is ungated. Substance: a prior, not a procedure — a request
that reads complete is evidence about how it was written, not about what it covers; no trigger
firing is not evidence the request has no unknowns. Explicitly **not** a fifth `calibration.md`
tripwire: all four existing tripwires take the agent's own plan or theory as object, and a tripwire
about the *request* breaks that section's object-consistency (S3's own rejected alternative, upheld).
**MN ✓ 2L ✓ MR ✓**

> R1 and R2 both land in `problem-framing.md:3`. They are one edit to that paragraph, written
> together or not at all — separately they produce a preamble that says the same thing twice.

### Tier 1 — the operator-evaluability cluster

**R3 — Doctrine A: the operator's evaluation capacity is a clearable unknown.** *(S2 Q4b + S5 C4 +
S13 F1; absorbs S13 F3)* Owner: `problem-framing.md:66`, as a precondition on the show-move. Second
trigger site: `communication.md:80`, cite-forward in the `:53` shape. Plus a clause on `SKILL.md:58`.
Substance: the show-move assumes the user will recognize the answer on sight; test that assumption
before spending on candidates. When you cannot name a reference point for how good this class of
artifact gets, and neither can they, N candidates cost N times one and settle nothing — establish
what separates a strong version from an obvious one first, and put that in the frame. Trigger for
the owner site is frame-time, before the approach is chosen; stating that explicitly is what keeps
it compatible with `reasoning-moves.md:118` (*"taste selects among correct candidates while the
choice is open"*). **MN ✓** — capability-conditioned throughout. **2L ✓** — the reference point is
discovered per task, never shipped as a default. **MR ✓** — governs how the frame is built, not what
the work is.

**R4 — Doctrine B: transfer enough literacy that they can judge.** *(S5 C8 + S13 F4 + the
S4→S11 reader-expertise observation)* Home: `problem-framing.md:67`'s surface clause. Substance:
where the user has disclosed unfamiliarity, the surfaced list must carry enough explanation for them
to evaluate each item — what the question is, why it bites in this domain, what a good answer looks
like.

> **2L — conditional, and this is the load-bearing check on the batch's largest cluster.** The bar
> passes only in **functional** form ("enough that they can evaluate each item") and fails in
> **register** form ("introductory level", "define terms on first use", "avoid jargon"). A functional
> bar is self-scoping — it is zero work when the reader already can evaluate — and a consumer wanting
> otherwise is issuing a user instruction, which meta-rule 1 already outranks the playbook with. A
> register prescription is a convention a consumer could reasonably set differently, shipped as a
> default: the identical defect S8 correctly rejected in its five-tier reference-media ordinal.
> **Ship R4 in functional form only.** If the operator judges even the functional form to be
> register prescription, R4 dies — and R3 then ships alone as "notice and say so", a materially
> smaller remediation than the ledgers imply. That reduction is stated here rather than discovered
> later.

Tension to resolve at landing, not merged away: `communication.md:20` (*"include exactly what
changes what the reader does next"*) argues against teaching content that changes no immediate
action. R4's answer is that it *does* change the next action — it is what makes the operator's next
answer usable — but the two texts must be reconciled explicitly at one of the two sites under
meta-rule 2, not left to collide. **MN ✓ MR ✓** (meta-rule 4 does not block it: `:67` already
mandates a user-visible surface, so this is content depth, not compliance narration).

**R5 — Offer the round when the residue is large.** *(S7 C6)* Home: after `communication.md:65`.
Substance: when the residue is several load-bearing questions at once, say so and offer the round
before starting rather than metering them out mid-work; the ask-sparingly bias exists to stop
question-noise, not to make you build on guesses you could have retired in one exchange.
**MN ✓ 2L ✓ MR ✓** (meta-rule 4 clean — this emits substance, not a named ceremony; S7 is right that
a ritual called "the interview" would not survive `SKILL.md:18`).

**R6 — The volunteer slot.** *(S2 Q2 + S7's additional candidate)* Same site as R5, distinct clause,
same residue-is-large condition. Substance: close the round by asking what they know is still open
that you did not ask about. The condition is load-bearing, not decoration — unconditioned it is
exactly the question-noise `problem-framing.md:51` guards against and the job-offloading
`communication.md:63` prohibits. **MN ✓ 2L ✓ MR ✓**

**R7 — Rank the ask path by downstream invalidation.** *(S7 C5)* Home: `problem-framing.md:52`'s
load-bearing branch. Substance: order what remains by how much downstream work the answer
invalidates, not by how differently the readings read; the ambiguity that changes the shape of the
design outranks one that changes a value inside it. Cite `planning.md:35-36` rather than duplicate
it. Use "downstream work invalidated", never "architecture" — the chapter also covers bug fixes, and
the transferable form already matches `SKILL.md:64`. **MN ✓ 2L ✓ MR ✓**

**R8 — Elicit an undisclosed starting point.** *(S4 (d))* Home: `problem-framing.md:69`, which
already owns the scaling. Substance: when the starting point is undisclosed *and* the two poles would
produce materially different pass widths, ask for it in one line before running the pass. The gate is
load-bearing: ungated it collides with `problem-framing.md:51` and with the decide-or-ask ordering at
`communication.md:49-54`. Home stays in `problem-framing.md` with a cite from `communication.md` —
not a fifth ask-category, which would put operator state in a list whose four members are all
user-values categories. **MN ✓ 2L ✓ MR ✓**

### Tier 2 — the show-moves

> **Concentration warning.** R3, R9, R10 and R12 all land on `problem-framing.md:66`, a bullet
> already at ~90 words. Applied as written, the unknown-knowns cell becomes the largest single bullet
> in the playbook and stops reading as a cell in a four-cell taxonomy. This is the same pressure D1
> option (ii) relieves: promoting the show-moves to their own section gives these four clauses a real
> home instead of a bullet. **The two decisions should be taken together.**
>
> **If D1(ii) is taken, `problem-framing.md:66` as cited stops existing.** The home for R3, R9, R10
> and R12 is then the new show-moves section, and R3's owner-site trigger moves with it. The
> doctrine follows the show-move wherever it lands; the four remediations are unchanged in substance.

**R9 — License the divergent spread as an elicitation instrument.** *(S6 C4; absorbs C6's
consequence)* Home: `problem-framing.md:66`. Substance: when the criterion is on-sight-only, several
deliberately different directions beat one refined candidate, and the divergence must run along the
dimension the operator cannot articulate rather than being N variations of one idea; the spread is a
deliverable, not an option survey. **Gated on D3** — needs (a) or (b) resolved first.
**MN ✓ 2L ✓ MR** — the self-scoping "deliverable, not a survey" clause is what keeps
`calibration.md:61` untouched. Also fixes S6's vocabulary hazard: the playbook's "taste"
(`reasoning-moves.md:101-118`) is the *agent's* code-quality signal; the article's is the
*operator's* aesthetic. R9's wording must not reuse the word.

**R10 — Name the elicitation artifact as a distinct artifact kind.** *(S6 C3)* Home:
`problem-framing.md:66`; one-line pointers at `execution.md:124` and `reasoning-moves.md:166`.
Substance: its completeness bar is "does it surface the criterion", not "does it work"; the
what-should-exist pass and the debris sweep apply to the real change; it is retired by explicit
decision, not by sweep. Without this, three standing rules read a deliberately-unwired artifact as a
defect — `reasoning-moves.md:166` (every omission scores as a finding), `problem-framing.md:98-107`
(a prototype has no survivable behavior to name), `execution.md:133` (a single-file mock is
scratch-file-shaped and gets swept). **MN ✓ 2L ✓ MR ✓** (pointers, not restatements).

**R11 — Re-run the ambiguity sort on the show-moves' residue.** *(S7 C1)* Home: after
`problem-framing.md:67`, closing the quadrant pass. Substance: the show-moves convert unknown knowns
into stated ones, and the newly stated ones are load-bearing by construction — sort them. Fixes a
real ordering gap: `problem-framing.md:45` fires the sort at frame time, *before* the show-moves
run, and nothing schedules a second pass over what they produce. **MN ✓ 2L ✓ MR ✓**

**R12 — Reference fidelity principle, cross-language port, and ask ordering.** *(S8 C4 + C5 + C6 +
C7)* Home: `problem-framing.md:66`'s exemplar clause. Three clauses:

- **Fidelity as a principle, never a ranked list** — take the highest-fidelity form available: the
  form that carries naming, structure and edge-case handling rather than implying them. S8's own
  rejection of a five-tier ordinal (implementation > schema > prose > diagram > image) is upheld — a
  design-led consumer could reasonably rank a component spec above a tangential implementation, so
  the ordinal is a baked-in default in a skill declared agnostic. **This clause subsumes C5**; no
  separate text.
- **Cross-language** — a reference in a different language, framework or stack still qualifies; what
  ports is the semantics and structure, never the syntax; form is governed by the execution
  chapter's "Write in the codebase's dialect, not yours". This also resolves the reconciliation seam
  S8 found by construction: without it, an agent following `:66` and an agent following
  `execution.md:55` produce different diffs from the same reference.
- **Ordering the ask** — search the codebase first; if nothing matches, ask for a reference *naming
  the aspect you need from it* (behavior, structure, or interface) rather than accepting the pointer
  alone.
**MN ✓ 2L ✓ MR ✓**

### Tier 3 — independent, single-home

**R14 — Decisions-first plan preface.** *(S9 C2 + C3 + C4 + C5)* Home: a short new section in
`planning.md` after "The shape of a useful plan", plus the presentation job added to the charter
sentence at `planning.md:3`, plus one clause at `:13` naming the durable tier's dual purpose (it
currently justifies itself solely by context loss). **Shape is load-bearing: a second view over the
same plan, never a re-sort.** Re-sorting steps by revision likelihood breaks `planning.md:29` (every
boundary a safe stopping point) and contradicts `SKILL.md:64` (sequence by risk). Substance: lead the
presentation with the choices the user would most plausibly make differently — data shapes,
interfaces other work will bind to, anything user-observable — ranked by the rework a late veto
would cause; steps whose only content is a behavior-preserving mechanical transformation go last in
the presentation. **Guardrail, must be explicit:** presentation prominence is not rigor. A step
placed last is not verified less — `planning.md:65`, the census at `:71-85`, and the verification
floors at `SKILL.md:89-92` apply unchanged. The article's *"I trust you on that part"* is an operator
allocating *their* attention, not the agent lowering its own bar. Home upheld against the
`communication.md` alternative: `communication.md`'s triggers are all message-composition triggers
that would have to be widened to reach an artifact. **MN ✓ 2L ✓ MR ✓**

**R15 + R16 + R17 — one edit to `context-economy.md` §"Externalize conclusions when they
stabilize".** Three clauses from S10, landing in one section:

- **R15 — phase-boundary reset** *(S10 a2)*: a phase completes and its output is a compiled artifact
  the next phase consumes; the artifact, not your context, is the handoff — recommend continuing in
  a clean context seeded with it, because the exploration that produced the artifact is now dead
  weight competing with execution. Every existing reset trigger (`:40`, `:47`, `:64`) is keyed to
  loss or degradation; none to successful completion. `orchestration.md:44` is the same mechanic with
  the opposite subject (it seeds a subordinate while the parent keeps its context) and citing it as
  coverage would paper over that.
- **R16 — promote the lesson-note purpose out of `opus-adaptation.md:52`** *(S10 c1; see D2)*: a
  second purpose alongside loss insurance — decisions made and why, so a later attempt inherits them
  instead of re-deriving. A **promotion**, not an addition. Leave behind only the model-conditioned
  residue.
- **R17 — the work note's disposition at task end** *(S10 internal seam)*: survives as a
  deliverable, is folded into the change description, or is removed — so `execution.md`'s debris
  sweep has an unambiguous answer. Currently `context-economy.md:37` mandates the note and never says
  where it lives, while `execution.md:128` sweeps "every file modified or untracked beyond your
  census baseline" and `:133` names scratch files in the project tree as debris, with no carve-out
  either way. The alternative — an exception at `execution.md:133` — is worse: it puts the note's
  lifecycle in a chapter that does not own it.
**MN ✓** **2L ✓** — say "durable artifact", never a specific filename; the article's
`implementation-notes.md` is exactly the baked-in default the two-lane clause forbids. **MR ✓**

**R18 — A fourth critic: the approver.** *(S11 Claim 3)* Home: the critic roster at
`reasoning-moves.md:120-128`, whose ownership is asserted at `:126` and whose bar at `:128` is
already open-ended (*"run every critic whose audience this artifact actually has"*). Defined, per
`:122`, by the information they lack: holding only the artifact, no session access, and deciding
whether to *accept* the work rather than merely understand it. Its concrete note: whether the
artifact shows the domain's standard failure questions were considered, or leaves the approver to
ask them. **2L ✓ only if format-agnostic** — naming Slack, a PR description, a design doc, or a demo
GIF bakes in a convention a consumer could reasonably do differently. **MN ✓ MR ✓** (placing this in
`communication.md` instead *would* collide with the roster's declared ownership).

**R19 — Name the behavior that changed in code you did not edit.** *(S12 R1)* Home:
`communication.md` §"Write the closing message for a reader who wasn't watching", before the closing
test at `:118`. Substance: an existing handler, dispatcher, or call site now reached under new
conditions; a default that now resolves differently. The diff shows the lines you wrote, never the
paths they activate. This completes the existing test at `:118` — *"could someone holding only this
message **and the diff** act correctly?"* — which currently leans on the diff for information the
diff structurally cannot carry. Adds no new work: the agent already holds the caller walk
(`verification.md:58`) and the consumer census (`planning.md:73-83`). Falsifiable — a named path, or
an explicit "none". Optional secondary: a one-line cross-reference from `execution.md:92`.
**MN ✓ 2L ✓ MR ✓** Records the direct tension S12 found: `communication.md:20` cuts "file-by-file
recaps the version-control diff already shows", which presumes the diff is a sufficient record;
R19's content is precisely what it is not, and the two must be reconciled at the site.

**R20 — Route feasibility unknowns out of the ambiguity sort.** *(S13 F2)* Home:
`problem-framing.md:65`, one pointer line. Substance: unknowns of the can-this-work-at-all shape route
to `planning.md` §"Order by risk and information gain". This survives meta-rule 2 because it is an
**active misroute**, not a chapter-location preference: `:65` sends the known-unknowns cell to a
*named* section (`:43-56`) that handles request-*reading* ambiguity only, so a feasibility unknown
lands where it structurally cannot be processed. Pointer-not-copy; no new doctrine —
feasibility-first ordering is already fully owned by `planning.md:35` and `:41-43`, and giving it a
second home would violate meta-rule 2. **MN ✓ 2L ✓ MR ✓**

**R21 — Post-delivery diagnostic ordering frame-attribution before execution-attribution.**
*(S14 C14.2 + C14.3)* Home: a new section in `problem-framing.md` plus a routing row in
`SKILL.md:126-140`. Trigger: a multi-step or session-spanning deliverable is returned as wrong or
not-what-was-meant. Substance: before re-executing, diff the complaint against the recorded frame and
re-run the quadrant pass; attribute to an uncleared quadrant cell before attributing to execution,
because re-executing against an unchanged frame reproduces the same error at full cost. **New section
justified:** every constituent move exists but each is triggered by a signal the agent observes
mid-flight (`planning.md:100-106`, `calibration.md:80-89`, `recovery.md:66-73`,
`reasoning-moves.md:58-64`, `execution.md:104`), and `communication.md:96-102` — the playbook's live
response to this condition — is execution-level (widen the class, sweep siblings) with nothing
routing attribution to the frame. Owner confirmed as `problem-framing.md` over `recovery.md`, whose
declared scope is self-observed stuck states, not returned deliverables. **MN ✓ 2L ✓ MR ✓**

**R24 — Make the scope bound bidirectional.** *(S6 C7)* Home: `problem-framing.md:84-92`, by pointer,
not new doctrine — the exclusion list has an upper bound (`:88`) and a lower one (the blind-spot pass
at `:67`); a scope stated without testing both is one bound short. The too-wide direction is heavily
armed (`:84-92`, `execution.md:108-122`, `communication.md:61`); the too-narrow direction is named
outright in exactly one place, `opus-adaptation.md:17`, which is model-scoped by design and cannot
serve as the general home — so the general case is genuinely uncovered. **MN ✓ 2L ✓ MR ✓**

### Tier 4 — low priority

**R23 — Parameterize the blind-spot checklist by domain.** *(S5 C2)* Home: `problem-framing.md:67`.
Substance: mark the enumerated probes (failure handling, concurrency, migration, operational story,
second consumer) as the software instance of a general move, and name one non-code exemplar axis so
the checklist reads as domain-parameterized rather than exhaustive. **Partial fix only** — see D1's
closing note and A1: the request still has to reach the chapter. **MN ✓ 2L ✓ MR ✓**

**R26 — An external-source branch in the check/skip matrix.** *(S4 (c))* Home: `calibration.md`,
which owns check/skip and recall grading. Substance: a version- or ecosystem-shaped claim no local
artifact can settle routes to an authoritative external source *when the session has one*, with
explicit fall-through to the downgrade-to-unverified move at `calibration.md:35` when it does not.
**2L / design boundary ✓ only in that form** — naming a tool or assuming network access violates the
design boundary. **Counter-argument recorded, and it is strong:** `calibration.md:35` and `:38`
already license downgrade-or-escalate tool-agnostically, and `:16` already lists "doc fetch" among
lookup options, so what is missing is only a *route to* an external source for a non-identifier
claim — arguably stylistic rather than behavioral. **MN ✓ MR ✓** Lowest priority in the set; a
defensible decline.

## 6. The claim ledger

One row per source claim. `→ Rn` points at §5; `→ Dn` at §3.

### S1 — map and territory

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| S1-1 map vs territory distinction | covered | `problem-framing.md:62`, `:75`, `:3`, `:28`; `planning.md:19` | no change — covered |
| S1-1 the *label* "map and territory" | missing | absent (incidental use `problem-framing.md:73`, `debugging.md:63`) | no change — rejected: a metaphor with no trigger is prose bloat in standing instructions; the substance is owned |
| S1-2a "unknowns" names the gap | covered | `problem-framing.md:58`, `:62`; `SKILL.md:58`; `planning.md:33-37` | no change — covered |
| S1-2b agent decides from best guess | covered (stronger) | `communication.md:45-54`, `:67-76`; `problem-framing.md:51`; `SKILL.md:96` | no change — covered |
| S1-2c more work → more unknowns | partial | `problem-framing.md:60`, `:69`, `:82`; `planning.md:7-13` | no change — rejected: descriptive, no trigger, no action; its actionable consequence is already owned |
| S1-3 quality bottlenecked by clarifying unknowns — mechanism | covered | `problem-framing.md:62`, `:66-67`; `SKILL.md:58`; `communication.md:65` | no change — covered |
| S1-3 …stated as a generational claim | partial | `opus-adaptation.md:9-59` carries no unknown-clarification delta | no change — rejected: inherently identity-coupled; no legal home that does not embed a model name → **D2** |
| S1-4 planning ahead is not enough | covered | `planning.md:98-108`; `recovery.md:20-26`; `execution.md:100-112`; `problem-framing.md:82` | no change — covered |
| S1-5 iterative discovery before/during/after | covered | before `problem-framing.md:58-82`; during `:45`, `reasoning-moves.md:58-64`; after `reasoning-moves.md:164-168`, `verification.md:51-62` | no change — covered |
| S1 residue: "after" targets the operator's understanding, not the artifact | partial | no rule converts a post-implementation finding into an update of the operator's model | amend → **R4** (the same doctrine, arriving from S1's angle) |

### S2 — the four quadrants

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| Q1 known knowns | covered | `problem-framing.md:64` | no change — covered |
| Q2 known unknowns | covered | `problem-framing.md:65` → `:43-56` → `communication.md:45-65` | no change — covered |
| Q2 routing asymmetry (operator-held question has no path in) | missing | the generator is bounded by `problem-framing.md:47` readings and `:67` domain priors | amend → **R6** (§2 judgment 2 — a distinct mechanism from R5) |
| Q3 unknown knowns | covered (stronger) | `problem-framing.md:66`; `SKILL.md:58` | no change — covered |
| Q4(a) what haven't I considered | covered | `problem-framing.md:67`, `:69`; `SKILL.md:58` | no change — covered |
| Q4(b) do I know how good it can be | missing | absent; near-miss "quality ceiling" at `:62` is a motivation clause, not this claim | amend → **R3**, filed at `:66` not `:67` (§4 correction 1) |

### S3 — unknown-reduction is the skill

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| Row 1 best operators carry few unknowns | out-of-scope (audience) | agent-side counterpart at `problem-framing.md:69` | no change — describes the human's epistemic state |
| Row 2 in sync with the codebase | covered | `execution.md:15-26`, `:21`; `reasoning-moves.md:180` | no change — covered |
| Row 3 in sync with model behaviors | out-of-scope (structural) | quarantined by `SKILL.md:146`, `:17`; `opus-adaptation.md:7`, `:63-68` | no change — rejected: no satisfying text exists that does not name a model → **D2** |
| Row 4 "they also assume unknowns" (the posture) | partial | present but gated: `problem-framing.md:5`, `:60`, `:73`; `SKILL.md:58` carries the gate verbatim | amend → **R2** |
| Row 5 reducing unknowns is the skill | partial | reduction moves at `:66-67` reachable only through `:60` | subsumed by **R2** |
| Row 6 planning for unknowns is the skill | covered | `planning.md:33-37`, `:49`; `reasoning-moves.md:56`, `:80` | no change — covered |
| Row 7 the skill is learnable over time | out-of-scope (audience) | — | no change — the agent has no cross-session lever; encoding one is user-preference content (meta-rule 1) |

### S4 — specificity balance, discovery accelerator, starting point

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| (a) too-specific → agent follows past the pivot point | covered | `problem-framing.md:22-41`, `:111-122`; `planning.md:98-108`; `SKILL.md:65` | no change — covered |
| (a) too-vague → industry-default assumptions | covered | `calibration.md:70-78`; `execution.md:36-42`, `:55-60`; `communication.md:91` | no change — covered |
| (b) remedy for failing both ways | covered | `problem-framing.md:58-69`, `:71-82` | no change — covered |
| (b) the both-ways causal diagnosis | out-of-scope (audience) | — | no change — rejected: rationale addressed to the prompt-writer; changes no agent action beyond `:58-82`; adding it is untriggered prose (meta-rule 4) |
| (c) codebase search | covered | `problem-framing.md:77`; `debugging.md:27`; `execution.md:41` | no change — covered |
| (c) broader topic knowledge | covered | `problem-framing.md:67` states the asymmetry outright | no change — covered |
| (c) faster iteration from failure | covered | `debugging.md:10` | no change — covered |
| (c) external research | partial | machinery at `orchestration.md:10`, `:44`, `calibration.md:16`; no route *to* a source | amend → **R26** (low; counter-argument recorded) |
| (d) operator's starting point, when disclosed | covered | `problem-framing.md:60`, `:69` | no change — covered |
| (d) …when undisclosed | missing | both hooks gate on the word "disclosed"; nothing licenses asking | amend → **R8** |
| (d) "let it work with you like a thought partner" | partial | `problem-framing.md:66` gives the moves, not the stance | no change — rejected: a stance without a trigger or an observable is not an instruction |
| (d) "disclose your experience" (imperative to the human) | out-of-scope (audience) | — | no change |

### S5 — blind spot pass

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 trigger: new part of the codebase | partial | `problem-framing.md:60`'s three arms exclude it; `:73` gates the falsification pass, opposite direction | amend → **D1** arm 4 |
| C2 trigger: unfamiliar non-code work | partial | wording domain-agnostic (`:67`, `:69`); probes software-shaped; chapter entry `:5` code-shaped | amend → **R23**, partial only; blocked by **A1** |
| C3 not knowing what questions to ask | covered | `problem-framing.md:67`; `SKILL.md:58` | no change — covered |
| C4 not knowing what good looks like | partial | `:66` and `:94-109` set a bar for the *agent*; `:66`'s exemplar move presumes the user knows a good reference | amend → **R3** (§2 judgment 1) |
| C5 not knowing what historical work exists | covered | `problem-framing.md:77`, `:78` | no change — covered (meta-rule 2: another section still counts). Caveat recorded: discovered, never relayed to the operator — that relay is **R4** |
| C6 not knowing what potholes to avoid | partial | `problem-framing.md:80`; `reasoning-moves.md:70-82` — both agent-internal design adversaries | no change — rejected: the premortem's disposal gates (blocked/fix-now/accept) have no "tell the operator this is domain lore" arm, and adding one duplicates **R4**'s transfer |
| C7 find the operator's unknown unknowns | covered | `problem-framing.md:67` names the move literally | no change — covered |
| C8 explain them back so they can prompt better | partial | `:67` mandates surfacing but as a bare list, terminating at "before locking the frame" | amend → **R4** |
| C9 operator context shapes the pass | covered | `problem-framing.md:69`, `:60` | no change — covered |

### S6 — brainstorms and prototypes

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 trigger: area dense in unknown knowns | partial | doctrine at `:66`; gated by `:60`, which the button-in-a-frame case never trips | amend → **D1** arm 5 |
| C2 cost asymmetry, general | covered | `problem-framing.md:66`, `:69`, `:3`, `:82` | no change — covered |
| C2(a) small spec change → drastically different implementation | missing | closest is `planning.md:104` (the consequence, never the cause) | amend → **R1** (folded in as the principle's mechanism) |
| C2(b) agents revert prior changes poorly | covered (unused premise) | `execution.md:106`, `:103` | no change — covered; **R1** spends the premise it currently states without using |
| C3 the throwaway's value is what it omits | partial + latent contradiction | `reasoning-moves.md:166`, `problem-framing.md:98-107`, `execution.md:133` each read a deliberately-unwired artifact as a defect | amend → **R10** |
| C4 several parallel design approaches | missing | no rule licenses divergence as an instrument | amend → **R9**, gated on **D3**. Support corrected: `:66` does not prescribe the singular (§4 correction 5) |
| C4 contradiction 1 — `calibration.md:61` | **not a contradiction** | survey depth governs the agent's own pursuit; a spread is a deliverable | no change — **D3**; S6's reading refuted (§4 correction 4) |
| C4 contradiction 2 — `communication.md:82` | contradicted | trigger at `:80` fires on a spread; `:82`+`:83` front-load the judgment being elicited | operator decision → **D3(a)** recommended |
| C4 visual/UI design as the canonical instance | missing | `:66` names "taste, workflow fit" only | subsumed by **R9** |
| C5 almost every session opens with brainstorming | out-of-scope (audience) + missing | `reasoning-moves.md:7` classifies but does not open; tension with `planning.md:7`, `:11` | operator decision → **D4**; recommended decline |
| C6 agent finds missed approaches / misses the forest | covered | `problem-framing.md:67`, `:118`; `reasoning-moves.md:134-152`, `:11` | no change — covered |
| C6 consequence: brainstorm output is the operator's to react to | missing | — | subsumed by **R9** |
| C7 guards against both too-narrow and too-wide scope | partial (one-directional) | too-wide `:84-92`, `execution.md:108-122`; too-narrow only `opus-adaptation.md:17` | amend → **R24** |

### S7 — interviews

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 interview follows brainstorming, aimed at the residue | partial | `problem-framing.md:52` has the shape but a tool-call antecedent; `:66-67` are per-cell routing, not a sequence | amend → **R11** |
| C2 the agent interviews the operator | partial | capability covered `communication.md:45-65`; the named ritual is not | no change — rejected as a ritual: a ceremony named "the interview" collides with meta-rule 4. The real gap is C6 |
| C3 operator-supplied context guides the questions | out-of-scope (audience) | analogues at `problem-framing.md:60`, `:69`; `communication.md:65` | no change |
| C4 one question at a time | partial (deliberate divergence) | `communication.md:65` conditions it on dependency | no change — rejected: the playbook's form is strictly better-specified, and a live operator instruction outranks it (meta-rule 1). Recorded as intentional divergence |
| C5 prioritize by architecture impact | partial (ranking exists, not on the ask path) | `problem-framing.md:52` (divergence, not blast radius); `planning.md:33-37`; `reasoning-moves.md:154-158` | amend → **R7** |
| C6 questions offered proactively, not as a last resort | contradicted in posture | `communication.md:49-54`, `:63`, `:65`; `problem-framing.md:51`, `:52`; `SKILL.md:56` — uniformly toward fewer questions | amend → **R5** |

### S8 — references

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 trigger: lacking the vocabulary | covered | `problem-framing.md:66`; `SKILL.md:58` | no change — covered |
| C2 trigger: describing costs more than it's worth | partial | `:66` conditions on inability, never on cost; `:60` gates the pass | amend → **D1** arm 6 |
| C3 the fix is a reference | covered | `problem-framing.md:66`, `:77`; `execution.md:21` | no change — covered |
| C4 reference media are ranked | missing | no ranking and no enumeration anywhere | amend → **R12**, as a *principle*; the five-tier ordinal is rejected on two-lane grounds |
| C5 source conveys richer detail than a screenshot | missing | `:66` compares prose-to-artifact, a different axis | subsumed by **R12** |
| C6 cross-language references | missing | zero hits; `:66` is source-unbounded but silent on what survives the crossing | amend → **R12** |
| C7 ask-the-user is agent-initiated | covered | `problem-framing.md:66` parenthetical; `SKILL.md:58` | no change — covered; ordering and "what to ask for" → **R12** |

### S9 — implementation plans

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 ask for a plan when ready to implement | covered (stronger) | `planning.md:5-15`, `:3` | no change — covered |
| C2 the plan exists to be reviewed | partial | `planning.md:12`, `:13` (agent re-readability), `:61`; `communication.md:76` | amend → **R14** (`:13` dual-purpose clause) |
| C3 foreground the parts most likely to change | missing | `planning.md:3` charter omits presentation; `:17-37` covers fields, not attention | new section → **R14** |
| C4 surface what I might need to alter | partial | `communication.md:67-76`, `:51`, `:58-61` — decision grain, never a plan's layout | subsumed by **R14** |
| C5 bury mechanical refactoring at the bottom | partial | separation doctrine at `planning.md:30`, `execution.md:90`; deprioritization absent | subsumed by **R14**, with the rigor guardrail explicit |
| C6 write the plan in HTML | out-of-scope (audience) | — | no change — output format is *what* is produced (meta-rule 1) |

### S10 — fresh session and implementation notes

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| (a1) planning output becomes a durable artifact | covered | `planning.md:13`, `:29`, `:108`; `context-economy.md:37` | no change — covered |
| (a2) deliberate fresh session at a clean phase boundary | partial | `context-economy.md:40`, `:47`, `:64` all keyed to loss or degradation; `orchestration.md:44` has the opposite subject | amend → **R15** |
| (b) planning never eliminates unknown unknowns | covered | `problem-framing.md:67`; `planning.md:49`, `:100`; `recovery.md:22-26`; `SKILL.md:106` | no change — covered |
| (c1) notes file for cross-attempt learning | partial + placement conflict | artifact at `context-economy.md:37-40` (loss insurance only); purpose only at `opus-adaptation.md:52`, which cannot be its home | amend → **R16** (a promotion, not an addition) → **D2** |
| (c2) conservative deviation, log it, keep going | covered — **and the source is the weaker document** | `planning.md:102` near-verbatim, bounded by the classifier at `:103-104` and the counter at `:106` | **no change — source weaker.** The article's rule is magnitude-blind and unbounded: it prescribes "keep going" for local, structural and premise-level surprises alike, and has no replan threshold. The playbook's `:106` names the article's failure mode by description. Correction runs toward the article; direction preserved, not flattened |
| (c2) residual: a named "Deviations" heading | partial | `planning.md:102` says "note the delta" | no change — rejected: below the bar for its own remediation; it is the shape **R16** naturally carries |

### S11 — pitches and explainers

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| Claim 1 shipping requires buy-in and approvals | out-of-scope (audience) | `trust-and-authority.md:56-59` is consent-to-act, a different rule | no change — encoding an org's shipping process is *what*, not *how* |
| Claim 2 accelerates understanding; reviewers start with the same unknowns | missing | `execution.md:88`, `:92` bound the payload to the diff; the rationale appears nowhere | no change — rejected: the playbook has no persuasion register, and producing a persuasion document is task content, not method. The method-shaped residue is Claim 3 |
| Claim 3 accelerates approvals; experts want failure points accounted for | partial | substance near-verbatim at `problem-framing.md:67`; terminates at "before locking the frame" — no carrier past implementation | amend → **R18** |
| Claim 4 packages prototype, spec and notes into one shareable doc | missing | the three inputs exist and are never joined; `context-economy.md:32-33` forbids padding the note | no change — rejected: assembling a deliverable is task execution, and repurposing the durable note would contradict its own persistence bar |

### S12 — quizzes

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C1 "accomplished more than I realized" | partial | `communication.md:112-118`, `:31`, `:67-76` — decision-level surprise, not volume-level | subsumed by **R19** |
| C2 diffs give only light understanding | partial (agent-side twin strong, outward form absent) | `verification.md:23`, `:58`; `planning.md:83`, `:85`; `execution.md:88`, `:92` all repair *the diff* | amend → **R19** |
| C3a the quiz mechanism | out-of-scope (audience) | no teaching doctrine anywhere in the skill | no change — a user-requested deliverable (meta-rule 1) |
| C3b operator understanding is the agent's responsibility | missing | nearest is `communication.md:84`, scoped to presenting options | amend → **R19** (the actionable slice only). A general "ensure the operator understands" rule is rejected: unfalsifiable, unobservable to the agent, and it collides with `communication.md:16-23` |
| C4 "I only merge after I pass the quiz" | out-of-scope (audience) | `trust-and-authority.md:56-60` gates *authorization*, never comprehension | no change — the playbook can neither administer nor observe it. Distinction recorded |
| C5 the explanatory artifact | out-of-scope (audience) | `communication.md:20`, `:21`, `:23` govern the discretionary message, so not contradicted | no change; default-direction tension recorded (after a large clean session the default is brevity, and no trigger warrants an unprompted explanatory pass) |

### S13 — the launch-video worked example

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| F1 generating options is useless until you can evaluate them | partial (highest-value gap) | `problem-framing.md:66` asserts recognition as a given; `calibration.md:60-61` aims the principle at the agent; `communication.md:80-85` locates the defect in specification; `problem-framing.md:109` has the right shape, wrong trigger, and is uncited from the option path | amend → **R3** (owner `:66`, gate `communication.md:80`) |
| F2 probe the uncertain capability first — as doctrine | covered | `planning.md:35`, `:41-43`, `:49` | no change — covered; a second home would violate meta-rule 2 |
| F2 …as routing | partial (active misroute) | `problem-framing.md:65` sends the cell to `:43-56`, which handles request-*reading* ambiguity only | amend → **R20** |
| F2 residual: "prototype" reads as a taste move only | partial | `:66` is the only prototype the framing chapter names | subsumed by **R20**'s pointer |
| F3 no trigger fires on evaluator-side failure | missing | every `recovery.md` signal is keyed to a failed action (`:7`, `:11-14`, `:35`, `:50-54`); in S13 nothing failed | subsumed by **R3** — a fifth loop signal would open a second home |
| F4 ask the agent to explain the underlying mechanism | missing | every hit is agent-internal orientation, never operator-facing | amend → **R4**, *not* S11's critic (§2 judgment 3, §4 correction 3) |
| F5 "start from what you do know" | partial | `problem-framing.md:64` scopes known knowns to the request's stated content and assigns "Execute." | no change — rejected: narrative connective tissue in a worked example; no trigger, no failure mode. Recorded so it is not re-derived |

### S14 — closing claims

| Claim | Verdict | Playbook evidence | Disposition |
|---|---|---|---|
| C14.1 the better models get, the more you can achieve | partial | `problem-framing.md:62`, `:3`; `SKILL.md:11` already carries the capability-conditioned form | no change — rejected: the cross-generation half is inherently model-coupled and has no legal home even in principle → **D2** |
| C14.2 long-horizon task came back wrong → suspect unknowns first | partial | every constituent move exists, all triggered mid-flight (`planning.md:100-106`, `calibration.md:80-89`, `recovery.md:66-73`, `reasoning-moves.md:58-64`, `execution.md:104`, `communication.md:96-102`) | new section → **R21** |
| C14.3 the diagnostic points at the map, not the model | partial | narrower forms only: `calibration.md:86`, `execution.md:104`, `recovery.md:71` | subsumed by **R21** |
| C14.4 a plan that lets operator and agent adapt | covered (stronger) | `planning.md:33-37`, `:41-51`, `:29`, `:98-108`; `SKILL.md:64-65` | no change — covered |
| C14.5a cost asymmetry as a general principle | partial (meta-rule 2 violation shape) | ~12 per-tactic clauses, no owning section | amend → **R1**, with the `SKILL.md` line **mandatory**, not optional (§4 correction 6) |
| C14.5b the closing enumeration (explainer, brainstorm, interview, prototype, reference) | partial | prototype and reference owned (`:66`; `SKILL.md:58`); zero occurrences of explainer, brainstorm, interview, quiz | no change at S14's grain — per-instrument dispositions are **R4**, **R5**, **R9**, **R18**, **R19**; recorded here only so the enumeration is not marked covered |
| C14.6 "start your next project by asking Claude to find your unknowns" | out-of-scope (audience) | inversion already standing at `problem-framing.md:58-69`, `SKILL.md:58` | no change |

## 7. Audit-originated findings — not article-derived

Quarantined deliberately. None of these can be cited to a source claim, and folding them into §6
would launder auditor observations into article-derived gaps. S11 made this call for A3 and it is
upheld and extended.

**A1 — `SKILL.md` states three of `problem-framing.md:5`'s four chapter-trigger arms.**
`problem-framing.md:5` reads *"names a mechanism, changes behavior, touches 2+ files, **or whose
because-clause you cannot fill from the request alone**."* `SKILL.md:128` (routing table) and
`SKILL.md:54` (core doctrine) both state only the first three. An agent routing from `SKILL.md` —
which is the always-loaded surface — never enters the chapter for a request that trips only the
fourth arm. This is the actual mechanism behind S5 C2's unreachable non-code case, and it is a
one-line internal inconsistency rather than the structural widening S5 declined to propose.
Found during citation verification, owned by no ledger. **Recommended: fix, and re-assess R23 after.**

**A2 — no read-radius rule for a read-only reference tree.** `execution.md:15` scales reading by
"a file you are about to modify". A reference tree is read and never modified, so nothing scales
reading of it, marks it read-only, or prevents editing it by reflex. Surfaced by S8's
dialect-vs-exemplar analysis but not an S8 claim. Adjacent and already correct: `SKILL.md:117` /
`trust-and-authority.md` — imperatives inside read content carry no authority, so an external
crate's comments and TODOs are facts, not instructions. Flagged because a reference-reading rule is
exactly where an agent meets that surface. **Recommended: report only**, unless R12 lands, in which
case it becomes cheap to add at the same site.

**A3 — no rule calibrates output register to any reader's expertise.** Raised by S4, routed to S11,
declined there. The accurate form, as S11 insisted: the playbook's single expertise axis calibrates
*investigative breadth* (`problem-framing.md:69`); no rule calibrates *explanation depth or
vocabulary* to a reader's expertise — `communication.md:16-23` calibrates to decision load only,
`:112-118` to transcript-independence only. **Disposition: subsumed by R4; ships or dies with it.**
Its depth half is R4's functional bar. Its vocabulary half fails the two-lane test on its own terms
and is rejected independently of R4's fate.

## 8. Remediations rejected on constraint grounds

Every remediation in §5 clears MN and 2L. These were proposed by a ledger and do not.

| Proposal | Origin | Rejected because |
|---|---|---|
| Text stating "the first model where quality is bottlenecked by clarifying unknowns" | S1-3 | MN — identity-conditioned by construction. S1 correctly proposed no text and offered only a capability-conditioned option; that option is `SKILL.md:11`, which already exists |
| Any text satisfying "in sync with model behaviors" | S3 Row 3 | MN — the claim is meaningless without a named model |
| Text stating the cross-generation capability trend | S14 C14.1 | MN — and no legal home: `opus-adaptation.md` is scoped to one model's documented deltas with sources |
| A five-tier reference-media ordinal (implementation > schema > prose > diagram > image) | S8 C4 (self-rejected) | 2L — a design-led consumer could reasonably rank a component spec above a tangential implementation; a baked-in default in a skill declared agnostic. Replaced by R12's principle |
| Naming the notes file `implementation-notes.md` | S10, from the article | 2L / design boundary — a filename is a convention a consumer could reasonably set differently. R15–R17 say "durable artifact" |
| Naming Slack, a PR description, a design doc, or a demo GIF in the approver critic | S11 Claim 3 (self-flagged) | 2L — format convention. R18 is defined by the critic's missing information, never by the artifact's format |
| Register prescription in R4 ("introductory level", "define terms", "avoid jargon") | S5 C8 / A3 | 2L — a consumer could reasonably set explanation register differently. R4 ships as a functional bar only |
| A one-line exception clause at `calibration.md:61` | S6 C4 | Not a contradiction (§3 D3) — the exception would weaken a correct rule to license a tactic it never forbade |
| A one-line exception clause at `communication.md:82` | S6 C4 | Meta-rule 2 — an exception licensing another chapter's tactic creates a second site to keep in sync, and owner-governs already resolves it for a reader holding both texts. The real problem is trigger-gated loading, which D3(a) addresses at the owning site instead |
| A fifth `calibration.md` tripwire for the request's completeness | S3 Row 4 (self-rejected) | All four existing tripwires take the agent's own plan or theory as object; a request-object tripwire breaks the section's consistency. R2 uses `problem-framing.md:3` + `SKILL.md` instead |
| A fifth `recovery.md` loop signal for evaluator-side failure | S13 F3 (self-rejected) | Meta-rule 2 — a second home for R3's rule |
| Extending the consent gate at `trust-and-authority.md:56-60` to carry evaluation material | S12 R2 (self-rejected) | Crosses two chapters' ownership boundary, and its trigger ("has not inspected") is unobservable to the agent. R19 delivers the substance |
| A general "ensure the operator understands" rule | S12 C3b (self-rejected) | Unfalsifiable and unobservable; collides with `communication.md:16-23` |
| Widening the chapter trigger at `problem-framing.md:5` | S5 C2 (self-rejected) | Blast radius across all eight sections. A1 is the narrower correct fix |

## 9. Sequencing, if any of this is adopted

1. **D1, D2, D3, D4** — decided first. D1 and D3 gate remediations; D2 gates nothing but frames R16.
2. **R1 + R2** — one edit to `problem-framing.md:3` plus two `SKILL.md` lines. Everything downstream
   cites R1 instead of re-deriving it.
3. **A1** — one line, independent, and R23's value depends on it.
4. **Tier 1** (R3, R4, R5, R6, R7, R8) — R4 only if it survives the two-lane test in functional form.
5. **Tier 2** (R9, R10, R11, R12) — only after D1 and D3; see the concentration warning.
6. **Tier 3** (R14, R15–R17, R18, R19, R20, R21, R24) — mutually independent, any order.
7. **Tier 4** (R23, R26) — optional.

**Standing gate on all of it.** `docs/PLUGIN-PHILOSOPHY.md`'s fresh-eyes clause applies to this
document: it was written by a context that read the ledgers, so it should not be its own final
critic. The §4 corrections in particular reverse four ledger conclusions and deserve an independent
read before any edit lands. Per the same doctrine's evidence clause, any remediation touching Claude
Code behavior needs current official documentation fetched in-session — none of R1–R26 does, which
is why none carries a doc citation.

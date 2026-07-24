# Repair ledger — what actually lands in `plugins/playbooks/skills/fable-5/`

`dispositions.md` proposed the remediation set. `disposition-review.md` and `codex-review.md` then
found defects in it. **Neither review's findings were folded back into `dispositions.md`** — by
design, so the reviews stay independent artifacts rather than becoming a second draft of the thing
they reviewed. This file is the merge: one row per proposed item, carrying the reviewer findings
against it and the disposition it lands under.

**This file governs the edits.** Where it disagrees with `dispositions.md`, this file wins, because
`dispositions.md` predates both reviews. Where a repair changes an item's substance, the new text is
written out in §3 rather than left to the landing editor.

## 1. How to read this

**Verdict, four values:**

- **ship** — lands as `dispositions.md` §5 describes it. No reviewer finding against it.
- **ship repaired** — lands, with the repair in §3. The substance survives; the wording, scope,
  trigger, or justification does not.
- **hold** — does not land until the operator rules. Either it fails the skill's own admission bar
  (`SKILL.md:11` — every line encodes something a strong model does not reliably do untold), or the
  repair changes it into something materially different from what was approved.
- **decision** — an operator decision, not a remediation. Recorded, not edited.

**Approval context.** The operator authorized "full set live" — everything recommended under D1
split, D3 option (a), D4 decline, D2 blocked. That authorization was given against
`dispositions.md`'s recommendations. Five items below cannot honor it as written: D3(a) and R4 were
refuted by both reviewers, D2 has no implementable form, and R18/R26 fail the admission bar on
reviewer analysis. Those five are `hold`; the rest proceed.

**The standing objection is not reopened here.** `codex-review.md` §4 argues the whole batch lacks
behavioral evidence — textual differences against one article, no failure cases. The operator saw it
and chose the full set. It belongs in the PR body, not in this ledger's verdicts.

## 2. The ledger

| Item | Verdict | Ground |
|---|---|---|
| **D1** — `problem-framing.md:60` trigger split | ship repaired | Both reviewers back option (ii). Arm 4 as written is not agent-observable (Codex: the agent knows only the user's *disclosed* starting point, never whether the user has worked in an area). Repair R-D1 in §3. Null option (review finding 8) is noted and declined — see §4. |
| **D2** — `context/opus-adaptation.md` boundary | hold | Both reviewers: presents no options and no recommendation (review finding 9), and its stated reason is wrong (finding 6 — `:52` is structurally identical to its five siblings; applied consistently the reason strips the whole section). Not implementable. Options written out in §4. R16 is separable and proceeds. |
| **D3** — divergent-spread collision | hold | Option (a) refuted by both. It narrows the exact trigger R3 depends on (finding 2), and misses `communication.md:65` (Codex §3). The repair — narrow both sites — is a **new option (a′)**, not the one approved. Written out in §3; needs a ruling. |
| **D4** — scope-setting opener | decision | Decline upheld, on the duplication ground (`planning.md:5-11` question 1 already fails on the boundary-not-derivable case), **not** on the erodes-act-directly ground, which Codex showed is overstated. No edit. |
| **R1** — cost asymmetry gets an owner | ship repaired | Codex §3: R1 avoids duplication **only if it actually converts the dispersed per-tactic clauses to citations**. Adding the paragraph alone is a net-negative edit. The conversion is in scope or R1 does not land. Repair R-R1 in §3. |
| **R2** — standing prior that requests carry unknowns | ship | No finding against it. One edit with R1 at `problem-framing.md:3` plus the ungated `SKILL.md` bullet. |
| **R3** — operator evaluation capacity is clearable | ship repaired | Finding 11: "cite-forward in the `:53` shape" understates it — `communication.md:53` states its rule operatively *and* names the owner, so the second site carries operative text. R3 is a two-site edit. Its second site is gated on D3. |
| **R4** — transfer enough literacy to judge | hold | Finding 1, two independent legs: its object (annotating the blind-spot list) cannot deliver S13 F4 (domain literacy at option-presentation time), and it is gated on *disclosed* unfamiliarity while R3's detection fires on *undisclosed* inability. Codex §3 adds the unresolved `communication.md:16-23` collision. Repair R-R4 in §3 changes what it is; needs a ruling. |
| **R5** — offer the round when residue is large | ship | No finding against it. |
| **R6** — the volunteer slot | ship repaired | Codex §3: collides with `communication.md:65` ("attach your recommended answer to every question you pose") — there is no recommended answer to "what do you know that I did not ask about". Fixed by D3(a′)'s narrowing of `:65`, which R6 therefore depends on. |
| **R7** — rank the ask path by downstream invalidation | ship | Codex names it among the safer set (pointer-shaped). |
| **R8** — elicit an undisclosed starting point | ship | No finding against it. |
| **R9** — license the divergent spread | ship | Substance clean. **Gated on D3.** |
| **R10** — name the elicitation artifact as an artifact kind | ship repaired | Finding 7: two of three supporting citations are overstated — `reasoning-moves.md:168`'s total rule carries an explicit "prediction does not apply here → strike it" escape, and `problem-framing.md:107`'s negative-criterion mandate is scoped to fixes, with `:109` already routing judgment-shaped tasks. Only the `execution.md:133` debris leg holds. Repair R-R10 in §3. |
| **R11** — re-run the ambiguity sort on show-move residue | ship | No finding against it. |
| **R12** — reference fidelity, cross-language port, ask ordering | ship repaired | Finding 5: the fidelity definition ("carries naming, structure and edge-case handling") reproduces the five-tier ordinal it rejects — those are code/spec-shaped properties an image carries none of, so the 2L stamp is unearned. Repair R-R12 in §3. |
| **R14** — decisions-first plan preface | ship repaired | Codex §3: for in-message plans `communication.md:67-76` already mandates surfacing every unbriefed decision with consequence and evidence. R14 is new only for the separately-consumed durable artifact. Scope it there. Repair R-R14 in §3. |
| **R15** — phase-boundary reset | ship | No finding against it. Every existing reset trigger is keyed to loss or degradation; none to successful completion. |
| **R16** — promote the lesson-note purpose | ship repaired | Finding 6: the promotion is right, the stated reason is wrong. Real ground: `:52` is the only bullet in `opus-adaptation.md:45-52` whose pointer target does not exist. Codex adds a substance risk — "decisions made and why" collides with `context-economy.md:32-33` ("do not pad the note with cheap facts") and partly duplicates `recovery.md:22-26`. Repair R-R16 in §3. |
| **R17** — the work note's disposition at task end | ship | Codex names it among the safer set (lifecycle completion). |
| **R18** — a fourth critic: the approver | hold | Finding 10: the `:126` ownership citation says something else ("No other chapter runs this critic" is about the maintainer critic). Codex §3 is the harder objection: `:128`'s bar is already total — *"run every critic whose audience this artifact actually has"* — so an approver who is a real audience is already in scope. Under the admission bar this is an example, not a missing doctrine. Needs a ruling: ship as a named example, or drop. |
| **R19** — name the behavior that changed in code you did not edit | ship | No finding against it. Completes the existing `:118` test, which currently leans on the diff for information the diff structurally cannot carry. |
| **R20** — route feasibility unknowns out of the ambiguity sort | ship | Codex names it among the safer set. An active mis-route, not a location preference. |
| **R21** — frame-attribution before execution-attribution | ship repaired | Codex §3: the "returned as wrong" trigger overlaps `debugging.md:5-13`, which requires a deterministic reproduction first for a reported broken behavior. Under trigger-gated loading, whichever chapter loads first decides. Repair R-R21 in §3 narrows the trigger to the not-what-was-meant case. |
| **R23** — parameterize the blind-spot checklist by domain | ship | Low priority, unchanged. Depends on A1 landing first to be reachable at all. |
| **R24** — make the scope bound bidirectional | ship | Codex names it among the safer set (pointer, not new doctrine). |
| **R26** — external-source branch in the check/skip matrix | hold | `dispositions.md` itself concedes it may be stylistic; Codex §3 agrees — `calibration.md:30-38` already requires check-or-downgrade/escalate and `:16` already names doc fetch as an observation source. Fails the admission bar on both reviews. Needs a ruling. |
| **A1** — `SKILL.md` states three of four chapter-trigger arms | ship | Both reviewers verified the fact. Finding 4's caveat is recorded, not fatal: fixing it makes the fourth arm operative for the first time, so A1 is narrower in *edit size*, not blast radius. That is the correct trade — the alternative is a documented trigger that structurally never fires. |
| **A2** — no read-radius rule for a read-only reference tree | ship | `dispositions.md` §7: report-only *unless R12 lands*, in which case it is cheap at the same site. R12 lands. |
| **A3** — output register vs reader expertise | — | Subsumed by R4; ships or dies with it. Its vocabulary half is rejected independently on 2L. |

**Counts.** 20 ship (11 as written, 9 repaired), 5 hold, 1 decision, 1 subsumed.

## 3. The repairs, written out

### R-D1 — arm 4 must be agent-observable

`dispositions.md` arm 4: *"the work sits in a region of the codebase or domain neither you nor the
user has worked in."* The agent cannot observe the second half. The playbook's own observable form
for this signal is `problem-framing.md:73` (*"in territory you have not touched this session"*).

**Repaired arm 4:** the work sits in territory you have read no prior art for this session, and the
request carries none of the domain's standard concerns. Both halves are things the agent can check.

Arms 5 and 6 relocate per option (ii) — arm 5 onto the show-move it gates, arm 6 onto the exemplar
clause inside it — and are **not** restated at the chapter trigger.

### R-D3 — option (a′), the complete narrowing

Option (a) narrows `communication.md:80` only. Three defects follow, and (a′) fixes all three:

1. **`:80`'s narrowing must not swallow R3's gate.** R3's second site fires on the operator's
   evaluation capacity, which is exactly the elicitation case (a) carves out. R3's clause therefore
   goes on its own trigger line at `communication.md`, not as a rider on `:80`.
2. **`communication.md:65` needs the same narrowing.** *"Attach your recommended answer to every
   question you pose"* fires on a spread presented as a question, and on R6's volunteer slot. The
   narrowing is the same distinction in both places: a question whose answer space the agent can
   enumerate and rank carries a recommendation; a question whose whole purpose is to elicit
   something only the user holds does not.
3. **The concept must resolve for a solo-loaded `communication.md`.** Both narrowings define the
   carve-out by what the agent lacks — no basis to rank the options, because the ranking criterion
   is the thing being elicited — rather than by pointing at `problem-framing.md`'s vocabulary. A
   pointer that resolves only when the other chapter is loaded reproduces the trigger-gated-loading
   hole D3 exists to close.

`calibration.md:61` stays untouched: `dispositions.md` §3 D3 established it is a scope mismatch, not
a contradiction, and R9's own self-scoping clause ("a deliverable, not an option survey") is where
that belongs. Codex's third bullet asks for it to be narrowed too; declining, on the disposition's
reasoning, which Codex did not rebut — it argued the collision "remains visible", which is the
scope-mismatch reading restated.

**Why this needs a ruling:** the operator approved (a), one edit at one site. (a′) is three edits at
two sites plus a trigger line. Same direction, materially larger.

### R-R1 — the pointer conversion is in scope, or R1 does not land

R1's whole 2L/meta-rule-2 defense is that the twelve per-tactic clauses *cite* the economics instead
of re-deriving them. Landing the paragraph without the conversion adds a thirteenth statement of the
same doctrine, which is the defect R1 exists to fix. The edit is: the owning paragraph at
`problem-framing.md:3`, **and** every per-tactic clause that currently re-derives the cost argument
rewritten to cite it. Enumerate those sites from the text at edit time, not from this list.

### R-R4 — what R4 becomes if it lands

Two changes, and together they make it a different remediation:

- **Object.** Not "annotate the blind-spot list." The literacy transfer is owed wherever the user is
  asked to judge something they lack the vocabulary to judge — option presentation, the show-move's
  candidate set, and the blind-spot list alike. That makes its home the presentation of any
  operator-facing choice, not `problem-framing.md:67`'s surface clause.
- **Trigger.** Not "where the user has disclosed unfamiliarity." Gate it on the same signal R3 uses:
  you cannot name a reference point for how good this class of artifact gets, and neither can they.
  Disclosure is one way that becomes visible, never the only one.

Repaired, R4 is a clause on R3's doctrine rather than an independent remediation — which is what
review finding 1's judgment-3 analysis implies. The functional-form 2L bar from `dispositions.md`
survives unchanged and still governs: "enough that they can evaluate each item", never a register
prescription.

**Why this needs a ruling:** `dispositions.md` states the consequence itself — if R4 dies, R3 ships
alone as "notice and say so", *"a materially smaller remediation than the ledgers imply."* Merging
R4 into R3 is the middle path and is what this repair produces. The operator approved R4 as its own
remediation at its own home.

### R-R10 — the justification shrinks to one leg

Drop the `reasoning-moves.md:168` and `problem-framing.md:98-107` citations. The `execution.md:133`
debris leg holds alone: a single-file mock in the project tree is scratch-file-shaped, so without a
rule naming the elicitation artifact as a distinct kind, the debris sweep takes it. R10's substance
(its completeness bar is "does it surface the criterion", it retires by explicit decision) is
unchanged; only the pointers at `execution.md:124` and `reasoning-moves.md:166` lose their premise
and come out.

### R-R12 — fidelity is relative to the aspect you need

`dispositions.md`'s definition ("carries naming, structure and edge-case handling rather than
implying them") names three code-shaped properties, so it re-ranks an implementation above a visual
reference by other means — the ordinal it rejected.

**Repaired:** take the form that most directly carries **the aspect you need from it** — behavior,
structure, or interface — and say which aspect that is. A screenshot is the highest-fidelity form
for a layout; an implementation is, for edge-case handling. The aspect is named per task, which is
what makes it self-scoping rather than a shipped default.

The cross-language clause and the ask-ordering clause land unchanged. A2 lands at the same site: a
reference tree is read and never modified, so it takes no read-radius scaling from
`execution.md:15`, and nothing marks it read-only.

### R-R14 — durable tier only

The in-message half comes out. `communication.md:67-76` already mandates surfacing every unbriefed
decision with what it changes and the evidence, which is R14's substance for a plan delivered in a
message. R14 lands as: when a plan is a separately-consumed durable artifact, lead it with the
choices the reader would most plausibly make differently, ranked by the rework a late veto would
cause. The guardrail stays verbatim and is load-bearing — presentation prominence is not rigor; a
step placed last is verified identically.

### R-R16 — corrected ground, narrowed substance

**Ground:** `opus-adaptation.md:52` is the only bullet in the `:45-52` section whose pointer target
does not exist — its five siblings each point at an owning chapter, and cross-attempt learning has
none. Not "general doctrine in a model chapter", which is true of all six and would strip the
section.

**Substance:** narrow "decisions made and why" to decisions whose re-derivation cost is what makes
them worth keeping — the same persistence bar `context-economy.md:32-33` already sets for the note.
Written wider it invites exactly the padding that rule forbids, and overlaps
`recovery.md:22-26`'s abandoned-path record.

### R-R21 — trigger excludes observed defects

Trigger becomes: a multi-step or session-spanning deliverable is returned as **not what was meant** —
the complaint is about the target, not about a behavior that demonstrably misbehaves. A reported
broken behavior routes to `debugging.md`'s reproduction-first rule unchanged, and the new section
says so in one line, so an agent holding only `problem-framing.md` does not pre-empt it.

## 4. Held for operator ratification

Restated in full, each with a recommendation. Nothing in this section lands until ruled.

**H1 — D3 becomes option (a′).** Approved: (a), one narrowing at `communication.md:80`. Repaired:
three narrowings across `:80` and `:65` plus a separate trigger line for R3's gate (§3, R-D3).
R9 and R6 both depend on it. **Recommendation: take (a′).** Option (a) as approved ships a known
regression — it disables R3's second trigger site, which is the defect D3 used to reject option (b).

**H2 — R4 merges into R3.** Approved: R4 as an independent remediation homed at
`problem-framing.md:67`. Repaired: a clause on R3's doctrine, re-homed to operator-facing choice
presentation and re-gated on undisclosed inability (§3, R-R4). **Recommendation: merge it.** The
alternative is R4 dying entirely, which leaves S13 F4 and S5 C4 unremediated while §6 marks them
`amend → R4`.

**H3 — D2 needs a rewrite before it is a decision.** Both reviewers: it presents no options and no
recommendation. The options it withholds are (i) retitle the chapter so it is not addressed to one
model version, (ii) split one model's documented deltas from the model-agnostic adaptation method,
(iii) accept the coupling under the provenance-named-playbook exception. **Recommendation: (iii),
accept the coupling, and close D2.** The chapter's name, framing and doc citations are all already
covered by `docs/PLUGIN-PHILOSOPHY.md`'s provenance exception; the three homeless claims stay
rejected on MN either way, so (i) and (ii) buy nothing the rejections do not already deliver. R16
proceeds regardless.

**H4 — R18 (the approver critic).** Codex: `reasoning-moves.md:128`'s bar is already total, so an
approver who is a real audience is in scope without R18. **Recommendation: drop it.** Under the
skill's admission bar an agent already running "every critic whose audience this artifact actually
has" does nothing differently for the added roster entry. If it lands at all it lands as a named
example under `:128`, never as a fourth roster member with its own definition.

**H5 — R26 (external-source branch).** `calibration.md:30-38` already requires check-or-downgrade
and `:16` already names doc fetch. **Recommendation: drop it.** Both reviews and the disposition
itself put it at or below the stylistic line; `dispositions.md` calls it "a defensible decline".

**H6 — D1's null option, declined rather than held.** Review finding 8 is right that the option set
omitted "keep the three arms as written". Declining it: arm 4 survives the diagnosis that killed
arms 5 and 6 — it is a genuine whole-pass signal, and the null option would drop it for a reason
that does not apply to it. Recorded here so the omission is answered rather than inherited.

## 5. Revised sequencing

`dispositions.md` §9 sequenced the full set. This is that order with the holds removed and the
repairs folded in.

1. **A1** — independent, one line, and R23 is unreachable without it.
2. **R1 + R2** — one edit to `problem-framing.md:3` plus the pointer conversion (R-R1) plus two
   `SKILL.md` lines. Everything downstream cites R1.
3. **D1** — the trigger split, with the repaired arm 4. Creates the show-moves home that Tier 2
   targets. **`problem-framing.md:66` as cited stops existing after this.**
4. **Tier 1** — R3 (two sites; its `communication.md` site waits on H1), R5, R6 (waits on H1), R7,
   R8.
5. **Tier 2** — R9 (waits on H1), R10, R11, R12 + A2. All land in the new show-moves section.
6. **Tier 3** — R14, R15, R16, R17, R19, R20, R21, R24. Mutually independent, any order.
7. **Tier 4** — R23.
8. **D4** — recorded, no edit.

**Line numbers go stale at step 2.** Every citation in this file and in `dispositions.md` is as-of
`15dcd61`. From step 2 onward, resolve homes by section name and re-read before editing.

## 6. What the fresh-eyes reviewer checks

`docs/PLUGIN-PHILOSOPHY.md`'s fresh-eyes clause binds the playbook diffs, not just
`dispositions.md`. The reviewer gets the diff and this ledger, and answers:

1. Does every landed clause match its row here — including the repaired substance, not the
   disposition's original?
2. Did R1's pointer conversion actually happen, at every site that re-derives the economics?
3. Does any landed clause name a model, a version, a filename, a tool, or a register — the MN and 2L
   constraints?
4. For each landed clause: what does an agent do differently because of it? A clause with no answer
   is a `hold` that leaked.
5. Do the two narrowings in R-D3 leave `communication.md` self-resolving when it is the only chapter
   loaded?

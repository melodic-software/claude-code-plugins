# Cross-vendor review of `dispositions.md` — Codex (gpt-5.6-sol)

Run: `codex exec -s read-only --skip-git-repo-check -C <repo> - < codex-inline-prompt.txt`
Exit status 0. ~144k-token session, model gpt-5.6-sol. No repo edits.
Artifacts embedded verbatim in the prompt (local sandbox exec is broken on this machine; see
session notes). Verdict below is Codex output, unedited.

## Bottom line

The reversals are mixed: S7 is correct; S13 is only half-correct; S2 and S6 are presented with more certainty than the skill supports. D3 is materially incomplete, D2 understates the scope change it proposes, and several remediations would duplicate or collide with standing rules—especially when only one trigger-gated chapter is loaded.

## 1. The four reversals

I treated “the four” as the four auditor clusters involving S2, S7, S13, and S6. Section 4 actually contains seven numbered corrections [dispositions.md:346-368](.work/fable-field-guide-audit/dispositions.md).

### S2: “achievable ceiling belongs in `:66`, not `:67`” — not established

This is a plausible placement decision, but not proof that S2 misread the taxonomy.

- `:66` covers knowledge the user cannot verbalize but “will recognize on sight” [problem-framing.md:66](plugins/playbooks/skills/fable-5/context/problem-framing.md).
- `:67` covers “gaps neither of you has considered” [problem-framing.md:67](plugins/playbooks/skills/fable-5/context/problem-framing.md).

The proposed case is specifically that neither party can name what distinguishes strong work from obvious work [dispositions.md:413-416](.work/fable-field-guide-audit/dispositions.md). That negates `:66`’s recognition premise and fits `:67`’s “neither of you” definition at least as naturally.

Placing the guard next to `:66` is operationally sensible because it guards the show-candidates tactic. But that is an ownership choice, not evidence that S2’s classification was wrong. Verdict: **reversal overstated**.

### S7: one mechanism versus two — correct

The skill contains three separate pieces:

- The agent generates plausible readings [problem-framing.md:47-49](plugins/playbooks/skills/fable-5/context/problem-framing.md).
- The agent generates domain-practitioner questions [problem-framing.md:67](plugins/playbooks/skills/fable-5/context/problem-framing.md).
- Once questions exist, it sequences or batches them [communication.md:65](plugins/playbooks/skills/fable-5/context/communication.md).

Nothing creates a scheduled question round, and nothing asks the operator to volunteer an open question that neither agent-generated process found. Therefore:

1. “Offer a round” creates an event.
2. “What remains open that I did not ask?” creates a new information channel.

Those are separable. S7’s own body said the first closes “roughly half” [S7.md:119-134](.work/fable-field-guide-audit/findings/S7.md), while its bottom line collapsed them [S7.md:136-140](.work/fable-field-guide-audit/findings/S7.md). Verdict: **reversal correct**.

### S13: F4 cannot live in S11’s critic — correct; routing it to R4 — incomplete

The first half is solid. The critic pass is explicitly an internal simulation whose critics are defined by missing information [reasoning-moves.md:120-128](plugins/playbooks/skills/fable-5/context/reasoning-moves.md). An operator-facing explainer is a produced artifact, not an internal critic. S11’s landing cannot own F4.

But the conclusion that F4 simply “inherits R3’s trigger sites” is unsupported. R4 is actually proposed under the unknown-unknown surface clause and only “where the user has disclosed unfamiliarity” [dispositions.md:423-427](.work/fable-field-guide-audit/dispositions.md). That clause remains behind the quadrant trigger [problem-framing.md:60](plugins/playbooks/skills/fable-5/context/problem-framing.md), while the evaluator failure can arise later under the independently re-entrant options trigger [communication.md:80](plugins/playbooks/skills/fable-5/context/communication.md).

Because chapters load only when their own trigger fires [SKILL.md:122-140](plugins/playbooks/skills/fable-5/SKILL.md), an agent can encounter the options failure with `communication.md` active and R4 unavailable. R3 has a proposed communication trigger; R4 does not.

Verdict: **correct rejection of the S11 home, but the claimed replacement routing is incomplete**.

### S6: `calibration.md:61` is not a contradiction — not proven

The actual rule is unqualified:

> “enumerate options only as deep as you would actually pursue them” and “a comparison you will not act on is decoration” [calibration.md:58-61](plugins/playbooks/skills/fable-5/context/calibration.md).

It does not say “only the agent’s private option surveys” or exclude deliverable candidate sets. The disposition imports that distinction into the text [dispositions.md:282-290](.work/fable-field-guide-audit/dispositions.md).

A reader holding both proposed doctrines might infer that every spread member is genuinely pursuable if selected. But an agent holding only `calibration.md` cannot: calibration can load independently when deliberation or verification is being weighed [SKILL.md:130](plugins/playbooks/skills/fable-5/SKILL.md). Under trigger-gated loading, the latent stop signal remains.

Verdict: **at best ambiguous; the reversal is not justified as a demonstrated misreading**.

The related S6 “singular” correction is sound. The grammar says “a sketch, a throwaway prototype, or one fully worked example” [problem-framing.md:66](plugins/playbooks/skills/fable-5/context/problem-framing.md). “One” modifies the worked-example alternative; it is not a universal cardinality cap.

Two additional section-4 corrections:

- A1 is factually correct: the chapter trigger includes the unfillable-because arm [problem-framing.md:5](plugins/playbooks/skills/fable-5/context/problem-framing.md), while both core doctrine and routing omit it [SKILL.md:54](plugins/playbooks/skills/fable-5/SKILL.md), [SKILL.md:128](plugins/playbooks/skills/fable-5/SKILL.md).
- Making S14’s `SKILL.md` line “mandatory” is a design consequence only if the economics must be ungated. It is not something the existing skill text independently proves.

## 2. D1–D4 and their costs

### D1 — directionally sound, but framed as a false structural choice

Putting whole-pass signals on the whole pass and show-specific signals on the show moves is the cleanest of the proposed shapes. Arms 5 and 6 do not justify running the unknown-unknown and falsification machinery [dispositions.md:199-203](.work/fable-field-guide-audit/dispositions.md).

Its stated cost is not understated; if anything, it is exaggerated. Extracting trigger lines does not necessarily mean the four-cell taxonomy “stops being the organizing structure” [dispositions.md:210-216](.work/fable-field-guide-audit/dispositions.md). The cells could remain the taxonomy while individual moves acquire local sub-triggers.

The omitted costs are more important:

- Arm 4 depends on knowing that neither party has worked in the area, but the skill only has access to the user’s disclosed starting point [problem-framing.md:69](plugins/playbooks/skills/fable-5/context/problem-framing.md).
- Multiple local triggers, an owner site, and communication pointers increase synchronization burden under trigger-gated loading.
- D1 is ineffective for the omitted chapter-routing arm until A1 is fixed, which the disposition does acknowledge [dispositions.md:227-234](.work/fable-field-guide-audit/dispositions.md).

Verdict: **reasonable recommendation, incomplete cost model rather than adoption-biased understatement**.

### D2 — the cleanup is plausible, but “promotion, not addition” understates the change

Moving generic doctrine out of a model-specific chapter is structurally sensible. `opus-adaptation.md:52` appears under model-conditioned “behaviors to emulate deliberately” [opus-adaptation.md:43-52](plugins/playbooks/skills/fable-5/context/opus-adaptation.md).

But the claim that cross-attempt learning has “no general-purpose owner anywhere” is too strong. General chapters already say:

- expensive conclusions go into durable notes [context-economy.md:30-39](plugins/playbooks/skills/fable-5/context/context-economy.md);
- an abandoned path is recorded so a later pass does not re-walk it [recovery.md:22-26](plugins/playbooks/skills/fable-5/context/recovery.md).

R16 would broaden this from expensive conclusions/dead ends to “decisions made and why” [dispositions.md:558-561](.work/fable-field-guide-audit/dispositions.md). That risks conflicting with “do not pad the note with cheap facts” [context-economy.md:32-33](plugins/playbooks/skills/fable-5/context/context-economy.md). Moving it from a model correction to general doctrine also expands who must follow it.

Verdict: **sound boundary cleanup, but materially undercosted and partly duplicative**.

### D3 — unsound as a complete fix; cost materially understated

Narrowing `communication.md:80` is better than relying on a distant exception. The direct collision with “mark exactly one option as recommended” is real [communication.md:78-84](plugins/playbooks/skills/fable-5/context/communication.md).

But D3 misses another rule in the same chapter:

> “attach your recommended answer to every question you pose” [communication.md:65](plugins/playbooks/skills/fable-5/context/communication.md).

An elicitation spread presented as a question still hits that rule. Narrowing only `:80` does not fix it. Nor does it resolve the unqualified calibration language discussed above.

Calling the cost “one pointer” [dispositions.md:329-331](.work/fable-field-guide-audit/dispositions.md) is therefore inaccurate. A complete fix requires at least:

- narrowing both recommendation rules;
- defining the elicitation-spread concept somewhere an independently loaded communication chapter can understand;
- resolving or narrowing `calibration.md:61`.

Verdict: **recommendation incomplete; costs understated in favor of adoption**.

### D4 — declining is defensible, but its cost argument favors rejection

The proposed narrow trigger is substantially covered already. If the boundary is not derivable, the agent cannot state a complete executable sequence, so planning question 1 fails; the missing answer becomes the first work item [planning.md:5-11](plugins/playbooks/skills/fable-5/context/planning.md). Adding another scope-setting-opener rule would mostly specialize that test.

However, D4 says the narrow rule would erode the act-direct bias [dispositions.md:333-344](.work/fable-field-guide-audit/dispositions.md). That is overstated: the proposed trigger fires exactly when the two-yes threshold does not hold. It does not change the genuine two-yes case.

R2 is also not a substitute for the procedure: R2 is explicitly “a prior, not a procedure” [dispositions.md:396-402](.work/fable-field-guide-audit/dispositions.md).

Verdict: **decline is reasonable because of duplication, but the stated cost is inflated to favor declining—not understated to favor adoption**.

## 3. Duplications and trigger-gated contradictions

Yes. The proposed set is not clean.

| Proposal | Problem |
|---|---|
| **R6** | The volunteer question conflicts with the standing requirement to attach a recommended answer to every question [communication.md:65](plugins/playbooks/skills/fable-5/context/communication.md). There is no coherent recommended answer to “what do you know is still open that I did not ask?” R6 does not narrow that rule [dispositions.md:455-459](.work/fable-field-guide-audit/dispositions.md). |
| **R9** | D3 addresses `communication.md:80-83` but not `communication.md:65`; the calibration collision also remains visible when calibration loads without problem framing [SKILL.md:124-136](plugins/playbooks/skills/fable-5/SKILL.md). |
| **R4** | It adds teaching content while communication says to include exactly what changes the next action and cut the rest [communication.md:16-23](plugins/playbooks/skills/fable-5/context/communication.md). The disposition acknowledges this but leaves reconciliation until landing [dispositions.md:441-446](.work/fable-field-guide-audit/dispositions.md). An unresolved reconciliation is not a ready remediation. |
| **R18** | The critic roster already has a total rule: “run every critic whose audience this artifact actually has” [reasoning-moves.md:128](plugins/playbooks/skills/fable-5/context/reasoning-moves.md). An approver who is actually an audience is already included. Naming one may be a useful example, but it is not a missing doctrine. Its failure-question criterion also reuses the blind-spot pass [problem-framing.md:67](plugins/playbooks/skills/fable-5/context/problem-framing.md). |
| **R14** | For in-message plans, the communication chapter already requires every unbriefed decision to be surfaced visibly, including consequences and evidence [communication.md:67-76](plugins/playbooks/skills/fable-5/context/communication.md). R14 is new only for a separately consumed durable artifact; applying it to both plan tiers duplicates the existing message rule [dispositions.md:533-547](.work/fable-field-guide-audit/dispositions.md). |
| **R26** | The existing matrix already requires checking a gating, expensive claim or downgrading/escalating it [calibration.md:30-38](plugins/playbooks/skills/fable-5/context/calibration.md), and already names doc fetch as an observation source [calibration.md:16](plugins/playbooks/skills/fable-5/context/calibration.md). R26 mostly names a source category; the disposition itself concedes it may be stylistic [dispositions.md:632-641](.work/fable-field-guide-audit/dispositions.md). |
| **R21** | Its broad “returned as wrong” trigger overlaps debugging’s rule that a reported broken behavior first gets a deterministic reproduction [debugging.md:5-13](plugins/playbooks/skills/fable-5/context/debugging.md). R21 instead orders frame attribution before execution attribution [dispositions.md:604-615](.work/fable-field-guide-audit/dispositions.md). For “not what was meant,” that is sensible; for an observed defect, it conflicts. Trigger-gated loading makes whichever chapter loads first decisive. |
| **R1** | The economics already exist as general prose in the problem-framing preamble [problem-framing.md:3](plugins/playbooks/skills/fable-5/context/problem-framing.md) and as the reversibility rationale [planning.md:53-65](plugins/playbooks/skills/fable-5/context/planning.md). R1 avoids duplication only if it actually replaces the dispersed clauses with pointers, as promised [dispositions.md:388-394](.work/fable-field-guide-audit/dispositions.md). Merely adding its proposed text would duplicate doctrine. |

R7, R10, R12, R17, R20, and R24 are safer because they are expressly framed as pointers, local applications, or lifecycle completions rather than second full formulations.

## 4. Strongest argument against adoption

The strongest argument is not that every proposal is bad. It is that this audit has not demonstrated that the proposed rules deserve to become standing instructions.

The skill sets a demanding admission criterion: every line supposedly captures something “a strong model does NOT reliably do untold” [SKILL.md:9-11](plugins/playbooks/skills/fable-5/SKILL.md). The audit establishes textual differences from one human-operator article; it does not present behavioral evaluations showing that agents following the current skill fail, or that these particular clauses correct those failures.

That evidentiary gap matters because the proposed batch is large, cross-linked, and already internally unstable:

- four remediations overload one existing bullet [dispositions.md:478-486](.work/fable-field-guide-audit/dispositions.md);
- D3’s own analysis admits owner-governs fails when chapters are not co-present [dispositions.md:300-312](.work/fable-field-guide-audit/dispositions.md);
- several proposed rules introduce exactly that kind of cross-trigger dependency;
- the skill itself warns that every token loaded competes with later reasoning and that unneeded content is “rot you paid for” [context-economy.md:5-12](plugins/playbooks/skills/fable-5/context/context-economy.md).

So the strongest case is:

> Do not convert an article-coverage ledger into roughly two dozen new standing rules without behavioral failure cases and controlled evaluations. The likely failure mode is not merely prose bloat; it is reduced salience of the existing high-value rules plus new chapter-order-dependent contradictions.

The disposition itself effectively concedes that it is not ready for wholesale adoption: it requires an independent fresh-eyes review before any edit lands [dispositions.md:887-890](.work/fable-field-guide-audit/dispositions.md). The defensible course is to fix proven internal seams such as A1, then test a very small number of behaviorally distinct candidates. Adopting the remediation set as a batch is not justified by the evidence embedded here.

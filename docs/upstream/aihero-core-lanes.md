# AI Hero course — core-lane decision record (lanes 3–5)

Interim decision record for the course's original six-lane contract's remaining discussion
lanes (3 compaction, 4 plan-mode, 5 grilling parity), run as a session chain on
`claude/pocock-steering-course-00zkvd` (restarted from the default branch after the steering
chain merged). Lane 6
([#2904](https://github.com/melodic-software/claude-code-plugins/issues/2904)) harvests these
rows into `docs/upstream/aihero-course.md` (its deliverable) and dissolves this file then —
the same graduation contract as the sibling steering record
(`docs/upstream/aihero-steering-lanes.md`).

Contract rules apply unchanged (`docs/topics/pocock-course-lanes/PLAN.md`, branch
`claude/plan-mode-discussion-55kszx`): interview-first per lane, claim ladder, lanes discuss
and decide but do not implement. Harness-behavior citations below reference the contract's
durable C1–C9 verdict table ("Harness-claims verdicts", verified 2026-08-17).

## Lane 3 — compaction doctrine (#2901, closed 2026-08-17)

Interview: 1 round, 5 questions, register gate clean (5/5), user confirmed. **Parity lane —
zero work items filed**; the known context-guard doc drift was already filed (#2973).

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Steered compaction as the default continuation mechanism; compact-before-QA as its ideal case | REJECT | QA over a compaction summary grades the summary (secondary evidence), never the work — exactly what context-guard's PostCompact evidence-degraded marker encodes; boundary validation routes to a fresh-context subagent (our shipped phase-verifier pattern), which his own phase-boundaries lesson concedes. Marker affirmed UNCHANGED — no boundary-timed carve-out (a hook cannot observe intent, and a conditional marker stops being evidence) |
| `/compact [instructions]` steering exists and is useful | CONFIRMED (C6) — for continuation only | Acknowledged as real (docs-verified); legitimate for steering an intentional between-phases compact while the window is still fresh (`session-flow:handoff` "Fork beats compaction" doctrine unchanged); never a QA substrate |
| "If auto-compact fires, something went wrong" (diagnostic half) | ADOPT (anchor phrase) | Convergent with context-guard's design: the zones exist to act before auto-compact fires; a firing = a missed boundary. Recorded as framing anchor, not a number |
| "The human owns the boundary" / disable auto-compact (prescriptive half) | REJECT | Unattended cloud/autonomous sessions have no human at the boundary; the licensed version is the instrumented ladder — observable zones → advisory injection → opt-in blocking gate (grace budget, handoff-path always writable). Auto-compact stays enabled as the last-resort safety net; a degraded continuation beats a hard stall |
| Compaction "seeds a fresh session" | REFUTED (C4) | Same session continues over a structured summary; only fork/`--fork-session` makes a new session ID. Our doctrine already states the mechanism correctly — no doc change |
| Messages queue during compaction | TRACK (C5, UNDOCUMENTED) | Never taught until cured; named Tier-0 cure: live interactive-session probe. Trigger: official docs documenting the behavior, or the cure being run |
| Transcript = primary source, compaction summary = secondary source | ADOPT (vocabulary) → lane 6 | Convergent with the save-point engine's lossless-transcript-vs-model-visible-conversation rule; term pair routed to #2904's adoption list (already a candidate there) |

## Lane 4 — plan-mode (#2902, closed 2026-08-17)

Interview: 1 round, 5 questions, register gate clean (5/5), user confirmed. **One work item
filed**: [#2997](https://github.com/melodic-software/claude-code-plugins/issues/2997) (eval
coverage regression-gating the lock/auto-guard defenses).

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| Plan mode rushes to an asset (the plan reads like the implementation) with no alignment step — the asset-rush trait | ADOPT (convergent-validated) | The interview-first pipeline IS the missing alignment step: `planning:interview` (pre-clarity contract) sequences upstream of `planning:plan`, which itself separates the permission mode from the planning discipline and gates execution on user approval. His critique targets using plan mode *as* the alignment step — a use our pipeline never makes |
| Plan mode's proper role | RETAIN (permission enforcement only) | Read-only exploration during planning + the approval-flow UI (C7 Shift+Tab and C8 ExitPlanMode/EnterPlanMode both CONFIRMED); never the understanding step. Already codified in `planning:plan` "Plan Mode Integration" |
| `lock` / auto-detect synthesize-directly = quiet reintroduction of the rush? | AUDITED — LICENSED EXCEPTION | Four structural defenses cited: (1) invoking `lock` is itself the user's explicit "I'm clear" (documented confirmation-gate exemption); (2) STOP-on-gap forbids fudging a surfaced unknown; (3) the auto-guard — a genuinely-user decision is never folded into the Brief silently, and unattended it becomes a `blocked` register row with `arbiter: USER-RESERVED`; (4) the register gate is a mechanical script exit, not self-grading. Regression coverage filed as #2997 |
| Design concept — shared understanding, not an artifact | ADOPT (vocabulary) → lane 6 | The general-domain interview's shared-understanding terminal (no Brief, no artifact) operationalizes it; no new machinery. Term already on #2904's adoption list |
| Shift+Tab cycling / plan-mode entry (C7); ExitPlanMode approval flow + EnterPlanMode (C8) | CONFIRMED | Recorded as-is from the contract's verdict table |
| `/plan` views the current plan (C9) | PARTIALLY TRUE | `/plan [description]` ENTERS plan mode; no documented command views the plan — the lesson's claim corrected in-row |

## Lane 5 — grilling parity (#2903, closed 2026-08-18)

Interview: 1 round (4 questions) + a user-invoked `/planning:audit-answers` adversarial pass —
two fresh-context validators, each reviewing the whole answer set with the producing session's
rationale withheld, each fetching the upstream grilling-family primaries independently. The
audit CHALLENGED the provisional zero-work-items answer and corrected two evidence
attributions; merged per the one-dissent-wins rule. **One work item filed**:
[#2998](https://github.com/melodic-software/claude-code-plugins/issues/2998).

| Claim / concern (lesson) | Verdict | Detail |
|---|---|---|
| grill-execute-clear: design tree | PARITY (attributed) | The tree model is verbatim-adjacent in the interview's loop doc; the decision-tree ledger is its persistence; rename recorded in the SSOT |
| Frontier rounds | PARITY (attributed) | Core loop, including dependency-goes-to-a-later-round and non-blocking sub-agent fact dispatch |
| Empty-frontier stop | PARITY+ (corrected by audit) | The user-confirmation gate itself is PARITY — upstream has it verbatim ("Do not act on it until the user confirms"). The genuine house strengtheners: the mechanical register-gate script, the ask-time register + drift check, the testable-acceptance-criteria stop, and me-mode's named-assumption-is-not-a-stop rule |
| "Execute" step | DELIBERATELY DIFFERENT | The interview hands off (Step 5 routing), never executes — pre-clarity is a discovery stage |
| "Clear" step | DELIBERATELY DIFFERENT — course side UNVERIFIED | The course lesson is unreachable (egress-blocked) and upstream's own repo docs teach the opposite ("Hand the same conversation straight to to-spec"). Our recommend-clear (never auto-clear) sits post-Brief and is licensed by Brief/ledger persistence — which dissolves upstream's own recorded no-ledger complaint. Loop-position nuance recorded; lesson text re-opens this row if supplied (tracked) |
| Emoji anchors + answer-by-number | CURRENT — no change | Opt-in default-off is the recorded deliberate adaptation; our any-order/partial-round/accept-shorthand set is a superset. Two cosmetic unadopted deltas noted, deliberately unfiled: upstream's bolded question-title slot; his answer-the-recommendation polarity note |
| Ungrillable question → prototype detour | ADOPT — filed #2998 | Both validators: absent from the interview (grep-confirmed), while upstream fires it mid-grilling ("stop grilling… build the throwaway version… come back and answer in one line"); our route exists only downstream (wayfind / plan / brainstorm) |
| Plan-mode-off while grilling | ADOPT — filed #2998 | Beyond upstream's taste point, a mechanical edge the audit surfaced: the ask-time register write is load-bearing and plan mode's read-only enforcement blocks it; includes reconciling `planning:plan`'s clarifying-rounds-in-plan-mode sentence with the lane 4 asset-rush doctrine |
| Grilling as a primitive, not a scheduled step | PARITY | The interview is exactly the primitive `prd`/`design`/`plan` reach for (propagated per the SSOT rows); our single dual-invocable shape also dissolves upstream's most-reported bug (partial dependency loading across its wrapper skills) |
| Provenance correction (adjacent, from the audit) | CORRECTED in SSOT | The PR-#532 row's "ADR 3-gate + glossary purity are house additions" claim is contradicted on current upstream main (`domain-modeling` carries both near-identically); annotated as convergent-or-derived, direction unverifiable |

Harvest notes for lane 6: the lane 3–4 C-row citations point at the contract PLAN.md on the
UNMERGED `claude/plan-mode-discussion-55kszx` branch — graduate or re-cite before that branch
is deleted; C8 was confirmed via the contract table only (not re-reproduced by the audit).

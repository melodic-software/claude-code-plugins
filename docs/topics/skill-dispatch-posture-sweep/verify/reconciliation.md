# Reconciliation — independent verification vs. the ledger

Two validators re-audited 49 of the 138 skills blind: they received the locked decisions and the
audit criteria, and were explicitly barred from reading the `## Rows` section or any batch artifact.
Their verdicts were diffed against the ledger by script.

| | Skills | Agree | Disagree |
|---|---|---|---|
| validator-A (B01 + B06 sets) | 22 | 17 | 5 |
| validator-B (B03 + B09 sets) | 27 | 21 | 6 |
| **Total** | **49** | **38 (78%)** | **11 (22%)** |

## The disagreements are not noise

Five of eleven are adjacent-category and change no behavior — both sides say don't dispatch
(`adhd:clarify`, `planning:brainstorm`) or both say dispatch and differ only on whether it is the
default (`docs-hygiene:audit-noise`, `session-flow:reanchor`, `session-flow:retro`).

The remaining six flip posture, and **both validators independently traced their disagreement to the
same three ambiguities in the criteria** — not to a judgment call about the skill. Each ambiguity
produces inconsistent verdicts *across batches* too, which means the original sweep already contained
the inconsistency; the validators surfaced it rather than introducing it.

## Ambiguity 1 — Decision 3 vs. Amendment 4: is nesting optional or a prerequisite?

Decision 3 makes `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` an optional detected capability whose absence
means "slower, same coverage." Amendment 4 says that for skills mandating a fresh-context fan-out as a
*correctness control*, absence silently degrades the control — so the env var is a hard prerequisite.
Both are in the Brief. Rows involving nested fan-out are therefore underdetermined.

Affected: `/claude-config:audit-instructions` (ledger DISPATCH-DEFAULT, validator INLINE-ONLY),
`/docs-hygiene:audit-derivability` (same split). Validator-A: *"Every non-recursion signal points at
dispatch. Highest-value row to ratify."* Validator-B: *"Under Amendment 4 this row becomes
DISPATCH-DEFAULT-with-nesting-required."*

**Recommended resolution: Amendment 4 governs.** B03 documented an observed failure rate for
self-audit substitution (4/4 reverse-direction edits in one compression wave). A contaminated context
running longer is not a fresh context — sequential execution cannot substitute for independence. The
consequence is that the verdict vocabulary needs a **gate annotation** rather than a fourth value:
*DISPATCH-DEFAULT (requires nesting)*. Without the annotation the row is a silent correctness
regression on any machine lacking the env var.

## Ambiguity 2 — does dispatch satisfy a skill's own fresh-context requirement by construction?

B11 applied this argument affirmatively to `/verification:confirm`: the skill demands a verdict "from
an agent that did NOT produce the artifact," so dispatching it satisfies that invariant by
construction — the argument for dispatch is correctness, not token cost. B09 did **not** apply the
same argument to `/review:quality-gate`, whose contract is the same shape, and verdicted INLINE-ONLY.
Same reasoning, opposite outcomes, different batches.

Affected: `/review:quality-gate` (ledger INLINE-ONLY, validator DISPATCH-OPTIONAL).

**Recommended resolution: the argument holds, with a limit.** Dispatching a verify-shaped skill does
satisfy producer ≠ critic when the parent is the producer. It does **not** satisfy *fan-out breadth* —
dispatching `quality-gate` yields one fresh agent, where its contract calls for a reviewer per lens.
So: independence yes, breadth no. Rows resting on independence alone flip to dispatchable; rows
needing N independent lenses fall back to Ambiguity 1.

## Ambiguity 3 — is a start-of-run gate a blocker, or pre-dispatch parent work?

B04 treated `/github:audit`'s scope confirmation as *"pre-dispatch parent work"* — the parent resolves
scope, then spawns with it fixed — and verdicted DISPATCH-DEFAULT. B03 treated `/discovery:blindspot`'s
step-1 intake question as a hard blocker and verdicted INLINE-ONLY. Structurally the same gate, at the
same position, resolved oppositely.

Affected: `/discovery:blindspot` (ledger INLINE-ONLY, validator DISPATCH-OPTIONAL),
`/bug-report:write` and `/planning:draft-goal-condition` on a related reading.

**Recommended resolution: a gate at the START of a run is pre-dispatch parent work, not a blocker.**
The parent asks, fixes the answer, and dispatches with it in the prompt. The mid-flow test in the
criteria already implies this — a question the parent can answer *before* spawning is by definition
not mid-flow — but it was never stated, so batches split on it.

## The unifying principle

All three resolutions are the same rule, and it is the rule the load-time machinery inventory arrived
at independently:

> **The parent owns the pre-dispatch envelope.** Precomputed values, scope confirmation, intake
> answers, dispatch-budget authorization, and capability checks are resolved in main context and
> passed into the dispatch prompt. The dispatched agent owns a bounded middle with no load-time
> machinery, no user turn, and no unresolved scope.

Stating that once removes all three ambiguities and, per the machinery inventory, is also what makes
the 34 preload-risky candidates dispatchable at all.

## Status

These are recommendations, not applied re-verdicts. The affected rows stay as the ledger has them
until the three ambiguities are ratified; applying them unilaterally would repeat the error the
validators just caught — resolving a genuine decision inside the artifact instead of surfacing it.

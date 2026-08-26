# Pre-PR ordering — where outcome verification sits

Owner doc for the ordered pre-PR sequence that more than one plugin routes into. It owns the
**order**; it does not own the checklist. `/session-flow:workflow` runs the human-facing
pre-PR sequence that implements this order, and remains the place to read *what*
each step does.

This convention exists because the registry's own trigger fired: a second plugin adopted an
ordering. `implementation:implement`'s completion step, titled "Hand off to the pre-PR sequence,"
prescribed outcome verification *before* review; `pre-pr.md` places review at step 2 and outcome
verification at step 7, and declared its order unreorderable. Two surfaces, one order, in
disagreement — the exact failure this registry prevents (#3047).

## The order

1. Test thoroughly
2. Review
3. Stage surgically
4. Simplify
5. Review the simplify diff
6. Re-test after simplify
7. **Verify outcome**
8. Open the PR

## The rule, and why this order

**Outcome verification is rendered on the code that ships — after the simplify pass, not before
it.** Steps 4–6 mutate the diff. A verdict rendered at step 3 is a verdict about code that no
longer exists by step 8, and the simplify edits then ship carrying an outcome claim nothing
tested them against.

The competing reading — confirm the thing *works* before spending review effort on it — is
already served, and earlier: step 1 gates the sequence on passing tests, and a caller like
`implement` has run its own build check and full test pass before it ever reaches the handoff.
What outcome verification adds is the *result-versus-intent* judgment with evidence, and that
judgment is only true of the final artifact. So "does it work" stays first; "did it achieve what
we set out to do" stays last.

The fleet had already settled this everywhere except the one site: `verification`'s own chaining
table (`skills/confirm/SKILL.md`) triggers on "review gate passes (no blocking findings)" and
*then* suggests `/verification:confirm`, and suggests the PR flow only after a CONFIRMED verdict.
The skill that renders the verdict, the skill that lists the sequence, and the plugin that opens
the PR all agreed; `implementation:implement`'s handoff step was the lone dissenter. That made
this a correction of one surface rather than a choice between two doctrines.

## Who is bound

Any plugin that routes into the pre-PR sequence — by naming its steps, by handing off to it, or
by invoking a step's implementing skill at a fixed point — states the order as this doc states it,
or cites this doc rather than restating a different one. That includes the handoff site in
`implementation:implement`, which cites this order instead of prescribing its own.

Binding the order does not bind the *invocation*. A cross-plugin step is still reached through a
presence-gated reference with a stated fallback, per
[`seam-phrasing`](../seam-phrasing/README.md) — gating whether `/verification:confirm` runs never
moves where it runs.

## What has no seam

The sequence structure — its steps and their order, including the simplify pass at 4–6 — is not
consumer config, and no plugin in this fleet reorders it at a handoff point. What *is* honored is
everything applied at each step: a consumer's own commands, its review criteria, and any mandatory
gates such as security review or approval, independently enforced by that consumer's CI and branch
protection. A consumer whose required ordering genuinely differs runs that ordering as its own
documented workflow, separately from these skills, rather than by editing a plugin.

## Conformance

Fleet audits check, per bound surface, that no plugin states a pre-PR step order conflicting with
the list above, and that a surface handing off to the sequence cites it rather than re-listing it
in another order.

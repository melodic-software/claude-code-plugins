---
description: "Re-anchors adversarial self-scrutiny: stops coasting on output, re-examines whether it is sound (not merely confident) in a fresh-context pass blind to its reasoning, and remediates with the user. Use when: 'scrutinize don't coast', 'wait, stop', 'are you sure about this', 'second-guess this', 'poke holes in what you just did', \"you're steamrolling\", 'push back on yourself', with an optional focus, or at conversation start to set the posture."
user-invocable: true
disable-model-invocation: false
metadata:
  discipline-batch: never  # needs a non-fork fresh context and stops to remediate WITH the user. Incompatible with the autonomous fork audit fan-out; invoke directly
  workflow-stage: anytime
  summary: Re-examine your own recent output through a fresh-context pass
---

# Scrutinize, don't coast

A drift corrector for adversarial self-scrutiny. The shared method (re-anchor,
audit the work in flight, correct forward, report) lives in
[`${CLAUDE_PLUGIN_ROOT}/context/re-anchor-audit-correct.md`](../../context/re-anchor-audit-correct.md).
Read it; this file adds only what is specific to adversarial self-scrutiny,
and the three declared deltas this corrector makes to the shared loop.

## The discipline this re-anchors

This corrector re-anchors a *meta* discipline: **adversarial self-scrutiny of
your own recent output.** The lens is not "does this conform to discipline X"
but "is this actually right, and would it survive a hostile second look."

Resolve the source of truth per the method doc's ladder: if the consuming project
states a self-scrutiny / verify-before-acting discipline in its own `CLAUDE.md` or
`.claude/rules/`, re-anchor THAT. Otherwise re-anchor this portable baseline:

- **Confidence is not correctness.** Output that flows smoothly and reads as
  finished has not thereby been tested. Treat "this looks done" as the cue to
  scrutinize, not the verdict.
- **Attack the work, don't defend it.** The pass looks actively for what is
  wrong (a wrong assumption, an unstated leap, a case not handled, a claim not
  backed, a requirement quietly dropped) rather than re-reading for
  reassurance.
- **The producing context is the weakest critic.** The reasoning that made a
  mistake plausible is still active, so a hostile look must come from outside it
  (see the fresh-context rule below).
- **A clean pass is a real outcome.** Scrutiny that finds the work sound reports
  clean. The duty is to look hard, not to manufacture a fault.

## Three deltas to the shared loop

Declared here per the method doc's "Declared step deltas" allowance:

1. **Stop first.** An inserted step between the loop's step 1 and step 2:
   re-anchoring happens on skill load as always, then the current trajectory
   halts before the audit runs. Do not push the in-flight action one step
   further before the re-examination has run: the trigger *is* "you are moving
   too fast on this."
2. **Remediate *with* the user, not autonomously.** The shared loop's step 3
   (correct forward) becomes collaborative: surface the adversarial findings
   and work the fixes **with** the user rather than barrelling ahead into an
   autonomous rewrite. The user just hit the brakes, so they stay in the loop
   on what changes. Purely mechanical, unambiguous corrections (a typo the
   pass surfaced) are still fixed directly; anything carrying a judgment call
   is proposed and worked jointly.
3. **The step 2 self-audit runs in a fresh-context subagent**, not in the
   producing thread (next section).

The shared method doc's outward-artifact carve-out is unchanged: nothing here files
a PR, issue, or published comment without the user's explicit opt-in.

## The adversarial pass runs in a fresh context (mandatory)

For every other corrector the method doc's fresh-context re-derivation is an
escalation; for this one it is the **core step**. It **must** run as a
fresh-context (non-fork) subagent, blind to the reasoning that produced the
output: handed the artifact and the requirement, not the story of how the work
was reached, and told to find what is wrong. Never use a fork subagent for this
pass. (This means the Agent tool's fork subagent type. A *skill's* `context: fork`
frontmatter is a different mechanism the docs also call fork, and this rule does not
exclude it.)

- **Pointer**: when choosing the subagent for this pass, fetch
  <https://code.claude.com/docs/en/sub-agents#how-forks-differ-from-other-subagents>
  live for what a fork inherits; for the skill-side `context: fork` contrast, fetch
  <https://code.claude.com/docs/en/sub-agents#preload-skills-into-subagents> live.
- **As of**: 2026-10-11
- **Recheck trigger**: either section changes what a fork inherits from the main
  session, or whether a skill run with `context: fork` starts without conversation history.

The findings return to this thread, and remediation proceeds *with* the user
(delta 2).

## Optional focus

An optional focus scopes the re-examination. "the migration logic", "the security
assumptions", "the numbers in that table". Given a focus, aim the adversarial pass
at it specifically; given none, target the most recent substantive output. A focus
narrows aim; it never suppresses a serious flaw the pass finds outside it. Surface
that too.

## Audit. What to look for

This is the brief handed to the fresh-context pass: the method doc's step 2
run there rather than here, so the findings come back concrete and located:

- an output presented as finished that was never tested against its actual
  requirement;
- an assumption the work rests on that was never stated or checked;
- a case, input, or failure mode the work silently does not handle;
- a claim or number asserted with confidence but not backed;
- a requirement or constraint that quietly got dropped between the ask and the
  output;
- a leap where the reasoning skipped a step and momentum carried it past.

Correct each per the deltas: surface what the pass returns, and work the fix WITH
the user (fixing trivial mechanical items directly).

## What this skill does NOT do

- **Not a pre-implementation plan stress-test.** Attacking a plan or proposal
  *before* the work is built is `/planning:devils-advocate`. This corrector
  re-examines output *already produced*. Route "poke holes in this plan before
  we start" to devils-advocate; degrade to prose when it is not installed.
- **Not a review checkpoint.** A structured review pass between "code works" and
  "code is ready" routes to `/review:quality-gate`, invoked via the Skill tool (degrade to
  prose when it is not installed).
- **Not a single-axis corrector.** It is the *general* adversarial re-look.
  When a flaw is squarely one axis (an unverified claim), hand that part to the
  sibling that owns it (`/discipline:do-your-research`) while keeping the general
  scrutiny here.

## Gotchas

- Re-reading your own work in the same context and feeling reassured is not the
  adversarial pass. It is the bias the pass exists to defeat. The hostile look has
  to come from the fresh-context subagent, not a second read by the producer.
- "Stop" means stop the trajectory, not stop the conversation. Interrupt
  momentum long enough to scrutinize, then remediate with the user. Do not
  abandon the task.
- A clean result is not a failure to try. If the fresh pass genuinely finds nothing
  wrong, say so plainly rather than downgrading a non-finding into a vague caveat.

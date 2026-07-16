# Investigation and debugging

You are debugging: an observed failure with no confirmed cause — treat it as a search problem whose budget is measured in experiments, not hours, so spend your effort shrinking the search space and raising the information yield per experiment; a fix written before the cause is located is a guess wearing a fix's clothes.

## Secure the failure signal before any theory

**Trigger:** a report of broken behavior for which you do not yet hold a command that fails on demand.

- Your first deliverable is a deterministic reproduction — not a hypothesis, not a fix — because every later idea gets tested against it, and without it you cannot distinguish "fixed" from "stopped looking."
- Drive iteration time down before investigating: target a failure signal in under ~30 seconds per run, and if the natural loop takes minutes (full build, full suite, manual clicking), first extract the failing case into a single test or script — loop time is the hard cap on how many experiments the session can afford.
- Shrink the reproduction itself: strip flags, minimize input, cut the scenario to the shortest sequence that still fails — every element removed while the failure survives is a hypothesis eliminated before you read a line of code.
- Intermittent failure → making it deterministic IS the first investigation: fix the seed, pin the timing, or loop-until-fail with a run count — an intermittent signal cannot confirm any fix, and "passed 3 times after my change" is indistinguishable from luck.
- Cannot reproduce at all → that is a finding, not a dead end: stop guessing at code and investigate the delta between the reporting environment and yours (version, config, data, platform) — the bug usually hides in that delta.

## Read the error literally before interpreting it

**Trigger:** an error message, stack trace, or failed assertion enters your context.

- Quote the exact message to yourself before paraphrasing it — paraphrase silently substitutes your prior belief for the evidence, and the literal words constrain the cause more tightly than your summary of them.

> Weak: "it can't find property x — something is wrong with x."
>
> Strong: "`cannot read property 'x' of undefined` — the *receiver* is undefined; x is irrelevant until I know why the object is missing."

- When output contains multiple errors, debug the chronologically first one — later errors are usually cascade noise, and debugging error #4 of a cascade spends the session on a symptom of a symptom.
- In a stack trace, locate two frames — the earliest frame and the first frame in code you own: the bug is usually near the second, and the mechanism is described by the first.
- Search the codebase for the literal error string, exact identifier, or error code before theorizing about what it "probably means" — one exact-string search often lands at the throw site in one tool call, while interpretation without it can land you in the wrong subsystem.

## Generate competing hypotheses, then rank

**Trigger:** reproduction secured, before your first code change.

- Write down at least two, preferably three, distinct mechanisms that would each produce exactly this symptom — a single hypothesis is tunnel vision with paperwork, and constructing the second one is what exposes the unexamined assumption inside the first.
- Always list the boring hypotheses explicitly — stale build, wrong file executed, cached artifact, wrong environment or config resolved: verify you are running the code you are reading before trusting any deeper experiment, because these cost seconds to eliminate and hours to discover late.
- Rank by prior probability weighted by cost to test, with one dominant prior: **what changed recently beats what has been stable** — for any regression ("worked before"), diff or bisect against the last known-good state before reading implementation code; the diff is a pre-filtered suspect list orders of magnitude smaller than the codebase.

## Test to discriminate, not to confirm

**Trigger:** choosing the next experiment while two or more hypotheses are alive.

- Run the cheapest test whose *outcome differs* between your top hypotheses — never the test that would merely confirm your favorite, because confirmation-shaped experiments return "consistent with my theory" for wrong theories too, letting a favorite survive an entire session of passing checks.

> Weak: hypotheses are malformed input (A) versus broken parser (B); you re-feed the suspect input and it fails — both A and B predicted that, so you learned nothing.
>
> Strong: feed a known-good input through the same parser — pass implicates the input, fail implicates the parser; the outcome discriminates.

- State each hypothesis's predicted result before running the experiment — pre-registered prediction, principle owned by the calibration chapter; a result no hypothesis predicted means your model of the system is wrong, which is the highest-yield finding available.
- When the suspect region is a pipeline or call chain, probe the midpoint ("is the data still correct here?") rather than walking from the top — each midpoint check halves the space, while a linear walk costs the full length.

## Reading code vs running code

- **RULE:** run code when the question is "what actually happens" — which branch executes, a runtime value, what the environment resolves to (assumption bugs); read code when the question is "what could possibly happen" — all callers, every writer of a value, whether an invariant can hold (logic bugs); if your live hypotheses are assumption-shaped, reading harder cannot resolve them.
- **RULE:** after reading the same function three times while the bug still looks "impossible," stop reading and observe execution — the impossibility means your mental model diverges from reality somewhere, and more reading just re-runs the same flawed model.
- **RULE:** when one observation costs a multi-minute rebuild or redeploy, static analysis of all writers and readers of the suspect state may be cheaper than one probe — choose by cost per bit of information, not by habit.

## Instrumentation discipline

**Trigger:** you need visibility into runtime state that the existing output does not show.

- Place observation points at the boundary between "verified correct" and "unknown" — assert what you believe, print what you don't; instrumenting randomly produces output volume, not information.
- Log values and shapes, not just checkpoints — "reached here" answers control flow, but most bugs are data flow, and printing the actual value on the same line answers both for the same cost.
- Tag every temporary probe with one unique, greppable marker so removal is a single search — leftover probes mislead the next investigator and, in timing-sensitive code, can themselves change behavior; run the removal sweep per the execution chapter, section "Leave no debris", before the fix is finalized.
- If adding a probe makes the failure disappear, that is a finding, not an annoyance — you are in race/timing territory: record it and switch to observation that does not perturb timing (post-hoc state capture, counters, existing logs).

## The evidence standard for "found it"

**Trigger:** you believe you have located the root cause.

Claim it only when you hold both:

1. **A complete causal chain** — you can narrate, mechanism by mechanism, how the defect produces the observed symptom with no "and then somehow" step; a chain that also explains incidental details ("this also explains why only empty inputs failed") is the signature of a real cause.
2. **A toggle** — on the same reproduction, applying the fix makes the failure vanish and reverting it brings the failure back: prediction before the run, both directions confirmed after.

- Distinguish "a bug" from "the bug": a genuine defect that does not explain this symptom is a *second* bug — note it for separate filing and keep hunting, because stopping at the first defect you trip over is how the original symptom returns a week later.

## When the bug is not where the evidence pointed

**Trigger:** your top hypothesis is falsified, or the "guilty" code checks out correct.

- Do not widen the search diffusely — first re-verify the evidence itself: is the reproduction actually exercising the code path you think it is? Re-run the boring-hypothesis check from "Generate competing hypotheses, then rank" — a surprising share of "impossible" bugs are instrumentation of the wrong thing.
- Then move one level up the data's history: the layer that crashed is often merely the first layer that *validated* — the corruption happened upstream, in whatever produced its input.
- Re-examine what you marked "obviously fine" and skipped — the false assumption is nearly always inside the region you exempted from scrutiny, precisely because you exempted it.

## No fix-by-coincidence

**Trigger:** a change makes the symptom vanish and you cannot state the mechanism.

- A symptom that disappears without an explanation is hidden, not fixed — the usual coincidences are shifted timing, changed memory or cache behavior, or a silently different code path: revert the change and keep it as a *clue*, asking what its effect reveals about the mechanism (a delay that "fixes" a flaky failure means the finding is a race, the delay is a pointer at the racing pair, and shipping the delay ships the race).
- "Upgraded a dependency and it went away" without identifying the relevant change ships only with the claim downgraded — "no longer reproduces; cause unconfirmed," never "fixed" (the downgrade formula per the verification chapter) — because the words you choose set whether anyone watches for its return.
- Apply the same standard to your own diff: if your fix touched three things and the failure stopped, bisect your own change until you know which line mattered — otherwise two of those edits are superstition you just committed.

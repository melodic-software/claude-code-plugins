# Performance techniques

Techniques for finding, proving, shipping, and protecting a performance win, in the order the loop
uses them. Each entry gives the idea, when to use it, the counter it yields, how it fails, and the
skill step that uses it. Figures from the source post appear only as examples, each marked
vendor-claimed (blog, 2026-09-23). The rules a harness must meet before any number is reported live
in [harness-integrity.md](harness-integrity.md); terms are defined in [glossary.md](glossary.md).

Sources: [How we made claude.ai 3x faster in two weeks][post].

## Contents

- [A. Choose the target](#a-choose-the-target)
- [B. Define the goal and its boundary](#b-define-the-goal-and-its-boundary)
- [C. Lab measurement and rigs](#c-lab-measurement-and-rigs)
- [D. Prove the proxy](#d-prove-the-proxy)
- [E. Diagnose](#e-diagnose)
- [F. Optimization patterns (latency catalog)](#f-optimization-patterns-latency-catalog)
- [G. Protect the win](#g-protect-the-win)
- [H. Ship, roll out, read the field](#h-ship-roll-out-read-the-field)
- [I. Steer and orchestrate](#i-steer-and-orchestrate)
- [J. Write the result up](#j-write-the-result-up)

## A. Choose the target

**Measurement makes it tractable.** Once a target has a number that can be re-run on demand, it can
be optimized. Measuring is step one of the climb, not setup before it, so adding a measurement is
usually the highest-leverage move available: anything countable is climbable. When: any time the
candidate list is ranked on suspicion. Counter: whichever count the new instrument produces. Fails
when: the new number does not track what users feel (see [D](#d-prove-the-proxy)). Used by:
`/performance:target` Evidence tiers ("instrument this first").

**Keep finding things to measure.** When the current measurements stop yielding, add a new one
instead of guessing harder. Every instrument finds something, and instruments compound: each new
one opens more candidates. When: the ranked list has gone flat or every candidate is E3 or E4.
Counter: the new instrument's. Fails when: instruments pile up with no owner and no correlation
check. Used by: `/performance:target` Evidence tiers.

**User complaints are valid starting signal.** Reports that the product feels slow are a legitimate
candidate source, never a ranking basis. When: a user or teammate names a slow operation. Counter:
none until instrumented. Fails when: the anecdote is ranked above a measurement. Used by:
`/performance:target` Inputs.

**Journey-based scoping.** Pick the few user journeys that cover most usage and optimize those.
Crossing journeys with platforms and products gives the **measurement matrix**, the full list of
measurements to baseline. Tie every candidate project to the journey it moves (**project list tied
to journeys**). When: the product surface is wide and effort must be pointed. Counter: one per
matrix cell. Fails when: journeys are chosen by intuition rather than from usage data. Used by:
`/performance:target` Inputs and Output. Example: four journeys covering 95% of activity gave
thirteen measurements ([post]; vendor-claimed (blog, 2026-09-23)).

**Audit telemetry before trusting it.** Check existing telemetry for accuracy and coverage before
ranking from it. When: a telemetry store is the input. Counter: none; the output is a list of gaps.
Fails when: a missing event reads as zero cost. Used by: `/performance:target` Inputs (telemetry
row).

**Estimates in the target unit.** Estimate each candidate's impact in the metric's own unit
(milliseconds, spawns) and sum them to size ambition. An estimate is an E3 note; it never sets the
goal. When: sizing a set of candidates. Counter: none. Fails when: the summed estimate becomes the
target. Used by: `/performance:target` Evidence tiers (E3).

**Subscriber census on a hot interaction.** Count the observers, hooks, and subscriptions that run
on a per-input path (a keystroke, a tool call). When: an interaction feels slow and does little
visible work. Counter: subscribers fired per interaction. Fails when: the census counts
registrations instead of executions. Used by: `/performance:target` E1; for process spawns,
[`scripts/spawn-census.sh`](../scripts/spawn-census.sh) already runs it. Example: thousands of hooks
and hundreds of store subscriptions re-rendering on every keystroke ([post]; vendor-claimed (blog,
2026-09-23)).

**Hot-path awareness.** When nearly everything touched is a hot path, raise the bar for every
change: more tests, smaller diffs, flags. When: the target is startup, input handling, or a
per-event path. Counter: none. Fails when: a hot-path change ships with cold-path review. Used by:
`/performance:target` Output.

**Opportunity refresh prompt.** Periodically ask what has not been explored, what can be climbed,
and where the most opportunity is now, and **invite divergent ideas** explicitly. When: early
targets were hit, or the list has gone stale. Counter: none. Fails when: the refresh re-ranks the
same list without adding a measurement. Used by: `/performance:target` (re-scan). The prompt, as
quoted in the post:

> we've ended up funding nearly every project in the original projects list and more. let's do a
> refresh […] what have we not explored, what can we hill climb on, where is the most opportunity
> at this point? […] i am open to WACKY ideas

## B. Define the goal and its boundary

**Time-to-usable as the end event.** End the measurement when the user can act (the input accepts
typing), not when loading finishes. Pair it with **comparable boundaries**: every measurement
starts at a user interaction, ends at the rendered result, and separates client from server work
(the client-side share of a round trip is its own number). When: writing the metric for any
user-facing operation. Counter: none; this fixes what the duration means. Fails when: two
measurements with different start or end events are compared. Used by: `/performance:goal` §1.

**Name the start state.** Cold start, fresh load, and warm navigation are different measurements.
Say which one. When: every goal. Counter: none. Fails when: a warm number is reported against a
cold baseline. Used by: `/performance:goal` §1.

**Field percentile as the headline.** Report a real-user percentile per journey. When: field data
exists. Counter: none. Fails when: a lab mean stands in for a field percentile. Used by:
`/performance:goal` Percentiles (the plugin keeps p50 and p95 as its house default). Example: the
post reports p75 per journey ([post]; vendor-claimed (blog, 2026-09-23)).

**Define the defect precisely.** Count only what the definition covers. For layout movement: shifts
after the page is usable, without user input. When: the target is a defect rate, not a duration.
Counter: occurrences under the definition. Fails when: the definition is loose enough to count
user-caused movement. Used by: `/performance:goal` §1.

**Measure the underlying signal.** Go below a composite score to the raw events it is built from.
When: a composite score is green while the symptom is visible. Counter: raw event count or
magnitude. Fails when: the raw events are summed back into the same composite. Used by:
`/performance:goal` §1 and Gotchas. Example: individual layout shifts of about 0.008, well inside a
0.1 "good" threshold, on a page users saw as janky ([post]; vendor-claimed (blog, 2026-09-23)).

**Instrumentation parity.** Give every product or surface the same timing marks so their numbers
compare. When: one surface lacks the marks the others have. Counter: none. Fails when: surfaces are
ranked against each other with different marks. Used by: `/performance:goal` §1.

**Baseline window.** New instrumentation yields a number only after data accumulates. Plan for the
window, and use a lab measurement meanwhile. When: the metric depends on field data that does not
exist yet. Counter: none. Fails when: a goal is set before the baseline exists. Used by:
`/performance:goal` §2.

**Price effects in frame budget.** State a visual effect's cost as a share of the frame budget (16.7
ms at 60 Hz, 8.33 ms at 120 Hz). When: an animation or effect competes with rendering. Counter:
milliseconds per frame, or frames over budget. Fails when: the effect is judged on appearance
alone. Used by: `/performance:goal` §1; the human rules on the tradeoff (see
[F](#perceived-performance)).

## C. Lab measurement and rigs

**Lab faster than deploy cadence.** Build lab measurements so iteration does not wait for field
data. **Unattended runs need a lab signal**: an agent working for hours or overnight needs a local
number it can re-run by itself. When: the field read takes longer than one iteration. Counter: the
lab benchmark's. Fails when: the lab number is never checked against the field (see
[H](#h-ship-roll-out-read-the-field)). Used by: `/performance:snapshot`.

**Reproduce with a benchmark.** Find or build a benchmark that shows the problem before fixing it.
When: always, before a fix. Counter: the benchmark's. Fails when: the benchmark passes on the
unfixed base. Used by: `/performance:target` and `/performance:snapshot` baseline.

**Instruction-count recipe.** For pure-language hot paths, count instructions executed under a CPU
simulator and compare against a checked-in baseline. A **deterministic counter needs one run**;
sample counts and percentiles apply to durations. When: the hot path is CPU-bound code in one
process. Counter: instructions executed (`Ir` under Cachegrind). Fails when: the "deterministic"
mode is assumed rather than checked; run the count twice first (harness-integrity rule 1). Used
by: `/performance:snapshot` step 2. Specifics are in the verification records below.

**Deterministic counter ladder.** When instruction counts are unavailable (a browser, a multi-process
path), climb down this ladder until one works:

| Counter | Where it applies |
|---|---|
| Instructions executed | Single-process, CPU-bound code under a simulator |
| Framework commits (renders) per interaction | UI frameworks with a commit phase |
| Function call counts | Runtimes with precise coverage |
| Layout and style recalculation counts | Browser rendering |
| DOM mutations | Browser pages |
| Process spawns, syscalls, queries, round trips | Shell, service, and data paths (this plugin's default) |

Used by: `/performance:target` "Name the counter"; `/performance:snapshot` step 2. Fails when: a
counter is climbed before it is shown to track the clock ([D](#d-prove-the-proxy)).

**Attribute by region and phase.** Tag each event with the named region it hit (sidebar,
transcript) and the phase it happened in (before first paint, after usable). When: one aggregate
hides several independent causes. Counter: events per region per phase. Fails when: region names
drift from the UI they label. Used by: `/performance:snapshot` step 2; `/performance:target` for
naming the symptom.

**Force the bad ordering in a test.** Write an integration test that deliberately delays one
dependency (hold data until after first paint) so a race reproduces every time. With it, **a binary
test is the benchmark**: for a defect that either happens or does not, the benchmark fails on any
occurrence. The proof is red N/N on the base and green N/N on the change, with N chosen per check
and recorded ([harness-integrity rule 3][hi3]). When: the defect is intermittent. Counter: failing
runs out of N. Fails when: the forced delay does not match the real ordering. Used by:
`/performance:snapshot` and `/performance:verify` §3. Example: 20 of 20 red on main, 20 of 20 green
on the fix ([post]; vendor-claimed (blog, 2026-09-23)).

**Count the defect in the recording.** Turn a recording into counts: rows that jump, appear, and
vanish. When: the only evidence is a screen recording. Counter: moved, appeared, and vanished
elements. Fails when: frames are sampled too sparsely to see a move. Used by:
`/performance:target` Inputs.

**Representative content in the corpus.** Benchmarks and differentials include realistic content:
non-ASCII punctuation, long inputs, large documents. When: building any benchmark corpus. Counter:
none. Fails when: an ASCII-only corpus misses a slow path real content triggers (see
[F](#make-the-hot-path-cheap)). Used by: `/performance:snapshot`; `/performance:verify` §2.

**Report first pass and later passes separately.** Cold first execution and warm repeats are
separate numbers. When: the path compiles, caches, or allocates on first use. Counter: per-pass
duration or count. Fails when: an average hides a slow first pass. Used by: `/performance:snapshot`
Warmup.

**Name the lab's blind spot.** State what the harness cannot see: a headless browser has no browser
UI to resize, a container has no GPU. **Environment-specific conditions** (managed or
policy-configured environments) belong on the same list. When: every lab report. Counter: none.
Fails when: a lab pass is reported as covering the field. Used by: `/performance:verify` §2 (the
unexercised mode).

**Put the metric in the demo.** Embed a live readout of the metric in the demonstration: a frame
rate computed from animation-frame timestamps. When: showing a perceptual fix. Counter: the
readout's. Fails when: the readout itself costs frames. Used by: `/performance:snapshot`.

**Rig checks.** Before trusting a rig against a new target, run these in order:

| Check | What it asks | Fails when |
|---|---|---|
| **Question the rig's ceiling** | Does the rig cap the metric and hide headroom? A headless browser ticking at 60 Hz cannot show 120 Hz smoothness. | A capped reading is reported as the product's limit |
| **Confirm rig capability first** | Can the harness measure the new target at all? Confirm it before re-running. | The re-run proceeds on an unconfirmed rig |
| **Deterministic stepping** | Drive time in controlled ticks so each unit (a frame) is an exact read, not a noisy one. | Stepping changes the workload's scheduling |
| **Rig self-check** | N ticks in produce exactly N units out. | The check is skipped and dropped units read as speed |
| **Budget fit per unit** | Report how many units fit the budget, not an average. A count over budget is a counter. | The mean hides the slow units |

Used by: `/performance:snapshot` steps 1-2; `/performance:goal` §2 is the floor-first analog.
Example: 240 frames out for 240 begin-frames at 8.33 ms ([post]; vendor-claimed (blog,
2026-09-23)).

### Verification records

| Claim | Basis | As of | Recheck when |
|---|---|---|---|
| `valgrind --tool=cachegrind <prog>` runs Cachegrind. Its `Ir` event counts instructions executed, and cache simulation is off by default, so `Ir` is the only event collected unless another is enabled. | [Cachegrind manual](https://valgrind.org/docs/manual/cg-manual.html) | 2026-09-23 | A Valgrind release changes the Cachegrind options section |
| `node --predictable` is a boolean V8 flag, "enable predictable mode", off by default. That it makes counts repeat run to run is not verified here. | `node --v8-options`, Node v24.20.0 | 2026-09-23 | A Node major release |
| Chrome DevTools Protocol `Profiler.startPreciseCoverage` with `callCount` collects call counts. Enabling it "prevents running optimized code and resets execution counters", so time a path without it. | [`js_protocol.json`](https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/js_protocol.json) | 2026-09-23 | The protocol file changes the command |
| `HeadlessExperimental.beginFrame` sends one BeginFrame and returns when the frame completes. It requires a target created with BeginFrameControl, and the domain is experimental. | [`browser_protocol.json`](https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/browser_protocol.json) | 2026-09-23 | The domain leaves experimental or is removed |

## D. Prove the proxy

**Discard flaky benchmarks.** A benchmark that is noisy between runs is removed, not tolerated, and
so is one whose count does not track user latency, so no one climbs the wrong hill. When: before a
benchmark becomes a target or a gate. Counter: run-to-run spread on an unchanged subject. Fails
when: a noisy benchmark is kept "for now" and later gates. Used by: `/performance:goal` §1
`Correlation:`.

**Prove-it-or-unship prompt.** Ask for proof that climbing each counter produces a measurable
wall-clock win, and remove the counters that cannot show it. When: a set of new counters is about
to become targets. Counter: none. Fails when: proof is accepted from a single path. Used by:
`/performance:goal` `Correlation:`. The prompt, as quoted in the post:

> please prove that hill climbing against each of these can result in measurable wall clock perf
> wins. we'll unship the benches for any candidates that cannot prove that

**Proxy validation experiment.** Drive the counter down on real hot paths and check that the clock
moved too. **Validate on more than one path**: at least two independent hot paths before
generalizing (two is judgment). When: a counter is proposed as a proxy. Counter: the proxy, plus a
duration. Fails when: the paths share a cause, so two paths are one data point. Used by:
`/performance:goal` `Correlation:` evidence; `/performance:verify` §4.

**Same benchmark, two rigs.** Measure the count under the deterministic simulator and the time
under the normal warm runtime, on the same benchmark. When: the counting rig distorts timing
(simulators and coverage modes are slow). Counter: both. Fails when: the two rigs run different
inputs. Used by: `/performance:snapshot`; the recipe the `Correlation:` evidence cites.

**Counts can understate the clock.** A count cut can give a larger time cut, or a smaller one.
Report both; never infer one from the other. When: every report that carries a counter. Counter:
both. Fails when: a count reduction is restated as a time reduction. Used by: `/performance:verify`
§4. Example: instructions cut 48% and 31% while wall-clock time fell 78% and 44% ([post];
vendor-claimed (blog, 2026-09-23)).

## E. Diagnose

Hand-off: a specific failure with no reproduction goes to `/debugging:debug`.

**Profile the counter.** Use the counting tool's own profile to see where the counted units go.
When: a counter is high and the cause is unknown. Counter: units per function. Fails when: the
profile of the simulated run is read as a time profile. Used by: `/performance:target` "Measure the
layers". Example: a quarter of one path's instructions were polymorphic dictionary lookups
resolving the same ID three times ([post]; vendor-claimed (blog, 2026-09-23)).

**Work causes by name.** List concrete, named offenders ("the header row that arrives late"), not a
category ("layout shift"). Then **fix in ranked batches**: fix the top offenders together,
re-measure, take the next batch. When: a defect has many causes. Counter: occurrences per named
cause. Fails when: a batch is fixed without re-measuring, so the ranking goes stale. Used by:
`/performance:target` Output.

**Hidden work no metric sees.** Trace code paths after the headline event. Work no load metric
covers, such as a silent reload, still costs. When: the headline metric is green and cost is still
suspected. Counter: occurrences of the hidden operation. Fails when: tracing stops at the event the
metric ends on. Used by: `/performance:target` "Measure the layers".

**Profile the idle state.** Profile idle sessions for background work. When: the product runs for
long periods between interactions. Counter: main-thread work per idle minute. Fails when: the
profile starts with an interaction. Used by: `/performance:target`.

**Hitch sweep.** Sweep for CPU stalls across the product instead of profiling one path. When: no
single path is suspected. Counter: stalls over a threshold. Fails when: the threshold is set above
the stalls users feel. Used by: `/performance:target`.

**Step unit by unit.** Step through the workload one unit (frame, chunk, request) at a time and time
each to find the slow ones. When: a long operation is slow somewhere in the middle. Counter: units
over budget. Fails when: units are averaged. Used by: `/performance:target`.

**Diagnosis ladder for a field report.** A report with a recording is a first-class input. Work it
in this order:

1. **Rule out your own change first.** Check your own instrument for the reporter's sessions before
   theorizing.
2. **Look up the reporter's own sessions.** Cross-reference the symptom with that user's field
   events.
3. **Arithmetic consistency check.** Predict the magnitude from the proposed cause and compare it to
   the observed value. Example: an element 18% down the page, on a page that grows 56 px, should
   move 0.18 × 56 ≈ 10 px; the recording showed 10 ([post]; vendor-claimed (blog, 2026-09-23)).
4. **Explain every qualifier.** Each qualifier in the report ("new tab only", "occasionally") has to
   be explained by the diagnosis.
5. **Intermittency as a race.** "Occasionally" often means two events race, such as first paint
   against a resize.
6. **Speedups expose latent defects.** Making something faster changes timing, which can expose a
   defect that was always there. Check whether the defect predates the change.

Counter: the reporter's own event values. Fails when: a theory is accepted that leaves a qualifier
unexplained or misses the arithmetic. Used by: `/performance:target` Inputs; `/debugging:debug`.

**Speculative loading as a cause class.** Browser prerendering and speculative loading can lay a
page out in a state the user never sees, then resize it after first paint. When: a layout defect
appears only on some navigations. Counter: shifts on prerendered loads. Fails when: the lab never
prerenders, so the class is invisible. Used by: `/performance:target` cause checklist.

## F. Optimization patterns (latency catalog)

Used by: `/performance:target` (candidate mechanisms) and `/implementation:implement`. Each pattern
still needs a measured baseline; the catalog names mechanisms, not wins.

### Perceived performance

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Static interactive shell** | Ship an inert but usable copy of the primary input in the initial HTML so users act before the framework initializes | Time to usable is dominated by framework startup | Time to first accepted input | The shell and the real UI disagree (see [G](#g-protect-the-win)) |
| **Placeholder handoff** | The real UI paints directly over the static copy; the swap itself must be invisible | Any static shell | Pixels moved at handoff | The two renders differ by even a pixel |
| **Preserve input across the handoff** | Anything typed into the placeholder survives the swap, in order | Any shell that accepts input | Lost or reordered keys | Input is dropped at swap |
| **Progressive reveal** | Reveal large structures incrementally (a table cell by cell) | A large block blocks the first paint of its region | Main-thread blocking per update | Incremental fill causes layout movement |
| **Delay the skeleton** | Show a loading indicator only after a short delay, so fast loads never flash it | Most loads are fast | Skeleton flashes per load | The delay (judgment; tune per surface) is longer than users tolerate |
| **Perceived-performance tradeoffs** | Progressive fill against complete rows, and effect cost against frame budget, are human taste calls | A change alters what users see while loading | None; a before/after ruling | The agent decides a taste call alone |

### Avoid repeated work

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Keep expensive components mounted** | Keep a costly component mounted across navigations instead of remounting it | The same component remounts on every navigation | Mounts per navigation | Stale state leaks between views |
| **Cut re-renders** | Render only the parts whose inputs changed; an incremental renderer should **touch only what changes** | Updates re-render unchanged regions | Renders or commits per interaction | Memo keys are wrong and updates are lost |
| **Memoize finished work** | Remove work that grows with total length per update by memoizing finished parts | Streaming or growing content | Work per chunk against content length | Finished parts are later mutated |
| **Deduplicate repeated lookups** | Resolve the same key once instead of several times on a hot path | A profile shows the same lookup repeated | Lookups per operation | The cached result goes stale |
| **Duplicate persistence on the main thread** | Repeated identical writes (the same snapshot cloned again) are waste; deduplicate, then move off-thread | Background persistence runs on the main thread | Writes per minute | Deduplication drops a real change |
| **Precompiled code cache** | Precompile startup code so the process does not recompile at every launch | Startup parses and compiles the same code every time | Compile time at launch | The cache is stale after an update and silently falls back |

### Anticipate

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Intent-driven prefetch** | Prefetch on an intent signal such as hover, before the click | Navigation targets are predictable | Time from click to render | Prefetches waste bandwidth or load on the server |

### Make the hot path cheap

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Cheap prefilter before an expensive match** | Run a constant-time check (the first character) before an expensive regex or parse | Most inputs cannot match | Instructions per input | The prefilter rejects a valid match |
| **Input-dependent slow path** | Some content switches the runtime to a slower representation | Performance varies with content, not size | Time per input class | The corpus lacks the triggering content |
| **Normalize before the hot loop** | Convert input to the fast representation once, before the expensive step | An input-dependent slow path is found | Time per input class | Conversion costs more than it saves |
| **Polymorphic lookup cost** | Dynamic property or dictionary lookups whose shapes vary are a hot-path cost signal (engine-specific) | A profile shows lookup overhead | Instructions per lookup | Engine-specific tuning is applied across engines |
| **Per-keystroke work is a smell** | Work that re-runs on every input event is a first-class candidate | Typing feels slow | Work per keystroke | Debouncing hides the cost instead of removing it |
| **Global selector cost** | One expensive global style rule can tax every DOM change; count recalculations to find it | DOM changes are slow everywhere | Style recalculations and their time | The rule is removed without checking what it styled |

Example of an input-dependent slow path: any non-Latin-1 character (an em dash, a curly quote) made
the engine store a whole string as two-byte, which put every highlighting regex on its slower path;
copying each code block into a one-byte string first fixed it ([post]; vendor-claimed (blog,
2026-09-23)).

### Move work

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Move growing work off the main thread** | Put incremental parsing of growing content in a worker | Parsing competes with rendering | Main-thread blocking time | Message passing costs more than the work |

## G. Protect the win

Used by: `/performance:protect` and `/performance:verify` Next.

**A benchmark has two jobs.** Each benchmark is a lab metric to move and a CI guardrail whose number
can only go down. When: a benchmark proves correlated. Counter: the benchmark's. Fails when: it
gates before it is proven ([D](#d-prove-the-proxy)).

**Ratchet mechanics.** CI fails when the count rises. A scheduled job proposes a lower ceiling when
the count falls, and a human merges it. **Ratchets hold the result** after the push ends. Gate on
counts; durations inform but are too flaky to gate. When: a counter-backed goal is MET. Counter:
the ratcheted count. Fails when: the ceiling is lowered automatically past a noisy dip, or a
duration is ratcheted.

**Wins decay.** Performance wins erode in a fast-moving codebase unless something holds them, so
**protect a proven win**: once proven, invest in keeping it. When: the win is merged. Counter: the
protected metric over time. Fails when: protection is deferred until the win is already gone.

**Guardrails scale with brittleness.** An optimization that is brittle by design gets
proportionally more guardrails. For a duplicated render (a static shell):

| Guardrail | What it checks |
|---|---|
| **Generate the copy from the source** | The duplicate is generated from the real component, and a test fails if the two drift |
| **Equivalence across configurations** | The fast path matches the real one across many viewport sizes within a tolerance |
| **Input-through-handoff test** | A test types through the transition and fails on any lost or reordered input |
| High-precision field reporting | See [H](#h-ship-roll-out-read-the-field) |

Fails when: a brittle optimization ships with the same checks as a safe one. Example: fourteen
viewport sizes within 1 px ([post]; vendor-claimed (blog, 2026-09-23)).

**Ship instruments with fixes.** A share of changes add telemetry or guardrails along with the
fix. When: every fix that introduces a new mechanism. Counter: none. Fails when: instruments are
promised for later. Example: about a third of changes ([post]; vendor-claimed (blog, 2026-09-23)).

**Scheduled jobs find opportunities.** A nightly job both catches regressions and surfaces new
candidates, and a **rig becomes a nightly job** once its sprint ends. When: a rig proved useful.
Counter: the rig's. Fails when: nobody reads the job's output.

**Tests before optimizations.** Unit tests land before the optimization. **Fix at your layer, test
the trigger**: when the cause is outside your code, fix within the layer you control and add a
test that simulates the external trigger. When: every optimization. Counter: none. Fails when: the
test is written after the change and passes on both. Used by: `/implementation:implement` (TDD).

**Codify wins as skills and guardrails.** Turn what was learned into skills and checks so new code
starts fast by default. When: the same fix recurs. Counter: none. Fails when: the lesson stays in a
thread.

**Safety mechanisms before pace.** Put review, tests, and flags in place before the fast phase
starts. When: before a push. Counter: none. Fails when: guardrails are added after the first
incident. Used by: `/performance:goal` §4 "What counts as done".

**Guardrails make volume safe.** High change volume with no incident is evidence that the
guardrails held, not that the changes were safe on their own. Example: more than three thousand
changes, no customer-facing incident or rollback ([post]; vendor-claimed (blog, 2026-09-23)).

## H. Ship, roll out, read the field

Used by: `/performance:verify` Next and the project's own release process. This plugin measures; it
does not deploy.

**PRs sized for risk and review.** Split a win into several PRs sized for their risk and for review;
one workstream produces **many small PRs**, not one large one. When: any win larger than one
reviewable change. Counter: none. Fails when: a risky piece hides in a large diff. Used by:
`/implementation:implement`.

**Flags for user-visible changes.** Put anything a user could see behind a flag. Flags are
**short-lived** by design; coordinate their rollout and cleanup in one place (**a thread for flag
lifecycle**), and **retire flags as soon as safe**, tracking the cleanup rate. Classify each flag:

| Kind | Purpose | Retire when |
|---|---|---|
| Kill switch | Turn the change off if it breaks | The change has run clean in the field |
| Ramp | Expose the change gradually | Exposure reaches everyone |

Counter: open flags, and flags retired per week. Fails when: flags accumulate with no owner.

**Staged rollout.** High-risk changes go to employees, then a small share of users, then everyone.
**Dogfooding catches what metrics miss**: internal users surface defects no metric sees. When:
every high-risk change. Counter: defects reported per stage. Fails when: a stage is skipped under
time pressure.

**Deploy regression watch as a standing duty.** Check every deploy for performance regressions, not
only the optimization changes, and keep **curated dashboards** current as part of the work. When:
continuously. Counter: the headline metrics per deploy. Fails when: only optimization changes are
watched.

**Watch the deploy, read the field.** After shipping, read field data to confirm the lab result.
**Segment field reads** by build, platform, and environment, and compare **dated field windows**
(two fixed date ranges), not one aggregate. When: after every shipped win. Counter: the field
percentile per segment. Fails when: an aggregate hides a regression on one platform.

**Ship telemetry to size prevalence.** Deploy the new event first, then read how often the defect
happens in the field. When: a defect's frequency is unknown. Counter: share of sessions affected.
Fails when: the fix ships in the same change as the event, so there is no baseline. Example: 31% of
page loads moved something after the page was usable ([post]; vendor-claimed (blog, 2026-09-23)).

**High-precision field reporting.** In the field, report the guarded quantity finely (sub-pixel)
and open a workstream on any nonzero value. When: a guardrail protects a brittle optimization.
Counter: the quantity at full precision. Fails when: rounding hides the first small regression.

**Ratchet or revert.** If the field improved, ratchet the benchmark. If not, turn the flag off and
iterate. When: after the field read. Counter: the benchmark's. Fails when: a win that did not show
in the field is ratcheted anyway. Used by: `/performance:verify` Next.

## I. Steer and orchestrate

Running many parallel workstreams (narrow scope, one owner each, merging colliding ones, closing on
diminishing returns) is covered in the playbooks
[orchestration chapter](../../playbooks/skills/fable-5/context/orchestration.md). Used by: the
human steering a push; no performance skill step points here. What stays here:

**Standing role brief.** A standing brief lists the surfaces owned, the responsibilities as verbs,
and an **explicit autonomy statement**: the goal autonomy and the autonomy allowed today. Template:

```text
Your job is <surfaces>. You <verb>, <verb>, and <verb>. You propose <what> and communicate with
<who>. The goal is <autonomy target>; today you may <current limit>.
```

When: starting any multi-session push. Fails when: the autonomy limit is left implicit.

**Time-boxed push.** Bound the effort in time so ambition and scope are set against a deadline.
When: a push with many candidates. Fails when: the box is extended instead of the scope cut.

**Reserve room for agent-proposed work.** Leave capacity for workstreams the agent proposes, with no
fixed share. When: planning a push. Fails when: the plan is fully allocated before measurement
starts.

**Options menu, human picks.** The agent lays out the measurement options and asks which to start
with. When: several counters are possible. Fails when: the agent starts all of them unasked.

**Named human owner per thread.** Every workstream has one named human who rules on it. When: more
than one workstream runs. Fails when: rulings stall with no owner.

**Boldness follows guardrails.** Push the agent to be bolder only when guardrails are strong. When
the agent defers because of merge or deploy lag, **remove the latency excuse**: the human commits
to a fast merge and deploy. And **targets are not the stopping point**: when targets are hit and
workstreams slow, nudge them on. When: guardrails from [G](#g-protect-the-win) are in place. Fails
when: boldness is pushed without them. The prompts, as quoted in the post:

> if you put it up right now I will get it merged and deployed. we have the power to do anything.
> please be braver

> Let's keep driving this down, the targets are not the stopping point. What's next? Be ambitious.

**Sidequests can pay off.** Let a side investigation run when it shows signal; it may become a main
win. When: a side finding has a measurement. Fails when: sidequests run with no number.

**Fix upstream.** When the cause is in a dependency, contribute the fix upstream as well as working
around it locally. When: a profile ends in a dependency. Fails when: the local workaround outlives
the upstream fix.

**Performance review as a service.** Other teams bring changes in for performance review. When: the
practice has a standing owner. Fails when: review happens only after regressions.

**Standing practice.** Keep the loop running as ongoing practice, not a one-off push. When: after
the push ends. Fails when: the rigs and ratchets stop being read.

## J. Write the result up

Used by: `/performance:verify` §4.

**Side-by-side recording as proof.** A before/after recording shows a perceptual fix, and **surface
perceptible changes for a ruling**: any user-perceptible change goes to its owner with before/after
evidence. When: the change is visible. Counter: counts taken from the recording (see
[C](#c-lab-measurement-and-rigs)). Fails when: a perceptible change is reported only as a number.
Used by: `/performance:verify` §4 `Behavior:` line.

**Blocking, CPU, and smoothness together.** Report total main-thread blocking, CPU share, and
sustained frame rate together. When: a rendering or streaming change. Counter: frames over budget.
Fails when: one of the three improves at the others' expense unreported.

**Report slow hardware and worst case.** Report results on slower hardware and the worst stall next
to the typical number. When: every rendering or startup result. Fails when: only the fast
machine's median is reported. Used by: `/performance:verify` `Not covered:`.

**Per-row results, not only the aggregate.** Report each platform and product row alongside the
aggregate, and combine speedup ratios with a **geometric mean**, not an arithmetic mean (see
[glossary](glossary.md)). When: a report covers several measurements. Fails when:
one large row dominates an arithmetic mean. Example: thirteen rows, "3.1x faster on average
(geometric mean)" ([post]; vendor-claimed (blog, 2026-09-23)).

**Human-cost framing.** Multiply the per-operation saving by frequency to state aggregate user time
saved, and label it an estimate. When: communicating impact. Fails when: the estimate is presented
as a measurement.

**State remaining gaps.** Name the percentiles, journeys, and extreme inputs not yet improved. Used
by: `/performance:verify` §4 `Not covered:`.

[post]: https://claude.dev/blog/how-we-made-claude-ai-faster
[hi3]: harness-integrity.md#3-a-discrimination-check-must-verify-its-own-patch-applied

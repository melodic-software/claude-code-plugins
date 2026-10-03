# Performance techniques

This plugin's own practice for finding, proving, shipping, and protecting a performance win, in the
order the loop uses it. Each entry is a rule the plugin applies: when it applies, the counter it
yields, how it fails, and the skill step that uses it. Each entry then carries one context-glue
record naming when to read its upstream source live; the catalog keeps none of that source's text,
figures, or quotes. The rules a harness must meet before any number is reported live in
[harness-integrity.md](harness-integrity.md); terms are defined in [glossary.md](glossary.md).

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

**Instrument before ranking.** When no candidate has a number that can be re-run on demand, the
first recommendation is to add one; a candidate without a number cannot be optimized. When: any
time the candidate list is ranked on suspicion. Counter: whichever count the new instrument
produces. Fails when: the new number does not track what users feel (see
[D](#d-prove-the-proxy)). Used by: `/performance:target` Evidence tiers ("instrument this first").

- **Pointer**: when explaining why a new measurement outranks a guessed fix, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers measurement-led target selection as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Add an instrument when the list goes flat.** When the current measurements stop producing
candidates, add a new measurement rather than re-ranking the same list. When: the ranked list has
gone flat or every candidate is E3 or E4. Counter: the new instrument's. Fails when: instruments
pile up with no owner and no correlation check. Used by: `/performance:target` Evidence tiers.

- **Pointer**: when you want worked cases of a new instrument surfacing candidates, fetch the post's [Scaling horizontally section][scale] live; no docs page covers instrument-driven candidate discovery as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**A complaint names a candidate, not a rank.** A report that the product feels slow puts an
operation on the candidate list; it never decides the order. When: a user or teammate names a slow
operation. Counter: none until instrumented. Fails when: the anecdote is ranked above a
measurement. Used by: `/performance:target` Inputs.

- **Pointer**: when you want the case of user reports opening a performance push, fetch the post's [opening section][post] live; no docs page covers complaint-led candidate intake as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Journey-based scoping.** Pick the few user journeys that usage data shows carry most of the use,
and optimize those. Crossing journeys with platforms and products gives the **measurement matrix**,
the full list of measurements to baseline. Tie every candidate project to the journey it moves
(**project list tied to journeys**). When: the product surface is wide and effort must be pointed.
Counter: one per matrix cell. Fails when: journeys are chosen by intuition rather than from usage
data. Used by: `/performance:target` Inputs and Output.

- **Pointer**: when choosing journeys from usage data, fetch the post's [The brief section][brief] live; no docs page covers journey selection for a performance push as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Audit telemetry before trusting it.** Before ranking from a telemetry store, check that its
events fire where expected and that its numbers agree with a direct measurement. When: a telemetry
store is the input. Counter: none; the output is a list of gaps. Fails when: a missing event reads
as zero cost. Used by: `/performance:target` Inputs (telemetry row).

- **Pointer**: when setting up a standing telemetry review, fetch the post's [The brief section][brief] live; no docs page covers telemetry audits before ranking as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Estimates in the target unit.** Estimate each candidate's gain in the metric's own unit
(milliseconds, spawns). An estimate may set the goal's Realistic target only for a candidate whose
cost was measured: the measured cost minus the estimated gain of the planned change, summed when
several changes aim at this metric, labeled estimate at the goal's human gate. When: sizing a set
of candidates, or proposing a Realistic target. Counter: none. Fails when: it sets a target with no
measured cost, or the target loses its estimate label. Used by: `/performance:target` Evidence
tiers (E3); `/performance:goal` §3.

- **Pointer**: when deciding whether a target is specific and measurable enough to set, fetch [Define your success criteria][success] live; correlate with the post's [The brief section][brief]. **As of**: 2026-10-02. **Recheck trigger**: that section moves or changes what it asks of a success criterion.

**Subscriber census on a hot interaction.** Count the observers, hooks, and subscriptions that run
on a per-input path (a keystroke, a tool call). When: an interaction feels slow and does little
visible work. Counter: subscribers fired per interaction. Fails when: the census counts
registrations instead of executions. Used by: `/performance:target` E1; for process spawns,
[`scripts/spawn-census.sh`](../scripts/spawn-census.sh) already runs it.

- **Pointer**: when you want a worked census on a UI input path, fetch the post's [Scaling horizontally section][scale] live; no docs page covers per-interaction subscriber censuses as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Raise the bar on hot paths.** A change to code that runs on every instance of a frequent
operation gets more tests, smaller diffs, and a flag. When: the target is startup, input handling,
or a per-event path. Counter: none. Fails when: a hot-path change ships with cold-path review. Used
by: `/performance:target` Output.

- **Pointer**: when deciding how much review a hot-path change needs, fetch the post's [Guardrails section][guard] live; no docs page covers hot-path review policy as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Re-scan for candidates.** When early targets are met or the list has gone stale, re-run
`/performance:target` over the whole surface, including paths nothing measures yet, and ask for
candidates outside the current list. When: early targets were hit, or the list has gone stale.
Counter: none. Fails when: the re-scan re-ranks the same list without adding a measurement. Used
by: `/performance:target` (re-scan).

- **Pointer**: when wording a re-scan request, fetch the post's [The brief section][brief] live; no docs page covers candidate re-scans as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

## B. Define the goal and its boundary

**Time-to-usable as the end event.** A user-facing duration starts at a user interaction and ends
when the user can act on the result (the input accepts typing), not when loading finishes. Client
and server work are separate numbers, so the client's share of a round trip is measured on its
own. Two durations compare only when their start and end events match (**comparable
boundaries**). When: writing the metric for any user-facing operation. Counter: none; this fixes
what the duration means. Fails when: two measurements with different start or end events are
compared. Used by: `/performance:goal` §1.

- **Pointer**: when choosing the start and end events for a journey, fetch the post's [The brief section][brief] live; no docs page covers journey measurement boundaries as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Name the start state.** Cold start, fresh load, and warm navigation are different measurements.
Say which one. When: every goal. Counter: none. Fails when: a warm number is reported against a
cold baseline. Used by: `/performance:goal` §1.

- **Pointer**: when you want start states reported side by side, fetch the post's [opening section][post] live; no docs page covers start-state labeling for app journeys as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Field percentile as the headline.** Report a named real-user percentile per journey. When: field
data exists. Counter: none. Fails when: a lab mean stands in for a field percentile. Used by:
`/performance:goal` Percentiles (the plugin keeps p50 and p95 as its house default).

- **Pointer**: when comparing this plugin's percentile default with a field headline, fetch the post's [opening section][post] live; no docs page covers per-journey field percentiles for app performance as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Define the defect precisely.** Count only what the definition covers. For layout movement,
exclude movement the user caused and movement before the page is usable. When: the target is a
defect rate, not a duration. Counter: occurrences under the definition. Fails when: the definition
is loose enough to count user-caused movement. Used by: `/performance:goal` §1.

- **Pointer**: when deciding which layout shifts count, fetch web.dev's [Expected versus unexpected layout shifts][cls-expected] live; correlate with the post's [The loop, thread by thread section][loop]. **As of**: 2026-10-02. **Recheck trigger**: that section moves or changes which shifts it excludes.

**Measure the underlying signal.** Go below a composite score to the raw events it is built from.
When: a composite score is green while the symptom is visible. Counter: raw event count or
magnitude. Fails when: the raw events are summed back into the same composite. Used by:
`/performance:goal` §1 and Gotchas.

- **Pointer**: when a layout score is green but movement is visible, fetch web.dev's [Layout shifts in detail][cls-detail] live; correlate with the post's [The loop, thread by thread section][loop]. **As of**: 2026-10-02. **Recheck trigger**: that section moves or changes how a shift is scored.

**Instrumentation parity.** Every surface compared in one ranking carries the same start and end
marks. When: one surface lacks the marks the others have. Counter: none. Fails when: surfaces are
ranked against each other with different marks. Used by: `/performance:goal` §1.

- **Pointer**: when one surface lacks the marks others have, fetch the post's [Steering section][steer] live; no docs page covers cross-surface timing marks as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Baseline window.** New instrumentation yields a number only after data accumulates. Plan for the
window, and use a lab measurement meanwhile. When: the metric depends on field data that does not
exist yet. Counter: none. Fails when: a goal is set before the baseline exists. Used by:
`/performance:goal` §2.

- **Pointer**: when planning around a new event's first data, fetch the post's [Steering section][steer] live; no docs page covers baseline windows for new instrumentation as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Price effects in frame budget.** State a visual effect's cost as a share of the frame budget
(1000 ms divided by the display's refresh rate). When: an animation or effect competes with
rendering. Counter: milliseconds per frame, or frames over budget. Fails when: the effect is judged
on appearance alone. Used by: `/performance:goal` §1; the human rules on the tradeoff (see
[F](#perceived-performance)).

- **Pointer**: when an effect's frame cost needs a human ruling, fetch the post's [Steering section][steer] live; no docs page covers effect-versus-budget rulings as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Parallel units on one event

When several units run in parallel for one user-visible event (hooks on one Claude Code hook event,
parallel CI jobs surfaced as one wait, concurrent requests behind one barrier), the user waits for
the **slowest** unit, not the sum. Record:

- **Event metric:** wall-clock time for the whole event, not the sum of per-unit CPU.
- **Unit metric:** the unit under study plus its **marginal cost**: the excess over the next-slowest
  peer on that event. A Stop hook at 300 ms matters only when it is 300 ms above the next-slowest
  Stop hook, not when read in isolation.
- **Event-level target:** the realistic and ideal targets for the user-visible wait, held beside the
  unit-level targets.
- **Summed CPU or syscall totals:** optional secondary figures; never a substitute for the event
  wall-clock target.

On MSYS/Cygwin, when the counter is a process count, state which accounting the goal uses (Job
Object +2 per external command vs PATH-shim `spawns=`); see
[harness-integrity.md](harness-integrity.md#process-counting-on-msyscygwin-git-bash).

Claude Code hooks are one example of parallel units, not the definition. This plugin treats the
hooks matching one event as parallel units and reads the event's wall time from the event-level
duration Claude Code reports, never from a sum of per-hook times.

- **Pointer**: when checking whether matching hooks run in parallel, fetch the hooks reference [Hook handler fields][hooks] live; when you need the event-level duration attribute, fetch the monitoring page's [Hook execution complete event][hook-complete] live. **As of**: 2026-10-02. **Recheck trigger**: either section changes how matching hooks run or renames the event-level duration attribute.

### Scaling arm when state grows with use

When the subject **reads state whose size grows with real use** (session transcripts, append-only
logs, unbounded histories, caches that accumulate entries, databases, queues), a single-size
measurement can pass while realistic use fails.

- Measure at **two or more sizes** spanning realistic use (for example 50 KB and 10 MB of the same
  transcript shape, not two sizes that exercise different code paths). Record each arm's size and
  result.
- **Done when** carries a stated bound: cost stays flat as size grows, or grows only within a named
  bound (for example "p50 does not grow faster than linear in the new bytes per Stop", or cost per
  new unit of content).
- When the bound is unknown, the scaling arms establish it and the goal is not locked until the
  human states one. Stop and say what is blocked; do not pick the bound for them.
- `/performance:target` should flag such candidates when ranking; if it did not, name the
  growing-state read in the goal anyway.

## C. Lab measurement and rigs

**A lab number for every iteration.** Build a lab measurement the agent can re-run alone, so an
iteration never waits for field data. **Unattended runs need a lab signal** most, since no one is
there to read the field for them. When: the field read takes longer than one iteration. Counter:
the lab benchmark's. Fails when: the lab number is never checked against the field (see
[H](#h-ship-roll-out-read-the-field)). Used by: `/performance:snapshot`.

- **Pointer**: when planning an unattended run's measurement, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers lab signals for unattended optimization as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Reproduce with a benchmark.** Before any fix, have a benchmark that fails, or reads high, on the
unfixed code. When: always, before a fix. Counter: the benchmark's. Fails when: the benchmark
passes on the unfixed base. Used by: `/performance:target` and `/performance:snapshot` baseline.

- **Pointer**: when you want the reproduce step in a full optimization loop, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers a per-goal optimization loop as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Instruction-count recipe.** For a CPU-bound hot path in one process, count instructions executed
under a CPU simulator and compare with a checked-in baseline. Durations need sample counts and
percentiles; a counter needs neither, only two agreeing runs on the unchanged subject before it is
trusted (harness-integrity rule 1). `ratchet.py add` and `propose-tighten` measure twice by
default, and `--runs` tunes it. When: the hot path is CPU-bound code in one process. Counter:
instructions executed (`Ir` under Cachegrind). Fails when: the deterministic mode is assumed rather
than checked. Used by: `/performance:snapshot` step 2. Tool specifics are in the verification
records below.

- **Pointer**: when choosing Cachegrind's options, fetch the Cachegrind manual's [command-line options][cg-opts] live; correlate with the post's [Anything can be hill climbed section][climb]. **As of**: 2026-10-02. **Recheck trigger**: a Valgrind release changes the Cachegrind options section.

**Deterministic counters by layer.** When instruction counts are unavailable (a browser, a
multi-process path), use the counter in this table that matches the subject's layer:

| Counter | Where it applies |
|---|---|
| Process spawns, syscalls, queries, round trips | Shell, service, and data paths (this plugin's default) |
| Instructions executed | Single-process, CPU-bound code under a simulator |
| Framework commits (renders) per interaction | UI frameworks with a commit phase |
| Function call counts | Runtimes with precise coverage |
| Layout and style recalculation counts | Browser rendering |
| DOM mutations | Browser pages |

This plugin ships no script for counters other than spawns. A counter of any kind is added with
`ratchet.py add` as a `.performance/ratchets.json` entry whose command prints `<field>=<number>`,
its goal text carrying the goal's Correlation clause. Reopen the question of a bundled counter when
a measured single-process CPU-bound Python or Node path appears; until then, run the
instruction-count recipe by hand.

When: instruction counts are unavailable for the subject. Counter: the row that matches the
subject's layer. Used by: `/performance:target` "Name the counter"; `/performance:snapshot` step 2;
`/performance:protect` §1. Fails when: a counter is climbed before it is shown to track the clock
([D](#d-prove-the-proxy)).

- **Pointer**: when choosing a browser counter, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers deterministic browser counters as a set as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Attribute by region and phase.** Label each event with the UI area it affected and the load stage
it occurred in, so one aggregate splits into separate causes. When: one aggregate hides several
independent causes. Counter: events per region per phase. Fails when: region names drift from the
UI they label. Used by: `/performance:snapshot` step 2; `/performance:target` for naming the
symptom.

- **Pointer**: when mapping a layout shift to the elements that moved, fetch MDN's [LayoutShift: sources property][ls-sources] live; correlate with the post's [The loop, thread by thread section][loop]. **As of**: 2026-10-02. **Recheck trigger**: that page changes what the property reports.

**Force the bad ordering in a test.** For an intermittent race, write a test that delays one
dependency past the event it races (for example, data arriving after first paint), so the bad
ordering happens on every run. Then **a binary test is the benchmark**: for a defect that either
happens or does not, the benchmark fails on any occurrence. The proof is red N/N on the base and
green N/N on the change, with N chosen per check and recorded ([harness-integrity rule 3][hi3]).
When: the defect is intermittent. Counter: failing runs out of N. Fails when: the forced delay does
not match the real ordering. Used by: `/performance:snapshot` and `/performance:verify` §4.

- **Pointer**: when you want a worked forced-ordering test, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers forced-ordering performance tests as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Count the defect in the recording.** When a screen recording is the only evidence, count from it:
elements that move, appear, or disappear between frames. When: the only evidence is a screen
recording. Counter: moved, appeared, and vanished elements. Fails when: frames are sampled too
sparsely to see a move. Used by: `/performance:target` Inputs.

- **Pointer**: when counting a defect from a recording, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers counting defects from recordings as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Representative content in the corpus.** Benchmarks and differentials include realistic content:
non-ASCII punctuation, long inputs, large documents. When: building any benchmark corpus. Counter:
none. Fails when: an ASCII-only corpus misses a slow path real content triggers (see
[F](#make-the-hot-path-cheap)). Used by: `/performance:snapshot`; `/performance:verify` §2.

- **Pointer**: when you want a case of content triggering a slow path, fetch the post's [Scaling horizontally section][scale] live; no docs page covers content-dependent benchmark corpora as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Report first pass and later passes separately.** Cold first execution and warm repeats are
separate numbers. When: the path compiles, caches, or allocates on first use. Counter: per-pass
duration or count. Fails when: an average hides a slow first pass. Used by: `/performance:snapshot`
Warmup.

- **Pointer**: when you want first and later passes reported apart, fetch the post's [Scaling horizontally section][scale] live; no docs page covers per-pass reporting as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Name the lab's blind spot.** State what the harness cannot see, for example browser chrome a
headless run lacks, or hardware a container lacks. **Environment-specific conditions** (managed or
policy-configured environments) belong on the same list. When: every lab report. Counter: none.
Fails when: a lab pass is reported as covering the field. Used by: `/performance:verify` §2 (the
unexercised mode).

- **Pointer**: when you want a defect the lab could not see, fetch the post's [Guardrails section][guard] live; no docs page covers lab blind-spot reporting as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Put the metric in the demo.** Show a live readout of the metric in the demonstration, such as a
frame-rate counter drawn in the page. When: showing a perceptual fix. Counter: the readout's. Fails
when: the readout itself costs frames. Used by: `/performance:snapshot`.

- **Pointer**: when building an in-page readout, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers in-demo metric readouts as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Rig checks.** Before trusting a rig against a new target, run these in order:

| Check | What it asks | Fails when |
|---|---|---|
| **Question the rig's ceiling** | Does the rig cap the metric and hide headroom? A rig that ticks at a fixed rate cannot show smoothness above that rate. | A capped reading is reported as the product's limit |
| **Confirm rig capability first** | Can the harness measure the new target at all? Confirm it before re-running. | The re-run proceeds on an unconfirmed rig |
| **Deterministic stepping** | Advance time in controlled ticks so each unit (a frame) reads the same on every run. | Stepping changes the workload's scheduling |
| **Rig self-check** | N ticks in produce exactly N units out. | The check is skipped and dropped units read as speed |
| **Budget fit per unit** | Report how many units fit the budget, not an average. A count over budget is a counter. | The mean hides the slow units |

When: before trusting a rig against a new target. Counter: units the self-check dropped, and units
over budget. Fails when: a check is skipped; each row names its own failure. Used by:
`/performance:snapshot` steps 1-2; `/performance:goal` §2 is the floor-first analog.

- **Pointer**: when building a stepped browser rig, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers rig checks for stepped rendering as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Verification records

**Cachegrind as the instruction counter.** This plugin counts instructions with Cachegrind's `Ir`
event and leaves cache simulation off. When: the instruction-count recipe runs. Counter: `Ir`. Fails
when: another event's total is read as the instruction count. Used by: the instruction-count recipe
above, run by hand.

- **Pointer**: when checking which events Cachegrind collects by default, fetch the Cachegrind manual's [command-line options][cg-opts] live. **As of**: 2026-09-23. **Recheck trigger**: a Valgrind release changes the Cachegrind options section.

**`node --predictable` is not relied on.** This plugin does not assume the flag makes counts repeat
run to run; it runs the count twice (harness-integrity rule 1). When: counting a Node subject.
Counter: whichever count the recipe takes. Fails when: one run's count is trusted because the flag
is set. Used by: the instruction-count recipe above, run by hand.

- **Pointer**: when checking what the flag does on the installed Node, fetch the output of `node --v8-options` live (probed on Node v24.20.0). **As of**: 2026-09-23. **Recheck trigger**: a Node major release.

**Call counts and timings in separate runs.** Take call counts with precise coverage on, and time
the path in a separate run with it off. When: call counts come from precise coverage. Counter:
function call counts. Fails when: a timing is taken with coverage on. Used by:
`/performance:snapshot` step 4 (two rigs).

- **Pointer**: when you need what enabling precise coverage changes, fetch `Profiler.startPreciseCoverage` in [`js_protocol.json`][cdp-js] live. **As of**: 2026-09-23. **Recheck trigger**: the protocol file changes the command.

**Stepped frames through DevTools.** A browser rig that steps frames uses
`HeadlessExperimental.beginFrame` and records that the domain is experimental. When: a browser rig
must step frames. Counter: frames over budget. Fails when: the domain changes and the rig is not
rechecked. Used by: `/performance:snapshot` step 2 (fixed-tick stepping).

- **Pointer**: when building the rig, fetch `HeadlessExperimental.beginFrame` in [`browser_protocol.json`][cdp-browser] live. **As of**: 2026-09-23. **Recheck trigger**: the domain leaves experimental or is removed.

## D. Prove the proxy

**Discard flaky benchmarks.** Drop a benchmark whose result varies run to run on an unchanged
subject, and drop one whose count does not move with user latency; neither becomes a target. When:
before a benchmark becomes a target or a gate. Counter: run-to-run spread on an unchanged subject.
Fails when: a noisy benchmark is kept "for now" and later gates. Used by: `/performance:goal` §1
`Correlation:`.

- **Pointer**: when deciding whether to keep a benchmark, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers benchmark retirement rules as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Require proof before a counter becomes a target.** Before a set of new counters becomes targets,
ask for evidence that lowering each one lowers wall-clock time, and retire the counters that cannot
show it. When: a set of new counters is about to become targets. Counter: none. Fails when: proof
is accepted from a single path. Used by: `/performance:goal` `Correlation:`.

- **Pointer**: when asking for that proof, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers counter-to-clock proof requests as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Proxy validation experiment.** Lower the counter on real hot paths and measure whether
wall-clock time fell with it. **Validate on more than one path**: at least two independent hot
paths before generalizing (two is judgment). When: a counter is proposed as a proxy. Counter: the
proxy, plus a duration. Fails when: the paths share a cause, so two paths are one data point. Used
by: `/performance:goal` `Correlation:` evidence; `/performance:verify` §5 `Correlation:`.

- **Pointer**: when you want a worked proxy validation, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers counter-to-clock validation as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Same benchmark, two rigs.** Take the count on the simulator rig and the duration on the normal
runtime after warmup, both from one benchmark and its inputs. When: the counting rig distorts timing
(simulators and coverage modes are slow). Counter: both. Fails when: the two rigs run different
inputs. Used by: `/performance:snapshot`; the recipe the `Correlation:` evidence cites.

- **Pointer**: when setting up the two rigs, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers paired count and timing rigs as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Counts can understate the clock.** A count cut can give a larger time cut, or a smaller one.
Report both; never infer one from the other. When: every report that carries a counter. Counter:
both. Fails when: a count reduction is restated as a time reduction. Used by: `/performance:verify`
§5.

- **Pointer**: when you want a case where count and time fell by different amounts, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers count-versus-time divergence as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

## E. Diagnose

Hand-off: a specific failure with no reproduction goes to `/debugging:debug`.

**Profile the counter.** Use the counting tool's own profile to see where the counted units go.
When: a counter is high and the cause is unknown. Counter: units per function. Fails when: the
profile of the simulated run is read as a time profile. Used by: `/performance:target` "Measure the
layers".

- **Pointer**: when reading a Cachegrind profile, fetch the Cachegrind manual's [Running cg_annotate][cg-annotate] live; correlate with the post's [Anything can be hill climbed section][climb]. **As of**: 2026-10-02. **Recheck trigger**: a Valgrind release changes that section.

**Work causes by name.** Name each cause concretely (the element and what it does wrong), not by
category. Then **fix in ranked batches**: fix the largest named causes together, re-measure, and
rank again. When: a defect has many causes. Counter: occurrences per named cause. Fails when: a
batch is fixed without re-measuring, so the ranking goes stale. Used by: `/performance:target`
Output.

- **Pointer**: when you want a worked cause list, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers cause-by-name triage as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Hidden work no metric sees.** Follow code paths past the event the headline metric ends on. Work
outside every metric's window, such as a reload nobody sees, still costs users. When: the headline
metric is green and cost is still suspected. Counter: occurrences of the hidden operation. Fails
when: tracing stops at the event the metric ends on. Used by: `/performance:target` "Measure the
layers".

- **Pointer**: when you want cases of work outside every metric, fetch the post's [Scaling horizontally section][scale] live; no docs page covers tracing past the headline event as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Profile the idle state.** Profile idle sessions for background work. When: the product runs for
long periods between interactions. Counter: main-thread work per idle minute. Fails when: the
profile starts with an interaction. Used by: `/performance:target`.

- **Pointer**: when you want an idle-profile case, fetch the post's [Scaling horizontally section][scale] live; no docs page covers idle-session profiling for this purpose as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Hitch sweep.** Sweep for CPU stalls across the product instead of profiling one path. When: no
single path is suspected. Counter: stalls over a threshold. Fails when: the threshold is set above
the stalls users feel. Used by: `/performance:target`.

- **Pointer**: when you want a sweep that found an input-dependent stall, fetch the post's [Scaling horizontally section][scale] live; no docs page covers product-wide stall sweeps as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Step unit by unit.** Time each unit of the workload (frame, chunk, request) on its own to find the
slow ones. When: a long operation is slow somewhere in the middle. Counter: units over budget.
Fails when: units are averaged. Used by: `/performance:target`.

- **Pointer**: when you want a per-frame stepping case, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers per-unit stepping as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Diagnosis ladder for a field report.** A report with a recording is a first-class input. Work it
in this order:

1. **Rule out your own change first.** Check your own instrument for the reporter's sessions before
   theorizing.
2. **Look up the reporter's own sessions.** Cross-reference the symptom with that user's field
   events.
3. **Arithmetic consistency check.** Predict the magnitude the proposed cause should produce and
   compare it with the observed value.
4. **Explain every qualifier.** Each qualifier in the report (where, how often, on which surface)
   must follow from the diagnosis.
5. **Intermittency as a race.** A defect seen only some of the time often comes from two events
   whose order varies between runs.
6. **Speedups expose latent defects.** Making something faster changes timing, which can expose a
   defect that was always there. Check whether the defect predates the change.

When: a field report arrives, recording or not. Counter: the reporter's own event values. Fails
when: a theory is accepted that leaves a qualifier
unexplained or misses the arithmetic. Used by: `/performance:target` Inputs; `/debugging:debug`.

- **Pointer**: when you want a field report worked through this ladder, fetch the post's [Guardrails section][guard] live; no docs page covers diagnosing a field report from a recording as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Speculative loading as a cause class.** A page the browser prepares before the user navigates can
be laid out for a viewport different from the one it is shown in, then resized after first paint.
When: a layout defect appears only on some navigations. Counter: shifts on prerendered loads. Fails
when: the lab never prerenders, so the class is invisible. Used by: `/performance:target` cause
checklist.

- **Pointer**: when a layout defect appears only on some navigations, fetch MDN's [How is speculative loading achieved?][spec-loading] live; correlate with the post's [Guardrails section][guard]. **As of**: 2026-10-02. **Recheck trigger**: that section moves or changes how browsers start a prerender.

## F. Optimization patterns (latency catalog)

Used by: `/performance:target` (candidate mechanisms) and `/implementation:implement`. Each pattern
still needs a measured baseline; the catalog names mechanisms, not wins.

### Perceived performance

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Static interactive shell** | Serve a static, usable version of the main input in the first HTML response, so input works while the framework starts | Time to usable is dominated by framework startup | Time to first accepted input | The shell and the real UI disagree (see [G](#g-protect-the-win)) |
| **Placeholder handoff** | The real UI renders over the static copy, and the switch must move nothing | Any static shell | Pixels moved at handoff | Any pixel differs between the two renders |
| **Preserve input across the handoff** | Text typed before the switch is kept, in the order typed | Any shell that accepts input | Lost or reordered keys | Input is dropped at the switch |
| **Progressive reveal** | Show a large structure in parts (a row or cell at a time) so no single update blocks | A large block blocks the first paint of its region | Main-thread blocking per update | Incremental fill causes layout movement |
| **Delay the skeleton** | Show a loading indicator only after a delay, so fast loads never show it | Most loads are fast | Skeleton flashes per load | The delay is longer than users tolerate; the delay is a per-surface human ruling |
| **Perceived-performance tradeoffs** | Whether to fill a structure in parts or all at once, and whether a visual effect is worth its share of the frame budget, are the human's rulings | A change alters what users see while loading | None; a before/after ruling | The agent decides a taste call alone |

- **Pointer**: when you want the case behind a row, fetch the post's [Guardrails section][guard] (static shell and handoff), [Steering section][steer] (fill, delay, and effect rulings), or [An 8-millisecond budget section][budget] (progressive reveal) live; no docs page covers these cases as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Avoid repeated work

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Keep expensive components mounted** | Keep a costly component mounted across navigations instead of remounting it | The same component remounts on every navigation | Mounts per navigation | Stale state leaks between views |
| **Cut re-renders** | Render only the parts whose inputs changed; an incremental renderer updates the changed region and leaves finished output alone | Updates re-render unchanged regions | Renders or commits per interaction | Memo keys are wrong and updates are lost |
| **Memoize finished work** | Cache the processed form of content that will not change, so each update costs only the new part | Streaming or growing content | Work per chunk against content length | Finished parts are later mutated |
| **Deduplicate repeated lookups** | Look a key up once per operation and reuse the result | A profile shows the same lookup repeated | Lookups per operation | The cached result goes stale |
| **Duplicate persistence on the main thread** | Skip a write whose content matches the previous one, then move the remaining writes off the main thread | Background persistence runs on the main thread | Writes per minute | Deduplication drops a real change |
| **Precompiled code cache** | Ship compiled startup code so each launch skips compiling it | Startup parses and compiles the same code every time | Compile time at launch | The cache is stale after an update and silently falls back |

- **Pointer**: when you want the case behind a row, fetch the post's [The brief section][brief] (mounted components, code cache), [Anything can be hill climbed section][climb] (repeated lookups), [Scaling horizontally section][scale] (duplicate persistence), or [An 8-millisecond budget section][budget] (re-renders, finished work) live; no docs page covers these cases as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Anticipate

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Intent-driven prefetch** | Prefetch on an intent signal such as hover, before the click | Navigation targets are predictable | Time from click to render | Prefetches waste bandwidth or load on the server |

- **Pointer**: when you want the prefetch case, fetch the post's [The brief section][brief] live; no docs page covers this case as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Make the hot path cheap

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Cheap prefilter before an expensive match** | Reject inputs that cannot match with a constant-time test before running an expensive regex or parse | Most inputs cannot match | Instructions per input | The prefilter rejects a valid match |
| **Input-dependent slow path** | Some content switches the runtime to a slower representation | Performance varies with content, not size | Time per input class | The corpus lacks the triggering content |
| **Normalize before the hot loop** | Convert input to the fast representation once, before the expensive step | An input-dependent slow path is found | Time per input class | Conversion costs more than it saves |
| **Polymorphic lookup cost** | Dynamic property or dictionary lookups whose shapes vary are a hot-path cost signal (engine-specific) | A profile shows lookup overhead | Instructions per lookup | Engine-specific tuning is applied across engines |
| **Per-keystroke work is a smell** | Work that re-runs on every input event is a first-class candidate | Typing feels slow | Work per keystroke | Debouncing hides the cost instead of removing it |
| **Global selector cost** | A costly style rule that matches broadly slows every DOM change; style recalculation counts find it | DOM changes are slow everywhere | Style recalculations and their time | The rule is removed without checking what it styled |

- **Pointer**: when you want the case behind a row, fetch the post's [Anything can be hill climbed section][climb] (prefilter, lookups) or [Scaling horizontally section][scale] (input-dependent slow path, keystroke work, global selector) live; no docs page covers these cases as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

### Move work

| Pattern | Idea | When | Counter | Fails when |
|---|---|---|---|---|
| **Move growing work off the main thread** | Put incremental parsing of growing content in a worker | Parsing competes with rendering | Main-thread blocking time | Message passing costs more than the work |

- **Pointer**: when you want the worker case, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers this case as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

## G. Protect the win

Used by: `/performance:protect` and `/performance:verify` Next.

**One benchmark, two uses.** A proven benchmark is both the number the lab work lowers and the
ceiling CI enforces. When: a benchmark proves correlated. Counter: the benchmark's. Fails when: it
gates before it is proven ([D](#d-prove-the-proxy)). Used by: `/performance:protect` §1.

- **Pointer**: when deciding whether a benchmark should also gate, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers benchmarks as CI gates for this purpose as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Ratchet mechanics.** CI fails when the count rises above the checked-in ceiling. When the count
falls, the ceiling is lowered in the same PR that lowered it; a scheduled job that proposes a lower
ceiling as a draft PR is only for a counter that can fall without a PR, and a human merges it.
**Ratchets hold the result** after the push ends. Only counts gate; durations are reported beside
them and never gate. When: a counter-backed goal is MET, unless the change shipped behind a flag
(see Ratchet or revert in [H](#h-ship-roll-out-read-the-field)). Counter: the ratcheted count.
Fails when: the ceiling is lowered automatically past a noisy dip, or a duration is ratcheted.
Used by: `/performance:protect` §3 and §4.

- **Pointer**: when you want a ratchet inside a full optimization loop, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers ratchets as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering ratchets.

**Protect a proven win.** Other changes erode a win unless a check holds it, so protection is added
when the win merges. When: the win is merged. Counter: the protected metric over time. Fails when:
protection is deferred until the win is already gone. Used by: `/performance:verify` Next, which
sends a counter MET to `/performance:protect`.

- **Pointer**: when deciding when to protect a win, fetch the post's [Guardrails section][guard] live; no docs page covers win protection as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Guardrails scale with brittleness.** The more ways an optimization can break without anyone
noticing, the more guardrails it gets. For a duplicated render (a static shell):

| Guardrail | What it checks |
|---|---|
| **Generate the copy from the source** | The static copy is built from the real component, and a test fails when the two differ |
| **Equivalence across configurations** | A test compares the static and real renders at a range of viewport sizes, within a stated pixel tolerance |
| **Input-through-handoff test** | A test enters text during the switch and fails when a character is lost or out of order |
| High-precision field reporting | See [H](#h-ship-roll-out-read-the-field) |

When: an optimization keeps a copy or a fast path that can drift from its source. Counter: none;
each guardrail is a test that passes or fails. Fails when: a brittle optimization ships with the
same checks as a safe one. Used by: `/performance:protect` §5.

- **Pointer**: when choosing guardrails for a duplicated render, fetch the post's [Guardrails section][guard] live; no docs page covers guardrails for a static shell as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Ship instruments with fixes.** A fix that introduces a new mechanism lands with the telemetry or
guardrail that watches it. When: every fix that introduces a new mechanism. Counter: none. Fails
when: instruments are promised for later. Used by: `/performance:protect` §5, which proposes
guardrails beside the ratchet; no skill step ships telemetry.

- **Pointer**: when you want instruments shipped beside fixes at scale, fetch the post's [Scaling horizontally section][scale] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Scheduled jobs find opportunities.** Run a proven rig on a schedule after its push ends: the
scheduled run catches regressions and surfaces new candidates. When: a rig proved useful. Counter:
the rig's. Fails when: nobody reads the job's output. Used by: no skill step; the project schedules
the rig (`/performance:protect` §4 schedules only ceiling tightening).

- **Pointer**: when turning a rig into a scheduled job, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers scheduled performance rigs as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Tests before optimizations.** Write the unit test before the optimization. **Fix at your layer,
test the trigger**: when the cause is outside your code, fix within the layer you control and add a
test that simulates the external trigger. When: every optimization. Counter: none. Fails when: the
test is written after the change and passes on both. Used by: `/implementation:implement` (TDD).

- **Pointer**: when you want an external-trigger test case, fetch the post's [Guardrails section][guard] live; no docs page covers this case as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Codify wins as skills and guardrails.** Turn what was learned into skills and checks so new code
starts fast by default. When: the same fix recurs. Counter: none. Fails when: the lesson stays in a
thread. Used by: no skill step; the human steering the push.

- **Pointer**: when you want the effect of codified wins on new code, fetch the post's [Scaling horizontally section][scale] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Safety mechanisms before pace.** Have review, tests, and flags in place before the work speeds
up. When: before a push. Counter: none. Fails when: guardrails are added after the first incident.
Used by: `/performance:goal` §4 "What counts as done".

- **Pointer**: when deciding which safety mechanisms a push needs first, fetch the post's [Guardrails section][guard] live; no docs page covers pre-push safety mechanisms as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

## H. Ship, roll out, read the field

Used by: `/performance:verify` Next and the project's own release process. This plugin measures; it
does not deploy.

**Small PRs per win.** Split a win into PRs each small enough to review and each carrying one risk;
one workstream produces **many small PRs**, not one large one. When: any win larger than one
reviewable change. Counter: none. Fails when: a risky piece hides in a large diff. Used by:
`/implementation:implement`.

- **Pointer**: when you want PR sizing inside the loop, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers PR sizing for performance work as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Flags for user-visible changes.** Gate any change a user could see behind a flag. Flags are
temporary: one place tracks every open flag's rollout and removal (**a thread for flag
lifecycle**), and each flag is removed once it is safe, with the removal rate tracked. Each flag is
one of two kinds, with its own removal condition:

| Kind | Purpose | Retire when |
|---|---|---|
| Kill switch | Turn the change off if it breaks | The change has run clean in the field |
| Ramp | Expose the change gradually | Exposure reaches everyone |

When: a change a user could see. Counter: open flags, and flags retired per week. Fails when: flags
accumulate with no owner. Used by: no skill step; the project's release process.

- **Pointer**: when setting up flag tracking, fetch the post's [Guardrails section][guard] live; no docs page covers flag lifecycle for performance work as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Staged rollout.** Expose a high-risk change in stages: internal users, then a fraction of users,
then all. **Dogfooding catches what metrics miss**: internal users report defects no metric sees.
In this marketplace the stages are main, dogfooded on the operator's hosts, then consumers, who get
the change through a version bump when they update, with auto-update off by default. When: every
high-risk change. Counter: defects reported per stage. Fails when: a stage is skipped under time
pressure. Used by: no skill step; the project's release process, in this marketplace the operator.

- **Pointer**: when a consumer reports a regression that the operator's hosts would have caught had the release waited, fetch [Run release channels][channels] live; correlate with the post's [Guardrails section][guard]. **As of**: 2026-10-02. **Recheck trigger**: that section moves or Claude Code adds a release-channel setting.

**Deploy regression watch as a standing duty.** Check each deploy's headline metrics for
regressions, whatever the deploy contained, and keep the dashboards that show them current. When:
continuously. Counter: the headline metrics per deploy. Fails when: only optimization changes are
watched. Used by: no skill step; the project's release process.

- **Pointer**: when writing a standing deploy-watch duty, fetch the post's [The brief section][brief] live; no docs page covers deploy regression duty for an agent as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Read the field after shipping.** Confirm the lab result in field data. **Segment field reads**:
one read per platform, build, and environment, compared across **dated field windows** (two fixed
date ranges), not one aggregate. When: after every shipped win. Counter: the field percentile per segment. Fails
when: an aggregate hides a regression on one platform. Used by: no skill step; the project's release
process.

- **Pointer**: when you want the field read inside the loop, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers a per-goal field read as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Field read for Claude Code hook behavior.** For Claude Code's own hook latency the field read is
`/harness-ops:observability latency`, taken before and after the release and compared. Its limits:
one open-ended window per call (`--days` or `--since`, with no end date), so the before read is
taken at release; grouping by lane and hook event only; fires compacted to the cold tier are
excluded. For any other subject, the field source is the telemetry the project's own instructions
name. When: a change to Claude Code hook behavior shipped behind a flag. Counter: none; the read
reports per-event p50 and p95 durations before and after. Fails when: the before read is taken
after the release, so both reads cover the change. Used by: no skill step; the operator shipping
the hook change.

- **Pointer**: when you need the attributes the latency read uses, fetch the monitoring page's [Hook execution complete event][hook-complete] live. **As of**: 2026-10-02. **Recheck trigger**: that section renames the event or its duration attribute.

**Ship telemetry to size prevalence.** Deploy the new event first, then read how often the defect
happens in the field. When: a defect's frequency is unknown. Counter: share of sessions affected.
Fails when: the fix ships in the same change as the event, so there is no baseline. Used by: no
skill step; the project's release process.

- **Pointer**: when sizing a defect's prevalence, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers prevalence telemetry for this purpose as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**High-precision field reporting.** Report the guarded quantity in the field at full precision
(below one pixel for movement), and open a workstream on any value above zero. When: a guardrail
protects a brittle optimization. Counter: the quantity at full precision. Fails when: rounding
hides the first small regression. Used by: no skill step; the project's release process.

- **Pointer**: when choosing field precision for a guardrail, fetch the post's [Guardrails section][guard] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Ratchet or revert.** If the field read shows the gain, ratchet the benchmark; if it does not, turn
the flag off and return to the change. When: a change shipped behind a flag, after the field read.
Counter: the benchmark's. Fails when: a win that did not show in the field is ratcheted anyway.
Used by: `/performance:verify` Next.

- **Pointer**: when deciding between ratchet and revert, fetch the post's [The loop, thread by thread section][loop] live; no docs page covers ratchets as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering ratchets.

## I. Steer and orchestrate

Running many workstreams at once is the subject of the playbooks
[orchestration chapter](../../playbooks/skills/fable-5/context/orchestration.md). Used by: the
human steering a push; no performance skill step points here. What stays here:

**Standing role brief.** A standing brief lists the surfaces owned, the duties as verbs, and an
**explicit autonomy statement**: the autonomy the work aims for and the autonomy allowed today.
Template:

```text
Surfaces you own: <surfaces>. Duties: <verb>, <verb>, <verb>. Propose <what>; report to <who>.
Autonomy target: <target>. Allowed today: <current limit>.
```

When: starting any multi-session push. Counter: none. Fails when: the autonomy limit is left
implicit. Used by:
the merge lane prompt in
[`prompts/loops/loop-lane-prompts.md`](../../../prompts/loops/loop-lane-prompts.md), whose limit
lives in [`plugins/autonomy/reference/guardrails.md`](../../autonomy/reference/guardrails.md).

- **Pointer**: when writing a standing brief, fetch the post's [The brief section][brief] live; no docs page covers standing performance briefs as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Time-boxed push.** Bound the effort in time so ambition and scope are set against a deadline.
When: a push with many candidates. Counter: none. Fails when: the box is extended instead of the
scope cut. Used by: no skill step; the human steering the push.

- **Pointer**: when sizing a time-boxed push, fetch the post's [The brief section][brief] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Leave unplanned capacity.** Plan a push with capacity left for workstreams the agent proposes
once measurement starts, with no fixed share. When: planning a push. Counter: none. Fails when: the
plan is fully allocated before measurement starts. Used by: no skill step; the human steering the
push.

- **Pointer**: when planning a push's capacity, fetch the post's [The brief section][brief] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Options menu, human picks.** The agent lays out the measurement options and asks which to start
with. When: several counters are possible. Counter: none. Fails when: the agent starts all of them
unasked. Used by: no skill step; the human steering the push.

- **Pointer**: when you want an options menu in practice, fetch the post's [Anything can be hill climbed section][climb] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**One human owner per workstream.** Each workstream has one named person who makes its rulings.
When: more than one workstream runs. Counter: none. Fails when: rulings stall with no owner. Used
by: no skill step; the human steering the push.

- **Pointer**: when assigning workstream owners, fetch the post's [Steering section][steer] live; no docs page covers human ownership of performance workstreams as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Widen scope only behind guardrails.** Ask the agent for larger changes only when the guardrails
in [G](#g-protect-the-win) are in place. When the agent holds back a change because merging or
deploying is slow, **remove the latency excuse**: the human commits to merging and deploying it
promptly. A met target does not close a workstream that still has measured candidates; the human,
not an automated nudge, asks it to continue, within the human's own `/goal` or `/loop` condition.
When: guardrails from [G](#g-protect-the-win) are in place. Counter: none. Fails when: wider scope
is pushed without them. Used by: no skill step; the human steering the push.

- **Pointer**: when deciding whether to push for wider changes, fetch the post's [Steering section][steer] live; no docs page covers steering an agent's ambition on performance work as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Sidequests can pay off.** Let a side investigation run when it shows signal; it may become a main
win. When: a side finding has a measurement. Counter: the side finding's own. Fails when: sidequests
run with no number. Used by: no skill step; the human steering the push.

- **Pointer**: when you want a sidequest that became a main win, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Fix upstream.** When the cause is in a dependency, contribute the fix upstream as well as working
around it locally. When: a profile ends in a dependency. Counter: none. Fails when: the local
workaround outlives the upstream fix. Used by: no skill step; the human steering the push.

- **Pointer**: when a profile ends in a dependency, fetch the post's [What's next section][next] live; no docs page covers upstream fixes from a performance push as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Performance review for other teams.** Once the practice has a standing owner, review other
teams' performance-sensitive changes before they merge. When: the practice has a standing owner.
Counter: none. Fails when: review happens only after regressions. Used by: no skill step; the
practice's standing owner.

- **Pointer**: when offering performance review to other teams, fetch the post's [Scaling horizontally section][scale] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Standing practice.** Keep reading the rigs and ratchets after a push ends; the practice continues
without a push. When: after the push ends. Counter: the rigs' and ratchets' own. Fails when: the
rigs and ratchets stop being read. Used by: no skill step; the practice's standing owner.

- **Pointer**: when deciding what continues after a push, fetch the post's [What's next section][next] live; no docs page covers this practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

## J. Write the result up

Used by: `/performance:verify` §5 Report.

**Side-by-side recording as proof.** A before/after recording shows a perceptible fix, and a change
users can see goes to its human owner with before/after media for a ruling. When: the change is
visible. Counter: counts taken from the recording (see [C](#c-lab-measurement-and-rigs)). Fails
when: a perceptible change is reported only as a number. Used by: the
`/source-control:pull-request` create step's Verification drafting, which lists before/after
captures for a change to rendered output for the person to attach.

- **Pointer**: when deciding which changes need a human ruling with media, fetch the post's [Steering section][steer] live; no docs page covers before/after media for performance rulings as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Blocking, CPU, and smoothness together.** Report total main-thread blocking, CPU share, and
sustained frame rate together. When: a rendering or streaming change. Counter: frames over budget.
Fails when: one of the three improves at the others' expense unreported. Used by: no skill step; the
author of the change's report.

- **Pointer**: when you want the three reported together, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers this reporting set as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Report slow hardware and worst case.** Report results on slower hardware and the worst stall next
to the typical number. When: every rendering or startup result. Counter: none; the worst stall is a
duration. Fails when: only the fast
machine's median is reported. Used by: `/performance:verify` `Not covered:`.

- **Pointer**: when you want slow-hardware and worst-case results reported, fetch the post's [An 8-millisecond budget section][budget] live; no docs page covers this reporting practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Per-row results, not only the aggregate.** Report each platform and product row alongside the
aggregate, and combine speedup ratios with a **geometric mean**, not an arithmetic mean (see
[glossary](glossary.md)). When: a report covers several measurements. Counter: none. Fails when:
one large row dominates an arithmetic mean. Used by: `/performance:verify` §5 (the geometric-mean
rule).

- **Pointer**: when you want a per-row table with a geometric-mean aggregate, fetch the post's [opening section][post] live; no docs page covers this reporting practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**Human-cost framing.** Multiply the per-operation saving by frequency to state aggregate user time
saved, and label it an estimate. When: communicating impact. Counter: none. Fails when: the
estimate is presented as a measurement. Used by: no skill step; the author of the impact statement.

- **Pointer**: when you want an aggregate user-time estimate in practice, fetch the post's [opening section][post] live; no docs page covers this framing as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

**State remaining gaps.** List what the result does not cover yet: other percentiles, other
journeys, extreme inputs. When: every report. Counter: none. Fails when: the list is omitted, or
reads `none` while something went unexercised. Used by: `/performance:verify` §5 `Not covered:`.

- **Pointer**: when you want remaining gaps stated in practice, fetch the post's [What's next section][next] live; no docs page covers this reporting practice as of 2026-10-02. **As of**: 2026-10-02. **Recheck trigger**: a docs page starts covering it.

[post]: https://claude.dev/blog/how-we-made-claude-ai-faster/
[brief]: https://claude.dev/blog/how-we-made-claude-ai-faster/#the-brief
[climb]: https://claude.dev/blog/how-we-made-claude-ai-faster/#anything-can-be-hill-climbed
[loop]: https://claude.dev/blog/how-we-made-claude-ai-faster/#the-loop-thread-by-thread
[scale]: https://claude.dev/blog/how-we-made-claude-ai-faster/#scaling-horizontally
[guard]: https://claude.dev/blog/how-we-made-claude-ai-faster/#guardrails
[steer]: https://claude.dev/blog/how-we-made-claude-ai-faster/#steering
[budget]: https://claude.dev/blog/how-we-made-claude-ai-faster/#an-8-millisecond-budget
[next]: https://claude.dev/blog/how-we-made-claude-ai-faster/#whats-next
[success]: https://platform.claude.com/docs/en/test-and-evaluate/define-success#define-your-success-criteria
[hooks]: https://code.claude.com/docs/en/hooks#hook-handler-fields
[hook-complete]: https://code.claude.com/docs/en/monitoring-usage#hook-execution-complete-event
[channels]: https://code.claude.com/docs/en/plugins/host-marketplace#run-release-channels
[cls-expected]: https://web.dev/articles/cls#expected-unexpected-layout-shifts
[cls-detail]: https://web.dev/articles/cls#layout-shifts-in-detail
[ls-sources]: https://developer.mozilla.org/en-US/docs/Web/API/LayoutShift/sources
[spec-loading]: https://developer.mozilla.org/en-US/docs/Web/Performance/Guides/Speculative_loading#how_is_speculative_loading_achieved
[cg-opts]: https://valgrind.org/docs/manual/cg-manual.html#cg-manual.cgopts
[cg-annotate]: https://valgrind.org/docs/manual/cg-manual.html#cg-manual.running-cg_annotate
[cdp-js]: https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/js_protocol.json
[cdp-browser]: https://github.com/ChromeDevTools/devtools-protocol/blob/master/json/browser_protocol.json
[hi3]: harness-integrity.md#3-a-discrimination-check-must-verify-its-own-patch-applied

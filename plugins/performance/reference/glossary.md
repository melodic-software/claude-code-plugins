# Performance glossary

Terms the performance skills and [techniques.md](techniques.md) use, defined for this plugin. A link
points at the entry or skill section that applies the term; where a term has an upstream source,
that catalog entry carries the context-glue record pointing at it.

- **Arithmetic consistency check.** Predict the magnitude a proposed cause should produce and
  compare it to the observed value; a mismatch rules the cause out. See
  [E](techniques.md#e-diagnose).
- **Baseline window.** The time new instrumentation needs to accumulate enough data to give a
  number. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Ceiling.** The checked-in maximum a ratchet enforces. See *ratchet*.
- **Census.** A count of everything that runs on one interaction: subscribers, hooks, observers,
  process spawns. See [A](techniques.md#a-choose-the-target).
- **Code cache.** Compiled startup code stored so a launch can skip compiling it. See
  [F](techniques.md#avoid-repeated-work).
- **Cold start, fresh load, warm navigation.** Three start states: nothing cached or running; a new
  page load with the process warm; a navigation inside an already-loaded app. Each is a separate
  measurement. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Correlation.** Evidence that moving a proxy moves the metric users feel. `unproven` is a legal
  value; a proxy with unproven correlation may be measured but not claimed. See
  [D](techniques.md#d-prove-the-proxy) and `/performance:goal` §1.
- **CPU hitch (long task).** A main-thread stall long enough for users to notice. See the hitch
  sweep in [E](techniques.md#e-diagnose).
- **Cumulative layout shift.** A composite score summing layout shifts over a page's life. It can
  stay green while individual shifts are visible. See *layout shift*.
- **Deterministic counter.** See *drift-immune counter*.
- **Deterministic stepping.** Advancing time in controlled ticks (for a browser, DevTools
  begin-frame control) so each unit reads the same on every run. See the rig checks in
  [C](techniques.md#c-lab-measurement-and-rigs).
- **Diminishing returns.** The point where further gains in a workstream shrink below their cost;
  the cue to close it. See [I](techniques.md#i-steer-and-orchestrate).
- **Dogfooding.** Releasing to internal users first, who surface defects no metric sees. See
  *staged rollout*.
- **Drift-immune counter.** A count (instructions, spawns, queries, renders) that does not vary
  with host load, so it reproduces where wall-clock time does not. Two runs on an unchanged subject
  must agree before it is trusted; `ratchet.py` measures twice by default, and `--runs` tunes it.
  See
  [`/performance:target`](../skills/target/SKILL.md) "Name the counter, not just the duration" and
  [C](techniques.md#c-lab-measurement-and-rigs).
- **Feature flag.** A runtime switch that gates a change. Here, removed once it is safe, and
  classified as a *kill switch* or a *ramp*. See [H](techniques.md#h-ship-roll-out-read-the-field).
- **Floor.** The irreducible cost of an operation, measured on its cheapest possible version before
  any work. See [`/performance:goal`](../skills/goal/SKILL.md) §2.
- **Frame budget.** The time one frame may take at a refresh rate: 1000 ms divided by the rate in
  hertz. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Geometric mean.** The nth root of the product of n values. Use it to combine speedup ratios: a
  2x speedup and a 2x slowdown average to 1x, no single large ratio dominates, and the result does
  not depend on which side is the reference. See [J](techniques.md#j-write-the-result-up).
- **Guardrail.** A test, check, or field alert that fails when a proven win regresses. See
  [G](techniques.md#g-protect-the-win).
- **Hidden work.** Cost that falls outside every headline metric's window, such as a reload after
  the load metric has ended. See [E](techniques.md#e-diagnose).
- **Hill climbing.** Repeatedly changing the code and keeping each change that moves a re-runnable
  number the right way. It needs a number first. See [A](techniques.md#a-choose-the-target);
  `/performance:climb` runs it against one goal's frozen harness.
- **Hot path.** Code that runs on every instance of a frequent operation (startup, each keystroke,
  each tool call), where small costs multiply. See [A](techniques.md#a-choose-the-target).
- **Hydration.** A client framework attaching to server- or statically-rendered markup and taking
  over. The static shell is shown until it finishes. See *static shell*.
- **Journey.** One user task measured end to end, such as opening a project or submitting a form.
  See [A](techniques.md#a-choose-the-target).
- **Kill switch.** A flag whose purpose is to turn a change off if it breaks. See *feature flag*.
- **Lab.** Measurement on a controlled rig the agent can re-run, as opposed to *real-user
  monitoring*. See [C](techniques.md#c-lab-measurement-and-rigs).
- **Latent-defect exposure.** A speedup changes timing and reveals a defect that was always
  present. See the diagnosis ladder in [E](techniques.md#e-diagnose).
- **Layout shift.** Visible movement of page content. As a defect, exclude movement the user caused
  and movement before the page is usable. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Long task.** See *CPU hitch*.
- **Main-thread blocking time.** Total time the main thread is busy long enough to delay input or
  rendering. See [J](techniques.md#j-write-the-result-up).
- **Measurement boundary.** The start event, end event, and client or server side that define what
  a duration covers. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Measurement matrix.** Journeys crossed with platforms and products: the full list of
  measurements to baseline. See [A](techniques.md#a-choose-the-target).
- **Megamorphic lookup.** See *polymorphic lookup*.
- **Memoize finished work.** Caching the processed form of content that will not change, so each
  update costs only the new part. See [F](techniques.md#avoid-repeated-work).
- **Named region and phase.** Labels on an event: the UI area it affected and the load stage it
  occurred in. See [C](techniques.md#c-lab-measurement-and-rigs).
- **Percentile (p50, p95).** The value below which that share of samples falls. The plugin's
  house default is p50 and p95. See [`/performance:goal`](../skills/goal/SKILL.md) "Percentiles and
  sample count".
- **Placeholder handoff.** The moment the real UI replaces a static copy; it must move nothing and
  lose no input. See [F](techniques.md#perceived-performance).
- **Polymorphic lookup.** A property or dictionary lookup whose object shapes vary, which a JIT
  cannot specialize; megamorphic when the shapes are many. A hot-path cost signal. See
  [F](techniques.md#make-the-hot-path-cheap).
- **Prerender.** See *speculative loading*.
- **Progressive reveal.** Showing a large structure incrementally so no single update blocks. See
  [F](techniques.md#perceived-performance).
- **Proxy metric.** A cheaper, steadier number standing in for what users feel. Valid only with
  proven *correlation*. See [D](techniques.md#d-prove-the-proxy).
- **Ramp.** A flag whose purpose is gradual exposure. See *feature flag*.
- **Ratchet.** A checked-in ceiling CI enforces: a rise fails the build, a fall lets the ceiling be
  lowered. See [G](techniques.md#g-protect-the-win) and `/performance:protect`.
- **Real-user monitoring (field).** Measurement from real users' sessions, segmented by build,
  platform, and environment. See [H](techniques.md#h-ship-roll-out-read-the-field).
- **Realistic and ideal targets.** The expected result given the floor and baseline, and the cost
  with no incidental overhead, held separately. See [`/performance:goal`](../skills/goal/SKILL.md)
  §3.
- **Red N/N and green N/N.** A binary check that fails on every one of N runs on the base and
  passes on every one of N runs on the change, N chosen per check and recorded. See
  [harness-integrity.md](harness-integrity.md) rule 3.
- **Rig ceiling.** A cap the rig imposes on the metric, such as a fixed tick rate, which hides
  headroom. See [C](techniques.md#c-lab-measurement-and-rigs).
- **Sidequest.** A side investigation allowed to run while it shows signal. See
  [I](techniques.md#i-steer-and-orchestrate).
- **Speculative loading.** A browser fetching or rendering a page before the user navigates to it;
  the page can be laid out for a viewport other than the one it is shown in. See
  [E](techniques.md#e-diagnose).
- **Staged rollout.** Exposure in stages: internal users, a small share of users, everyone. See
  [H](techniques.md#h-ship-roll-out-read-the-field).
- **Static shell.** A static, usable version of the main UI served in the first HTML response and
  shown while the framework starts. See [F](techniques.md#perceived-performance).
- **Thread.** One narrow workstream with one owner. Mapping it to an agent session is this plugin's
  inference. See [I](techniques.md#i-steer-and-orchestrate).
- **Thread owner.** The one named person who makes a workstream's rulings. See
  [I](techniques.md#i-steer-and-orchestrate).
- **Time to usable.** Time until the user can act, such as the input accepting keystrokes. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Warm navigation.** See *cold start, fresh load, warm navigation*.
- **Win decay.** Erosion of a performance win as other changes land. See
  [G](techniques.md#g-protect-the-win).
- **Worker offload.** Moving CPU work off the main thread into a worker. See
  [F](techniques.md#move-work).

# Performance glossary

Terms the performance skills and [techniques.md](techniques.md) use. A link points at the entry or
skill section that applies the term.

Sources: [How we made claude.ai 3x faster in two weeks](https://claude.dev/blog/how-we-made-claude-ai-faster).

- **Arithmetic consistency check.** Predict the magnitude a proposed cause should produce and
  compare it to the observed value; a mismatch rules the cause out. See
  [E](techniques.md#e-diagnose).
- **Baseline window.** The time new instrumentation needs to accumulate enough data to give a
  number. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Ceiling.** The checked-in maximum a ratchet enforces. See *ratchet*.
- **Census.** A count of everything that runs on one interaction: subscribers, hooks, observers,
  process spawns. See [A](techniques.md#a-choose-the-target).
- **Code cache.** Precompiled startup code saved so a process does not recompile it at every
  launch. See [F](techniques.md#avoid-repeated-work).
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
- **Deterministic stepping.** Driving time in controlled ticks (for a browser, begin-frame control)
  so each unit is an exact read. See the rig checks in [C](techniques.md#c-lab-measurement-and-rigs).
- **Diminishing returns.** The point where further gains in a workstream shrink below their cost;
  the cue to close it. See [I](techniques.md#i-steer-and-orchestrate).
- **Dogfooding.** Releasing to internal users first, who surface defects no metric sees. See
  *staged rollout*.
- **Drift-immune counter.** A count (instructions, spawns, queries, renders) that does not vary
  with host load, so it reproduces where wall-clock time does not. Once two runs on an unchanged
  subject agree, one run suffices. See
  [`/performance:target`](../skills/target/SKILL.md) "Name the counter" and
  [C](techniques.md#c-lab-measurement-and-rigs).
- **Feature flag.** A runtime switch that gates a change. Here, short-lived by design, and either a
  kill switch or a ramp. See [H](techniques.md#h-ship-roll-out-read-the-field).
- **Floor.** The irreducible cost of an operation, measured on its cheapest possible version before
  any work. See [`/performance:goal`](../skills/goal/SKILL.md) §2.
- **Frame budget.** The time one frame may take at a refresh rate: about 16.7 ms at 60 Hz, 8.33 ms
  at 120 Hz. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Geometric mean.** The nth root of the product of n values. Use it to combine speedup ratios: a
  2x speedup and a 2x slowdown average to 1x, no single large ratio dominates, and the result does
  not depend on which side is the reference. See [J](techniques.md#j-write-the-result-up).
- **Guardrail.** A test, check, or field alert that fails when a proven win regresses. See
  [G](techniques.md#g-protect-the-win).
- **Hidden work.** Cost no headline metric covers, such as a silent reload after the load metric
  ends. See [E](techniques.md#e-diagnose).
- **Hill climbing.** Repeatedly changing the code and keeping each change that moves a re-runnable
  number the right way. It needs a number first. See [A](techniques.md#a-choose-the-target).
- **Hot path.** Code that runs on every instance of a frequent operation (startup, each keystroke,
  each tool call), where small costs multiply. See [A](techniques.md#a-choose-the-target).
- **Hydration.** A client framework attaching to server- or statically-rendered markup and taking
  over. The static shell is shown until it finishes. See *static shell*.
- **Journey.** One user task measured end to end, such as launching the app or sending a message.
  See [A](techniques.md#a-choose-the-target).
- **Kill switch.** A flag whose purpose is to turn a change off if it breaks. See *feature flag*.
- **Lab.** Measurement on a controlled rig the agent can re-run, as opposed to *real-user
  monitoring*. See [C](techniques.md#c-lab-measurement-and-rigs).
- **Latent-defect exposure.** A speedup changes timing and reveals a defect that was always
  present. See the diagnosis ladder in [E](techniques.md#e-diagnose).
- **Layout shift.** Visible movement of page content. As a defect, count only shifts after the page
  is usable and without user input. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Long task.** See *CPU hitch*.
- **Main-thread blocking time.** Total time the main thread is busy long enough to delay input or
  rendering. See [J](techniques.md#j-write-the-result-up).
- **Measurement boundary.** The start event, end event, and client or server side that define what
  a duration covers. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Measurement matrix.** Journeys crossed with platforms and products: the full list of
  measurements to baseline. See [A](techniques.md#a-choose-the-target).
- **Megamorphic lookup.** See *polymorphic lookup*.
- **Memoize finished blocks.** Caching the processed form of content that will not change, so each
  update costs only the part still changing. See [F](techniques.md#avoid-repeated-work).
- **Named region and phase.** Tags on an event: the UI region it hit and the load phase it happened
  in (before first paint, after usable). See [C](techniques.md#c-lab-measurement-and-rigs).
- **Percentile (p50, p75, p95).** The value below which that share of samples falls. The plugin's
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
- **Rig ceiling.** A cap the rig imposes on the metric, such as a fixed 60 Hz tick, which hides
  headroom. See [C](techniques.md#c-lab-measurement-and-rigs).
- **Sidequest.** A side investigation allowed to run while it shows signal. See
  [I](techniques.md#i-steer-and-orchestrate).
- **Speculative loading.** A browser loading or prerendering a page before the user commits to it;
  the page can be laid out in a state the user never sees. See [E](techniques.md#e-diagnose).
- **Staged rollout.** Exposure in stages: internal users, a small share of users, everyone. See
  [H](techniques.md#h-ship-roll-out-read-the-field).
- **Static shell.** An inert but usable copy of the primary UI in the initial HTML, shown before the
  framework initializes. See [F](techniques.md#perceived-performance).
- **Thread.** One narrow workstream with one owner. Mapping it to an agent session is inference,
  not a stated equivalence. See [I](techniques.md#i-steer-and-orchestrate).
- **Thread owner.** The one named human who rules on a workstream. See
  [I](techniques.md#i-steer-and-orchestrate).
- **Time to usable (time to typeable).** Time until the user can act, such as the input accepting
  keystrokes. See [B](techniques.md#b-define-the-goal-and-its-boundary).
- **Warm navigation.** See *cold start, fresh load, warm navigation*.
- **Win decay.** Erosion of a performance win as other changes land. See
  [G](techniques.md#g-protect-the-win).
- **Worker offload.** Moving CPU work off the main thread into a worker. See
  [F](techniques.md#move-work).

# Performance Criterion: baseline / compare

Verify a **performance-improvement claim** against data. This file owns the performance-family measurement discipline; the phase table, invocation forms, core no-baseline rule, and tooling notes are owned by SKILL.md ("Two-phase model" / "Purpose"). Run the phases manually when the consuming project has no harness.

## `baseline` phase (at planning time)

When a plan claims a perf improvement:

1. **Identify the claim precisely:** "faster" at what, by how much, under what conditions? "More efficient" → which resource? "Optimized" → which bottleneck?
2. **Choose metrics** matching the claim:

   | Claim type | Metrics | How to measure |
   |-----------|---------|---------------|
   | Faster execution | Wall time, CPU time | Your test runner's timing output, a shell timer (`time` on POSIX/Git Bash, `Measure-Command` in PowerShell) |
   | Faster build | Build time | Your build tool's timing output, CI run durations |
   | Less memory | Peak RSS, allocation count | Your platform's profiler or memory-counter tooling |
   | Fewer allocations | Allocation rate, GC pressure | Your benchmark harness, allocation profiler |
   | Better throughput | Requests/sec, items/sec | Load test, benchmark harness |
   | Reduced latency | P50, P95, P99 | Tracing dashboard, load tests |

3. **Noise floor: don't optimize below it.** Estimate aggregate savings against run-to-run variance. If projected savings sit within the noise floor, the change is unmeasurable. Skip it and surface the noise-floor argument BEFORE doing the work, not after.
4. **Capture the baseline:** measure the pre-change state under controlled conditions (same machine, data, config; minimum 3 runs, ideally 5+; discard the warm-up run). Store mean + std in the topic's memory-tier baselines directory (SKILL.md "Two-phase model", machine-bound, never committed) and record baseline + target in the plan.

## `compare` phase (at `/verification:measure performance`)

1. **Retrieve the baseline** from the topic's memory-tier baselines directory (or the plan itself). Confirm it was measured under comparable conditions. If no baseline exists, apply the no-baseline honesty rule (SKILL.md "Purpose"): report the current measurement and that the improvement cannot be quantified.
2. **Measure current state** under the SAME conditions as the baseline (same machine, data, config; multiple runs; report mean ± std, not a single number).
3. **Report:**

   ```text
   ## Performance: compare vs baseline

   ### Claim
   <what improvement is claimed>

   ### Methodology
   - Tool: <measurement tool> · Conditions: <machine, data, config> · Runs: <N>

   ### Results
   | Metric | Before (mean ± std) | After (mean ± std) | Delta | % change |
   |--------|--------------------|--------------------|-------|----------|
   | <metric> | <baseline> | <current> | <diff> | <%> |

   ### What limits the number
   Limiter:    <what stops the after arm doing better, and the run that shows it> | unknown
   Ruled out:  <another explanation for the delta: the evidence that excludes it> | unknown
   Handed off: no | /performance:verify, <why>

   ### Assessment
   <statistically meaningful? methodology sound?>
   ```

   Fill `Limiter:` and `Ruled out:` from this compare's own runs, or hand the compare to `/performance:verify` when the `performance` plugin is enabled, and say which on the `Handed off:` line. A handed-off report writes `see /performance:verify` on the other two lines and gives no verdict of its own: `/performance:verify`'s report carries the verdict, and the compare skips SKILL.md's verdict record ("Record the verdict for the head it judged"). The reason: a number with no known limit cannot be trusted, because nothing in a printed delta tells a sound run from one held by the harness, a warm cache or skipped work.
   - **`Limiter:`** names what bounds the after figure (a sleep or poll interval, a lock both arms wait on, a saturated core, disk or network throughput, the load driver). A measured run confirms it, such as a profiled extra run or OS counters recorded while it ran; reading the code only suggests one.
   - **`Ruled out:`** names at least one other thing the delta could reflect (arms on different build modes or settings, one arm left on defaults while the other was tuned, a cache the after arm found warm, failed or skipped work, run-to-run spread), each with the evidence that excludes it.
   - Hand off when filling either line needs a profiler, a fresh-context re-derivation or a cold-start run of each arm that this compare lacks.

4. **Verdict:**
   - **CONFIRMED**: measurements show clear improvement with sound methodology, and `Limiter:` and `Ruled out:` are both filled
   - **INCONCLUSIVE**: variance too high, conditions differ, sample too small, or `Limiter:` or `Ruled out:` reads `unknown` (an `unknown` line only blocks CONFIRMED; NOT CONFIRMED and DEGRADED stand without either line)
   - **NOT CONFIRMED**: no baseline, or measurements don't support the claim
   - **DEGRADED**: performance got worse (flag immediately)

## Common pitfalls

- **Single-run measurements** tell you nothing about variance. Always run multiple times.
- **Different conditions.** Comparing a debug-build baseline to a release-build current state is meaningless.
- **Micro-optimization without macro impact.** Saving 1ms in a function inside a 200ms request is noise, not signal.
- **Forgetting warm-up.** First-run JIT + cold cache inflate initial measurements. Discard the first run or include warm-up.

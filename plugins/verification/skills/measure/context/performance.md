# Performance Criterion — baseline / compare

Verify a **performance-improvement claim** against data. This file owns the performance-family measurement discipline; the phase table, invocation forms, core no-baseline rule, and tooling notes are owned by SKILL.md ("Two-phase model" / "Purpose") — run the phases manually when the consuming project has no harness.

## `baseline` phase (at planning time)

When a plan claims a perf improvement:

1. **Identify the claim precisely** — "faster" at what, by how much, under what conditions? "More efficient" → which resource? "Optimized" → which bottleneck?
2. **Choose metrics** matching the claim:

   | Claim type | Metrics | How to measure |
   |-----------|---------|---------------|
   | Faster execution | Wall time, CPU time | Your test runner's timing output, a shell timer (`time` on POSIX/Git Bash, `Measure-Command` in PowerShell) |
   | Faster build | Build time | Your build tool's timing output, CI run durations |
   | Less memory | Peak RSS, allocation count | Your platform's profiler or memory-counter tooling |
   | Fewer allocations | Allocation rate, GC pressure | Your benchmark harness, allocation profiler |
   | Better throughput | Requests/sec, items/sec | Load test, benchmark harness |
   | Reduced latency | P50, P95, P99 | Tracing dashboard, load tests |

3. **Noise floor — don't optimize below it.** Estimate aggregate savings against run-to-run variance. If projected savings sit within the noise floor, the change is unmeasurable — skip it and surface the noise-floor argument BEFORE doing the work, not after.
4. **Capture the baseline** — measure the pre-change state under controlled conditions (same machine, data, config; minimum 3 runs, ideally 5+; discard the warm-up run). Store mean + std in the topic's memory-tier baselines directory (SKILL.md "Two-phase model" — machine-bound, never committed) and record baseline + target in the plan.

## `compare` phase (at `/verification:measure performance`)

1. **Retrieve the baseline** from the topic's memory-tier baselines directory (or the plan itself). Confirm it was measured under comparable conditions. If no baseline exists, apply the no-baseline honesty rule (SKILL.md "Purpose") — report the current measurement and that the improvement cannot be quantified.
2. **Measure current state** under the SAME conditions as the baseline (same machine, data, config; multiple runs; report mean ± std, not a single number).
3. **Report:**

   ```text
   ## Performance — compare vs baseline

   ### Claim
   <what improvement is claimed>

   ### Methodology
   - Tool: <measurement tool> · Conditions: <machine, data, config> · Runs: <N>

   ### Results
   | Metric | Before (mean ± std) | After (mean ± std) | Delta | % change |
   |--------|--------------------|--------------------|-------|----------|
   | <metric> | <baseline> | <current> | <diff> | <%> |

   ### Assessment
   <statistically meaningful? methodology sound?>
   ```

4. **Verdict:**
   - **CONFIRMED** — measurements show clear improvement with sound methodology
   - **INCONCLUSIVE** — variance too high, conditions differ, or sample too small
   - **NOT CONFIRMED** — no baseline, or measurements don't support the claim
   - **DEGRADED** — performance got worse (flag immediately)

## Common pitfalls

- **Single-run measurements** tell you nothing about variance — always run multiple times.
- **Different conditions** — comparing a debug-build baseline to a release-build current state is meaningless.
- **Micro-optimization without macro impact** — saving 1ms in a function inside a 200ms request is noise, not signal.
- **Forgetting warm-up** — first-run JIT + cold cache inflate initial measurements. Discard the first run or include warm-up.

## Marketplace plugin skills (evidence sources when the harness lands)

- **Code-level perf** — `dotnet-diag:analyzing-dotnet-performance` scans ~50 anti-patterns (async deadlocks, GC pressure, string allocation).
- **Microbenchmarks** — `dotnet-diag:microbenchmarking` for BenchmarkDotNet setup + methodology.
- **Build perf** — `dotnet-msbuild:build-perf-baseline` / `build-perf-diagnostics`.
- **Web perf** — `cloudflare:web-perf` for Core Web Vitals via Chrome DevTools.

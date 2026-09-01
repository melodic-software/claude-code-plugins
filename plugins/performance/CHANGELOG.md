# Changelog

All notable changes to the `performance` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Initial release.** A measurement-first optimization workflow for an arbitrary target, built
  around refusing to report what the data does not support. Generalized from one end-to-end run of
  the workflow by hand against the `disk-hygiene` destructive-guard hook (#3523), including the five
  verification harnesses in that session that each produced a confident WRONG answer rather than an
  error. Settled by the `/planning:interview` #3530 required; see
  `docs/topics/performance-plugin/PLAN.md`.
- **`target`**: identify and rank optimization candidates by evidence quality rather than
  suspicion. An unmeasured target makes "instrument this first" the recommendation, not a guess.
- **`goal`**: human-gated goal construction. Holds a realistic and an ideal target separately and
  computes the irreducible floor before any work, so a target below the floor is surfaced as
  unreachable-by-any-code-change up front. The source run asked for p50 <= 250 ms on a host charging
  0.3-2.8 s per process spawn, and only discovered the goal was unreachable at the end.
- **`snapshot`**: baseline and post capture with the host qualified first. Repeated no-op spawns
  characterize the machine's own noise (via the `spawn_noise` lib shared with `claude-ops`), a
  drift-immune counter is reported alongside and ranked above any duration, arms are interleaved
  within one run rather than compared across two passes, and a wall-clock claim is refused from a
  host carrying the bimodal contention signature.
- **`verify`**: fresh-context adversarial re-derivation that does not inherit the implementer's
  numbers, plus a report that never rounds a miss into a win.
- **`reference/harness-integrity.md`**: the discipline the other skills apply. A harness must prove
  it is not measuring itself, a probe must assert its own precondition and fail rather than silently
  degrade, and a discrimination check must verify its own patch applied and restore from saved bytes
  rather than from version control.
- **`scripts/`**: nine harnesses ported from the source run's scratch tree, which lived on local disk
  only and was not durable. `spawn-census.sh` and `run-spawn-census.sh` (spawn census via a
  **stable** shim dir, closing the defect where a `mktemp -d` shim invalidated the subject's
  `PATH`-keyed cache every run and the census measured its own randomization), `ab.sh` +
  `summarize.py` + `ratio.py` (interleaved A/B, order flipped per iteration, ratio suppressed under
  concurrency and floored at 20 pairs), `differential.py` (byte-identical pre/post behavior over an
  argv matrix), `discriminate.py` (consolidated does-this-check-actually-fail harness), plus
  `harness-lib.sh` and `pathfix.py` for the shared preconditions. Each ships a co-located test suite;
  200 assertions across the nine.
- **`lib/spawn_noise.py`**: a byte-identical copy of the canonical `claude-ops` lib, registered as a
  cross-plugin cluster with a dedicated sync gate so the bimodal threshold has exactly one home.

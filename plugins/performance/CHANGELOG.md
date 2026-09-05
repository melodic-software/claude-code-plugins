# Changelog

All notable changes to the `performance` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.2]

### Changed

- **`target`**: dropped the past-tense account of the retracted WDAC diagnosis and the layer-attribution
  instinct, restating both as present-tense rules that keep the 15x-spread and 88%-of-the-cost
  figures. Consolidated the `Use when:` trigger list into three intents.
- **`goal`**: removed the narration of the run that set an unreachable p50 target and the run that
  learned a counter outlives a duration; both now state the mechanism directly. Consolidated the
  `Use when:` trigger list.
- **`snapshot`**: replaced "this host spread 15.7x" with a deferral to `is_measurable()`, which is
  the gate that owns where the line sits, and restated the drifting-host, harness-integrity,
  stalled-counter and `PATH`-shim passages in the present tense. Consolidated the `Use when:`
  trigger list.
- **`verify`**: restated the separate-phase rationale, the two-verifier floor, the mode-coverage
  rule, the both-arms-differ rule and the green-CI gotcha as present-tense mechanisms instead of
  tallies from one past run. Consolidated the `Use when:` trigger list.
- **Evals**: `target` case 3 and `verify` cases 2, 3 and 7 now assert the rewritten mechanisms
  rather than the removed narration. The prompts and the graded expectations are unchanged.

Applied from the 2026-09 prompt-audit against Claude Fable 5.1 (docs/specs/prompt-audit-skills-2026-09.md).

## [0.1.1]

### Fixed

- **`spawn-census.test.sh` called an assertion helper it never defined, so two
  assertions did nothing.** `assert_not_contains` appears at two call sites; the
  suite defines five functions and that is not one of them, and it sources no
  helper file that could have supplied it. Both calls died as `command not
  found` on stderr, incremented no counter, and the suite still exited 0 with 28
  `PASS` lines against 30 call sites. The two dead assertions guarded exactly the
  false green this plugin exists to refuse: a census line printed for a subject
  that never ran. Proven by mutation rather than argued: emitting
  `spawns=0 rc=127 []` before the never-ran refusal left the old suite at **exit
  0 with zero failures**, and fails the fixed suite twice, naming both the 127
  and 126 arms.
- **An assertion label contradicted its own expectation.** It read "an
  unresolvable denominator still exits 0" while asserting `2`. Exit 2 is a
  refusal, so the label is now "a comparison arm the clock cannot resolve is
  refused", which matches both the assertion and `ratio.py`'s own vocabulary.
- A dead `mkdir` for a fixture directory nothing references, and duplicate
  section-header numbers in two suites.

### Changed

- **`spawn-census.sh` carries a 100-line reflow from the `bash-format` hook**,
  which runs `shfmt` without `-ci` while `.editorconfig` sets no
  `switch_case_indent`, so `case` arms de-indent from four spaces to two. It is
  hook output, not a hand edit, and it is provably semantics-free: `shfmt -mn`,
  `bash --pretty-print` and a whitespace-stripped content hash all report
  identical, and that combination was shown sensitive by six seeded mutations it
  catches against three controls it correctly ignores. Notably a double space
  inside a string literal is caught by the two parsers and missed by both a
  `git diff -w` and the content hash, so no single check would have been enough.
  The suite's output is byte-identical against both versions.

### Known issues

- **The spawn instrument has four undocumented blind spots.** It counts via
  PATH-prepended shims, which is sound for indirect spawns: a subshell, a command
  substitution, a pipeline, `xargs`, a nested script and a backgrounded job are
  all counted correctly. But a subject invoking an absolute path
  (`/usr/bin/sed`), resetting `PATH`, running under `env -i`, or forking without
  exec is counted as **zero**. Three of those emit a tidy `spawns=0 rc=0 []`,
  which is the confidently-wrong-number shape this script's own header exists to
  refuse, and nothing in the plugin's docs mentions the limitation.
- **`pathfix.py` is under-selected by the test mapper.** Four modules import it
  and none of their suites is selected, because the selector seeds its reverse
  lookup with the basename including `.py` while an `import pathfix` reference
  carries no extension. Latent rather than live: mutating `pathfix.py` is still
  caught by its own co-located suite, which drives its whole public surface.

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
  `harness-lib.sh` and `pathfix.py` for the shared preconditions. Each ships a co-located test suite.
- **`lib/spawn_noise.py`**: a byte-identical copy of the canonical `claude-ops` lib, registered as a
  cross-plugin cluster with a dedicated sync gate so the bimodal threshold has exactly one home.

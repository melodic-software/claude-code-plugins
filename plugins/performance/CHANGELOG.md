# Changelog

All notable changes to the `performance` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.3.1] - 2026-10-01

### Fixed

- **`verify` reserves the verifier's final turns for its report**
  ([#5662](https://github.com/melodic-software/claude-code-plugins/issues/5662)). The dispatch brief
  now states a turn cap, a turn to stop gathering by, and a `Coverage:` line naming what was not
  reached; unreached checks stay NOT MET. New eval for the turn budget.

## [0.3.0] - 2026-09-29

### Added

- **`snapshot` verifies instrument identity and the code path each arm took**
  ([#4436](https://github.com/melodic-software/claude-code-plugins/issues/4436),
  [#4437](https://github.com/melodic-software/claude-code-plugins/issues/4437)). Step 1b records the
  measuring tool's path, revision and version, checks the copy is not behind its upstream from local
  refs, and checks the goal's output column is produced. A post snapshot that differs from the
  baseline's tool identity withholds the ratio unless a named tool-identity override is recorded.
  Step 2b reports a per-arm `Path:` line with the state reset or recorded and an `unobserved`
  outcome, flagged like a mismatch. `harness-integrity.md` gains rule 7, failures 7 and 8, and two
  checklist items. New evals for identity mismatch, override and unobserved path.
- **`goal` names the code path under test** and the observable that identifies it
  ([#4437](https://github.com/melodic-software/claude-code-plugins/issues/4437)).
- **`goal` requires a stated bound on how cost grows with state size**
  ([#4438](https://github.com/melodic-software/claude-code-plugins/issues/4438)): flat, or a named
  growth bound, in place of an unproven scaling claim. `goal`'s Gotchas gain a constant-counter
  worked example with its verification record. New `target` evals cover the growing-state candidate.
- **`verify` reports a `Deployed:` disposition and an `Open follow-up:` line**
  ([#4441](https://github.com/melodic-software/claude-code-plugins/issues/4441)), with the
  `installed_plugins.json` claim recorded with its basis. New evals for version mismatch,
  agreement and no install record.

### Changed

- **`goal` moves the parallel-units and growing-state procedures to `techniques.md`**, keeping a
  short rule and the `Event`, `Unit` and `Scaling` output lines
  ([#4438](https://github.com/melodic-software/claude-code-plugins/issues/4438),
  [#4439](https://github.com/melodic-software/claude-code-plugins/issues/4439)). `snapshot` and
  `verify` now consume those lines.
- **`verify` keeps the verdict on the measurement.** A version mismatch no longer forces NOT MET, so
  MET is reachable before merge; the mismatch is carried by `Deployed:` and `Open follow-up:`
  ([#4441](https://github.com/melodic-software/claude-code-plugins/issues/4441)).

### Fixed

- **`snapshot` steps 1b and 2b no longer split the paragraphs that close steps 1 and 2**, so the
  house-rule paragraph ends step 1 and the deterministic-counter paragraph ends step 2.
- **`harness-integrity.md` no longer lists a command substitution as a zero-process case** while
  stating that `$(...)` is always a spawn on MSYS
  ([#4440](https://github.com/melodic-software/claude-code-plugins/issues/4440)). A per-platform
  delta table marks POSIX and native Windows as unmeasured, and the MSYS fork-plus-`CreateProcess`
  mechanism is labeled a hypothesis.

## [0.2.10] - 2026-09-28

### Changed

- **Argument hints** on `goal`, `protect`, `snapshot`, `target`, `verify` stay inside the 100-character house style
  ([#3542](https://github.com/melodic-software/claude-code-plugins/issues/3542)).
  Examples, defaults, and flag catalogs that exceeded the budget now live in the skill body.

## [0.2.9] - 2026-09-28

### Changed

- **Skill descriptions trimmed to 500 characters or fewer (#4661).** Four of the five listed
  skills ran over 500. Each now leads with its use case, keeps its quoted trigger phrases, and
  names its nearest sibling. What the bodies already carry is cut: host-qualification mechanics,
  floor-computation detail, and restated skip lists. `check-listing-budget.sh
  plugins/performance/skills` goes from 4,235 to 2,277 characters. `protect` was
  already under 500. No skill is renamed or merged.

## [0.2.8] - 2026-09-28

### Fixed

- **`verify` ties MET to deployed code, not only a measured tree**
  ([#4441](https://github.com/melodic-software/claude-code-plugins/issues/4441)). Step 3 compares
  the harness path/version with `installed_plugins.json` (or the project-scope install record) and
  refuses **MET** when they differ without a post-deployment re-measurement. The report adds
  `Measured:` and `Deployed:` lines.
- **`goal` and `snapshot` document parallel event-level targets and MSYS process accounting**
  ([#4439](https://github.com/melodic-software/claude-code-plugins/issues/4439),
  [#4440](https://github.com/melodic-software/claude-code-plugins/issues/4440)). Goals for hooks
  (and similar parallel units) record event wall time, unit marginal cost, and event-level
  realistic/ideal targets. `harness-integrity.md` states the Job Object +2-per-external-command rule
  on Git Bash and how it differs from PATH-shim `spawns=` census output.

## [0.2.7] - 2026-09-28

### Fixed

- **`goal` requires a scaling arm when the subject reads growing state**
  ([#4438](https://github.com/melodic-software/claude-code-plugins/issues/4438)). A single-size
  measurement can pass while realistic transcripts grow without bound. The goal records two or more
  sizes, a `Scaling:` line, and a done criterion on how cost may grow with size. **`target`** flags
  growing-state candidates in the ranking table. New eval 11.

## [0.2.6] - 2026-09-28

### Fixed

- **`snapshot` verifies the measuring tool before timing**
  ([#4436](https://github.com/melodic-software/claude-code-plugins/issues/4436)). Record path,
  revision, and version; confirm every flag the goal's metric command names is supported; stop and
  name the fix when the copy is stale or incomplete. New eval 11.

## [0.2.5] - 2026-09-28

### Fixed

- **`snapshot` reports and controls which code path each arm took**
  ([#4437](https://github.com/melodic-software/claude-code-plugins/issues/4437)). Before each arm,
  reset or record state that selects the path; report intended versus observed path with evidence;
  flag arms that do not match the goal's named path. New eval 10.

## [0.2.3] - 2026-09-28

### Fixed

- **`goal` reads its inputs and states the contention predicate** ([#4270](https://github.com/melodic-software/claude-code-plugins/issues/4270)).
  A new section 0 quotes the chosen candidate's `/performance:target` row verbatim and stops when
  the ranking says to instrument that candidate first; with no ranking, it records the tier the
  user's evidence earns rather than the baseline's tier. Section 2 passes the spawn probe's
  summary to `is_measurable()` and quotes its reason, stating the two-part signature (spread at
  or above 3.0x AND a slow mode at or above 500 ms). The Output line reads
  `Target (from /performance:target): <candidate> @ <E1..E4>`. New eval 10 for the
  instrument-first stop.
- **`snapshot` states the paired-ratio median's 20-pair floor** beside the percentile floor,
  mirroring `scripts/ratio.py`; below it the raw per-pair ratios are reported and no median.

## [0.2.2] - 2026-09-28

### Fixed

- **The skills now point at the bundled harness scripts** ([#4269](https://github.com/melodic-software/claude-code-plugins/issues/4269)). No skill body named anything in `scripts/`, so one snapshot run hand-rolled its own interleaving harness and reported 63 ms for a command that exited 127 in every sample. `snapshot` now runs `ab.sh` for interleaving (and says not to hand-roll a timing loop), names `run-spawn-census.sh` for spawn counts and `summarize.py` for the percentile floor. `verify` names `differential.py` and `discriminate.py`.
- **`snapshot`'s `spawn_noise` import anchors to `${CLAUDE_PLUGIN_ROOT}/lib`.** The `parents[3]` recipe assumed a `skills/<skill>/scripts/` caller the plugin does not ship, so a run replaced it with a hardcoded versioned cache path.
- **`harness_require_python` pins the interpreter by absolute path and runs it once.** It returned the bare name `python3` or `python`, which resolves by `PATH` order and can reach a stub. It now uses the `type -P` path and skips (by name) any candidate that fails `import sys`.
- **`harness-integrity.md` covers resolution as well as spelling.** It adds failure 6 (the 63 ms / exit-127 signature), a rule 6 bullet on bare-name interpreter resolution, and checklist items for absolute-path interpreters, exit codes 127 and 126, and using the bundled harness. New evals: `snapshot` 8 and 9, `verify` 11.

## [0.2.1] - 2026-09-27

### Changed

- **`snapshot`**: Storage is three numbered steps: check whether `/verification:measure` resolves, invoke it or record why not, and land the capture under `.work/<topic-slug>/baselines/`. The report header names which branch ran (assisted, verification absent, or verification present and skipped because of a stated reason), so a degraded dependency no longer reads the same as a deliberate skip. A capture that lands outside that path says so at the top of the report.
- README names the reader of each skill's `metadata.workflow-stage` and `metadata.summary`: `scripts/generate-cheatsheet.mjs`, which builds `docs/skill-cheat-sheet.md`.

## [0.2.0] - 2026-09-23

### Added

- **`protect`**: a fifth skill that locks in a proven counter win. It proposes a checked-in
  counter ceilings file, a CI step that fails when a counter rises above its ceiling, and a lower
  ceiling when the counter falls: in the same PR, or through a scheduled draft PR for a counter
  that can fall without a code change. It also covers guardrails
  for fragile optimizations and win decay. It never merges.
- **`scripts/ratchet.py`** with `check`, `propose-tighten`, and `add`, plus `ratchet.test.sh`
  negative controls: a counter above its ceiling fails, at or below passes, and malformed input,
  including a NaN or infinite ceiling or measured value, fails.
- **`reference/techniques.md`**: a technique catalog in loop-phase order (choose the target,
  define the goal and its boundary, lab rigs, prove the proxy, diagnose, latency patterns, protect
  the win, ship and read the field, steer, write the result up). Each skill step points at the
  section it uses.
- **`reference/glossary.md`**: the terms the skills and the catalog use, including correlation,
  ratchet, win decay, measurement boundary, and geometric mean.
- **`goal`**: a required `Correlation:` line (`unproven` is a legal value), a `Boundary:` line
  and measurement-boundary clause (start event, end event, the side of a process or network split
  each falls on, start state), and a gotcha that a metric green while the symptom is visible is the
  wrong metric.
- **`snapshot`**: a `Rig:` line on every duration, the two-rig recipe for correlation evidence,
  first-pass and later-pass times reported separately, and fixed-tick budget-fit counts as counters.
- **`verify`**: report lines `Correlation:` (with `unproven` shown beside the headline counter),
  `Rig:`, an optional `Cost:`, and `Not covered:`; a rule that multi-target aggregates use the
  geometric mean; `## Next` routes a met counter to `/performance:protect` and a met result with a
  large realistic-to-ideal gap to `/performance:target` for a re-scan.
- **`target`**: pointers to the census, region-and-phase tagging, hidden-work, and diagnosis
  sections; screenshots and recordings count as candidate sources; telemetry is checked for
  accuracy and coverage before it ranks anything.

### Changed

- **`harness-integrity.md` rule 3**: a check that may be flaky repeats each arm N times, with N
  chosen per check and recorded, and both arms must be N/N. Rule 1 adds the fixed-tick rig
  self-check. The checklist gains the N/N item.
- **README**: the skill table lists five skills; the Baselines rule narrows to "durations are
  never committed; a counter ceiling for `/performance:protect` may be"; a Reference section points
  at the catalog, the glossary, and the source article.
- **`snapshot` storage** states that a counter ceiling is not a baseline and no duration is
  committed. The manifest description lists five skills.
- **`verify`**: an unexercised mode is reported under `Not covered:`.

## [0.1.9] - 2026-09-21

### Changed

- American spellings throughout this plugin's prose, ahead of the `en-us` locale the
  shared typos config adopts. Wording only: no behavior, option, default, or identifier
  changes. Released sections were corrected in place on the same terms.

## [0.1.8]

### Changed

- The nine performance script suites source one test-helpers.sh for their pass, fail, assert and capture helpers instead of nine inline copies. Case numbering, output and exit codes are unchanged.

## [0.1.7]

### Changed

- Route the resolve-and-note step through one helper, dedupe with dict.fromkeys, fold the drive-rest default and drop dead initializers and guards in the performance harness scripts (behavior unchanged).

## [0.1.6]

### Added

- **`verify`**: a `## Next` section naming the skill that normally runs after this one, in
  the mention-only shape the skill-body rule describes.

## [0.1.5]

### Fixed

- **`ab.test.sh`**: the unread stdin arm is `sleep 0.01` instead of `exit 0`, so a host whose
  millisecond clock records `exit 0` as 0ms still produces a defined paired ratio. Sleep does
  not drain stdin, so the 141-fabrication assertion still holds.

## [0.1.4]

### Fixed

- **`ab.test.sh`**: the plumbing no-op is `sleep 0.01` instead of `printf ok`, so a host whose
  millisecond clock records `printf` as 0ms still produces a defined paired ratio rather than
  fail-closing every comparison-arm sample.

## [0.1.3]

### Changed

- **`harness-integrity.md` rule 6**: corrected the Windows path-spelling claim and every restatement
  of it across the plugin. A drive-letter path in forward-slash form does resolve when bash reads it.
  What collapses is the backslash form interpolated unquoted into a command string, which then exits
  127. The rule now carries a dated verification and a recheck trigger, and the
  `harness_require_posix_path` refusal with its `--allow-windows-paths` escape hatch is unchanged.
  (prompt-audit follow-up F2)
- **`harness-integrity.md` framing**: restated the failure table's introduction, the rule prose, and
  the two section headings in the present tense, dropping the session narration, the "four of the
  five" and "three of the five" counts, and the standalone-skill aside. Prose now points at
  "failure N" rather than "case N", and no table row, rule, or assertion was renumbered or
  reordered. (prompt-audit follow-up F2)
- Dated the benchstat flag-set claim in the snapshot skill against the tool's own documentation (prompt-audit follow-up F6)

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

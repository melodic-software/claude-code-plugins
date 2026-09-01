# performance-plugin

Source issue: [#3530](https://github.com/melodic-software/claude-code-plugins/issues/3530).
Interview: round 1, Q1-Q9, all answered 2026-08-31. Ledger (memory tier, not committed):
`.work/performance-plugin/interview-checklist.md`.
Research slice (memory tier, not committed): `.work/performance-plugin-methodology/RESEARCH.md`.

## Brief

### TLDR

- A new `performance` plugin whose skills run a measurement-first optimization workflow: identify a
  target, construct a goal with realistic and ideal tiers plus a computed floor, snapshot a
  baseline, verify, and report.
- Its headline metric is a **drift-immune counter**, not a duration. It ships exactly one built-in
  counter (process spawns); every other metric is user-declared per domain.
- It **refuses** to report a wall-clock claim from a host whose noise it has characterized as
  pathological, and says which counter it can report instead.
- It owns measurement, goal construction, and verification. It delegates the code change to
  `/implementation:implement` and depends on `/verification:measure` for baseline/compare mechanics.
- Gates hard-block. Every gate ships with a discrimination check proving it fails when its condition
  is unmet.

### Goal

Performance optimization in this fleet becomes a repeatable, measured discipline rather than a
per-session improvisation that produces confident, unverifiable numbers. The plugin exists because a
competent operator with a strong prompt still produced five verification harnesses in one session
that each returned a **confident wrong answer** rather than an error. The workflow's value is not
that it measures; it is that it refuses to report what it cannot support, and that every gate it
enforces has itself been proven to discriminate.

### Constraints

- **No skill may report a duration without a noise characterization.** Violating this reproduces the
  exact failure the plugin exists to prevent.
- **Every gate must be verified to discriminate.** A check that passes whether or not its condition
  holds is worse than no check, because it reports success. Each gate ships with a two-arm test: a
  positive arm where it must fire and a negative arm where it must not, and the arms must be shown
  to differ.
- **`/verification:measure` is not reimplemented.** It already owns two-phase baseline/compare,
  machine-bound baseline storage, and the no-baseline refusal. Duplicating it is the silent second
  way `/discipline:reuse-or-replace` prohibits.
- **The noise-characterization threshold has exactly one home.** No copy of
  `BIMODAL_SPREAD_RATIO` may exist in two plugins.
- New plugin follows repo conventions: `.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md`,
  marketplace entry with a category drawn from `docs/CATALOG-TAXONOMY.md` (read
  `.claude/rules/catalog-taxonomy.md` first), changelog-parity and plugin-schema CI gates green.
- Validate with `scripts/affected-tests.sh --run`, never a hand-picked suite.
- Prose follows the repo's house style; `plugins/*/skills/*/vendor/**` formatting is not a model.

### Acceptance criteria

- `plugins/performance/` exists with a manifest that validates — the `plugin-schema` CI gate goes
  green on the new directory, and `changelog-parity` passes.
- `/skill-quality:check` reports PASS for each new skill.
- The workflow refuses to report a wall-clock claim from a host characterized as too noisy to
  measure — asserted by a test feeding it a high-variance baseline (refusal) AND a low-variance
  baseline (normal report), with the two arms shown to produce different outcomes.
- A drift-immune counter is reported alongside, and ranked above, any duration — verified by reading
  the emitted report format.
- Every normative claim in a skill body carries a citation to a source fetched during the research
  pass, or is explicitly labelled as a house rule with no field consensus behind it.
- `claude-ops:audit-performance` consumes the promoted shared noise-characterization lib and its
  existing tests still pass.

### Decisions locked in the interview

| Q | Decision |
|---|---|
| Q1 | **Narrow metrics, broad targets.** Any target reducible to one repeatable command. Process-spawn count is the ONLY built-in drift-immune counter; all others are user-declared per domain. |
| Q2 | **Depend + route.** `performance` owns the discipline and depends on `/verification:measure` for baseline/compare. `measure` stays and gains one routing line pointing here for wall-clock claims on a drifting host. |
| Q3 | **Measurement + goal + verification only.** The code change is delegated to `/implementation:implement`. |
| Q4 | **Gates hard-block**, with a named per-gate override that is recorded in the emitted report. |
| Q5 | **Reuse `BIMODAL_SPREAD_RATIO`** as the unmeasurable-host threshold rather than inventing a second number. Q4's recorded override applies. The refusal message must name the counter it can still report. |
| Q6 | **Baselines live in the memory tier**, `.work/<topic-slug>/baselines/`, machine-bound, never committed. Matches `/verification:measure` exactly. |
| Q7 | **Promote the noise-characterization algorithm into a shared lib** with one home for the threshold, and refactor `claude-ops:audit-performance` to consume it. No reaching into its private script directory; no copy-and-drift. |
| Q8 | **Phases 2-6 may run unattended. Phase 1 (goal construction) is human-gated always.** The loop is opt-in, may open PRs, may never merge. Mirrors the repo's existing loop-lane topology. |
| Q9 | **Both pairing modes.** Sequential interleaving suppresses the paired ratio under concurrent load; simultaneous duet-style paired arms report it. #3530's Phase 4 text is corrected, not followed. |

### Captured assumptions

- The plugin is used primarily on this host and hosts like it (Windows, MSYS/native mix, bimodal
  process-creation cost) — revisit if it is aimed at contributors whose hosts are always noisy, which
  would make the Q5 refusal posture unusable rather than protective.
- Promoting the shared lib will not break `claude-ops:audit-performance`'s existing tests — revisit
  if that refactor turns out to touch its reporting contract rather than just its internals.
- Skill decomposition (one workflow skill with phases, versus one skill per phase) is a planning
  decision — revisit if it turns out to change what the acceptance criteria can assert.

### Out-of-scope

- Owning the code change. Phase 3 delegates to `/implementation:implement`.
- Reimplementing baseline/compare mechanics that `/verification:measure` already provides.
- Built-in counters beyond process spawns. Syscall, query, and allocation counters are user-declared
  in V1 and only become built-ins once validated against a real target.
- Merging its own PRs, under any autonomy setting.
- Superseding or removing `/verification:measure`.

### Deferred questions

- Q10 — Where exactly does the shared noise-characterization lib live, and does the
  `claude-ops:audit-performance` refactor land in this PR or a follow-up? — defer until planning;
  **arbiter: /planning:plan**
- Q11 — Skill decomposition: one workflow skill with six phases, or one skill per phase? — defer
  until planning; **arbiter: /planning:plan**
- Q12 — Sample count and percentile choice. #3530 says "p50 and p95 over >=20 samples", but the
  research found no community-grounded sample count and the SRE Book names 99th/99.9th rather than
  p95. Whatever ships is a house choice and must be labelled as one. — defer until skill authoring;
  **arbiter: USER-RESERVED**

## Plan

<!-- empty — populated by /planning:plan -->

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

Written 2026-08-31 against `feat/performance-plugin` (branched from `origin/main` at `79f1c29`).
Resolves Q10 and Q11 (arbiter `/planning:plan`). Q12 stays USER-RESERVED and is surfaced at the
approval gate below, not resolved here.

### Q11 resolved — skill decomposition

**Four skills, no router.** Each names its successor, the way the repo's own planning pipeline
chains (`interview` -> `explore` -> `plan` -> `implement`) rather than routing through a hub.

| Skill | Phases | Owns |
|---|---|---|
| `/performance:target` | 0 | Identify and rank candidate targets by **evidence quality**, not suspicion. When nothing is measured, the top recommendation is "instrument this first". Entry point. |
| `/performance:goal` | 1 | Human-gated always. Metric + the exact command producing it, a **realistic** target, an **ideal** target, and the computed **floor**. Refuses to accept a target below the measured floor without the user deciding. |
| `/performance:snapshot` | 2, 4 | Host qualification, snapshot capture, interleaved and duet A/B, the drift-immune counter, and the unmeasurable-host refusal. |
| `/performance:verify` | 5, 6 | Fresh-context adversarial re-derivation that does not inherit the implementer's numbers, plus the report. |

**Naming.** `snapshot`, not `measure`. Q2 locked "depend + route" on `/verification:measure`; two
skills named `measure` in two plugins is the routing line failing to route. `snapshot` is also
#3530's own vocabulary ("baseline snapshot", "post snapshot").

**Harness-integrity is a shared reference plus a script, not a fifth skill.** The five
confident-wrong harnesses are the plugin's most important content, but they are a discipline applied
*inside* `snapshot` and `verify`, not something invoked standalone. Ships as
`reference/harness-integrity.md` plus `scripts/discriminate.py`, both consumed by the two skills that
need them. Promoting it to a fifth skill is the obvious V2 move if users start asking "does my
harness actually discriminate?" as a standalone question; deferring keeps the shared skill-listing
budget lower for V1.

### Q10 resolved — the shared lib, and the PR split

**A cross-plugin runtime import is not available.** Plugins install independently, so
`performance` cannot import from `claude-ops` at runtime. The interview's accepted answer ("promote
into a shared lib") is implemented through the repo's established mechanism for exactly this, not
through an import.

**The established pattern**, already carrying six clusters (`scripts/cross-plugin-source-registry.txt`):

- canonical source at repo root `lib/<name>`;
- byte-identical copies at `plugins/<name>/lib/<name>` in each carrying plugin;
- a dedicated `scripts/sync-<name>.sh` built on `scripts/lib/sync-cluster.sh`, giving `--check`,
  `--check-bump <ref>`, and `--print-manifest`;
- registered in `scripts/cross-plugin-source-registry.txt` with its check named;
- a CI job.

This satisfies the brief's constraint that the threshold has exactly one home: `lib/` is the home,
and every copy that drifts fails CI loudly.

**Applied here:**

- Canonical `lib/spawn-noise.py`, holding `summarize_spawn_samples`, `spawn_probe`,
  `BIMODAL_SPREAD_RATIO`, `SLOW_SPAWN_FLOOR_MS`, `SPAWN_SAMPLES`, `NOOP_SPAWN`.
- Copies at `plugins/claude-ops/lib/spawn-noise.py` and (in PR 2)
  `plugins/performance/lib/spawn-noise.py`.
- `scripts/sync-spawn-noise.sh` + registry entry + CI job `spawn-noise-sync`.
- `audit_performance.py` imports it with the `sys.path.insert(_LIB_DIR)` shape already used by
  `plugins/disk-hygiene/skills/clean/scripts/destructive_guard.py:55`, and **re-exports the names**
  so `test_audit_performance.py`'s `engine.summarize_spawn_samples` keeps resolving. The promotion is
  test-invisible; the six existing cases are the proof.

**The threshold is a two-part predicate, not a constant.** `bimodal-spawn-latency` fires on
`spread_ratio >= BIMODAL_SPREAD_RATIO (3.0)` **AND** `max >= SLOW_SPAWN_FLOOR_MS`. A wide ratio alone
is not the contention signature: a cold first spawn against a warm second clears 3x while every
sample is still fast. `performance` must consume the predicate, never re-derive a verdict from the
ratio alone.

**Two PRs.**

- **PR 1** — lib promotion, sync gate, registry entry, CI job, `claude-ops` refactor + CHANGELOG +
  version bump. Self-contained, test-invisible, independently reviewable.
- **PR 2** — the `performance` plugin itself, consuming the lib, plus the one routing line into
  `/verification:measure`.

Rationale: PR 2 is already large (four skills, harness scripts, evals, marketplace entry). Folding a
cross-plugin refactor of a third plugin into it makes review materially worse. The split is
reversible: if PR 1 reviews trivially, PR 2 can be opened before it merges and rebased.

### Category

`verification`. Checked against the taxonomy's Assignment principle rather than assumed: the subject
is arbitrary code, not one of the special subjects (Claude Code, the workstation, music, personal),
so the plugin files by lifecycle activity. `verification`'s scope line is "Prove a change achieved
its intended outcome against baseline and intent", which is this plugin's whole shape.
`codebase-health` is filed `quality` because it audits artifacts on an absolute axis; this plugin is
before/after proof against a baseline, which is the distinguishing trait.

### Approach, in order

1. **PR 1.** Extract `lib/spawn-noise.py`; add `scripts/sync-spawn-noise.sh` + its `.test.sh`;
   register the cluster; add the CI job; refactor `audit_performance.py` to import and re-export;
   bump `claude-ops` version + CHANGELOG. Gate: the six existing `summarize_spawn_samples` cases pass
   unchanged.
2. **Scaffold `plugins/performance/`** — `.claude-plugin/plugin.json`, `CHANGELOG.md`, `README.md`,
   `lib/spawn-noise.py` (synced copy), marketplace entry, regenerated `docs/CATALOG.md`. Gate:
   `plugin-schema` and `changelog-parity` green.
3. **Author `reference/harness-integrity.md`** first, before any skill body. It is the content the
   other four depend on, and it is the plugin's reason for existing.
4. **Author the four skills**, each citing the research slice. Parallelizable across workers once
   step 3 lands, since each is a separate file with no shared edit surface.
5. **Port the harnesses** from `D:/worktrees/bench-dh/` into `scripts/`, with precondition assertions
   built in. They live on local disk only and are not durable.
6. **Add the routing line** to `plugins/verification/skills/measure/SKILL.md` + CHANGELOG + version
   bump.
7. **Evals** per skill; `/skill-quality:check` per skill.
8. **PR 2** per the repo's body template.

### Test strategy

- **The refusal criterion is the highest-risk one.** Per the source session, four of five
  discrimination checks failed by exiting identically in *both* arms and reporting "not
  discriminating". So the refusal test asserts three things, not two: the high-variance arm refuses,
  the low-variance arm reports normally, and **the two arms produced different output** as a
  first-class assertion. Annotated `# discriminating-skip-required:` so
  `scripts/check-discriminating-test-skips.sh` forbids skipping it.
- Contract tests as `plugins/performance/**/*.test.sh`, modelled on
  `plugins/disk-hygiene/hooks/run-python-hook.test.sh` (32 assertions, full cache-invalidation
  matrix) — tests that assert their own preconditions.
- Python unit tests for `lib/spawn-noise.py`.
- Validate with `scripts/affected-tests.sh --run`, never a hand-picked suite.
- Lint against LF content (`tr -d '\r'`): `core.autocrlf=true` on this machine makes shellcheck
  report SC1017 on every line and bury real findings.

### Blast radius

| Surface | Change |
|---|---|
| `lib/spawn-noise.py`, `scripts/sync-spawn-noise.sh` (+ test), CI workflow, registry | New (PR 1) |
| `plugins/claude-ops/**` | Refactor + CHANGELOG + version bump (PR 1) |
| `plugins/performance/**` | New (PR 2) |
| `.claude-plugin/marketplace.json`, `docs/CATALOG.md` | New entry + regeneration (PR 2) |
| `plugins/verification/skills/measure/SKILL.md` + CHANGELOG + version | One routing line (PR 2) |

Three plugins are touched in total. Two of them (`claude-ops`, `verification`) are existing,
installed, and working; both changes are additive and version-bumped.

### Surfaced at the approval gate

**Q12 (USER-RESERVED) — sample count and percentile choice.** #3530 specifies "p50 and p95 over >=20
samples". The research grounds none of it: no benchmarking-community sample count for a meaningful
percentile exists beyond the derivable `1/(1-p)` floor, and the SRE Book names the 99th and 99.9th
percentiles rather than p95. Whatever ships is a house choice that must be labelled as one in the
skill body. This needs the user at the approval gate, because it changes what the skills assert.

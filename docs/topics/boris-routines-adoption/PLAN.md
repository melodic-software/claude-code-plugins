# boris-routines-adoption — PLAN

Research record: `.work/boris-routines-adoption/research/` (8 lane files) and the interview ledger
`.work/boris-routines-adoption/interview-checklist.md`. Primary source and its evidentiary standing:
`.work/boris-routines-adoption/source/README.md`.

## Brief

### TLDR

Generalize the maintenance-routine pattern reported by @bcherny (2026-08-13) into tool-, org-, and
product-agnostic capability for this marketplace: **detectors** that emit conforming findings, plus
**catalog rows** governing them, plus the **substrate** both need. Not a port of his eleven routines,
and not a new plugin.

The research inverted the original framing three times, and the Brief encodes the inverted shape:

1. **The apply machinery already exists and is reachable by file format alone** (validated, below).
   What is missing, class after class, is a **detector** to feed it.
2. **Merge rate cannot justify any of this.** Three independent lines — peer-reviewed observational,
   large-N regression, randomized trial — find artifact quality weakly-to-not coupled to acceptance.
   The verification contract is justified on **defect escape** and **reviewer burden**, never on
   acceptance.
3. **Class-level beats instance-level.** Three lanes converged from different literatures: durable
   wins come from policy and mechanism, not from better per-instance agent judgement.

### Goal

Ship, in dependency order:

- **Tier 0 substrate** — the four items below, which every candidate class depends on.
- **Tier 1 detectors** — three classes with the strongest evidence and a real local surface.
- **Catalog rows** for every class considered, including the ones deliberately not built, so the
  reasoning is recorded rather than re-litigated.

### Constraints

**Binding repository rules** (verified, `path:line` in the research record):

- **ADR 0005** — a new class extends the existing catalog: a `reference/` edit plus a `CHANGELOG.md`
  entry plus a version bump. **Not a new catalog, not a new skill, not a new plugin.** This closed
  the original "where does it land" question; it is not reopened here.
- **ADR 0004 incumbent-first gate is binding** — no remediation ships until it proves no existing
  skill covers it, with `path:line` evidence. Satisfied for all eight classes by
  `research/V1-coverage-negatives.md`; each issue carries its own evidence.
- **ADR 0008** — a row is admitted only when its observable is anchored to text that is present. An
  obligation a surface *should* satisfy, anchored to nothing, does not become a row however well
  sourced.
- Version bump **and** matching CHANGELOG entry in the same PR (CI-enforced, zero exemptions);
  `metadata.workflow-stage` required; regenerate `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md`;
  SKILL.md under 500 lines; **evals required for any new skill**; only `docs/topics/` is
  docs-only-allowlisted, so anything under `plugins/**` runs the full CI suite.

**Product constraints** (verified at primary, `code.claude.com/docs/en/routines.md`, 2026-08-14):

- Routines are available on **Pro, Max, Team, and Enterprise** — the mechanism is reachable on this
  account. Claude Tag (the Slack surface the source used) is Team/Enterprise-only and is out of
  reach; only that delivery surface is unavailable, not the capability.
- **Minimum schedule interval is one hour.** Runs count against a per-account daily allowance;
  **one-off runs do not**, which is the pilot lever.
- **No permission containment during a run** — "no permission-mode picker and no approval prompts".
  Containment is repo selection, environment, connector list, and the `claude/`-branch push rule.
- **Repo `.claude/` loads; user-scope `~/.claude` does not.** `pluginConfigs` is ignored at project
  scope by design, so any plugin taking `userConfig` has no cloud-run way to receive values.
- **Green status ≠ success** — "It does not mean the task in your prompt succeeded." Efficacy reads
  logs, never statuses.
- **Workflows do not travel into scheduled runs**; custom slash commands do.

**Evidentiary constraint:** the source is a single self-report with zero independent corroboration
and no published methodology. Nothing in this plan may cite 388/180 as evidence of efficacy.

### Acceptance criteria

Per-unit close-out loop — one class at a time: incumbent evidence recorded → row derived through the
catalog's own mapping rules → detector or deferral shipped → CI green → CHANGELOG + version bump in
the same PR. A class is **closed** when its row exists with a derived guardrail class and either a
shipped detector or a `join:` trigger naming what would unblock it.

1. **Findings-file coexistence is settled before a second producer ships.** The fix action consumes
   exactly one file and merges nothing; two producers in one branch directory means the later
   timestamp silently wins. Green run, hidden findings. This is a correctness gate, not a nicety.
2. **Every detector emits machine-computed severity**, not prose routed through an LLM crosswalk. No
   crosswalk row exists for a deterministic surface today; that is contract work, not a detail.
3. **Every class-level gate satisfies items 1-2 of the trust-path definition** (below). Items 3-5 are
   org-scale and explicitly deferred at solo volume.
4. **No acceptance-rate metric anywhere** — not as a promotion input, not as an efficacy signal.
5. Each shipped detector carries evals, per the CI gate.

### Captured assumptions

- The format-only path stays supported. **Validated 2026-08-14, not assumed**: a hand-written
  conforming file from a non-fanout producer passed the fix action's locator, frontmatter gate,
  exact-branch check, and table parse, including the cell-escaping rule. Probe deleted afterward —
  while it existed it *was* the newest file in that directory and would have shadowed a real review.
- Detectors are scripts unless a named agent is earned. The repo's own philosophy prefers one script
  "wherever the judgment is mechanical", and fanout can dispatch **agents only** — which is why
  `mutation-testing:audit`, the best deterministic detector in the fleet, reaches no relay today.
- Catalog rows derive their guardrail class through the existing mapping rules, never by hand.

### The class-level trust path (the operative definition)

An **instance-level** path asks a judge to evaluate each change on its merits. A **class-level** path
decides once, for a category, what condition makes any member acceptable — so the per-instance
question collapses from a judgement to a check. The mechanism: per-instance persuasion is subject to
habituation; a standing class rule is not.

| # | Requirement | Portable? |
|---|---|---|
| 1 | Class definition narrow enough that membership is decidable without judgement | **yes** |
| 2 | Machine-checkable gate that fails closed | **yes** |
| 3 | A denominator — enough instances to compute a rate | org-scale |
| 4 | An outcome signal that is **not** the merge decision | org-scale |
| 5 | A lookback window and a demotion rule | org-scale |

"Dead-code removal where the code is provably unreachable" is a class. "Code quality improvements"
is not. If deciding membership needs the judgement you were eliminating, it is an instance-level path
wearing a class-level label.

Solo shape: **the gate without the statistics** — narrow class, machine-checkable gate, run it
*before* the PR opens, human on the merge. The earned auto-merge tier is deferred with a trigger.

### Scope — tiers

**Tier 0 — substrate. Blocks everything.**

| Item | Why |
|---|---|
| Findings-file coexistence | Silent-shadowing correctness bug the moment a second producer exists |
| Detector contract | Machine-computed severity, rule/threshold vocabulary, suppression; owner doc must precede the **second** adopter |
| Per-repo capability detection | The agnostic core: which classes bind, resolved from repo state (build files, language, test framework, flag system, architecture config, MCP servers, CLI tools) |
| Repo-scope plugin declaration | User-scope does not load in cloud; **gated on the cloud probe** (below) |

**Tier 1 — build.** Formal-logic modeling (decision tables + property-based testing; strongest
evidence, and its mechanical artifacts *are* the verification payload) · useless-test **repair**
queue (genuinely uncovered; the fleet names the capability it lacks) · layering enforcement, **inform-human posture** (most mechanical once rules exist; propose-and-baseline, never impose-and-fail).

**Tier 2 — rows now, build later.** Dead code, both postures, with a **30-90 day** window floor and
staged quarantine — never the source's one-day window · clone **detection** + trend gating (the unify
*decision* has no automation precedent in twenty years) · stale-flag removal (strong prior art;
consumer-facing, no local surface).

**Tier 3 — rows recording why not.** Logic simplification above expression level (no published
effectiveness evidence; excluded by name in `tidyings.md`) · abstraction flattening (no validated
detector exists, and the fault data runs backwards — Speculative Generality and Middle Man sometimes
*reduce* faults) · ant-only shipper (the decision is a human product call) · GUI crash fuzzing (no
local surface; 36.6% crash-replay reproducibility).

### Out of scope

- A new plugin, a new catalog, or a parallel governance surface (ADR 0005).
- A self-tuning routine class. Across 22 verified papers, none tunes from deployed production
  outcomes with a human gate; the famous citations are within-episode and do not persist. The
  existing promotion apparatus is the better-grounded shape and already avoids the merge-rate
  confound by keying on completions, gate passes, and reverts.
- Auto-merge without human review at solo volume — requirements 3-5 above are unmeetable here.
- Porting the source's prompts. They are a **meta-prompt** (instructions to *create* routines), one
  layer above any stored prompt.

### Deferred questions

- **Q12 (arbiter: USER-RESERVED)** — repo-scope plugin declaration in cloud. Two official pages
  contradict each other on whether repo-declared marketplace plugins install; workspace trust for a
  cloud clone is undocumented, and if untrusted the declaration is ignored **silently**;
  private-marketplace auth in cloud is undocumented. **One probe settles all three**: scratch repo,
  declare a plugin via `extraKnownMarketplaces` + `enabledPlugins`, fire a routine, read the
  transcript — public and private. Unresolvable from documentation. Tier 0's fourth item is blocked
  on it, and the documented alternative (components committed directly to `.claude/`) is the fallback.
- **Q4 follow-on (arbiter: `/planning:plan`)** — add a reviewer-burden term to the existing promotion
  predicate, and keep any future tuner's signal set disjoint from promotion evidence. Composition
  hazard if not: a tuner could raise the metric that promotes the cell that reduces scrutiny of the
  tuner's own output.
- **Q2 (resolved, recorded)** — `join: proven recurring manual pattern` stays our-own-proven. The
  source's run is named-product evidence and belongs in the routine-catalog research record, not the
  non-normative precedent-pointers section, whose own scope line routes it elsewhere.
- **Live daily run-cap numbers (arbiter: USER-RESERVED)** — the docs direct readers to
  `claude.ai/code/routines`; published figures trace to a stale April blog post. Needs an
  authenticated session.

## Plan

_Empty. `/planning:plan` fills this section._

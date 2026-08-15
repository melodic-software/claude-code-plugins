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

- **Q12 (arbiter: USER-RESERVED)** — repo-scope plugin declaration in cloud. **Filed as
  [#2660](https://github.com/melodic-software/claude-code-plugins/issues/2660)** (`needs-human`).
  Two official pages contradict each other on whether repo-declared marketplace plugins install;
  workspace trust for a cloud clone is undocumented, and if untrusted the declaration is ignored
  **silently**; private-marketplace auth in cloud is undocumented. One probe settles all three, and
  it cannot run unattended — browser selection, account mutation, and metered usage all require the
  human. Tier 0's fourth item is blocked on it; the documented alternative (components committed
  directly to `.claude/`) is the fallback and needs no marketplace fetch, trust step, or credentials.
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

Design gate: Tier B early-exit — `design/design-resolution.md`.

Revised 2026-08-15 after a fresh-context adversarial pass. Every change below is anchored to a file
re-read this session; the pre-revision draft is `ecdd288c`.

### Goal

**What**: ship the Tier 0 substrate, then the first Tier 1 detector, then catalog rows for every
class considered — sequenced so the silent-shadowing correctness gate closes before any second
findings producer exists.

**Why**: the Brief settles *what*; nothing in it reaches a repository until a detector emits a
conforming findings file and the apply relay consumes it without dropping the other producer's
findings.

**Approved 2026-08-15.** Branch shape (a); both reductions below and the close-out deviation accepted
as stated.

**Two reductions against the Brief, stated rather than absorbed** — both were routed to the approval
gates in "Handoff to implementation", because dropping Brief-listed scope is the user's call, and
both were accepted there:

1. The Brief's Tier 1 names **three** detectors. This cycle ships **one** (can't-fail tests). The
   other two become catalog rows with named triggers. Rationale in "Alternatives considered"; the
   reduction itself is not a mechanical outcome.
2. The Brief names a useless-test **repair queue**. This cycle ships **detection**. Per `V1` §C.4 a
   judgment-shaped finding is surfaced, not auto-applied, so the queue-and-apply half needs an
   explicit decision it has not had.

**One deviation from the Brief's stated discipline**: the Brief's acceptance criteria describe a
per-unit close-out loop, "one class at a time". This plan batches rows into one phase and ships one
detector in another — stage-at-a-time. Reason: the substrate phases are shared by every class, so a
per-class loop would re-pay them N times. Flagged rather than silently restructured.

### Standards grounding

No standards index exists in this repo (`.claude/` holds `settings.json`, `source-control.md`,
`hooks/` only). Surfaces inferred from repo structure; nothing was written to persist an index.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/adr/` | 0004 incumbent-first gate · 0005 extend-the-catalog · 0008 (see note) | team |
| `docs/PLUGIN-PHILOSOPHY.md` | Naming (`:59-60`) · convention registry (`:468-499`) · deterministic-gate preference (`:664-666`) · named-agent bar (`:718-720`) | team |
| `docs/conventions/liveness-assertion/` | `README.md:58` green-with-hidden-findings class | team |
| `docs/conventions/finding-suppression/` | opt-in obligations + derived `finding_id` | team |
| `docs/conventions/topic-docs/` | contract slice vs memory slice, prune-with-pointer | team |
| `plugins/source-control/skills/commit/reference/exec-bit.md` | exec-bit + Windows filemode trap | team |
| `scripts/docs-only-paths.txt` | `:38-42` — exec-bit and ShellCheck are ungated and repo-wide | team |
| `AGENTS.md` | `git add -A` prohibition (its only surviving rule) | team |
| `REVIEW.md` | org severity vocabulary overriding `plugins/review/context/severity.md` | team |
| `~/.claude/CLAUDE.md` | pointer-not-copy · producer ≠ critic · no suppressed diagnostics | personal (user-global) |

**ADR 0008 note.** Its title and body scope it to the **instruction-audit catalog**
(`plugins/claude-config/skills/audit-instructions/`), not the routine catalog. The Brief applies its
present-text principle to routine rows by analogy. This plan follows the Brief but states the
citation as analogical, not as a direct binding.

**Repo defect found while grounding, needing an upstream fix.** `AGENTS.md` is 28 lines at HEAD and
carries only the `git add -A` rule; commit `e22190ed` ("chore: sync standards components") deleted
the 34 lines `7c2a9b3d` had added, including the exec-bit and Windows-filemode guidance. It is a
managed materialization, so a local patch is deleted by the next sync — the fix belongs upstream in
`melodic-software/standards`. Tracked as a follow-up, not a phase of this plan.

### Phase dependency spine

```text
P1 coexistence ──> P2 convention stub ──> P3 Pattern-C pilot ──> P4 harden convention ──> P7 detector
                        (must merge to main)                                                  ^
P5 catalog rows ──> P6 predicate term ───────────────────────────────────────────────────────┘
                        (one autonomy PR)                             (P7 amends its row)

P8 capability detection ── promoted to its own topic; independent track
P9 repo-scope plugin declaration ── blocked on spike #2660
P10 graduate + prune the contract slice ── terminal; the gate FAILS today
```

Three ordering constraints, each with a reason that is not obvious:

- **`P1 → P3`**: fanout is producer #1, so **the first detector of any kind makes producer #2**, and
  `fix-pass-mode.md:3` consumes exactly one file. Coexistence is strictly first, not merely early.
- **`P2 → P3`**: `PLUGIN-PHILOSOPHY.md:471` — "A new cross-plugin convention lands in an owner doc
  **before a second plugin adopts it**." That is a deadline, not a licence to author it late. The
  multi-producer rule is a cross-plugin concern, and P3 makes `mutation-testing` the second plugin
  adopting it, so a stub owner doc must precede P3. P4 then hardens the stub from what P3 observed —
  which is the real argument for the doc trailing the pilot, and it survives without `:471`.
- **`P2 merged to main → P3`**: a plugin cannot cite a repo-relative `docs/conventions/` path — it
  installs standalone. The repo's established form is a raw URL to `main`
  (`plugins/architecture/reference/topic-docs.md:6` and four more), and
  `plugins/skill-quality/scripts/check-skill.sh:480-495` fails broken refs. So P2 and P3 cannot ride
  one PR, and P2 must land first.

---

### Phase 1: Multi-producer findings coexistence [TODO]

Review: architecture

Closes Tier 0 item 1 and acceptance criterion 1. Shape in `design/design-resolution.md` Sketch 1.
**Two changes, not one** — the merge is inoperative without the first.

- [ ] **Pre-flight consumer check** (FIRST work item — this migrates a consumed file contract):
      `grep -rn "review-findings\|fix-pass-record\|source-findings" --include='*.md' --include='*.sh' --include='*.py' .`
      Enumerate every parse path of the findings frontmatter, the findings table, and the record,
      inside and outside `plugins/review/`. Record each parse site in the phase notes before editing.
- [ ] **Change 1 — the record becomes a consumption ledger.** `fix-pass-mode.md:76` writes it only
      under `--yes` in a non-interactive session; "Interactive and headless-stop paths write no
      record". Make the write **unconditional on every apply path**, and let `source-findings:`
      carry the full consumed **set**. Its unwatched-apply review role becomes additive. Without
      this, the interactive path — the Brief's own solo shape — has no consumption marker at all and
      the merge set grows without bound, re-injecting findings that `fix-pass-mode.md:95`'s required
      re-review has already resolved.
- [ ] **Change 2 — the locator becomes a merge set.** All `type: review-findings` files whose
      `branch:` equals the current branch exactly, minus every file named by any `source-findings:`
      of a record **whose own `branch:` also matches exactly**. The branch filter applies to *both*
      sides: `fix-pass-mode.md:7` calls it load-bearing because the slug is lossy, and an unfiltered
      record from a slug-collided branch would silently truncate the set.
- [ ] **Dedup is presence-only**: collapse rows sharing identical `Location` **and** identical
      `Finding` text; everything else stays a distinct row with its producer named in `Surface(s)`.
      State in the doc that this is deliberately narrower than Stage 3's key and why —
      `findings-normalization.md:77` puts dedup at "Stage 3 Sonnet (semantic merge)" and `:66` orders
      "Minimize FALSE-MERGE over FALSE-SPLIT". The fix action runs no LLM stage, and the ±3-line
      bucket would merge distinct defects at `foo.ts:42` and `foo.ts:44`, dropping one remediation.
- [ ] Union `## Unparsed` by concatenation; union `## Surfaces` with each producer named; report each
      consumed file's `tier:` rather than picking one. `default-mode.md:77` declares these required
      "to keep the report honest about coverage".
- [ ] The Step 3 plan header names the consumed file **set**, not a single path (`:31` today).
- [ ] State the degenerate cases: empty set keeps today's clean STOP; a single file reduces to
      today's behavior byte-for-byte.
- [ ] Tolerate the conditional `> DEGRADED:` blockquote above `## Findings`
      (`run-everything-mode.md:163-168`).
- [ ] One sentence on the shared-directory case: a `.claude/topic-docs.yaml` `memory_dir` resolving
      outside the worktree makes one directory serve several worktrees on different branches — the
      exact-`branch:` filter on both sides is what keeps that correct.
- [ ] Version bump `plugins/review/.claude-plugin/plugin.json` (0.19.0 → 0.20.0) **and** the matching
      `plugins/review/CHANGELOG.md` entry in the same PR.
- [ ] **Sanity Check:** `scripts/check-changelog-parity.sh --check-bump origin/main` exits 0. The bare
      form exits 2 (usage), and plain `--check` asserts only the static invariant — `--check-bump` is
      the mode that proves a `## [<version>]` entry was newly added, which is what six phases cite it
      for.
- [ ] **Sanity Check:** `scripts/check-changed-skills.sh origin/main` exits 0. Editing
      `context/fix-pass-mode.md` makes `fanout` a changed skill (`check-changed-skills.sh:52-56` maps
      **any** path under `plugins/<p>/skills/<s>/` to the skill dir), so the full static contract gate
      runs; only `--require-evals` is SKILL.md-scoped.
- [ ] **Sanity Check:** `grep -c "fix-pass-record" plugins/review/skills/fanout/context/fix-pass-mode.md`
      ≥ 3 (written unconditionally, read as the ledger, and excluded from the locator).
- [ ] **Sanity Check:** two conforming fixtures with different timestamps in one branch directory —
      the plan output lists findings from **both** and names **both** files in its header.
- [ ] **Sanity Check:** after an interactive apply against fixture A, a re-run with A and a newer B
      present lists **only** B's findings — proving the ledger is written on the interactive path.
- [ ] **Sanity Check:** a fixture directory holding a record whose `branch:` differs from the current
      branch — that record excludes nothing.
- [ ] **Sanity Check:** two rows at `foo.ts:42` and `foo.ts:44` with different `Finding` text both
      survive into the plan (false-merge guard).

| File | Action | What changes |
|---|---|---|
| `plugins/review/skills/fanout/context/fix-pass-mode.md` | MODIFY | Unconditional record; merge set by consumption marking; presence-only dedup; coverage-field union; file-set plan header |
| `plugins/review/skills/fanout/context/default-mode.md` | MODIFY | Pointer to the multi-producer rule |
| `plugins/review/CHANGELOG.md` | MODIFY | Entry for the bump |
| `plugins/review/.claude-plugin/plugin.json` | MODIFY | 0.19.0 → 0.20.0 |
| `plugins/review/skills/fanout/SKILL.md` | KEEP | Audited — no SKILL.md edit, so `--require-evals` does not fire; the rest of the static gate still runs |

---

### Phase 2: Detector-findings convention — stub [TODO]

Minimal owner doc for the cross-plugin concern, landed **before** the second adopter per
`PLUGIN-PHILOSOPHY.md:471`. Deliberately thin: it fixes only what P3 must obey, leaving the rules
P3's evidence should shape to P4.

- [ ] Create `docs/conventions/detector-findings/README.md` + `CHANGELOG.md` (the majority sibling
      shape — 12 of 20 convention directories carry a CHANGELOG).
- [ ] Own the **multi-producer rule** here, not in a review-plugin context file:
      `PLUGIN-PHILOSOPHY.md:470` is "One owner doc per shared concern", and a rule binding three
      plugins cannot live inside one of them. Phase 1's file points here.
- [ ] Fix the four producer-owned fields per `design/design-resolution.md` Sketch 2: machine-computed
      `Tier`, `high`-or-omitted `Confidence` (never `low` — it ranks below absent), repo-relative
      `file:line` `Location`, cell escaping.
- [ ] Cite the findings-file schema by pointer to `default-mode.md`. Never copy it.
- [ ] Add the row to the convention registry table at `PLUGIN-PHILOSOPHY.md:474-499`.
- [ ] **Sanity Check:** `ls docs/conventions/detector-findings/README.md docs/conventions/detector-findings/CHANGELOG.md`
      exits 0.
- [ ] **Sanity Check:** `grep -c "detector-findings" docs/PLUGIN-PHILOSOPHY.md` ≥ 1.
- [ ] **Sanity Check:** `grep -c "^| Rank | Tier | Confidence" docs/conventions/detector-findings/README.md`
      returns 0 (pointer-not-copy; the schema's owner is `default-mode.md`).
- [ ] **Sanity Check:** `gh pr view --json state -q .state` on this phase's PR returns `MERGED` before
      Phase 3 opens — Phase 3's raw-URL citation does not resolve until it is.

---

### Phase 3: Pattern-C proof slice — `mutation-testing:audit` persists findings [TODO]

The integration slice. Smallest end-to-end demonstration that a **non-fanout producer reaches the
apply relay**, run against a detector that already exists rather than one invented alongside the
contract. `V1` §C.5: fanout dispatches agents only, so this skill "reaches no relay… It is an unwired
gap, and Pattern C would close it without touching fanout."

- [ ] **ADR-0004 incumbent evidence** (first work item): `path:line` proving no existing surface
      persists mutation survivors into the findings schema. Starting point: `V1` §C.5 and the
      mutation-testing read-only clause. **Inline the `path:line` evidence into the phase's issue and
      PR body** — do not cite the `.work/` file. It is gitignored, so a delegated worker, a fresh
      session, or a second machine cannot open it, and the ADR-0004 record is a durable obligation.
- [ ] Add a persist step emitting the schema verbatim from `default-mode.md:50-79`, **opt-in behind a
      flag** — the default path stays report-and-stop.
- [ ] **Amend the skill's own invariant, and the grounds its leaf name was accepted on.**
      `SKILL.md:37-38` says "the tree at the end of a run is byte-identical to the tree at the
      start", and `scripts/skill-leaf-name-registry.txt:48-49` records that same sentence as the
      grounds for `mutation-testing` holding the `audit` leaf. Restate both as byte-identical **with
      respect to tracked source**; the flag writes only into the gitignored memory tier. The verb
      table permits this already — `PLUGIN-PHILOSOPHY.md:59`: "Mutation only behind an explicit user
      override such as an autofix argument" — so this is a wording correction, not a contract break.
- [ ] The `description` currently says "report surviving mutants **read-only**" and must change.
      **Preserve every existing trigger phrase verbatim** — `scripts/check-changed-skills.sh` runs
      trigger-keyword preservation against HEAD.
- [ ] Severity is **machine-computed** from the survivor's verdict class (productive / arid /
      equivalent), never re-derived from prose. Confidence `high` only where the run cites the
      executed mutant; **omitted** otherwise.
- [ ] Escape `|` as `\|` and flatten newlines in `Finding` / `Action` — mutant diffs contain pipes.
      Relativize paths; emit `file:line`.
- [ ] Run the self-ignore guard before the first memory-tier write; never edit the consumer's root
      `.gitignore`.
- [ ] Cite the Phase 2 convention by **raw URL to `main`**, matching
      `plugins/architecture/reference/topic-docs.md:6`. A repo-relative path does not resolve for an
      installed plugin.
- [ ] Version bump + CHANGELOG for `plugins/mutation-testing`. SKILL.md **is** in this diff, so
      `evals/evals.json` must cover the new flag path and the amended invariant.
- [ ] If the persist step is scripted: `git update-index --chmod=+x` before commit (see Phase 7's
      exec-bit item — the gate is repo-wide and ungated).
- [ ] **Sanity Check:** `scripts/check-changed-skills.sh origin/main` exits 0 (evals present; trigger
      keywords preserved).
- [ ] **Sanity Check:** the emitted file's frontmatter `branch:` equals `git branch --show-current`
      exactly, and its filename matches `^[0-9]{8}T[0-9]{6}Z-[a-z0-9._-]+\.md$`.
- [ ] **Sanity Check:** with a fanout findings file also present for the same branch,
      `review:fanout fix` plans findings from **both** producers, and its header names both files —
      the Phase 1 gate proven in situ, not in a fixture.
- [ ] **Sanity Check:** `git status --porcelain` is empty after a persist run except for the
      gitignored memory-tier write — the amended invariant, asserted.

---

### Phase 4: Harden the detector-findings convention [TODO]

Written from what Phase 3 observed. Must land before Phase 7 — the second detector.

- [ ] **Rule-id → severity-tier crosswalk, with the test each mapping asserts.** This is acceptance
      criterion 2's actual contract work: `plugins/review/context/severity.md:7` defines tiers by
      **tests** ("you can name a concrete input… that produces a wrong result"), which a bare
      threshold cannot evaluate. A rule whose tier cannot be argued from the test is not admitted.
- [ ] Rule/threshold vocabulary: every finding names the rule id and the threshold that fired, so
      severity is auditable without re-reading the code.
- [ ] Bind suppression to `docs/conventions/finding-suppression/` — including its derived
      `finding_id` — rather than inventing a second suppression surface.
- [ ] Cite `REVIEW.md` as the consumer-precedence override over `severity.md:3`; the plugin file is
      the fallback baseline.
- [ ] Record the gating consequence from `V1` §C.4: a finding is auto-appliable only when
      single-file, high-confidence, and not architectural-judgment-shaped — so layering and
      abstraction detectors are **designed to inform a human**, not to feed an autonomous apply loop.
- [ ] **Decide the shared-emitter question.** Emitting a conforming file requires resolving
      `memory_dir` with its fallback ladder, computing `<branch-slug>`, running the self-ignore guard,
      relativizing paths, escaping cells, and formatting a colon-free UTC timestamp. Phase 3 is the
      second implementation and Phase 7 would be the third. Either declare a shared-source cluster in
      `scripts/cross-plugin-source-registry.txt` (drift-checked by
      `scripts/check-cross-plugin-source-drift.sh`, registered at `PLUGIN-PHILOSOPHY.md:479`), or
      record why three implementations are accepted and how drift is caught.
- [ ] **Sanity Check:** `grep -c "finding-suppression" docs/conventions/detector-findings/README.md`
      ≥ 1 and `grep -c "REVIEW.md" .../README.md` ≥ 1.
- [ ] **Sanity Check:** no crosswalk row has an empty test cell —
      `awk -F'|' '/^\| rule-/ { gsub(/ /,"",$4); if ($4=="") exit 1 }' docs/conventions/detector-findings/README.md`
      exits 0, and the count of `^| rule-` rows equals the rule count. (A bare
      `grep -c "^| .* | .* |"` also matches the header and separator rows, so it can never equal the
      rule count.)
- [ ] **Sanity Check:** `scripts/check-cross-plugin-source-drift.sh` exits 0, whichever branch of the
      shared-emitter decision was taken.

---

### Phase 5: Catalog rows for every class considered [TODO]

Closes the Brief's "rows for every class considered, including the ones deliberately not built".
Every row derives its guardrail class **through the mapping rules at `routines.md:88-146`**, never by
hand — that is the phase's whole discipline.

- [ ] **Existing-row sweep (FIRST work item).** Per candidate class, record "no row" or the existing
      row's identity. The sweep runs against `routines.md` itself, not against the gitignored research
      record — this phase is routed to a sub-agent worker, which cannot read `.work/`. Two rows
      already exist and would otherwise be duplicated:
      `routines.md:192` `dead-code-sweep` (`not-a-routine`) and `:195` `coverage-mutation-watch`
      (`not-a-routine`). A match becomes an **amendment** item with its own derivation, never a
      second row. ADR-0004's incumbent gate applies to rows here, not only to detectors.
- [ ] Present-observable admission check per row (the Brief's ADR-0008 analogy): a row is admitted
      only where its observable is anchored to text that is present. Drop any candidate anchored to
      nothing.
- [ ] Tier 1 rows with join triggers: formal-logic modeling · can't-fail test repair · layering
      enforcement (inform-human posture).
- [ ] Tier 2 rows: dead code, both postures — **amend `:192`**, window floor **30-90 days with staged
      quarantine**, never the source's one day · clone **detection + trend gating** only · stale-flag
      removal.
- [ ] Tier 3 rows recording why not: logic simplification above expression level · abstraction
      flattening · ant-only shipper · GUI crash fuzzing.
- [ ] Score each on the catalog axes (Judgment / Output / Access), then apply the mapping rules
      including the hybrid split rule and the composition rule (`C5 > C4 > C3 > C2 > C1`).
- [ ] Named-product evidence goes to the research record, **not** to `## Precedent pointers` — that
      section's own scope line routes it elsewhere, and it is non-normative.
- [ ] Nothing in any row cites 388/180 as efficacy evidence.
- [ ] **Sanity Check:** no two rows share a class token —
      `awk -F'|' '/^\| [a-z]/ {print $2}' plugins/autonomy/reference/routines.md | sort | uniq -d`
      returns empty. (A bare `grep -c "^| "` would also count the status legend at `:155-159` and the
      category divider rows, so it is not the check.)
- [ ] **Sanity Check:** `grep -n "388\|180 merged" plugins/autonomy/reference/routines.md` returns
      empty.
- [ ] **Sanity Check:** every added row's `Derived row` value is reproducible by reading only
      `routines.md:88-146` and the row's own axis cells. **Declared human gate** — a reviewer who did
      not author the rows re-derives three of them. No command self-clears it, so it is listed under
      "User-approval gates" rather than posing as mechanical.

---

### Phase 6: Q4 follow-on — reviewer-burden term, recorded as deferred [TODO]

The Brief names `/planning:plan` as this question's arbiter. Silence would leave a designated
obligation unfilled.

Ships in the **same autonomy PR as Phase 5** — one version bump, one CHANGELOG entry covering both.
Splitting them either duplicates the bump or strands one phase without its changelog line, and the
parity gate fails on both.

- [ ] In `plugins/autonomy/reference/guardrails/work-classes.md` §"Suggested default predicates",
      record a reviewer-burden term as **deferred with an explicit trigger**, not as a live term: it
      needs a denominator, and trust-path requirements 3-5 are org-scale and deferred at solo volume.
- [ ] Record the composition hazard as a standing constraint: any future tuner's signal set stays
      **disjoint** from promotion evidence — otherwise a tuner could raise the metric that promotes
      the cell that reduces scrutiny of the tuner's own output.
- [ ] Reassert that no acceptance/merge-rate metric enters the predicate, in either role.
- [ ] **Sanity Check:** `grep -c "reviewer burden\|reviewer-burden" plugins/autonomy/reference/guardrails/work-classes.md`
      ≥ 1, and the surrounding text contains both `deferred` and a named trigger.
- [ ] **Sanity Check (two assertions, both mechanical):**
      `grep -ci "never a promotion input\|no acceptance-rate\|not an efficacy signal" plugins/autonomy/reference/guardrails/work-classes.md`
      ≥ 1, **and**
      `grep -Eci "predicate .*(merge\|acceptance) rate\|(merge\|acceptance) rate .*(threshold\|>=)" plugins/autonomy/reference/guardrails/work-classes.md`
      returns 0. Phrased as "returns only lines that forbid it", zero matches satisfies it vacuously —
      which is today's state — so omitting this phase's reassertion entirely would have passed.

---

### Phase 7: Tier 1 detector #1 — can't-fail test audit [TODO]

Review: code-design

Ships the first Tier 1 detector and settles the handoff's completion criterion "at least one Tier 1
detector ships and reaches the apply relay" (that phrasing is the handoff's, not the Brief's
`### Acceptance criteria`). Chosen over the other two Tier 1 classes on trust-path requirement 1:
assertion-free and tautological tests are AST-detectable, so **membership is decidable without
judgement**. Layering enforcement is not decidable until Phase 8 lands its rules; formal-logic
modeling produces inform-human findings with no apply path.

- [ ] **ADR-0004 incumbent evidence** (first work item): `V1` §N3 — delete half airtight
      (`mutation-testing/skills/audit/SKILL.md:248`; all six `plugins/review/agents/*.md` caged
      without Edit/Write; `fix-pass-mode.md:17-18` has no test-quality class;
      `code-tidying/reference/tidyings.md:23`), and the fleet routes three times to a
      `plugins/dotnet-test/` that does not exist. **Record the boundary against `mutation-testing`
      explicitly**, since §N3's evidence is about *repair*, not detection: static AST detection of
      tests that cannot fail (cheap, no execution) versus dynamic proof that tests do not detect
      change (expensive). They are complements, not rivals. **Inline every `path:line` above into the
      issue and PR body** rather than citing the gitignored `.work/` record — this phase routes part
      of its work to a sub-agent that cannot read it.
- [ ] **Leaf verb is `audit`, joining the registered owner set** — not `scan`. Nine plugins already
      say `audit` for exactly this contract (read-only findings report). The registry's own header
      states a new plugin joining an accepted collision "has to be argued on its own merits"; the
      sanctioned response is to make that argument, not to pick a synonym that avoids it.
      `check-skill-leaf-names.sh:14-17` explicitly disclaims naming authority, so it is a collision
      tripwire, never the basis for the verb.
- [ ] Add `testing` to line 53 of `scripts/skill-leaf-name-registry.txt` with the joining grounds
      recorded above the entry, in the style of the existing entries.
- [ ] New skill at `plugins/testing/skills/audit/` — **no new plugin** (ADR 0005).
- [ ] Detection is a **script**, not an agent: the judgment is mechanical
      (`PLUGIN-PHILOSOPHY.md:664-666`), and the named-agent bar (`:718-720`) is not met.
- [ ] Rules v1, each with an id and a threshold: zero-assertion test body · assertion whose expected
      value is recomputed by the code under test · fully-mocked test with no assertion on a real
      collaborator.
- [ ] **A fourth rule was dropped**: "a skip that vacates the only discriminating assertion of a case
      group" is verbatim what `scripts/check-discriminating-test-skips.sh:1-5` already gates over
      `plugins/**/*.test.sh` and `.claude/hooks/*.test.sh`. Record the incumbent; scope any revival
      to ecosystems that bash-only script does not cover.
- [ ] Remediation posture is **repair, not pruning** — the finding's `Action` proposes an assertion,
      never a deletion. The repair *queue* is out of scope this cycle (see `### Goal`).
- [ ] **Ship a `--check` exit-code mode** alongside the report. This is what makes trust-path
      requirement 2 — "machine-checkable gate that fails closed" — real rather than nominal, and
      acceptance criterion 3 turns on it. The report skill stays `audit`; the gate is the mode, per
      the verb doctrine reserving `check` for pass/fail.
- [ ] Emit through the Phase 4 convention, cited by raw URL to `main`; reach the relay by Pattern C —
      no fanout edits.
- [ ] Frontmatter obligations: `metadata.workflow-stage` (absent is a hard error),
      `metadata.summary` ≤100 codepoints, `description` + `when_to_use` ≤1536 chars, SKILL.md <500
      lines.
- [ ] `evals/evals.json` required; every file under `evals/fixtures/` referenced by a grader.
- [ ] Co-located `*.test.sh`; no GNU-only constructs in changed `.sh`.
- [ ] **exec-bit:** `git update-index --chmod=+x` for every new shebang file before commit. The gate
      "flags every tracked shebang file recorded 100644" and scans the whole repo, ungated by the
      docs-only allowlist (`scripts/docs-only-paths.txt:38-42`); on Windows `core.filemode` is
      conventionally false, so `git add` records 100644 and CI fails with a diagnostic that
      contradicts the local file mode.
- [ ] **Amend** the `can't-fail test repair` row from Phase 5 to reflect shipped detection. **Do not
      flip it to `v1`**: `routines.md:156` defines `v1` as "proven manual pattern", the Brief's
      resolved Q2 keeps that trigger our-own-proven, and under `:92-94` a script detector derives
      `not-a-routine` for its detection portion while the repair judgment — the actual routine — is
      not built. No `reference/routines/` leaf either; leaves are `v1`-only (`:210`).
- [ ] Regenerate `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` — never hand-edit.
- [ ] Version bump + CHANGELOG for **both** `plugins/testing` and `plugins/autonomy` in this PR.
- [ ] **Sanity Check:** `scripts/check-skill-leaf-names.sh --check` exits 0.
- [ ] **Sanity Check:** `scripts/check-changed-skills.sh origin/main`, `scripts/check-orphaned-fixtures.sh`,
      `scripts/check-shell-portability.sh` all exit 0.
- [ ] **Sanity Check:** `! git ls-files -s plugins/testing/skills/audit/ | grep -q '^100644.*\.sh$'`.
      Written as `grep -c … returns 0` it inverts — `grep -c` exits 1 on a zero count, so the success
      case fails the command and a mis-staged `.sh` passes.
- [ ] **Sanity Check:** `wc -l plugins/testing/skills/audit/SKILL.md` < 500.
- [ ] **Sanity Check:** `--check` against a fixture with one assertion-free test exits non-zero;
      against the negative fixture it exits 0.
- [ ] **Sanity Check:** on a fixture containing one assertion-free test, the emitted findings file is
      consumed by `review:fanout fix`, whose plan lists that finding — the criterion's actual
      settlement, not a proxy.
- [ ] **Sanity Check:** `! grep -q "^| can.t-fail-test-repair .*| v1 |" plugins/autonomy/reference/routines.md`.

---

### Phase 8: Per-repo capability detection — PROMOTE TO SUB-TOPIC [TODO]

Tier 0 item 3, and the clause the Original goal names verbatim ("configurable per repo/product/app
based on the repo itself, any external context provided from CLAUDE.md, AGENTS.md, repo files, MCP
servers, CLI tools").

**Promotion trigger fires on three counts**: its own exploration need (what each ecosystem's
detection signal actually is), an independent commit boundary, and a >300 LOC estimate. Planning it
inline would make this PLAN.md unscannable and deny the work its own clean-context boundary.
Independent of Phases 1-7 — it can run on any track.

- [ ] Create `docs/topics/routine-capability-detection/` and run `/planning:interview` then
      `/planning:plan` against it.
- [ ] **This creates a second contract slice, red-lined by the same gate as this one** — it matches no
      grandfather line and cannot be exempted. Phase 10 does not absorb it: the promoted topic owes
      its **own** graduation-and-prune before its own merge, which is the convention's ordinary
      per-slice lifecycle rather than a special case. Its PLAN must carry a terminal phase of the same
      shape.
- [ ] Inputs it inherits, not re-derives: the catalog's axes and mapping rules (`routines.md:88-146`);
      the three-layer config cascade (`docs/conventions/config-cascade/`); the deterministic-gate
      preference (`PLUGIN-PHILOSOPHY.md:664-666`).
- [ ] **Sanity Check:** `ls docs/topics/routine-capability-detection/PLAN.md` exits 0, and
      `awk '/^## Brief/{f=1;next} f&&NF{found=1;exit} END{exit !found}' docs/topics/routine-capability-detection/PLAN.md`
      exits 0 (the `## Brief` carries content).
- [ ] **Sanity Check:** that PLAN carries a terminal graduate-and-prune phase —
      `grep -qi "check-contract-slice-prune" docs/topics/routine-capability-detection/PLAN.md`.

---

### Phase 9: Repo-scope plugin declaration — BLOCKED [TODO]

Tier 0 item 4. Blocked on spike
[#2660](https://github.com/melodic-software/claude-code-plugins/issues/2660) (`needs-human`): two
official pages contradict each other, workspace trust for a cloud clone is undocumented, and an
untrusted declaration is ignored **silently**.

- [ ] **No work item here proceeds unattended.** The probe mutates a GitHub account and metered
      usage, and browser selection is forbidden to the agent.
- [ ] **Meanwhile, the documented fallback is the planned path**, not a contingency: components
      committed directly to `.claude/skills|agents|commands` are part of the clone and need no
      marketplace fetch, trust step, or credentials. Phases 1-8 and 10 are unaffected either way.
- [ ] **Sanity Check:** `gh issue view 2660 --json state,labels` shows the spike still open, or its
      resolution comment is quoted into this phase before any work item starts.

---

### Phase 10: Graduate the durable outcomes and prune the contract slice [TODO]

**This gate fails right now, on this branch, against `origin/main`.** Executed 2026-08-15:

```text
$ bash scripts/check-contract-slice-prune.sh --check-diff origin/main
Contract-slice prune gate FAILED — this change set leaves 2 path(s) under docs/topics/:
  A  docs/topics/boris-routines-adoption/PLAN.md
  A  docs/topics/boris-routines-adoption/design/design-resolution.md
exit 1
```

`docs/topics/<slug>/` is **Contract tier** — `docs/conventions/topic-docs/README.md:43`, "Committed
**on the task branch only**; pruned before merge". `scripts/contract-slice-baseline.txt` grandfathers
eleven slugs that predate the gate and says in its own header that a new slice "matches no line and
is red-lined rather than grandfathered… adding a line here in the same PR that adds the slice exempts
nothing", because the baseline is read from the **base** revision.

Consequences the earlier drafts missed:

- **The PR for this branch cannot merge as it stands.** That is the handoff's next action after
  planning, so this phase is not a tail item — it gates the very first merge.
- **Phase 8 creates a second slice** (`docs/topics/routine-capability-detection/`) that is red-lined
  the same way and owes its own graduation.
- **`#### Mechanical work`'s per-phase `[TODO]`→`[DOING]`→`[DONE]` tag advancement puts the slice in
  every phase PR's diff**, so under a phase-per-PR shape the gate fires every time — which is what
  makes the branch-shape decision below structural rather than cosmetic.

- [x] **Graduate the coexistence decision to an ADR.** Done 2026-08-15:
      [ADR 0010](../../adr/0010-merge-findings-across-producers-and-mark-consumption-explicitly.md).
      It passes all three admission tests: hard to reverse (it changes a contract `default-mode.md:48`
      calls stable and other producers consume), surprising without context (a future reader asks why
      the consumer merges rather than takes the newest), and the result of a real trade-off (three
      named options for coexistence, two named keys for dedup, each chosen for stated reasons). It is
      written **before** Phase 1 rather than after, because under shape (a) it is what carries the
      decision once this slice is pruned — Phase 1 implements the ADR rather than deciding it.
- [ ] **Graduate the ADR-0004 incumbent evidence out of the gitignored tree.** `git check-ignore -v
      .work/` returns `.work/.gitignore:1:*`. Phases 3, 5, and 7 each open by citing
      `V1-coverage-negatives.md` §C.5 / §N3, and two of those phases route to sub-agent workers that
      **cannot open the file**; a fresh session or second machine cannot either. The ADR-0004 record
      is a durable obligation, so the load-bearing `path:line` evidence is inlined into the phase
      bodies and the graduated ADR, rather than pointing at a checkout-local artifact.
- [ ] File the remaining phases as tracker issues carrying their own inlined incumbent evidence, per
      the handoff's decomposition action.
- [ ] **Name what carries the plan after the slice is gone.** Under shape (a) the durable carriers are
      exactly three: the graduated ADR (the coexistence decision and its rejected alternatives), the
      per-phase tracker issues (each phase's work items, sanity checks, and inlined `path:line`
      evidence), and this PR's body (the whole plan, for provenance). Nothing load-bearing may be left
      pointing only at `docs/topics/boris-routines-adoption/` or at `.work/` — both are unreachable
      after merge, the first because it is deleted and the second because it was never pushed.
- [ ] Paste the approved PLAN.md into the PR description inside a `<details>` block (PR bodies cap
      near 64 KB — paste the contract, reference the rest).
- [ ] A final commit deletes `docs/topics/boris-routines-adoption/`. The deletion itself is what
      passes the gate.
- [ ] **Sanity Check:** `bash scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 0.
- [ ] **Sanity Check:** `bash scripts/check-contract-slice-prune.sh --check` exits 0 — the stale guard
      fails on a baseline entry whose slice no longer exists, so no orphan line is left behind.
- [ ] **Sanity Check:** `ls docs/topics/boris-routines-adoption/ 2>/dev/null` returns non-zero, and the
      PR body contains the pasted plan (`gh pr view --json body -q .body | grep -c "## Plan"` ≥ 1).

---

### Blast radius

**HIGH.** Four triggers matched: a **new convention** (`detector-findings`) that constrains all
future detectors; a **breaking change to a documented stable contract** (`default-mode.md:48` titles
the findings-file shape "stable contract — the fix action consumes it") whose consumers are not all
inside `plugins/review/`; **nine phases**, several touching behavior no doc describes; and a
cross-cutting surface — the findings pipeline is what every review in the fleet flows through.
Reversibility is good (git revert works, no published API), and the repo's CI gates are dense, which
is what keeps this HIGH rather than CRITICAL.

### Stress-test summary

A fresh-context adversarial pass ran against the `ecdd288c` draft with the rationale withheld. It
returned 2 CRITICAL, 8 HIGH, 11 MEDIUM, 4 LOW. Every finding acted on below was **re-verified against
the file before the plan was changed** — subagent output is synthesis, not ground truth.

The two CRITICALs both attacked the same phase and both held:

1. **The staleness bound could not exist on the path the plan runs.** `fix-pass-mode.md:76` writes
   the `fix-pass-record` only under `--yes` in a non-interactive session — "Interactive and
   headless-stop paths write no record". The Brief's own solo shape is interactive, so the bound was
   a no-op there and the merge set would have grown without limit, re-injecting findings that
   `:95`'s required post-fix re-review had already resolved. **The draft would have regressed a
   documented loop while claiming to close a correctness gate.** Fixed by making the record
   unconditional — a consumption ledger — and bounding by `source-findings:` rather than timestamp.
2. **The dedup key was not mechanically available.** `findings-normalization.md:77` places dedup at
   "Stage 3 Sonnet (semantic merge)" and `:66` orders "Minimize FALSE-MERGE over FALSE-SPLIT — a
   false merge silently drops a real issue". The fix action runs no LLM stage. Fixed by specifying
   presence-only matching and stating why it is deliberately narrower.

A second fresh-context pass then reviewed the revision on the axes the first did not cover — Brief
scope-item mapping, sanity-check executability, and convention reinvention. It returned 1 Critical, 7
Important, 2 Suggestion, and its Critical was **executed, not argued**:
`scripts/check-contract-slice-prune.sh --check-diff origin/main` exits 1 on this branch today. That
produced Phase 10 and the branch-shape question in `### Open questions`. Its other findings, each
re-verified, repaired five sanity checks that could not pass as written — a bare
`check-changelog-parity.sh` exits 2 on usage; a `grep -c … returns 0` check inverts its own exit
code; a forbidden-metric grep passed vacuously on zero matches; two checks had no command at all —
widened acceptance criterion 4's sweep from two files to the whole change set, bound the
routine-delivery open question to `liveness-assertion`'s two-limb Core contract instead of deferring
it by scope, and surfaced that the ADR-0004 evidence sits in a gitignored tree two delegated phases
cannot read. Two citation drifts were corrected (12 not 13 convention CHANGELOGs; registry `:48-49`
not `:51-52`).

Also verified and fixed: `PLUGIN-PHILOSOPHY.md:471` is a **deadline**, not a licence to author the
owner doc late, and the pilot phase is itself the second adopter — hence the stub-then-harden split.
`AGENTS.md` is 28 lines at HEAD and no longer carries the exec-bit or stdin guidance the draft cited
(deleted by `e22190ed`), so the grounding table was re-pointed and an upstream follow-up recorded.
`routines.md:192,195` already carry `dead-code-sweep` and `coverage-mutation-watch`, so the catalog
phase gained an existing-row sweep as its first work item. Two scope reductions the draft had
absorbed silently — Tier 1 three-to-one, and detection-rather-than-repair — are now stated in
`### Goal` and routed to the approval gates.

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Bound the merge set by the newest `fix-pass-record` timestamp | The record is written only on the headless `--yes` path, so the bound is a no-op on the interactive path the Brief's solo shape uses |
| Reuse Stage 3's ±3-line dedup key in the fix action | It is a Sonnet semantic stage the consumer does not have; the bucket would merge distinct defects and silently drop a remediation |
| One-writer-per-directory + a separate merge step | The merge component has no owner today; extending the existing consumer adds no new surface |
| Detector appends into fanout's file | Requires a write-ordering and locking convention that does not exist |
| Author the owner doc after the first adopter | `PLUGIN-PHILOSOPHY.md:471` sets a deadline, not a permission; the stub-then-harden split gets the pilot's evidence without breaking it |
| Build a Tier 1 detector before the Pattern-C pilot | Forfeits the integration slice — the contract would be authored against a predicted adopter instead of a real one |
| Formal-logic modeling as the first detector | Strongest external evidence, but its findings are inform-human with no apply path, so it cannot settle the relay criterion |
| Layering enforcement first | Membership is not decidable until Phase 8 ships per-repo layering rules |
| Name the new skill `testing:scan` | Avoids the registry argument instead of making it; nine plugins say `audit` for this contract, and a tenth saying `scan` fragments fleet vocabulary |
| Flip the test-repair row to `v1` on shipped detection | `v1` means proven manual pattern; a `DET` detector derives `not-a-routine` and the repair judgment is unbuilt |
| Reach the relay by adding a fanout leaf | Four hand edits, none auto-discovered; a conforming file needs zero |
| Add a live reviewer-burden term to the promotion predicate now | Unmeasurable at solo volume — a term with no denominator is a metric in name only |

### Test strategy

The verification surfaces are shell gates, evals, and fixture-driven probes — not a unit-test suite.
Test-first applies as fixture-first: the failing fixture exists before the change.

- **Phase 1 (contract change, regression-shaped):** the named regression is *two conforming files in
  one branch directory, both surviving into the plan*. It fails against today's locator and passes
  after. Three further fixtures pin the properties the adversarial pass found missing: a single-file
  case (no behavior change), an interactive-apply case (the ledger is written), and a
  distinct-defects-within-3-lines case (no false merge).
- **Phase 3 (integration slice):** an end-to-end probe, not a unit assertion — emit from
  mutation-testing, consume via `review:fanout fix`, assert the plan names the mutant finding and
  both files. The prior session's hand-written conforming file is the fixture shape.
- **Phase 7 (new skill):** `evals/evals.json` is CI-required; graders assert rule id + threshold per
  fixture. Positive fixtures per rule, plus a negative fixture (a genuinely discriminating test) that
  must produce **zero** findings — the false-positive guard decides whether anyone keeps the detector
  on. `--check` exit codes are asserted in the co-located `*.test.sh`.
- **Phases 2, 4, 5, 6 (doc/contract):** the grep-shaped sanity checks above, plus a fresh-context
  reviewer re-deriving three Phase 5 rows from the mapping rules alone.
- **Every phase, three change-set-wide gates:** `scripts/check-changelog-parity.sh --check-bump origin/main`;
  `scripts/check-changed-skills.sh origin/main`; and
  `scripts/check-contract-slice-prune.sh --check-diff origin/main` — the last **fails today** against
  this very branch (see Phase 10).
- **Acceptance criterion 4 is change-set-wide, not per-file.** The criterion says "anywhere", so the
  forbidden-metric sweep runs over the whole diff every phase —
  `git diff origin/main | grep -Ein "merge rate|merge-rate|acceptance rate"` yields only forbidding
  lines. Scoping it to `routines.md` and `work-classes.md`, as two phases originally did, left P3, P4,
  and P7 uncovered, and each of those ships or governs a severity surface.
- Only `docs/topics/` is docs-only-allowlisted, so every phase touching `plugins/**` or
  `docs/conventions/` runs the full suite; exec-bit and ShellCheck run repo-wide regardless.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| The merge re-surfaces findings already fixed by hand | **High on the interactive path pre-fix** | High | Change 1 makes the ledger unconditional; the interactive-apply fixture is the proof |
| Presence-only dedup false-splits, producing duplicate rows | Med | Low | Deliberate: a false split adds noise, a false merge drops a remediation. Direction chosen and stated |
| Phase 3's flag alters `audit`'s stated invariant | High | Med | Invariant and registry grounds amended in the same PR; `git status --porcelain` asserted clean |
| Phase 3 breaks trigger-keyword preservation on `description` | Med | High | Existing trigger phrases preserved verbatim; `check-changed-skills.sh origin/main` is the gate |
| Phase 7 exec-bit failure on Windows | **High** | Med | `git update-index --chmod=+x` item plus a `git ls-files -s` sanity check |
| Phase 7 detector emits false positives and gets ignored | High | High | Negative fixture must return zero findings; rules carry ids so a noisy rule is disabled individually |
| A Phase 5 row duplicates an existing one | **High pre-fix** | High | Existing-row sweep is the first work item; duplicate-class-token check |
| A Phase 5 guardrail class is assigned by hand | Med | High | Reviewer re-derives three rows from `routines.md:88-146` alone |
| Detector output never reaches a human in a cloud routine | Med | Med | Named in `### Open questions` with a trigger; detectors are local-only this cycle |
| #2660 resolves against repo-scope declaration | Med | Low | Fallback is already the planned path |

### Execution shape

**Recommended: sequential** — P1 → P2 → P3 → P4 → P7, with P5 → P6 (one autonomy PR) landing before
P7's row amendment. P8 runs on its own topic track. P9 is externally blocked.

**File-overlap matrix**

| Phase | Files | Overlaps with |
|---|---|---|
| P1 | `plugins/review/**` | none |
| P2 | `docs/conventions/detector-findings/**`, `docs/PLUGIN-PHILOSOPHY.md` | P4 |
| P3 | `plugins/mutation-testing/**`, `scripts/skill-leaf-name-registry.txt` | P7 |
| P4 | `docs/conventions/detector-findings/**` | P2 |
| P5 | `plugins/autonomy/reference/routines.md` + manifest/CHANGELOG | P6, P7 |
| P6 | `plugins/autonomy/reference/guardrails/work-classes.md` + manifest/CHANGELOG | P5, P7 |
| P7 | `plugins/testing/**`, `plugins/autonomy/reference/routines.md` + manifest/CHANGELOG, `scripts/skill-leaf-name-registry.txt` | P3, P5, P6 |

**Why not parallel.** P1 → P2 → P3 → P4 → P7 is a hard chain, and P2 additionally must **merge to
`main`** before P3 — a barrier no amount of concurrency removes. The only file-disjoint pair worth
running together is P1 alongside P5+P6, and both are documentation-shaped and short. Against that,
P1 is the correctness gate every later phase assumes; running it visibly first, alone, is worth more
than the wall-clock. **Parallel option if wanted:** Wave A = {P1} ∥ {P5+P6}, two agents, ALLOWED =
`plugins/review/**` and `plugins/autonomy/**` respectively; FORBIDDEN for both = PLAN.md, each
other's tree, and all staging/commit operations. Fallback on a fence violation: abort that agent,
finish sequentially.

**Per-phase routing**

| Phase | Surface | Basis |
|---|---|---|
| P1 | main-session | Contract judgment on a consumed file format; the degenerate and adversarial cases need care |
| P2 | main-session | Owner-doc authoring; decides where a cross-plugin rule lives |
| P3 | main-session | Integration slice; its sanity checks are empirical probes, not file assertions |
| P4 | main-session | Crosswalk design turns on a severity test a threshold cannot evaluate |
| P5 | sub-agent worker | Mechanical derivation through fixed mapping rules over a bounded row set, after the sweep |
| P6 | main-session | Small, judgment-bearing, and it discharges a named arbiter obligation |
| P7 | main-session + sub-agent for fixtures/evals | Skill authoring is judgment-heavy; fixture generation is mechanical volume |
| P8 | own sub-topic | Promoted — own exploration need, own commit boundary, >300 LOC |
| P9 | user-attended | Browser selection, account mutation, metered usage |
| P10 | main-session | Graduation decides what becomes durable; the branch-shape question is the user's |

### Open questions

- ~~**BLOCKING: what branch shape carries a ten-phase plan past the contract-slice prune gate?**~~
  **RESOLVED 2026-08-15 — shape (a).** Graduate early, prune at this branch's merge, then run phases
  as independent PRs. This PR graduates the coexistence ADR
  ([0010](../../adr/0010-merge-findings-across-producers-and-mark-consumption-explicitly.md)) plus
  the inlined incumbent evidence, files the remaining phases as tracker issues, pastes the plan into
  its own body, and prunes the slice. Later phases carry their contract in their issue and PR bodies,
  so no slice exists to red-line. The rejected alternative was one long-lived branch with all ten
  phases as commits and a single terminal prune: it keeps PLAN.md on disk throughout and needs no
  issue decomposition, but yields one very large PR and defers every gate to the end — which is how
  a silent-shadowing bug survived to draft stage here.
- **Detector output has no delivery path in a cloud routine — and this is a conformance question, not
  a scoping one.** `.work/` is gitignored (`*`), a cloud run's containment is the `claude/`-branch
  push rule, and "green status ≠ success", so a scheduled routine running any detector produces
  output nobody reads. `docs/conventions/liveness-assertion/README.md:56-65` requires every advisory
  or gate surface to satisfy **at least one** of its two limbs — fail loud, or publish to an
  agent-readable channel — and "deferred by scope" is neither. Each detector must therefore **name
  the limb it satisfies**: Phase 7's `--check` mode is limb 1 (exits non-zero, blocks), which is the
  cleanest answer and another reason that mode is not optional. A detector shipping report-only with
  no reachable channel is non-conforming, whatever the cycle boundary says.
- Whether Phase 3's persist flag should write when the run finds **zero** survivors. An empty
  conforming file is honest but adds a row-less file to the merge set. Settle inside Phase 3.
- Whether `docs/conventions/detector-findings/` is the right convention name. Named at Phase 2
  authoring time; `/naming:name-it-better` if contested.
- Live daily run-cap numbers remain USER-RESERVED. Nothing in Phases 1-8 depends on them.

### Handoff to implementation

#### User-approval gates

- **The branch shape, (a) or (b) in `### Open questions`.** It is hard to reverse once phases start
  landing, and it decides whether the plan survives on disk or in issue bodies. Nothing should be
  implemented before it is answered.
- **Phase 5's row re-derivation** — a reviewer who did not author the rows re-derives three of them
  from `routines.md:88-146` alone. Declared human gate; no command clears it.
- **Phase 9's spike state** — quoting #2660's resolution into the phase is a human read, not a check.
- **The two scope reductions in `### Goal`** — Tier 1 three-to-one, and detection-rather-than-repair.
  Both drop Brief-listed scope; neither is a mechanical outcome.
- **The per-unit close-out deviation** — batching rows and shipping stage-at-a-time restructures a
  discipline the locked Brief states.
- **Phase 3's flag surface and the amended `audit` invariant** — a user-facing flag plus a change to
  the grounds a registered leaf name was accepted on.
- **Phase 7's registry join** — adding `testing` to the `audit` owner set is the argument the registry
  asks for; it wants a human behind it.
- **Phase 8 promotion** — creating a second topic directory is a scope shape change.
- **Any Phase 5 row that fails the present-observable admission check** — dropping a class the Brief
  listed is a scope cut.
- **Phase 9** — every work item. Nothing runs unattended.

#### Execution shape (`[EXEC-SHAPE]`)

Sequential P1 → P2 → P3 → P4 → P7; P5 → P6 in one autonomy PR before P7's amendment; P8 promoted; P9
blocked. Routing table and scope fences above. Phase boundaries are PR boundaries **except** P5+P6,
which share one autonomy version bump and one CHANGELOG entry. P2 is a hard merge barrier: its
convention must be on `main` before P3 can cite it.

#### Mechanical work

- Commit per phase; surgical `git add` of named paths only — `git add -A` and `git add .` are
  forbidden (`AGENTS.md`). Commit messages via stdin heredoc, never multi-line `-m` (a PreToolUse
  hook blocks it).
- `git update-index --chmod=+x` for every new shebang file before its first commit.
- PLAN.md phase tags advance `[TODO]` → `[DOING]` → `[DONE]` main-session only; workers report back.
- Each `plugins/**` phase verifies its own version bump and CHANGELOG entry **before** opening its
  PR — the parity gate exempts no plugin.
- PR bodies need a native closing keyword (or the literal `No linked issue`) **and** a non-empty
  `## Related`; the linkage check strips HTML comments, so an unedited template does not pass.
- Sequential fallback if a parallel run is chosen and fails: abort the offending agent and finish
  that phase sequentially; the other agent continues.

#### Follow-ups outside this plan

- **Re-land the deleted `AGENTS.md` guidance upstream in `melodic-software/standards`.** The exec-bit
  and Windows-filemode content was removed by `e22190ed`'s managed sync; a local patch is deleted by
  the next sync, so the fix belongs in the upstream owner.

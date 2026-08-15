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

### Goal

**What**: ship the Tier 0 substrate, then the first Tier 1 detector, then catalog rows for every
class considered — sequenced so the silent-shadowing correctness gate closes before any second
findings producer exists.

**Why**: the Brief settles *what*; nothing in it reaches a repository until a detector emits a
conforming findings file and the apply relay consumes it without dropping the other producer's
findings.

### Standards grounding

No standards index exists in this repo (`.claude/` holds `settings.json`, `source-control.md`,
`hooks/` only). Surfaces inferred from repo structure; nothing was written to persist an index.

| Surface | Sections cited | Layer provenance |
|---|---|---|
| `docs/adr/` | 0004 incumbent-first gate · 0005 extend-the-catalog · 0008 anchored observable | team |
| `docs/PLUGIN-PHILOSOPHY.md` | Naming (`:59-60`) · deterministic-gate preference (`:664-666`) · named-agent bar (`:718-720`) · owner-doc-before-second-adopter (`:471`) | team |
| `docs/conventions/liveness-assertion/` | `README.md:58` green-with-hidden-findings class | team |
| `docs/conventions/finding-suppression/` | opt-in obligations + derived `finding_id` | team |
| `docs/conventions/topic-docs/` | contract slice vs memory slice, prune-with-pointer | team |
| `AGENTS.md` | no `git add -A` · commit message via stdin · exec-bit=failure | team |
| `REVIEW.md` | org severity vocabulary overriding `plugins/review/context/severity.md` | team |
| `~/.claude/CLAUDE.md` | pointer-not-copy · producer ≠ critic · no suppressed diagnostics | personal (user-global) |

### Phase dependency spine

```text
P1 coexistence ──> P2 Pattern-C proof ──> P3 detector owner doc ──> P5 useless-test detector
                                                                          ^
P6 catalog rows ──> P7 predicate term ─────────────────────────────────────┘ (row flip to v1)

P4 capability detection ── promoted to its own topic; independent track
P8 repo-scope plugin declaration ── blocked on spike #2660
```

`P1 → P2` is not merely "early": fanout is producer #1, so **the first detector of any kind makes
producer #2**, and `fix-pass-mode.md:3` consumes exactly one file. `P3` sits *after* `P2` because
`PLUGIN-PHILOSOPHY.md:471` puts the owner doc before the **second** adopter, not the first — so the
pilot's evidence informs the contract rather than the contract being guessed ahead of it.

---

### Phase 1: Multi-producer findings coexistence [TODO]

Review: architecture

Closes Tier 0 item 1 and acceptance criterion 1. Shape resolved in `design/design-resolution.md`
Sketch 1.

- [ ] **Pre-flight consumer check** (FIRST work item — this migrates a consumed file contract):
      `grep -rn "review-findings" --include='*.md' --include='*.sh' --include='*.py' .` and
      `grep -rn "fix-pass-record" -r .` — enumerate every parse path of the findings frontmatter and
      of the findings table, inside and outside `plugins/review/`. Record each parse site in the
      phase notes before editing.
- [ ] Extend the Step 1 locator in `context/fix-pass-mode.md` from newest-one to the merge set:
      all `type: review-findings` files for the exact current branch whose filename timestamp
      exceeds the newest `type: fix-pass-record` timestamp.
- [ ] Union the parsed rows by the existing Stage-3 dedup key (normalized path + ±3-line bucket);
      line-less rows bucket by path + category + gist, per `findings-normalization.md:66`.
- [ ] Merge `## Unparsed` by concatenation — never drop, per the section's own contract.
- [ ] State the degenerate cases explicitly in the doc: empty set keeps today's clean STOP; a single
      file reduces to today's behavior byte-for-byte.
- [ ] Tolerate the conditional `> DEGRADED:` blockquote above `## Findings`
      (`run-everything-mode.md:163-168`).
- [ ] Record the multi-producer rule in `context/default-mode.md` as a pointer to the fix-action
      section — one authoritative statement, not two.
- [ ] Version bump `plugins/review/.claude-plugin/plugin.json` (0.19.0 → 0.20.0) **and** the matching
      `plugins/review/CHANGELOG.md` entry in the same PR.
- [ ] **Sanity Check:** `scripts/check-changelog-parity.sh` exits 0.
- [ ] **Sanity Check:** `grep -n "the newest" plugins/review/skills/fanout/context/fix-pass-mode.md`
      returns no line describing single-file consumption of `review-findings`.
- [ ] **Sanity Check:** `grep -c "fix-pass-record" plugins/review/skills/fanout/context/fix-pass-mode.md`
      ≥ 2 (the marker is now both written and read).
- [ ] **Sanity Check:** two hand-written conforming fixtures with different timestamps in one
      branch directory — the plan output lists findings from **both**; deleting the newer one and
      re-running lists the older one's findings unchanged.

| File | Action | What changes |
|---|---|---|
| `plugins/review/skills/fanout/context/fix-pass-mode.md` | MODIFY | Locator → merge set; dedup + Unparsed union; staleness bound |
| `plugins/review/skills/fanout/context/default-mode.md` | MODIFY | Pointer to the multi-producer rule |
| `plugins/review/CHANGELOG.md` | MODIFY | Entry for the bump |
| `plugins/review/.claude-plugin/plugin.json` | MODIFY | 0.19.0 → 0.20.0 |
| `plugins/review/skills/fanout/SKILL.md` | KEEP | Audited — no SKILL.md edit, so `REQUIRE_EVALS` does not fire |

---

### Phase 2: Pattern-C proof slice — `mutation-testing:audit` persists findings [TODO]

The integration slice. Smallest end-to-end demonstration that a **non-fanout producer reaches the
apply relay**, run against a detector that already exists rather than one being invented alongside
the contract. `V1` §C.5: fanout dispatches agents only, so this skill "reaches no relay… It is an
unwired gap, and Pattern C would close it without touching fanout."

- [ ] **ADR-0004 incumbent evidence** (first work item): record `path:line` proving no existing
      surface persists mutation survivors into the findings schema. Starting point:
      `V1-coverage-negatives.md` §C.5 and the mutation-testing SKILL.md read-only clause.
- [ ] Add a persist step to `plugins/mutation-testing/skills/audit/` emitting the schema verbatim
      from `default-mode.md:50-79`: frontmatter `type: review-findings` / `date` / `branch` / `tier`,
      `## Findings`, `## By dimension`, `## Unparsed`, `## Surfaces`.
- [ ] Severity is **machine-computed** from the survivor's own verdict class (productive / arid /
      equivalent), never re-derived from prose. Confidence `high` only where the run cites the
      executed mutant; **omitted** otherwise — never `low` (`findings-normalization.md:62,72`:
      absent outranks `low`).
- [ ] Escape `|` as `\|` and flatten newlines in `Finding` / `Action` — mutant diffs contain pipes.
- [ ] Relativize paths before writing; emit `file:line` so rows dedup at ±3 lines rather than
      false-merging on gist.
- [ ] Run the self-ignore guard before the first memory-tier write; never edit the consumer's root
      `.gitignore`.
- [ ] Persist is **opt-in behind a flag** — `audit` keeps its read-only verb contract by default.
- [ ] Version bump + CHANGELOG for `plugins/mutation-testing` in the same PR. SKILL.md **is** in this
      diff, so `evals/evals.json` must cover the new flag path.
- [ ] **Sanity Check:** run the flag on a fixture repo; the emitted file's frontmatter `branch:`
      equals `git branch --show-current` exactly, and its filename matches
      `^[0-9]{8}T[0-9]{6}Z-[a-z0-9._-]+\.md$`.
- [ ] **Sanity Check:** with a fanout findings file also present for the same branch,
      `review:fanout fix` plans findings from **both** producers — the Phase 1 gate proven in situ,
      not in a fixture.
- [ ] **Sanity Check:** `scripts/check-changed-skills.sh` exits 0 (evals present for the changed
      SKILL.md).

---

### Phase 3: Detector contract owner doc [TODO]

Closes Tier 0 item 2 and acceptance criterion 2. Written **after** Phase 2 so its rules are recorded
from an adopter, not predicted. Must land before Phase 5 — the second adopter.

- [ ] New convention at `docs/conventions/detector-findings/` (`README.md` + `CHANGELOG.md`, matching
      the shape of every sibling convention).
- [ ] Govern the four producer-owned fields per `design/design-resolution.md` Sketch 2: machine-computed
      `Tier`, `high`-or-omitted `Confidence`, repo-relative `file:line` `Location`, cell escaping.
- [ ] Define the rule/threshold vocabulary: every finding names the rule id and the threshold that
      fired, so severity is auditable without re-reading the code.
- [ ] Bind suppression to the existing `docs/conventions/finding-suppression/` — including its
      derived `finding_id` — rather than inventing a second suppression surface.
- [ ] Cite the multi-producer rule from Phase 1 by pointer. Do not restate it.
- [ ] Cite `REVIEW.md` as the consumer-precedence override over
      `plugins/review/context/severity.md:3`; the plugin file is the fallback baseline.
- [ ] Record the gating consequence from `V1` §C.4 verbatim in effect: a finding is auto-appliable
      only when single-file, high-confidence, and not architectural-judgment-shaped — so
      layering and abstraction detectors are **designed to inform a human**, not to feed an
      autonomous apply loop.
- [ ] **Sanity Check:** `ls docs/conventions/detector-findings/README.md docs/conventions/detector-findings/CHANGELOG.md`
      exits 0.
- [ ] **Sanity Check:** `grep -c "finding-suppression" docs/conventions/detector-findings/README.md`
      ≥ 1 and `grep -c "REVIEW.md" docs/conventions/detector-findings/README.md` ≥ 1.
- [ ] **Sanity Check:** the doc contains no copy of the findings-file schema —
      `grep -c "^| Rank | Tier | Confidence" docs/conventions/detector-findings/README.md` returns 0
      (pointer-not-copy; the schema's owner is `default-mode.md`).

---

### Phase 4: Per-repo capability detection — PROMOTE TO SUB-TOPIC [TODO]

Tier 0 item 3, and the clause the Original goal names verbatim ("configurable per repo/product/app
based on the repo itself, any external context provided from CLAUDE.md, AGENTS.md, repo files, MCP
servers, CLI tools").

**Promotion trigger fires on three counts**: its own exploration need (what each ecosystem's
detection signal actually is), an independent commit boundary, and a >300 LOC estimate. Planning it
inline would make this PLAN.md unscannable and deny the work its own clean-context boundary.

- [ ] Create `docs/topics/routine-capability-detection/` and run `/planning:interview` then
      `/planning:plan` against it.
- [ ] Inputs it inherits, not re-derives: the catalog's axes and mapping rules
      (`routines.md:88-146`); the three-layer config cascade
      (`docs/conventions/config-cascade/`); the deterministic-gate preference
      (`PLUGIN-PHILOSOPHY.md:664-666`).
- [ ] **Sanity Check:** `ls docs/topics/routine-capability-detection/PLAN.md` exits 0 and its
      `## Brief` is non-empty.

---

### Phase 5: Tier 1 detector #1 — can't-fail test scan [TODO]

Review: code-design

Closes acceptance criterion "at least one Tier 1 detector ships and reaches the apply relay". Chosen
over the other two Tier 1 classes on trust-path requirement 1: assertion-free and tautological tests
are AST-detectable, so **membership is decidable without judgement**. Layering enforcement is not
decidable until Phase 4 lands its rules; formal-logic modeling produces inform-human findings with no
apply path, so it cannot settle this criterion.

- [ ] **ADR-0004 incumbent evidence** (first work item): `V1-coverage-negatives.md` §N3 — delete half
      airtight (`mutation-testing/skills/audit/SKILL.md:248`; all six `plugins/review/agents/*.md`
      caged without Edit/Write; `fix-pass-mode.md:17-18` has no test-quality class;
      `code-tidying/reference/tidyings.md:23`), and the fleet routes three times to a
      `plugins/dotnet-test/` that does not exist.
- [ ] **Phase-entry check:** `scripts/check-skill-leaf-names.sh` — `audit` carries a closed owner set
      (registry line 53, nine plugins), so the leaf is `scan`, which has no registry entry. Confirm
      before authoring; if a collision appeared, argue it on merits or rename.
- [ ] New skill under an existing plugin — **no new plugin** (ADR 0005). Target
      `plugins/testing/skills/scan/`.
- [ ] Detection is a **script**, not an agent: the judgment is mechanical
      (`PLUGIN-PHILOSOPHY.md:664-666`), and the named-agent bar (`:718-720`) is not met.
- [ ] Rules v1, each with an id and a threshold: zero-assertion test body · assertion whose expected
      value is recomputed by the code under test · fully-mocked test with no assertion on a real
      collaborator · a skip that vacates the only discriminating assertion of a case group.
- [ ] Remediation posture is **repair, not pruning** — the finding's `Action` proposes an assertion,
      never a deletion. Recorded Brief decision; the strongest research recommends repair, and those
      repairs uncovered real bugs.
- [ ] Emit through the Phase 3 contract; reach the relay by Pattern C — no fanout edits.
- [ ] Frontmatter obligations: `metadata.workflow-stage` (absent is a hard error),
      `metadata.summary` ≤100 codepoints, `description` + `when_to_use` ≤1536 chars, SKILL.md <500
      lines.
- [ ] `evals/evals.json` required; every file under `evals/fixtures/` referenced by a grader.
- [ ] Co-located `*.test.sh`; no GNU-only constructs in changed `.sh`
      (`scripts/check-shell-portability.sh`).
- [ ] Flip the `useless-test-repair` row in `plugins/autonomy/reference/routines.md` from its Phase 6
      join trigger to `v1` and add its leaf under `reference/routines/`.
- [ ] Regenerate `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md` — never hand-edit.
- [ ] Version bump + CHANGELOG for **both** `plugins/testing` and `plugins/autonomy` in this PR.
- [ ] **Sanity Check:** `scripts/check-skill-leaf-names.sh --check` exits 0.
- [ ] **Sanity Check:** `scripts/check-changed-skills.sh` exits 0; `scripts/check-orphaned-fixtures.sh`
      exits 0; `scripts/check-shell-portability.sh` exits 0.
- [ ] **Sanity Check:** `wc -l plugins/testing/skills/scan/SKILL.md` < 500.
- [ ] **Sanity Check:** on a fixture containing one assertion-free test, the emitted findings file
      is consumed by `review:fanout fix`, whose plan lists that finding — the criterion's actual
      settlement, not a proxy.
- [ ] **Sanity Check:** `git diff --name-only` shows no hand edit to `docs/CATALOG.md` outside a
      regeneration run.

---

### Phase 6: Catalog rows for every class considered [TODO]

Closes the Brief's "rows for every class considered, including the ones deliberately not built".
Every row derives its guardrail class **through the mapping rules at `routines.md:88-146`**, never by
hand — that is the phase's whole discipline.

- [ ] ADR-0008 admission check per row (first work item): a row is admitted only where its observable
      is anchored to text that is present. Drop any candidate whose observable anchors to nothing.
- [ ] Tier 1 rows with join triggers: formal-logic modeling · can't-fail test repair · layering
      enforcement (inform-human posture).
- [ ] Tier 2 rows: dead code, both postures, window floor **30-90 days with staged quarantine** —
      never the source's one day · clone **detection + trend gating** only · stale-flag removal.
- [ ] Tier 3 rows recording why not: logic simplification above expression level · abstraction
      flattening · ant-only shipper · GUI crash fuzzing.
- [ ] Score each on the catalog axes (Judgment / Output / Access), then apply the mapping rules
      including the hybrid split rule and the composition rule (`C5 > C4 > C3 > C2 > C1`).
- [ ] Named-product evidence goes to the research record, **not** to `## Precedent pointers` — that
      section's own scope line routes it elsewhere, and it is non-normative.
- [ ] Nothing in any row cites 388/180 as efficacy evidence.
- [ ] **Sanity Check:** `grep -c "^| " plugins/autonomy/reference/routines.md` increases by exactly
      the number of rows added; every added row has all six columns populated.
- [ ] **Sanity Check:** `grep -n "388\|180 merged" plugins/autonomy/reference/routines.md` returns
      empty.
- [ ] **Sanity Check:** every added row's `Derived row` value is reproducible by reading only
      `routines.md:88-146` and the row's own axis cells — spot-checked against three rows by a
      reviewer who did not author them.

---

### Phase 7: Q4 follow-on — reviewer-burden term, recorded as deferred [TODO]

The Brief names `/planning:plan` as this question's arbiter (`## Deferred questions`). Silence would
leave a designated obligation unfilled.

Ships in the **same autonomy PR as Phase 6** — one version bump, one CHANGELOG entry covering both.

- [ ] In `plugins/autonomy/reference/guardrails/work-classes.md` §"Suggested default predicates",
      record a reviewer-burden term as **deferred with an explicit trigger**, not as a live term:
      it needs a denominator, and trust-path requirements 3-5 are org-scale and deferred at solo
      volume.
- [ ] Record the composition hazard as a standing constraint: any future tuner's signal set stays
      **disjoint** from promotion evidence — otherwise a tuner could raise the metric that promotes
      the cell that reduces scrutiny of the tuner's own output.
- [ ] Reassert that no acceptance/merge-rate metric enters the predicate, in either role.
- [ ] **Sanity Check:** `grep -c "reviewer burden\|reviewer-burden" plugins/autonomy/reference/guardrails/work-classes.md`
      ≥ 1 and the surrounding text contains both the word `deferred` and a named trigger.
- [ ] **Sanity Check:** `grep -in "merge rate\|merge-rate\|acceptance rate" plugins/autonomy/reference/guardrails/work-classes.md`
      returns only lines that forbid it, never lines that use it as evidence.

---

### Phase 8: Repo-scope plugin declaration — BLOCKED [TODO]

Tier 0 item 4. Blocked on spike
[#2660](https://github.com/melodic-software/claude-code-plugins/issues/2660) (`needs-human`): two
official pages contradict each other, workspace trust for a cloud clone is undocumented, and an
untrusted declaration is ignored **silently**.

- [ ] **No work item here proceeds unattended.** The probe mutates a GitHub account and metered
      usage, and browser selection is forbidden to the agent.
- [ ] **Meanwhile, the documented fallback is the planned path**, not a contingency: components
      committed directly to `.claude/skills|agents|commands` are part of the clone and need no
      marketplace fetch, trust step, or credentials. Phases 1-3 and 5-7 are unaffected either way.
- [ ] **Sanity Check:** `gh issue view 2660 --json state,labels` shows the spike still open, or its
      resolution comment is quoted into this phase before any work item starts.

---

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| One-writer-per-directory + a separate merge step | The merge component has no owner today; extending the existing consumer adds no new surface |
| Detector appends into fanout's file | Requires a write-ordering and locking convention that does not exist |
| Build a Tier 1 detector before wiring `mutation-testing:audit` | Forfeits the integration slice — the contract would be authored against a predicted adopter instead of a real one |
| Formal-logic modeling as the first detector | Strongest external evidence, but its findings are inform-human with no apply path, so it cannot settle the relay criterion |
| Layering enforcement first | Membership is not decidable until Phase 4 ships per-repo layering rules |
| Reach the relay by adding a fanout leaf | Four hand edits, none auto-discovered; a conforming file needs zero |
| Add a live reviewer-burden term to the promotion predicate now | Unmeasurable at solo volume — a term with no denominator is a metric in name only |

### Test strategy

The verification surfaces here are shell gates, evals, and fixture-driven probes — not a unit-test
suite. Test-first applies as fixture-first: the failing fixture exists before the change.

- **Phase 1 (contract change, regression-shaped):** the named regression is *two conforming files in
  one branch directory, both findings surviving into the plan*. It fails against today's locator and
  passes after. A single-file fixture pins the no-behavior-change property.
- **Phase 2 (integration slice):** an end-to-end probe, not a unit assertion — emit from
  mutation-testing, consume via `review:fanout fix`, assert the plan text names the mutant finding.
  The prior session's hand-written conforming file is the fixture shape.
- **Phase 5 (new skill):** `evals/evals.json` is CI-required; graders assert rule id + threshold on
  each fixture. Co-located `*.test.sh` covers the detection script. Positive fixtures per rule, plus
  a negative fixture (a genuinely discriminating test) that must produce **zero** findings — the
  false-positive guard is the one that decides whether anyone keeps the detector on.
- **Phases 3, 6, 7 (doc/contract):** grep-shaped sanity checks above, plus a fresh-context reviewer
  re-deriving three Phase 6 rows from the mapping rules alone.
- **Every phase:** `scripts/check-changelog-parity.sh` and the full CI suite — only `docs/topics/` is
  docs-only-allowlisted, so every phase touching `plugins/**` or `docs/conventions/` runs everything.

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Phase 1 merge re-surfaces findings already fixed | Med | Med | Staleness bound at the newest `fix-pass-record` timestamp; degenerate single-file case pinned by fixture |
| Phase 2's flag alters `audit`'s read-only verb contract | Med | High | Persist is opt-in behind a flag; default path unchanged; verb-contract line asserted in the eval |
| Phase 5 detector emits false positives and gets ignored | High | High | Negative fixture required to return zero findings; rules carry ids so a noisy rule is disabled individually rather than the detector wholesale |
| A Phase 6 row's guardrail class is assigned by hand | Med | High | Reviewer re-derives three rows from `routines.md:88-146` alone; hand-assignment shows up as a mismatch |
| #2660 resolves against repo-scope declaration | Med | Low | Fallback is already the planned path, not a contingency |
| Phase 4 sub-topic drifts from this Brief | Med | Med | It inherits the axes, cascade, and gate preference by citation; its own Brief re-locks scope |

### Execution shape

**Recommended: sequential** — P1 → P2 → P3 → P5, with P6 → P7 (one autonomy PR) insertable anywhere
before P5's row flip. P4 runs on its own topic track. P8 is externally blocked.

**File-overlap matrix**

| Phase | Files | Overlaps with |
|---|---|---|
| P1 | `plugins/review/**` | none |
| P2 | `plugins/mutation-testing/**` | none |
| P3 | `docs/conventions/detector-findings/**` | none |
| P5 | `plugins/testing/**`, `plugins/autonomy/reference/routines.md` + manifest/CHANGELOG | P6, P7 |
| P6 | `plugins/autonomy/reference/routines.md` + manifest/CHANGELOG | P5, P7 |
| P7 | `plugins/autonomy/reference/guardrails/work-classes.md` + manifest/CHANGELOG | P5, P6 |

**Why not parallel.** P1/P2/P3 are chained by dependency, and the only file-disjoint pair worth
running together — P1 alongside P6+P7 — saves little: both are documentation-shaped and neither is
long-running. Weighed against that, P1 is the correctness gate every later phase assumes; running it
visibly first, alone, is worth more than the wall-clock. **Parallel option if wanted:** Wave A =
{P1} ∥ {P6+P7}, two agents, with the scope fence being P1's ALLOWED = `plugins/review/**` and
P6+P7's ALLOWED = `plugins/autonomy/**`; FORBIDDEN for both = PLAN.md, each other's tree, and all
staging/commit operations. Fallback if a fence is violated: abort that agent, finish sequentially.

**Per-phase routing**

| Phase | Surface | Basis |
|---|---|---|
| P1 | main-session | Contract judgment on a consumed file format; degenerate cases need care |
| P2 | main-session | Integration slice; its sanity check is an empirical probe, not a file assertion |
| P3 | main-session | Contract authoring informed by P2's observed behavior |
| P4 | own sub-topic | Promoted — own exploration need, own commit boundary, >300 LOC |
| P5 | main-session + sub-agent for fixtures/evals | Skill authoring is judgment-heavy; fixture generation is mechanical volume |
| P6 | sub-agent worker | Mechanical derivation through fixed mapping rules over a bounded row set |
| P7 | main-session | Small, judgment-bearing, and it discharges a named arbiter obligation |
| P8 | user-attended | Browser selection, account mutation, metered usage |

### Open questions

- Whether Phase 2's persist flag should also write when the run finds **zero** survivors. An empty
  conforming file is honest but becomes the newest file; under Phase 1's merge it is harmless, under
  today's locator it would shadow. Settle inside Phase 2, after Phase 1 lands.
- Whether `docs/conventions/detector-findings/` is the right convention name. Named at Phase 3
  authoring time; `/naming:name-it-better` if it is contested.
- Live daily run-cap numbers remain USER-RESERVED. Nothing in Phases 1-7 depends on them.

### Handoff to implementation

#### User-approval gates

- **Phase 8** — every work item. Nothing runs unattended.
- **Phase 2's flag surface** — a new user-facing flag on an existing skill's verb contract; confirm
  the flag name and default before authoring.
- **Phase 4 promotion** — creating a second topic directory is a scope shape change; confirm before
  `docs/topics/routine-capability-detection/` exists.
- **Any Phase 6 row that fails the ADR-0008 admission check** — dropping a class the Brief listed is
  a scope cut, not a mechanical outcome.

#### Execution shape (`[EXEC-SHAPE]`)

Sequential P1 → P2 → P3 → P5, P6 → P7 in one autonomy PR, P4 promoted, P8 blocked. Routing table and
scope fences above. Phase boundaries are PR boundaries **except** P6+P7, which share one autonomy
version bump and one CHANGELOG entry — splitting them across PRs would either duplicate the bump or
strand one phase without its changelog line, and the parity gate fails either way.

#### Mechanical work

- Commit per phase; surgical `git add` of named paths only — `git add -A` and `git add .` are
  forbidden (AGENTS.md). Commit messages via stdin heredoc, never multi-line `-m` (a PreToolUse hook
  blocks it).
- PLAN.md phase tags advance `[TODO]` → `[DOING]` → `[DONE]` main-session only; workers report back.
- Each `plugins/**` phase verifies its own version bump and CHANGELOG entry **before** opening its
  PR — the parity gate exempts no plugin.
- PR bodies need a native closing keyword (or the literal `No linked issue`) **and** a non-empty
  `## Related`; the linkage check strips HTML comments, so an unedited template does not pass.
- Sequential fallback if a parallel run is chosen and fails: abort the offending agent and finish
  that phase sequentially; the other agent continues.

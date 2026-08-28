# PLAN: copied-external-content

Interview contract locked 2026-08-27 on branch `claude/detect-copied-external-content-k5aw77`.
Discovery, brainstorm, blindspot, and audit-answers artifacts (all verification PASS) live in the
untracked memory slice `.work/copied-external-content/`; the interview ledger there records all 18
register rows and the validator verdicts behind every decision below.

## Brief

### TLDR

- New dedicated plugin: scans tracked markdown for content copied (verbatim or summarized) from
  external sources and refactors copies into citations, stamped records, or pointers.
- Detection is LLM-led and breadcrumb-first; deterministic scripts do only reasoning-free work
  (fingerprint compare of two concrete texts, link extraction, exclusion filtering, expiry check).
- Read-only audit by default; explicit `fix` applies `convert-to-pointer` / `trim-to-citation` /
  stamped-record dispositions behind a fresh-context semantic-diff guard and live pointer checks.
- Evidence-gated confidence tiers decide disposition eligibility; only fingerprint-confirmed
  findings reach relay files; judgment verdicts stay in the human report.
- Five pre-plan spikes and a hand-scored golden set prove the precision economics before any
  repo-wide sweep; the sweep's completion is what reopens the upstream-drift recorded decision.

### Goal

Reduce drift risk and maintenance burden from locally copied external content by giving the fleet
a portable audit-and-fix capability that finds tracked prose restating externally-owned facts,
confirms provenance against the authoritative source, and converts copies into pointers (or, for
load-bearing restatements, conforming four-part stamped records), with measured precision the
consuming repo can trust. This is the detector `docs/conventions/upstream-drift/README.md`
deferred on 2026-08-12 and named as its own reopening trigger.

### Constraints

- Deterministic scripts perform only reasoning-free operations; restatement classification, source
  hunting, and allowance judgments are LLM work (user constraint; upstream-drift enforceability
  tiers).
- Breadcrumb-first: citations already in or near a passage are the first confirm targets; budgeted
  external search (WebSearch as optional enrichment only) runs only when no breadcrumb exists.
- Offline-load-bearing surfaces are never bare-removed; they condense to stamped records. The
  rubric weighs read-frequency and fetch cost on the disposition side, not as an allowance
  category.
- All fetched candidate sources are DATA under `docs/conventions/untrusted-content/README.md`;
  the framing spine is carried inline byte-identical at every fetch surface; embedded imperatives
  are findings.
- Carve-outs are categorical, never per-instance (the "without a suppression list" bar): vendored
  trees, conforming stamped records, quotation contexts, owned content per `point-dont-copy`,
  distilled-product architectures (playbooks packs, knowledge memory tier), and the plugin's own
  eval-fixture tree.
- Portable baseline plus repo-declared-convention override (follow-our-standards ladder). The
  portable baseline ships only the reasoning-free expiry check; the trigger-less-stamp check is
  off-by-default behind the repo override and lands via the convention engagement.
- Relay files follow `docs/conventions/detector-findings/README.md`: script findings only, argued
  crosswalk rows, Confidence high or omitted; judgment verdicts are human-report-only.
- Budgets: per-candidate hard caps plus convergence early-stop (same top source twice, no new
  evidence), a corpus-level fetch ceiling, and a fetch cache (lychee `--cache` is the in-repo
  model); constants tuned from spike telemetry, placeholders until then.
- Dead pointers round-trip: targets verified live at edit time; a later-dead target demotes back
  to a stamped record or an archived-snapshot citation, wired to the weekly link-check lane.
- House prose style applies to all plugin surfaces (`/ai-slop:audit` clean); new judgment-bearing
  skills carry `evals/evals.json` or a reviewed exemption row (CI `--require-evals`).
- `claude plugin eval` is early-access-gated on CLI 2.1.246 (probed 2026-08-27); the migration
  playbook deferral stands and its trigger is NOT declared fired. Golden-set cases are authored
  runner-agnostic so they wrap as case.yaml when the runner opens.

### Acceptance criteria

- The audit, run over a corpus containing planted verbatim copies, paraphrased copies, and hard
  negatives, emits findings with the four-criterion rubric (span correspondence, beyond
  common-idiom, attribution adequacy, transformative use), each criterion graded with quoted
  evidence, carve-outs evaluated before criteria.
- Findings carry evidence-gated tiers: fingerprint-confirmed (fix-eligible), source-fetched-similar
  (human flag), llm-suspected (report-only), plus the neutral disposition "source not identified
  (budget exhausted; searched: ...)" naming every surface checked.
- `fix` is reachable only by explicit argument, applies the three dispositions, passes a
  fresh-context semantic-diff guard, and verifies every pointer target live before writing.
- Rubric verdicts are sampled three times; unanimity renders the verdict, splits route to the
  human.
- The golden set (5 to 10 synthetic cases growing toward 20 to 50, positives as shape-preserving
  rewrites of real history cases, hard negatives including paraphrase-styled-never-copied
  distractors) is hand-scored for case-level precision/recall; the fix-mode precision gate binds
  only at a stated minimum n per finding class, below which the class ships report-only.
- Execution contract for the eventual repo-wide sweep: one tracked file at a time; apply the
  verdict, verify (semantic-diff plus pointer liveness), close; a file is closed when every
  finding in it carries a disposition or an explicit neutral outcome; sweep completion (not spike
  results) fires the upstream-drift reopening, recorded as one convention engagement with one
  changelog entry, major bump only if the enforceability verdict changes.
- Spike phase (throwaway, losers captured, one written question each) precedes /planning:plan:
  S1 golden-set hand-scored P/R, S2 hand-run grading skeleton, S3 rubric + 3-vote judge against
  ~30 hand-labeled findings, S4 tier-mapping adoption, S5 budget instrumentation from S1/S3 runs.

### Captured assumptions

- The four-criterion rubric decomposition is sufficient; revisit if S3's judge-vs-human
  precision/recall shows a criterion is unreliable or missing.
- Categorical carve-outs clear the recorded decision's "without a suppression list" bar; revisit
  if the sweep accumulates per-instance suppressions.
- Fingerprint compare (shingle/Jaccard or winnowing) of a local passage against a fetched page is
  reliable for verbatim/near-verbatim spans; revisit if S1/S2 show discrimination failures.
- The stamp-date corpus (~141 to 155 tracked files) is the primary target population; revisit if
  nomination surfaces a materially different population.
- Hand-scored evals suffice until the plugin-eval runner leaves early access; revisit when
  medley#1418 moves or a `claude plugin eval` invocation succeeds.

### Out-of-scope

- Code comments (v1 non-goal; route-out note toward `code-tidying:audit-comment-residue`).
- A per-source hash store (deferred; scanner telemetry feeds the convention's designed-issue
  trigger, expected to fire at the first sweep).
- In-repo duplication (owned by `extract-ssot` and `reference-dont-duplicate`), doc-vs-code drift
  (doc-drift-detector, codebase-health), doc-level worth (audit-derivability), in-flight
  discipline (point-dont-copy).
- Declaring the migration playbook's plugin-eval deferral trigger fired.
- Standing search-API integrations (Bing/Google CSE class); WebSearch enrichment only.

### Deferred questions

- Q19 - Plugin and skill naming (working candidate: `provenance`) - defer until the design phase;
  resolve via /planning:design with /naming:name-it-better; **arbiter: /planning:plan**
- Q16 - Numeric values of the fix-mode precision bar, report-mode recall floor, and minimum n per
  finding class - defer until plan time with S1/S3 measurements in hand; **arbiter:
  USER-RESERVED**
- Q10 - Budget constants (N searches, M fetches per candidate; corpus-level ceiling) - defer until
  S5 telemetry exists; **arbiter: /planning:plan**

## Plan

Written 2026-08-27 by /planning:plan against the accepted design in `design/` (capability
matrix, type inventory, plugin topology, design threads, convention engagement). Name locked:
`provenance` (Q19, user pick at the design gate). This plan covers building and measuring the
plugin (handoff actions 3 to 5). The repo-wide sweep and the convention engagement (actions 6
and 7) are follow-on phases promoted to their own topic; see Phase 8.

**Approved 2026-08-27 by the user** ("OK I agree with all recommendations"), after the
fresh-context review and devils-advocate hardening passes. Execution begins at Phase 1.

### Q16 and Q10 resolutions (recorded here; schema in `design/type-inventory.md`)

Q16 (user-resolved 2026-08-27, posture not fixed numbers): accuracy is the goal, and
recall-first: the user will spend more tokens rather than let copies slip through. Report
surfaces are never filtered by any bar; the bars gate only fix-mode eligibility and release
readiness, and every one of them is a tunable config key, not a constant. Defaults:
`fix_precision_bar` 0.95, `report_recall_floor` 0.8, `min_n_per_class` 10. The same
resolution funds a configurable verification-depth block (the `accuracy` config below):
multi-pass nomination, perspective-diverse judges, and an optional independent review agent
are all dials the consuming repo can turn up. The user's best case is a skill that improves
its own accuracy over time; Phase 6 builds that loop (adjudicated findings become golden-set
fixtures via shape-preserving synthetic rewrite; run telemetry retunes constants).

Accuracy config (amends the type-inventory schema, dated note there): `accuracy: {
nomination_passes: 2, judge_lens_diversity: true, review_agents: 1,
deep_research_on_exhaustion: false }`. `judge_samples` stays a TOP-LEVEL key (single home,
matching the schema and the Q10 list); the setup skill rejects unknown keys under `accuracy`
so a misplaced `accuracy.judge_samples` fails loudly instead of becoming a silent no-op.
A review-agent veto never reassigns a tier (the mapping is fixed at contract time): it forces
the finding's disposition to `leave-with-reason`, human-routed, so the finding stays visible
and fix-ineligible; the finding record carries a `review` block mirroring `rubric` (dated
type-inventory amendment). `deep_research_on_exhaustion` is presence-gated per seam-phrasing:
when no research-capable skill is installed the dial degrades to a visible warning plus the
normal neutral disposition, never a refusal. `judge_lens_diversity` defaults on under the
user's accuracy directive, and Phase 6's dial measurement is the commitment behind it: if
diversity degrades verdict unanimity without a recall gain, the default flips off in the same
change that records the measurement. Nomination passes union their nominations (recall
bias); diverse judge lenses replace three identical prompts (S3 measured self-consistency
only, and the user funded the diversity probe); `review_agents` adds fresh-context unbiased
validators over STANDS verdicts before fix eligibility; `deep_research_on_exhaustion` lets a
run escalate a not-found candidate to a /discovery:research-style pass instead of stopping at
the budget, off by default because it multiplies cost per candidate.

Q10 (plan-resolved from S5 telemetry): fetches are cheap (~0.55 s/page, compare ~29 ms/file),
judge sampling is the cost center, and the user's accuracy-over-tokens directive says budgets
exist to bound runaway loops, not to save money. Defaults, all config-tunable:
`searches_per_candidate` 3, `fetches_per_candidate` 5, `corpus_fetch_ceiling` 200,
`judge_samples` 3 (floor 3 for fix-eligible findings), `stamp_expiry_days` 180, separation
`{min_containment: 0.3, min_span_words: 15}`.

### Standards grounding

No standards index exists (`docs/standards/` absent, no `.claude/standards.yaml`); rung-4
inference from repository context that is not auto-loaded:

| Surface | Sections cited | Layer provenance |
|---|---|---|
| detector-findings | `docs/conventions/detector-findings/README.md` (relay contract, severity crosswalk; enforced by `scripts/check-detector-findings-crosswalk.sh --check`) | team |
| upstream-drift | `docs/conventions/upstream-drift/README.md` (four-part records, fetch route, recorded decision) | team |
| untrusted-content | `docs/conventions/untrusted-content/README.md` (framing spine, inline byte-identical) | team |
| config-cascade | `docs/conventions/config-cascade/README.md` (`.claude/provenance.json`, `--show-config`) | team |
| shell-test-helpers | `docs/conventions/shell-test-helpers/README.md` (paired `.test.sh` shape) | team |
| evals warrant | `scripts/check-changed-skills.sh <base-ref>` (applies `--require-evals` internally to changed skills) plus `scripts/evals-warrant-exemptions.txt` | team |
| house prose | `/ai-slop:audit` catalog; `.claude/rules/vendor-docs-are-not-style.md` (ambient, not re-pulled) | team |
| topic-docs | `docs/conventions/topic-docs/README.md` (destination rung order the emitter's caller resolves) | team |
| plugin-data-report-keying | `docs/conventions/plugin-data-report-keying/README.md` (the report sidecar's keying) | team |
| seam-phrasing | `docs/conventions/seam-phrasing/README.md` (presence-gated references to sibling plugins) | team |
| invocation-mode | `docs/conventions/invocation-mode/README.md` (the two new always-listed skill descriptions) | team |

### Test strategy

TDD (Red-Green-Refactor) for every deterministic script: the paired test is written first,
red, then the script makes it green. Test boundaries, all settled by this plan's approval:

- `fingerprint.mjs` pure module functions plus its CLI (newly introduced). First tests are the
  two S2 amendment fixtures: an inline-quote fixture that must strip to zero matches, and a
  real-sized-file fixture where a 27-word planted span must surface as a matched span, not a
  diluted whole-file score.
- The five bash script CLIs (newly introduced), fixture-driven per shell-test-helpers.
- `evals/evals.json` per judgment-bearing skill (existing house harness; the CI warrant).
- The golden-set harness (newly introduced): hand-scored case-level P/R with
  `score-golden.sh` doing the mechanical tally. Runner-agnostic per the Brief.

Edge cases owned by named tests: unparsed stamp forms decline with reasons (check-stamps),
fixture-tree exclusion is unconditional (list-corpus), emitter refuses on unreachable contract
(emit-findings), curly plus straight inline quotes strip (fingerprint).

### Phases

### Phase 1: Scaffold and registration [DONE]

Create the plugin skeleton per `design/plugin-topology.md` and register it.

- [x] `plugins/provenance/.claude-plugin/plugin.json` CREATE (manifest, version 0.1.0)
- [x] `plugins/provenance/README.md` CREATE (boundary statement per topology doc, config keys, marker forms, and a prerequisites section: Node for fingerprint.mjs, bash for the scripts, WebSearch optional with the degraded breadcrumb-only branch named)
- [x] `plugins/provenance/CHANGELOG.md` CREATE
- [x] `.claude-plugin/marketplace.json` MODIFY (add entry, ai-slop entry as the shape precedent; category chosen from the `docs/CATALOG-TAXONOMY.md` vocabulary, which `scripts/generate-catalog.mjs`'s CATEGORY_ORDER enforces)
- [x] `docs/CATALOG.md` MODIFY (regenerate: `node scripts/generate-catalog.mjs`)
- [x] `docs/SKILL-CHEAT-SHEET.md` MODIFY (regenerate: `node scripts/generate-cheatsheet.mjs`; regenerated again in Phase 5 when the SKILL.md files land)
- [x] `.claude/settings.json` MODIFY (insert `"provenance@melodic-software": true` under `enabledPlugins` in byte order; the catalog-enablement gate fails both UNENABLED and UNSORTED, and this is the three-time-shipped failure class the gate exists for)

**Sanity Check:** `jq empty plugins/provenance/.claude-plugin/plugin.json` exits 0;
`jq -e '.plugins[] | select(.name == "provenance")' .claude-plugin/marketplace.json` exits 0;
`bash scripts/validate-plugins.sh` exits 0 (it runs the catalog and cheatsheet `--check` plus
manifest validation, so the generated views must be regenerated in this phase);
`bash scripts/check-plugin-catalog-enablement.sh` exits 0.

### Phase 2: Fingerprint module [DONE]

Review: code-design

The load-bearing pure module, rewritten from `spike-fingerprint.mjs` per prototype discipline
(never lifted verbatim). Preprocessing inside the module: strip code fences, blockquotes, and
inline-quoted spans (straight and curly) from the local text before shingling; then word
5-shingles, containment, Jaccard, longest matched span; matched-SPAN verdicts with local line
offsets. Contract: `design/type-inventory.md` "fingerprint.mjs".

- [x] `plugins/provenance/skills/audit/scripts/fingerprint.mjs` CREATE
- [x] `plugins/provenance/skills/audit/scripts/fingerprint.test.mjs` CREATE (first, red)
- [x] `plugins/provenance/skills/audit/scripts/fingerprint.test.sh` CREATE (discovery wrapper, autonomy-plugin shape with a node-absent SKIP; `run-plugin-tests.sh` discovers only `*.test.sh`, so without the wrapper the module has zero CI coverage)

**Sanity Check:** `node plugins/provenance/skills/audit/scripts/fingerprint.test.mjs` exits 0
and its output names the inline-quote fixture and the span-dilution fixture as passing;
`bash plugins/provenance/skills/audit/scripts/fingerprint.test.sh` exits 0;
`node .../fingerprint.mjs compare --local <fixture> --source <fixture> --json | jq -e
'.matched_spans'` exits 0.

### Phase 3: Deterministic scripts [DONE]

The five bash scripts with paired tests, contracts in `design/type-inventory.md`. Each is
reasoning-free (Brief C1); stdout JSON, stderr diagnostics, non-zero exit only on operational
failure.

- [x] `plugins/provenance/skills/audit/scripts/list-corpus.sh` + `.test.sh` CREATE (46 cases)
- [x] `plugins/provenance/skills/audit/scripts/extract-breadcrumbs.sh` + `.test.sh` CREATE (42 cases)
- [x] `plugins/provenance/skills/audit/scripts/check-stamps.sh` + `.test.sh` CREATE (43 cases)
- [x] `plugins/provenance/skills/audit/scripts/emit-findings.sh` + `.test.sh` CREATE (51 cases)
- [x] `plugins/provenance/skills/audit/scripts/score-golden.sh` + `.test.sh` CREATE (41 cases)

Contract split for `emit-findings.sh`, following the ai-slop precedent exactly (its
`context/persist-findings.md` hands the script `--out <resolved path>`): the MODEL resolves
the destination through the topic-docs rung order and runs the fetch-and-refuse contract
gate; the SCRIPT receives `--report <sidecar> --out <resolved path>` and does only the
reasoning-free composition (cell escaping, rule-id-first Finding cells, tier lookup).
Rung resolution involves prose inference and is not reasoning-free, so putting it in bash
would violate Brief constraint C1 (stress-test finding, 2026-08-27; type-inventory carries
the dated amendment).

**Sanity Check:** `for t in plugins/provenance/skills/audit/scripts/*.test.sh; do bash "$t" ||
exit 1; done` exits 0; `bash scripts/affected-tests.sh --run` (diff vs origin/main) exits 0
(the `--run` flag executes; bare invocation only lists).

**Sanity Check result, 2026-08-28.** The first command exits 0: all six suites pass, 244 cases
across the five bash scripts plus the fingerprint wrapper. The second **exits 3, not 0, and the
plan's expectation of 0 was unreachable from the moment Phase 2 landed** — not a Phase 3
regression. `affected-tests.sh` reserves exit 1 for a failing suite; exit 3 means every shell
suite it selected passed AND it also selected a suite in an ecosystem it deliberately refuses to
guess a runner for. `fingerprint.test.mjs` is permanently such a suite, so any diff touching this
plugin selects it and the runner can never return 0. Verified both lanes green rather than
treating the code as a failure: 29 shell suites passed under `--run`, and
`node plugins/provenance/skills/audit/scripts/fingerprint.test.mjs` exits 0 at 21 of 21. Later
phases should read this gate as "exit 0, or exit 3 with the Node lane run separately and green".

**Corpus baseline, 2026-08-28** (measured, not projected; `--as-of 2026-08-28`, 1,347 tracked
markdown files after carve-outs, 20 vendored paths declined): 525 stamp candidates, 482 parsed,
43 declined (19 month-name forms, 24 bare years), 0 expired at the 180-day default. The oldest
parsed stamp is 2026-04-08, which is why the default window fires on nothing; at a 60-day window
the same corpus yields 9 findings. Two findings that cost measurement to reach are recorded in
`plugins/provenance/CHANGELOG.md` under `[0.1.0]`: mawk's silent interval-expression panic, and
the keyword-window narrowing that removed an API beta identifier
(`context-management-2025-06-27`) masquerading as an expired stamp.

### Phase 4: Reference artifacts [DONE]

The versioned prose surfaces the audit flow loads at the step that needs them, per
`design/plugin-topology.md` load order. The rubric catalog is the T7 shape: carve-outs first,
four binary criteria with quoted-evidence requirements and worked pass/fail examples, the tier
table, one four-part record per entry restating an externally-owned rule.

- [x] `plugins/provenance/skills/audit/reference/rubric.md` CREATE
- [x] `plugins/provenance/skills/audit/reference/dispositions.md` CREATE (three dispositions, guards, demotion path)
- [x] `plugins/provenance/skills/audit/reference/source-fetch.md` CREATE (rung ladder, identity checks, cache, budgets; four-part record citing upstream-drift)
- [x] `plugins/provenance/skills/audit/reference/nomination.md` CREATE (nomination and judge prompt templates, untrusted spine inline)
- [x] `plugins/provenance/skills/audit/context/persist-findings.md` CREATE (relay mechanics, refuse-when-unreachable; model-side rung resolution per the Phase 3 contract split)

Noted tension, resolution tagged in the handoff: ai-slop's model fetches the detector-findings
contract from the publisher's raw URL at run time, which PLUGIN-PHILOSOPHY's org-agnosticism
section flags as non-conforming (open case) and which turns every offline run report-only.
Planned resolution: resolve the contract shape through the installed `review` plugin's bundled
copy when present (presence-gated per seam-phrasing), publisher URL as fallback,
refuse-when-neither-reachable retained.

**Resolution landed 2026-08-28** in `context/persist-findings.md` as a three-rung order, with
the seam-phrasing elements at the reference site (gate on installed-ness of `review`, never a
marketplace id; stated fallback; ownership framing). One scope limit is stated there rather than
left implicit: rung 1 yields the file SHAPE and the merge rules, which is what composition
needs, but severity-vocabulary mapping to a consuming project stays model work either way.

**Sanity Check:** each criterion id greps individually (`for c in C1-span-correspondence
C2-beyond-common-idiom C3-attribution-adequacy C4-transformative-use; do grep -q "$c"
plugins/provenance/skills/audit/reference/rubric.md || exit 1; done` exits 0); the
untrusted-content convention's own two conformance greps pass over `source-fetch.md` and
`nomination.md`, and are re-run in Phase 5 over SKILL.md's fetch step and fix-flow liveness
check (all four T8 surfaces covered); `/ai-slop:audit` over the five files reports clean.

**Sanity Check result, 2026-08-28.** All four criterion ids grep individually. The two
untrusted-content greps match file-for-file over exactly `source-fetch.md` and `nomination.md`,
which is the correct Phase 4 state: the remaining two T8 surfaces are SKILL.md's fetch step and
the fix-flow liveness check, both Phase 5. The ai-slop detector reports 0 findings across the
five files; markdownlint, typos, editorconfig-checker, `check-skill-portability.sh --all`,
`check-purged-em-dashes.sh --check` and `validate-plugins.sh` all exit 0. Em-dash density in the
new reference files (4 to 12 per file) sits inside the range the ai-slop precedent already
carries (`catalog.md` has 24) and none of these paths is on the purge ratchet's declared-clean
list, so the campaign's allowlist is unaffected.

One expected unresolved reference: `context/persist-findings.md` and the reference files name
`/provenance:audit`, whose `SKILL.md` lands in Phase 5. The repo's skill-reference hook flags it
until then; it is correct as written and resolves when Phase 5 commits.

### Phase 5: Skills and evals [DONE]

Review: code-design

The two SKILL.md surfaces (audit with actions `audit` default read-only, `fix`, `sweep`;
setup for config management) plus their evals. Fix and sweep mechanics follow the Brief:
explicit argument only, semantic-diff guard, pointer liveness, closure accounting. The setup
skill manages `.claude/provenance.json` including the Q16/Q10 keys and the `accuracy` block
above; the audit flow reads the accuracy dials when spawning nomination, judge, and review
subagents.

- [x] `plugins/provenance/skills/audit/SKILL.md` CREATE (composition step explicitly reconciles emit-findings.sh behavior against context/persist-findings.md, since Wave A authors the two halves of that contract in separate agents)
- [x] `plugins/provenance/skills/audit/evals/evals.json` CREATE (8 cases; referencing ONLY fixtures that exist at this phase; the eval-quality lint FAILs unresolvable fixture paths, so golden-dir references wait for Phase 6's MODIFY)
- [x] `plugins/provenance/skills/audit/evals/fixtures/` CREATE (three synthetic fixtures about a fictional tool, so the repo carries no actual copied text: an expired stamp, a quoted-and-cited hard negative, and an unattributed restatement)
- [x] `plugins/provenance/skills/audit/context/gotchas.md` CREATE (not in the original list; added because `check-skill` asks for a Gotchas surface and the build produced real failure history worth recording, and because moving it off SKILL.md kept that file under the 200-line soft target)
- [x] `plugins/provenance/skills/setup/SKILL.md` CREATE
- [x] `plugins/provenance/skills/setup/evals/evals.json` CREATE (6 cases)
- [x] `scripts/skill-leaf-name-registry.txt` MODIFY (append `provenance` to the `audit` row's owner set with argued grounds per the file's own format; the row is a fixed 14-plugin set, no wildcard, and `check-skill-leaf-names.sh --check` fails on an owner-set change that arrives unargued. `setup` is wildcarded, no edit needed)

**Sanity Check:** `bash scripts/check-changed-skills.sh origin/main` exits 0 with the two new
skills in scope (it applies `--require-evals` to changed skills internally);
`bash scripts/check-skill-leaf-names.sh --check` exits 0;
`node scripts/generate-cheatsheet.mjs && node scripts/generate-catalog.mjs` then
`bash scripts/validate-plugins.sh` exits 0; the untrusted-content conformance greps pass over
the audit SKILL.md's fetch step and fix-flow liveness check; `/skill-quality:check` over both
SKILL.md files reports no blocking findings; `grep -n 'fix' plugins/provenance/skills/audit/SKILL.md`
shows fix reachable only under an explicit-argument heading.

**Sanity Check result, 2026-08-28.** All pass. `check-changed-skills.sh origin/main` exits 0 with
both new skills in scope at 0 errors and 0 warnings; `check-skill-leaf-names.sh --check` exits 0
at 15 registered collisions; both generators run and `validate-plugins.sh` exits 0; the two
untrusted-content greps now match file-for-file over three files, adding SKILL.md to the two
Phase 4 surfaces, so all four T8 ingest surfaces are covered (SKILL.md carries the full spine at
its fetch step and the fix flow's liveness check cites that statement rather than restating it);
`fix` appears only in the router row and under `## Fix flow (explicit invocation only)`. The
ai-slop detector, markdownlint, typos and the eval-quality lint are all clean.

Three corrections this phase made, each caught by a gate rather than by review:

- **The branch was 22 commits behind `origin/main`**, which made `check-changed-skills.sh` report
  a dropped-trigger-keyword regression in `ai-slop`, a plugin this branch never touched. Merging
  `origin/main` cleared it. A skill warrant compares against the base ref, so a stale branch
  manufactures failures in other people's skills.
- **The setup skill's action vocabulary was wrong.** The setup contract requires `check` as the
  leading action with `apply` documented (or a declared check-only carve-out), not the
  `show`/`init`/`set` shape first drafted. `validate-plugins.sh` named all four violations.
- **Setup skills must not carry `metadata.workflow-stage`/`summary`**: they are excluded from the
  cheat sheet as infra setup, and `generate-cheatsheet.mjs` fails on the contradiction.

### Phase 6: Golden set, measurement, and the improvement loop [TODO]

Author 5 to 10 synthetic cases per the type-inventory case shape (positives as
shape-preserving rewrites of real history cases, hard negatives including
paraphrase-styled-never-copied distractors and quoted-and-cited excerpts, plus 2 to 3
adversarial synonym-rotation cases probing the separation rule, per design thread T15). Run
the audit over the fixture corpus, hand-score case-level P/R, tune the separation constants
and budgets from the measured telemetry, and record the measured values in this PLAN. Build
the improvement loop: an `adjudications.md` reference section in the audit skill instructing
that human-rejected findings and later-discovered misses are converted (synthetic rewrite,
never verbatim externally-owned text) into new golden cases, so the set grows toward 20 to 50
and accuracy improves run over run. This phase also measures the accuracy dials the user
funded: diverse judge lenses versus identical prompts (the T15 diversity probe, now in scope)
and multi-pass nomination union, scored against the same golden set so each dial's recall
gain is a recorded number, not a belief.

Consequences stated plainly (stress-test findings, 2026-08-27). First, the v1 fix posture:
with 5 to 10 total cases across four classes, no class reaches `min_n_per_class` 10, so
EVERY class ships report-only at v1 by the gate's own arithmetic; fix mode goes live per
class only when the growth loop carries that class past minimum n at or above the precision
bar, `verbatim` targeted first. This is the designed path, not a failure, and growing the
two fix-eligible classes to n >= 10 is a NAMED exit condition of the sub-topic's first
growth round, not an open-ended aspiration. The phase's required deliverable is the gate
decision table (per class: n, P, R, gate outcome) recorded in this file; at n near 10 the
0.95 bar means one error demotes, so the bar behaves as a ratchet, not a statistic, and that
is accepted. Second, Phase 6 runs are sidecar-only: the emitter is not invoked until Phase
7's registry rows exist, so no relay file ever carries a rule id with no crosswalk row. The
T15 live no-breadcrumb (not-found) probe needs a live corpus and moves to the Phase 8
sub-topic's Brief.

Harness seam (design amendment, dated in `design/capability-matrix.md`): the fixture-tree
exclusion moves from unconditional-in-script to a CONFIG-LAYER entry (this repo's
`.claude/provenance.json` `excluded_paths`), exactly the ai-slop resolution of #3041, so the
eval harness's isolation (empty HOME plus CLAUDE_PROJECT_DIR) lifts the exclusion and
fixtures are measurable while every normal run still declines them. `list-corpus.sh` (built
in Phase 3, so the contract lands before Wave A dispatches) takes the exclusion from config,
not a hardcoded glob. Offline sources: a case directory with `source.md` present
short-circuits the fetch stage (stated in `reference/source-fetch.md`), so golden runs
exercise nomination, resolution, fingerprint, and judgment without live fetches; the bypass
is scoped to corpus enumeration and fetch, never to judgment stages.

- [ ] `plugins/provenance/skills/audit/evals/evals.json` MODIFY (register the golden case dirs as `files[]`; `check-orphaned-fixtures.sh --check` fails unregistered fixture files, and the adjudication loop text must state that a new case is not landed until evals.json names it)

- [ ] `plugins/provenance/skills/audit/evals/fixtures/golden/c01-.../` CREATE (5 to 10 case dirs: case.md, expected.json, source.md where needed)
- [ ] `plugins/provenance/skills/audit/reference/dispositions.md` MODIFY (adjudication-to-fixture loop, if not landed in Phase 4)
- [ ] `docs/topics/copied-external-content/PLAN.md` MODIFY (record measured P/R)

**Sanity Check:** `bash plugins/provenance/skills/audit/scripts/score-golden.sh --report
.work/copied-external-content/golden-run-report.json` exits 0 and emits per-class P/R (the
sidecar path convention: the run's memory slice, this name); with this repo's config in
place, `bash plugins/provenance/skills/audit/scripts/list-corpus.sh plugins/provenance`
output does NOT contain `fixtures/golden` (config-layer exclusion active); the gate decision
table (per class: n, P, R, outcome) recorded in this file; `bash
scripts/check-orphaned-fixtures.sh --check` exits 0; `git diff --name-only` for the phase
contains no relay findings file.

### Phase 7: Crosswalk registration and quality gate [TODO]

Land the three draft crosswalk rows from `design/type-inventory.md` in the detector-findings
registry, then run the full-repo quality gates over every new surface.

- [ ] `docs/conventions/detector-findings/README.md` MODIFY (three rows: rule-verbatim-copy, rule-stamp-expired, rule-trigger-less-stamp; RESHAPED into the registry's exact column set `| Rule id | What fires it | The test the disposition is argued from | Tier or disposition | Auto-applicable |` with pipes escaped and the `<name>` placeholders substituted to `provenance/audit/rule-*`, appended to the existing table, never pasted as a second table: the crosswalk check locates the table by its exact header and fails duplicates)
- [ ] `docs/conventions/detector-findings/CHANGELOG.md` MODIFY (entry for the rows)
- [ ] `plugins/provenance/**` KEEP (audited by the gates, no planned change)

Registering the `rule-trigger-less-stamp` crosswalk row here does NOT fire the upstream-drift
convention engagement and does not touch that convention's "named but not built" table row:
the engagement fires at sweep completion only (Brief; `design/convention-engagement.md`), and
the row update is part of that engagement's changelog entry, owned by the Phase 8 sub-topic.
The interim state (check built and registered, convention table not yet updated) is accepted
and recorded here so it reads as scheduled, not drifted.

**Sanity Check:** `bash scripts/check-detector-findings-crosswalk.sh --check` exits 0;
`/ai-slop:audit` over `plugins/provenance` reports clean; full repo CI test lane
(`bash scripts/affected-tests.sh`) exits 0.

### Phase 8: Sweep and convention engagement (promoted sub-topic) [TODO]

The repo-wide sweep under the Brief's execution contract, the combined upstream-drift
convention engagement (executing `design/convention-engagement.md`), and the narrow CI
regression gate for the cleaned state are promoted to their own topic
(`docs/topics/provenance-sweep/`, own PLAN.md) per the sub-topic promotion trigger: own
commit boundaries, more than five work items, and its own measurement needs. This phase in
the parent plan is only the promotion itself. The sub-topic's Brief must carry, beyond the
execution contract: the T15 live no-breadcrumb (not-found) probe as a first-run validation
item, and sweep resume semantics (the fetch ceiling and cache are scoped per SWEEP and
recorded in the closure ledger, so a resumed sweep neither resets its spend nor silently
reuses a stale cache; the ledger is checkout-local, stated).

- [ ] `docs/topics/provenance-sweep/PLAN.md` CREATE (Brief inherited from this file's execution-contract criteria plus the two items above)

**Sanity Check:** the sub-topic PLAN.md exists and its Brief cites this file; nothing under
`plugins/provenance` changes in this phase (`git diff --name-only` for the phase touches only
`docs/topics/provenance-sweep/`).

### Alternatives considered

| Alternative | Why rejected |
|---|---|
| Fold into docs-hygiene instead of a new plugin | Interview Q1, validated: ai-slop is the structural precedent; boundary argued against every adjacent owner in `design/plugin-topology.md` |
| Deterministic web-scale copy detection | No candidate corpus, no durable search-API substrate (RESEARCH.md); rejected before design |
| Whole-file containment verdicts | S2: a real 27-word match diluted to 0.019 on a 2,912-shingle file; span reporting adopted |
| `claude plugin eval` as the v1 harness | Runner refuses with an early-access gate on CLI 2.1.246, probed twice by execution; single-track evals.json plus golden set instead |
| Fixed Q16 bars as constants | User resolution 2026-08-27: recall-first posture, everything tunable; bars became config defaults |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Verification depth makes runs slow and token-heavy | High | Low | Accepted explicitly by the user (accuracy over tokens, 2026-08-27); every dial is config; convergence early-stop bounds loops |
| Fingerprint evaded by systematic paraphrase | Med | Med | Such spans stay `llm-suspected`, report-only by contract; adversarial fixtures in Phase 6 measure the boundary |
| Golden-set fixtures leak externally-owned text | Low | High | Synthetic-only rule stated in the case shape; Phase 6 review checks every source.md is invented |
| Fix rewrite loses meaning | Low | High | Fresh-context semantic-diff verifier, revert accounting, pointer liveness at edit time (Brief) |
| Report noise at recall-first posture | Med | Low | Tiers keep report surfaces triaged; carve-outs run before criteria; user accepted the trade explicitly |

## Blast radius

MEDIUM. Additive new plugin directory plus two shared-surface edits (marketplace.json, the
detector-findings registry). Stress-test triggers matched: new skill creation with side
effects (fix mode edits files), new enforcement surface (relay rules), multi-step build.
Formal stress-test: run (Step 4).

## Stress-test summary

Two fresh-context passes ran 2026-08-27 against the draft: the plan reviewer (13 findings: 1
CRITICAL, 5 IMPORTANT, 7 SUGGESTION) and a devils-advocate stress-test (15 findings: 1
CRITICAL, 4 HIGH, 5 MEDIUM, 5 LOW). Load-bearing findings were verified against the repo
before fixing; all confirmed, all folded in. The headline catches: the marketplace edit
needed the generated catalog views AND the `.claude/settings.json` enablement key (the
three-time-shipped CI failure class); the `audit` leaf name needs an argued registry
addition; `fingerprint.test.mjs` needed a `.test.sh` discovery wrapper to be CI-covered at
all; the emitter script's contract violated the reasoning-free constraint and was split
model-side/script-side per the ai-slop precedent; the min-n arithmetic makes v1 fix mode
dark for every class (now stated as the designed path with a named exit condition); and the
unconditional fixture exclusion would have made the golden harness unable to measure the
shipped pipeline (moved to the config layer, the repo's own #3041 resolution). Both
reviewers' verdict: amend, do not rework; no finding undermined the Brief or the accepted
architecture.

## Execution shape

Phase 1 gates everything (the directory skeleton). After it, Wave A runs three file-disjoint
phases in parallel; Wave B is sequential because each consumes prior outputs.

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 2 | `scripts/fingerprint.*` | none |
| 3 | `scripts/*.sh`, `scripts/*.test.sh` | none |
| 4 | `reference/*.md`, `context/*.md` | 6 (dispositions.md, if loop text lands late) |
| 5 | `skills/*/SKILL.md`, `evals/evals.json` | none |
| 6 | `evals/fixtures/golden/**`, PLAN.md | 4 (dispositions.md) |
| 7 | `docs/conventions/detector-findings/*` | none |
| 8 | `docs/topics/provenance-sweep/` | none |

### Recommended shape

> Wave A (parallel sub-agents, single message): Phases 2, 3, 4
> Wave B (sequential after Wave A): 5, then 6, then 7, then 8
> Cost note: 3 parallel agents multiply token usage roughly 3x over sequential for that wave;
> sequential remains valid and loses only wall-clock.
> Fallback: on a scope-fence violation, concurrent-edit race, or an agent reporting
> cannot-complete, abort that agent and run 2 then 3 then 4 sequentially; other agents continue.

### Scope-fencing tables (Wave A)

| Agent | Phase | ALLOWED files | LOC est |
|---|---|---|---|
| A1 | 2 | `plugins/provenance/skills/audit/scripts/fingerprint.mjs`, `fingerprint.test.mjs` | ~450 |
| A2 | 3 | `plugins/provenance/skills/audit/scripts/*.sh`, `*.test.sh` (five pairs) | ~900 |
| A3 | 4 | `plugins/provenance/skills/audit/reference/*.md`, `context/persist-findings.md` | ~600 |

Each agent FORBIDDEN: any file outside its ALLOWED list; PLAN.md; other agents' territory;
staging, commit, or push. Each worker brief carries the divergence-escalation clause from the
plan template verbatim. PLAN.md phase-tag flips are main-session-owned and serialized (agents
report back; the main session commits), so the tag-flip write never races Wave A. A2 builds
`emit-findings.sh` while A3 writes `context/persist-findings.md`; both anchor to the
type-inventory contract, and Phase 5's main-session composition step reconciles the two
halves explicitly.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | small, touches the shared marketplace manifest |
| 2 | sub-agent worker | pure module, fixture-driven TDD, fully fenced |
| 3 | sub-agent worker | mechanical script pairs, contracts fully specified in type-inventory |
| 4 | main-session | judgment-heavy prose to house style, spine must land byte-identical |
| 5 | main-session | judgment-heavy; composes every prior artifact |
| 6 | main-session | hand-scoring is human-adjacent judgment; records values into PLAN |
| 7 | main-session | shared convention registry edit, argued rows |
| 8 | main-session | promotion only |

## Open questions

- None blocking. T15 probes are all owned: adversarial fixtures and judge-lens diversity in
  Phase 6; the live no-breadcrumb not-found probe in the Phase 8 sub-topic's Brief (it needs
  a live corpus the offline golden set cannot supply).

## Handoff to implementation

### User-approval gates

- v1 ships with fix mode dark for every class (the min-n arithmetic above); the first
  per-class fix-mode activation, when the growth loop clears the gate, is surfaced to the
  user rather than flipped silently.
- [FALLBACK, confirm or override] `context/persist-findings.md` resolves the detector-findings
  contract through the installed `review` plugin's bundled copy when present, publisher raw
  URL as fallback, refusing only when neither is reachable. This departs from ai-slop's
  URL-only precedent to serve offline runs and org-agnosticism; ai-slop itself is untouched.
- Any scope expansion beyond `plugins/provenance/**` plus the named shared surfaces
  (`.claude-plugin/marketplace.json`, `.claude/settings.json` enablement key, the two
  generated views `docs/CATALOG.md` and `docs/SKILL-CHEAT-SHEET.md`,
  `scripts/skill-leaf-name-registry.txt`, the detector-findings registry and its changelog)
  stops for approval.

### Execution shape ([EXEC-SHAPE] tagged)

- [EXEC-SHAPE] Wave A parallelism (Phases 2, 3, 4) with the scope fences above; sequential
  fallback documented. Basis: file-disjoint per the overlap matrix.
- [EXEC-SHAPE] Q10 budget defaults set from S5 telemetry (values above). Basis: Brief names
  /planning:plan as Q10 arbiter; S5 numbers captured this session.
- [EXEC-SHAPE] Sub-topic promotion of the sweep (Phase 8). Basis: promotion trigger rows
  (commit boundary, item count) in the plan template.
- [EXEC-SHAPE] Q16 defaults 0.95 / 0.8 / 10 and the `accuracy` block defaults (2 nomination
  passes, 3 diverse judges, 1 review agent, deep-research escalation off) as config-key
  values under the user's accuracy-first, all-tunable resolution. Basis: user answers at the
  Q16 round and the mid-plan accuracy directive, both 2026-08-27.
- [EXEC-SHAPE] Fixture exclusion via the config layer rather than unconditional-in-script.
  Basis: the repo's own litigated precedent (#3041, quoted in `.claude/ai-slop.json`), read
  this session.
- [EXEC-SHAPE] Review-agent veto forces `leave-with-reason` without tier reassignment.
  Basis: the type contract's fixed-mapping rule plus the Brief's fail-safe direction (every
  uncertainty falls to a report-only surface, never silence).
- [EXEC-SHAPE] Trigger-less-stamp registry row lands in Phase 7 with the engagement draft
  annotated (option b), rather than deferring the row to the sub-topic. Basis: the
  crosswalk-completeness gate favors registering emitting rules when they ship; the interim
  state is recorded in both artifacts.

### Mechanical work

- Commit boundary per phase, conventional-commit subjects, phase tag flipped in the same
  commit as the phase's changes.
- Verification checkpoint per phase is its Sanity Check block, run before the phase commit.
- Sequential fallback path as stated in Execution shape.

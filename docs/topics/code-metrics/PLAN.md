# code-metrics

Contract for a new `code-metrics` plugin. The `## Brief` section below was locked by
`/planning:interview` on 2026-09-05 after seven rounds, one research pass, one five-corpus
validation pass with independent verifiers, and one blind naming pass. The working ledger, the
research artifacts, and every refutation are in the topic's memory slice
(`.work/code-quality-metrics-plugins/`, not committed). `## Plan` is empty until `/planning:plan`.

## Brief

### TLDR

- Ship one new plugin, `code-metrics`, category `quality`, with five narrow read-only audit lanes
  (`audit-complexity`, `audit-size`, `audit-duplication`, `audit-coverage`, `audit-type-debt`) plus
  `principles` (metric literacy, the SSOT for cross-metric caveats) and `setup` (consumer config).
- It reads source files and existing build artifacts. It never runs tests, never mutates code, and
  never renders a keep-or-retire verdict; CRAP is a derived output of `audit-coverage`, not a lane.
- V1 ecosystem lanes: TypeScript/JavaScript, Python, Bash, Go. C# is deferred behind a runtime probe.
- Thresholds are configurable through the config cascade with cited provenance and no fixed bar;
  measurement is scoped to a change and feeds `verification:measure`, never a repo-wide dashboard.
- Existing owners are untouched: `mutation-testing` (mutants), `testing:audit` (tautological
  tests), `code-tidying:audit-dead-code` (dead code), `coupling:reduce` (coupling), `toolchain:lint`.

### Goal

A consumer of this marketplace can measure the shape of their code, in any of the covered
ecosystems, with one presence-gated skill per concern, and get numbers whose provenance is cited
and whose limits are stated rather than a bar they have to argue with. The plugin covers every
measure from the operator's original list that has no owner today, delegates by pointer to the
three that do, and leaves the consumer able to tune every default per user, team, and repository
without editing the plugin.

### Constraints

- `docs/PLUGIN-PHILOSOPHY.md` Design boundary: one cohesive capability, useful alone, works outside
  this organization; no imports from a sibling plugin; every cross-plugin reference is either a
  declared dependency or presence-gated with a documented fallback per
  `docs/conventions/seam-phrasing/`. A bare unguarded reference is a defect.
- Naming grammar (`docs/PLUGIN-PHILOSOPHY.md` Naming): skill names are imperative verbs with fixed
  contracts (`audit` = read-only report; `setup` = consumer config; `principles` = sanctioned
  knowledge-router noun); the plugin namespace supplies the object. No `check` gate in V1.
- Skills only. No hooks, agents, MCP servers, `bin/`, or workflows; nothing under any
  `plugins/*/hooks/**`, `lib/`, `docs/conventions/hook-*`, `docs/adr/**`, or `scripts/check-*.sh`.
- Native references follow `docs/conventions/native-references/`: a read-time presence gate, never
  an availability assertion, never a marketplace qualifier on a native surface.
- Configuration follows `docs/conventions/config-cascade/` for layering (user-global, team,
  local overlay); this plugin declares its own keys. Deliberately kept findings follow
  `docs/conventions/finding-suppression/`; deliberate replication declared by the target repo
  (for example `scripts/cross-plugin-source-registry.txt`) is an exclusion, not a suppression.
- Each skill description stays under the 1,536-character listing cap and is written for the shared
  1%-of-context listing budget that 243 existing skills already draw from.
- ADR 0003: nothing fires a finding default-on without a measured corpus sweep. V1 reports
  measures and never emits a finding, so the sweep is not owed; that boundary is stated in each
  description.
- ADR 0018: the plugin, not the skill, is the encapsulation boundary for path citation.
- Standards citations: cyclomatic 20 cites ISO/IEC 5055:2021 §8.2.117 (normative); the standard's
  file-size default is §8.2.115, 5% of a function's non-empty lines; 1000 lines per file is
  informative-only in the ISO text and is never cited as ISO-backed. OMG ASCQM is never cited
  without a version and never by page number. Threshold 22 is dropped: no provenance found.
- `scc` is not a cyclomatic collector (substring matching, file-level, 287 of 366 languages with a
  non-empty check list); if its figure appears it is named as scc's own approximation. No skill or
  plugin name uses `static`: coverage is a dynamic measure that this plugin reads statically.
- Validation before any push: `scripts/affected-tests.sh --run`; PRs open as drafts and satisfy
  `.claude/rules/pr-body-contract.md`.

### Acceptance criteria

- `plugins/code-metrics/` exists with exactly seven skills; `/skill-quality:check` exits 0 for each;
  `/plugin-quality:audit` reports no unguarded cross-plugin reference;
  `/docs-hygiene:audit-encapsulation detect` reports none; `scripts/affected-tests.sh --run` is
  clean with zero unmapped files; `.claude-plugin/marketplace.json` carries the entry with
  `category: quality` and `docs/CATALOG.md` is regenerated.
- Every description is under 1,536 characters, opens with the distinguishing object, and the
  `/skill-quality:check listing-budget plugins/*/skills` report is recorded in the plugin README.
- `audit-coverage` parses lcov (2.2 `FNL`/`FNA` records included), Cobertura XML, and coverage.py
  JSON, with a fixture for each, and reads no SQLite; a missing artifact produces a visible warning
  and a documented reduced result, never a silent skip. It reports CRAP by invoking
  `audit-complexity`, using the Savoia and Evans formula `comp^2 * (1 - cov/100)^3 + comp`.
- Defaults ship with citations: cyclomatic 20 (§8.2.117) with 10 (McCabe 1976) and 15 (NIST SP
  500-235) selectable; file length as the plugin's own labelled number with the §8.2.115 alternative
  selectable; cognitive complexity (Campbell, SonarSource), Halstead difficulty (Halstead 1977),
  and CRAP cite their authors and state that no standard sets a threshold. All resolve through the
  config cascade and a fixture proves the team layer overrides the user layer.
- `audit-duplication` reads a declared sanctioned-replication registry before reporting and a
  fixture on this repository's vendored `hook-utils.sh` cluster reports zero debt for it.
- `audit-type-debt` reports a percentage for TypeScript (`type-coverage`) and Python (mypy
  `--any-exprs-report`), reports C# as a labelled occurrence count or omits it, and its description
  states that no standard or CWE anchors the measure.
- `principles` carries the corrected CRAP provenance (introduced July 2007 as "Change Risk Analysis
  and Predictions", later renamed by its authors to "Change Risk Anti-Patterns"), states that CRAP
  is not a validated change-risk predictor, and states the Lewis 2013 mechanism (an unactionable
  score is ignored). The cross-metric caveats appear once, here.
- Each lane names its collectors per ecosystem with presence gates and fallbacks, and a lane with
  no collector for an ecosystem says so and continues rather than stalling.
- No file under `plugins/*/hooks/**`, `lib/`, `docs/conventions/`, `docs/adr/`, or
  `scripts/check-*.sh` is changed by the plugin's PR.

### Captured assumptions

- Current ISO vocabulary prefers "measure" over "metric" (MEDIUM; preview-sourced). Did not change
  the name, which the tooling register decided. Revisit if ISO/IEC 25000-23.2 publishes with
  contrary vocabulary.
- Test coverage sits under Reliability/Maturity in ISO/IEC 25023:2016 and its id is `RMa-4-S`
  (MEDIUM; the normative body is paywalled). Revisit if the body is obtained or 25000-23.2
  publishes.
- Official guidance is silent on skills-per-plugin (five official surfaces unchecked). Revisit if
  any of those surfaces states a rule.
- OMG ASCQM v1.1 keeps the §8.2.115 and §8.2.117 defaults and clause-7 numbering (verified by diff).
  Revisit on ASCQM v1.2 or an ISO/IEC 5055 revision; the systematic review closed 2026-06-05.
- Simian's Apache-2.0 relicensing rests on the vendor's own publications. Revisit if a third party
  confirms before the plugin depends on it.
- `Microsoft.CodeAnalysis.Metrics` 5.6.0 ships a .NET Framework 4.7.2 executable and is
  Windows-shaped as packaged. Revisit when a Linux runtime probe or the `CodeAnalysisMetricData`
  API route is tested.

### Out-of-scope

- The C# complexity lane (Q21). Follow-up whose first step is the runtime probe above.
- Any edit-time gate or hook. That is the hook lanes' territory and the hook-budget contract.
- A repo-wide dashboard, trend store, or history; measurement is per change.
- Surviving mutants, dead code, tautological tests, coupling reduction, and linting, which keep
  their existing owners; the plugin points at them.
- The mutation-score error-axis non-equivalence finding (PIT and Infection count errors as
  detected, Stryker excludes them), passed to `mutation-testing` rather than acted on here.
- The nine unlinked "dead code" mentions across other plugins; that is `discipline:point-dont-copy`
  territory.
- Cross-plugin reference edits (`verification/skills/measure/context/metrics.md`,
  `testing/skills/write/context/organize.md`, `mutation-testing/skills/principles`), which ship as a
  separate PR per Q15, including the missing gate and fallback at `organize.md:63-66`.

### Deferred questions

- Q22, Branch strategy: the session is bound to one branch, which already carries the shipped
  skill-doctor unit (`b92f6ead`), while Q15 requires the plugin to ship as a separate PR, defer
  until the /planning:plan approval gate; **arbiter: USER-RESERVED**
- Q23, A dedicated `skill-doctor` row in `docs/native-surfaces/records.json` needs an
  `upstream-source` pin (the `anthropics/claude-code` CHANGELOG commit SHA), which is outside this
  session's repository scope, defer until the operator supplies the SHA or adds the repository to
  scope; **arbiter: USER-RESERVED**

## Plan

<!-- populated by /planning:plan -->

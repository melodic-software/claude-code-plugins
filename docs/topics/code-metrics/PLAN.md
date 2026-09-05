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
- Validation before any push: `scripts/affected-tests.sh --run`. One branch
  (`claude/code-quality-metrics-plugins-p99tkz`) and one draft PR, opened only after all of the
  work is done and validated (Q22); the PR body satisfies `.claude/rules/pr-body-contract.md`.

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
- Nothing else in the plugin's own tree. The cross-plugin reference edits
  (`verification/skills/measure/context/metrics.md`, `testing/skills/write/context/organize.md`,
  `mutation-testing/skills/principles`, including the missing gate and fallback at
  `organize.md:63-66`) are in scope of the same branch and PR per Q22, as their own commits after
  the plugin's files land.

### Deferred questions

- Q23, A dedicated `skill-doctor` row in `docs/native-surfaces/records.json` needs an
  `upstream-source` pin (the `anthropics/claude-code` CHANGELOG commit SHA), which is outside this
  session's repository scope, defer until the operator supplies the SHA or adds the repository to
  scope; **arbiter: USER-RESERVED**

## Plan

Drafted by `/planning:plan` on 2026-09-05 against the Brief above and the design slice in
[`design/`](design/) (`design-threads.md` T1 to T21, `contracts.md`, `module-boundary.md`,
`domain-model.md`). Scale: **Large** (a new plugin of roughly sixty files, four cross-cutting
registry edits, three sibling-plugin edits), so the full template with stress-test applies.

### Goal

**What.** Ship `plugins/code-metrics/` (seven skills, shared scripts, fixtures, suites, README,
changelog), register it in the marketplace and its generated indexes, and land the three
presence-gated cross-plugin pointers, all on this branch, as one draft PR opened when everything
below is green.
**Why.** Five measures on the operator's list have no owner in the marketplace; the Brief's design
gives them one plugin that reads code and artifacts, cites provenance, and never renders a verdict.

### Standards grounding

No `.claude/standards.yaml` and no `docs/standards/README.md` exist at the resolution root, and no
personal layer exists at `~/.claude/standards/`, so the ladder's inference rung applies: the
repository's own instruction surfaces are the standards. Nothing was persisted (non-interactive
session; the assumption is surfaced here).

| Surface | Sections loaded | Layer provenance |
|---|---|---|
| `docs/PLUGIN-PHILOSOPHY.md` | Design boundary, Naming, Configuration ownership, Setup is explicit and repeatable, Prerequisites and failure behavior, Evidence and validation, Fresh-eyes checkpoints | team (repository) |
| `docs/conventions/{config-cascade,seam-phrasing,native-references,finding-suppression,ecosystem-commands,upstream-drift,shell-test-helpers,invocation-mode}/README.md` | whole contracts | team |
| `docs/CATALOG-TAXONOMY.md` | Vocabulary, Assignment principle | team |
| `.claude/rules/{ruff-pin,vendor-docs-are-not-style,pr-body-contract,catalog-taxonomy}.md` | ambient (fired) | team |
| `plugins/skill-quality/scripts/check-skill.sh` header | the 25 skill rules | team (tooling as standard) |
| `scripts/affected-tests.sh` header, `scripts/affected-tests-no-suite.txt` | mapping rules R1 to R6, the no-suite allowlist | team |

### Baseline (measurable acceptance item)

The Brief asks for the listing-budget report in the README. Captured before any code-metrics skill
exists (raw capture in the topic's memory slice, never committed):

| Measure | Baseline 2026-09-05 | Target |
|---|---|---|
| Listing-eligible skills | 182 across 74 roots | 188 (six new; `setup` is model-invisible) |
| Aggregate listing chars | 135,541 (already 16.9x the documented 8,000 default) | delta from the six new descriptions recorded in the README, each entry under 1,536 |

### Test strategy

Style, per `/tdd:principles` (output-based first; stub only unmanaged out-of-process dependencies;
split high-complexity-many-collaborator code): parsers, the CRAP formula, config resolution, and
JSON assembly are pure functions from input files to output and get **output-based unit tests**
(`test_*.py`, pytest). Collectors and the dispatcher are the imperative shell around out-of-process
tools, so their suites (`*.test.sh`) **stub the tools** with a fixture `bin/` prepended to `PATH`
whose fake executables replay captured real output, and assert on the printed JSON. Red first: each
phase's first commit is the failing suite against the fixture, then the script.

Test boundaries (all newly introduced; each is the script's command line, one seam per script):

| Boundary | Drives | Existing? |
|---|---|---|
| `scripts/resolve-config.py <layers...>` | cascade merge, per-key override, provenance layer | new |
| `scripts/detect-lanes.sh <files...>` | extension map, consumer `globs` override, `enabled: false` | new |
| `scripts/collectors/<tool>.sh probe\|measures\|collect\|install_hint` | presence gate, output translation | new |
| `scripts/parsers/{lcov,cobertura,coverage_py_json}.py` | `parse(path) -> {file: {line: hits}}` | new |
| `skills/audit-coverage/scripts/crap.py` | the formula, `null` on no executable lines | new |
| `scripts/dispatch.sh <skill> <measures> [scope]` | end-to-end: scope, run table, exit codes 0/2/3 | new |
| `skills/*/scripts/run.sh` | argument parsing to dispatch | new |
| `skills/setup/scripts/check.sh` | probe table, config validation, tracked-file guard | new |

Fixtures are real captures where the sandbox can run the tool (probed 2026-09-05: `lizard`,
`radon`, `multimetric` via `uvx`; `jscpd` via `npx`; `go install` for `gocyclo`, `gocognit`,
`dupl`, `scc`; Java is present for PMD CPD) and hand-written from documented formats otherwise,
labelled as such in the fixture header. Edge cases owed a case each: lcov 2.2 `FNL`/`FNA` without
`FN`; Cobertura with a non-conforming DTD; coverage.py JSON with `excluded_lines`; a function with
no executable lines (CRAP `null`); all lanes unavailable (exit 0, every `run[]` row non-`ok`); a
collector that probes but fails in `collect` (exit 3); a registry-sanctioned clone cluster
(excluded, listed); team layer overriding user layer; `enabled: false` under `--all`.

### Alternatives considered

| Alternative | Why rejected | Switch condition |
|---|---|---|
| One `audit` skill with a measure argument instead of five | The listing budget prices a skill at its description, not its body; five narrow descriptions route better and each lane's prerequisites differ. Brief Q17. | A skill-count cap appears in official guidance, or the listing budget starts charging per skill rather than per description. |
| `scc` as the cyclomatic collector | Substring matching, file level, wrong by construction (Brief). | scc ships a parsed per-function cyclomatic mode. |
| `lizard` only, dropping native tools | Loses the numbers a repository's own ESLint or radon config already produces; teams read those. | lizard adds Bash and cognitive complexity. |
| Parsing coverage.py's `.coverage` SQLite | Documented as an internal, unstable schema. | coverage.py publishes the schema as stable. |
| A `check` gate in V1 | ADR 0003 requires a measured precision sweep before anything default-on fires. | A corpus sweep is run and recorded. |
| Shipping a C# occurrence count for type debt | Not comparable to the two true percentages; invites the comparison it cannot support (T9). | A Roslyn analyzer emitting an identifier-level ratio exists. |
| Per-skill copies of the shared scripts | Duplication inside one plugin with no sync gate. | The encapsulation audit starts flagging plugin-level `scripts/` citations. |
| A separate PR for the cross-plugin edits (Q15 as first answered) | Superseded by Q22: one branch, one PR. | The operator reverses Q22. |

### Risks and mitigations

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| A collector's real output differs from the captured fixture on another version | Med | Med | Each adapter pins the version it was captured against in `reference/collectors.md` with a recheck trigger; `probe` prints the version into `run[]`. |
| `affected-tests.sh` maps a new file to nothing and fails closed | High without discipline | Low | Every code file lands with its co-located suite in the same commit; Phase sanity checks run `--explain`. |
| Description drift past 1,536 chars or a `Use when` without single quotes | Med | Low | `check-skill.sh` per skill in every phase's sanity check. |
| ESLint-based collectors depend on the consumer's ESLint config | High | Low | They resolve only when `eslint` is on PATH or in `node_modules/.bin` and a config exists; otherwise `unavailable` with reason, and `lizard` covers cyclomatic anyway. |
| Peer sessions touch `verification`, `testing`, or `mutation-testing` concurrently | Low | Med | Announce Phase 10 files to peers before editing; take the next patch version at edit time, not at plan time. |
| The em-dash ratchet fails on a new file | Med | Low | Add the plugin's globs to `em-dash-purged-paths.txt` in Phase 9 and run the check; write to the house style from the start. |
| `check-orphaned-fixtures.sh` flags eval fixtures | Low | Low | Script fixtures live under the plugin's `scripts/fixtures/`, outside `evals/fixtures/`; eval cases carry no fixture files. |
| Sandbox cannot reach a tool to capture a fixture | Low (probed) | Low | Hand-write from the documented format and label the fixture header `unverified against a live run` (`[FALLBACK]` below). |

### Phases

Execution order is integration-first: Phase 1 is the walking skeleton (one skill, one measure, no
external tool) proven end to end before any collector lands.

### Phase 1: Walking skeleton, `audit-size` end to end [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/.claude-plugin/plugin.json` | CREATE | name, `0.1.0`, description, author, MIT, keywords; no `userConfig` (T4) |
| [ ] `plugins/code-metrics/README.md` | CREATE | lead, Works in any repo, Requirements (collector table), Install, Configuration, License; listing-budget section placeholder filled in Phase 9 |
| [ ] `plugins/code-metrics/CHANGELOG.md` | CREATE | Keep a Changelog, `## [0.1.0]` |
| [ ] `plugins/code-metrics/reference/report-schema.md` | CREATE | `code-metrics/v1` field reference from `design/contracts.md` §2 |
| [ ] `plugins/code-metrics/reference/collectors.md` | CREATE | stamped table; rows filled per phase |
| [ ] `plugins/code-metrics/scripts/detect-lanes.sh` + `detect-lanes.test.sh` | CREATE | extension map; consumer `globs`; `enabled: false` |
| [ ] `plugins/code-metrics/scripts/report.py` + `test_report.py` | CREATE | JSON assembly, markdown rendering, exit-code taxonomy |
| [ ] `plugins/code-metrics/scripts/dispatch.sh` + `dispatch.test.sh` | CREATE | scope resolution (change, paths, `--all`), collector ladder, `run[]` rows |
| [ ] `plugins/code-metrics/scripts/collectors/line-counter.sh` + `.test.sh` | CREATE | bundled counter: `lines_total`, `lines_non_blank`, labelled comment-agnostic |
| [ ] `plugins/code-metrics/scripts/collectors/scc.sh` + `.test.sh` | CREATE | `scc --format json` translation; probe |
| [ ] `plugins/code-metrics/scripts/fixtures/{sources/,tool-output/scc.json,bin/scc}` | CREATE | sample files per lane; captured scc output; fake bin |
| [ ] `plugins/code-metrics/skills/audit-size/{SKILL.md,scripts/run.sh,scripts/run.test.sh,evals/evals.json}` | CREATE | the skill; `size.mode` file-lines and iso-8.2.115 |

Steps:

1. Red: `dispatch.test.sh` asserts a `code-metrics/v1` document for a fixture tree with `scc`
   absent from PATH (line-counter used, `run[]` row names it) and present (fake bin).
2. Green: `detect-lanes.sh`, `report.py`, `dispatch.sh`, the two collectors, `run.sh`.
3. `SKILL.md` for `audit-size` to the frontmatter rules in `design/module-boundary.md`; the
   description states the default reference (1000, plugin's own) and that no finding is emitted.

**Sanity Check:**

- `bash plugins/code-metrics/skills/audit-size/scripts/run.sh --all plugins/code-metrics/scripts/fixtures/sources | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["schema"]=="code-metrics/v1" and d["skill"]=="audit-size" and d["run"]'` exits 0
- `bash plugins/skill-quality/scripts/check-skill.sh plugins/code-metrics/skills/audit-size` exits 0
- `scripts/affected-tests.sh --explain` lists zero unmapped files for the phase's diff; `--run` exits 0
- `python -m pytest -q plugins/code-metrics` exits 0; `scripts/run-ruff.sh check plugins/code-metrics` exits 0
- `shellcheck --rcfile .shellcheckrc plugins/code-metrics/scripts/*.sh plugins/code-metrics/scripts/collectors/*.sh plugins/code-metrics/skills/*/scripts/*.sh` exits 0

### Phase 2: Config cascade and `setup` [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/scripts/resolve-config.py` + `test_resolve_config.py` | CREATE | three layers, per-key override, provenance layer per key, unknown keys inert |
| [ ] `plugins/code-metrics/reference/config.md` | CREATE | every key from `design/contracts.md` §1, merge form declared next to the keys |
| [ ] `plugins/code-metrics/skills/setup/{SKILL.md,scripts/check.sh,scripts/check.test.sh,templates/config-template.yaml,evals/evals.json}` | CREATE | `check` probes collectors and validates config; `apply` writes the team file; `disable-model-invocation: true`; never installs, never edits `.gitignore` |
| [ ] `plugins/code-metrics/scripts/fixtures/config/{user.yaml,team.yaml,local.yaml}` | CREATE | the team-overrides-user fixture the Brief requires |
| [ ] `plugins/code-metrics/scripts/dispatch.sh` | MODIFY | read thresholds and lane overrides through `resolve-config.py` |

**Sanity Check:**

- `python3 plugins/code-metrics/scripts/resolve-config.py plugins/code-metrics/scripts/fixtures/config/user.yaml plugins/code-metrics/scripts/fixtures/config/team.yaml | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["complexity"]["cyclomatic"]["reference"]==d["_provenance"]["complexity.cyclomatic.reference"]["value"] and d["_provenance"]["complexity.cyclomatic.reference"]["layer"]=="team"'` exits 0
- `grep -c 'per-key override' plugins/code-metrics/reference/config.md` returns at least 1
- `grep -c '^disable-model-invocation: true' plugins/code-metrics/skills/setup/SKILL.md` returns 1
- `bash plugins/code-metrics/skills/setup/scripts/check.sh` in a scratch repo with no config exits 0 and prints one row per collector with `missing` or a version
- the Phase 1 sanity-check commands, re-run

### Phase 3: `audit-complexity` [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/scripts/collectors/{lizard,radon,eslint-complexity,sonarjs,gocyclo,gocognit,shellmetrics,multimetric}.sh` + eight `.test.sh` | CREATE | T1 ladder; each translates to `measures[]` rows with `start_line`/`end_line` |
| [ ] `plugins/code-metrics/scripts/fixtures/tool-output/{lizard.csv,radon-cc.json,radon-hal.json,eslint.json,sonarjs.json,gocyclo.txt,gocognit.json,shellmetrics.csv,multimetric.json}` and matching `fixtures/bin/*` | CREATE | captured where the sandbox can run the tool, else documented-format with a labelled header |
| [ ] `plugins/code-metrics/skills/audit-complexity/{SKILL.md,scripts/run.sh,scripts/run.test.sh,evals/evals.json}` | CREATE | cyclomatic, cognitive, halstead; references with provenance (20 §8.2.117; 10; 15; cognitive and Halstead `null`) |
| [ ] `plugins/code-metrics/reference/collectors.md` | MODIFY | eight stamped rows |

**Sanity Check:**

- with `PATH=plugins/code-metrics/scripts/fixtures/bin:$PATH`, `bash plugins/code-metrics/skills/audit-complexity/scripts/run.sh --all plugins/code-metrics/scripts/fixtures/sources | python3 -c 'import json,sys; d=json.load(sys.stdin); t=[x for x in d["thresholds"] if x["measure"]=="cyclomatic"][0]; assert t["reference"]==20 and "8.2.117" in t["provenance"]; assert any(r["lane"]=="python" and r["measure"]=="cognitive" and r["status"]=="unavailable" for r in d["run"])'` exits 0
- `grep -c 'scc' plugins/code-metrics/skills/audit-complexity/SKILL.md` returns 0 (scc never named as a complexity source)
- each of the eight `.test.sh` suites exits 0 under `scripts/affected-tests.sh --run`; `check-skill.sh` exits 0 for the skill

### Phase 4: `audit-coverage` with CRAP [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/scripts/parsers/{lcov,cobertura,coverage_py_json}.py` + three `test_*.py` | CREATE | one interface `parse(path) -> {file: {line: hits}}`; lcov handles `FNL`/`FNA`, `FN`/`FNDA`, `MCDC`; Cobertura tolerant of DTD drift |
| [ ] `plugins/code-metrics/scripts/fixtures/coverage/{lcov-1x.info,lcov-2.2.info,cobertura.xml,coverage-py.json}` | CREATE | one per format, the 2.2 file with `FNL`/`FNA` and no `FN` |
| [ ] `plugins/code-metrics/skills/audit-coverage/{SKILL.md,scripts/run.sh,scripts/run.test.sh,scripts/crap.py,scripts/test_crap.py,evals/evals.json}` | CREATE | artifact discovery and explicit paths; per-file and per-function coverage; CRAP by invoking the sibling `audit-complexity` run script; missing artifact is a visible warning plus a reduced result |
| [ ] `plugins/code-metrics/reference/collectors.md` | MODIFY | rows for the three formats with the lcov 2.2 and coverage.py SQLite stamps |

**Sanity Check:**

- `python3 -c 'import sys; sys.path.insert(0,"plugins/code-metrics/scripts/parsers"); import lcov; d=lcov.parse("plugins/code-metrics/scripts/fixtures/coverage/lcov-2.2.info"); assert d and all(isinstance(v,dict) for v in d.values())'` exits 0
- `python3 plugins/code-metrics/skills/audit-coverage/scripts/crap.py --comp 5 --cov 0` prints `130`; `--comp 5 --cov 100` prints `5`; `--comp 5 --cov null` prints `null`
- `grep -rc 'sqlite\|\.coverage\b' plugins/code-metrics/scripts/parsers/*.py` returns 0 for every file
- `bash plugins/code-metrics/skills/audit-coverage/scripts/run.sh --all plugins/code-metrics/scripts/fixtures/sources --artifacts /nonexistent.info` exits 0 and its JSON has a `run[]` row with `status: "unavailable"` naming the missing artifact
- `check-skill.sh` exits 0; `python -m pytest -q plugins/code-metrics` exits 0

### Phase 5: `audit-duplication` [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/scripts/collectors/{jscpd,cpd,dupl}.sh` + three `.test.sh` | CREATE | jscpd JSON; CPD XML translated; dupl for Go; Bash only via jscpd |
| [ ] `plugins/code-metrics/scripts/fixtures/{tool-output/jscpd.json,tool-output/cpd.xml,tool-output/dupl.txt,registry/cluster.txt,sources/cluster/{a,b}/hooks/hook-utils.sh}` | CREATE | a byte-identical two-plugin cluster and the registry line that sanctions it |
| [ ] `plugins/code-metrics/skills/audit-duplication/{SKILL.md,scripts/run.sh,scripts/run.test.sh,evals/evals.json}` | CREATE | debt after exclusions; `excluded[]` names the registry line |

**Sanity Check:**

- with the fake `jscpd` on PATH, `bash plugins/code-metrics/skills/audit-duplication/scripts/run.sh --all plugins/code-metrics/scripts/fixtures/sources/cluster --registry plugins/code-metrics/scripts/fixtures/registry/cluster.txt | python3 -c 'import json,sys; d=json.load(sys.stdin); assert d["summary"]["duplicated_lines"]==0 and len(d["excluded"])>=1'` exits 0
- the same command without `--registry` reports `duplicated_lines` greater than 0
- `check-skill.sh` exits 0; suites exit 0

### Phase 6: `audit-type-debt` [TODO]

Review: code-design

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/scripts/collectors/{type-coverage,mypy-report}.sh` + two `.test.sh` | CREATE | TS percentage; Python `--any-exprs-report` counts and Cobertura type-check coverage |
| [ ] `plugins/code-metrics/scripts/fixtures/tool-output/{type-coverage.json,mypy-any-exprs.txt}` | CREATE | captured |
| [ ] `plugins/code-metrics/skills/audit-type-debt/{SKILL.md,scripts/run.sh,scripts/run.test.sh,evals/evals.json}` | CREATE | description states no standard or CWE anchors the measure; C# row `not-applicable` with the T9 sentence |

**Sanity Check:**

- `grep -c 'no standard or CWE' plugins/code-metrics/skills/audit-type-debt/SKILL.md` returns at least 1 (in the description line)
- with fake bins, the run script's JSON has `values.type_coverage_pct` for `typescript` and `values.any_expressions` for `python`, and a `dotnet` row with `status: "not-applicable"`
- `check-skill.sh` exits 0; suites exit 0

### Phase 7: `principles` [TODO]

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/skills/principles/{SKILL.md,evals/evals.json}` | CREATE | knowledge router: measure definitions, thresholds and their provenance, CRAP, literature, the cross-metric caveats (once, here), gated pointers to the five owners the Brief names |
| [ ] `plugins/code-metrics/skills/principles/reference/{measures.md,thresholds.md,crap.md,literature.md}` | CREATE | CRAP provenance as the Brief states it; Lewis 2013 mechanism; McCabe "reasonable, but not magical"; NIST six practices; ISO clause map; "not a validated change-risk predictor" |

**Sanity Check:**

- `grep -c 'Change Risk Analysis and Predictions' plugins/code-metrics/skills/principles/reference/crap.md` returns at least 1 and `grep -c 'Change Risk Anti-Patterns' ...` returns at least 1
- `grep -c 'not a validated' plugins/code-metrics/skills/principles/reference/crap.md` returns at least 1
- `grep -c 'Lewis' plugins/code-metrics/skills/principles/reference/literature.md` returns at least 1
- `grep -c 'if that plugin is installed\|when the .* plugin is installed' plugins/code-metrics/skills/principles/SKILL.md` returns at least 5
- `check-skill.sh` exits 0; the SKILL.md is under 200 lines

### Phase 8: README, evals quality, house style [TODO]

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/code-metrics/README.md` | MODIFY | Requirements table complete; Configuration section points at `reference/config.md`; skill list of exactly seven |
| [ ] `plugins/code-metrics/skills/*/evals/evals.json` | MODIFY | pass `check-evals-quality.sh` |
| [ ] every `plugins/code-metrics/**/*.md` | KEEP or MODIFY | em-dash free, typos clean, markdownlint clean |

**Sanity Check:**

- `bash plugins/skill-quality/scripts/check-evals-quality.sh plugins/code-metrics/skills/*/evals/evals.json` exits 0
- `bash plugins/ai-slop/skills/audit/scripts/detect.sh --paths-file <(ls plugins/code-metrics/README.md plugins/code-metrics/skills/*/SKILL.md)` reports zero findings
- `grep -rn '—' plugins/code-metrics --include='*.md' | wc -l` prints 0
- `bash scripts/check-skill-count-claims.sh` exits 0

### Phase 9: Registration and generated indexes [TODO]

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `.claude-plugin/marketplace.json` | MODIFY | entry after the `codebase-health` neighbour by the file's own ordering, `category: quality`, tags |
| [ ] `.claude/settings.json` | MODIFY | `"code-metrics@melodic-software": true` in byte order |
| [ ] `docs/CATALOG.md`, `docs/SKILL-CHEAT-SHEET.md` | MODIFY | regenerated, never hand-edited |
| [ ] `scripts/skill-leaf-name-registry.txt` | MODIFY | `principles code-metrics,mutation-testing,tdd` |
| [ ] `scripts/em-dash-purged-paths.txt` | MODIFY | `plugins/code-metrics/README.md` and `plugins/code-metrics/skills/*/SKILL.md` |
| [ ] `plugins/code-metrics/README.md` | MODIFY | the listing-budget section: baseline 135,541 over 182 skills, the after figure, per-entry chars for the six eligible skills |

**Sanity Check:**

- `node scripts/generate-catalog.mjs --check` exits 0; `node scripts/generate-cheatsheet.mjs --check` exits 0
- `bash scripts/validate-plugins.sh` exits 0
- `bash scripts/check-plugin-catalog-enablement.sh` exits 0; `bash scripts/check-skill-leaf-names.sh --check` exits 0; `bash scripts/check-purged-em-dashes.sh --check` exits 0; `bash scripts/check-cross-plugin-source-drift.sh --check` exits 0; `bash scripts/check-orphaned-fixtures.sh --check` exits 0
- `bash plugins/skill-quality/scripts/check-listing-budget.sh plugins/*/skills | grep -c '188 listing-eligible'` returns 1
- `grep -c 'code-metrics' docs/CATALOG.md` returns at least 1

### Phase 10: Cross-plugin pointers [TODO]

Announce the three files to the peer sessions first (`list_sessions mine:true`, then the
create/fire/delete trigger sequence), and take each plugin's next patch version at edit time.

Files:

| File | Action | Rationale |
|---|---|---|
| [ ] `plugins/verification/skills/measure/context/metrics.md` | MODIFY | in the proxy table's "How to check" cells and the `baseline` step: "invoke `/code-metrics:audit-<measure>` when the `code-metrics` plugin is installed; otherwise the manual counts above" |
| [ ] `plugins/verification/{.claude-plugin/plugin.json,CHANGELOG.md}` | MODIFY | next patch, Changed entry |
| [ ] `plugins/testing/skills/write/context/organize.md` | MODIFY | lines 63-66: add the missing gate and fallback to the two `dotnet-test` references, and point CRAP at `/code-metrics:audit-coverage` when that plugin is installed |
| [ ] `plugins/testing/{.claude-plugin/plugin.json,CHANGELOG.md}` | MODIFY | next patch, Fixed entry |
| [ ] `plugins/mutation-testing/skills/principles/SKILL.md` or `reference/metrics.md` | MODIFY | one gated sentence: cross-metric caveats (coverage, CRAP, complexity) are owned by `/code-metrics:principles` when that plugin is installed; the oracle-gap material stays here |
| [ ] `plugins/mutation-testing/{.claude-plugin/plugin.json,CHANGELOG.md}` | MODIFY | next patch, Changed entry |

**Sanity Check:**

- `grep -n 'dotnet-test' plugins/testing/skills/write/context/organize.md | grep -vc 'installed'` prints 0
- `grep -c 'code-metrics' plugins/verification/skills/measure/context/metrics.md` returns at least 1 and every such line also matches `installed`
- `bash scripts/check-changelog-parity.sh --check-bump origin/main` exits 0
- `scripts/affected-tests.sh --run` exits 0 for the phase's diff

### Phase 11: Fresh-eyes review, full validation, draft PR [TODO]

Review: architecture, code-design

1. Dispatch `review:code-reviewer` (fresh context) over the branch diff; fix confirmed findings.
2. `/plugin-quality:audit code-metrics` and `/docs-hygiene:audit-encapsulation detect`; fix
   confirmed findings.
3. Full gates: `scripts/affected-tests.sh --run --explain`, `bash scripts/validate-plugins.sh`,
   `shellcheck` over the plugin, `scripts/run-ruff.sh check plugins/code-metrics`,
   `python -m pytest -q plugins/code-metrics`, `bash scripts/run-plugin-tests.sh` filtered to
   the plugin.
4. `/planning:plan close-out`, then the draft PR through `/source-control:commit` conventions with
   the body to `.claude/rules/pr-body-contract.md` (`No related issue: <reason>` unless an issue is
   supplied; `## Summary`, `## Fix`, `## Verification`, `## Related`), and a peer announcement
   naming branch, title, and files.

**Sanity Check:**

- every command in step 3 exits 0 on the branch head
- `plugins/docs-hygiene/skills/audit-encapsulation/scripts/detect.sh` reports zero candidates under `plugins/code-metrics`
- the PR exists as a draft and its body's first line matches `^(Closes|Fixes|Resolves) #[0-9]+|^No related issue:`
- `ls plugins/code-metrics/skills | wc -l` prints 7

## Blast radius

Blast radius: **MEDIUM**
Stress-test needed: **Yes, invoking /planning:devils-advocate in a fresh-context sub-agent**
Reason: roughly sixty new files but all inside one new plugin directory plus four registry edits
and three one-line sibling-plugin pointers; no hooks, CI, or shared libraries change, and every
step is a `git revert` away. The triggers that match are "new skill creation that composes other
skills" (audit-coverage composes audit-complexity; principles points at five owners) and a
multi-step implementation touching tool output formats the sandbox cannot fully verify.

## Stress-test summary

<!-- Step 3 reviewer findings and Step 4 devils-advocate outcome recorded here -->

## Execution shape

### Phase file-overlap matrix

| Phase | Files | Overlaps with |
|---|---|---|
| 1 | plugin root files, `scripts/{dispatch,detect-lanes,report}`, `collectors/{line-counter,scc}`, `skills/audit-size` | 2 (dispatch.sh), 9 (README) |
| 2 | `scripts/resolve-config.py`, `reference/config.md`, `skills/setup`, `scripts/dispatch.sh` | 1 |
| 3 | eight collectors, `skills/audit-complexity`, `reference/collectors.md` | 4, 5, 6 (collectors.md rows only) |
| 4 | `scripts/parsers/*`, `skills/audit-coverage`, `reference/collectors.md` | 3 (reads its run script; collectors.md) |
| 5 | three collectors, `skills/audit-duplication`, cluster fixture | 3, 4, 6 (collectors.md rows only) |
| 6 | two collectors, `skills/audit-type-debt` | 3, 4, 5 (collectors.md rows only) |
| 7 | `skills/principles` | none |
| 8 | README, evals, prose sweep | 9 |
| 9 | marketplace, settings, catalog, cheat-sheet, registries, README | 8 |
| 10 | three sibling plugins | none |
| 11 | none (review and gates) | all, read-only |

### Dependency graph

- 1 → 2 (dispatch gains config resolution) → {3, 5, 6, 7} (all need the dispatcher and config).
- 3 → 4 (CRAP needs the complexity run script and its `measures[]` shape).
- {3, 4, 5, 6, 7} → 8 → 9 → 11; 10 is independent of 3 to 9 but sequenced after 9 so the pointer
  targets exist when a reviewer follows them, and before 11.
- Integration-first: Phase 1 is the end-to-end slice.

### Recommended shape

> Wave A (sequential, main session): 1 → 2.
> Wave B (parallel sub-agent workers, one message): 3, 5, 6, 7. Each is file-disjoint except for
> appending rows to `reference/collectors.md`; to remove that overlap each worker writes its rows
> to `reference/collectors/<skill>.md` fragments and the main session concatenates them into
> `collectors.md` at the start of Phase 8.
> Wave C (sequential after 3 returns, may overlap the rest of Wave B): 4.
> Wave D (sequential, main session): 8 → 9 → 10 → 11.
> Cost note: four parallel workers in Wave B multiply token usage roughly fourfold for that wave
> against an estimated 1,200 lines of independent work; the saving is wall-clock, not tokens.

### Scope-fencing tables (Wave B and C)

| Agent | Phase | ALLOWED files | LOC |
|---|---|---|---|
| A1 | 3 | `plugins/code-metrics/scripts/collectors/{lizard,radon,eslint-complexity,sonarjs,gocyclo,gocognit,shellmetrics,multimetric}.sh` and `.test.sh`; `scripts/fixtures/tool-output/<those>`; `scripts/fixtures/bin/<those>`; `skills/audit-complexity/**`; `reference/collectors/audit-complexity.md` | ~500 |
| A2 | 5 | `scripts/collectors/{jscpd,cpd,dupl}.sh` and `.test.sh`; matching fixtures; `scripts/fixtures/registry/**`; `scripts/fixtures/sources/cluster/**`; `skills/audit-duplication/**`; `reference/collectors/audit-duplication.md` | ~300 |
| A3 | 6 | `scripts/collectors/{type-coverage,mypy-report}.sh` and `.test.sh`; matching fixtures; `skills/audit-type-debt/**`; `reference/collectors/audit-type-debt.md` | ~200 |
| A4 | 7 | `skills/principles/**` | ~250 |
| A5 | 4 | `scripts/parsers/**`; `scripts/fixtures/coverage/**`; `skills/audit-coverage/**`; `reference/collectors/audit-coverage.md` | ~450 |

**Each agent FORBIDDEN:** any file outside its ALLOWED list; `PLAN.md`; `scripts/dispatch.sh`,
`scripts/report.py`, `scripts/detect-lanes.sh`, `scripts/resolve-config.py` (report a needed
change instead); other agents' territory; staging, commit, or push.

**Each agent reports at end:** work items completed, per-criterion Sanity Check verdict, actual
LOC delta, and any fixture labelled `unverified against a live run`.

```text
DIVERGENCE ESCALATION (mandatory): if reality diverges from this brief —
a precondition fails, a file/symbol named here is absent or different than
described, scope is blocked, or a design question arises mid-task — STOP.
Do not improvise, fix forward, or expand scope. Report to the orchestrator:
what you found, what the brief expected, and the exact state of your work
(files touched, edits applied / not applied). Await a revised brief.
```

### Sequential fallback

> If a scope-fence violation, a concurrent-edit race, or an agent reporting cannot-complete
> occurs, abort that agent and run its phase sequentially in the main session (3 → 5 → 6 → 7 → 4
> order); the other workers continue.

### Per-phase routing table

| Phase | Surface | Basis |
|---|---|---|
| 1 | main-session | sets the contracts every later phase reads; judgment-heavy |
| 2 | main-session | cascade semantics and the setup interview shape need conversation context |
| 3 | sub-agent worker (A1) | mechanical: eight adapters to one contract, fixture capture |
| 4 | sub-agent worker (A5) | file-disjoint after Phase 3; parser and formula work with fixed inputs |
| 5 | sub-agent worker (A2) | mechanical, file-disjoint |
| 6 | sub-agent worker (A3) | mechanical, file-disjoint |
| 7 | sub-agent worker (A4) | prose from the validated corpora; file-disjoint |
| 8 | main-session | cross-skill consistency judgment |
| 9 | main-session | registry edits touch shared files |
| 10 | main-session | peer coordination and sibling-plugin judgment |
| 11 | main-session, with fresh-context reviewers dispatched | the fresh-eyes rule |

Agent teams are not routed: the workers do not need to message each other.

## Open questions

- Q23 (the `skill-doctor` store row's upstream-source pin) stays deferred and does not block any
  phase.

## Handoff to implementation

### User-approval gates

- `[FALLBACK — confirm or override]` A fixture the sandbox cannot capture from a live tool run is
  hand-written from the tool's documented output format and its header says
  `unverified against a live run`; the adapter's `reference/collectors.md` row carries the same
  label until someone runs the tool. Implementation surfaces every such fixture in its phase
  report.
- `[FALLBACK — confirm or override]` If a peer session is mid-edit on one of the three Phase 10
  files when the announcement goes out, Phase 10 waits for that peer's push and rebases on it
  rather than editing concurrently; the PR is not opened until Phase 10 lands.
- Any scope expansion (a sixth audit lane, a `check` gate, a hook) stops and asks.

### Execution shape ([EXEC-SHAPE] tagged)

- `[EXEC-SHAPE]` Walking skeleton on `audit-size` with the bundled line counter, so the end-to-end
  probe needs no external tool.
- `[EXEC-SHAPE]` Wave B parallel workers for Phases 3, 5, 6, 7 with the fences above; Phase 4
  follows Phase 3.
- `[EXEC-SHAPE]` Shared code at `plugins/code-metrics/scripts/`, fixtures at
  `plugins/code-metrics/scripts/fixtures/`, collector stamp fragments at
  `reference/collectors/<skill>.md` merged in Phase 8.
- `[EXEC-SHAPE]` Plugin version `0.1.0`; `MIN_PYTHON = (3, 9)`; stdlib-only Python.
- `[EXEC-SHAPE]` Size default `1000` labelled as the plugin's own number, `500` documented as
  selectable, `iso-8.2.115` mode selectable (design T10).
- `[EXEC-SHAPE]` Sanity-check criteria per phase as written above.

### Mechanical work

- One commit per phase at minimum, conventional-commit subject scoped `code-metrics` (or the
  sibling plugin's name in Phase 10), each commit carrying its suites; push after every phase so a
  peer or a resumed session sees the state.
- Every phase ends with `scripts/affected-tests.sh --run` on the phase diff and the phase's
  Sanity Check commands; a red check blocks the commit.
- Phase status tags advance in this file in the same commit as the phase's source changes.
- `DEVIATIONS.md` beside this file records any deviation from a named test boundary or fence.

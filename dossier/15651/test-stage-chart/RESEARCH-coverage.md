---
topic: test-stage-chart
section: coverage
abstract: 'R1 (HIGH (single source)): "/testing:plan maps changed files to unit, integration, architecture, E2E, analyzer, property and characterization or differential tests, and names no fuzz, contract, load, chaos or production-stage technique"'
claims:
  - claim: "/testing:plan maps changed files to unit, integration, architecture, E2E, analyzer, property and characterization or differential tests, and names no fuzz, contract, load, chaos or production-stage technique"
    id: R1
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software/claude-code-plugins"
    single_source: "The claim is about the text of one skill file in this repository; the repository is the only publisher of its own skill files."
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/blob/ca041f276d894076c098e63c855213b5722e8cfe/plugins/testing/skills/plan/SKILL.md"
        tier: 0
        pool: "melodic-software/claude-code-plugins"
        measures: "plugins/testing/skills/plan/SKILL.md read end to end this run at commit ca041f2; its classification table (lines 54-66) and plan template (lines 74-102)"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "The file was read in full; its table and template are the whole of its test-type vocabulary."
    qualifiers:
      - "As of commit ca041f2 on main."
  - claim: "The verification plugin ships confirm, measure and setup skills; none of them carries a technique catalog, and the confirm refactor context requires a differential run for a Replace"
    id: R2
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software/claude-code-plugins"
    single_source: "The claim is about this repository's own skill files; the repository is the only publisher of them."
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/tree/ca041f276d894076c098e63c855213b5722e8cfe/plugins/verification/skills"
        tier: 0
        pool: "melodic-software/claude-code-plugins"
        measures: "skill directory listing of plugins/verification/skills, the description lines of its three SKILL.md files, and a grep of the plugin skills for technique names, which hit confirm/context/refactor.md lines 25-27 and 102 (differential run) and measure/context/performance.md lines 18-19 (load test as a metric source)"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "The listing gives the skill set; the descriptions and the grep show no catalog of techniques and show the differential-run rule."
    qualifiers:
      - "Bodies of confirm and measure were read through grep hits and descriptions, not end to end."
  - claim: "In the testing, verification, app-control, bugs:scan and review:security-review skill files and the autonomy routines reference, fuzzing appears as the gui-crash-fuzzing row marked not-a-routine and as the testing:audit Go adapter that recognizes FuzzXxx functions as tests to audit, and contract tests appear in testing:test-value as a source of expected values"
    id: R3
    confidence: HIGH (single source)
    claim_kind: content
    source_owner: "melodic-software/claude-code-plugins"
    single_source: "The claim is about the text of this repository's own files; the repository is the only publisher of them."
    tiers: [0]
    applies_to: "version-independent"
    sources:
      - url: "https://github.com/melodic-software/claude-code-plugins/blob/ca041f276d894076c098e63c855213b5722e8cfe/plugins/autonomy/reference/routines.md"
        tier: 0
        pool: "melodic-software/claude-code-plugins"
        measures: "case-insensitive grep for fuzz, contract test, chaos, load test, soak, feature flag, threat model, penetration, tap compare and differential over the named skill directories and plugins/autonomy/reference, at commit ca041f2; hits at routines.md:237 (gui-crash-fuzzing, not-a-routine) and testing/skills/test-value/SKILL.md:73,79 (contract test); a second grep for fuzz over every file of plugins/testing, plugins/verification and the other named skills adds testing/skills/audit/adapters/go-testing.yaml:1,10 (TestXxx and FuzzXxx recognized as test functions), its eval fixture, and a CHANGELOG line"
        role: primary
        published: 2026-11-12
        dated_by: source-commit
        applies_to: "version-independent"
        standing: current
    inference: "The grep output lists every hit in the searched scope; the routines row and the Go adapter are the fuzzing hits other than fixtures and changelog text, and test-value is the contract-test hit."
    qualifiers:
      - "Scope is the named directories; other plugins were checked only through a SKILL.md-wide grep whose hits were not each opened."
produced_by: phase-1
---

# Coverage

## Evidence this table rests on

R1 (HIGH (single source)): "/testing:plan maps changed files to unit, integration, architecture, E2E, analyzer, property and characterization or differential tests, and names no fuzz, contract, load, chaos or production-stage technique"

R2 (HIGH (single source)): "The verification plugin ships confirm, measure and setup skills; none of them carries a technique catalog, and the confirm refactor context requires a differential run for a Replace"

R3 (HIGH (single source)): "In the testing, verification, app-control, bugs:scan and review:security-review skill files and the autonomy routines reference, fuzzing appears as the gui-crash-fuzzing row marked not-a-routine and as the testing:audit Go adapter that recognizes FuzzXxx functions as tests to audit, and contract tests appear in testing:test-value as a source of expected values"

## Per-technique table

Applies: **repo** means a consumer repository can carry the technique as code, config or a run
against a locally started build; **ops** means it needs a running production service the consumer
operates, the scope the 2018 post set for its production phases (origin sidecar). Covering skill
names come from this repository's `plugins/` tree (skill listing read this run; descriptions from
the installed listing unless the Basis column says read or grep). Current practice is a one-line
pointer; rows without a fetched source say judgment.

| # | Stage | Technique | Applies | Covering skill | Coverage | Current practice (Basis) |
|---|---|---|---|---|---|---|
| 1 | Pre | unit tests | repo | `testing:write`, `testing:plan` | yes | xUnit-family tests in CI (judgment) |
| 2 | Pre | functional tests | repo | `testing:write` | yes | behavior tests at the public API (judgment) |
| 3 | Pre | component tests | repo | `testing:write` | yes | one component with doubles at its edges (judgment) |
| 4 | Pre | fuzz tests | repo | `testing:audit` audits Go fuzz tests it finds; no skill plans or writes one | partial | coverage-guided fuzzing in the toolchain (lens sidecar, a Gap) |
| 5 | Pre | property based tests | repo | `testing:plan` row, `testing:write` | yes | generators plus invariants (testing:plan read) |
| 6 | Pre | formal verification | repo | none | gap | TLA+ or Lean model checked separately (judgment; parked by owner) |
| 7 | Pre | static analysis | repo | `toolchain:lint`, `code-metrics:*` | yes | analyzers in CI (judgment) |
| 8 | Pre | mutation tests | repo | `mutation-testing:audit` | yes | Stryker, mutmut on the diff (judgment) |
| 9 | Pre | coverage tests | repo | `code-metrics:audit-coverage` | yes | coverage artifacts read, not gated (judgment) |
| 10 | Pre | benchmark tests | repo | `verification:measure`, `performance:snapshot` | yes | baseline then compare (verification grep) |
| 11 | Pre | contract tests | repo | `testing:test-value` mentions only | partial | consumer-driven contracts (lens sidecar, a Gap) |
| 12 | Pre | lint tests | repo | `toolchain:lint`, `toolchain:ratchet` | yes | linters plus count ratchet (judgment) |
| 13 | Pre | acceptance tests | repo | `verification:confirm` | yes | outcome check against intent (judgment) |
| 14 | Pre | regression tests | repo | `debugging:debug`, `testing:write` | yes | a failing test per fixed bug (judgment) |
| 15 | Pre | smoke tests | repo | `testing:run-e2e` | yes | start the build, hit key paths (judgment) |
| 16 | Pre | usability tests | repo (plans) | `user-experience:evaluate`, `plan-user-research` | yes | moderated sessions with a script (judgment) |
| 17 | Pre | UI/UX tests | repo | `testing:check-visual-parity`, `user-interface:audit`, `playwright` | yes | browser automation plus visual diff (judgment) |
| 18 | Pre | penetration tests | ops | none (`review:security-review` reviews code) | gap | a tester attacks a running target (judgment) |
| 19 | Pre | threat modeling | repo | `review:security-review` (review only) | partial | data-flow model per feature (judgment) |
| 20 | Pre | performance tests | repo | `performance:*` | yes | measured counters on a qualified host (judgment) |
| 21 | Deploy | integration tests | repo | `testing:plan` rows, `testing:write` | yes | real dependencies in containers (testing:plan read) |
| 22 | Deploy | tap compare | repo offline, ops live | `verification:confirm` differential run, `testing:write` differential | partial | offline old-versus-new replay (verification grep); live replay needs traffic |
| 23 | Deploy | load tests | ops | none (`verification:measure` names it as a metric source) | gap | k6, Gatling against a deployed build (judgment) |
| 24 | Deploy | shadowing | ops | none | n/a for repo | mesh mirroring (post cites Istio mirroring) |
| 25 | Deploy | config tests | repo | `testing:plan` config/DI row; `harness-config:audit` for Claude Code only | partial | config validated in CI before push (judgment) |
| 26 | Deploy | soak tests | ops | none | n/a for repo | long runs under realistic load (post) |
| 27 | Release | canarying | ops | none | n/a for repo | partial release with automated analysis (judgment) |
| 28 | Release | monitoring | ops | none | n/a for repo | SLO metrics during rollout (judgment) |
| 29 | Release | traffic shaping | ops | none | n/a for repo | load-balancer weights (post) |
| 30 | Release | feature flagging | ops | none (`bugs:scan` lens reads flag code) | n/a for repo | flag service plus stale-flag cleanup (judgment) |
| 31 | Release | exception tracking | ops | none | n/a for repo | error tracker per release (judgment) |
| 32 | Post | teeing | ops | none | n/a for repo | traffic copy to a second cluster (post) |
| 33 | Post | profiling | repo | `debugging:analyze-profile` | yes | captured CPU or heap profiles read offline (judgment) |
| 34 | Post | logs/events | ops | none for consumer apps (`harness-ops:observability` is Claude Code telemetry) | n/a for repo | structured events (judgment) |
| 35 | Post | chaos testing | ops | none | n/a for repo | fault injection in production (judgment) |
| 36 | Post | monitoring | ops | none | n/a for repo | dashboards and alerts (judgment) |
| 37 | Post | A/B tests | ops | none | n/a for repo | experiment platform (judgment) |
| 38 | Post | tracing | repo (local traces) | `debugging:analyze-profile`, `playwright` traces | partial | distributed tracing needs a running system (judgment) |
| 39 | Post | dynamic exploration | repo (local build) | `app-control:drive` | partial | live querying of production telemetry (judgment; post gives no definition) |
| 40 | Post | real user monitoring | ops | none | n/a for repo | browser RUM agent (judgment) |
| 41 | Post | auditing | repo (settings, code) | `github:audit`, `codebase-health:audit` | partial | audit trails of production actions (judgment) |
| 42 | Post | oncall experience | ops | none | n/a for repo | runbooks, paging review (judgment) |

## Counts, re-derived

- Applies: 26 repo (19 pre-production, 3 deploy, 4 post-release), 16 ops.
- Ops rows by reason: 15 are deploy, release or post-release rows that need live traffic, inside
  the scope the 2018 post set for its production phases; 1, penetration tests, is a pre-production
  row marked ops by judgment because it needs a running target, outside that scope statement.
- Covered at least partly: 25 of 42 (18 pre-production, 3 deploy, 0 release, 4 post-release);
  fully: 17.
- Repo-applicable rows with no coverage: formal verification. With partial coverage: fuzz (audit
  only), contract, threat modeling, tap compare (live), config (consumer app config), tracing,
  dynamic exploration, auditing.

## Difference from the earlier count

The earlier digest count was 25 of 42, and this run also counts 25, with two rows moved. Fuzz moves
from none to partial, because the `testing:audit` Go adapter audits FuzzXxx tests (the grep behind the third claim in the
header). Logs/events moves from partial to none, because `harness-ops:observability` reads Claude
Code's own telemetry, not a consumer application's logs (skill description in the installed
listing). Every other row matches the earlier table's coverage call. Of the earlier gap list,
formal verification stays a gap and fuzz, contract tests and dynamic exploration are partial.

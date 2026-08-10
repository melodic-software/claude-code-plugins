# Changelog

All notable changes to the `mutation-testing` plugin are documented here. Format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); this plugin uses semantic versioning.

## [0.1.0]

### Added

- **Initial release.** Three skills covering the mutation-testing concern: knowledge, provisioning,
  and a read-only diff-scoped run.
- **`/mutation-testing:principles`** — knowledge router over five source-attributed reference
  spokes: mutant states and operator catalogs, the metric family (mutation score, covered-code
  score, PIT's test strength, Infection's MSI, the oracle gap), the scaling protocol
  (diff-scoping, one mutant per line, arid-node suppression, review-time surfacing), tooling by
  ecosystem plus the manual protocol for languages with none, and the theory (competent programmer
  hypothesis, coupling effect, the equivalent-mutant problem). A quick decision guide answers the
  common questions with no reference load.
- **`/mutation-testing:setup`** — `check` inspects ecosystem detection, tool presence and
  runnability, test-runner support, baseline suite health, known flakiness, the effective config
  across cascade layers, diff-target resolution, suppression-record hygiene, and tracked-not-ignored
  status; `apply` interviews and writes `.claude/mutation-testing.md` plus an empty
  `.claude/mutation-testing-arid.md`. Proposes the tool's install command, never installs unprompted.
- **`/mutation-testing:audit`** — diff-scoped run generating at most one mutant per changed line,
  executing against a test selection cached once per target, with revert guaranteed on every exit
  path. Reports per file ranked by oracle gap.
- **Arid-node suppression adopts the finding-suppression convention in full** —
  `.claude/mutation-testing-arid.md`, kept as a surface separate from the config so a config diff
  reads as a policy change and a suppression diff reads as an accepted finding.
  `audit/context/suppression.md` owns this plugin's read of the contract: the five required keys
  mapped to a mutation finding (`check` as the qualified operator, `claim` as `arid(kind=…)` from a
  closed vocabulary, `sites`, `reason`, `date`), the `finding_id` and anchor derivations — binding
  the convention's `heading_path` to the mutated node's enclosing scope path, since source code has
  no headings — the policy-floor precedence inversion, and the four dispositions. Entries are
  proposed complete and never written unprompted; an equivalent mutant is never suppressed, because
  the convention's record is not for a finding that is simply wrong.

### Notes on deliberate omissions

- **No score-threshold field and no build gate.** A mutation score has a permanent, unknowable
  ceiling below 100% because equivalent mutants cannot all be removed, and every point of score is
  purchasable by suppressing a mutant — so a gate selects for suppression over testing. The
  reasoning, with sources, ships in `principles/reference/scaling-and-suppression.md`.
- **Survivor triage is delegated, mandatorily.** Classifying a survivor as productive, arid, or
  equivalent is the `self-grade` bias class, so it runs in a fresh-context (non-fork) subagent; the
  equivalence call prefers a cross-vendor advisor when one is installed, with the same-vendor
  fresh-context subagent as the stated fallback. Executing a mutant is exempt as a deterministic
  gate — the tests' pass/fail is the verdict.
- **An equivalence verdict must cite a demonstration.** Asserted from inspection alone it is
  reported as *unclassified*, not as equivalent.
- **The oracle gap is defined once**, in `principles/reference/metrics.md`, as
  `mutation score − code coverage`. A large negative gap is the bad direction, so the audit ranks
  **ascending**. The audit does not restate the formula — an inverted second definition would silently
  reverse the ranking of the report's most important column.
- **Restoration is verified against the preflight snapshot, not against a clean tree.** Phase 0
  permits unrelated dirty files, so an unconditional clean-tree probe would report a false restore
  failure on any repo with work in progress — and teach the reader to ignore the one line that must
  never be ignored.
- **No review-time surfacing yet.** Surfacing mutants as review comments is the shape with the
  strongest industrial evidence, but that evidence is conditional on a suppression loop already
  existing — an un-suppressed run is roughly 85% noise at Google's reported starting ratio. Deferred
  until the suppression record carries real entries.
